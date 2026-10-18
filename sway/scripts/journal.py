#!/usr/bin/python3
"""Trading-Journal (Super+Ctrl+j): Screenshot vom fokussierten Monitor, dann
das eww-Panel "journal" auf diesem Monitor (ein Formular statt Abfragen).

Panel: "+ <letztes Setup>" (nur Timeframe/Ergebnis/R) oder "Neu" mit
live/backtest, Datum TT.MM.JJJJ, Entry-Zeit NY HH:MM (Session wird berechnet),
Symbol, Long/Short (Pflicht, nicht vorbelegt), Model (Ordner in
Trading/TradingModels/), Timeframe, Ergebnis, R (optional). Vorbelegt: live, heute, jetzt, zuletzt benutztes Symbol/Model/TF.
Speichern -> Notiz per ask.sh (rofi, Esc = ohne Notiz) -> Datei. Freitext geht
nie durch eww (ungeschuetzte Shell-Zeile), das Panel schickt nur Indizes und
per Regex gepruefte Felder.

Eine Datei je Setup:
  Trading/journaling/{live-trades,backtesting}/JJJJ/MM/TT/<datum> <HHMM> <Symbol> <Long|Short> <Model>.md
Bilder daneben (<erfasst>_HHMMSS.png), je Screenshot ein Abschnitt
"## <TF> · erfasst TT.MM.JJJJ HH:MM". Frontmatter mit Properties und Tags
(journal/<typ>, session/…, direction/…, model/…, instrument/…, result/…).
Letztes Setup + letzte Wahl in ~/.local/state/journal-last.json, offener
Screenshot in $XDG_RUNTIME_DIR/journal-pending.json.
Aufruf: journal.py            Screenshot + Panel (nochmal = abbrechen)
        journal.py save MODUS TYP DATUM ZEIT SYM RICHTUNG MODEL TF ERGEBNIS [R]
        journal.py cancel | selftest
"""
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime

from market import NY, SESSIONS

VAULT = os.path.expanduser("~/Documents/Obsidian Vault")
ROOT = os.path.join(VAULT, "Trading", "journaling")
MODELS = os.path.join(VAULT, "Trading", "TradingModels")
FOLDER = {"live": "live-trades", "backtest": "backtesting"}
SYMBOLS = ["NQ1!", "ES1!"]
TFS = ["1m", "3m", "5m", "15m", "1h", "4h", "D"]
RESULTS = ["Win", "Loss", "BE", "offen"]
NO_MODEL = "kein Model"
DIRS = ["Long", "Short"]
STATE = os.path.expanduser("~/.local/state/journal-last.json")
ASK = os.path.expanduser("~/.config/sway/scripts/ask.sh")
ORDER = ["date", "time_ny", "session", "type", "instrument", "direction", "model", "timeframes",
         "result", "r", "captured", "tags"]


class Abort(Exception):
    pass


def ask(title):
    """Eingabezeile (rofi); Esc -> Abort."""
    p = subprocess.run([ASK, title], capture_output=True, text=True)
    if p.returncode != 0:
        raise Abort
    return p.stdout.strip()


def parse_date(s):
    try:
        return datetime.strptime(s.strip(), "%d.%m.%Y").date()
    except ValueError:
        return None


def parse_time(s):
    m = re.fullmatch(r"(\d{1,2}):?(\d{2})", s.strip())
    if m and int(m[1]) < 24 and int(m[2]) < 60:
        return f"{int(m[1]):02d}:{m[2]}"
    return None


def parse_r(s):
    """Optionales R: '' -> '', '2' / '-1' / '0,5' -> Zahl als Text, sonst None."""
    s = s.strip().replace(",", ".")
    if not s:
        return ""
    try:
        return f"{float(s):g}"
    except ValueError:
        return None


def session(hhmm):
    h, m = map(int, hhmm.split(":"))
    t = h * 60 + m
    return next((n for n, a, b in SESSIONS if a <= t < b), "ausserhalb")


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def first(last, items):
    """Zuletzt benutzten Eintrag nach oben."""
    return [last] + [i for i in items if i != last] if last else items


