#!/bin/sh
# HL2-Ladebalken fuer hyprlock (~/.config/hypr/hyprlock.conf).
# lock.sh schreibt den Sperrzeitpunkt; der Balken fuellt sich in 2 s, dann
# wechselt der Text von LOADING... auf SUIT LOCKED.
# Aufruf: loading.sh bar | loading.sh text
STEPS=20      # Bloecke im Balken
TICK=100      # ms pro Block -> 20 x 100 ms = 2 s
start=$(cat "${XDG_RUNTIME_DIR:-/tmp}/hl2-lock-start" 2>/dev/null || echo 0)
# Nanosekunden: das date der Rust-Coreutils ignoriert die Breite in %3N
n=$(( ($(date +%s%N) - start) / (TICK * 1000000) ))
[ "$n" -gt "$STEPS" ] && n=$STEPS

if [ "$1" = text ]; then
    [ "$n" -lt "$STEPS" ] && echo "LOADING..." || echo "SUIT LOCKED"
    exit
fi
full=""; empty=""; i=0
while [ $i -lt $STEPS ]; do
    [ $i -lt "$n" ] && full="$full▮" || empty="$empty▮"
    i=$((i + 1))
done
echo "$full<span fgalpha='22%'>$empty</span>"
