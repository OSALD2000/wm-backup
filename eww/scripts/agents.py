#!/usr/bin/python3
"""Agenten-Panel (eww-Fenster "agents", Super+c): laufende Claude-Code- und
Codex-Sessions mit Status, darunter die letzten 10 beendeten, nach Ordner gruppiert.

Aufruf: agents.py watch        Stand alle TICK s nach STATE, waybar wecken
                               (custom/agents), Meldung, wenn ein Agent fertig
                               wird und sein Fenster nicht sichtbar ist.
                               exec_always, ein neuer Start beendet den alten.
        agents.py follow       deflisten im Panel: STATE bei jeder Aenderung
        agents.py open|close   Panel + sway-Mode "[ AGENTS ]" (j/k, Enter, Esc)
        agents.py sel 1|-1     Auswahl bewegen
        agents.py go [IDX|KEY] Auswahl anspringen (Fenster fokussieren, beendete
                               Session in Alacritty fortsetzen), Panel zu
        agents.py bar          waybar-Modul custom/agents
        agents.py selftest

Quellen: Claude  ~/.claude/sessions/<pid>.json (status busy/idle) + Transkript
         Codex   ~/.codex/state_5.sqlite (threads) + Ende der rollout-Datei
Der Watcher ruft nie eww auf: eww startet nur sidebar.py (siehe CLAUDE.md).
"""
import glob
import html
import json
import os
import re
import sqlite3
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
CLAUDE = os.path.join(HOME, ".claude")
CODEX_DB = os.path.join(HOME, ".codex/state_5.sqlite")
RUN = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
STATE = os.path.join(RUN, "agents.json")
SEL = os.path.join(RUN, "agents.sel")
PIDFILE = os.path.join(RUN, "agents.pid")
SELF = os.path.abspath(__file__)
SIGNAL = 11      # = "signal" von custom/agents in waybar/config.jsonc
TICK = 2         # Sekunden zwischen zwei Runden des Watchers
HIST_EVERY = 30  # Verlauf seltener, er liest Transkripte
HIST_N = 10
CODEX_LIVE = 15 * 60  # Codex-App-Threads gelten so lange nach der letzten Aktivitaet als offen
MODE = "[ AGENTS ]"   # = mode in sway/config
# Codex-Threads ohne Terminal: welches Fenster zeigt sie (app_id/class, Regex)
CODEX_APPS = {"codex-chrome-extension-sidepanel": "google-chrome",
              "codex_vscode": "vscode", "Codex Desktop": "chatgpt|codex"}


# ── sway ─────────────────────────────────────────────────────────────
def swaymsg(*args):
    r = subprocess.run(["swaymsg", "-r", *args], capture_output=True, text=True)
    return json.loads(r.stdout or "null")


def sway_windows(tree):
    """-> Liste der Fenster: id, pid, app, title, ws, visible, focused."""
    out = []

    def walk(n, ws):
        if n.get("type") == "workspace":
            ws = n["name"].split(":", 1)[-1]
        if n.get("pid") and n.get("type") in ("con", "floating_con"):
            out.append({"id": n["id"], "pid": n["pid"], "title": n.get("name") or "",
                        "app": n.get("app_id") or (n.get("window_properties") or {}).get("class") or "",
                        "ws": ws, "visible": bool(n.get("visible")), "focused": bool(n.get("focused"))})
        for c in n.get("nodes", []) + n.get("floating_nodes", []):
            walk(c, ws)
    walk(tree or {}, "")
    return out


