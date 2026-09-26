#!/usr/bin/env python3
"""Arrange whatever monitors are connected, left to right, laptop rightmost.

Sway-Port von ~/.config/i3/scripts/screens.py. layout() ist unveraendert — die
Anordnungslogik ist compositor-agnostisch. Neu sind nur Ein- und Ausgabe:
swaymsg -t get_outputs (JSON) statt xrandr --query (Regex), und
`swaymsg output ... position` statt `xrandr --pos`.

Zwei Unterschiede zu xrandr, die den Code kuerzer machen:
  * Sway listet nur *angeschlossene* Outputs. Abgezogene Schirme muss niemand
    mehr explizit abschalten, das macht der Compositor selbst.
  * Sway waehlt den preferred mode von allein. Also erst `enable`, dann die
    tatsaechliche Groesse zurueklesen — kein Raten am Modus-Flag.
"""

import json
import subprocess
import sys

LAPTOP = "eDP-1"


def swaymsg(*args):
    return subprocess.run(["swaymsg", *args], capture_output=True, text=True,
                          check=True).stdout


def outputs():
    """-> [(name, w, h, active)] alle angeschlossenen Outputs"""
    out = []
    for o in json.loads(swaymsg("-r", "-t", "get_outputs")):
        mode = o.get("current_mode") or (o.get("modes") or [None])[-1] or {}
        out.append((o["name"], mode.get("width", 0), mode.get("height", 0),
                    o["active"]))
    return out


def layout(connected):
    """-> [(name, w, h, x)] ordered left to right, tiled with no gaps.

    Externals descend by name, laptop last. That ordering is what every old
    script encoded by hand: HDMI-1 > DP-9 > DP-8 > DP-7, then eDP-1.
    # ponytail: string sort, so DP-10 lands right of DP-9. Add natural sort
    # if a dock ever hands out DP-10 and it matters.
    """
    ext = sorted((c for c in connected if c[0] != LAPTOP), reverse=True)
    lap = [c for c in connected if c[0] == LAPTOP]
    placed, x = [], 0
    for name, w, h in ext + lap:
        placed.append((name, w, h, x))
        x += w
    return placed


def self_check():
    px = lambda placed: [(n, x) for n, _, _, x in placed]

    # today: HDMI-A-1 left, DP-7 centre, laptop right
    assert px(layout([("eDP-1", 1920, 1200), ("HDMI-A-1", 1920, 1200),
                      ("DP-7", 1920, 1200)])) == \
        [("HDMI-A-1", 0), ("DP-7", 1920), ("eDP-1", 3840)]

    # home.sh / test.sh / MAJPlatz.sh: DP-8 left, DP-7 centre
    assert px(layout([("DP-7", 1920, 1080), ("DP-8", 1920, 1080),
                      ("eDP-1", 1920, 1200)])) == \
        [("DP-8", 0), ("DP-7", 1920), ("eDP-1", 3840)]

    # SEBPlatz.sh: DP-9 left, DP-8 centre
    assert px(layout([("DP-8", 1920, 1080), ("DP-9", 1920, 1080),
                      ("eDP-1", 1920, 1200)])) == \
        [("DP-9", 0), ("DP-8", 1920), ("eDP-1", 3840)]

    # reset.sh: laptop alone
    assert px(layout([("eDP-1", 1920, 1200)])) == [("eDP-1", 0)]

    # work.sh: two externals, laptop excluded
    assert px(layout([("DP-7", 1920, 1080), ("DP-8", 1920, 1080)])) == \
        [("DP-8", 0), ("DP-7", 1920)]

    # offsets follow real widths, not an assumed 1920
    assert px(layout([("DP-7", 2560, 1440), ("HDMI-A-1", 1280, 1024),
                      ("eDP-1", 1920, 1200)])) == \
        [("HDMI-A-1", 0), ("DP-7", 1280), ("eDP-1", 3840)]

    print("self-check ok")


def main():
    if "--self-check" in sys.argv:
        return self_check()

    dry = "--dry-run" in sys.argv
    all_out = outputs()
    off = set()

    if "--no-laptop" in sys.argv and any(n != LAPTOP for n, *_ in all_out):
        off.add(LAPTOP)

    wanted = [o for o in all_out if o[0] not in off]
    if not wanted:
        sys.exit("no connected outputs — nothing to arrange")

    cmds = [("output", n, "disable") for n in off]
    # erst einschalten, damit Sway den preferred mode setzt ...
    for name, _, _, active in wanted:
        if not active:
            cmds.append(("output", name, "enable"))
    for c in cmds:
        print(" ".join(("swaymsg",) + c)) if dry else swaymsg(*c)

    # ... dann die echten Groessen lesen und positionieren
    live = outputs() if not dry else all_out
    size = {n: (w, h) for n, w, h, _ in live}
    connected = [(n, *size.get(n, (0, 0))) for n, *_ in wanted]
    for name, _, _, x in layout(connected):
        c = ("output", name, "position", str(x), "0")  # Sway: "X Y", nicht xrandr-"X,Y"
        print(" ".join(("swaymsg",) + c)) if dry else swaymsg(*c)


if __name__ == "__main__":
    main()
