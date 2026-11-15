#!/usr/bin/python3
"""Daten fuer die Befehlsleiste (Quickshell, quickshell/CommandBar.qml) und
das Vorschau-Raster: Fenster des sichtbaren Workspaces je Monitor (Tabs der
Leiste, Baum-Reihenfolge) und alle Workspaces samt Fenstern ("grid").
Super+q / Super+Ctrl+q laufen mit next/prev genau durch die Tabs im Kreis und
verlassen den Monitor nie (sways `focus next` springt am Ende raus).

Aufruf: sidebar.py watch       eww (HUD) und Quickshell neu starten, dann bei
                               jeder Aenderung STATE schreiben, Quickshell liest
                               die Datei. Laeuft per exec_always, ein neuer
                               Start beendet den alten (PIDFILE).
        sidebar.py next|prev   naechstes/vorheriges Fenster der Tabs fokussieren
        sidebar.py nudge ID up|down  Fenster in den Tabs verschieben (Mausrad)
        sidebar.py workspaces apply go|move OUTPUT N CON
                               Workspace hin / Fenster CON dorthin, ruft die
                               Befehlsleiste (Super+f)
        sidebar.py selftest
"""
import configparser
import glob
import json
import os
import re
import subprocess
import sys
import time

APP_DIRS = [os.path.expanduser("~/.local/share/applications"),
            "/usr/share/applications",
            "/var/lib/snapd/desktop/applications",
            "/var/lib/flatpak/exports/share/applications"]
FALLBACK = "application-x-executable"  # Icon fuer Apps ohne .desktop-Eintrag
# Icons selbst als Datei suchen und in eww fest auf 16px skalieren: per
# Icon-Name nimmt GTK die Groesse, die das Theme gerade hat -> ungleich gross.
# Reihenfolge = Vorrang; die Themes nur fuer den FALLBACK.
ICON_DIRS = [os.path.expanduser("~/.local/share/icons"), "/usr/share/icons/hicolor",
             "/usr/share/pixmaps", "/var/lib/snapd/desktop/icons",
             "/var/lib/flatpak/exports/share/icons", "/usr/share/icons/Yaru",
             "/usr/share/icons/Adwaita", "/usr/share/icons/HighContrast"]
RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
PIDFILE = os.path.join(RUN, "eww-sidebar.pid")
STATE = os.path.join(RUN, "sidebar.json")  # {"wins": {output: [...]}, "grid": [...]} fuer Quickshell
QS = os.path.expanduser("~/.local/bin/quickshell")
# Vorschaubilder fuer das Vorschau-Raster (Super+Tab, quickshell/Overview.qml).
# Sway kann nur Monitore abfotografieren, und Fenster hinter Tabs/auf
# unsichtbaren Workspaces malt es gar nicht -> der Watcher fotografiert jedes
# Fenster, solange es sichtbar ist; das Raster zeigt den letzten Stand. In XDG_RUNTIME_DIR (tmpfs, nur fuer Osa lesbar), weg nach
# dem Abmelden. ponytail: alte Bilder geschlossener Fenster bleiben bis dahin.
SHOTS = os.path.join(RUN, "win-shots")
SHOT_EVERY = 3  # Sekunden, hoechstens so oft je Fenster
OVERVIEW = os.path.join(RUN, "overview.open")  # existiert = Raster offen, snap() pausiert
AREAS = ["TERMINAL", "BROWSER", "CODE", "CODE 2", "TRADING", "FREI", "TOOLS",
         "TODOS", "CHAT", "MEDIEN"]  # Workspace-Raster 1-10, siehe CLAUDE.md
LETTERS = "dsa"  # Monitor-Kuerzel von rechts (Laptop) nach links, siehe collapse()
BASE = {"a": 10, "s": 20, "d": 30}  # Workspace-Nummer = BASE + N


def swaymsg(*args):
    return json.loads(subprocess.run(["swaymsg", "-r", *args], capture_output=True,
                                     text=True, check=True).stdout)