def ppid(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            return int(f.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def window_of(pid, wins, title=""):
    """Fenster, in dem Prozess pid laeuft: Elternkette hoch bis zu einer
    Fenster-PID. Hat die mehrere Fenster (IntelliJ), entscheidet der Titel."""
    by_pid = {}
    for w in wins:
        by_pid.setdefault(w["pid"], []).append(w)
    while pid > 1:
        if pid in by_pid:
            c = by_pid[pid]
            return next((w for w in c if title and title in w["title"]), c[0])
        pid = ppid(pid)
    return None


# ── Hilfen ───────────────────────────────────────────────────────────
def group_of(cwd):
    if cwd.startswith(os.path.join(HOME, "Documents/Codex/")):
        return "Codex-Chats"  # Chrome-Seitenleiste legt je Chat einen Ordner an
    return "~" if cwd.rstrip("/") == HOME else os.path.basename(cwd.rstrip("/")) or "/"


def dur(sec):
    m = int(max(sec, 0)) // 60
    return f"{m} min" if m < 60 else f"{m // 60}:{m % 60:02d} h" if m < 24 * 60 else f"{m // 1440} d"


def short(s, n=90):
    s = str(s or "")
    if "## My request:" in s:  # Chrome-Seitenleiste: Tab-Kontext davor weg
        s = s.split("## My request:", 1)[1]
    s = " ".join(html.unescape(s).split())
    return s if len(s) <= n else s[:n - 1] + "…"


def tokens(n):
    return f"{n / 1000:.0f}k" if n else ""


def tail_lines(path, size=256 * 1024):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(f.tell() - size, 0))
            data = f.read().decode("utf-8", "replace")
    except OSError:
        return []
    out = []
    for line in data.splitlines()[1:] if len(data) >= size else data.splitlines():
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def tool_text(name, inp):
    inp = inp if isinstance(inp, dict) else {}
    arg = next((inp[k] for k in ("file_path", "path", "command", "cmd", "pattern",
                                 "description", "url", "query", "prompt") if inp.get(k)), "")
    if isinstance(arg, list):
        arg = " ".join(map(str, arg))
    if isinstance(arg, str) and arg.startswith(HOME + "/"):
        arg = "~/" + arg[len(HOME) + 1:]
    return short(f"{name} {arg}", 70)


# ── Claude ───────────────────────────────────────────────────────────
def claude_transcript(sid):
    return next(iter(glob.glob(os.path.join(CLAUDE, "projects", "*", sid + ".jsonl"))), None)


def claude_details(path):
    """Titel, letzter Prompt, letzte Aktion, Kontextgroesse aus dem Transkript-Ende."""
    title = prompt = action = ""
    ctx = 0
    for r in tail_lines(path) if path else []:
        t = r.get("type")
        if t == "ai-title":
            title = r.get("aiTitle", title)
        elif t == "custom-title":
            title = r.get("customTitle", title)
        elif t == "last-prompt":
            prompt = r.get("lastPrompt", prompt)
        elif t == "assistant":
            msg = r.get("message") or {}
            u = msg.get("usage") or {}
            ctx = (u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0)
                   + u.get("cache_creation_input_tokens", 0)) or ctx
            for c in msg.get("content") or []:
                if c.get("type") == "tool_use":
                    action = tool_text(c.get("name", ""), c.get("input"))
                elif c.get("type") == "text" and c.get("text", "").strip():
                    action = "» " + short(c["text"], 70)
    return title, prompt, action, ctx


def proc_alive(pid, start):
    try:
        with open(f"/proc/{pid}/stat") as f:
            fields = f.read().rsplit(")", 1)[1].split()
        return not start or fields[19] == str(start)  # Feld 22 = starttime, gegen PID-Wiederverwendung
    except (OSError, IndexError):
        return False


def claude_live(wins, now):
    out = []
    for f in glob.glob(os.path.join(CLAUDE, "sessions", "*.json")):
        try:
            with open(f) as fh:
                s = json.load(fh)
        except (OSError, ValueError):
            continue
        if not proc_alive(s.get("pid", 0), s.get("procStart")):
            continue
        title, prompt, action, ctx = claude_details(claude_transcript(s.get("sessionId", "")))
        w = window_of(s["pid"], wins, title)
        st = s.get("status", "idle")
        out.append({"key": "claude:" + s.get("sessionId", ""), "tool": "claude", "sid": s.get("sessionId", ""),
                    "status": "busy" if st == "busy" else "idle", "raw": st,
                    "name": title or s.get("name", ""), "cwd": s.get("cwd", ""),
                    "since": dur(now - s.get("startedAt", now * 1000) / 1000),
                    "prompt": short(prompt), "action": action, "tokens": tokens(ctx),
                    "con": w and w["id"], "ws": w["ws"] if w else "", "visible": bool(w and w["visible"]),
                    "focused": bool(w and w["focused"]), "t": s.get("updatedAt", 0) / 1000})
    return out


