#!/bin/sh
# ws.sh go|move N — Workspace N des fokussierten Monitors.
# Namen "<nr>:<kuerzel><N>" (u = 11-20, i = 21-30, o = 31-40, siehe sway/config).
# Der Monitor ergibt sich aus der Nummer des fokussierten Workspaces; ohne
# passende Nummer (alter Name o.ae.) gilt u.
num=$(swaymsg -t get_workspaces | jq '.[] | select(.focused).num')
case $(( (num - 1) / 10 )) in 2) k=i b=20 ;; 3) k=o b=30 ;; *) k=u b=10 ;; esac
ws="$((b + $2)):$k$2"
case $1 in
    go)   swaymsg workspace "$ws" ;;
    move) swaymsg move container to workspace "$ws" ;;
esac