def desktop_apps():
    """-> {kleingeschriebener Schluessel: (Icon, Name)}. Schluessel sind Dateiname
    ohne .desktop und StartupWMClass, damit app_id und X11-class beide treffen."""
    apps = {}
    for d in reversed(APP_DIRS):  # ~/.local zuletzt -> gewinnt
        for f in glob.glob(os.path.join(d, "*.desktop")):
            p = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                p.read(f, encoding="utf-8")
                e = p["Desktop Entry"]
            except (configparser.Error, KeyError, UnicodeDecodeError):
                continue
            val = (e.get("Icon") or FALLBACK, e.get("Name") or "")
            apps[os.path.basename(f)[:-8].lower()] = val
            if e.get("StartupWMClass"):
                apps[e["StartupWMClass"].lower()] = val
    return apps


def icon_index():
    """-> {Icon-Name: bester Pfad}. Je Name gewinnt das erste ICON_DIRS-Verzeichnis,
    darin SVG vor der groessten PNG (Pfade wie .../128x128/apps/x.png)."""
    best = {}
    for prio, d in enumerate(ICON_DIRS):
        for root, _, files in os.walk(d):
            m = re.search(r"/(\d+)x\d+", root)
            for f in files:
                stem, ext = os.path.splitext(f)
                if ext not in (".svg", ".png"):
                    continue
                score = (-prio, ext == ".svg", int(m.group(1)) if m else 0)
                if stem not in best or score > best[stem][0]:
                    best[stem] = (score, os.path.join(root, f))
    return {k: v[1] for k, v in best.items()}


def resolve(icon, index):
    """Icon-Name oder absoluter Pfad (Snaps) -> Pfad; unbekannt -> FALLBACK-Pfad."""
    if icon.startswith("/"):
        return icon
    return index.get(icon) or index.get(FALLBACK, "")


def win_entry(node, apps, index=None):
    """-> {id, name, title, focused, icon} fuer Tabs, Befehlsleiste und Vorschau."""
    app = node.get("app_id") or (node.get("window_properties") or {}).get("class") or "?"
    icon, name = apps.get(app.lower(), (FALLBACK, ""))
    return {"id": node["id"], "name": name or app, "title": node.get("name") or app,
            "focused": node.get("focused", False), "icon": resolve(icon, index or {})}


def visible_windows(tree, apps, index=None):
    """-> {output: [{id, name, title, focused, icon, active, group}]}: nur der
    sichtbare Workspace je Output (current_workspace), Floating-Fenster hinten
    dran. group = Kennung des obersten Containers mit Layout splith/splitv
    ueber dem Fenster (unterhalb des Workspaces), also des geteilten Tabs aus
    #split; sonst None."""
    out = {}

    def collect(node, acc, group=None):
        if node.get("pid") and node.get("type") in ("con", "floating_con"):
            acc.append(dict(win_entry(node, apps, index), group=group))
        elif group is None and node.get("layout") in ("splith", "splitv") and node.get("type") != "workspace":
            group = node.get("id")
        for child in node.get("nodes", []) + node.get("floating_nodes", []):
            collect(child, acc, group)

    for o in tree.get("nodes", []):
        if o.get("name") == "__i3":  # Scratchpad
            continue
        acc = out.setdefault(o["name"], [])
        for ws in o.get("nodes", []):
            if ws.get("name") == o.get("current_workspace"):
                collect(ws, acc)
                # zuletzt fokussiertes Fenster des Workspaces (Fokus-Stack hinab),
                # damit die Leiste auch ohne Tastaturfokus eins markiert
                node = ws
                while node.get("focus"):
                    fid = node["focus"][0]
                    node = next((c for c in node.get("nodes", []) + node.get("floating_nodes", [])
                                 if c["id"] == fid), {})
                for w in acc:
                    w["active"] = w["id"] == node.get("id")
    return out


def has_focus(n):
    return n.get("focused") or any(has_focus(c) for c in n.get("nodes", []) + n.get("floating_nodes", []))


def focused_output(tree):
    return next((o["name"] for o in tree.get("nodes", []) if has_focus(o)), None)


