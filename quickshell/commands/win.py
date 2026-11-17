#!/usr/bin/python3
"""Fenster-Befehle der Befehlsleiste (quickshell/CommandBar.qml, commands.json).

win.py split [a,s,… [> ziel]]   Fenster nebeneinander als ein geteilter Tab
                                (ohne Liste: alle; ab 4 Fenstern zwei Reihen),
                                mit > ziel auf diesen Workspace (Fokus geht mit)
win.py reset                    alle Teilungen im Workspace aufloesen (Tabs)
win.py close a,s,…              diese Fenster schliessen
win.py only a                   alle ausser a schliessen
win.py full [a]                 Vollbild an/aus (ohne Code: aktives Fenster)
win.py open name [> ziel]       App (Desktop-Eintrag) starten, mit Ziel dort
win.py selftest

Codes = Codes der Tabs (a s d … aa), Liste mit Komma. Ziel = [Bildschirm] Workspace
wie in der Leiste, ohne Fenstercode: a j = A7, f = Workspace 4 hier.
Stand kommt von der Leiste als BAR_CONTEXT (JSON: here, con, tabs, grid), also
genau das, was beim Tippen zu sehen war. Ausgabe = Meldung fuer die Leiste.
"""
import configparser
import glob
import json
import os
import re
import subprocess
import sys

KEYS = "asdfghjklö"
TMP = "99:umbau"  # Hilfs-Workspace, collapse() in sidebar.py laesst ihn in Ruhe
MARK = "_wsplit"
APP_DIRS = [os.path.expanduser("~/.local/share/applications"), "/usr/share/applications",
            "/var/lib/snapd/desktop/applications", "/var/lib/flatpak/exports/share/applications"]


class Fail(Exception):
    pass


def split_args(args):
    """["a,s", ">", "a", "j"] -> ("a,s", "a j"); auch "a,s>a j" oder ohne Ziel."""
    text = " ".join(args)
    head, _, target = text.partition(">")
    return head.strip(), target.strip()


def ids(ctx, codes):
    """'a, s,d' -> [con_id …] in Reihenfolge der Tabs der Eingabe."""
    tabs = {t["code"]: t["id"] for t in ctx["tabs"]}
    out = []
    for c in filter(None, re.split(r"[\s,]+", codes)):
        if c not in tabs:
            raise Fail(f"kein Fenster mit Code {c}")
        out.append(tabs[c])
    return out


def target(ctx, text):
    """'a j' -> Feld aus grid ({name, output, …}). ponytail: Teilmenge der
    Grammatik aus nav.js (immer mit Workspace: parse() verschluckt leere Teile),
    node gibt es im sway-PATH nicht."""
    m = re.fullmatch(r"(?:([asd]) )?([" + KEYS + r"])", " ".join(text.split()))
    if not m:
        raise Fail(f"Ziel {text!r} versteht nur [a|s|d] a…ö, z. B. a j = A7")
    screen = m[1] or ctx["here"]
    cell = next((c for c in ctx["grid"] if c["letter"] == screen and
                 c["number"] == KEYS.index(m[2]) + 1), None)
    if not cell:
        raise Fail(f"Bildschirm {screen.upper()} gibt es gerade nicht")
    return cell


def here(ctx):
    return next(c for c in ctx["grid"] if c["letter"] == ctx["here"] and c["visible"])


def chain(ws):
    """ws[1:] der Reihe nach hinter ws[0] in dessen Container haengen."""
    cmds = []
    for prev, w in zip(ws, ws[1:]):
        cmds += [f"[con_id={prev}] mark --replace {MARK}", f"[con_id={w}] move container to mark {MARK}"]
    return cmds


def row(ws):
    """Fenster ws als eine Reihe: ws[0] in einen splith-Container, Rest dahinter."""
    return [f"[con_id={ws[0]}] focus", "split horizontal"] + chain(ws)


