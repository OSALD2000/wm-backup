#!/usr/bin/python3
"""Lern-Stoppuhr fuer das eww-Widget.

Aufruf: learn.py watch | toggle NAME | start NAME | stop [--idle SEK] | discard | undo
                 | add NAME | archive NAME | selftest
Daten:  ~/.local/share/learn-timer/data.json
"""
import fcntl
import json
import os
import shutil
import sys
import time
from datetime import date, datetime, timedelta

STREAK_MIN = 30  # Minuten Lernzeit pro Tag, damit der Tag fuer die Streak zaehlt
DIR = os.path.expanduser("~/.local/share/learn-timer")
DATA = os.path.join(DIR, "data.json")
BEAT = os.path.join(DIR, "heartbeat")
BACKUPS = os.path.join(DIR, "backups")  # eine Kopie pro Tag, die letzten 30 bleiben
STALE = 120  # Sek. ohne Heartbeat = Rechner war aus/abgestuerzt -> Session dort beenden
HEAT_WEEKS = 26  # Spalten der Heatmap (passt in die Panelbreite)
WEEKDAYS = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]


def load():
    try:
        with open(DATA) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"topics": [], "sessions": [], "running": None, "last": None}


def backup():
    os.makedirs(BACKUPS, exist_ok=True)
    target = os.path.join(BACKUPS, f"{date.today()}.json")
    if os.path.exists(DATA) and not os.path.exists(target):
        shutil.copy2(DATA, target)
        for old in sorted(os.listdir(BACKUPS))[:-30]:
            os.remove(os.path.join(BACKUPS, old))


def save(d):
    backup()
    tmp = DATA + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f, indent=1)
    os.replace(tmp, DATA)


def beat():
    with open(BEAT, "w"):
        pass


def beat_age(now):
    try:
        return now - os.path.getmtime(BEAT)
    except FileNotFoundError:
        return 0


def finish(d, end):
    r = d["running"]
    if r:
        end = max(r["start"], end)
        if end > r["start"]:
            d["sessions"].append({"topic": r["topic"], "start": r["start"], "end": end})
        d["running"] = None


def recover(d, now):
    """Laufender Timer, aber lange kein Heartbeat -> Rechner war aus. Beim letzten Lebenszeichen beenden."""
    if d["running"] and beat_age(now) > STALE:
        finish(d, os.path.getmtime(BEAT))


def per_day(sessions):
    days = {}
    for s in sessions:
        a, b = s["start"], s["end"]
        while a < b:
            day = datetime.fromtimestamp(a).date()
            e = min(b, datetime.combine(day + timedelta(1), datetime.min.time()).timestamp())
            days[day] = days.get(day, 0) + e - a
            a = e
    return days


def streak(days, today):
    need = STREAK_MIN * 60
    day = today if days.get(today, 0) >= need else today - timedelta(1)  # heute zaehlt erst ab Schwelle
    n = 0
    while days.get(day, 0) >= need:
        n += 1
        day -= timedelta(1)
    return n


def level(sec):
    """Farbstufe der Heatmap wie bei GitHub: 0 = nichts, 4 = 2h+."""
    return 0 if sec <= 0 else 1 if sec < 1800 else 2 if sec < 3600 else 3 if sec < 7200 else 4


def fmt(sec):
    m = int(sec) // 60
    return f"{m // 60}h {m % 60:02d}m" if m >= 60 else f"{m}m"


def clock(sec):
    s = int(sec)
    return f"{s // 3600}:{s // 60 % 60:02d}:{s % 60:02d}"


def stats(d, now):
    today = datetime.fromtimestamp(now).date()
    monday = today - timedelta(today.weekday())
    r = d["running"]
    sessions = d["sessions"] + ([{"topic": r["topic"], "start": r["start"], "end": now}] if r else [])
    topics = [t["name"] for t in d["topics"] if not t.get("archived")]
    focus = r["topic"] if r else d.get("last") if d.get("last") in topics else (topics[0] if topics else "")

    by_topic = {t: per_day([s for s in sessions if s["topic"] == t]) for t in topics}
    all_days = per_day(sessions)
    fd = by_topic.get(focus, {})
    last7 = [today - timedelta(i) for i in range(6, -1, -1)]
    top = max([fd.get(x, 0) for x in last7] + [3600])  # Skala mind. 1h, sonst wirken 5 Minuten riesig

    first = monday - timedelta(weeks=HEAT_WEEKS - 1)
    heat = [[{"l": "future", "t": ""} if x > today else
             {"l": level(all_days.get(x, 0)), "t": f"{WEEKDAYS[x.weekday()]} {x:%d.%m.} · {fmt(all_days.get(x, 0))}"}
             for x in (first + timedelta(w * 7 + i) for i in range(7))] for w in range(HEAT_WEEKS)]

    return {
        "running": bool(r),
        "heat": heat,
        "topic": focus,
        "elapsed": clock(now - r["start"]) if r else "",
        "today": fmt(fd.get(today, 0)),
        "week": fmt(sum(v for k, v in fd.items() if k >= monday)),
        "total": fmt(sum(fd.values())),
        "streak": streak(fd, today),
        "all_today": fmt(all_days.get(today, 0)),
        "all_streak": streak(all_days, today),
        "suit": min(100, round(100 * all_days.get(today, 0) / (STREAK_MIN * 60))),  # HUD: Tagesziel in %
        "bars": [{"d": WEEKDAYS[x.weekday()], "pct": round(100 * fd.get(x, 0) / top),
                  "h": fmt(fd.get(x, 0)), "today": x == today} for x in last7],
        "topics": [{"name": t, "today": fmt(by_topic[t].get(today, 0)), "total": fmt(sum(by_topic[t].values())),
                    "active": bool(r) and r["topic"] == t} for t in topics],
        "has_last": bool(d["sessions"]) and not r,
    }