def collapse(tree):
    """-> sway-Befehle, damit jeder Workspace das Kuerzel seines Monitors traegt.
    Kuerzel nach Position, von rechts: d, s, a (1: d, 2: d+s, 3: d+s+a). Ein
    Workspace mit fremdem Kuerzel bekommt mit gleicher Nummer das des Monitors,
    auf dem er liegt (s3 -> d3). Faengt Assigns, abgezogene Schirme und den
    Login ab: sway legt den ersten Workspace je Monitor an, solange noch nicht
    alle Monitore da sind, und erwischt dabei fremde Kuerzel (a1 auf der Mitte).
    Die alten Kuerzel u/i/o (bis HL2-v30) gelten als fremd und werden so beim
    ersten Lauf umbenannt (i3 -> s3). ponytail: uio aus der Regex streichen,
    sobald keine Session mit alten Namen mehr laeuft.
    Gibt es den Ziel-Workspace noch nicht, wird umbenannt (bleibt, wo er ist),
    sonst wandern die Fenster dorthin.
    ponytail: Steckt man einen Schirm wieder an, wandern die Fenster nicht zurueck."""
    outs = [o for o in tree.get("nodes", []) if o.get("active")]
    outs.sort(key=lambda o: o.get("rect", {}).get("x", 0), reverse=True)
    own = {o["name"]: LETTERS[min(i, len(LETTERS) - 1)] for i, o in enumerate(outs)}
    names = {ws.get("name") for o in outs for ws in o.get("nodes", [])}
    cmds = []
    for o in outs:
        k = own[o["name"]]
        for ws in o.get("nodes", []):
            m = re.fullmatch(r"\d+:([asduio])(\d+)", ws.get("name", ""))
            if not m or m[1] == k:
                continue
            dest = f"{BASE[k] + int(m[2])}:{k}{m[2]}"
            if dest not in names:
                cmds.append(f'rename workspace "{ws["name"]}" to "{dest}"')
                names.add(dest)
                continue
            cmds += [f"[con_id={c['id']}] move container to workspace {dest}"
                     for c in ws.get("nodes", []) + ws.get("floating_nodes", [])]
            if has_focus(ws):
                cmds.append(f"workspace {dest}")  # der leere alte verschwindet dann
    return cmds


def step(wins, delta):
    """-> id des Fensters delta Schritte weiter, im Kreis; None bei leerer Liste."""
    if not wins:
        return None
    i = next((k for k, w in enumerate(wins) if w["focused"]), -1)
    return wins[(i + delta) % len(wins)]["id"]


def cycle(delta):
    tree = swaymsg("-t", "get_tree")
    wid = step(visible_windows(tree, {}).get(focused_output(tree), []), delta)
    if wid is not None:
        subprocess.run(["swaymsg", f"[con_id={wid}] focus"], capture_output=True)


def nudge(wid, way):
    """Fenster wid in der Liste eine Stelle hoch (up) / runter (down)."""
    tree = swaymsg("-t", "get_tree")
    wid = int(wid)
    ids = next((ids for ws in visible_windows(tree, {}).values()
                if wid in (ids := [w["id"] for w in ws])), [])
    i = ids.index(wid) if ids else 0
    j = i + (-1 if way == "up" else 1)
    if 0 <= j < len(ids):
        subprocess.run(["swaymsg", f"[con_id={wid}] swap container with con_id {ids[j]}"], capture_output=True)


