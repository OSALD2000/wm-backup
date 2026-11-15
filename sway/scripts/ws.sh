#!/bin/sh
# ws.sh go|move N — Workspace N des fokussierten Monitors (Super[+Shift]+N).
# Namen "<nr>:<kuerzel><N>" (a = 11-20, s = 21-30, d = 31-40, siehe sway/config).
# Der Monitor ergibt sich aus der Nummer des fokussierten Workspaces; ohne
# passende Nummer (alter Name o.ae.) gilt d (den gibt es immer, siehe collapse()
# in eww/scripts/sidebar.py). Andere Monitore: Navigator (Super+f).
num=$(swaymsg -t get_workspaces | jq '.[] | select(.focused).num')
case $(( (num - 1) / 10 )) in 1) k=a b=10 ;; 2) k=s b=20 ;; *) k=d b=30 ;; esac

ws="$(( b + $2 )):$k$2"
case $1 in
    go)   swaymsg workspace "$ws" ;;
    move) swaymsg move container to workspace "$ws" ;;
esac
