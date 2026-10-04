#!/bin/sh
# ws.sh go|move N — Workspace N des fokussierten Monitors.
# Namen "<nr>:<kuerzel><N>" (u = 11-20, i = 21-30, o = 31-40, siehe sway/config).
# Der Monitor ergibt sich aus der Nummer des fokussierten Workspaces; ohne
# passende Nummer (alter Name o.ae.) gilt o (den gibt es immer, siehe collapse()
# in eww/scripts/sidebar.py).
num=$(swaymsg -t get_workspaces | jq '.[] | select(.focused).num')
case $(( (num - 1) / 10 )) in 1) k=u b=10 ;; 2) k=i b=20 ;; *) k=o b=30 ;; esac
ws="$((b + $2)):$k$2"
case $1 in
    go)   swaymsg workspace "$ws" ;;
    move) swaymsg move container to workspace "$ws" ;;
esac
