// Karte im Ticket-Board: Kennung, Prio (▲ hoch, ● mittel, ▼ niedrig), Titel bis
// 3 Zeilen, Labels als Chips, Checkliste. Archivierte gedimmt, `bad` = roter Rand.
import QtQuick

Item {
    id: card
    required property var t
    required property var shell
    property bool selected: false
    signal clicked()
    // Szenenposition des Zeigers; das Board waehlt nur bei echter Mausbewegung
    signal hovered(point p)

    readonly property color prioInk: t.prio === "hoch" ? shell.warn
                                     : t.prio === "niedrig" ? Qt.alpha(shell.hud, 0.45) : shell.hud
    height: content.implicitHeight + 22
    opacity: t.archived ? 0.45 : 1

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: card.selected || mouse.containsMouse ? card.shell.hover : card.shell.box
        border.width: card.t.bad ? 2 : 1
        border.color: card.t.bad ? card.shell.warn : card.shell.edge
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    // Prio hoch: Akzentstrich links
    Rectangle {
        visible: card.t.prio === "hoch"
        x: 0; y: 8; width: 2; height: parent.height - 16
        color: card.shell.warn
    }

    Column {
        id: content
        x: 14; y: 11; width: parent.width - 28
        spacing: 7

        Item {
            width: parent.width; height: keyText.implicitHeight
            Text {
                id: keyText
                text: card.t.key
                font { family: card.shell.font; pixelSize: 11; bold: true }
                color: Qt.alpha(card.shell.hud, 0.5)
            }
            Text {
                anchors { right: parent.right; verticalCenter: keyText.verticalCenter }
                text: ({ hoch: "▲", mittel: "●", niedrig: "▼" })[card.t.prio] || "●"
                font { family: card.shell.font; pixelSize: 12; bold: true }
                color: card.prioInk
            }
        }
        Text {
            width: parent.width
            text: card.t.title
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font { family: card.shell.font; pixelSize: 14; bold: true }
            color: card.shell.hud
        }
        // Labels links, Checkliste rechts
        Item {
            visible: card.t.labels.length > 0 || card.t.check[1] > 0
            width: parent.width; height: Math.max(chips.height, check.implicitHeight)
            Flow {
                id: chips
                width: parent.width - (check.visible ? check.width + 8 : 0)
                spacing: 4
                Repeater {
                    model: card.t.labels
                    Rectangle {
                        required property string modelData
                        width: label.implicitWidth + 10; height: 18
                        radius: 2
                        color: card.shell.box
                        border.width: 1
                        border.color: card.shell.edge
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: "#" + parent.modelData
                            font { family: card.shell.font; pixelSize: 10; bold: true }
                            color: Qt.alpha(card.shell.hud, 0.75)
                        }
                    }
                }
            }
            Text {
                id: check
                anchors { right: parent.right; bottom: parent.bottom }
                visible: card.t.check[1] > 0
                text: "☑ " + card.t.check[0] + "/" + card.t.check[1]
                font { family: card.shell.font; pixelSize: 11; bold: true }
                color: card.t.check[0] === card.t.check[1] ? card.shell.hud : Qt.alpha(card.shell.hud, 0.6)
            }
        }
        Text {
            visible: !!card.t.bad
            width: parent.width
            wrapMode: Text.Wrap
            text: "⚠ " + card.t.bad
            font { family: card.shell.font; pixelSize: 11; bold: true }
            color: card.shell.warn
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.clicked()
        onPositionChanged: m => card.hovered(mapToItem(null, m.x, m.y))
    }
}
