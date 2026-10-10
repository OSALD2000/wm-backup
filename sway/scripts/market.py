#!/usr/bin/python3
"""waybar custom/market: New-York-Zeit + laufende Session (ICT-Killzones).

Text "NY 09:12 · NY AM · Open 18m", ausserhalb einer Session "… · NY PM in 2h25",
am Wochenende / in der taeglichen CME-Pause "… · zu". Klasse active/idle/closed
fuer style.css, Tooltip = alle Sessions in NY- und Ortszeit.
Aufruf: market.py | market.py selftest
"""
import json
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

NY = ZoneInfo("America/New_York")
SESSIONS = [("ASIA", 20 * 60, 24 * 60), ("LONDON", 2 * 60, 5 * 60),
            ("NY AM", 7 * 60, 10 * 60), ("NY PM", 13 * 60 + 30, 16 * 60)]  # Minuten NY-Zeit
OPEN = 9 * 60 + 30  # Kassa-Eroeffnung, Countdown in NY AM


def closed(t):
    """CME-Futures: Fr 17:00 bis So 18:00 zu, sonst taeglich 17-18 Pause."""
    m, wd = t.hour * 60 + t.minute, t.weekday()
    return wd == 5 or (wd == 4 and m >= 17 * 60) or (wd == 6 and m < 18 * 60) or 17 * 60 <= m < 18 * 60


def dur(m):
    return f"{m // 60}h{m % 60:02d}" if m >= 60 else f"{m}m"


def state(t):
    """-> (Text hinter der Uhr, CSS-Klasse) fuer NY-Zeit t."""
    m = t.hour * 60 + t.minute
    if closed(t):
        return "zu", "closed"
    for name, a, b in SESSIONS:
        if a <= m < b:
            return name + (f" · Open {dur(OPEN - m)}" if name == "NY AM" and m < OPEN else ""), "active"
    name, a, _ = min(SESSIONS, key=lambda s: (s[1] - m) % 1440)
    return f"{name} in {dur((a - m) % 1440)}", "idle"


def tooltip(t):
    local = lambda m: t.replace(hour=m // 60 % 24, minute=m % 60).astimezone().strftime("%H:%M")
    rows = [f"{n:<7} {a // 60:02d}:{a % 60:02d}-{b // 60 % 24:02d}:{b % 60:02d}  (hier {local(a)}-{local(b)})"
            for n, a, b in SESSIONS]
    return "<tt>" + "\n".join(["Session NY-Zeit", *rows, "OPEN    09:30"]) + "</tt>"


def selftest():
    at = lambda *a: datetime(*a, tzinfo=NY)
    assert state(at(2026, 10, 7, 9, 12)) == ("NY AM · Open 18m", "active")  # Mittwoch
    assert state(at(2026, 10, 7, 9, 45)) == ("NY AM", "active")
    assert state(at(2026, 10, 7, 11, 5)) == ("NY PM in 2h25", "idle")
    assert state(at(2026, 10, 7, 21, 0)) == ("ASIA", "active")
    assert state(at(2026, 10, 7, 0, 30)) == ("LONDON in 1h30", "idle")  # nach Mitternacht
    assert state(at(2026, 10, 7, 17, 30))[1] == "closed"  # CME-Pause
    assert state(at(2026, 10, 10, 12, 0))[1] == "closed"  # Samstag
    assert state(at(2026, 10, 11, 18, 30)) == ("ASIA in 1h30", "idle")  # Sonntag offen
    tooltip(at(2026, 10, 7, 9, 0))
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["selftest"]:
        selftest()
    else:
        t = datetime.now(NY)
        text, cls = state(t)
        print(json.dumps({"text": f"NY {t:%H:%M} · {text}", "class": cls, "tooltip": tooltip(t)}))
