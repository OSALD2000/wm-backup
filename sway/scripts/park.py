#!/usr/bin/python3
"""Session parken (Super+Ctrl+p) / zurueckholen (Super+Ctrl+Shift+p).

park.py save     Name per ask.sh, alle Fenster aller Monitore (ohne Scratchpad)
                 merken und auf 36:o6 schieben.
park.py restore  Session per ask.sh-Liste waehlen, jedes noch offene Fenster
                 zurueck auf seinen alten Workspace; die Session ist danach weg.
Gespeichert in $XDG_RUNTIME_DIR/parked.json ({name: {con_id: workspace}}):
con_ids gelten nur bis zum Neustart von sway, danach waere die Datei wertlos.
Fehlt der alte Monitor, zieht collapse() in sidebar.py den Workspace um.
Aufruf: park.py save|restore|selftest
"""
import json
import os
import subprocess
import sys

PARK = "36:o6"
DB = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "parked.json")
ASK = os.path.expanduser("~/.config/sway/scripts/ask.sh")


def windows(tree, skip=("__i3_scratch", PARK)):
    """-> {con_id: workspace} fuer jedes Fenster ausserhalb der Workspaces skip."""
    out = {}

    def walk(node, ws):
        if node.get("type") == "workspace":
            ws = node["name"]
        kids = node.get("nodes", []) + node.get("floating_nodes", [])
        if not kids and node.get("type") in ("con", "floating_con") and ws:
            if ws not in skip:
                out[str(node["id"])] = ws
        for k in kids:
            walk(k, ws)

    walk(tree, None)
    return out


def load():
    try:
        with open(DB) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def store(db):
    tmp = DB + ".tmp"
    with open(tmp, "w") as f:
        json.dump(db, f)
    os.replace(tmp, DB)


def ask(title, options=None):
    """-> Eingabe aus ask.sh, None bei Esc/leer."""
    args = [ASK, title] + (["-"] if options is not None else [])
    r = subprocess.run(args, input="\n".join(options or []), capture_output=True, text=True)
    return r.stdout.strip() or None


def sway(cmds):
    if cmds:
        subprocess.run(["swaymsg", "; ".join(cmds)], stdout=subprocess.DEVNULL)


def notify(msg):
    subprocess.run(["notify-send", "SESSION", msg])


def save():
    tree = json.loads(subprocess.check_output(["swaymsg", "-t", "get_tree"]))
    wins = windows(tree)
    if not wins:
        return notify("keine Fenster zum Parken")
    name = ask("SESSION PARKEN")
    if not name:
        return
    db = load()
    db.setdefault(name, {}).update(wins)  # gleicher Name = Session erweitern
    store(db)
    sway([f'[con_id={c}] move container to workspace "{PARK}"' for c in wins]
         + [f"workspace {PARK}"])
    notify(f"{name}: {len(wins)} Fenster auf o6")


def restore():
    db = load()
    if not db:
        return notify("keine geparkte Session")
    name = ask("SESSION ZURUECK", list(db))
    if name not in db:
        return
    wins = db.pop(name)
    store(db)
    # geschlossene Fenster weglassen, sonst bricht swaymsg die Kette ab
    alive = windows(json.loads(subprocess.check_output(["swaymsg", "-t", "get_tree"])), ())
    wins = {c: ws for c, ws in wins.items() if c in alive}
    sway([f'[con_id={c}] move container to workspace "{ws}"' for c, ws in wins.items()])
    notify(f"{name}: {len(wins)} Fenster zurueck")


def selftest():
    win = lambda i: {"id": i, "type": "con", "nodes": []}
    ws = lambda n, *k: {"type": "workspace", "name": n, "nodes": list(k)}
    tree = {"type": "root", "nodes": [{"type": "output", "nodes": [
        ws("__i3_scratch", win(1)), ws(PARK, win(2)),
        ws("31:o1", win(3), {"id": 9, "type": "con", "nodes": [win(4)]}),
        {**ws("33:o3"), "floating_nodes": [{"id": 5, "type": "floating_con", "nodes": []}]}]}]}
    assert windows(tree) == {"3": "31:o1", "4": "31:o1", "5": "33:o3"}, windows(tree)
    assert set(windows(tree, ())) == {"1", "2", "3", "4", "5"}
    print("ok")


if __name__ == "__main__":
    {"save": save, "restore": restore, "selftest": selftest}[sys.argv[1]]()