def claude_history(skip, cache):
    """Beendete Sessions, neueste zuerst. Nur Sessions mit >= 2 Prompts,
    keine Subagents (die liegen eine Ebene tiefer)."""
    files = sorted(glob.glob(os.path.join(CLAUDE, "projects", "*", "*.jsonl")),
                   key=lambda p: -os.path.getmtime(p))
    out = []
    for p in files:
        sid = os.path.basename(p)[:-6]
        if sid in skip:
            continue
        m = os.path.getmtime(p)
        if cache.get(p, (None,))[0] != m:
            cache[p] = (m, claude_summary(p))
        s = cache[p][1]
        if s and s["prompts"] >= 2:
            out.append({"key": "claude:" + sid, "tool": "claude", "sid": sid, "status": "ended",
                        "name": s["title"], "cwd": s["cwd"], "prompt": short(s["first"]), "t": m})
            if len(out) >= HIST_N:
                break
    return out


def claude_summary(path):
    title, first, cwd, prompts = "", "", "", 0
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if '"ai-title"' in line or '"custom-title"' in line:
                    r = json.loads(line)
                    title = r.get("customTitle") or r.get("aiTitle") or title
                elif line.startswith('{"type":"user"') or '"type":"user"' in line[:200]:
                    try:
                        r = json.loads(line)
                    except ValueError:
                        continue
                    c = (r.get("message") or {}).get("content")
                    if isinstance(c, str) and not c.startswith("<"):
                        prompts += 1
                        first = first or c
                    cwd = cwd or r.get("cwd", "")
    except (OSError, ValueError):
        return None
    return {"title": title, "first": first, "cwd": cwd, "prompts": prompts}


# ── Codex ────────────────────────────────────────────────────────────
def codex_threads(where, args=()):
    try:
        db = sqlite3.connect(f"file:{CODEX_DB}?mode=ro", uri=True, timeout=1)
        db.row_factory = sqlite3.Row
        # thread_source 'user' = vom Menschen gestartet: ohne guardian/review/
        # Subagents und ohne die aus Claude importierten Sessions (leer)
        rows = db.execute("select id, rollout_path, cwd, title, first_user_message, originator, "
                          "created_at, updated_at from threads where thread_source='user' "
                          "and archived=0 and tokens_used>0 and " + where +
                          " order by updated_at desc limit 40", args).fetchall()
        db.close()
        return [dict(r) for r in rows]
    except sqlite3.Error:
        return []


def codex_details(path):
    """busy?, letzter Prompt, letzte Aktion, Kontext aus dem rollout-Ende."""
    busy, prompt, action, ctx = None, "", "", 0
    for r in tail_lines(path, 64 * 1024):
        p = r.get("payload") or {}
        t = p.get("type")
        if t == "task_started":
            busy = True
        elif t == "task_complete":
            busy = False
        elif t == "token_count":
            ctx = ((p.get("info") or {}).get("last_token_usage") or {}).get("input_tokens") or ctx
        elif r.get("type") == "response_item" and t == "message":
            txt = " ".join(c.get("text", "") for c in p.get("content") or [] if isinstance(c, dict))
            if p.get("role") == "user" and txt.strip() and not txt.lstrip().startswith(("<", "#")):
                prompt = txt
            elif p.get("role") == "assistant" and txt.strip():
                action = "» " + short(txt, 70)
        elif r.get("type") == "response_item" and t in ("function_call", "custom_tool_call", "local_shell_call"):
            try:
                inp = json.loads(p.get("arguments") or "{}")
            except ValueError:
                inp = {}
            action = tool_text(p.get("name", "shell"), inp if isinstance(inp, dict) else {})
    # Kein Marker im Ende = langer Turn, task_started liegt weiter vorn -> arbeitet
    return busy is not False, prompt, action, ctx


