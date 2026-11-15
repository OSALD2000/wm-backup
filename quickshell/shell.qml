// Gemeinsame Wurzel der Quickshell-Teile: Farben des Themes (root) und der
// Stand aus $XDG_RUNTIME_DIR/sidebar.json, den eww/scripts/sidebar.py watch schreibt:
// {"wins": {output: [{id, name, title, focused, active, icon}]}, "grid": [...]}.
// Teile: Befehlsleiste unter der waybar (Super+f), siehe CommandBar.qml, das
// Ticket-Board (Super+m), siehe Tickets.qml, und das Vorschau-Raster (Super+Tab),
// siehe Overview.qml.
import QtQuick
import Quickshell
import Quickshell.Io

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
    property var state: ({ wins: {}, grid: [] })

    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/sidebar.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.state = JSON.parse(text()) } catch (e) {}
        }
    }

    Tickets { shell: root }
    Overview { shell: root }
    CommandBar { shell: root }
}
