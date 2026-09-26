#!/bin/sh
# Theme-Werkzeug fuer wm-backup. Das Repo ist die Quelle, ~/.config das Ziel.
#
#   theme.sh list                 Theme-Tags + aktuell deployter Stand
#   theme.sh current              nur den deployten Stand
#   theme.sh status               Live-Dateien, die vom deployten Stand abweichen
#   theme.sh switch <tag> [-n] [-f]
#                                 Tag nach ~/.config deployen und neu laden
#                                 -n = nur anzeigen, -f = Abweichungen ueberschreiben
#   theme.sh sync-back            Live-Stand ins Repo-Arbeitsverzeichnis kopieren
#                                 (fuer neue Themes; danach git diff + commit)
#
# Kein rsync --delete: Dateien, die der Ziel-Tag nicht kennt (z. B. hypr/ in
# FirstSetup), bleiben liegen. Sie stoeren nicht, weil nur der deployte
# Stand sie referenziert.
set -eu

REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/wm-theme
FFP=$HOME/snap/firefox/common/.mozilla/firefox/h5d4ltr7.default
DIRS="sway hypr waybar rofi eww swaync swaylock alacritty"
# Muell in den Live-Ordnern, der nie ins Repo gehoert
EXCL="--exclude=.git --exclude=*.bak* --exclude=themes/ --exclude=*.pak"

# Paare "Repo-Pfad Ziel-Pfad"; Ordner mit /, Dateien ohne
map() {
    for d in $DIRS; do echo "$d/ $HOME/.config/$d/"; done
    echo "wallpaper.jpg $HOME/Private/wallpaper.jpg"
    echo "browser/chrome-hl2-theme/ $HOME/.config/chrome-hl2-theme/"
    echo "browser/firefox/userChrome.css $FFP/chrome/userChrome.css"
    echo "browser/firefox/userContent.css $FFP/chrome/userContent.css"
    echo "browser/firefox/user.js $FFP/user.js"
}

# Ohne State-Datei gilt HEAD (bzw. der Tag darauf) als deployt
current() {
    cat "$STATE" 2>/dev/null ||
        git -C "$REPO" describe --tags --exact-match HEAD 2>/dev/null || echo HEAD
}

# --out-format: bei Ordnern Ziel+Dateiname, bei Einzeldateien nur das Ziel
fmt() { case $1 in */) echo "$2%n" ;; *) echo "$2" ;; esac; }

export_ref() {  # $1 ref, $2 Zielordner
    mkdir -p "$2"
    git -C "$REPO" archive "$1" | tar -x -C "$2"
}

# Dateien aus Stand $1 (exportiert), die live fehlen oder anders sind
drift() {
    map | while read -r src dst; do
        [ -e "$1/$src" ] || continue
        rsync -rcn --out-format="$(fmt "$src" "$dst")" "$1/$src" "$dst" | grep -v '/$' || true
    done | sed 's|//*|/|g'
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

case ${1:-} in
list)
    cur=$(current)
    git -C "$REPO" tag --sort=creatordate --format='%(refname:short) %(creatordate:short) %(subject)' |
        while read -r t rest; do
            [ "$t" = "$cur" ] && m='*' || m=' '
            echo "$m $t  $rest"
        done
    echo "deployt: $cur"
    ;;
current) current ;;
status)
    export_ref "$(current)" "$TMP/cur"
    d=$(drift "$TMP/cur")
    [ -z "$d" ] && echo "sauber: live = $(current)" || { echo "abweichend von $(current):"; echo "$d"; }
    ;;
switch)
    tag=${2:?Tag fehlt, siehe: theme.sh list}; shift 2
    dry=; force=
    for a in "$@"; do case $a in -n) dry=1 ;; -f) force=1 ;; esac; done
    git -C "$REPO" rev-parse -q --verify "refs/tags/$tag" >/dev/null ||
        { echo "unbekannter Tag: $tag" >&2; exit 1; }

    export_ref "$(current)" "$TMP/cur"
    d=$(drift "$TMP/cur")
    if [ -n "$d" ] && [ -z "$force" ]; then
        echo "Abbruch: live weicht vom deployten Stand $(current) ab:" >&2
        echo "$d" >&2
        echo "Erst sichern (sync-back + commit) oder mit -f ueberschreiben." >&2
        exit 2
    fi

    export_ref "$tag" "$TMP/new"
    map | while read -r src dst; do
        [ -e "$TMP/new/$src" ] || continue
        mkdir -p "$(dirname "$dst")"
        rsync -rlc ${dry:+-n} --out-format="  $(fmt "$src" "$dst")" "$TMP/new/$src" "$dst" | grep -v '/$' || true
    done
    [ -n "$dry" ] && { echo "(Probelauf, nichts geaendert)"; exit 0; }
    mkdir -p "$(dirname "$STATE")"; echo "$tag" > "$STATE"

    # Neu laden. swaymsg reload startet waybar, swaync und screens.py ueber
    # exec_always neu. swayidle (Lock-Befehl!) und eww-Fenster sind nur exec
    # -> selbst neu starten, mit dem Befehl aus der neuen sway-Config.
    if [ -n "${SWAYSOCK:-}" ]; then
        swaymsg reload >/dev/null
        # exec-Zeile zu $1 aus der sway-Config, \-Fortsetzungen zusammengefuegt
        execline() {
            sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}' "$HOME/.config/sway/config" |
                sed -n "s/^exec \(--no-startup-id \)\{0,1\}\($1.*\)$/\2/p" | head -1
        }
        pkill -x swayidle || true
        cmd=$(execline swayidle); [ -n "$cmd" ] && setsid sh -c "$cmd" >/dev/null 2>&1 &
        if command -v eww >/dev/null; then
            eww kill >/dev/null 2>&1 || true
            cmd=$(execline 'eww open'); [ -n "$cmd" ] && setsid sh -c "$cmd" >/dev/null 2>&1 &
        fi
    else
        echo "Keine Sway-Session: Neuladen uebersprungen (Super+Shift+C spaeter)."
    fi
    echo "deployt: $tag. Firefox/Chrome neu starten, damit das Browser-Theme greift."
    ;;
sync-back)
    map | while read -r src dst; do
        [ -e "$dst" ] || continue
        mkdir -p "$(dirname "$REPO/$src")"
        rsync -rlc $EXCL --out-format="  $(fmt "$src" "$src")" "$dst" "$REPO/$src" | grep -v '/$' || true
    done
    echo "Jetzt: git -C $REPO status / diff pruefen, dann committen."
    ;;
*) sed -n '2,15p' "$0"; exit 1 ;;
esac