def codex_tui_pids():
    """Laufende Codex-Terminal-Clients -> [(pid, cwd)], neueste zuerst."""
    out = []
    for d in glob.glob("/proc/[0-9]*"):
        try:
            with open(d + "/comm") as f:
                if f.read().strip() != "codex":
                    continue
            with open(d + "/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
            if any(a in (b"app-server", b"sandbox", b"exec", b"mcp-server") for a in argv[1:3]):
                continue
            out.append((int(d[6:]), os.readlink(d + "/cwd")))
        except OSError:
            continue
    return sorted(out, reverse=True)


def codex_live(wins, now):
    out, used = [], set()
    tui = codex_tui_pids()
    rows = codex_threads("updated_at > ?", (int(now) - 7 * 86400,)) if tui else []
    pairs = []
    # ponytail: Terminal -> Thread ueber cwd + neuester codex-tui-Thread dort;
    # zwei Codex im selben Ordner koennen vertauscht sein
    for pid, cwd in tui:
        r = next((r for r in rows if r["cwd"] == cwd and r["originator"] == "codex-tui"
                  and r["id"] not in used), None)
        if r:
            used.add(r["id"])
            pairs.append((r, window_of(pid, wins)))
    for r in codex_threads("updated_at > ? and coalesce(originator,'') != 'codex-tui'", (int(now) - CODEX_LIVE,)):
        rx = CODEX_APPS.get(r["originator"] or "", "chatgpt|codex")
        pairs.append((r, next((w for w in wins if re.search(rx, w["app"], re.I)), None)))
    for r, w in pairs:
        busy, prompt, action, ctx = codex_details(r["rollout_path"])
        out.append({"key": "codex:" + r["id"], "tool": "codex", "sid": r["id"],
                    "status": "busy" if busy else "idle", "raw": "busy" if busy else "idle",
                    "name": short(r["title"] or r["first_user_message"], 60), "cwd": r["cwd"],
                    "since": dur(now - r["created_at"]), "prompt": short(prompt or r["first_user_message"]),
                    "action": action, "tokens": tokens(ctx), "con": w and w["id"],
                    "ws": w["ws"] if w else "", "visible": bool(w and w["visible"]),
                    "focused": bool(w and w["focused"]), "t": r["updated_at"]})
    return out


def codex_history(skip):
    return [{"key": "codex:" + r["id"], "tool": "codex", "sid": r["id"], "status": "ended",
             "name": short(r["title"], 60), "cwd": r["cwd"], "prompt": short(r["first_user_message"]),
             "t": r["updated_at"], "originator": r["originator"] or ""}
            for r in codex_threads("1") if "codex:" + r["id"] not in skip][:HIST_N]


# ── Stand ────────────────────────────────────────────────────────────
def grouped(items):
    """Nach Ordner gruppieren; Gruppen und Eintraege nach letzter Aktivitaet."""
    groups = {}
    for it in sorted(items, key=lambda i: -i["t"]):
        groups.setdefault(group_of(it["cwd"]), []).append(it)
    return [{"name": g, "path": its[0]["cwd"].replace(HOME, "~", 1), "items": its} for g, its in groups.items()]


def build(live, hist, new, now):
    for it in live:
        it["new"] = it["key"] in new
    live_g = grouped(live)
    hist_g = grouped(sorted(hist, key=lambda i: -i["t"])[:HIST_N])
    i = 0
    for g in live_g + hist_g:
        for it in g["items"]:
            it["idx"] = i
            i += 1
            if it["status"] == "ended":
                it["ago"] = "vor " + dur(now - it["t"])
    return {"live": live_g, "hist": hist_g, "count": i,
            "busy": sum(it["status"] == "busy" for it in live),
            "idle": sum(it["status"] == "idle" for it in live),
            "new": sum(it["new"] for it in live), "n": len(live)}


def bar_json(st):
    if not st.get("n"):
        return {"text": "λ", "class": "none", "tooltip": "Keine Agenten (Super+c)"}
    text = "λ"
    if st["busy"]:
        text += f" {st['busy']}⚙"
    if st["idle"]:
        text += f" {st['idle']}✓"
    tip = "\n".join(f"{'⚙' if it['status'] == 'busy' else '✓'} {g['name']} · {it['tool']} · {it['name']}"
                    for g in st["live"] for it in g["items"])
    return {"text": text, "class": "new" if st["new"] else "busy" if st["busy"] else "idle",
            "tooltip": tip + "\nSuper+c = Panel"}


def notify(it):
    """HL2-Pickup ueber swaync; Klick springt hin. notify-send -A blockiert bis
    zum Klick oder Ablauf -> abgekoppelt starten."""
    sh = '[ "$(notify-send -a agents -A default=Hinspringen "$1" "$2")" = default ] && exec "$0" go "$3"'
    subprocess.Popen(["sh", "-c", sh, SELF, f"λ {it['name'] or group_of(it['cwd'])}",
                      f"{it['tool'].upper()} BEREIT · {group_of(it['cwd'])}", it["key"]],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def transitions(prev, live, new):
    """busy -> idle bei unsichtbarem Fenster = neu + Meldung. Neu bleibt, bis
    das Fenster fokussiert ist. -> zu meldende Eintraege."""
    out = []
    for it in live:
        if it["focused"]:
            new.discard(it["key"])
        elif prev.get(it["key"]) == "busy" and it["status"] == "idle" and not it["visible"]:
            new.add(it["key"])
            out.append(it)
    keys = {it["key"] for it in live}
    new &= keys
    return out


def write_state(st):
    with open(STATE + ".tmp", "w") as f:
        json.dump(st, f, ensure_ascii=False)
    os.replace(STATE + ".tmp", STATE)


def kill_previous():
    try:
        with open(PIDFILE) as f:
            os.kill(int(f.read()), 15)
    except (OSError, ValueError):
        pass
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))


