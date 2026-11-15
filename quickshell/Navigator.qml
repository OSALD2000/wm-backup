// Navigator (Super+f): Bildschirm, Workspace und Fenster per Buchstabencode,
// Overlay auf dem fokussierten Monitor. Decodierung in nav.js (dort die
// Grammatik), Daten = "grid" aus sidebar.json (shell.state), beim Oeffnen
// eingefroren: Codes bleiben stabil, solange das Panel offen ist.
// Oben das Raster (Zeile je Bildschirm A/S/D, Feld je Workspace mit Taste und
// App-Icons), darunter die Fenster des Ziel-Workspaces mit ihren Codes.
// Workspace hin/verschieben ueber `sidebar.py workspaces apply`, Fenster und
// Bildschirm direkt per I3.dispatch. Maus: Klick aufs Feld = hin (bei m:
// verschieben), Klick auf ein Fenster = dorthin.
// `quickshell ipc call nav toggle|open|close|type TEXT|press NAME|info`
// (type/press zum Testen ohne Tastatur).
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.I3
import Quickshell.Wayland
import "nav.js" as Nav

Scope {
    id: nv
    required property var shell

    property bool open: false
    property string output: ""
    property string typed: ""
    property var snap: []            // "grid" beim Oeffnen
    property int con: 0              // aktives Fenster beim Oeffnen (fuer m)
    property bool caretOn: true

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
    readonly property string target: r.screen || here           // Bildschirm der Eingabe
    readonly property var list: ctx.wins(target, r.ws)           // Fenster mit Codes
    readonly property var tcell: cell(target, r.ws) || {}

    // Feld zu Kuerzel + Workspace (0 = sichtbarer)
    function cell(s, w) {
        return snap.find(c => c.letter === s && (w ? c.number === w : c.visible))
    }

    function show() {
        output = I3.focusedMonitor ? I3.focusedMonitor.name : ""
        snap = JSON.parse(JSON.stringify(shell.state.grid || []))
        con = 0
        for (const c of snap) for (const w of c.wins || []) if (w.focused) con = w.id
        typed = ""
        open = true
        pop.restart()
        keys.forceActiveFocus()
    }
    function hide() { open = false }

    function apply(action, c) {
        if (!c || (action === "move" && !con)) return
        Quickshell.execDetached([shell.sidebar, "workspaces", "apply", action, c.output,
                                 String(c.number), String(con)])
    }
    function focusWin(w) {
        if (w) I3.dispatch(`[con_id=${w.id}] focus`)
        hide()
    }
    function key(ch) {
        if (typed === "" && ch === "m" && !con) return reject()  // nichts zum Verschieben
        const next = Nav.decode(typed + ch, ctx)
        const a = Nav.act(r, next)
        if (a === "error") return reject()
        typed += ch
        const t = next.screen || here
        if (a === "go") apply("go", cell(t, next.ws))
        else if (a === "move") { apply("move", cell(t, next.ws)); hide() }
        else if (a === "win") focusWin(ctx.wins(t, next.ws)[next.win])
    }
    function enter() {
        const e = Nav.enter(r)
        if (e === "win") focusWin(list[r.match])
        else if (e === "output") { I3.dispatch(`focus output ${JSON.stringify(tcell.output)}`); hide() }
        else if (e === "move") { apply("move", tcell); hide() }
        else if (e === "close") hide()
    }
    function click(c) {
        apply(r.move ? "move" : "go", c)
        hide()
    }
    function reject() { shake.restart() }
    function handle(name, text) {
        if (!open) return false
        if (name === "Escape") hide()
        else if (name === "Return") enter()
        else if (name === "Backspace") typed = Nav.back(typed, ctx)
        else if (text && text.length === 1) key(text.toLowerCase())
        else return false
        return true
    }

    IpcHandler {
        target: "nav"
        function toggle(): void { if (nv.open) nv.hide(); else nv.show() }
        function open(): void { nv.show() }
        function close(): void { nv.hide() }
        function type(text: string): void { for (const c of text) nv.handle("", c) }
        function press(name: string): void { nv.handle(name, "") }
        function info(): string {
            return JSON.stringify({ open: nv.open, typed: nv.typed, output: nv.output, con: nv.con,
                                    here: nv.here, decode: nv.r })
        }
    }

    Timer { interval: 530; repeat: true; running: nv.open; onTriggered: nv.caretOn = !nv.caretOn }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === nv.output) || Quickshell.screens[0]
        visible: nv.open
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "navigator"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        readonly property int cellW: Math.min(130, Math.floor((width - 160) / 10) - 8)
        readonly property int cellH: 78
        readonly property int gap: 8

        // abdunkeln, Klick daneben = zu
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(nv.shell.bg, 0.72)
            MouseArea { anchors.fill: parent; onClicked: nv.hide() }
        }

        Rectangle {
            id: box
            anchors.centerIn: parent
            width: col.width + 48; height: col.height + 40
            color: nv.shell.bg
            radius: 4
            border.width: 1
            border.color: Qt.alpha(nv.shell.hud, 0.5)
            ParallelAnimation {
                id: pop
                NumberAnimation { target: box; property: "scale"; from: 0.92; to: 1; duration: 260; easing.type: Easing.OutBack }
                NumberAnimation { target: box; property: "opacity"; from: 0; to: 1; duration: 180 }
            }
            MouseArea { anchors.fill: parent }  // Klicks im Kasten schliessen nicht

            Item {
                id: keys
                focus: true
                Keys.onPressed: ev => {
                    const names = { [Qt.Key_Escape]: "Escape", [Qt.Key_Return]: "Return",
                                    [Qt.Key_Enter]: "Return", [Qt.Key_Backspace]: "Backspace" }
                    ev.accepted = nv.handle(names[ev.key] || "", ev.text)
                }
            }

            Column {
                id: col
                anchors.centerIn: parent
                spacing: 14

                // Kopf: Modus + Eingabefeld
                Row {
                    spacing: 18
                    Text {
                        id: title
                        text: "λ  " + (nv.r.move ? "FENSTER VERSCHIEBEN" : "NAVIGATOR")
                        font { family: nv.shell.font; pixelSize: 24; bold: true }
                        color: nv.shell.hud
                    }
                    Rectangle {
                        id: input
                        anchors.verticalCenter: title.verticalCenter
                        width: Math.max(160, typedText.implicitWidth + 24); height: 32; radius: 3
                        color: nv.shell.box
                        border.width: 1
                        border.color: shake.running ? nv.shell.warn : nv.shell.hud
                        transform: Translate { id: nudge }
                        Text {
                            id: typedText
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: nv.typed + (nv.caretOn ? "▏" : " ")
                            font { family: nv.shell.font; pixelSize: 18; bold: true; letterSpacing: 2 }
                            color: nv.shell.hud
                        }
                        SequentialAnimation {
                            id: shake
                            NumberAnimation { target: nudge; property: "x"; to: 6; duration: 40 }
                            NumberAnimation { target: nudge; property: "x"; to: -6; duration: 60 }
                            NumberAnimation { target: nudge; property: "x"; to: 0; duration: 40 }
                            PauseAnimation { duration: 160 }
                        }
                    }
                    Text {
                        anchors.baseline: title.baseline
                        text: nv.r.wait === "b" ? "Bildschirm: a s d"
                            : nv.r.wait === "w" ? "Workspace: a … ö"
                            : nv.r.code && nv.r.win < 0 && nv.r.match >= 0 ? "Enter = Fenster " + (nv.r.match + 1) + " · weiter tippen"
                            : nv.r.screen && !nv.r.ws ? "Enter = " + (nv.r.move ? "dorthin verschieben" : "Bildschirm fokussieren")
                            : ""
                        font { family: nv.shell.font; pixelSize: 12; bold: true }
                        color: Qt.alpha(nv.shell.hud, 0.6)
                    }
                }

                // Raster: Zeile je Bildschirm, Feld je Workspace
                Column {
                    spacing: win.gap
                    Repeater {
                        model: nv.rows
                        Row {
                            id: row
                            required property var modelData
                            readonly property string letter: modelData[0].letter
                            readonly property bool chosen: nv.target === letter
                            spacing: win.gap
                            opacity: nv.r.screen && !chosen ? 0.35 : 1
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            Column {
                                width: 48
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: row.letter.toUpperCase()
                                    font { family: nv.shell.font; pixelSize: 26; bold: true }
                                    color: row.chosen ? nv.shell.hud : Qt.alpha(nv.shell.hud, 0.55)
                                }
                                Text {
                                    width: 48; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                    text: row.modelData[0].output
                                    font { family: nv.shell.font; pixelSize: 9 }
                                    color: Qt.alpha(nv.shell.hud, 0.45)
                                }
                            }

                            Repeater {
                                model: row.modelData
                                Rectangle {
                                    id: c
                                    required property var modelData
                                    required property int index
                                    readonly property var wins: modelData.wins || []
                                    readonly property bool sel: row.chosen && nv.r.ws === modelData.number
                                    width: win.cellW; height: win.cellH
                                    radius: 4
                                    color: modelData.visible ? nv.shell.fill : cm.containsMouse ? nv.shell.hover : nv.shell.box
                                    border.width: sel ? 2 : 1
                                    border.color: sel ? nv.shell.hud : modelData.focused ? Qt.alpha(nv.shell.hud, 0.6) : nv.shell.edge
                                    opacity: wins.length || modelData.visible ? 1 : 0.6
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    layer.enabled: sel
                                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: nv.shell.hud; shadowBlur: 0.7; shadowOpacity: 0.6 }

                                    MouseArea {
                                        id: cm
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: nv.click(c.modelData)
                                    }
                                    // Taste gross, darunter Nummer + Bereich
                                    Text {
                                        x: 8; y: 4
                                        text: Nav.KEYS[c.index]
                                        font { family: nv.shell.font; pixelSize: 18; bold: true }
                                        color: nv.shell.hud
                                    }
                                    Text {
                                        anchors { right: parent.right; top: parent.top; margins: 6 }
                                        text: (c.modelData.visible ? "● " : "") + (c.modelData.number % 10) + " " + c.modelData.area
                                        font { family: nv.shell.font; pixelSize: 9; bold: true }
                                        color: Qt.alpha(nv.shell.hud, 0.7)
                                    }
                                    Row {
                                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 8 }
                                        spacing: 4
                                        Repeater {
                                            model: c.wins.slice(0, 4)
                                            Image {
                                                required property var modelData
                                                width: 22; height: 22
                                                sourceSize: Qt.size(44, 44)
                                                source: modelData.icon ? "file://" + modelData.icon : ""
                                            }
                                        }
                                        Text {
                                            visible: c.wins.length > 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: "+" + (c.wins.length - 4)
                                            font { family: nv.shell.font; pixelSize: 11; bold: true }
                                            color: nv.shell.hud
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Fenster des Ziel-Workspaces mit Code; passende hervorgehoben
                Text {
                    text: nv.tcell.name
                          ? nv.target.toUpperCase() + (nv.tcell.number % 10) + "  ·  " + nv.tcell.area + "  ·  "
                            + (nv.list.length ? nv.list.length + " Fenster" : "leer")
                          : ""
                    font { family: nv.shell.font; pixelSize: 13; bold: true }
                    color: nv.shell.hud
                }
                Flow {
                    width: 56 + 10 * (win.cellW + win.gap)
                    spacing: 6
                    Repeater {
                        model: nv.list
                        Rectangle {
                            id: w
                            required property var modelData
                            required property int index
                            readonly property string code: Nav.code(index)
                            readonly property bool hit: nv.r.code !== "" && code.indexOf(nv.r.code) === 0
                            width: 300; height: 30; radius: 3
                            color: hit ? nv.shell.fill : wm.containsMouse ? nv.shell.hover : nv.shell.box
                            border.width: 1
                            border.color: hit ? nv.shell.hud : nv.shell.edge
                            opacity: nv.r.code && !hit ? 0.4 : 1
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            MouseArea {
                                id: wm
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: nv.focusWin(w.modelData)
                            }
                            Row {
                                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                Text {
                                    width: 28
                                    text: w.code
                                    font { family: nv.shell.font; pixelSize: 15; bold: true }
                                    color: nv.shell.hud
                                }
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18; height: 18
                                    sourceSize: Qt.size(36, 36)
                                    source: w.modelData.icon ? "file://" + w.modelData.icon : ""
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 220; elide: Text.ElideRight
                                    text: w.modelData.name + "  ·  " + w.modelData.title
                                    font { family: nv.shell.font; pixelSize: 11 }
                                    color: nv.shell.hud
                                }
                            }
                        }
                    }
                }
                Text {
                    text: "[m] [b a/s/d] [w a…ö] [Fenster] · Enter = los · Bksp = zurueck · Esc = zu"
                    font { family: nv.shell.font; pixelSize: 11 }
                    color: Qt.alpha(nv.shell.hud, 0.45)
                }
            }
        }
    }
}
