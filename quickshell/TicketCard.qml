// Karte im Ticket-Board: Kennung, Prio (▲ hoch, ● mittel, ▼ niedrig), Titel bis
// 3 Zeilen, Labels als Chips, Checkliste. Archivierte gedimmt, `bad` = roter Rand.
// Bewegung: Hover hebt leicht an, Prio hoch atmet (Akzentstrich), neue Prio dreht
// den Pfeil, wachsende Checkliste blitzt, flash() = kurzes Gluehen, bump(d) = Abprallen.
// fold/slide/intro setzt das Board (Listen-Uebergaenge, Oeffnen), lift/tilt die
// fliegende Kopie. Ziehen: MouseArea.drag auf dragTarget (Proxy des Boards).
import QtQuick
import QtQuick.Effects

Item {
    id: card
    required property var t
    required property var shell
    property bool selected: false
    property real breath: 0.7        // vom Board, laeuft nur bei offenem Board
    property real face: 1            // Deckkraft des Inhalts (0 = die Kopie fliegt gerade)
    property real intro: 1           // 0..1 Einflug beim Oeffnen
    property real fold: 1            // 0 = zusammengeklappt (Archivieren)
    property real slide: 0           // seitlich (Reiterwechsel)
    property real lift: 0            // 0..1 angehoben (Ziehen, Flug)
    property real tilt: 2.5          // Neigung in Grad bei lift 1
    property Item dragTarget: null   // Proxy des Boards; null = nicht ziehbar
    signal clicked()
    // Szenenposition des Zeigers; das Board waehlt nur bei echter Mausbewegung
    signal hovered(point p)
    signal pressed(point at)         // Druckpunkt in der Karte (Proxy hinlegen)
    signal dragStarted()
    signal released()

    readonly property color prioInk: t.prio === "hoch" ? shell.warn
                                     : t.prio === "niedrig" ? Qt.alpha(shell.hud, 0.45) : shell.hud
    property real hov: mouse.containsMouse ? 1 : 0
    property real kick: 0
    property real glow: 0
    property real dim: t.archived ? 0.45 : 1
    Behavior on dim { NumberAnimation { duration: 200 } }
    height: content.implicitHeight + 22

    function flash() { flashAnim.restart() }
    function bump(d) { kickAnim.d = d; kickAnim.restart() }

    transform: [
        Scale { origin.y: card.height / 2; yScale: card.fold },
        Translate { x: card.slide + card.kick; y: 14 * (1 - card.intro) }
    ]
    Behavior on hov { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.01 } }

    // Prio-Pfeil und Checkliste nur animieren, wenn sich dasselbe Ticket aendert
    property var last: ({ key: "", prio: "", done: 0 })
    onTChanged: {
        if (t.key === last.key) {
            if (t.prio !== last.prio) spin.restart()
            if (t.check[0] > last.done) blink.restart()
        }
        last = { key: t.key, prio: t.prio, done: t.check[0] }
    }
    Component.onCompleted: {
        last = { key: t.key, prio: t.prio, done: t.check[0] }
        // Hoehe sofort richtig: Column/Flow ordnen sonst erst im naechsten Durchgang, die
        // Liste setzt die Nachbarn (samt laufendem displaced-Uebergang) auf die falsche Hoehe
        chips.forceLayout(); content.forceLayout()
    }

    Item {
        id: faceItem
        anchors.fill: parent
        opacity: card.face * card.intro * card.dim
        scale: 1 + 0.02 * card.hov + 0.04 * card.lift
        rotation: card.tilt * card.lift
        layer.enabled: card.lift > 0.01
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: card.shell.hud
            shadowBlur: 0.5 + 0.5 * card.lift
            shadowOpacity: 0.45 * card.lift
            shadowVerticalOffset: 8 * card.lift
        }

        Rectangle {
            anchors.fill: parent
            radius: 4
            // angehoben deckend, sonst scheint die Karte darunter durch
            color: card.lift > 0.01 ? Qt.tint(card.shell.bg, card.shell.fill)
                   : card.selected || mouse.containsMouse ? card.shell.hover : card.shell.box
            border.width: card.t.bad ? 2 : 1
            border.color: card.t.bad ? card.shell.warn
                          : card.lift > 0.01 ? card.shell.hud
                          : mouse.containsMouse ? Qt.alpha(card.shell.hud, 0.4) : card.shell.edge
            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }
        }
        // Gluehen: neu, gelandet in Fertig
        Rectangle {
            anchors { fill: parent; margins: -2 }
            visible: card.glow > 0
            opacity: card.glow
            radius: 6
            color: Qt.alpha(card.shell.hud, 0.12)
            border.width: 2
            border.color: card.shell.hud
            layer.enabled: visible
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: card.shell.hud; shadowBlur: 0.8; shadowOpacity: 0.9 }
        }
        // Prio hoch: Akzentstrich links, atmet
        Rectangle {
            visible: card.t.prio === "hoch"
            x: 0; width: 2
            height: (parent.height - 16) * (0.75 + 0.25 * card.breath)
            anchors.verticalCenter: parent.verticalCenter
            color: card.shell.warn
            opacity: 0.5 + 0.5 * card.breath
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
                    id: arrow
                    anchors { right: parent.right; verticalCenter: keyText.verticalCenter }
                    text: ({ hoch: "▲", mittel: "●", niedrig: "▼" })[card.t.prio] || "●"
                    font { family: card.shell.font; pixelSize: 12; bold: true }
                    color: card.prioInk
                    Behavior on color { ColorAnimation { duration: 250 } }
                    // neue Stufe: einmal herumdrehen und kurz aufploppen
                    ParallelAnimation {
                        id: spin
                        NumberAnimation { target: arrow; property: "rotation"; from: -180; to: 0; duration: 420; easing.type: Easing.OutBack }
                        NumberAnimation { target: arrow; property: "scale"; from: 1.6; to: 1; duration: 420; easing.type: Easing.OutBack }
                    }
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
                    property real flare: 0
                    anchors { right: parent.right; bottom: parent.bottom }
                    visible: card.t.check[1] > 0
                    text: "☑ " + card.t.check[0] + "/" + card.t.check[1]
                    font { family: card.shell.font; pixelSize: 11; bold: true }
                    color: card.t.check[0] === card.t.check[1] || flare > 0 ? card.shell.hud : Qt.alpha(card.shell.hud, 0.6)
                    scale: 1 + 0.35 * flare
                    transformOrigin: Item.Right
                    // waechst die Checkliste: kurz aufblitzen
                    NumberAnimation { id: blink; target: check; property: "flare"; from: 1; to: 0; duration: 500; easing.type: Easing.OutCubic }
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
    }

    SequentialAnimation {
        id: flashAnim
        NumberAnimation { target: card; property: "glow"; to: 1; duration: 90 }
        NumberAnimation { target: card; property: "glow"; to: 0; duration: 650; easing.type: Easing.OutQuad }
    }
    // Abprallen: kurz in Richtung d, federnd zurueck
    SequentialAnimation {
        id: kickAnim
        property int d: 1
        NumberAnimation { target: card; property: "kick"; to: 16 * kickAnim.d; duration: 80; easing.type: Easing.OutQuad }
        NumberAnimation { target: card; property: "kick"; to: 0; duration: 420; easing.type: Easing.OutElastic; easing.amplitude: 1.2; easing.period: 0.35 }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true   // sonst nimmt die ListView senkrechtes Ziehen als Scrollen
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        drag.target: card.dragTarget
        onPressed: m => card.pressed(Qt.point(m.x, m.y))
        drag.onActiveChanged: if (drag.active) card.dragStarted()
        onReleased: card.released()
        onCanceled: card.released()
        onClicked: card.clicked()   // nach einem Ziehen meldet Qt keinen Klick
        onPositionChanged: m => card.hovered(mapToItem(null, m.x, m.y))
    }
}
