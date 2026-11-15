#!/bin/sh
# #clear — alle Fenster im fokussierten Workspace schliessen (sway kill: Apps mit
# ungespeicherten Aenderungen fragen selbst nach und bleiben offen).
# Vertrag aller Befehle: siehe CommandBar.qml (stdout optional {"notify": "..."}).
n=$(swaymsg -t get_tree | jq '[.. | objects | select(.type == "workspace") | select([.. | objects | select(.focused == true)] | length > 0)
      | .. | objects | select((.type == "con" or .type == "floating_con") and .pid != null)] | length')
[ "$n" -gt 0 ] || { echo '{"notify": "Workspace ist schon leer"}'; exit 0; }
swaymsg -q '[workspace=__focused__] kill' || exit 1
printf '{"notify": "%s Fenster geschlossen"}\n' "$n"