def watch():
    while True:
        now = time.time()
        if beat_age(now) > STALE:
            with locked():
                d = load()
                recover(d, now)
                save(d)
        if beat_age(now) > 30 or not os.path.exists(BEAT):
            beat()
        print(json.dumps(stats(load(), now)), flush=True)
        time.sleep(1)


class locked:
    def __enter__(self):
        self.f = open(os.path.join(DIR, ".lock"), "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)

    def __exit__(self, *a):
        self.f.close()


def command(d, cmd, arg, now):
    names = {t["name"]: t for t in d["topics"]}
    if cmd in ("start", "toggle"):
        if arg not in names:
            return
        if cmd == "toggle" and d["running"] and d["running"]["topic"] == arg:
            finish(d, now)
        elif not (d["running"] and d["running"]["topic"] == arg):
            finish(d, now)  # nur ein Timer gleichzeitig
            d["running"] = {"topic": arg, "start": now}
            d["last"] = arg
    elif cmd == "stop":
        idle = float(arg) if arg else 0  # swayidle: Leerlaufzeit vor der Sperre nicht mitzaehlen
        finish(d, now - idle)
    elif cmd == "discard":
        d["running"] = None
    elif cmd == "undo":
        if d["sessions"] and not d["running"]:
            d["sessions"].pop()
    elif cmd == "add":
        if arg in names:
            names[arg]["archived"] = False
        elif arg:
            d["topics"].append({"name": arg})
    elif cmd == "archive":
        if arg in names:
            if d["running"] and d["running"]["topic"] == arg:
                finish(d, now)
            names[arg]["archived"] = True  # Stunden bleiben erhalten


def selftest():
    ts = lambda *a: datetime(*a).timestamp()
    # Mitternacht wird auf zwei Tage aufgeteilt
    days = per_day([{"start": ts(2026, 9, 21, 23, 30), "end": ts(2026, 9, 22, 0, 45)}])
    assert days == {date(2026, 9, 21): 1800, date(2026, 9, 22): 2700}, days
    # Streak zaehlt ab gestern, solange heute die Schwelle noch nicht erreicht ist
    days = {date(2026, 9, 22): 1800, date(2026, 9, 23): 3600, date(2026, 9, 24): 100}
    assert streak(days, date(2026, 9, 24)) == 2
    assert streak(days, date(2026, 9, 25)) == 0
    days[date(2026, 9, 24)] = 1800
    assert streak(days, date(2026, 9, 24)) == 3
    # Woche beginnt Montag; Toggle / nur ein Timer / idle / undo / archive
    d = {"topics": [{"name": "A"}, {"name": "B"}], "sessions": [], "running": None, "last": None}
    command(d, "toggle", "A", ts(2026, 9, 20, 10))  # Sonntag -> letzte Woche
    command(d, "start", "B", ts(2026, 9, 20, 11))
    assert d["running"]["topic"] == "B" and d["sessions"][-1]["topic"] == "A"
    command(d, "stop", "600", ts(2026, 9, 20, 12))
    assert d["sessions"][-1]["end"] == ts(2026, 9, 20, 11, 50)
    command(d, "toggle", "A", ts(2026, 9, 21, 9))  # Montag
    command(d, "toggle", "A", ts(2026, 9, 21, 10))
    s = stats(d, ts(2026, 9, 21, 12))
    assert s["topic"] == "A" and s["week"] == "1h 00m" and s["total"] == "2h 00m", s
    command(d, "undo", None, 0)
    assert stats(d, ts(2026, 9, 21, 12))["total"] == "1h 00m"
    command(d, "archive", "B", 0)
    assert [t["name"] for t in stats(d, 0)["topics"]] == ["A"]
    assert [level(x) for x in (0, 60, 1800, 3600, 7200)] == [0, 1, 2, 3, 4]
    heat = stats(d, ts(2026, 9, 21, 12))["heat"]
    assert len(heat) == HEAT_WEEKS and heat[-2][6]["l"] == 3 and heat[-1][0]["l"] == 0 and heat[-1][1]["l"] == "future", heat[-1]
    d["sessions"] = [{"topic": "A", "start": ts(2026, 9, 21, 9), "end": ts(2026, 9, 21, 9, 15)}]
    assert stats(d, ts(2026, 9, 21, 12))["suit"] == 50  # 15 von 30 Minuten
    d["sessions"][0]["end"] = ts(2026, 9, 21, 10)
    assert stats(d, ts(2026, 9, 21, 12))["suit"] == 100  # gedeckelt
    print("selftest ok")


if __name__ == "__main__":
    os.makedirs(DIR, exist_ok=True)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "watch"
    if cmd == "watch":
        watch()
    elif cmd == "selftest":
        selftest()
    else:
        arg = sys.argv[2].strip() if len(sys.argv) > 2 else None
        if cmd == "stop" and arg == "--idle":
            arg = sys.argv[3]
        with locked():
            d = load()
            now = time.time()
            recover(d, now)
            command(d, cmd, arg, now)
            save(d)
            beat()
