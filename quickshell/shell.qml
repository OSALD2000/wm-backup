// Fensterliste links, eine je Monitor (ersetzt die eww-Sidebar).
// Daten schreibt eww/scripts/sidebar.py watch nach $XDG_RUNTIME_DIR/sidebar.json:
// {"wins": {output: [{id, name, title, focused, icon}]}, "show": [outputs]}.
// Nur Fenster des sichtbaren Workspaces; offen erst ab 2 Fenstern, Super+b = aus.
// Klick fokussiert, Mittelklick schliesst, Mausrad sortiert (sidebar.py nudge).
// Look = waybar (waybar/style.css): eckige Kaesten wie die Workspaces, Leiste buendig
// in voller Hoehe; der aktive Eintrag ist gefuellt wie der aktive Workspace.
// Dazu das Workspace-Raster (Super+u / Super+Shift+u), siehe unten bei `grid`.
// Dazu das Ticket-Board (Super+m), siehe Tickets.qml, und das Vorschau-Raster
// (Super+Tab), siehe Overview.qml.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.I3
import Quickshell.Wayland

ShellRoot {
    id: root

    readonly property color hud: "#FFDC00"
    readonly property color bg: "#141310"
    readonly property string font: "Iosevka Nerd Font"
    // = @bar/@edge/@box/@fill/@hover in waybar/style.css
    readonly property color barBg: Qt.rgba(22 / 255, 20 / 255, 13 / 255, 0.88)
    readonly property color edge: Qt.rgba(1, 0.86, 0, 0.14)
    readonly property color box: Qt.rgba(40 / 255, 36 / 255, 24 / 255, 0.55)
    readonly property color fill: Qt.rgba(1, 0.86, 0, 0.16)
    readonly property color hover: Qt.rgba(1, 0.86, 0, 0.08)
    readonly property color warn: "#FF5A3C"  // = @warn: Fehler, Prio hoch, ungueltige Tickets
    readonly property string sidebar: Quickshell.env("HOME") + "/.config/eww/scripts/sidebar.py"
    property var state: ({ wins: {}, show: [], grid: [] })

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/sidebar.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.state = JSON.parse(text()) } catch (e) {}
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panel
            required property var modelData
            readonly property var wins: root.state.wins[modelData.name] || []
            readonly property int active: wins.findIndex(w => w.active)

            screen: modelData
            visible: root.state.show.includes(modelData.name)
            // Ebene "bottom": Sway setzt die waybar (top) zuerst, die Leiste beginnt darunter.
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "sidebar"
            anchors { left: true; top: true; bottom: true }
            implicitWidth: 60
            exclusiveZone: implicitWidth
            color: "transparent"

            // Einfahren beim Oeffnen
            onVisibleChanged: if (visible) intro.restart()
            ParallelAnimation {
                id: intro
                NumberAnimation { target: pill; property: "x"; from: -60; to: 0; duration: 380; easing.type: Easing.OutBack }
                NumberAnimation { target: pill; property: "opacity"; from: 0; to: 1; duration: 300 }
            }

            Rectangle {
                id: pill
                width: parent.width; height: parent.height
                color: root.barBg
                clip: true

                // Trennlinie rechts, wie border-bottom der waybar
                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1; color: root.edge
                }

                // Markierung des aktiven Fensters: gleitet federnd mit
                Item {
                    id: marker
                    // feste Eintragshoehe 56 + spacing -> Position ohne itemAtIndex (nicht reaktiv)
                    x: 5; width: parent.width - 10; height: 56
                    y: panel.active >= 0 ? list.y + panel.active * (height + list.spacing) - list.contentY : y
                    opacity: panel.active >= 0 ? 1 : 0
                    Behavior on y { SpringAnimation { spring: 4; damping: 0.28; epsilon: 0.25 } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    Rectangle {
                        id: glow
                        anchors.fill: parent
                        radius: 4
                        color: root.fill
                        border.width: 1
                        border.color: Qt.rgba(1, 0.86, 0, 0.5)
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: root.hud
                            shadowBlur: 0.6
                            shadowOpacity: breathe.value * 0.45
                        }
                    }
                    // Akzentstrich links, atmet leicht
                    Rectangle {
                        x: -4; width: 2; radius: 0
                        height: 26 * breathe.value + 8
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.hud
                    }
                    QtObject {
                        id: breathe
                        property real value: 0.7
                        SequentialAnimation on value {
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.55; duration: 1400; easing.type: Easing.InOutSine }
                        }
                    }
                }

                ListView {
                    id: list
                    anchors { fill: parent; topMargin: 6; bottomMargin: 6 }
                    spacing: 4
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: panel.wins; objectProp: "id" }

                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260 }
                            NumberAnimation { property: "scale"; from: 0.3; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2 }
                        }
                    }
                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 0; duration: 180 }
                            NumberAnimation { property: "scale"; to: 0.2; duration: 220; easing.type: Easing.InBack }
                        }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "x,y"; duration: 320; easing.type: Easing.OutCubic }
                        NumberAnimation { properties: "opacity,scale"; to: 1; duration: 200 }
                    }
                    move: displaced

                    delegate: Item {
                        id: entry
                        required property var modelData
                        required property int index
                        readonly property bool current: index === panel.active
                        width: list.width; height: 56

                        Item {
                            id: body
                            anchors.fill: parent
                            scale: mouse.pressed ? 0.88 : mouse.containsMouse ? 1.08 : 1
                            Behavior on scale { SpringAnimation { spring: 5; damping: 0.25 } }

                            // Kasten wie #workspaces button; der aktive liegt unter der Markierung
                            Rectangle {
                                anchors { fill: parent; leftMargin: 5; rightMargin: 5 }
                                radius: 4
                                color: mouse.containsMouse && !entry.current ? root.hover : root.box
                                border.width: 1
                                border.color: root.edge
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Image {
                                id: icon
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 7
                                width: 26; height: 26
                                sourceSize: Qt.size(56, 56)
                                source: entry.modelData.icon ? "file://" + entry.modelData.icon : ""
                                smooth: true
                                opacity: entry.current || mouse.containsMouse ? 1 : 0.72
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                // kleiner Huepfer, wenn das Fenster den Fokus bekommt
                                SequentialAnimation {
                                    id: hop
                                    NumberAnimation { target: icon; property: "y"; to: 2; duration: 120; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: icon; property: "y"; to: 7; duration: 380; easing.type: Easing.OutBounce }
                                }
                            }
                            Text {
                                anchors { horizontalCenter: parent.horizontalCenter; top: icon.bottom; topMargin: 3 }
                                width: parent.width - 12
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: entry.modelData.name
                                font { family: root.font; pixelSize: 9; bold: true }
                                color: entry.current ? root.hud : Qt.rgba(1, 0.86, 0, 0.6)
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                        }
                        onCurrentChanged: if (current) hop.restart()

                        MouseArea {
                            id: mouse
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ev => I3.dispatch(`[con_id=${entry.modelData.id}] ${ev.button === Qt.MiddleButton ? "kill" : "focus"}`)
                            onWheel: ev => Quickshell.execDetached([root.sidebar, "nudge", String(entry.modelData.id), ev.angleDelta.y > 0 ? "up" : "down"])
                            onContainsMouseChanged: if (containsMouse) tip.show(entry)
                                                    else if (tip.owner === entry) tip.owner = null
                        }
                    }
                }
            }

            // Fenstertitel als Popout rechts neben dem Eintrag. Deckend und ohne
            // Ausblenden: ein halbtransparentes Popup hinterliess Geisterbilder.
            PopupWindow {
                id: tip
                property Item owner: null
                property string label: ""
                function show(e) {
                    owner = e; label = e.modelData.title
                    anchor.rect.y = e.mapToItem(null, 0, 0).y + (e.height - implicitHeight) / 2
                    anchor.updateAnchor()
                }
                anchor.window: panel
                anchor.rect.x: panel.width
                anchor.gravity: Edges.Bottom | Edges.Right
                visible: owner !== null
                implicitWidth: Math.min(text.implicitWidth + 24, 420)
                implicitHeight: 30
                color: root.bg

                Rectangle {
                    anchors.fill: parent
                    color: root.bg
                    radius: 4
                    border.width: 1
                    border.color: Qt.rgba(1, 0.86, 0, 0.5)
                    Text {
                        id: text
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, 396)
                        elide: Text.ElideRight
                        text: tip.label
                        font { family: root.font; pixelSize: 12; bold: true }
                        color: root.hud
                    }
                }
            }
        }
    }

    // Workspace-Raster: eine Zeile je Monitor (links -> rechts), zehn Felder mit
    // den App-Icons, live aus "grid" in sidebar.json. sidebar.py workspaces go|move
    // oeffnet es per `quickshell ipc call grid open ACTION FELD CON OUTPUT`
    // (Startfeld = letztes Ziel, CON = aktives Fenster beim Oeffnen), bestaetigt
    // wird ueber sidebar.py workspaces apply. Tasten: hjkl/Pfeile, u/i/o = Zeile,
    // 1-0 = Feld waehlen + bestaetigen, Enter, Tab = Modus, Esc. Maus: Klick auf
    // ein Feld bestaetigt, Klick auf ein Icon springt zu dem Fenster.
    QtObject {
        id: grid
        property bool open: false
        property string action: "go"
        property int sel: 0
        property int con: 0
        property string output: ""
        // Eingabefeld je Zeile: getippte Nummer und zu welcher Zeile sie gehoert
        property string typed: ""
        property int typedRow: -1
        readonly property var cells: root.state.grid || []
        readonly property int rows: Math.ceil(cells.length / 10)

        function confirm(i) {
            const c = cells[i]
            if (!c || (action === "move" && !con)) return
            Quickshell.execDetached([root.sidebar, "workspaces", "apply", action, c.output, String(c.number), String(con)])
            open = false
        }
        // Ziffer ins Feld der aktuellen Zeile: 2-9 und 0 (=10) sofort los,
        // "1" wartet kurz, ob noch "0" kommt (10), sonst los
        function type(d) {
            const r = Math.floor(sel / 10)
            if (typedRow !== r) typed = ""
            typedRow = r
            typed = typed === "1" && d === "0" ? "10" : d
            sel = Math.min(cells.length - 1, r * 10 + (typed === "0" ? 10 : Number(typed)) - 1)
            if (typed === "1") dial.restart()
            else confirm(sel)
        }
        function moveSel(dx, dy) {
            if (!cells.length) return
            const r = Math.max(0, Math.min(rows - 1, Math.floor(sel / 10) + dy))
            sel = Math.min(cells.length - 1, r * 10 + (sel % 10 + dx + 10) % 10)
        }
    }

    QtObject {
        id: caret
        property bool on: true
        property Timer blink: Timer { interval: 530; repeat: true; running: grid.open; onTriggered: caret.on = !caret.on }
    }

    IpcHandler {
        target: "grid"
        function open(action: string, sel: int, con: int, output: string): void {
            grid.action = action; grid.sel = sel; grid.con = con; grid.output = output
            grid.typed = ""; grid.typedRow = -1
            grid.open = true
        }
        function close(): void { grid.open = false }
    }

    Timer {
        id: dial
        interval: 700
        onTriggered: if (grid.open && grid.typed === "1") grid.confirm(grid.sel)
    }

    PanelWindow {
        id: gridWin
        screen: Quickshell.screens.find(s => s.name === grid.output) || Quickshell.screens[0]
        visible: grid.open
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "workspace-grid"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        readonly property int cellW: Math.min(140, Math.floor((width - 160) / 10) - 8)
        readonly property int cellH: 92
        readonly property int gap: 8

        onVisibleChanged: if (visible) { pop.restart(); keys.forceActiveFocus() }

        // abdunkeln, Klick daneben = abbrechen
        Rectangle {
            id: dim
            anchors.fill: parent
            color: Qt.rgba(0.08, 0.075, 0.06, 0.72)
            MouseArea { anchors.fill: parent; onClicked: grid.open = false }
        }

        Rectangle {
            id: box
            anchors.centerIn: parent
            width: col.width + 48; height: col.height + 40
            color: root.bg
            radius: 4
            border.width: 1
            border.color: Qt.rgba(1, 0.86, 0, 0.5)
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
                    const k = ev.key
                    if (k === Qt.Key_Escape) grid.open = false
                    else if (k === Qt.Key_H || k === Qt.Key_Left) grid.moveSel(-1, 0)
                    else if (k === Qt.Key_L || k === Qt.Key_Right) grid.moveSel(1, 0)
                    else if (k === Qt.Key_K || k === Qt.Key_Up) grid.moveSel(0, -1)
                    else if (k === Qt.Key_J || k === Qt.Key_Down) grid.moveSel(0, 1)
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) grid.confirm(grid.sel)
                    else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { if (grid.con) grid.action = grid.action === "go" ? "move" : "go" }
                    else if (k >= Qt.Key_0 && k <= Qt.Key_9) grid.type(String(k - Qt.Key_0))
                    else if (k === Qt.Key_Backspace) { dial.stop(); grid.typed = "" }
                    else {
                        const r = grid.cells.findIndex(c => c.letter === ev.text.toLowerCase())
                        if (r < 0) return
                        grid.sel = r + grid.sel % 10
                    }
                    ev.accepted = true
                }
            }

            Column {
                id: col
                anchors.centerIn: parent
                spacing: 14

                Row {
                    spacing: 18
                    Text {
                        text: "λ  " + (grid.action === "go" ? "WORKSPACE WECHSELN" : "FENSTER VERSCHIEBEN")
                        font { family: root.font; pixelSize: 24; bold: true }
                        color: root.hud
                    }
                    Text {
                        anchors.baseline: parent.children[0].baseline
                        text: grid.con ? "Tab = " + (grid.action === "go" ? "verschieben" : "wechseln") : ""
                        font { family: root.font; pixelSize: 12; bold: true }
                        color: Qt.rgba(1, 0.86, 0, 0.5)
                    }
                }

                Item {
                    id: board
                    width: 56 + 10 * (gridWin.cellW + gridWin.gap)
                    height: grid.rows * (gridWin.cellH + gridWin.gap)

                    // Auswahl: gleitet federnd wie die Markierung der Fensterliste
                    Rectangle {
                        z: 2
                        x: 56 + (grid.sel % 10) * (gridWin.cellW + gridWin.gap) - 3
                        y: Math.floor(grid.sel / 10) * (gridWin.cellH + gridWin.gap) - 3
                        width: gridWin.cellW + 6; height: gridWin.cellH + 6
                        radius: 5
                        color: "transparent"
                        border.width: 2
                        border.color: root.hud
                        Behavior on x { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.25 } }
                        Behavior on y { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.25 } }
                        layer.enabled: true
                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: root.hud; shadowBlur: 0.7; shadowOpacity: 0.6 }
                    }

                    // Zeilenkopf: Kuerzel + Anschluss
                    Repeater {
                        model: grid.rows
                        Column {
                            id: head
                            required property int index
                            readonly property var first: grid.cells[index * 10] || {}
                            readonly property bool here: Math.floor(grid.sel / 10) === index
                            y: index * (gridWin.cellH + gridWin.gap) + (gridWin.cellH - height) / 2
                            width: 48
                            spacing: 3
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (first.letter || "").toUpperCase()
                                font { family: root.font; pixelSize: 26; bold: true }
                                color: first.output === grid.output ? root.hud : Qt.rgba(1, 0.86, 0, 0.55)
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 48; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                text: first.output || ""
                                font { family: root.font; pixelSize: 9 }
                                color: Qt.rgba(1, 0.86, 0, 0.45)
                            }
                            // Eingabefeld: Ziffern gehen in das Feld der aktuellen Zeile,
                            // Klick waehlt die Zeile
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 40; height: 20; radius: 3
                                color: head.here ? root.fill : root.box
                                border.width: 1
                                border.color: head.here ? root.hud : root.edge
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: (grid.typedRow === head.index ? grid.typed : "")
                                          + (head.here && caret.on ? "▏" : head.here ? " " : "")
                                    font { family: root.font; pixelSize: 12; bold: true }
                                    color: root.hud
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.IBeamCursor
                                    onClicked: { grid.sel = head.index * 10 + grid.sel % 10; grid.typed = ""; grid.typedRow = head.index }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: grid.cells
                        Rectangle {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property var wins: modelData.wins || []
                            x: 56 + (index % 10) * (gridWin.cellW + gridWin.gap)
                            y: Math.floor(index / 10) * (gridWin.cellH + gridWin.gap)
                            width: gridWin.cellW; height: gridWin.cellH
                            radius: 4
                            color: modelData.visible ? root.fill : cellMouse.containsMouse ? root.hover : root.box
                            border.width: 1
                            border.color: modelData.focused ? Qt.rgba(1, 0.86, 0, 0.6) : root.edge
                            opacity: wins.length || modelData.visible ? 1 : 0.6
                            Behavior on color { ColorAnimation { duration: 150 } }

                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: if (containsMouse) grid.sel = cell.index
                                onClicked: grid.confirm(cell.index)
                            }

                            Text {
                                x: 8; y: 6
                                text: (cell.modelData.number % 10) + "  " + cell.modelData.area
                                font { family: root.font; pixelSize: 10; bold: true }
                                color: cell.modelData.visible ? root.hud : Qt.rgba(1, 0.86, 0, 0.7)
                            }
                            Text {
                                anchors { right: parent.right; top: parent.top; margins: 6 }
                                visible: cell.modelData.visible
                                text: "●"
                                font.pixelSize: 9
                                color: root.hud
                            }
                            // Fenster als Icons; Klick = zu dem Fenster springen
                            Row {
                                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 10 }
                                spacing: 4
                                Repeater {
                                    model: cell.wins.slice(0, 4)
                                    Image {
                                        id: ico
                                        required property var modelData
                                        width: 24; height: 24
                                        sourceSize: Qt.size(48, 48)
                                        source: modelData.icon ? "file://" + modelData.icon : ""
                                        scale: icoMouse.containsMouse ? 1.25 : 1
                                        Behavior on scale { SpringAnimation { spring: 5; damping: 0.3 } }
                                        MouseArea {
                                            id: icoMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onContainsMouseChanged: if (containsMouse) grid.sel = cell.index
                                            onClicked: { I3.dispatch(`[con_id=${ico.modelData.id}] focus`); grid.open = false }
                                        }
                                    }
                                }
                                Text {
                                    visible: cell.wins.length > 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "+" + (cell.wins.length - 4)
                                    font { family: root.font; pixelSize: 11; bold: true }
                                    color: root.hud
                                }
                            }
                        }
                    }
                }

                // Titel des ersten Fensters im gewaehlten Feld bzw. Anzahl
                Text {
                    readonly property var c: grid.cells[grid.sel] || {}
                    readonly property var w: c.wins || []
                    width: board.width; elide: Text.ElideRight
                    text: !c.name ? "" : c.letter.toUpperCase() + (c.number % 10) + "  ·  " + c.output + "  ·  "
                          + (w.length ? w.length + " Fenster: " + w.map(x => x.name).join(", ") : "leer")
                    font { family: root.font; pixelSize: 13; bold: true }
                    color: root.hud
                }
                Text {
                    text: "hjkl / Pfeile · u i o = Zeile · Nummer ins Feld tippen (1-10) · Enter / Klick = los · Klick auf Icon = zum Fenster · Esc"
                    font { family: root.font; pixelSize: 11 }
                    color: Qt.rgba(1, 0.86, 0, 0.45)
                }
            }
        }
    }

    Tickets { shell: root }
    Overview { shell: root }
}
