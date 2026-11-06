// Vorschau-Raster (Super+Tab): alle Fenster aller Monitore als Kacheln mit dem
// letzten Bild, Overlay auf dem fokussierten Monitor. Fenster = "grid" aus
// sidebar.json (shell.state, Reihenfolge wie das Workspace-Raster: Monitor links
// -> rechts, Workspace 1-10). Bilder macht sidebar.py snap() nach
// $XDG_RUNTIME_DIR/win-shots/<id>.png; solange das Overlay zu sehen ist, liegt
// overview.open daneben und snap() pausiert (sonst fotografiert es das Overlay).
// Tasten: hjkl/Pfeile, Tab/Shift+Tab = weiter/zurueck, u/i/o = erstes Fenster des
// Monitors, / = Filter, Enter = hin, Entf = schliessen (Raster bleibt offen), Esc.
// Maus: Hover waehlt, Klick = hin, Mittelklick oder ✕ = schliessen.
// `quickshell ipc call overview toggle|open|close|press NAME|type TEXT|info`.
// Bewegung wie Tickets.qml: Zeitgeber `clock` staffelt Oeffnen/Schliessen.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.I3
import Quickshell.Wayland

Scope {
    id: ov
    required property var shell

    readonly property string run: Quickshell.env("XDG_RUNTIME_DIR")
    readonly property string flag: run + "/overview.open"
    readonly property int gap: 14

    property bool open: false
    property string output: ""
    readonly property string focused: I3.focusedMonitor ? I3.focusedMonitor.name : ""
    property int sel: 0
    property string filter: ""
    property bool filtering: false
    property string stamp: ""        // haengt an den Bild-URLs: je Oeffnen neu laden
    property int zapId: 0            // per Entf geschlossen: Kachel blitzt rot
    property int goId: 0             // per Enter gewaehlt: Kachel zoomt beim Schliessen
    property real clock: 0           // 0..900 ms seit dem Oeffnen, beim Schliessen rueckwaerts
    property real breath: 0.7
    property var pointer: null       // letzte Mausposition (Szene)

    readonly property var all: {
        const out = []
        for (const c of shell.state.grid || [])
            for (const w of c.wins || [])
                out.push(Object.assign({}, w, { ws: c.letter.toUpperCase() + c.number, area: c.area,
                                                letter: c.letter, here: c.visible }))
        return out
    }
    readonly property var wins: {
        const f = filter.toLowerCase()
        return f ? all.filter(w => [w.name, w.title, w.ws, w.area].join(" ").toLowerCase().includes(f)) : all
    }
    readonly property var cur: wins[sel] || null
    // Spalten so, dass die Kacheln am groessten werden (hoechstens 560 breit); bei
    // Gleichstand weniger Spalten. Bild 0.6 der Breite + 52 Fuss + Abstand
    readonly property var fit: {
        let best = { cols: 1, size: 0 }
        for (let c = 1; c <= 6; c++) {
            const rows = Math.ceil(Math.max(1, wins.length) / c)
            const size = Math.min(560, area.width / c, (area.height / rows - 52 - gap) / 0.6 + gap)
            if (size > best.size + 1) best = { cols: c, size: Math.floor(size) }
        }
        return best
    }
    readonly property int cols: fit.cols

    onWinsChanged: sel = Math.max(0, Math.min(sel, wins.length - 1))
    onSelChanged: grid.positionViewAtIndex(sel, GridView.Contain)
    onFilteringChanged: (filtering ? filterInput : keys).forceActiveFocus()

    function stage(at, len) { return Math.max(0, Math.min(1, (clock - at) / len)) }
    function outCubic(x) { return 1 - Math.pow(1 - x, 3) }
    function outBack(x) { const c = 1.70158; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2) }

    function show() {
        output = focused
        filter = ""; filtering = false; zapId = 0; goId = 0; pointer = null
        stamp = String(Date.now())
        sel = Math.max(0, all.findIndex(w => w.focused))
        Quickshell.execDetached(["touch", flag])
        open = true
        outroAnim.stop(); introAnim.restart()
        keys.forceActiveFocus()
    }
    function hide() {
        if (!open) return
        open = false; filtering = false
        introAnim.stop(); outroAnim.restart()
    }
    function go(w) {
        if (!w) return
        goId = w.id
        I3.dispatch(`[con_id=${w.id}] focus`)
        hide()
    }
    // ponytail: Apps mit Rueckfrage (ungespeichert) bleiben stehen, die Kachel blitzt nur
    function kill(w) {
        if (!w) return
        zapId = 0; zapId = w.id
        I3.dispatch(`[con_id=${w.id}] kill`)
    }
    function moveSel(dx, dy) {
        if (wins.length) sel = Math.max(0, Math.min(wins.length - 1, sel + dx + dy * cols))
    }
    function handle(name) {
        if (!open) return false
        const dir = { h: [-1, 0], Left: [-1, 0], l: [1, 0], Right: [1, 0],
                      k: [0, -1], Up: [0, -1], j: [0, 1], Down: [0, 1] }[name]
        if (filtering) {
            if (name === "Escape") { filter = ""; filtering = false }
            else if (name === "Return") go(cur)
            else if (name === "Tab" || name === "Down") moveSel(1, 0)
            else if (name === "Backtab" || name === "Up") moveSel(-1, 0)
            else return false
        } else if (dir) moveSel(dir[0], dir[1])
        else if (name === "Tab") sel = wins.length ? (sel + 1) % wins.length : 0
        else if (name === "Backtab") sel = wins.length ? (sel - 1 + wins.length) % wins.length : 0
        else if (name === "Return" || name === " ") go(cur)
        else if (name === "Delete") kill(cur)
        else if (name === "Escape") { if (filter) filter = ""; else hide() }
        else if (name === "/") filtering = true
        else if (name.length === 1 && "uio".includes(name)) {
            const i = wins.findIndex(w => w.letter === name)
            if (i >= 0) sel = i
        } else return false
        return true
    }

    // Zeitachse bis 900 ms (Kachel 14: 160 + 14*35 + 300 = 950, gekappt); zu: schnell rueckwaerts
    NumberAnimation { id: introAnim; target: ov; property: "clock"; to: 900; duration: 900 }
    NumberAnimation { id: outroAnim; target: ov; property: "clock"; to: 0; duration: 240; easing.type: Easing.OutQuad }
    SequentialAnimation on breath {
        running: ov.open
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.55; duration: 1400; easing.type: Easing.InOutSine }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { if (ov.open) ov.hide(); else ov.show() }
        function open(): void { ov.show() }
        function close(): void { ov.hide() }
        function press(name: string): void { ov.handle(name) }
        function type(text: string): void { ov.filter = text; ov.sel = 0 }
        function info(): string {
            return JSON.stringify({ open: ov.open, sel: ov.sel, count: ov.wins.length,
                                    cur: ov.cur ? ov.cur.id : 0, filter: ov.filter })
        }
    }

    PanelWindow {
        id: win
        screen: Quickshell.screens.find(s => s.name === ov.output) || Quickshell.screens[0]
        visible: ov.open || ov.clock > 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "overview"
        WlrLayershell.keyboardFocus: ov.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        onVisibleChanged: if (!visible) Quickshell.execDetached(["rm", "-f", ov.flag])

        // abdunkeln, Klick daneben = schliessen
        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(ov.shell.bg, 0.72)
            opacity: ov.stage(0, 160)
            MouseArea { anchors.fill: parent; onClicked: ov.hide() }
        }

        Rectangle {
            id: box
            // wie das Ticket-Board: 40 px Rand, oben + 30 fuer die Waybar
            anchors { fill: parent; margins: 40; topMargin: 70 }
            color: ov.shell.bg
            radius: 4
            border.width: 1
            border.color: Qt.alpha(ov.shell.hud, 0.5)
            scale: 0.92 + 0.08 * ov.outBack(ov.stage(0, 300))
            opacity: ov.stage(0, 180)
            clip: true
            MouseArea { anchors.fill: parent }  // Klicks im Kasten schliessen nicht

            Item {
                id: keys
                focus: true
                Keys.onPressed: ev => {
                    const named = { [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Escape]: "Escape",
                                    [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Backtab", [Qt.Key_Left]: "Left",
                                    [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down", [Qt.Key_Delete]: "Delete" }
                    ev.accepted = ov.handle(named[ev.key] || ev.text)
                }
            }

            // HUD-Abtastlinie: laeuft beim Oeffnen einmal von oben nach unten
            Rectangle {
                visible: ov.open && ov.clock < 900
                width: parent.width; height: 2
                y: parent.height * ov.outCubic(ov.stage(60, 560))
                color: ov.shell.hud
                opacity: 0.7 * (1 - ov.stage(420, 200))
                layer.enabled: true
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: ov.shell.hud; shadowBlur: 1; shadowOpacity: 1 }
            }

            // Kopf: λ FENSTER, Zahl, Filter, Tasten
            Item {
                id: head
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24; topMargin: 18 }
                height: 36

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // λ leuchtet beim Oeffnen auf und atmet danach
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "λ"
                        font { family: ov.shell.font; pixelSize: 24; bold: true }
                        color: ov.shell.hud
                        scale: 1 + 0.4 * (1 - ov.outBack(ov.stage(60, 380)))
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: ov.shell.hud
                            shadowBlur: 0.8
                            shadowOpacity: Math.min(1, 0.2 + 0.55 * ov.breath + 1.2 * (1 - ov.stage(250, 700)))
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 4; rightPadding: 10
                        text: "FENSTER"
                        font { family: ov.shell.font; pixelSize: 24; bold: true }
                        color: ov.shell.hud
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: countText.implicitWidth + 16; height: 22; radius: 3
                        color: ov.shell.fill
                        border.width: 1
                        border.color: Qt.alpha(ov.shell.hud, 0.5)
                        Text {
                            id: countText
                            anchors.centerIn: parent
                            text: ov.filter ? ov.wins.length + " / " + ov.all.length : ov.all.length
                            font { family: ov.shell.font; pixelSize: 12; bold: true }
                            color: ov.shell.hud
                        }
                    }
                    Item { width: 14; height: 1 }

                    // Filter: / oder Klick = eingeben, Esc = leeren
                    Rectangle {
                        id: filterChip
                        readonly property bool active: !!ov.filter || ov.filtering
                        anchors.verticalCenter: parent.verticalCenter
                        width: filterRow.width + 20; height: 26
                        clip: true
                        radius: 3
                        color: active ? ov.shell.fill : filterMouse.containsMouse ? ov.shell.hover : ov.shell.box
                        border.width: 1
                        border.color: ov.filtering ? ov.shell.hud : active ? Qt.alpha(ov.shell.hud, 0.5) : ov.shell.edge
                        Behavior on width { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.25 } }
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea {
                            id: filterMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.IBeamCursor
                            onClicked: ov.filtering = true
                        }
                        Row {
                            id: filterRow
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Text {
                                text: "⌕"
                                font { family: ov.shell.font; pixelSize: 13; bold: true }
                                color: filterChip.active ? ov.shell.hud : Qt.alpha(ov.shell.hud, 0.7)
                            }
                            TextInput {
                                id: filterInput
                                visible: ov.filtering
                                width: Math.max(140, contentWidth + 4)
                                text: ov.filter
                                onTextEdited: { ov.filter = text; ov.sel = 0 }
                                font { family: ov.shell.font; pixelSize: 12; bold: true }
                                color: ov.shell.hud
                                selectionColor: Qt.alpha(ov.shell.hud, 0.35)
                                selectedTextColor: ov.shell.hud
                                Keys.onPressed: ev => {
                                    const named = { [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Escape]: "Escape",
                                                    [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Backtab", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down" }
                                    if (named[ev.key]) ev.accepted = ov.handle(named[ev.key])
                                }
                            }
                            Text {
                                visible: !ov.filtering
                                text: ov.filter || "FILTER  /"
                                font { family: ov.shell.font; pixelSize: 12; bold: true }
                                color: ov.filter ? ov.shell.hud : Qt.alpha(ov.shell.hud, 0.7)
                            }
                        }
                    }
                }

                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: "hjkl · Tab · u i o = Monitor · Enter = hin · Entf = schliessen · Esc"
                    font { family: ov.shell.font; pixelSize: 11 }
                    color: Qt.alpha(ov.shell.hud, 0.45)
                }
            }

            // Fuss: voller Titel des gewaehlten Fensters
            Text {
                id: foot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 24; bottomMargin: 16 }
                elide: Text.ElideRight
                text: ov.cur ? ov.cur.ws + "  ·  " + ov.cur.area + "  ·  " + ov.cur.title : ""
                font { family: ov.shell.font; pixelSize: 13; bold: true }
                color: ov.shell.hud
                opacity: ov.stage(400, 300)
            }

            Item {
                id: area
                anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: foot.top
                          leftMargin: 24; rightMargin: 24; topMargin: 16; bottomMargin: 12 }

                Text {
                    anchors.centerIn: parent
                    visible: !ov.wins.length
                    text: ov.filter ? "KEIN TREFFER" : "KEINE FENSTER"
                    font { family: ov.shell.font; pixelSize: 20; bold: true }
                    color: Qt.alpha(ov.shell.hud, 0.45)
                }

                GridView {
                    id: grid
                    readonly property int rows: Math.ceil(count / ov.cols)
                    anchors.centerIn: parent
                    cellWidth: Math.max(160, ov.fit.size)
                    cellHeight: Math.floor((cellWidth - ov.gap) * 0.6) + 52 + ov.gap
                    width: Math.min(count, ov.cols) * cellWidth
                    height: Math.min(area.height, rows * cellHeight)
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: ov.wins; objectProp: "id" }

                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
                            NumberAnimation { property: "scale"; from: 0.6; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2 }
                        }
                    }
                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: 240 }
                            NumberAnimation { property: "scale"; to: 0.4; duration: 280; easing.type: Easing.InBack }
                        }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "x,y"; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                        NumberAnimation { properties: "opacity,scale"; to: 1; duration: 200 }
                    }
                    move: displaced

                    // Auswahl: gleitet federnd, Schein atmet
                    Rectangle {
                        z: 3
                        readonly property real cw: grid.cellWidth - ov.gap
                        readonly property real ch: grid.cellHeight - ov.gap
                        x: (ov.sel % ov.cols) * grid.cellWidth + ov.gap / 2 - cw * 0.03 - 5
                        y: Math.floor(ov.sel / ov.cols) * grid.cellHeight + ov.gap / 2 - ch * 0.03 - 5
                        width: cw * 1.06 + 10; height: ch * 1.06 + 10
                        visible: grid.count > 0
                        radius: 6
                        color: "transparent"
                        border.width: 2
                        border.color: ov.shell.hud
                        opacity: ov.stage(450, 250)
                        Behavior on x { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.25 } }
                        Behavior on y { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.25 } }
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true; shadowColor: ov.shell.hud; shadowBlur: 0.8
                            shadowOpacity: 0.3 + 0.5 * ov.breath
                        }
                    }

                    delegate: Item {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool chosen: index === ov.sel
                        readonly property bool going: ov.goId === modelData.id && !ov.open
                        readonly property int at: 160 + Math.min(index, 14) * 35
                        property real lift: chosen ? 1 : mouse.containsMouse ? 0.4 : 0
                        property real shake: 0
                        property real flash: 0
                        width: grid.cellWidth; height: grid.cellHeight
                        z: chosen ? 2 : 1
                        Behavior on lift { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.005 } }

                        readonly property bool zapped: ov.zapId === modelData.id
                        onZappedChanged: if (zapped) zap.restart()
                        ParallelAnimation {
                            id: zap
                            SequentialAnimation {
                                NumberAnimation { target: tile; property: "shake"; to: -9; duration: 40 }
                                NumberAnimation { target: tile; property: "shake"; to: 8; duration: 60 }
                                NumberAnimation { target: tile; property: "shake"; to: -5; duration: 50 }
                                NumberAnimation { target: tile; property: "shake"; to: 3; duration: 50 }
                                NumberAnimation { target: tile; property: "shake"; to: 0; duration: 50 }
                            }
                            SequentialAnimation {
                                NumberAnimation { target: tile; property: "flash"; to: 1; duration: 60 }
                                NumberAnimation { target: tile; property: "flash"; to: 0; duration: 500; easing.type: Easing.OutQuad }
                            }
                        }

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            // nur bei echter Mausbewegung waehlen: beim Oeffnen und wenn die
                            // Kacheln unter dem stehenden Zeiger umsortieren, meldet Qt auch Hover
                            onPositionChanged: ev => {
                                const p = mapToItem(null, ev.x, ev.y)
                                if (ov.pointer && (p.x !== ov.pointer.x || p.y !== ov.pointer.y)) ov.sel = tile.index
                                ov.pointer = p
                            }
                            onClicked: ev => ev.button === Qt.MiddleButton ? ov.kill(tile.modelData) : ov.go(tile.modelData)
                        }

                        Rectangle {
                            id: card
                            anchors { fill: parent; margins: ov.gap / 2 }
                            transform: Translate { x: tile.shake }
                            // staffelt herein; beim Schliessen in umgekehrter Folge raus,
                            // die gewaehlte Kachel zoomt dabei auf
                            opacity: tile.going ? 1 : ov.stage(tile.at, 200)
                            scale: (tile.going ? 1.15 - 0.12 * ov.stage(0, 900) : 0.8 + 0.2 * ov.outBack(ov.stage(tile.at, 300)))
                                   * (1 + 0.06 * tile.lift)
                            radius: 4
                            color: ov.shell.box
                            border.width: 1
                            border.color: tile.flash > 0 ? ov.shell.warn : tile.chosen ? Qt.alpha(ov.shell.hud, 0.7) : ov.shell.edge

                            // Bild (letzter sichtbarer Stand), ohne Bild das App-Icon gross
                            Rectangle {
                                id: shotBox
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                                height: parent.height - 52
                                radius: 3
                                color: Qt.darker(ov.shell.bg, 1.3)
                                clip: true
                                Image {
                                    id: shot
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    verticalAlignment: Image.AlignTop
                                    asynchronous: true
                                    cache: false
                                    source: "file://" + ov.run + "/win-shots/" + tile.modelData.id + ".png?" + ov.stamp
                                }
                                Image {
                                    anchors.centerIn: parent
                                    visible: shot.status !== Image.Ready
                                    width: 72; height: 72
                                    sourceSize: Qt.size(144, 144)
                                    source: tile.modelData.icon ? "file://" + tile.modelData.icon : ""
                                    opacity: 0.55
                                }
                                // nicht gewaehlt = abgedunkelt
                                Rectangle {
                                    anchors.fill: parent
                                    color: ov.shell.bg
                                    opacity: 0.45 * (1 - tile.lift)
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    color: ov.shell.warn
                                    opacity: 0.45 * tile.flash
                                }

                                // Kennzeichen: Monitor + Workspace + Bereich, ● = gerade sichtbar
                                Rectangle {
                                    x: 8; y: 8
                                    width: badge.implicitWidth + 14; height: 22; radius: 3
                                    color: Qt.alpha(ov.shell.bg, 0.85)
                                    border.width: 1
                                    border.color: tile.chosen ? ov.shell.hud : Qt.alpha(ov.shell.hud, 0.35)
                                    Text {
                                        id: badge
                                        anchors.centerIn: parent
                                        text: tile.modelData.ws + "  " + tile.modelData.area + (tile.modelData.here ? "  ●" : "")
                                        font { family: ov.shell.font; pixelSize: 11; bold: true }
                                        color: ov.shell.hud
                                    }
                                }
                                // ✕ beim Darueberfahren
                                Rectangle {
                                    anchors { right: parent.right; top: parent.top; margins: 8 }
                                    width: 24; height: 22; radius: 3
                                    visible: mouse.containsMouse || xMouse.containsMouse
                                    color: xMouse.containsMouse ? ov.shell.warn : Qt.alpha(ov.shell.bg, 0.85)
                                    border.width: 1
                                    border.color: ov.shell.warn
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        font { family: ov.shell.font; pixelSize: 12; bold: true }
                                        color: xMouse.containsMouse ? ov.shell.bg : ov.shell.warn
                                    }
                                    MouseArea {
                                        id: xMouse
                                        z: 2
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: ov.kill(tile.modelData)
                                    }
                                }
                            }

                            // App-Icon + Name, darunter der Titel
                            Image {
                                id: icon
                                anchors { left: parent.left; leftMargin: 10; top: shotBox.bottom; topMargin: 11 }
                                width: 28; height: 28
                                sourceSize: Qt.size(56, 56)
                                source: tile.modelData.icon ? "file://" + tile.modelData.icon : ""
                                scale: 1 + 0.15 * tile.lift
                            }
                            Text {
                                id: appName
                                anchors { left: icon.right; leftMargin: 10; right: parent.right; rightMargin: 10; top: shotBox.bottom; topMargin: 8 }
                                elide: Text.ElideRight
                                text: tile.modelData.name
                                font { family: ov.shell.font; pixelSize: 13; bold: true }
                                color: tile.chosen ? ov.shell.hud : Qt.alpha(ov.shell.hud, 0.75)
                            }
                            Text {
                                anchors { left: appName.left; right: appName.right; top: appName.bottom; topMargin: 2 }
                                elide: Text.ElideRight
                                text: tile.modelData.title
                                font { family: ov.shell.font; pixelSize: 10 }
                                color: Qt.alpha(ov.shell.hud, 0.5)
                            }
                        }

                    }
                }
            }
        }
    }
}
