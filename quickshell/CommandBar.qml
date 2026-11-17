// Befehlsleiste (ersetzt Fensterliste links und Navigator-Overlay): je Bildschirm
// eine Leiste direkt unter der waybar, volle Breite, immer sichtbar.
// Links die Tabs = Fenster des sichtbaren Workspaces ("wins" aus sidebar.json)
// mit Code (nav.js), Klick fokussiert, Mittelklick schliesst, Mausrad sortiert
// (sidebar.py nudge), Hover = voller Titel. Rechts die Kommandozeile.
// Ebene "bottom" + exclusiveZone: sway setzt die waybar (top) zuerst, die Leiste
// landet darunter. Tastatur bekommt eine Leiste auf "bottom" unter sway nicht,
// deshalb oeffnet Super+f (`quickshell ipc call bar toggle`) ein Overlay mit
// exklusivem Fokus, das genau ueber dem Eingabefeld liegt, samt Liste darunter.
// Eingabe = nav.js: Codes wie `a s s`, `f `, `d`, `m a f` (mit Enter), Befehle
// `#wort arg …` mit Enter aus commands/commands.json (Tab ergaenzt den Namen):
//   {"name": {"help": "...", "exec": ["skript", ...]}}  exec[0] = Datei in
//     commands/, "~/…" oder absoluter Pfad; Woerter nach #name als Argumente
//     (nie durch eine Shell). Umgebung BAR_CONTEXT = JSON des eingefrorenen
//     Stands (context()). stdout = {"notify": "Text"} oder Klartext (erste
//     Zeile), Exit != 0 = Fehler (letzte stderr-Zeile) -> Meldung in der Leiste.
//   {"name": {"help": "...", "builtin": "tree"}}  kann nur die Leiste (#all).
// Daten beim Oeffnen eingefroren ("grid"): Codes bleiben stabil.
// Laeuft in einem Fenster eine Claude-/Codex-Session (agents.json von
// eww/scripts/agents.py, Feld "con" = sway-Fenster), zeigen Tabs, Liste und
// Baum statt "Alacritty" Zeichen, Werkzeug, Session-Titel und Status (look()).
// "#all text" = Baum nur mit passenden Fenstern, Enter = erster Treffer.
// `quickshell ipc call bar toggle|open|close|type TEXT|press NAME|info`.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.I3
import Quickshell.Wayland
import "nav.js" as Nav