def plan_split(ws, home, dest=None):
    """sway-Befehle: Fenster ws erst auf oberste Ebene (ueber TMP und zurueck bzw.
    gleich nach dest), dann als ein geteilter Container, ab 4 in zwei Reihen.
    sway: split auf einem Einzelkind aendert nur das Layout seines Containers,
    deshalb jede Reihe erst als eigener Tab, dann splitv um Reihe 1 und Reihe 2
    hinein (move to mark auf einem Container = hinein, auf einem Fenster = dahinter)."""
    if len(ws) < 2:
        raise Fail("split braucht mindestens 2 Fenster")
    to = dest or home
    cmds = []
    if dest:
        cmds.append(f'workspace "{dest["name"]}" output "{dest["output"]}"')  # dort anlegen
    else:
        cmds += [f'[con_id={w}] move container to workspace "{TMP}"' for w in ws]
    cmds += [f'[con_id={w}] move container to workspace "{to["name"]}"' for w in ws]
    rows = [ws] if len(ws) <= 3 else [ws[:(len(ws) + 1) // 2], ws[(len(ws) + 1) // 2:]]
    for r in rows:
        cmds += row(r)
    if len(rows) == 2:
        cmds += [f"[con_id={ws[0]}] focus", "focus parent", "split vertical", "focus parent",
                 f"mark --replace {MARK}", f"[con_id={rows[1][0]}] focus", "focus parent",
                 f"move container to mark {MARK}"]
    return cmds + [f"unmark {MARK}", f"[con_id={ws[0]}] focus"]


def plan_reset(ws, home, active):
    """Alle Fenster ueber TMP raus und zurueck (= oberste Ebene, Reihenfolge per
    Marke: sway sortiert sonst hinter das fokussierte Fenster), dann Tabs."""
    cmds = [f'[con_id={w}] move container to workspace "{TMP}"' for w in ws]
    cmds += [f'[con_id={ws[0]}] move container to workspace "{home["name"]}"'] + chain(ws)
    cmds.append(f"unmark {MARK}")
    keep = active if active in ws else ws[0]
    return cmds + [f"[con_id={ws[0]}] focus", "layout tabbed", f"[con_id={keep}] focus"]


def desktop(query):
    """-> (Kennung, Name) des besten Desktop-Eintrags: genau, dann Anfang, dann enthalten."""
    q, found = query.lower(), []
    for d in APP_DIRS:
        for f in glob.glob(os.path.join(d, "*.desktop")):
            p = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                p.read(f, encoding="utf-8")
                name = p["Desktop Entry"].get("Name", "")
            except (configparser.Error, KeyError, UnicodeDecodeError):
                continue
            did = os.path.basename(f)[:-8]
            keys = [did.lower(), name.lower()]
            rank = 0 if q in keys else 1 if any(k.startswith(q) for k in keys) else \
                2 if any(q in k for k in keys) else None
            if rank is not None:
                found.append((rank, len(did), did, name or did))
    if not found:
        raise Fail(f"keine App zu {query!r}")
    return min(found)[2:]


def plan_open(app, dest):
    did, _ = app
    if not re.fullmatch(r"[\w.+-]+", did):
        raise Fail(f"Kennung {did!r} sieht falsch aus")
    pre = [f'workspace "{dest["name"]}" output "{dest["output"]}"',
           f'workspace --no-auto-back-and-forth "{dest["name"]}"'] if dest else []
    # ponytail: das Fenster landet, wo beim Aufgehen der Fokus ist; wer vorher
    # weiterspringt, bekommt es dort
    return pre + [f"exec gtk-launch {did}"]


def sway(cmds):
    r = subprocess.run(["swaymsg", "-r", "; ".join(cmds)], capture_output=True, text=True)
    errs = [x.get("error", "?") for x in json.loads(r.stdout or "[]") if not x.get("success")]
    if r.returncode or errs:
        raise Fail("sway: " + ("; ".join(errs) or r.stderr.strip()))


def label(cell):
    return cell["letter"].upper() + str(cell["number"] % 10)


def main(cmd, args):
    ctx = json.loads(os.environ.get("BAR_CONTEXT") or "{}")
    if not ctx.get("grid"):
        raise Fail("nur aus der Befehlsleiste aufrufen (BAR_CONTEXT fehlt)")
    head, dest = split_args(args)
    home = here(ctx)
    dest = target(ctx, dest) if dest else None
    if cmd == "split":
        ws = ids(ctx, head) if head else [t["id"] for t in ctx["tabs"]]
        sway(plan_split(ws, home, dest))
        return f"{len(ws)} Fenster geteilt" + (f" auf {label(dest)}" if dest else "")
    if cmd == "reset":
        ws = [t["id"] for t in ctx["tabs"]]
        if not ws:
            return "Workspace ist leer"
        sway(plan_reset(ws, home, ctx.get("con")))
        return "wieder Tabs"
    if cmd in ("close", "only"):
        ws = ids(ctx, head)
        if not ws:
            raise Fail(f"{cmd} braucht Codes, z. B. #{cmd} a,s")
        if cmd == "only":
            ws = [t["id"] for t in ctx["tabs"] if t["id"] not in ws]
        if ws:
            sway([f"[con_id={w}] kill" for w in ws])
        return f"{len(ws)} Fenster geschlossen"
    if cmd == "full":
        ws = ids(ctx, head) or [ctx.get("con")]
        if not ws[0]:
            raise Fail("kein aktives Fenster")
        sway([f"[con_id={ws[0]}] focus", f"[con_id={ws[0]}] fullscreen toggle"])
        return ""
    if cmd == "open":
        if not head:
            raise Fail("open braucht einen App-Namen, z. B. #open firefox")
        app = desktop(head)
        sway(plan_open(app, dest))
        return f"{app[1]} startet" + (f" auf {label(dest)}" if dest else "")
    raise Fail(f"unbekannt: {cmd}")


def selftest():
    grid = [{"letter": l, "number": n, "name": f"{b + n}:{l}{n}", "output": o, "visible": n == v}
            for l, b, o, v in [("a", 10, "HDMI-A-1", 2), ("d", 30, "eDP-1", 1)] for n in range(1, 11)]
    ctx = {"here": "d", "con": 7, "grid": grid,
           "tabs": [{"code": c, "id": i} for c, i in [("a", 5), ("s", 6), ("d", 7), ("f", 8), ("aa", 9)]]}
    assert split_args(["a,s", ">", "a", "j"]) == ("a,s", "a j")
    assert split_args(["a,s>a", "j"]) == ("a,s", "a j") and split_args([]) == ("", "")
    assert ids(ctx, "a, s,aa") == [5, 6, 9] and ids(ctx, "") == []
    for bad in ["x", "a,ss"]:
        try:
            ids(ctx, bad); raise AssertionError(bad)
        except Fail:
            pass
    assert target(ctx, "a j")["name"] == "17:a7"
    assert target(ctx, "f")["name"] == "34:d4"    # ohne Bildschirm: hier
    for bad in ["", "a j a", "x", "s f", "aj"]:    # s gibt es im Test nicht
        try:
            target(ctx, bad); raise AssertionError(bad)
        except Fail:
            pass
    home = here(ctx)
    two = plan_split([5, 6], home)
    assert two[:2] == ['[con_id=5] move container to workspace "99:umbau"',
                       '[con_id=6] move container to workspace "99:umbau"']
    assert two[2:] == ['[con_id=5] move container to workspace "31:d1"',
                       '[con_id=6] move container to workspace "31:d1"',
                       "[con_id=5] focus", "split horizontal",
                       "[con_id=5] mark --replace _wsplit", "[con_id=6] move container to mark _wsplit",
                       "unmark _wsplit", "[con_id=5] focus"]
    four = plan_split([5, 6, 7, 8], home)
    assert four.count("split horizontal") == 2 and four.count("split vertical") == 1
    assert four.index("split vertical") > four.index("[con_id=8] move container to mark _wsplit")
    assert four[-3] == "move container to mark _wsplit"
    far = plan_split([5, 6], home, target(ctx, "a j"))
    assert far[0] == 'workspace "17:a7" output "HDMI-A-1"' and "99:umbau" not in " ".join(far)
    try:
        plan_split([5], home); raise AssertionError("ein Fenster")
    except Fail:
        pass
    reset = plan_reset([5, 6], home, 6)
    assert reset[2:5] == ['[con_id=5] move container to workspace "31:d1"',
                          "[con_id=5] mark --replace _wsplit", "[con_id=6] move container to mark _wsplit"]
    assert reset[-3:] == ["[con_id=5] focus", "layout tabbed", "[con_id=6] focus"]
    assert plan_reset([5, 6], home, 99)[-1] == "[con_id=5] focus"
    assert plan_open(("firefox_firefox", "Firefox"), target(ctx, "a j")) == [
        'workspace "17:a7" output "HDMI-A-1"', 'workspace --no-auto-back-and-forth "17:a7"',
        "exec gtk-launch firefox_firefox"]
    try:
        plan_open(("x; rm", "X"), None); raise AssertionError("Kennung")
    except Fail:
        pass
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["selftest"]:
        selftest()
        sys.exit(0)
    try:
        msg = main(sys.argv[1], sys.argv[2:])
    except Fail as e:
        sys.exit(str(e))
    if msg:
        print(msg)