def models():
    try:
        return sorted(d for d in os.listdir(MODELS) if os.path.isdir(os.path.join(MODELS, d)))
    except OSError:
        return []


# --- Frontmatter: einfache key: value-Zeilen, Listen inline [a, b] oder als "  - x"
#     (so schreibt Obsidian sie nach einer Aenderung in den Properties)

def split(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return {}, text
    fm, key = {}, None
    for line in m[1].splitlines():
        if line.startswith("  - ") and key:
            fm[key].append(line[4:].strip().strip('"'))
        elif ":" in line:
            key, v = line.split(":", 1)
            v = v.strip()
            if v.startswith("[") and v.endswith("]"):
                fm[key] = [x.strip().strip('"') for x in v[1:-1].split(",") if x.strip()]
            elif v == "":
                fm[key] = []
            else:
                fm[key] = v.strip('"')
    return fm, text[m.end():]


def join(fm, body):
    out = ["---"]
    for k in ORDER + [k for k in fm if k not in ORDER]:
        if k not in fm or fm[k] == "":
            continue
        v = fm[k]
        if isinstance(v, list):
            out.append(f"{k}:")
            out += [f"  - {x}" for x in v]
        else:
            out.append(f'{k}: "{v}"' if re.search(r"[:#!\[\]]", v) else f"{k}: {v}")
    return "\n".join(out) + "\n---\n" + body


def set_result(fm, result, r):
    fm["result"] = result.lower()
    fm["r"] = r
    fm["tags"] = [t for t in fm.get("tags", []) if not t.startswith("result/")] + [f"result/{slug(result)}"]


def section(tf, now, note, img):
    return f"\n## {tf} · erfasst {now:%d.%m.%Y %H:%M}\n\n" + (f"{note}\n\n" if note else "") + f"![[{img}]]\n"


RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
PENDING = os.path.join(RUN, "journal-pending.json")


def eww(*args):
    # stdout=DEVNULL: sonst erbt ein frisch gestarteter Daemon die Pipe und es haengt
    subprocess.run(["eww", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def cancel():
    eww("close", "journal")
    p = load(PENDING)
    for f in (p.get("tmp"), PENDING):
        if f and os.path.exists(f):
            os.remove(f)


def start():
    if os.path.exists(PENDING):  # Panel offen -> zweiter Druck bricht ab
        return cancel()
    now = datetime.now()
    out = subprocess.run(["swaymsg", "-t", "get_outputs"], capture_output=True, text=True).stdout
    mon = next(o["name"] for o in json.loads(out) if o.get("focused"))
    img = f"{now:%Y-%m-%d_%H%M%S}.png"
    tmp = os.path.join(RUN, "journal-" + img)
    subprocess.run(["grim", "-o", mon, tmp], check=True)  # vor dem Panel, sonst ist es mit drauf
    st = load(STATE)
    last = st.get("path") if st.get("path") and os.path.exists(st["path"]) else ""
    last_open = False
    if last:
        with open(last) as f:
            last_open = split(f.read())[0].get("result", "offen") == "offen"
    syms = first(st.get("symbol"), SYMBOLS)
    mods = first(st.get("model"), models() + [NO_MODEL])
    with open(PENDING, "w") as f:
        json.dump({"tmp": tmp, "img": img, "now": now.isoformat(), "symbols": syms, "models": mods}, f)
    opts = {"last": os.path.basename(last)[:-3] if last else "", "last_open": last_open,
            "symbols": [{"v": i, "l": x} for i, x in enumerate(syms)],
            "models": [{"v": i, "l": x} for i, x in enumerate(mods)],
            "tfs": [{"v": x, "l": x} for x in TFS],
            "results": [{"v": x.lower(), "l": x} for x in RESULTS],
            "types": [{"v": "live", "l": "Live"}, {"v": "backtest", "l": "Backtest"}],
            "dirs": [{"v": x.lower(), "l": x} for x in DIRS]}
    eww("update", "jr_opts=" + json.dumps(opts), "jr_mode=" + ("add" if last else "new"),
        "jr_type=live", f"jr_date={now:%d.%m.%Y}", f"jr_time={datetime.now(NY):%H:%M}",
        "jr_sym=0", "jr_dir=", "jr_model=0", "jr_tf=" + st.get("tf", "5m"), "jr_res=offen", "jr_r=", "jr_err=")
    eww("open", "journal", "--screen", mon)


def build(mode, typ, date, hhmm, sym, direction, model, tf, res, r, p, st):
    """Werte aus dem Panel -> (Pfad, Frontmatter, Body) oder Fehlertext."""
    if tf not in TFS:
        return "Timeframe waehlen"
    r = parse_r(r)
    if r is None:
        return "R ist keine Zahl"
    res = res.capitalize() if res.capitalize() in RESULTS else "offen"
    if mode == "add":
        path = st.get("path")
        if not path or not os.path.exists(path):
            return "Letztes Setup nicht gefunden"
        with open(path) as f:
            fm, body = split(f.read())
        if fm.get("result", "offen") == "offen" and res != "offen":
            set_result(fm, res, r)
        tfs = fm.get("timeframes") or []
        tfs = tfs if isinstance(tfs, list) else [tfs]
        fm["timeframes"] = tfs + ([] if tf in tfs else [tf])
        return path, fm, body
    d, hhmm = parse_date(date), parse_time(hhmm)
    if not d:
        return "Datum TT.MM.JJJJ pruefen"
    if not hhmm:
        return "Zeit HH:MM pruefen"
    typ = typ if typ in FOLDER else "live"
    direction = direction.capitalize()
    if direction not in DIRS:
        return "Long oder Short waehlen"
    try:
        sym, model = p["symbols"][int(sym)], p["models"][int(model)]
    except (ValueError, IndexError, KeyError):
        return "Symbol/Model waehlen"
    name = re.sub(r'[*"\\/<>:|?^\[\]#]', "", f"{d:%Y-%m-%d} {hhmm.replace(':', '')} {sym} {direction} {model}")
    folder = os.path.join(ROOT, FOLDER[typ], f"{d:%Y}", f"{d:%m}", f"{d:%d}")
    path, n = os.path.join(folder, name + ".md"), 2
    while os.path.exists(path):
        path, n = os.path.join(folder, f"{name} {n}.md"), n + 1
    ses = session(hhmm)
    fm = {"date": f"{d:%Y-%m-%d}", "time_ny": hhmm, "session": ses, "type": typ,
          "instrument": sym, "direction": direction.lower(), "model": model, "timeframes": [tf],
          "captured": p["now"][:10],
          "tags": ["trading", "journal", f"journal/{typ}", f"session/{slug(ses)}", f"direction/{direction.lower()}",
                   f"model/{slug(model)}", f"instrument/{slug(sym)}"]}
    set_result(fm, res, r)
    st.update(symbol=sym, model=model)
    return path, fm, f"\n# {d:%d.%m.%Y} {hhmm} NY – {sym} {direction} {model}\n"


def save(args):
    p, st = load(PENDING), load(STATE)
    if not p or not os.path.exists(p["tmp"]):
        return cancel()
    args = (args + [""] * 10)[:10]
    tf = args[7]
    out = build(*args, p, st)
    if isinstance(out, str):
        return eww("update", "jr_err=" + out)
    path, fm, body = out
    eww("close", "journal")
    try:
        note = ask("NOTIZ (optional)")
    except Abort:
        note = ""
    now = datetime.fromisoformat(p["now"])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    # move statt replace: $XDG_RUNTIME_DIR ist tmpfs, os.replace scheitert dann (EXDEV)
    img, n = p["img"], 2
    while os.path.exists(os.path.join(os.path.dirname(path), img)):  # zwei Bilder in einer Sekunde
        img, n = p["img"][:-4] + f"_{n}.png", n + 1
    shutil.move(p["tmp"], os.path.join(os.path.dirname(path), img))
    os.remove(PENDING)
    with open(path + ".tmp", "w") as f:
        f.write(join(fm, body.rstrip("\n") + "\n" + section(tf, now, note, img)))
    os.replace(path + ".tmp", path)
    st.update(path=path, tf=tf)
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        json.dump(st, f)
    subprocess.run(["notify-send", "JOURNAL", f"{os.path.basename(path)[:-3]} · {fm['session']} · {tf} gespeichert"])


def selftest():
    assert parse_date("07.01.2025").isoformat() == "2025-01-07"
    assert parse_date("31.02.2025") is None and parse_date("7.1.25") is None
    assert parse_time("9:56") == "09:56" and parse_time("0956") == "09:56"
    assert parse_time("24:00") is None and parse_time("x") is None
    assert parse_r("") == "" and parse_r("0,5") == "0.5" and parse_r("-1") == "-1"
    assert parse_r("abc") is None
    assert session("09:56") == "NY AM" and session("21:00") == "ASIA"
    assert session("12:00") == "ausserhalb" and session("13:30") == "NY PM"
    assert slug("NQ1!") == "nq1" and slug("NY AM") == "ny-am" and slug(NO_MODEL) == "kein-model"
    assert first("ES1!", SYMBOLS) == ["ES1!", "NQ1!"] and first(None, SYMBOLS) == SYMBOLS
    fm = {"date": "2025-01-07", "time_ny": "09:56", "instrument": "NQ1!", "timeframes": ["5m"],
          "tags": ["trading", "result/offen"]}
    set_result(fm, "Win", "2")
    text = join(fm, "\n# T\n")
    assert 'time_ny: "09:56"' in text and 'instrument: "NQ1!"' in text and "  - result/win" in text
    assert "result/offen" not in text and "r: 2" in text
    assert split(text) == (fm, "\n# T\n")
    # Obsidian-Schreibweise und Inline-Listen werden gelesen
    assert split("---\ntags: [a, b]\nx:\n  - 1\n---\nB")[0] == {"tags": ["a", "b"], "x": ["1"]}
    assert "## 1m · erfasst 18.10.2026 16:34\n\n![[a.png]]" in section("1m", datetime(2026, 10, 18, 16, 34), "", "a.png")
    # Panel-Werte -> Datei
    global ROOT
    import tempfile
    ROOT = tempfile.mkdtemp()
    p, st = {"symbols": ["ES1!", "NQ1!"], "models": ["Sakura", NO_MODEL], "now": "2026-10-18T16:34:11"}, {}
    path, fm, body = build("new", "backtest", "07.01.2025", "9:56", "1", "short", "0", "5m", "offen", "", p, st)
    assert path == f"{ROOT}/backtesting/2025/01/07/2025-01-07 0956 NQ1! Short Sakura.md", path
    assert fm["session"] == "NY AM" and fm["result"] == "offen" and "result/offen" in fm["tags"]
    assert st == {"symbol": "NQ1!", "model": "Sakura"} and "# 07.01.2025 09:56 NY – NQ1! Short Sakura" in body
    assert fm["direction"] == "short" and "direction/short" in fm["tags"]
    assert build("new", "live", "31.02.2025", "09:56", "0", "long", "0", "5m", "win", "", p, {}).startswith("Datum")
    assert build("new", "live", "07.01.2025", "09:56", "0", "long", "0", "5m", "win", "x", p, {}) == "R ist keine Zahl"
    assert build("new", "live", "07.01.2025", "09:56", "0", "", "0", "5m", "win", "", p, {}) == "Long oder Short waehlen"
    os.makedirs(os.path.dirname(path))
    with open(path, "w") as f:
        f.write(join(fm, body))
    _, fm2, _ = build("add", "", "", "", "", "", "", "1m", "loss", "-1", p, {"path": path})
    assert fm2["timeframes"] == ["5m", "1m"] and fm2["result"] == "loss" and fm2["r"] == "-1"
    print("ok")


if __name__ == "__main__":
    cmd = sys.argv[1:2]
    if cmd == ["selftest"]:
        selftest()
    elif cmd == ["save"]:
        save(sys.argv[2:])
    elif cmd == ["cancel"]:
        cancel()
    else:
        start()