Scope {
    id: cb
    required property var shell

    readonly property int barH: 30
    readonly property int waybarH: 30        // = "height" in waybar/config.jsonc
    readonly property int inputW: 340
    readonly property string dir: Quickshell.env("HOME") + "/.config/quickshell/commands"
    property var cmds: ({})

    property bool open: false
    property bool tree: false                // #all offen
    property string output: ""
    property string typed: ""
    property var tabHits: []                 // Tab blaettert gerade durch diese Befehle
    property int tabIdx: -1
    property var snap: []                    // "grid" beim Oeffnen
    property int con: 0                      // aktives Fenster beim Oeffnen (fuer m)
    property var msg: ({ text: "", warn: false, output: "" })
    property string treeFilter: ""           // "#all text": Suchtext, klein geschrieben
    property var agents: ({})                // sway-Fenster -> Session aus agents.json
    readonly property var tools: ({ claude: { glyph: "✳", name: "Claude" }, codex: { glyph: "◎", name: "Codex" } })

    FileView {
        path: cb.dir + "/commands.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { cb.cmds = JSON.parse(text()) } catch (e) { cb.say("commands.json: " + e, true) } }
    }
    // laufende Agenten-Sessions; agents.py schreibt atomar, kaputtes JSON = alter Stand bleibt
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/agents.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const m = {}
                for (const g of JSON.parse(text()).live || [])
                    for (const it of g.items || []) if (it.con) m[it.con] = it
                cb.agents = m
            } catch (e) {}
        }
    }

    readonly property var rows: {
        const out = []
        for (let i = 0; i < snap.length; i += 10) out.push(snap.slice(i, i + 10))
        return out
    }
    readonly property string here: (snap.find(c => c.output === output) || {}).letter || "d"
    readonly property var ctx: ({
        screens: rows.map(r => r[0].letter).join(""),
        here: here,
        wins: (s, w) => (cell(s, w) || {}).wins || []
    })
    readonly property var r: Nav.decode(typed, ctx)
    readonly property string target: r.screen || here
    readonly property bool local: r.cmd === null && !r.screen && !r.ws   // Tabs der Leiste gemeint
    readonly property var list: ctx.wins(target, r.ws)

    function cell(s, w) { return snap.find(c => c.letter === s && (w ? c.number === w : c.visible)) }
    function visibleNr(s) { return (cell(s, 0) || {}).number || 0 }
    function hit(c) { return r.code !== "" && c.indexOf(r.code) === 0 }
    // Anzeige eines Fensters: mit Agenten-Session Zeichen + Werkzeug + Session-Titel
    // + Status (⚙ arbeitet, ✓ bereit), sonst App-Name + Fenstertitel
    function look(w) {
        const a = agents[w.id], tl = a && tools[a.tool]
        return tl ? { glyph: tl.glyph, name: tl.name, title: a.name || w.title, mark: a.status === "busy" ? "⚙" : "✓", agent: a }
                  : { glyph: "", name: w.name, title: w.title, mark: "", agent: null }
    }
    // Suchtext fuer "#all text": App, Titel, Werkzeug, Session, Verzeichnis, Bereich
    function matches(w, c) {
        if (!treeFilter) return true
        const L = look(w), a = L.agent || {}
        return [w.name, w.title, L.name, L.title, a.cwd || "", a.tool || "", c.area, c.letter + (c.number % 10)]
               .join(" ").toLowerCase().indexOf(treeFilter) >= 0
    }

    // Zeilen der Liste unter dem Eingabefeld: {key, label, icons, head, hit, dim, act}
    readonly property var drop: {
        const NAMES = { a: "links", s: "Mitte", d: "Laptop" }
        const winRow = (w, i, s, ws) => {
            const key = tree ? Nav.route(s, ws, i, here, visibleNr(s)) : Nav.code(i)
            // im Baum zaehlt der ganze getippte Befehl, sonst nur der Fenstercode
            const t = tree ? typed : r.code
            const L = look(w)
            return { key: key, label: (L.glyph ? L.glyph + "  " : "") + L.name + "  ·  " + L.title + (L.mark ? "  " + L.mark : ""),
                     icons: L.glyph ? [] : [w.icon],
                     hit: t !== "" && key.indexOf(t) === 0, dim: t !== "" && key.indexOf(t) !== 0, act: { win: w.id } }
        }
        if (r.cmd !== null) {
            const p = Nav.parse(r.cmd)
            const names = tabHits.length ? tabHits : Object.keys(cmds).filter(n => n.indexOf(p.name) === 0).sort()
            return names.map(n => ({ key: "#" + n, label: cmds[n].help || "", hit: n === p.name, act: { cmd: n } }))
        }
        if (tree) {
            // Code bleibt der Platz im Workspace, auch wenn der Filter Fenster ausblendet
            const out = []
            for (const row of rows) {
                const s = row[0].letter, part = []
                for (const c of row) {
                    const hits = c.wins.map((w, i) => matches(w, c) ? winRow(w, i, s, c.number) : null)
                                       .filter(x => x)
                    if (!hits.length) continue
                    part.push({ head: true, key: "  " + Nav.KEYS[c.number - 1],
                                label: (c.visible ? "● " : "") + (c.number % 10) + " " + c.area, act: { go: c } }, ...hits)
                }
                if (part.length) out.push({ head: true, key: s.toUpperCase(), label: NAMES[s] + "  ·  " + row[0].output }, ...part)
            }
            if (!out.length) out.push({ head: true, key: "", label: "keine Treffer fuer \"" + treeFilter + "\"" })
            return out
        }
        if (r.screen || r.ws)
            return list.map((w, i) => winRow(w, i, target, r.ws || visibleNr(target)))
        return []
    }

    function show() {
        output = I3.focusedMonitor ? I3.focusedMonitor.name : ""
        snap = JSON.parse(JSON.stringify(shell.state.grid || []))
        con = 0
        for (const c of snap) for (const w of c.wins || []) if (w.focused) con = w.id
        typed = ""; tree = false; treeFilter = ""
        open = true
        keys.forceActiveFocus()
    }
    function hide() { open = false; tree = false; typed = ""; treeFilter = "" }
    // Stand fuer Befehls-Skripte: Tabs des sichtbaren Workspaces hier (mit Code)
    // und alle Workspaces, wie beim Tippen zu sehen
    function context() {
        return { output: output, here: here, con: con, screens: ctx.screens,
                 tabs: ctx.wins(here, 0).map((w, i) => ({ code: Nav.code(i), id: w.id, name: w.name, title: w.title })),
                 grid: snap.map(c => ({ output: c.output, letter: c.letter, number: c.number, name: c.name,
                                        area: c.area, visible: c.visible, wins: c.wins.map(w => ({ id: w.id, name: w.name })) })) }
    }
    function say(text, warn) { msg = { text: text, warn: !!warn, output: output }; msgTimer.restart() }
    function reject() { shake.restart() }

    function apply(action, c) {
        if (!c || (action === "move" && !con)) return
        Quickshell.execDetached([shell.sidebar, "workspaces", "apply", action, c.output,
                                 String(c.number), String(con)])
    }
    function focusWin(id) {
        if (id) I3.dispatch(`[con_id=${id}] focus`)
        hide()
    }
    function key(ch) {
        if (typed === "" && ch === "m" && !con) return reject()  // nichts zum Verschieben
        if (Nav.decode(typed + ch, ctx).error) return reject()
        typed += ch                                          // ausgefuehrt wird erst mit Enter
    }
    function enter() {
        if (tree && treeFilter && typed === "") {            // Suche: Enter = erster Treffer
            const first = drop.find(x => x.act && x.act.win)
            return first ? focusWin(first.act.win) : reject()
        }
        const e = Nav.enter(r)
        if (e === "win") focusWin((list[r.match] || {}).id)
        else if (e === "go") { apply("go", cell(target, r.ws)); hide() }
        else if (e === "output") { I3.dispatch(`focus output ${JSON.stringify(cell(target, 0).output)}`); hide() }
        else if (e === "move") { apply("move", cell(target, r.ws)); hide() }
        else if (e === "cmd") run(Nav.parse(r.cmd))
        else if (e === "close") hide()
        else reject()
    }
    function run(p) {
        const c = cmds[p.name]
        if (!c) { reject(); return say("unbekannt: #" + p.name, true) }
        if (c.builtin === "tree") { tree = true; treeFilter = p.args.join(" ").toLowerCase(); typed = ""; return }
        if (!c.exec || !c.exec.length) { reject(); return say("#" + p.name + ": weder exec noch builtin", true) }
        const x = c.exec[0], home = Quickshell.env("HOME")
        const bin = x[0] === "/" ? x : x.indexOf("~/") === 0 ? home + x.slice(1) : dir + "/" + x
        call.createObject(cb, { name: p.name, running: true,
                                environment: { BAR_CONTEXT: JSON.stringify(context()) },
                                command: [bin, ...c.exec.slice(1), ...p.args] })
        hide()
    }
    function click(act) {
        if (act.win) focusWin(act.win)
        else if (act.go) { apply(r.move ? "move" : "go", act.go); hide() }
        else if (act.output) { I3.dispatch(`focus output ${JSON.stringify(act.output)}`); hide() }
        else if (act.cmd) { typed = "#" + act.cmd; keys.forceActiveFocus() }
    }
    // Tab / Shift+Tab: Befehlsnamen ergaenzen (nav.js complete), ergaenzt das
    // nichts mehr, durch die Treffer blaettern. Nur solange der Name getippt wird.
    function tab(dir) {
        if (r.cmd === null || /\s/.test(r.cmd)) return
        if (!tabHits.length) {
            const c = Nav.complete(r.cmd, Object.keys(cmds))
            if (!c) return reject()
            if (c.text !== r.cmd) { typed = "#" + c.text; return }
            tabHits = c.hits; tabIdx = dir > 0 ? -1 : 0
        }
        tabIdx = (tabIdx + dir + tabHits.length) % tabHits.length
        typed = "#" + tabHits[tabIdx]
    }
    function handle(name, text) {
        if (!open) return false
        if (name !== "Tab" && name !== "Backtab") { tabHits = []; tabIdx = -1 }
        if (name === "Tab") tab(1)
        else if (name === "Backtab") tab(-1)
        else if (name === "Escape") hide()
        else if (name === "Return") enter()
        else if (name === "Backspace") typed = r.cmd !== null ? typed.slice(0, -1) : Nav.back(typed)
        else if (text && text.length === 1) {
            if (r.cmd !== null) typed += text          // Befehl: Text so, wie getippt
            else key(text.toLowerCase())
        } else return false
        return true
    }

    // ein Process je Befehl; Meldung aus {"notify"} bzw. stderr
    Component {
        id: call
        Process {
            property string name
            property int code: -1
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            onExited: c => code = c
            onRunningChanged: if (!running) {
                if (code === 0) {
                    const text = stdout.text.trim()
                    let out = { notify: text.split("\n")[0] }
                    try { out = JSON.parse(text) } catch (e) {}
                    if (out.notify) cb.say("#" + name + "  " + out.notify, false)
                } else {
                    cb.say("#" + name + "  " + (stderr.text.trim().split("\n").pop()
                           || (code < 0 ? "Start fehlgeschlagen" : "Exit " + code)), true)
                }
                destroy()
            }
        }
    }
    Timer { id: msgTimer; interval: 4000; onTriggered: cb.msg = { text: "", warn: false, output: "" } }

    IpcHandler {
        target: "bar"
        function toggle(): void { if (cb.open) cb.hide(); else cb.show() }
        function open(): void { cb.show() }
        function close(): void { cb.hide() }
        function type(text: string): void { for (const c of text) cb.handle("", c) }
        function press(name: string): void { cb.handle(name, "") }
        function info(): string {
            return JSON.stringify({ open: cb.open, tree: cb.tree, typed: cb.typed, output: cb.output,
                                    con: cb.con, here: cb.here, decode: cb.r, drop: cb.drop.length, msg: cb.msg })
        }
    }

    // ── Leiste je Bildschirm ────────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            readonly property var wins: cb.shell.state.wins[modelData.name] || []
            readonly property int active: wins.findIndex(w => w.active)
            readonly property bool typing: cb.open && cb.output === modelData.name && cb.local
            // Tabs: zwischen 120 und 260 breit; passt das nicht, die ersten + "+N"
            readonly property int avail: width - cb.inputW - 30
            readonly property int fits: Math.max(1, Math.floor((avail - 48) / 124))
            readonly property int shown: wins.length * 124 > avail ? Math.min(wins.length, fits) : wins.length
            readonly property int tabW: shown ? Math.max(120, Math.min(260, Math.floor((avail - (shown < wins.length ? 48 : 0)) / shown) - 4)) : 0

            screen: modelData
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "commandbar"
            anchors { left: true; right: true; top: true }
            implicitHeight: cb.barH
            exclusiveZone: cb.barH
            color: cb.shell.barBg

            // Trennlinie unten, wie border-bottom der waybar
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: cb.shell.edge }

            // Markierung des aktiven Tabs: gleitet federnd mit
            Rectangle {
                x: 6 + bar.active * (bar.tabW + 4); y: 3
                width: bar.tabW; height: cb.barH - 7
                visible: bar.active >= 0 && bar.active < bar.shown
                radius: 3
                color: cb.shell.fill
                border.width: 1
                border.color: Qt.alpha(cb.shell.hud, 0.5)
                Behavior on x { SpringAnimation { spring: 4; damping: 0.28; epsilon: 0.25 } }
                Behavior on width { NumberAnimation { duration: 200 } }
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: cb.shell.hud; shadowBlur: 0.5; shadowOpacity: 0.35 }
            }

            ListView {
                id: tabs
                x: 6; y: 3
                width: bar.avail; height: cb.barH - 7
                orientation: ListView.Horizontal
                spacing: 4
                interactive: false
                model: ScriptModel { values: bar.wins.slice(0, bar.shown); objectProp: "id" }

                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220 }
                        NumberAnimation { property: "scale"; from: 0.5; to: 1; duration: 360; easing.type: Easing.OutBack }
                    }
                }
                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 0; duration: 160 }
                        NumberAnimation { property: "scale"; to: 0.5; duration: 200; easing.type: Easing.InBack }
                    }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x"; duration: 280; easing.type: Easing.OutCubic }
                    NumberAnimation { properties: "opacity,scale"; to: 1; duration: 180 }
                }
                move: displaced

                delegate: Item {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property string code: index >= 0 ? Nav.code(index) : ""  // -1 beim Ausblenden
                    readonly property bool current: index === bar.active
                    readonly property bool lit: bar.typing && cb.hit(code)
                    readonly property var look: cb.look(modelData)
                    width: bar.tabW; height: tabs.height
                    opacity: bar.typing && cb.r.code !== "" && !lit ? 0.35 : 1
                    Behavior on opacity { NumberAnimation { duration: 120 } }

                    // geteilter Tab (#split): gemeinsame Unterstreichung bis zum Nachbarn
                    Rectangle {
                        visible: !!tab.modelData.group
                        anchors { left: parent.left; bottom: parent.bottom; bottomMargin: -2 }
                        width: parent.width + ((bar.wins[tab.index + 1] || {}).group === tab.modelData.group ? 4 : 0)
                        height: 2
                        color: cb.shell.hud
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 3
                        color: tab.lit ? cb.shell.fill : mouse.containsMouse && !tab.current ? cb.shell.hover : tab.current ? "transparent" : cb.shell.box
                        border.width: 1
                        border.color: tab.lit ? cb.shell.hud : cb.shell.edge
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    Row {
                        anchors { left: parent.left; leftMargin: 7; right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
                        spacing: 7
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tab.code
                            font { family: cb.shell.font; pixelSize: 13; bold: true }
                            color: cb.shell.hud
                        }
                        Image {
                            visible: !tab.look.glyph
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16
                            sourceSize: Qt.size(32, 32)
                            source: tab.modelData.icon ? "file://" + tab.modelData.icon : ""
                            opacity: tab.current || mouse.containsMouse ? 1 : 0.75
                        }
                        // Agenten-Session statt App-Icon
                        Text {
                            visible: !!tab.look.glyph
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; horizontalAlignment: Text.AlignHCenter
                            text: tab.look.glyph
                            font { family: cb.shell.font; pixelSize: 14; bold: true }
                            color: cb.shell.hud
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x
                            elide: Text.ElideRight
                            text: (tab.look.mark ? tab.look.mark + " " : "") + tab.look.name
                                  + (bar.tabW > 150 ? "  ·  " + tab.look.title : "")
                            font { family: cb.shell.font; pixelSize: 11; bold: tab.current }
                            color: tab.current ? cb.shell.hud : Qt.alpha(cb.shell.hud, 0.65)
                        }
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ev => I3.dispatch(`[con_id=${tab.modelData.id}] ${ev.button === Qt.MiddleButton ? "kill" : "focus"}`)
                        onWheel: ev => Quickshell.execDetached([cb.shell.sidebar, "nudge", String(tab.modelData.id), ev.angleDelta.y > 0 ? "up" : "down"])
                        onContainsMouseChanged: if (containsMouse) tip.show(tab)
                                                else if (tip.owner === tab) tip.owner = null
                    }
                }
            }
            // Ueberlauf: Rest per #all oder Super+Tab
            Text {
                visible: bar.shown < bar.wins.length
                x: 6 + bar.shown * (bar.tabW + 4) + 6
                anchors.verticalCenter: parent.verticalCenter
                text: "+" + (bar.wins.length - bar.shown)
                font { family: cb.shell.font; pixelSize: 12; bold: true }
                color: cb.shell.hud
            }

            // Eingabefeld (Ruhezustand); beim Tippen liegt das Overlay darueber
            Rectangle {
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                width: cb.inputW; height: cb.barH - 8
                radius: 3
                color: cb.shell.box
                border.width: 1
                border.color: cb.msg.text && cb.msg.output === bar.modelData.name && cb.msg.warn ? cb.shell.warn : cb.shell.edge
                Text {
                    anchors { left: parent.left; leftMargin: 9; right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                    elide: Text.ElideRight
                    readonly property bool mine: cb.msg.text && cb.msg.output === bar.modelData.name
                    text: mine ? cb.msg.text : "λ   Super+f   ·   # Befehle"
                    font { family: cb.shell.font; pixelSize: 11; bold: mine }
                    color: mine && cb.msg.warn ? cb.shell.warn : mine ? cb.shell.hud : Qt.alpha(cb.shell.hud, 0.4)
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: cb.show() }
            }

            // voller Titel unter dem Tab. Deckend und ohne Ausblenden (Geisterbilder)
            PopupWindow {
                id: tip
                property Item owner: null
                property string label: ""
                function show(t) {
                    owner = t; label = t.modelData.title
                    anchor.rect.x = t.mapToItem(null, 0, 0).x
                    anchor.updateAnchor()
                }
                anchor.window: bar
                anchor.rect.y: cb.barH
                anchor.gravity: Edges.Bottom | Edges.Right
                visible: owner !== null && !cb.open
                implicitWidth: Math.min(tipText.implicitWidth + 24, 520)
                implicitHeight: 28
                color: cb.shell.bg
                Rectangle {
                    anchors.fill: parent
                    color: cb.shell.bg
                    radius: 3
                    border.width: 1
                    border.color: Qt.alpha(cb.shell.hud, 0.5)
                    Text {
                        id: tipText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, 496)
                        elide: Text.ElideRight
                        text: tip.label
                        font { family: cb.shell.font; pixelSize: 12; bold: true }
                        color: cb.shell.hud
                    }
                }
            }
        }
    }

    // ── Eingabe: Overlay mit exklusivem Fokus ueber dem Eingabefeld ─────────
    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === cb.output) || Quickshell.screens[0]
        visible: cb.open
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "commandbar-input"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        MouseArea { anchors.fill: parent; onClicked: cb.hide() }  // Klick daneben = zu

        Item {
            id: keys
            focus: true
            Keys.onPressed: ev => {
                const names = { [Qt.Key_Escape]: "Escape", [Qt.Key_Return]: "Return",
                                [Qt.Key_Enter]: "Return", [Qt.Key_Backspace]: "Backspace",
                                [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Backtab" }
                ev.accepted = cb.handle(names[ev.key] || "", ev.text)
            }
        }

        Column {
            x: win.width - cb.inputW - 6
            y: cb.waybarH + 4
            width: cb.inputW
            spacing: 4

            Rectangle {
                id: input
                width: cb.inputW; height: cb.barH - 8
                radius: 3
                color: cb.shell.bg
                border.width: 1
                border.color: shake.running ? cb.shell.warn : cb.shell.hud
                transform: Translate { id: nudge }
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: cb.shell.hud; shadowBlur: 0.6; shadowOpacity: 0.5 }
                Row {
                    anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Text {
                        text: cb.r.move ? "⇢" : "λ"
                        font { family: cb.shell.font; pixelSize: 13; bold: true }
                        color: cb.shell.hud
                    }
                    Text {
                        id: typedText
                        text: cb.typed + (caret.on ? "▏" : " ")
                        font { family: cb.shell.font; pixelSize: 13; bold: true; letterSpacing: 1 }
                        color: cb.shell.hud
                    }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                    text: cb.typed && cb.r.cmd === null ? Nav.label(cb.r)
                        : cb.tree && !cb.typed && cb.treeFilter ? "Suche: " + cb.treeFilter + " · Enter = erster"
                        : cb.tree && !cb.typed ? "Enter / Esc = zu" : ""
                    font { family: cb.shell.font; pixelSize: 10 }
                    color: Qt.alpha(cb.shell.hud, 0.55)
                }
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: nudge; property: "x"; to: 6; duration: 40 }
                    NumberAnimation { target: nudge; property: "x"; to: -6; duration: 60 }
                    NumberAnimation { target: nudge; property: "x"; to: 0; duration: 40 }
                    PauseAnimation { duration: 160 }
                }
                QtObject {
                    id: caret
                    property bool on: true
                    property Timer blink: Timer { interval: 530; repeat: true; running: cb.open; onTriggered: caret.on = !caret.on }
                }
            }

            // Liste: Befehle, #all-Baum oder die Fenster am getippten Ziel
            Rectangle {
                visible: cb.drop.length > 0
                width: cb.inputW
                height: Math.min(dropList.contentHeight + 12, win.height - cb.waybarH - cb.barH - 40)
                radius: 3
                color: cb.shell.bg
                border.width: 1
                border.color: Qt.alpha(cb.shell.hud, 0.5)
                MouseArea { anchors.fill: parent }  // Klicks in der Liste schliessen nicht

                ListView {
                    id: dropList
                    anchors { fill: parent; margins: 6 }
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: cb.drop
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: dropList.width; height: 24
                        radius: 2
                        color: modelData.hit ? cb.shell.fill : rowMouse.containsMouse && modelData.act ? cb.shell.hover : "transparent"
                        border.width: modelData.hit ? 1 : 0
                        border.color: cb.shell.hud
                        opacity: modelData.dim ? 0.4 : 1
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !!row.modelData.act
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cb.click(row.modelData.act)
                        }
                        Row {
                            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                            spacing: 8
                            Text {
                                width: row.modelData.head ? implicitWidth : 70
                                text: row.modelData.key
                                font { family: cb.shell.font; pixelSize: row.modelData.head ? 12 : 13; bold: true }
                                color: cb.shell.hud
                            }
                            Repeater {
                                model: row.modelData.icons || []
                                Image {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 16; height: 16
                                    sourceSize: Qt.size(32, 32)
                                    source: modelData ? "file://" + modelData : ""
                                }
                            }
                            Text {
                                width: cb.inputW - 120 - (row.modelData.icons || []).length * 24
                                elide: Text.ElideRight
                                text: row.modelData.label
                                font { family: cb.shell.font; pixelSize: 11; bold: !!row.modelData.head }
                                color: row.modelData.head ? Qt.alpha(cb.shell.hud, 0.7) : cb.shell.hud
                            }
                        }
                    }
                }
            }
        }
    }
}