def eww(*args):
    # DEVNULL statt capture_output: startet eww dabei den Daemon, erbt der die
    # Pipe, und capture wartet ewig
    subprocess.run(["eww", *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def windows(node):
    """-> alle Fenster unter node (mit Floating), in Baum-Reihenfolge."""
    if node.get("pid") and node.get("type") in ("con", "floating_con"):
        yield node
    for child in node.get("nodes", []) + node.get("floating_nodes", []):
        yield from windows(child)


def snap(tree, taken):
    """Sichtbare Fenster fotografieren, je Fenster hoechstens alle SHOT_EVERY s.
    Im Hintergrund (&), damit der Watcher nicht wartet; sleep, damit das Fenster
    nach dem Wechsel fertig gemalt ist. Gesperrt oder bei offenem Vorschau-Raster
    nie: grim saehe den Lockscreen bzw. das Overlay."""
    now, cmds = time.time(), []
    for w in windows(tree):
        if w.get("visible") and now - taken.get(w["id"], 0) > SHOT_EVERY:
            taken[w["id"]] = now
            r, f = w["rect"], os.path.join(SHOTS, f'{w["id"]}.png')
            cmds.append(f'grim -s 0.3 -l 1 -g "{r["x"]},{r["y"]} {r["width"]}x{r["height"]}" {f}.tmp && mv {f}.tmp {f}')
    if cmds:
        os.makedirs(SHOTS, mode=0o700, exist_ok=True)
        subprocess.run(["sh", "-c", f"(sleep 0.3; pgrep -x 'hyprlock|swaylock' >/dev/null || [ -e {OVERVIEW} ] || {{ "
                        + "; ".join(cmds) + "; }) >/dev/null 2>&1 &"])


def workspace_entries(tree, apps={}, index=None):
    """Zehn Felder je Monitor, zeilenweise von links nach rechts wie collapse().
    Mit den Fenstern je Feld; der Watcher schreibt das als "grid" nach STATE,
    Navigator und Vorschau-Raster in Quickshell lesen es live."""
    outs = sorted((o for o in tree.get("nodes", []) if o.get("active")),
                  key=lambda o: o["rect"]["x"])
    # shortcut: Das Workspace-Schema hat drei Monitore (a/s/d), bei mehr zuerst ws.sh/collapse erweitern.
    if len(outs) > len(LETTERS):
        raise ValueError("Das Workspace-Schema unterstuetzt hoechstens drei Bildschirme.")
    entries = []
    for o, letter in zip(outs, LETTERS[:len(outs)][::-1]):
        workspaces = {ws["name"]: ws for ws in o.get("nodes", [])}
        for number, area in enumerate(AREAS, 1):
            name = f"{BASE[letter] + number}:{letter}{number}"
            ws = workspaces.get(name, {})
            entries.append({"output": o["name"], "letter": letter, "number": number,
                            "name": name, "area": area,
                            "visible": name == o.get("current_workspace"),
                            "focused": bool(has_focus(ws)),
                            "wins": [win_entry(w, apps, index) for w in windows(ws)]})
    return entries


def apply(action, output, number, con):
    """Workspace N auf output: hin (go) oder Fenster con dorthin (move, Fokus bleibt)."""
    if action not in ("go", "move"):
        raise ValueError("apply erwartet go oder move")
    target = next((e for e in workspace_entries(swaymsg("-t", "get_tree"))
                   if e["output"] == output and e["number"] == int(number)), None)
    if target is None:
        raise ValueError("Bildschirme haben sich geaendert. Bitte den Navigator neu oeffnen.")
    name = json.dumps(target["name"])
    # Neue Workspaces auch bei ausgeschaltetem Laptop auf dem gewaehlten Monitor anlegen.
    commands = [f'workspace {name} output {json.dumps(output)}',
                f"workspace --no-auto-back-and-forth {name}" if action == "go" else
                f"[con_id={int(con)}] move container to workspace {name}"]
    for command in commands:
        result = swaymsg(command)
        if not all(item.get("success") for item in result):
            raise RuntimeError("; ".join(item.get("error", "Sway-Befehl fehlgeschlagen")
                                         for item in result if not item.get("success")))


def kill_previous():
    """exec_always startet bei jedem Reload einen neuen Watcher -> alten beenden.
    Per PID-Datei statt pkill -f: das traefe auch die sh -c-Zeile von sway."""
    try:
        with open(PIDFILE) as f:
            os.kill(int(f.read()), 15)
    except (OSError, ValueError):
        pass
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))


