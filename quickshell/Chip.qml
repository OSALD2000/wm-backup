// Chip im Ticket-Board (Kopf und Detail-Popup): Kasten wie die waybar-Workspaces,
// `on` = gewaehlt. Klick drueckt ihn kurz ein, neue Beschriftung (Zaehler) huepft.
// Chip.Glide = Leuchtstrich unter dem gewaehlten Chip einer Reihe.
import QtQuick
import QtQuick.Effects

Rectangle {
    id: chip
    required property var shell
    property string label
    property bool on: false
    property color ink: on ? shell.hud : Qt.alpha(shell.hud, 0.7)
    property real press: area.pressed ? 1 : 0
    property real hop: 0
    signal hit()
    implicitWidth: txt.implicitWidth + 20
    implicitHeight: 26
    radius: 3
    scale: 1 - 0.08 * press + hop
    color: on ? shell.fill : area.containsMouse ? shell.hover : shell.box
    border.width: 1
    border.color: on ? shell.hud : area.containsMouse ? Qt.alpha(shell.hud, 0.35) : shell.edge
    Behavior on color { ColorAnimation { duration: 150 } }
    Behavior on border.color { ColorAnimation { duration: 150 } }
    Behavior on press { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.01 } }

    onLabelChanged: hopAnim.restart()
    SequentialAnimation {
        id: hopAnim
        NumberAnimation { target: chip; property: "hop"; to: 0.14; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: chip; property: "hop"; to: 0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
    }

    Text {
        id: txt
        anchors.centerIn: parent
        text: chip.label
        font { family: chip.shell.font; pixelSize: 12; bold: true }
        color: chip.ink
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.hit()
    }

    // Leuchtstrich unter `to` (Chip in `row`): gleitet federnd und streckt sich in
    // Laufrichtung, die vordere Kante ist schneller als die hintere.
    // Liegt neben der Row (nicht darin), sonst ordnet die Row ihn mit ein.
    component Glide: Rectangle {
        id: glide
        required property var shell
        property Item row
        property Item to
        readonly property real tl: to ? row.x + to.x + 3 : l
        readonly property real tr: to ? row.x + to.x + to.width - 3 : r
        property real l: tl
        property real r: tr
        x: l; width: Math.max(2, r - l)
        y: row.y + row.height + 4; height: 2
        radius: 1
        color: shell.hud
        opacity: to ? 1 : 0
        Behavior on l { SpringAnimation { spring: glide.tl > glide.l ? 3 : 6; damping: 0.3; epsilon: 0.25 } }
        Behavior on r { SpringAnimation { spring: glide.tr > glide.r ? 6 : 3; damping: 0.3; epsilon: 0.25 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
        layer.enabled: true
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: glide.shell.hud; shadowBlur: 0.6; shadowOpacity: 0.8 }
    }
}
