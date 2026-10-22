#!/bin/sh
# ws.sh go|move N   — Workspace N des fokussierten Monitors.
# ws.sh tgo|tmove N — Workspace N des Ziel-Monitors (Super+Ctrl[+Shift]+N).
# ws.sh cycle [-1]  — Ziel weiterschalten u -> i -> o (Super+Esc), -1 = zurueck.
# ws.sh bar         — Ziel fuer waybar custom/target ("→ I", leer bei 1 Monitor).
# Namen "<nr>:<kuerzel><N>" (u = 11-20, i = 21-30, o = 31-40, siehe sway/config).
# Der Monitor ergibt sich aus der Nummer des fokussierten Workspaces; ohne
# passende Nummer (alter Name o.ae.) gilt o (den gibt es immer, siehe collapse()
# in eww/scripts/sidebar.py). Das Ziel steht in $XDG_RUNTIME_DIR/ws-target,
# Start und Rueckfall ist o (Laptop).
f=${XDG_RUNTIME_DIR:-/tmp}/ws-target
# Vorhandene Kuerzel nach Anzahl Monitore: 1 = o, 2 = oi, 3 = oiu.
n=$(swaymsg -t get_outputs | jq '[.[] | select(.active)] | length')
have=$(echo oiu | cut -c1-"$n")
t=$(cat "$f" 2>/dev/null)
case $t in [uio]) case $have in *$t*) ;; *) t=o ;; esac ;; *) t=o ;; esac

# Nachbar von Kuerzel $1 in Richtung $2 (+1 = rechts) unter u i o, nur
# vorhandene, rundum.
step() {
    l=$(echo uio | tr -cd "$have")
    i=$(( ($(expr index "$l" "$1") - 1 + $2 + ${#l}) % ${#l} + 1 ))
    echo "$l" | cut -c"$i"
}

base() { case $1 in u) echo 10 ;; i) echo 20 ;; *) echo 30 ;; esac; }

case $1 in
    go|move)
        num=$(swaymsg -t get_workspaces | jq '.[] | select(.focused).num')
        case $(( (num - 1) / 10 )) in 1) k=u ;; 2) k=i ;; *) k=o ;; esac ;;
    tgo|tmove) k=$t ;;
    cycle)
        t=$(step "$t" "${2:-1}")
        echo "$t" > "$f"
        pkill -RTMIN+10 -x waybar  # = "signal" von custom/target
        exit ;;
    bar) [ "$n" -gt 1 ] && echo "→ $t" | tr uio UIO; exit ;;
esac

ws="$(( $(base "$k") + $2 )):$k$2"
case $1 in
    go|tgo)     swaymsg workspace "$ws" ;;
    move|tmove) swaymsg move container to workspace "$ws" ;;
esac
