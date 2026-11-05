// Ticket-Board (Super+m): Tickets aus dem Obsidian-Vault in fuenf Spalten,
// Overlay auf dem fokussierten Monitor. Daten: `ticket.py watch` laeuft dauerhaft
// (eine JSON-Zeile je Aenderung). Jede Aktion ist ein eigener ticket.py-Aufruf
// (set/quick/open, Argumente als Liste), stderr landet in der Fehlerzeile.
// Alle Tasten laufen ueber handle(), auch `quickshell ipc call tickets press NAME`;
// `type TEXT` fuellt das offene Eingabefeld, `info` zeigt den Zustand als JSON.
import QtQuick
import QtQuick.Effects
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
    property string err: ""
    property Item selItem: null      // Karte unter dem Auswahlrahmen
    property var pointer: null       // letzte Mausposition (Szene)

    // gewaehlte Karte, nur wenn sie gerade zu sehen ist
    readonly property var cur: {
        const t = state.tickets.find(x => x.key === key)
        return t && shown(t) && (!tab || t.project === tab) ? t : null
    }
    readonly property var blank: ({ key: "", project: "", num: 0, title: "", status: "backlog", prio: "mittel",
                                    labels: [], archived: false, aliases: [], check: [0, 0], created: "",
                                    mtime: 0, path: "", body: "", bad: "" })

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
        const list = cards(statuses[col])
        key = list.length ? list[Math.min(row, list.length - 1)].key : ""
        if (!key) detail = false
    }
    function moveCol(d) {
        col = Math.max(0, Math.min(4, col + d))
        const list = cards(statuses[col])
        key = list.length ? list[Math.min(row, list.length - 1)].key : ""
    }
    // Status setzen, Spalte folgt; In Arbeit voll -> kein Aufruf
    function shift(t, c) {
        if (c < 0 || c > 4) return
        if (statuses[c] === "in-arbeit" && t.status !== "in-arbeit" && state.wip >= 3) {
            err = "Drei reichen fuer jetzt"
            return
        }
        run(["set", t.key, "status", statuses[c]])
        col = c
    }
    function edit(mode, value) { text = value; editing = mode }
    function submit() {
        const mode = editing, v = text.trim()
        editing = ""
        if (mode === "filter") filter = v.replace(/^#/, "")
        else if (mode === "new") {
            if (v) run(["quick", statuses[col], (tab && !/^[A-Za-z][A-Za-z0-9]*:/.test(v) ? tab + ": " : "") + v],
                       k => tix.key = k)
        } else if (key && (v || mode === "labels")) run(["set", key, mode, v], k => tix.key = k)
    }
    // ein Process je Aufruf; done(stdout) bei Erfolg
    function run(args, done) {
        call.createObject(tix, { command: [ticketPy, ...args.map(String)], done: done || null, running: true })
    }
    function show() {
        output = focused
        detail = false; editing = ""; pointer = null
        fix()
        open = true
    }
    function hide() { open = false; detail = false; editing = "" }
    // Hover waehlt nur bei echter Mausbewegung: Karten, die unter den
    // stillstehenden Zeiger rutschen, nehmen die Auswahl nicht weg
    function hover(p, c, k) {
        const moved = pointer && (pointer.x !== p.x || pointer.y !== p.y)
        pointer = p
        if (moved && !detail && !editing) select(c, k)
    }

    // Einzige Tastenlogik (Tastatur und IPC). true = Taste verbraucht.
    function handle(name) {
        if (!open) return false
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
        case "H": if (t) shift(t, col - 1); break
        case "L": if (t) shift(t, col + 1); break
        case "Return": if (t) detail = true; break
        case "Escape": if (detail) detail = false; else hide(); break
        case "n": edit("new", ""); break
        case "e": if (t) edit("title", t.title); break
        case "t": if (t) edit("labels", t.labels.join(" ")); break
        case "P": if (t) edit("project", t.project); break
        case "p": if (t) run(["set", t.key, "prio", prios[(prios.indexOf(t.prio) + 1) % 3]]); break
        case "a": if (t) run(["set", t.key, "archived", t.archived ? "nein" : "ja"]); break
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
        return true
    }

    onStateChanged: fix()
    onTabChanged: fix()
    onFilterChanged: fix()
    onShowArchiveChanged: fix()
    onErrChanged: if (err) errTimer.restart()
    onEditingChanged: (editing === "filter" ? filterInput : editing ? fieldInput : keys).forceActiveFocus()

    Timer { id: errTimer; interval: 4000; onTriggered: tix.err = "" }

    Component {
        id: call
        Process {
            property var done: null
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onExited: code => {
                if (code !== 0) {
                    const msg = stderr.text.trim().split("\n").pop() || ""
                    tix.err = msg.replace(/^Fehler: /, "") || "ticket.py " + command[1] + ": Exit " + code
                    tix.fix()
                } else if (done) done(stdout.text.trim())
                destroy()
            }
        }
    }

    // Stand aus dem Vault; endet watch, nach 2 s neu starten
    Process {
        id: watcher
        running: true
        command: [tix.ticketPy, "watch"]
        stdout: SplitParser {
            onRead: data => {
                try { tix.state = JSON.parse(data) } catch (e) { tix.err = "watch: " + e }
            }
        }
        onExited: rewatch.restart()
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
        visible: tix.open
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "tickets"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        onVisibleChanged: if (visible) { pop.restart(); keys.forceActiveFocus() }

        // abdunkeln, Klick daneben = schliessen
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(tix.shell.bg, 0.72)
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
            ParallelAnimation {
                id: pop
                NumberAnimation { target: box; property: "scale"; from: 0.92; to: 1; duration: 260; easing.type: Easing.OutBack }
                NumberAnimation { target: box; property: "opacity"; from: 0; to: 1; duration: 180 }
            }
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
                                    [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down" }
                    ev.accepted = tix.handle(named[ev.key] || ev.text)
                }
            }

            // Kopf: λ TICKETS, Projekt-Reiter, Label-Filter, Archiv, ✕
            Item {
                id: head
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24; topMargin: 18 }
                height: 36

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        rightPadding: 18
                        text: "λ  TICKETS"
                        font { family: tix.shell.font; pixelSize: 24; bold: true }
                        color: tix.shell.hud
                    }
                    Repeater {
                        model: ["", ...tix.state.projects]
                        TicketDetail.Chip {
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
                        radius: 3
                        color: active ? tix.shell.fill : filterMouse.containsMouse ? tix.shell.hover : tix.shell.box
                        border.width: 1
                        border.color: tix.editing === "filter" ? tix.shell.hud : active ? Qt.alpha(tix.shell.hud, 0.5) : tix.shell.edge
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
                    TicketDetail.Chip {
                        anchors.verticalCenter: parent.verticalCenter
                        shell: tix.shell
                        readonly property int n: tix.state.tickets.filter(t => t.archived).length
                        label: "◫ ARCHIV" + (n ? "  " + n : "")
                        on: tix.showArchive
                        onHit: tix.showArchive = !tix.showArchive
                    }
                }
                TicketDetail.Chip {
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
                        x: index * (cols.colW + cols.gap)
                        width: cols.colW; height: cols.height

                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: "transparent"
                            border.width: 1
                            border.color: column.here ? Qt.alpha(tix.shell.hud, 0.3) : tix.shell.edge
                            Behavior on border.color { ColorAnimation { duration: 150 } }
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
                            }
                            Text {
                                readonly property bool full: column.status === "in-arbeit" && tix.state.wip >= 3
                                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                text: column.status === "in-arbeit" ? tix.state.wip + "/3" : column.list.length
                                font { family: tix.shell.font; pixelSize: 14; bold: true }
                                color: full ? tix.shell.warn : column.here ? tix.shell.hud : Qt.alpha(tix.shell.hud, 0.6)
                            }
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1
                                color: tix.shell.edge
                            }
                        }

                        // leere Spalte
                        Rectangle {
                            x: 10; y: cols.listTop + (column.withField ? cols.fieldH + 8 : 0)
                            width: parent.width - 20; height: 56
                            visible: !column.list.length
                            radius: 4
                            color: "transparent"
                            border.width: 1
                            border.color: tix.shell.edge
                            Text {
                                anchors.centerIn: parent
                                text: "leer"
                                font { family: tix.shell.font; pixelSize: 12; bold: true }
                                color: Qt.alpha(tix.shell.hud, 0.3)
                            }
                        }

                        ListView {
                            id: cardList
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10; bottomMargin: 10
                                      topMargin: cols.listTop + (column.withField ? cols.fieldH + 8 : 0) }
                            spacing: 8
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: ScriptModel { values: column.list; objectProp: "key" }

                            delegate: TicketCard {
                                id: cardItem
                                required property var modelData
                                required property int index
                                readonly property ListView view: ListView.view
                                width: ListView.view.width
                                shell: tix.shell
                                t: modelData
                                selected: tix.key === modelData.key
                                onSelectedChanged: if (selected) {
                                    tix.selItem = cardItem
                                    view.positionViewAtIndex(index, ListView.Contain)
                                } else if (tix.selItem === cardItem) tix.selItem = null
                                Component.onCompleted: if (selected) tix.selItem = cardItem
                                onClicked: { tix.editing = ""; tix.select(column.index, modelData.key); tix.detail = true }
                                onHovered: p => tix.hover(p, column.index, modelData.key)
                            }
                        }
                    }
                }

                // Auswahlrahmen: gleitet federnd zur gewaehlten Karte, auch ueber Spalten
                Rectangle {
                    readonly property Item card: tix.selItem
                    z: 3
                    x: tix.col * (cols.colW + cols.gap) + 10 - 3
                    y: (card ? card.view.y + card.y - card.view.contentY
                             : cols.listTop + (tix.editModes.includes(tix.editing) && !tix.detail ? cols.fieldH + 8 : 0)) - 3
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

            // Abdunkelung hinter dem Detail-Popup, Klick = Popup zu
            Rectangle {
                anchors.fill: parent
                radius: 4
                visible: dlg.visible
                color: Qt.alpha(tix.shell.bg, 0.7)
                MouseArea { anchors.fill: parent; onClicked: { tix.editing = ""; tix.detail = false } }
            }
            TicketDetail {
                id: dlg
                anchors.centerIn: parent
                width: Math.min(880, parent.width * 0.6); height: Math.min(parent.height * 0.82, implicitHeight)
                visible: tix.detail && !!tix.cur
                shell: tix.shell
                t: tix.cur || tix.blank
                onSetField: (field, value) => {
                    if (field === "status") tix.shift(tix.cur, tix.statuses.indexOf(value))
                    else tix.run(["set", tix.key, field, value])
                }
                onEdit: field => tix.handle(({ title: "e", labels: "t", project: "P" })[field])
                onOpenNote: tix.handle("o")
                onClosed: { tix.editing = ""; tix.detail = false }
            }

            // Eingabefeld fuer neu/Titel/Labels/Projekt: oben in der Spalte, bei offenem
            // Popup ueber dessen Titel
            Rectangle {
                id: field
                visible: tix.editModes.includes(tix.editing)
                x: tix.detail ? dlg.x + 24 : cols.x + tix.col * (cols.colW + cols.gap) + 10
                y: tix.detail ? dlg.y + dlg.titleY - 8 : cols.y + cols.listTop
                width: tix.detail ? dlg.width - 48 : cols.colW - 20
                height: cols.fieldH
                radius: 4
                color: Qt.tint(tix.shell.bg, tix.shell.fill)
                border.width: 1
                border.color: tix.shell.hud
                Text {
                    id: fieldLabel
                    x: 12; anchors.verticalCenter: parent.verticalCenter
                    text: ({ new: "NEU", title: "TITEL", labels: "LABELS", project: "PROJEKT" })[tix.editing] || ""
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
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) ev.accepted = tix.handle("Return")
                        else if (ev.key === Qt.Key_Escape) ev.accepted = tix.handle("Escape")
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !parent.text
                        text: tix.editing === "new" ? (tix.tab ? "" : "PROJ: ") + "Titel #label !hoch"
                              : tix.editing === "labels" ? "mcp docs (leer = keine)" : ""
                        font: parent.font
                        color: Qt.alpha(tix.shell.hud, 0.3)
                    }
                }
            }

            // Fehlerzeile: Aufruf-Fehler, sonst Hinweise aus watch
            Text {
                id: errLine
                anchors { left: parent.left; right: parent.right; bottom: foot.top; leftMargin: 24; rightMargin: 24; bottomMargin: 8 }
                height: 18
                elide: Text.ElideRight
                text: tix.err || tix.state.error ? "⚠ " + (tix.err || tix.state.error) : ""
                font { family: tix.shell.font; pixelSize: 12; bold: true }
                color: tix.err ? tix.shell.warn : Qt.alpha(tix.shell.warn, 0.7)
            }
            Text {
                id: foot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 24; rightMargin: 24; bottomMargin: 16 }
                elide: Text.ElideRight
                text: tix.editing ? "Enter = speichern · Esc = abbrechen" + (({
                          new: " · Format: [PROJ:] Titel #label !hoch|mittel|niedrig, Status = Spalte",
                          labels: " · Labels mit Leerzeichen getrennt, leer = keine",
                          filter: " · leer = Filter aus" })[tix.editing] || "")
                      : "hjkl / Pfeile waehlen · H/L schieben · Enter Details · n neu · e Titel · t Labels · p Prio · P Projekt"
                        + " · a archivieren · A Archiv zeigen · o Obsidian · Tab / 0-9 Projekt · / Filter · Esc zu"
                font { family: tix.shell.font; pixelSize: 11 }
                color: Qt.alpha(tix.shell.hud, 0.45)
            }
        }
    }
}
