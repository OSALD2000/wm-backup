#!/bin/sh
# Sperre im HL2-Look: hyprlock (~/.config/hypr/hyprlock.conf).
# Startet hyprlock nicht oder stuerzt es ab, uebernimmt swaylock — Sway laesst
# nach einem abgestuerzten Lock-Client einen neuen die Sperre uebernehmen.
#
# Im Hintergrund, weil swayidle -w auf den Befehl wartet und hyprlock (anders
# als swaylock -f) erst beim Entsperren zurueckkehrt. Das sleep gibt der Sperre
# Zeit zu stehen, bevor before-sleep den Rechner schlafen legt.
pgrep -x hyprlock >/dev/null && exit 0
( hyprlock || swaylock -f ) &
sleep 1
