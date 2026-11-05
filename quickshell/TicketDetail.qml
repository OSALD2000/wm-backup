// Detail-Popup im Ticket-Board: Felder als Chips (Klick wirkt wie die Taste),
// darunter der Notiztext als Markdown. Der Text wird nur in Obsidian bearbeitet.
import QtQuick

Rectangle {
    id: dlg
    required property var t
    required property var shell
    // Oberkante des Titels: das Eingabefeld des Boards legt sich beim Bearbeiten darueber
    readonly property real titleY: body.y + title.y
    implicitHeight: body.y + body.height + md.implicitHeight + foot.height + 64
    // MarkdownText faerbt Links mit der App-Palette (blau, unlesbar): Links, <url> und
    // nackte URLs als HTML-Anker in Theme-Farbe. ponytail: trifft auch URLs in Code-Spans.
    function links(md) {
        return md.replace(/\[([^\]]+)\]\(([^)\s]+)\)|<(https?:\/\/[^>\s]+)>|(https?:\/\/[^\s<>)\]]*[^\s<>)\].,;:!?])/g,
                          (m, label, url, auto, bare) => `<a href="${url || auto || bare}" style="color: ${shell.hud}">${label || auto || bare}</a>`)
    }
    signal setField(string field, string value)
    signal edit(string field)  // title | labels | project
    signal openNote()
    signal closed()

    // Chip: Kasten wie die waybar-Workspaces, `on` = gewaehlt. Auch der Kopf des Boards nutzt ihn.
    component Chip: Rectangle {
        id: chip
        required property var shell
        property string label
        property bool on: false
        property color ink: on ? shell.hud : Qt.alpha(shell.hud, 0.7)
        signal hit()
        implicitWidth: txt.implicitWidth + 20
        implicitHeight: 26
        radius: 3
        color: on ? shell.fill : area.containsMouse ? shell.hover : shell.box
        border.width: 1
        border.color: on ? shell.hud : area.containsMouse ? Qt.alpha(shell.hud, 0.35) : shell.edge
        Behavior on color { ColorAnimation { duration: 150 } }
        Text {
            id: txt
            anchors.centerIn: parent
            text: chip.label
            font { family: chip.shell.font; pixelSize: 12; bold: true }
            color: chip.ink
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.hit()
        }
    }
    component Caption: Text {
        required property var shell
        height: 26
        verticalAlignment: Text.AlignVCenter
        font { family: shell.font; pixelSize: 11; bold: true }
        color: Qt.alpha(shell.hud, 0.5)
    }

    color: shell.bg
    radius: 4
    border.width: 1
    border.color: Qt.alpha(shell.hud, 0.5)
    MouseArea { anchors.fill: parent }  // Klicks im Popup schliessen nicht

    Chip {
        shell: dlg.shell
        anchors { right: parent.right; top: parent.top; margins: 18 }
        label: "✕"
        onHit: dlg.closed()
    }

    Column {
        id: body
        x: 28; y: 24; width: parent.width - 56
        spacing: 14

        Text {
            text: dlg.t.key + "   ·   " + dlg.t.project + "   ·   angelegt " + (dlg.t.created || "?")
            font { family: dlg.shell.font; pixelSize: 12; bold: true }
            color: Qt.alpha(dlg.shell.hud, 0.5)
        }
        Text {
            id: title
            width: parent.width - 40
            text: dlg.t.title
            wrapMode: Text.Wrap
            font { family: dlg.shell.font; pixelSize: 22; bold: true }
            color: dlg.shell.hud
            MouseArea { anchors.fill: parent; cursorShape: Qt.IBeamCursor; onClicked: dlg.edit("title") }
        }
        Text {
            visible: !!dlg.t.bad
            text: "⚠ " + dlg.t.bad
            font { family: dlg.shell.font; pixelSize: 12; bold: true }
            color: dlg.shell.warn
        }

        Grid {
            columns: 2
            rowSpacing: 8
            columnSpacing: 18

            Caption { shell: dlg.shell; text: "PROJEKT" }
            Chip { shell: dlg.shell; label: dlg.t.project; onHit: dlg.edit("project") }

            Caption { shell: dlg.shell; text: "STATUS" }
            Row {
                spacing: 6
                Repeater {
                    model: ["backlog", "todo", "in-arbeit", "review", "fertig"]
                    Chip {
                        required property string modelData
                        shell: dlg.shell
                        label: modelData.toUpperCase().replace("-", " ")
                        on: dlg.t.status === modelData
                        onHit: dlg.setField("status", modelData)
                    }
                }
            }

            Caption { shell: dlg.shell; text: "PRIO" }
            Row {
                spacing: 6
                Repeater {
                    model: [["hoch", "▲"], ["mittel", "●"], ["niedrig", "▼"]]
                    Chip {
                        required property var modelData
                        shell: dlg.shell
                        label: modelData[1] + " " + modelData[0].toUpperCase()
                        on: dlg.t.prio === modelData[0]
                        ink: modelData[0] === "hoch" ? dlg.shell.warn
                             : on || modelData[0] === "mittel" ? dlg.shell.hud : Qt.alpha(dlg.shell.hud, 0.55)
                        onHit: dlg.setField("prio", modelData[0])
                    }
                }
            }

            Caption { shell: dlg.shell; text: "LABELS" }
            Row {
                spacing: 6
                Repeater {
                    model: dlg.t.labels
                    Chip {
                        required property string modelData
                        shell: dlg.shell
                        label: "#" + modelData
                        onHit: dlg.edit("labels")
                    }
                }
                Chip {
                    shell: dlg.shell
                    label: dlg.t.labels.length ? "✎" : "+ LABEL"
                    onHit: dlg.edit("labels")
                }
            }

            Caption { shell: dlg.shell; text: "CHECKLISTE"; visible: dlg.t.check[1] > 0 }
            Caption {
                shell: dlg.shell
                visible: dlg.t.check[1] > 0
                text: "☑ " + dlg.t.check[0] + " / " + dlg.t.check[1]
                color: dlg.shell.hud
            }
        }

        Rectangle { width: parent.width; height: 1; color: dlg.shell.edge }
    }

    // Notiztext aus der Datei, gerendert
    Flickable {
        id: notes
        anchors { top: body.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: foot.top
                  leftMargin: 28; rightMargin: 28; bottomMargin: 14 }
        clip: true
        contentHeight: md.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Text {
            id: md
            width: notes.width
            textFormat: Text.MarkdownText
            text: dlg.links(dlg.t.body)
            wrapMode: Text.Wrap
            font { family: dlg.shell.font; pixelSize: 14 }
            color: dlg.shell.hud
            lineHeight: 1.2
            linkColor: dlg.shell.hud
            palette.link: dlg.shell.hud  // MarkdownText nimmt die Linkfarbe aus der Palette
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: foot.top; leftMargin: 28; rightMargin: 28; bottomMargin: 12 }
        height: 1
        color: dlg.shell.edge
    }
    Row {
        id: foot
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 28; bottomMargin: 20 }
        spacing: 8
        Chip { shell: dlg.shell; label: "◆ IN OBSIDIAN  o"; onHit: dlg.openNote() }
        Chip {
            shell: dlg.shell
            label: (dlg.t.archived ? "↺ ZURUECKHOLEN" : "▣ ARCHIVIEREN") + "  a"
            onHit: dlg.setField("archived", dlg.t.archived ? "nein" : "ja")
        }
    }
    Text {
        anchors { right: parent.right; verticalCenter: foot.verticalCenter; rightMargin: 28 }
        text: "e Titel · t Labels · P Projekt · p Prio · H/L Status · Esc zu"
        font { family: dlg.shell.font; pixelSize: 11 }
        color: Qt.alpha(dlg.shell.hud, 0.45)
    }
}