def watch():
    kill_previous()
    prev, new, cache, hist, hist_at, last = {}, set(), {}, [], 0, None
    while True:
        now = time.time()
        wins = sway_windows(swaymsg("-t", "get_tree"))
        live = claude_live(wins, now) + codex_live(wins, now)
        if now - hist_at > HIST_EVERY or os.path.exists(SEL):  # Panel offen -> frisch
            skip = {it["key"].split(":", 1)[1] for it in live} | {it["key"] for it in live}
            hist, hist_at = claude_history(skip, cache) + codex_history(skip), now
        for it in transitions(prev, live, new):
            notify(it)
        prev = {it["key"]: it["status"] for it in live}
        st = build(live, hist, new, now)
        cur = json.dumps(st, ensure_ascii=False)
        if cur != last:
            write_state(st)
            subprocess.run(["pkill", f"-RTMIN+{SIGNAL}", "-x", "waybar"])
            last = cur
        time.sleep(TICK)


# ── Panel ────────────────────────────────────────────────────────────
def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"live": [], "hist": [], "count": 0, "busy": 0, "idle": 0, "new": 0, "n": 0}


def items(st):
    return [it for g in st["live"] + st["hist"] for it in g["items"]]


def follow():
    last = None
    while True:
        try:
            m = os.path.getmtime(STATE)
        except OSError:
            m = 0
        if m != last:
            print(json.dumps(load(), ensure_ascii=False), flush=True)
            last = m
        time.sleep(0.5)


def get_sel():
    try:
        with open(SEL) as f:
            return int(f.read())
    except (OSError, ValueError):
        return 0