def watch():
    kill_previous()
    # Alle eww-Prozesse weg, nicht nur `eww kill`: ein Daemon, der seinen Socket
    # verloren hat (zwei gleichzeitige Starts), zeigt seine Fenster weiter an
    # und ist per eww nicht mehr erreichbar -> doppelte HUD-Fenster.
    subprocess.run(["pkill", "-x", "eww"])
    subprocess.run(["pkill", "-x", "quickshell"])
    subprocess.run(["rm", "-f", OVERVIEW])  # sonst pausiert snap() fuer immer
    time.sleep(0.3)
    eww("open-many", "hud-left", "hud-right")
    subprocess.Popen([QS], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    apps, index = desktop_apps(), icon_index()  # ponytail: nur beim Start; neue Apps nach Super+Shift+C
    events = subprocess.Popen(["swaymsg", "-m", "-t", "subscribe", '["window","workspace","output","tick"]'],
                              stdout=subprocess.PIPE, text=True)
    last, taken = None, {}
    while True:
        tree = swaymsg("-t", "get_tree")
        cmds = collapse(tree)
        if cmds:
            subprocess.run(["swaymsg", "; ".join(cmds)], capture_output=True)
            tree = swaymsg("-t", "get_tree")
        snap(tree, taken)
        wins = visible_windows(tree, apps, index)
        try:
            grid = workspace_entries(tree, apps, index)
        except ValueError:  # mehr als drei Monitore: kein Raster, Tabs laufen weiter
            grid = []
        cur = json.dumps({"wins": wins, "grid": grid})
        if cur != last:
            with open(STATE + ".tmp", "w") as f:
                f.write(cur)
            os.replace(STATE + ".tmp", STATE)  # atomar: Quickshell liest nie halbe Dateien
            last = cur
        if not events.stdout.readline():
            return


def selftest():
    def con(i, app, focused=False, typ="con", **kw):
        return {"type": typ, "pid": i, "id": i, "app_id": app, "name": f"t{i}", "focused": focused, **kw}
    tree = {"type": "root", "nodes": [
        {"type": "output", "name": "__i3", "nodes": [{"type": "workspace", "nodes": [con(9, "x")]}]},
        {"type": "output", "name": "DP-7", "current_workspace": "23:i3", "nodes": [
            {"type": "workspace", "name": "21:i1", "num": 21, "nodes": [con(5, "hidden")]},
            {"type": "workspace", "name": "23:i3", "num": 23, "nodes": [
                {"type": "con", "nodes": [con(1, "code"), con(2, None, True,
                                           window_properties={"class": "jetbrains-idea"})]}],
             "floating_nodes": [con(3, "snap", typ="floating_con")]}]},
        {"type": "output", "name": "eDP-1", "current_workspace": "31:o1", "nodes": [
            {"type": "workspace", "name": "31:o1", "nodes": []}]}]}
    apps = {"code": ("vscode", "Visual Studio Code"), "jetbrains-idea": ("idea", "IntelliJ"),
            "snap": ("/snap/x.png", "")}
    index = {"vscode": "/i/vscode.svg", "idea": "/i/idea.png", FALLBACK: "/i/fb.svg"}
    w = visible_windows(tree, apps, index)
    assert list(w) == ["DP-7", "eDP-1"] and w["eDP-1"] == [], w
    a, b, c = w["DP-7"]
    assert [x["id"] for x in w["DP-7"]] == [1, 2, 3]  # 5 liegt auf unsichtbarem WS
    assert (a["icon"], a["name"]) == ("/i/vscode.svg", "Visual Studio Code")
    assert (b["name"], b["focused"]) == ("IntelliJ", True)
    assert (c["icon"], c["name"]) == ("/snap/x.png", "snap")
    assert visible_windows(tree, {}, index)["DP-7"][0]["icon"] == "/i/fb.svg"
    assert [x["group"] for x in w["DP-7"]] == [None, None, None]  # Container ohne split-Layout
    tree["nodes"][1]["nodes"][1]["nodes"][0].update(id=40, layout="splith")  # nach #split
    assert [x["group"] for x in visible_windows(tree, {})["DP-7"]] == [40, 40, None]
    assert resolve("gibtsnicht", {}) == ""
    assert focused_output(tree) == "DP-7"
    assert step(w["DP-7"], 1) == 3 and step(w["DP-7"], -1) == 1
    assert step(w["DP-7"][:2], 1) == 1  # im Kreis
    assert step([], 1) is None
    out = lambda name, x, *ws: {"type": "output", "name": name, "active": True,
                                "rect": {"x": x}, "nodes": list(ws)}
    lap = lambda *ws: {"nodes": [{"type": "output", "name": "__i3", "nodes": []},
                                 out("eDP-1", 3840, *ws)]}
    assert collapse(lap({"name": "11:a1", "nodes": [], "focused": True})) == \
        ['rename workspace "11:a1" to "31:d1"']
    assert collapse(lap({"name": "31:d1", "nodes": [con(1, "a")]})) == []
    # Ziel gibt es schon -> Fenster wandern
    assert collapse(lap({"name": "33:d3", "nodes": []}, {"name": "23:s3", "nodes": [con(1, "a")]})) == \
        ["[con_id=1] move container to workspace 33:d3"]
    # Login: a1 auf der Mitte, a3 auf dem Laptop (drei Monitore)
    three = {"nodes": [out("HDMI-A-1", 0, {"name": "11:a1", "nodes": []}),
                       out("DP-7", 1920, {"name": "12:a2", "nodes": []}),
                       out("eDP-1", 3840, {"name": "13:a3", "nodes": []})]}
    assert collapse(three) == ['rename workspace "13:a3" to "33:d3"',
                               'rename workspace "12:a2" to "22:s2"']
    # zwei Monitore: a wird s in der Mitte, d auf dem Laptop
    two = {"nodes": [out("DP-7", 1920, {"name": "11:a1", "nodes": [con(1, "a")]}),
                     out("eDP-1", 3840, {"name": "31:d1", "nodes": []})]}
    assert collapse(two) == ['rename workspace "11:a1" to "21:s1"']
    # Migration der alten Namen bis HL2-v30: u/i/o -> a/s/d am gleichen Platz
    old = {"nodes": [out("HDMI-A-1", 0, {"name": "11:u1", "nodes": [con(1, "a")]}),
                     out("DP-7", 1920, {"name": "23:i3", "nodes": [con(2, "b")]},
                         {"name": "23:s3", "nodes": [con(3, "c")]}),
                     out("eDP-1", 3840, {"name": "40:o10", "nodes": [], "focused": True})]}
    assert collapse(old) == ['rename workspace "40:o10" to "40:d10"',
                             "[con_id=2] move container to workspace 23:s3",
                             'rename workspace "11:u1" to "11:a1"']
    grid = workspace_entries(three)
    assert len(grid) == 30
    assert [grid[i]["name"] for i in (0, 9, 10, 20, 29)] == \
        ["11:a1", "20:a10", "21:s1", "31:d1", "40:d10"]
    assert [e["name"] for e in workspace_entries(two)][::10] == ["21:s1", "31:d1"]
    solo = lap({"name": "31:d1", "focused": True, "nodes": [con(1, "a")],
                "floating_nodes": [con(2, "b")]})
    solo["nodes"][1]["current_workspace"] = "31:d1"
    assert len(workspace_entries(solo)) == 10
    cell = workspace_entries(solo, apps, index)[0]
    assert (cell["name"], cell["letter"], cell["area"], cell["visible"], cell["focused"]) == \
        ("31:d1", "d", "TERMINAL", True, True)
    assert [w["id"] for w in cell["wins"]] == [1, 2]
    assert workspace_entries(solo)[-1]["wins"] == []
    assert workspace_entries({"nodes": []}) == []
    from unittest.mock import patch
    ok = [{"success": True}]
    with patch(__name__ + ".swaymsg", side_effect=[solo, ok, ok]) as ipc:
        apply("move", "eDP-1", "5", "1")
        assert ipc.call_args.args == ('[con_id=1] move container to workspace "35:d5"',)
    with patch(__name__ + ".swaymsg", side_effect=[solo, ok, ok]) as ipc:
        apply("go", "eDP-1", "10", "0")
        assert [c.args for c in ipc.call_args_list[1:]] == \
            [('workspace "40:d10" output "eDP-1"',), ('workspace --no-auto-back-and-forth "40:d10"',)]
    # Ein abgezogener Monitor und ein Sway-Fehler brechen ab.
    for replies, error in [([{"nodes": []}], ValueError),
                           ([solo, [{"success": False, "error": "test"}]], RuntimeError)]:
        with patch(__name__ + ".swaymsg", side_effect=replies):
            try:
                apply("move", "eDP-1", "7", "1")
            except error:
                pass
            else:
                raise AssertionError("Workspace-Aktion trotz Fehler ausgefuehrt")
    print("ok")


if __name__ == "__main__":
    if sys.argv[1] == "workspaces":
        try:
            apply(*sys.argv[3:7])
        except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
            subprocess.run(["notify-send", "Befehlsleiste", str(error)])
            sys.exit(str(error))
        sys.exit(0)
    {"watch": watch, "next": lambda: cycle(1), "prev": lambda: cycle(-1),
     "nudge": lambda: nudge(sys.argv[2], sys.argv[3]),
     "selftest": selftest}[sys.argv[1]]()
