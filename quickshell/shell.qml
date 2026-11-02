// Fensterliste links, eine je Monitor (ersetzt die eww-Sidebar).
// Daten schreibt eww/scripts/sidebar.py watch nach $XDG_RUNTIME_DIR/sidebar.json:
// {"wins": {output: [{id, name, title, focused, icon}]}, "show": [outputs]}.
// Nur Fenster des sichtbaren Workspaces; offen erst ab 2 Fenstern, Super+b = aus.
// Klick fokussiert, Mittelklick schliesst, Mausrad sortiert (sidebar.py nudge).
// Look = waybar (waybar/style.css): eckige Kaesten wie die Workspaces, Leiste buendig
// in voller Hoehe; der aktive Eintrag ist gefuellt wie der aktive Workspace.
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
    readonly property string sidebar: Quickshell.env("HOME") + "/.config/eww/scripts/sidebar.py"
    property var state: ({ wins: {}, show: [] })

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
}