def set_sel(i):
    with open(SEL, "w") as f:
        f.write(str(i))
    subprocess.run(["eww", "update", f"agent_sel={i}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def open_panel():
    out = next((o["name"] for o in swaymsg("-t", "get_outputs") or [] if o.get("focused")), "eDP-1")
    set_sel(0)
    subprocess.run(["eww", "open", "agents", "--screen", out], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["swaymsg", f'mode "{MODE}"'], stdout=subprocess.DEVNULL)


def close_panel():
    try:
        os.remove(SEL)
    except OSError:
        pass
    subprocess.run(["eww", "close", "agents"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["swaymsg", "mode default"], stdout=subprocess.DEVNULL)


def action(it, wins=()):
    """-> sway-Befehl fuer den Eintrag (wins = sway_windows, fuer App-Fenster)."""
    if it.get("con"):
        return f"[con_id={it['con']}] focus"
    cwd = it.get("cwd") or HOME
    if it["status"] == "ended" and (it["tool"] == "claude" or it.get("originator") in ("codex-tui", "")):
        cmd = ["claude", "--resume"] if it["tool"] == "claude" else ["codex", "resume"]
        q = lambda s: "'" + s.replace("'", "'\\''") + "'"
        return "exec alacritty --working-directory " + q(cwd) + " -e " + " ".join(cmd + [q(it["sid"])])
    # ponytail: Codex-App/Chrome/VS Code nur fokussieren, kein Deep-Link zum Thread
    rx = CODEX_APPS.get(it.get("originator", ""), "chatgpt|codex")
    w = next((w for w in wins if re.search(rx, w["app"], re.I)), None)
    return f"[con_id={w['id']}] focus" if w else None


def go(arg=None):
    st = load()
    its = items(st)
    if arg and not arg.lstrip("-").isdigit():
        it = next((i for i in its if i["key"] == arg), None)
    else:
        i = int(arg) if arg else get_sel()
        it = its[i] if 0 <= i < len(its) else None
    close_panel()
    cmd = it and action(it, sway_windows(swaymsg("-t", "get_tree")))
    if cmd:
        subprocess.run(["swaymsg", cmd], stdout=subprocess.DEVNULL)


def selftest():
    home = HOME
    assert group_of(home + "/Work/x/Fairgleichen") == "Fairgleichen"
    assert group_of(home + "/Documents/Codex/2026-10-13/ka") == "Codex-Chats"
    assert group_of(home) == "~"
    assert dur(42 * 60) == "42 min" and dur(2 * 3600 + 5 * 60) == "2:05 h" and dur(3 * 86400) == "3 d"
    a = {"key": "claude:a", "status": "busy", "focused": False, "visible": False}
    b = {"key": "codex:b", "status": "busy", "focused": False, "visible": True}
    new = set()
    # a wird fertig, Fenster nicht sichtbar -> Meldung; b sichtbar -> keine
    out = transitions({"claude:a": "busy", "codex:b": "busy"},
                      [dict(a, status="idle"), dict(b, status="idle")], new)
    assert [i["key"] for i in out] == ["claude:a"] and new == {"claude:a"}
    transitions({}, [dict(a, status="idle", focused=True)], new)
    assert new == set()  # Fokus = gesehen
    mk = lambda k, cwd, t, s="busy": {"key": k, "cwd": cwd, "t": t, "status": s, "tool": "claude",
                                       "name": k, "sid": k}
    st = build([mk("x", "/p/A", 5), mk("y", "/p/B", 9, "idle"), mk("z", "/p/A", 7)],
               [mk("h", "/p/A", 1, "ended")], set(), 10)
    assert [g["name"] for g in st["live"]] == ["B", "A"]
    assert [it["key"] for it in items(st)] == ["y", "z", "x", "h"]
    assert [it["idx"] for it in items(st)] == [0, 1, 2, 3] and st["count"] == 4
    assert (st["busy"], st["idle"], st["n"]) == (2, 1, 3)
    assert bar_json(st)["text"] == "λ 2⚙ 1✓"
    assert action({"con": 7}) == "[con_id=7] focus"
    r = action({"tool": "claude", "status": "ended", "sid": "s1", "cwd": "/a b/it's"})
    assert r == "exec alacritty --working-directory '/a b/it'\\''s' -e claude --resume 's1'", r
    assert action({"tool": "codex", "status": "idle", "originator": "codex-chrome-extension-sidepanel"},
                  [{"id": 3, "app": "google-chrome"}]) == "[con_id=3] focus"
    assert short("# Chrome tabs:\n- x\n\n## My request:\nseo &amp; so") == "seo & so"
    assert tool_text("Edit", {"file_path": home + "/x/y"}) == "Edit ~/x/y"
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl") as f:
        f.write('{"type":"event_msg","payload":{"type":"item_completed"}}\n' * 3)
        f.flush()
        assert codex_details(f.name)[0] is True
        f.write('{"type":"event_msg","payload":{"type":"task_complete"}}\n')
        f.flush()
        assert codex_details(f.name)[0] is False
    print("selftest ok")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "bar"
    arg = sys.argv[2] if len(sys.argv) > 2 else None
    if cmd == "watch":
        watch()
    elif cmd == "follow":
        follow()
    elif cmd == "open":
        open_panel()
    elif cmd == "close":
        close_panel()
    elif cmd == "toggle":
        close_panel() if os.path.exists(SEL) else open_panel()
    elif cmd == "sel":
        n = load()["count"]
        set_sel((get_sel() + int(arg or 1)) % n if n else 0)
    elif cmd == "go":
        go(arg)
    elif cmd == "bar":
        print(json.dumps(bar_json(load()), ensure_ascii=False))
    elif cmd == "selftest":
        selftest()
