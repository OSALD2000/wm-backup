// Ticket-Board (Super+m): Tickets aus dem Obsidian-Vault in fuenf Spalten,
// Overlay auf dem fokussierten Monitor. Daten: `ticket.py watch` laeuft dauerhaft
// (eine JSON-Zeile je Aenderung). Jede Aktion ist ein eigener ticket.py-Aufruf
// (set/quick/open, Argumente als Liste), stderr landet in der Fehlerzeile.
// Alle Tasten laufen ueber handle(), auch `quickshell ipc call tickets press NAME`;
// `type TEXT` fuellt das offene Eingabefeld, `info` zeigt den Zustand als JSON.
// Status, Prio und Archiv aendern den Stand sofort (optimistisch), ticket.py schreibt
// hinterher; scheitert der Aufruf, gilt wieder der letzte watch-Stand.
// Bewegung: ein Zeitgeber `clock` staffelt Oeffnen/Schliessen, eine fliegende Kopie
// (`flyer`) traegt Karten bei H/L und Drag & Drop, Federn wie in shell.qml.
// Endlos laeuft nur `breath` (und der Cursor), beides nur bei offenem Board.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.I3
import Quickshell.Wayland

Scope {
    id: tix
    required property var shell

    readonly property var statuses: ["backlog", "todo", "in-arbeit", "review", "fertig"]
    readonly property var prios: ["hoch", "mittel", "niedrig"]
    readonly property string ticketPy: Quickshell.env("HOME") + "/.config/sway/scripts/ticket.py"
    readonly property var editModes: ["new", "title", "labels", "project"]  // Feld in der Spalte

    property bool open: false
    property string output: ""
    // I3 gleich beim Laden verbinden: sonst ist focusedMonitor beim ersten Oeffnen noch leer
    readonly property string focused: I3.focusedMonitor ? I3.focusedMonitor.name : ""
    property var state: ({ projects: [], tickets: [], wip: 0, error: "" })
    property var watched: ({ projects: [], tickets: [], wip: 0, error: "" })  // letzter watch-Stand
    // gemerkt, solange Quickshell laeuft
    property string tab: ""          // "" = ALLE
    property int col: 0
    property string key: ""
    property int row: 0              // Stelle in der Spalte, falls die Karte verschwindet
    property string filter: ""
    property bool showArchive: false
    // pro Oeffnen
    property bool detail: false
    property string editing: ""      // "" | new | title | labels | project | filter
    property string text: ""         // Inhalt des offenen Eingabefelds
    property string target: ""       // Karte, fuer die e/t/P gestartet wurde
    property string err: ""
    property string armed: ""        // Karte, fuer die Entf einmal gedrueckt wurde (3 s)
    property Item selItem: null      // Karte unter dem Auswahlrahmen
    property var pointer: null       // letzte Mausposition (Szene)
    property var lastCur: blank      // haelt den Popup-Inhalt beim Zuklappen

    // Bewegung
    property real clock: 0           // 0..900 ms seit dem Oeffnen, beim Schliessen rueckwaerts
    property real breath: 0.7        // atmen: λ, Prio hoch, leere Spalte
    property int tabDir: 0           // kurz nach einem Reiterwechsel: Karten gleiten seitlich
    property string prevTab: ""
    // fliegende Kopie: Kennung, Ziel-Status, Start (in `cols`), Fortschritt
    property string flyKey: ""
    property string flyStatus: ""
    property var flyT: blank
    property point flyFrom
    property real flyP: 1
    property real lift0: 0           // Anhebung beim Start (nach dem Ziehen)
    property bool flyMoved: false
    property Item flyTo: null        // Karte, auf der die Kopie landet
    property string dragKey: ""      // gerade gezogene Karte
    property real pick: 0            // 0..1 Anheben beim Ziehen
    property int dropCol: -1
    signal blocked()                 // In Arbeit voll

    // gewaehlte Karte, nur wenn sie gerade zu sehen ist
    readonly property var cur: {
        const t = state.tickets.find(x => x.key === key)
        return t && shown(t) && (!tab || t.project === tab) ? t : null
    }
    readonly property var blank: ({ key: "", project: "", num: 0, title: "", status: "backlog", prio: "mittel",
                                    labels: [], archived: false, aliases: [], check: [0, 0], created: "",
                                    mtime: 0, path: "", body: "", bad: "" })

    // 0..1-Abschnitt der Zeitachse ab `at` (ms), `len` lang
    function stage(at, len) { return Math.max(0, Math.min(1, (clock - at) / len)) }
    function outCubic(x) { return 1 - Math.pow(1 - x, 3) }
    function outBack(x) { const c = 1.70158; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2) }

    // Archiv-Schalter + Label-Filter
    function shown(t) {
        const f = filter.toLowerCase()
        return (showArchive || !t.archived) && (!f || t.labels.some(l => l.toLowerCase() === f))
    }
    function count(p) { return state.tickets.filter(t => shown(t) && (!p || t.project === p)).length }
    // Karten einer Spalte: Prio hoch zuerst, dann Nummer; Fertig nach mtime, neueste oben
    function cards(status) {
        const rank = t => prios.indexOf(t.prio)
        return state.tickets.filter(t => t.status === status && (!tab || t.project === tab) && shown(t))
            .sort((a, b) => status === "fertig" ? b.mtime - a.mtime || b.num - a.num
                            : rank(a) - rank(b) || a.num - b.num || a.project.localeCompare(b.project))
    }
    function select(c, k) {
        col = c; key = k
        row = Math.max(0, cards(statuses[c]).findIndex(t => t.key === k))
    }
    // Nach neuem Stand: dieselbe Kennung (auch ueber Alias nach Projektwechsel) in
    // ihrer Spalte, sonst dieselbe Stelle der aktuellen Spalte
    function fix() {
        const t = key ? state.tickets.find(x => x.key === key) || state.tickets.find(x => x.aliases.includes(key)) : null
        if (t && cards(t.status).some(x => x.key === t.key)) return select(statuses.indexOf(t.status), t.key)
        // gewaehlte Karte ist weg: Popup und Eingabe zu dieser Karte schliessen,
        // sonst zeigen/aendern sie still den Nachbarn
        if (key) {
            detail = false
            if (editing !== "new" && editing !== "filter") editing = ""
        }
        const list = cards(statuses[col])
        key = list.length ? list[Math.min(row, list.length - 1)].key : ""
    }
    function moveCol(d) {
        col = Math.max(0, Math.min(4, col + d))
        const list = cards(statuses[col])
        key = list.length ? list[Math.min(row, list.length - 1)].key : ""
    }

    // Stand sofort aendern (wip wie ticket.py: nicht archiviert)
    function patch(k, fields) {
        const tickets = state.tickets.map(t => t.key === k ? Object.assign({}, t, fields) : t)
        state = Object.assign({}, state, { tickets: tickets,
                                           wip: tickets.filter(t => t.status === "in-arbeit" && !t.archived).length })
    }
    // Status setzen: H/L, Drag & Drop (from = Lage der gezogenen Kopie), Status-Chip.
    // Die Karte fliegt als Kopie hin; In Arbeit voll -> Abprallen, kein Aufruf.
    function moveTo(k, status, from) {
        const t = state.tickets.find(x => x.key === k), c = statuses.indexOf(status)
        if (!t || c < 0) {
            if (from) flyKey = ""
            return
        }
        const d = c - statuses.indexOf(t.status)
        if (!d || status === "in-arbeit" && state.wip >= 3) {
            if (d) { fail("Drei reichen fuer jetzt"); blocked() }
            if (from) fly(t, t.status, from, false, pick)
            else if (d && selItem && selItem.t.key === k) selItem.bump(d > 0 ? 1 : -1)
            return
        }
        const start = from || (flyKey === k ? Qt.point(flyer.x, flyer.y)
                               : selItem && selItem.t.key === k ? selItem.mapToItem(cols, 0, 0) : null)
        if (start) fly(t, status, start, true, from ? pick : 0)
        patch(k, { status: status, mtime: Date.now() / 1000 })
        run(["set", k, "status", status])
    }
    function setField(k, field, value) {
        if (field === "status") return moveTo(k, value)
        patch(k, field === "archived" ? { archived: value === "ja" } : { [field]: value })
        run(["set", k, field, value])
    }
    // Kopie von `from` zur Karte k in Spalte `status` (die Karte meldet sich als flyTo)
    function fly(t, status, from, moved, lift) {
        flyKey = ""; flyTo = null   // `landing` der Zielkarte schaltet neu und meldet sie
        flyT = t; flyFrom = from; flyMoved = moved; lift0 = lift
        flyStatus = status; flyKey = t.key
        flyAnim.restart()
    }
    function land() {
        if (flyMoved && flyTo) {
            flyTo.flash()
            if (flyStatus === "fertig") burst.fire(flyer.x + flyer.width / 2, flyer.y + flyer.height / 2)
        }
        flyKey = ""
    }
    // Ziehen: beim Druck liegt der Proxy auf der Karte (MouseArea.drag bewegt ihn),
    // ab der Schwelle hebt die Kopie ab; Loslassen -> DropArea der Spalte unter dem Zeiger
    function grab(card, at) {
        const p = card.mapToItem(cols, 0, 0)
        dragProxy.x = p.x; dragProxy.y = p.y
        dragProxy.Drag.hotSpot = at
    }
    function dragStart(c, t) {
        editing = ""
        select(c, t.key)
        flyAnim.stop()
        flyKey = ""; flyTo = null
        flyT = t; flyStatus = t.status
        dragKey = t.key; flyKey = t.key
        pickAnim.restart()
    }
    function endDrag() {
        if (!dragKey) return
        const k = dragKey, t = state.tickets.find(x => x.key === k)
        dropCol = -1
        dragProxy.Drag.drop()
        dragKey = ""
        moveTo(k, dropCol >= 0 ? statuses[dropCol] : t ? t.status : "", Qt.point(dragProxy.x, dragProxy.y))
    }

    function edit(mode, value) { text = value; target = key; editing = mode }
    function submit() {
        const mode = editing, v = text.trim()
        if (mode !== "filter") fieldFlash.restart()
        editing = ""
        if (mode === "filter") filter = v.replace(/^#/, "")
        else if (mode === "new") {
            if (v) run(["quick", statuses[col], (tab && !/^[A-Za-z][A-Za-z0-9]*:/.test(v) ? tab + ": " : "") + v],
                       k => tix.key = k)
        } else if (target && (v || mode === "labels")) run(["set", target, mode, v], k => tix.key = k)
    }
    // ein Process je Aufruf; done(stdout) bei Erfolg. "--" nach dem Unterbefehl:
    // Freitext wie "-x" ist sonst fuer argparse eine Option
    function run(args, done) {
        call.createObject(tix, { command: [ticketPy, args[0], "--", ...args.slice(1).map(String)],
                                 done: done || null, running: true })
    }
    // Loeschen braucht zwei Anlaeufe auf derselben Karte innerhalb 3 s
    function disarm() {
        if (!armed) return
        armed = ""; delTimer.stop()
        if (err.startsWith("Nochmal Entf")) err = ""
    }
    function arm(k) {
        armed = k; delTimer.restart()
        fail("Nochmal Entf = " + k + " loeschen")
    }
    // Papierkorb: Karte sofort raus (Entfernen-Animation), bei Fehler stellt run() den Stand wieder her
    function remove(k) {
        disarm()
        const tickets = state.tickets.filter(t => t.key !== k)
        state = Object.assign({}, state, { tickets: tickets,
                                           wip: tickets.filter(t => t.status === "in-arbeit" && !t.archived).length })
        detail = false
        run(["delete", k])
    }
    // Fehlerzeile: schuettelt sich, pulsiert rot, blendet nach 4 s aus
    function fail(msg) {
        err = msg
        errFade.stop(); errLine.opacity = 1
        errShake.restart(); errTimer.restart()
    }
    function show() {
        output = focused
        detail = false; editing = ""; pointer = null
        fix()
        open = true
        outroAnim.stop(); introAnim.restart()
        keys.forceActiveFocus()
    }
    // logisch sofort zu; das Fenster bleibt, bis die Staffel rueckwaerts durch ist
    function hide() {
        open = false; detail = false; editing = ""
        if (dragKey) { dragKey = ""; flyKey = "" }
        introAnim.stop(); outroAnim.restart()
    }
    // Hover waehlt nur bei echter Mausbewegung: Karten, die unter den
    // stillstehenden Zeiger rutschen, nehmen die Auswahl nicht weg
    function hover(p, c, k) {
        const moved = pointer && (pointer.x !== p.x || pointer.y !== p.y)
        pointer = p
        if (moved && !detail && !editing && !dragKey) select(c, k)
    }

    // Einzige Tastenlogik (Tastatur und IPC). true = Taste verbraucht.
    function handle(name) {
        if (!open) return false
        if (name !== "Delete") disarm()
        if (editing) {
            if (name === "Return") submit()
            else if (name === "Escape") editing = ""
            else return false
            return true
        }
        const t = cur, list = cards(statuses[col]), i = list.findIndex(x => x.key === key)
        switch (name) {
        case "h": case "Left": moveCol(-1); break
        case "l": case "Right": moveCol(1); break
        case "j": case "Down": if (list.length) select(col, list[Math.min(i + 1, list.length - 1)].key); break
        case "k": case "Up": if (list.length) select(col, list[Math.max(i - 1, 0)].key); break
        case "H": if (t) moveTo(t.key, statuses[col - 1]); break
        case "L": if (t) moveTo(t.key, statuses[col + 1]); break
        case "Return": if (t) detail = true; break
        case "Escape": if (detail) detail = false; else hide(); break
        case "n": detail = false; edit("new", ""); break
        case "e": if (t) edit("title", t.title); break
        case "t": if (t) edit("labels", t.labels.join(" ")); break
        case "P": if (t) edit("project", t.project); break
        case "p": if (t) setField(t.key, "prio", prios[(prios.indexOf(t.prio) + 1) % 3]); break
        case "a": if (t) setField(t.key, "archived", t.archived ? "nein" : "ja"); break
        case "Delete": if (t) { if (armed === t.key) remove(t.key); else arm(t.key) } break
        case "A": showArchive = !showArchive; break
        case "o": if (t) { run(["open", t.key]); hide() } break
        case "/": edit("filter", filter); break
        case "Tab": case "Backtab": {
            const tabs = ["", ...state.projects], d = name === "Tab" ? 1 : tabs.length - 1
            tab = tabs[(tabs.indexOf(tab) + d) % tabs.length]
            break
        }
        default:
            if (!/^[0-9]$/.test(name)) return false
            if (name === "0") tab = ""
            else if (state.projects[name - 1]) tab = state.projects[name - 1]
        }
        if (detail && !cur) detail = false  // z. B. h/l in eine leere Spalte: Popup nie unsichtbar offen
        return true
    }

    onStateChanged: {
        if (tab && !state.projects.includes(tab)) tab = ""  // Projektordner weg: zurueck auf ALLE
        fix()
    }
    onTabChanged: {
        const tabs = ["", ...state.projects]
        tabDir = tabs.indexOf(tab) < tabs.indexOf(prevTab) ? -1 : 1
        prevTab = tab
        tabSlide.restart()
        fix()
    }
    onKeyChanged: disarm()
    onFilterChanged: fix()
    onShowArchiveChanged: fix()
    onCurChanged: if (cur) lastCur = cur
    onEditingChanged: (editing === "filter" ? filterInput : editing ? fieldInput : keys).forceActiveFocus()

    Timer { id: delTimer; interval: 3000; onTriggered: tix.disarm() }
    Timer { id: errTimer; interval: 4000; onTriggered: errFade.restart() }
    Timer { id: tabSlide; interval: 350; onTriggered: tix.tabDir = 0 }
    // Zeitachse bis 900 ms (letzte Karte: 240 + 4*45 + 7*30 + 260); zu: schnell rueckwaerts
    NumberAnimation { id: introAnim; target: tix; property: "clock"; to: 900; duration: 900 }
    NumberAnimation { id: outroAnim; target: tix; property: "clock"; to: 0; duration: 220; easing.type: Easing.OutQuad }
    NumberAnimation { id: flyAnim; target: tix; property: "flyP"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic; onFinished: tix.land() }
    NumberAnimation { id: pickAnim; target: tix; property: "pick"; from: 0; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
    SequentialAnimation on breath {
        running: tix.open
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.55; duration: 1400; easing.type: Easing.InOutSine }
    }

    // Zaehler im Spaltenkopf: die neue Zahl rollt herein (groesser = von unten) und
    // huepft; wobble() = wackeln und blinken (In Arbeit voll)
    component Roll: Item {
        id: roll
        property string value
        property font font
        property color color
        property string shown
        property string old
        property real p: 1
        property int dir: 1
        property real hop: 0
        property real blink: 0
        function wobble() { wobbleAnim.restart() }
        width: now.implicitWidth; height: now.implicitHeight
        clip: true
        scale: 1 + hop
        Component.onCompleted: shown = value
        onValueChanged: {
            dir = parseInt(value) < parseInt(shown) ? -1 : 1
            old = shown; shown = value
            rollAnim.restart()
        }
        Text { id: now; text: roll.shown; y: roll.dir * roll.height * (1 - roll.p); font: roll.font; color: roll.color; opacity: 1 - roll.blink }
        Text { text: roll.old; y: -roll.dir * roll.height * roll.p; visible: roll.p < 1; font: roll.font; color: roll.color }
        ParallelAnimation {
            id: rollAnim
            NumberAnimation { target: roll; property: "p"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
            SequentialAnimation {
                NumberAnimation { target: roll; property: "hop"; to: 0.3; duration: 90; easing.type: Easing.OutQuad }
                NumberAnimation { target: roll; property: "hop"; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 3 }
            }
        }
        ParallelAnimation {
            id: wobbleAnim
            SequentialAnimation {
                NumberAnimation { target: roll; property: "rotation"; to: -16; duration: 50 }
                NumberAnimation { target: roll; property: "rotation"; to: 13; duration: 80 }
                NumberAnimation { target: roll; property: "rotation"; to: -9; duration: 70 }
                NumberAnimation { target: roll; property: "rotation"; to: 5; duration: 60 }
                NumberAnimation { target: roll; property: "rotation"; to: 0; duration: 60 }
            }
            SequentialAnimation {
                loops: 3
                NumberAnimation { target: roll; property: "blink"; to: 0.8; duration: 70 }
                NumberAnimation { target: roll; property: "blink"; to: 0; duration: 90 }
            }
            NumberAnimation { target: roll; property: "hop"; from: 0.4; to: 0; duration: 450; easing.type: Easing.OutBack }
        }
    }
    // Cursor der Eingabefelder: blinkt weich, solange `blinking`
    component Caret: Rectangle {
        property bool blinking: false
        width: 2
        SequentialAnimation on opacity {
            running: blinking
            loops: Animation.Infinite
            PropertyAction { value: 1 }
            PauseAnimation { duration: 450 }
            NumberAnimation { to: 0; duration: 120 }
            PauseAnimation { duration: 300 }
            NumberAnimation { to: 1; duration: 120 }
        }
    }

    Component {
        id: call
        Process {
            property var done: null
            property int code: -1
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onExited: c => code = c
            // endet (nach exited) oder startet nicht (FailedToStart, ohne exited): einmal aufraeumen
            onRunningChanged: if (!running) {
                if (code === 0) {
                    if (done) done(stdout.text.trim())
                } else {
                    const msg = stderr.text.trim().split("\n").pop() || ""
                    tix.state = tix.watched
                    tix.fail(msg.replace(/^Fehler: /, "")
                             || "ticket.py " + command[1] + (code < 0 ? ": Start fehlgeschlagen" : ": Exit " + code))
                    tix.fix()
                }
                destroy()
            }
        }
    }

    // Stand aus dem Vault; endet watch (oder startet nicht), melden und nach 2 s neu
    Process {
        id: watcher
        property string last: ""     // letzte stderr-Zeile
        running: true
        command: [tix.ticketPy, "watch"]
        stdout: SplitParser {
            onRead: data => {
                try { tix.watched = tix.state = JSON.parse(data) } catch (e) { tix.fail("watch: " + e) }
            }
        }
        stderr: SplitParser { onRead: data => watcher.last = data }
        onRunningChanged: if (!running) {
            tix.fail("watch beendet" + (last ? ": " + last.replace(/^Fehler: /, "") : "") + ", Neustart in 2 s")
            last = ""
            rewatch.restart()
        }
    }
    Timer { id: rewatch; interval: 2000; onTriggered: watcher.running = true }

    IpcHandler {
        target: "tickets"
        function toggle(): void { if (tix.open) tix.hide(); else tix.show() }
        function open(): void { tix.show() }
        function close(): void { tix.hide() }
        function press(name: string): void { tix.handle(name) }
        function type(text: string): void { tix.text = text }
        function info(): string {
            return JSON.stringify({ open: tix.open, tab: tix.tab, col: tix.col, key: tix.key,
                                    detail: tix.detail, editing: tix.editing, err: tix.err })
        }
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === tix.output) || Quickshell.screens[0]
        visible: tix.open || tix.clock > 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "tickets"
        WlrLayershell.keyboardFocus: tix.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        onVisibleChanged: if (visible) keys.forceActiveFocus()

        // abdunkeln, Klick daneben = schliessen
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(tix.shell.bg, 0.72)
            opacity: tix.stage(0, 160)
            MouseArea { anchors.fill: parent; onClicked: tix.hide() }
        }

        Rectangle {
            id: box
            // 40 px Rand, oben + 30 fuer die Waybar
            anchors { fill: parent; margins: 40; topMargin: 70 }
            color: tix.shell.bg
            radius: 4
            border.width: 1
            border.color: Qt.alpha(tix.shell.hud, 0.5)
            // ploppt auf (0.92 -> 1)
            scale: 0.92 + 0.08 * tix.outBack(tix.stage(0, 300))
            opacity: tix.stage(0, 180)
            // Klicks im Kasten schliessen nicht; Mausbewegung ausserhalb der Karten merken
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onPositionChanged: m => tix.pointer = mapToItem(null, m.x, m.y)
            }

            Item {
                id: keys
                focus: true
                Keys.onPressed: ev => {
                    const named = { [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Escape]: "Escape",
                                    [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Backtab", [Qt.Key_Left]: "Left",
                                    [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down", [Qt.Key_Delete]: "Delete" }
                    ev.accepted = tix.handle(named[ev.key] || ev.text)
                }
            }

            // Kopf: λ TICKETS, Projekt-Reiter, Label-Filter, Archiv, ✕
            Item {
                id: head
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24; topMargin: 18 }
                height: 36

                Row {
                    id: headRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // λ leuchtet beim Oeffnen auf und atmet danach
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "λ"
                        font { family: tix.shell.font; pixelSize: 24; bold: true }
                        color: tix.shell.hud
                        scale: 1 + 0.4 * (1 - tix.outBack(tix.stage(60, 380)))
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: tix.shell.hud
                            shadowBlur: 0.8
                            shadowOpacity: Math.min(1, 0.2 + 0.55 * tix.breath + 1.2 * (1 - tix.stage(250, 700)))
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 4; rightPadding: 18
                        text: "TICKETS"
                        font { family: tix.shell.font; pixelSize: 24; bold: true }
                        color: tix.shell.hud
                    }
                    Repeater {
                        id: tabRep
                        // ScriptModel: Reiter bleiben dieselben Objekte, neue Zaehler huepfen
                        model: ScriptModel { values: ["", ...tix.state.projects] }
                        Chip {
                            required property string modelData
                            anchors.verticalCenter: parent.verticalCenter
                            shell: tix.shell
                            label: (modelData || "ALLE") + "  " + tix.count(modelData)
                            on: tix.tab === modelData
                            onHit: tix.tab = modelData
                        }
                    }
                    Item { width: 18; height: 1 }

                    // Label-Filter: Klick = eingeben, × = aus
                    Rectangle {
                        id: filterChip
                        readonly property bool active: !!tix.filter || tix.editing === "filter"
                        anchors.verticalCenter: parent.verticalCenter
                        width: filterRow.width + 20; height: 26
                        clip: true
                        radius: 3
                        color: active ? tix.shell.fill : filterMouse.containsMouse ? tix.shell.hover : tix.shell.box
                        border.width: 1
                        border.color: tix.editing === "filter" ? tix.shell.hud : active ? Qt.alpha(tix.shell.hud, 0.5) : tix.shell.edge
                        Behavior on width { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.25 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea {
                            id: filterMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (tix.editing !== "filter") tix.edit("filter", tix.filter)
                        }
                        Row {
                            id: filterRow
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Text {
                                text: "⌕"
                                font { family: tix.shell.font; pixelSize: 13; bold: true }
                                color: filterChip.active ? tix.shell.hud : Qt.alpha(tix.shell.hud, 0.7)
                            }
                            TextInput {
                                id: filterInput
                                visible: tix.editing === "filter"
                                width: Math.max(120, contentWidth + 4)
                                text: tix.text
                                onTextEdited: tix.text = text
                                font { family: tix.shell.font; pixelSize: 12; bold: true }
                                color: tix.shell.hud
                                selectionColor: Qt.alpha(tix.shell.hud, 0.35)
                                selectedTextColor: tix.shell.hud
                                cursorDelegate: Caret { color: tix.shell.hud; blinking: tix.open }
                                Keys.onPressed: ev => {
                                    if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) ev.accepted = tix.handle("Return")
                                    else if (ev.key === Qt.Key_Escape) ev.accepted = tix.handle("Escape")
                                }
                            }
                            Text {
                                visible: tix.editing !== "filter"
                                text: tix.filter ? "#" + tix.filter : "FILTER"
                                font { family: tix.shell.font; pixelSize: 12; bold: true }
                                color: tix.filter ? tix.shell.hud : Qt.alpha(tix.shell.hud, 0.7)
                            }
                            Text {
                                visible: !!tix.filter && tix.editing !== "filter"
                                text: "×"
                                font { family: tix.shell.font; pixelSize: 13; bold: true }
                                color: clearMouse.containsMouse ? tix.shell.warn : tix.shell.hud
                                MouseArea {
                                    id: clearMouse
                                    anchors { fill: parent; margins: -4 }
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: tix.filter = ""
                                }
                            }
                        }
                    }
                    Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        shell: tix.shell
                        readonly property int n: tix.state.tickets.filter(t => t.archived).length
                        label: "◫ ARCHIV" + (n ? "  " + n : "")
                        on: tix.showArchive
                        onHit: tix.showArchive = !tix.showArchive
                    }
                }
                // Reiter-Markierung: gleitet und streckt sich
                Chip.Glide {
                    shell: tix.shell
                    row: headRow
                    to: tabRep.count ? tabRep.itemAt(["", ...tix.state.projects].indexOf(tix.tab)) : null
                }
                Chip {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    shell: tix.shell
                    label: "✕"
                    onHit: tix.hide()
                }
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; top: head.bottom; leftMargin: 24; rightMargin: 24; topMargin: 14 }
                height: 1
                color: tix.shell.edge
            }

            // fuenf Spalten, gleich breit; jede scrollt fuer sich
            Item {
                id: cols
                readonly property int gap: 12
                readonly property real colW: (width - 4 * gap) / 5
                readonly property int listTop: 50   // Oberkante der Kartenliste in der Spalte
                readonly property int fieldH: 40
                anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: errLine.top
                          leftMargin: 24; rightMargin: 24; topMargin: 30; bottomMargin: 12 }

                Repeater {
                    model: 5
                    Item {
                        id: column
                        required property int index
                        readonly property string status: tix.statuses[index]
                        readonly property bool here: tix.col === index
                        readonly property bool withField: here && !tix.detail && tix.editModes.includes(tix.editing)
                        readonly property var list: tix.cards(status)
                        readonly property bool full: status === "in-arbeit" && tix.state.wip >= 3
                        // beim Ziehen: Zielspalte leuchtet (rot, wenn In Arbeit voll)
                        readonly property bool target: drop.containsDrag && tix.flyT.status !== status
                        // Oeffnen: Spalten kommen gestaffelt von unten
                        readonly property real k: tix.outCubic(tix.stage(90 + 45 * index, 260))
                        x: index * (cols.colW + cols.gap)
                        width: cols.colW; height: cols.height
                        opacity: k
                        transform: Translate { y: 34 * (1 - column.k) }

                        DropArea {
                            id: drop
                            anchors.fill: parent
                            onDropped: tix.dropCol = column.index
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: "transparent"
                            border.width: 1
                            border.color: column.here ? Qt.alpha(tix.shell.hud, 0.3) : tix.shell.edge
                            Behavior on border.color { ColorAnimation { duration: 150 } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            opacity: column.target ? 1 : 0
                            visible: opacity > 0
                            color: Qt.alpha(column.full ? tix.shell.warn : tix.shell.hud, 0.05)
                            border.width: 2
                            border.color: column.full ? tix.shell.warn : tix.shell.hud
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            layer.enabled: visible
                            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: column.full ? tix.shell.warn : tix.shell.hud; shadowBlur: 0.8; shadowOpacity: 0.7 }
                        }
                        // Kopf: Name + Anzahl, In Arbeit als n/3; gewaehlte Spalte hell
                        Rectangle {
                            x: 1; y: 1; width: parent.width - 2; height: 40
                            radius: 3
                            color: column.here ? tix.shell.hover : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                text: column.status.toUpperCase().replace("-", " ")
                                font { family: tix.shell.font; pixelSize: 14; bold: true }
                                color: column.here ? tix.shell.hud : Qt.alpha(tix.shell.hud, 0.6)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Roll {
                                id: counter
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                value: column.status === "in-arbeit" ? tix.state.wip + "/3" : String(column.list.length)
                                font { family: tix.shell.font; pixelSize: 14; bold: true }
                                color: column.full ? tix.shell.warn : column.here ? tix.shell.hud : Qt.alpha(tix.shell.hud, 0.6)
                            }
                            Connections {
                                target: tix
                                function onBlocked() { if (column.status === "in-arbeit") counter.wobble() }
                            }
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1
                                color: tix.shell.edge
                            }
                        }

                        // leere Spalte: gestrichelter Rahmen, pulsiert sanft
                        Item {
                            id: emptyBox
                            x: 10; y: cols.listTop + (column.withField ? cols.fieldH + 8 : 0)
                            width: parent.width - 20; height: 56
                            opacity: column.list.length ? 0 : 1
                            visible: opacity > 0
                            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                            Behavior on opacity { NumberAnimation { duration: 250 } }
                            Shape {
                                anchors.fill: parent
                                ShapePath {
                                    strokeColor: Qt.alpha(tix.shell.hud, 0.12 + 0.25 * tix.breath)
                                    strokeWidth: 1
                                    strokeStyle: ShapePath.DashLine
                                    dashPattern: [4, 3]
                                    fillColor: "transparent"
                                    PathRectangle { x: 0.5; y: 0.5; width: emptyBox.width - 1; height: emptyBox.height - 1; radius: 4 }
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "leer"
                                font { family: tix.shell.font; pixelSize: 12; bold: true }
                                color: Qt.alpha(tix.shell.hud, 0.2 + 0.15 * tix.breath)
                            }
                        }

                        ListView {
                            id: cardList
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10; bottomMargin: 10
                                      topMargin: cols.listTop + (column.withField ? cols.fieldH + 8 : 0) }
                            // im Takt mit dem aufklappenden Eingabefeld
                            Behavior on anchors.topMargin { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                            spacing: 8
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: ScriptModel { values: column.list; objectProp: "key" }

                            // neu: ploppt mit Gluehen; Reiterwechsel: gleitet von der Seite herein
                            add: Transition {
                                id: addT
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                                    NumberAnimation { property: "scale"; from: tix.tabDir ? 1 : 0.6; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                    NumberAnimation { property: "slide"; from: tix.tabDir * 70; to: 0; duration: 280; easing.type: Easing.OutCubic }
                                    ScriptAction {
                                        script: {
                                            const c = addT.ViewTransition.item
                                            if (!tix.tabDir && c.t.key !== tix.flyKey) c.flash()
                                        }
                                    }
                                }
                            }
                            // weg: klappt zusammen (Archiv); Reiterwechsel: gleitet zur Seite hinaus
                            remove: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 0; duration: tix.tabDir ? 140 : 220 }
                                    NumberAnimation { property: "fold"; to: tix.tabDir ? 1 : 0; duration: 240; easing.type: Easing.InBack }
                                    NumberAnimation { property: "slide"; to: -tix.tabDir * 70; duration: 220; easing.type: Easing.InCubic }
                                }
                            }
                            // Luecke schliesst sich federnd, Platz rueckt auf
                            displaced: Transition {
                                NumberAnimation { properties: "x,y"; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                                NumberAnimation { properties: "opacity,scale,fold"; to: 1; duration: 200 }
                                NumberAnimation { property: "slide"; to: 0; duration: 200 }
                            }
                            move: displaced

                            delegate: TicketCard {
                                id: cardItem
                                required property var modelData
                                required property int index
                                readonly property ListView view: ListView.view
                                // Ziel der fliegenden Kopie
                                readonly property bool landing: tix.flyKey === modelData.key && tix.flyStatus === column.status
                                function reveal() { view.positionViewAtIndex(index, ListView.Contain) }
                                width: ListView.view.width
                                shell: tix.shell
                                t: modelData
                                breath: tix.breath
                                selected: tix.key === modelData.key
                                // fliegt/gezogen: die Kopie zeigt die Karte, hier bleibt Platz
                                face: tix.flyKey !== modelData.key ? 1 : tix.dragKey ? 0.3 : 0
                                intro: tix.outCubic(tix.stage(240 + 45 * column.index + 30 * Math.min(index, 7), 260))
                                dragTarget: dragProxy
                                onSelectedChanged: if (selected) {
                                    tix.selItem = cardItem
                                    reveal()
                                } else if (tix.selItem === cardItem) tix.selItem = null
                                onLandingChanged: if (landing) { tix.flyTo = cardItem; Qt.callLater(reveal) }
                                Component.onCompleted: {
                                    if (selected) tix.selItem = cardItem
                                    if (landing) { tix.flyTo = cardItem; Qt.callLater(reveal) }
                                }
                                // Karte verschwindet mitten im Ziehen (neuer Stand): wie Loslassen
                                Component.onDestruction: if (tix.dragKey && tix.dragKey === t.key) tix.endDrag()
                                onClicked: { tix.editing = ""; tix.select(column.index, modelData.key); tix.detail = true }
                                onHovered: p => tix.hover(p, column.index, modelData.key)
                                onPressed: at => tix.grab(cardItem, at)
                                onDragStarted: tix.dragStart(column.index, modelData)
                                onReleased: tix.endDrag()
                            }
                        }
                    }
                }

                // Auswahlrahmen: gleitet federnd zur gewaehlten Karte, auch ueber Spalten.
                // Nur im Kartenbereich (unter den Spaltenkoepfen) zu sehen.
                Item {
                    x: -20; y: 42
                    width: cols.width + 40; height: cols.height - 42 + 6
                    clip: true
                    z: 3
                    opacity: tix.stage(450, 250)
                    Rectangle {
                        readonly property Item card: tix.selItem
                        x: 20 + tix.col * (cols.colW + cols.gap) + 10 - 3
                        y: (card ? card.view.y + card.y - card.view.contentY
                                 : cols.listTop + (tix.editModes.includes(tix.editing) && !tix.detail ? cols.fieldH + 8 : 0)) - 3 - 42
                        width: cols.colW - 20 + 6
                        height: (card ? card.height : 56) + 6
                        radius: 6
                        color: "transparent"
                        border.width: 2
                        border.color: tix.shell.hud
                        opacity: card ? 1 : 0.35
                        Behavior on x { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.25 } }
                        Behavior on y { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.25 } }
                        Behavior on height { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.25 } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: tix.shell.hud; shadowBlur: 0.7; shadowOpacity: 0.6 }
                    }
                }

                // Ziehen: MouseArea.drag bewegt diesen Proxy, Drag meldet ihn den DropAreas
                Item {
                    id: dragProxy
                    width: cols.colW - 20; height: 40
                    Drag.active: tix.dragKey !== ""
                }
                // fliegende Kopie: folgt beim Ziehen dem Proxy, fliegt sonst im Bogen von
                // flyFrom zur Zielkarte (deren Lage live, sie kann noch rutschen)
                TicketCard {
                    id: flyer
                    readonly property real toX: tix.statuses.indexOf(tix.flyStatus) * (cols.colW + cols.gap) + 10
                    readonly property real toY: tix.flyTo ? tix.flyTo.view.y + tix.flyTo.y - tix.flyTo.view.contentY : tix.flyFrom.y
                    z: 5
                    visible: tix.flyKey !== ""
                    enabled: false   // nur Anzeige, Maus geht an die Karten darunter
                    width: cols.colW - 20
                    shell: tix.shell
                    t: tix.flyT
                    breath: tix.breath
                    selected: true
                    x: tix.dragKey ? dragProxy.x : tix.flyFrom.x + (toX - tix.flyFrom.x) * tix.flyP
                    y: tix.dragKey ? dragProxy.y : tix.flyFrom.y + (toY - tix.flyFrom.y) * tix.flyP - 26 * Math.sin(Math.PI * tix.flyP)
                    lift: tix.dragKey ? tix.pick : Math.max(tix.lift0 * (1 - tix.flyP), 0.8 * Math.sin(Math.PI * tix.flyP))
                    tilt: tix.dragKey || toX >= tix.flyFrom.x ? 2.5 : -2.5
                }
                // Fertig: Funken spruehen, ein Haken zeichnet sich
                Item {
                    id: burst
                    property real p: 1
                    function fire(cx, cy) { x = cx - width / 2; y = cy - height / 2; burstAnim.restart() }
                    z: 6
                    width: 140; height: 140
                    visible: p < 1
                    layer.enabled: visible
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: tix.shell.hud; shadowBlur: 0.6; shadowOpacity: 0.9 }
                    NumberAnimation { id: burstAnim; target: burst; property: "p"; from: 0; to: 1; duration: 800 }
                    Repeater {
                        model: 8
                        Rectangle {
                            required property int index
                            readonly property real a: (index * 45 + 22.5) * Math.PI / 180
                            readonly property real d: 16 + 48 * tix.outCubic(Math.min(1, burst.p / 0.7))
                            width: 3; height: 4 + 10 * (1 - burst.p)
                            radius: 1.5
                            color: tix.shell.hud
                            x: burst.width / 2 + Math.cos(a) * d - width / 2
                            y: burst.height / 2 + Math.sin(a) * d - height / 2
                            rotation: index * 45 + 22.5 + 90
                            opacity: 1 - burst.p
                        }
                    }
                    Shape {
                        id: tick
                        // Haken: erst der kurze Strich (A->B), dann der lange (B->C)
                        readonly property real d: Math.min(1, burst.p / 0.45)
                        readonly property real d1: Math.min(1, d / 0.35)
                        readonly property real d2: Math.max(0, (d - 0.35) / 0.65)
                        anchors.centerIn: parent
                        width: 34; height: 28
                        scale: 0.7 + 0.3 * tix.outBack(Math.min(1, burst.p / 0.3))
                        opacity: burst.p < 0.7 ? 1 : (1 - burst.p) / 0.3
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: tix.shell.hud
                            strokeWidth: 4
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            startX: 3; startY: 15
                            PathLine { x: 3 + 9 * tick.d1; y: 15 + 10 * tick.d1 }
                            PathLine { x: 12 + 19 * tick.d2; y: 25 - 22 * tick.d2 }
                        }
                    }
                }
            }

            // Abdunkelung hinter dem Detail-Popup, Klick = Popup zu
            Rectangle {
                anchors.fill: parent
                radius: 4
                visible: dlg.visible
                opacity: Math.min(1, dlg.g)
                color: Qt.alpha(tix.shell.bg, 0.7)
                MouseArea { anchors.fill: parent; onClicked: { tix.editing = ""; tix.detail = false } }
            }
            // Detail-Popup: waechst federnd aus der Karte in die Mitte, schrumpft zurueck
            TicketDetail {
                id: dlg
                readonly property bool want: tix.detail && !!tix.cur
                property real g: 0
                property rect src: Qt.rect(0, 0, 1, 1)   // Lage der Karte (in `box`)
                anchors.centerIn: parent
                width: Math.min(880, parent.width * 0.6); height: Math.min(parent.height * 0.82, implicitHeight)
                visible: want || g > 0.01
                opacity: Math.min(1, 2 * g)
                transform: [
                    Scale {
                        xScale: dlg.src.width / dlg.width + (1 - dlg.src.width / dlg.width) * dlg.g
                        yScale: dlg.src.height / dlg.height + (1 - dlg.src.height / dlg.height) * dlg.g
                    },
                    Translate { x: (dlg.src.x - dlg.x) * (1 - dlg.g); y: (dlg.src.y - dlg.y) * (1 - dlg.g) }
                ]
                onWantChanged: {
                    const c = tix.selItem
                    src = c ? c.mapToItem(box, 0, 0, c.width, c.height)
                            : Qt.rect(box.width / 2 - 120, box.height / 2 - 50, 240, 100)
                    if (want) { shrink.stop(); grow.restart() } else { grow.stop(); shrink.restart() }
                }
                NumberAnimation { id: grow; target: dlg; property: "g"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                NumberAnimation { id: shrink; target: dlg; property: "g"; to: 0; duration: 220; easing.type: Easing.OutCubic }
                shell: tix.shell
                t: tix.cur || tix.lastCur
                onSetField: (field, value) => tix.setField(tix.key, field, value)
                onEdit: field => tix.handle(({ title: "e", labels: "t", project: "P" })[field])
                onOpenNote: tix.handle("o")
                armed: tix.armed === t.key
                onRemove: tix.handle("Delete")
                onClosed: { tix.editing = ""; tix.detail = false }
            }

            // Eingabefeld fuer neu/Titel/Labels/Projekt: oben in der Spalte, bei offenem
            // Popup ueber dessen Titel. Klappt federnd auf, Enter blitzt, klappt zu.
            Rectangle {
                id: field
                readonly property bool want: tix.editModes.includes(tix.editing)
                property string mode: ""   // haelt die Beschriftung beim Zuklappen
                property real k: 0
                property real flare: 0
                onWantChanged: {
                    if (want) { mode = tix.editing; fold.stop(); unfold.restart() }
                    else { unfold.stop(); fold.restart() }
                }
                NumberAnimation { id: unfold; target: field; property: "k"; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                NumberAnimation { id: fold; target: field; property: "k"; to: 0; duration: 170; easing.type: Easing.InQuad }
                NumberAnimation { id: fieldFlash; target: field; property: "flare"; from: 1; to: 0; duration: 380; easing.type: Easing.OutCubic }
                visible: want || k > 0.01
                transform: Scale { yScale: Math.max(0, field.k) }
                opacity: Math.min(1, k * 2)
                x: tix.detail ? dlg.x + 24 : cols.x + tix.col * (cols.colW + cols.gap) + 10
                y: tix.detail ? dlg.y + dlg.titleY - 8 : cols.y + cols.listTop
                width: tix.detail ? dlg.width - 48 : cols.colW - 20
                height: cols.fieldH
                radius: 4
                color: Qt.tint(Qt.tint(tix.shell.bg, tix.shell.fill), Qt.alpha(tix.shell.hud, 0.4 * flare))
                border.width: 1 + flare
                border.color: tix.shell.hud
                layer.enabled: flare > 0.01
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: tix.shell.hud; shadowBlur: 0.7; shadowOpacity: field.flare }
                Text {
                    id: fieldLabel
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    text: ({ new: "NEU", title: "TITEL", labels: "LABELS", project: "PROJEKT" })[field.mode] || ""
                    font { family: tix.shell.font; pixelSize: 10; bold: true }
                    color: Qt.alpha(tix.shell.hud, 0.55)
                }
                TextInput {
                    id: fieldInput
                    anchors { left: fieldLabel.right; right: parent.right; leftMargin: 10; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    clip: true
                    text: tix.text
                    onTextEdited: tix.text = text
                    font { family: tix.shell.font; pixelSize: 14; bold: true }
                    color: tix.shell.hud
                    selectionColor: Qt.alpha(tix.shell.hud, 0.35)
                    selectedTextColor: tix.shell.hud
                    cursorDelegate: Caret { color: tix.shell.hud; blinking: tix.open }
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) ev.accepted = tix.handle("Return")
                        else if (ev.key === Qt.Key_Escape) ev.accepted = tix.handle("Escape")
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !parent.text
                        text: field.mode === "new" ? (tix.tab ? "" : "PROJ: ") + "Titel #label !hoch"
                              : field.mode === "labels" ? "mcp docs (leer = keine)" : ""
                        font: parent.font
                        color: Qt.alpha(tix.shell.hud, 0.3)
                    }
                }
            }

            // Fehlerzeile: Aufruf-Fehler, sonst Hinweise aus watch
            Text {
                id: errLine
                property real shake: 0
                property real pulse: 0
                anchors { left: parent.left; right: parent.right; bottom: foot.top; leftMargin: 24; rightMargin: 24; bottomMargin: 8 }
                height: 18
                elide: Text.ElideRight
                text: tix.err || tix.state.error ? "⚠ " + (tix.err || tix.state.error) : ""
                font { family: tix.shell.font; pixelSize: 12; bold: true }
                color: tix.err ? tix.shell.warn : Qt.alpha(tix.shell.warn, 0.7)
                transform: Translate { x: errLine.shake }
                layer.enabled: pulse > 0.01
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: tix.shell.warn; shadowBlur: 0.7; shadowOpacity: errLine.pulse }
                ParallelAnimation {
                    id: errShake
                    SequentialAnimation {
                        NumberAnimation { target: errLine; property: "shake"; to: 10; duration: 45 }
                        NumberAnimation { target: errLine; property: "shake"; to: -8; duration: 70 }
                        NumberAnimation { target: errLine; property: "shake"; to: 6; duration: 60 }
                        NumberAnimation { target: errLine; property: "shake"; to: -3; duration: 50 }
                        NumberAnimation { target: errLine; property: "shake"; to: 0; duration: 50 }
                    }
                    SequentialAnimation {
                        NumberAnimation { target: errLine; property: "pulse"; to: 1; duration: 60 }
                        NumberAnimation { target: errLine; property: "pulse"; to: 0.25; duration: 260 }
                        NumberAnimation { target: errLine; property: "pulse"; to: 0.9; duration: 140 }
                        NumberAnimation { target: errLine; property: "pulse"; to: 0; duration: 600; easing.type: Easing.OutQuad }
                    }
                }
                // nur der Aufruf-Fehler blendet aus; Hinweise aus watch bleiben stehen
                SequentialAnimation {
                    id: errFade
                    NumberAnimation { target: errLine; property: "opacity"; to: 0; duration: 400 }
                    ScriptAction { script: tix.err = "" }
                    NumberAnimation { target: errLine; property: "opacity"; to: 1; duration: 150 }
                }
            }
            Text {
                id: foot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 24; rightMargin: 24; bottomMargin: 16 }
                elide: Text.ElideRight
                text: tix.editing ? "Enter = speichern · Esc = abbrechen" + (({
                          new: " · Format: [PROJ:] Titel #label !hoch|mittel|niedrig, Status = Spalte",
                          labels: " · Labels mit Leerzeichen getrennt, leer = keine",
                          filter: " · leer = Filter aus" })[tix.editing] || "")
                      : "hjkl / Pfeile waehlen · H/L oder Ziehen schieben · Enter Details · n neu · e Titel · t Labels · p Prio · P Projekt"
                        + " · a archivieren · Entf loeschen · A Archiv zeigen · o Obsidian · Tab / 0-9 Projekt · / Filter · Esc zu"
                font { family: tix.shell.font; pixelSize: 11 }
                color: Qt.alpha(tix.shell.hud, 0.45)
            }
        }
    }
}
