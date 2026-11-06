#!/usr/bin/python3
"""Tickets als Markdown-Dateien im Obsidian-Vault (Quelle der Wahrheit).

Aufruf: ticket.py list [PROJ] [STATUS] | show KEY | new PROJ TITEL [-p PRIO] [-l LABEL]... [-s STATUS]
        | set KEY FELD WERT | delete KEY (Datei in <Vault>/.trash)
        | quick [STATUS TEXT] | open KEY | watch | migrate | selftest
FELD:   status | prio | title | project | labels | archived (ja|nein)
Datei:  <Vault>/Tickets/<PROJ>/<PROJ>-<N> <Titel>.md, Frontmatter status prio created
        archived aliases tags. Fremde Frontmatter-Zeilen und der Text bleiben byte-gleich.
Nur dieses Skript schreibt Ticket-Dateien: atomar (.tmp + os.replace) unter flock.
"""
import fcntl
import json
import os
import re
import subprocess
import sys
import time
from datetime import date
from pathlib import Path
from urllib.parse import quote

STATUSES = ("backlog", "todo", "in-arbeit", "review", "fertig")
PRIOS = ("hoch", "mittel", "niedrig")
WIP = 3  # hoechstens so viele nicht archivierte Tickets in-arbeit (alle Projekte)
MANAGED = ("status", "prio", "created", "archived", "aliases", "tags")
DEFAULT_BODY = """## Ziel

## Naechste Schritte
- [ ]

## Notizen & Links
"""
FILE_RE = re.compile(r"^([A-Z][A-Z0-9]*)-(\d+) (.+)\.md$")
PROJ_RE = re.compile(r"^[A-Z][A-Z0-9]*$")
KEY_RE = re.compile(r"^([A-Za-z_][\w-]*):(.*)$")
VAULT = ROOT = TEMPLATE = LAST = None


def use_vault(vault, last=None):
    global VAULT, ROOT, TEMPLATE, LAST
    VAULT = Path(vault)
    ROOT = VAULT / "Tickets"
    TEMPLATE = VAULT / "Templates" / "Ticket.md"
    LAST = Path(last) if last else Path.home() / ".local/state/tickets-last"


use_vault(Path.home() / "Private/obsidian-vault")


class locked:
    """flock auf Tickets/.lock (legt Tickets/ an). Nicht verschachteln."""
    def __enter__(self):
        ROOT.mkdir(parents=True, exist_ok=True)
        self.f = open(ROOT / ".lock", "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)

    def __exit__(self, *a):
        self.f.close()


# --- Frontmatter ---------------------------------------------------------

def split(text):
    """-> (Frontmatter-Zeilen ohne ---, Text danach unveraendert)."""
    if not text.startswith("---\n"):
        return [], text
    pos, lines = 4, []
    while pos <= len(text):
        nl = text.find("\n", pos)
        end = len(text) if nl < 0 else nl
        line = text[pos:end]
        if line.rstrip() == "---":
            return lines, text[end + 1:]
        if nl < 0:
            break
        lines.append(line)
        pos = nl + 1
    raise ValueError("Frontmatter ohne schliessendes ---")


def _unq(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


def _block_end(lines, i):
    """Index hinter dem Block der Schluesselzeile i (eingerueckte bzw. `- `-Zeilen)."""
    j = i + 1
    while j < len(lines) and (lines[j][:1] in (" ", "\t") or lines[j].startswith("- ") or lines[j] == "-"):
        j += 1
    return j


def parse_fm(lines):
    """key: wert, [a, b], Blockliste -> dict (Werte str oder list[str])."""
    out, i = {}, 0
    while i < len(lines):
        m = KEY_RE.match(lines[i])
        if not m:
            i += 1
            continue
        k, v = m.group(1), m.group(2).strip()
        j = _block_end(lines, i)
        if v.startswith("[") and v.endswith("]"):
            out[k] = [_unq(x) for x in re.findall(r'"[^"]*"|\'[^\']*\'|[^,]+', v[1:-1]) if x.strip()]
        elif v == "":
            out[k] = [_unq(l.strip()[1:]) for l in lines[i + 1:j] if l.strip().startswith("-")]
        else:
            out[k] = _unq(v)
        i = j
    return out


def _q(x):
    """Listeneintrag quoten, wenn Komma, Doppelpunkt usw. ihn sonst zerlegen wuerden."""
    if re.search(r"[,:\[\]{}#&*!|>'\"%@`]", x) or x != x.strip():
        return json.dumps(x, ensure_ascii=False)
    return x


def set_fm(lines, updates):
    """Ersetzt nur die Bloecke der genannten Schluessel; None entfernt, Fehlende werden angehaengt."""
    lines = list(lines)
    for k, v in updates.items():
        new = [] if v is None else [f"{k}: [{', '.join(_q(x) for x in v)}]" if isinstance(v, (list, tuple)) else f"{k}: {v}"]
        for i, l in enumerate(lines):
            m = KEY_RE.match(l)
            if m and m.group(1) == k:
                lines[i:_block_end(lines, i)] = new
                break
        else:
            lines += new
    return lines


def clean_title(s):
    """Obsidian-verbotene Zeichen -> Leerzeichen, hoechstens 80 Zeichen an Wortgrenze."""
    s = re.sub(r'[/\\:*?"<>|#^\[\]]', " ", s)
    s = re.sub(r"\s+", " ", s).strip(" .")
    if len(s) > 80:
        cut = s[:80]
        if s[80] != " " and " " in cut:
            cut = cut.rsplit(" ", 1)[0]
        s = cut.strip(" .")
    if not s:
        raise ValueError("Titel ist leer.")
    return s


def clean_project(p):
    p = p.strip().upper()
    if not PROJ_RE.match(p):
        raise ValueError("Projektname nur A-Z und 0-9, Beginn mit Buchstabe.")
    return p


def clean_labels(labels):
    out = []
    for l in labels:
        l = re.sub(r'[,\[\]"\'#\s]', "", l)
        if l and l not in out:
            out.append(l)
    return out


def _list(v):
    return v if isinstance(v, list) else ([v] if v else [])


# --- Lesen ---------------------------------------------------------------

def read(path):
    path = Path(path)
    m = FILE_RE.match(path.name)
    if not m:
        raise ValueError(f"{path.name}: kein Ticket-Dateiname")
    text = path.read_text()
    lines, body = split(text)
    d = parse_fm(lines)
    bad = []
    status, prio = d.get("status", "backlog"), d.get("prio", "mittel")
    if status not in STATUSES:
        bad.append(f"Status '{status}' unbekannt")
        status = "backlog"
    if prio not in PRIOS:
        bad.append(f"Prio '{prio}' unbekannt")
        prio = "mittel"
    labels = [t for t in _list(d.get("tags", [])) if t != "ticket"
              and not t.startswith(("projekt/", "status/", "prio/"))]
    # nur Punkte mit Text: das leere "- [ ]" der Vorlage zaehlt nicht
    check = re.findall(r"^\s*- \[( |x|X)\][ \t]+\S", body, re.M)
    return {"key": f"{m.group(1)}-{m.group(2)}", "project": m.group(1), "num": int(m.group(2)),
            "title": m.group(3), "status": status, "prio": prio, "labels": labels,
            "archived": str(d.get("archived", "")).lower() in ("true", "ja", "yes"),
            "aliases": _list(d.get("aliases", [])),
            "check": [sum(c != " " for c in check), len(check)],
            "created": str(d.get("created", "")), "mtime": int(path.stat().st_mtime),
            "path": str(path), "body": body, "bad": "; ".join(bad)}


def _load(f, proj):
    """Eine Datei lesen -> (Ticket | None, Fehlertext | None)."""
    m = FILE_RE.match(f.name)
    if not m or m.group(1) != proj:
        return None, f"{proj}/{f.name}: keine Kennung {proj}-<N>"
    try:
        return read(f), None
    except (ValueError, OSError, UnicodeDecodeError) as e:
        return None, f"{proj}/{f.name}: {e}"


def _state(projects, entries):
    """entries: [(Ticket | None, Fehlertext | None)] -> Stand wie scan()."""
    tickets, errs, seen = [], [], set()
    for t, err in entries:
        if err:
            errs.append(err)
        if t:
            if t["key"] in seen:
                errs.append(f"doppelte Kennung {t['key']}")
            seen.add(t["key"])
            if t["bad"]:
                errs.append(f"{t['key']}: {t['bad']}")
            tickets.append(t)
    wip = sum(t["status"] == "in-arbeit" and not t["archived"] for t in tickets)
    return {"projects": projects, "tickets": tickets, "wip": wip, "error": "; ".join(errs)}


def _files():
    """([Projekte], [(Datei, Projekt)]) in fester Reihenfolge."""
    projects, files = [], []
    if ROOT.is_dir():
        for d in sorted(ROOT.iterdir()):
            if d.is_dir() and PROJ_RE.match(d.name):
                projects.append(d.name)
                files += [(f, d.name) for f in sorted(d.glob("*.md"))]
    return projects, files


def scan():
    """Alle Projekte und Tickets; Probleme einzeln in `error` (nie schreiben)."""
    projects, files = _files()
    return _state(projects, [_load(f, p) for f, p in files])


class Watcher:
    """poll() liefert den Stand nur bei neuem Pfad/neuer mtime; liest nur Geaendertes."""
    def __init__(self):
        self.cache, self.sig = {}, None

    def poll(self):
        projects, files = _files()
        cache, sig = {}, []
        for f, proj in files:
            try:
                mt = f.stat().st_mtime_ns
            except OSError:
                mt = -1
            sig.append((str(f), mt))
            old = self.cache.get(str(f))
            if old and old[0] == mt:
                cache[str(f)] = old
                continue
            t, err = _load(f, proj)
            if t is None and old and old[1]:  # unlesbar: letzter guter Stand bleibt
                t = old[1]
            cache[str(f)] = (mt, t, err)
        sig = (tuple(projects), tuple(sig))
        self.cache = cache
        if sig == self.sig:
            return None
        self.sig = sig
        return _state(projects, [(t, e) for _, t, e in cache.values()])


def find(key, tickets):
    k = key.strip().upper()
    for t in tickets:
        if t["key"].upper() == k:
            return t
    for t in tickets:
        if k in (a.upper() for a in t["aliases"]):
            return t
    raise ValueError(f"Ticket {key} nicht gefunden.")


def next_num(project, tickets):
    pre, n = project.upper() + "-", 0
    # auch unlesbare/verirrte Dateien zaehlen: ihre Nummer wird nie neu vergeben
    # auch der Papierkorb: geloeschte Nummern bleiben vergeben
    for f in [*ROOT.glob("*/*.md"), *(VAULT / ".trash").glob("*.md")]:
        m = FILE_RE.match(f.name)
        if m and m.group(1) == project.upper():
            n = max(n, int(m.group(2)))
    for t in tickets:
        for k in [t["key"], *t["aliases"]]:
            m = re.fullmatch(re.escape(pre) + r"(\d+)", k.upper())
            if m:
                n = max(n, int(m.group(1)))
    return n + 1


# --- Schreiben (nur unter locked aufrufen) ----------------------------------

def _atomic(path, text):
    tmp = Path(str(path) + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def _tags(project, status, prio, labels):
    return ["ticket", f"projekt/{project.lower()}", f"status/{status}", f"prio/{prio}", *labels]


def write(t, fields, title=None, project=None):
    """Schreibt die genannten Felder (+ Tags, Aliase neu), benennt um / verschiebt."""
    p = Path(t["path"])
    lines, body = split(p.read_text())
    proj, key = t["project"], t["key"]
    if project and project != proj:
        proj = project
        key = f"{proj}-{next_num(proj, scan()['tickets'])}"
    name = clean_title(title) if title is not None else t["title"]
    fields = dict(fields)
    labels = fields.pop("labels", t["labels"])
    status, prio = fields.get("status", t["status"]), fields.get("prio", t["prio"])
    aliases = list(t["aliases"])
    for k in (t["key"], key):
        if k not in aliases:
            aliases.append(k)
    upd = {**fields, "aliases": aliases, "tags": _tags(proj, status, prio, labels)}
    new = ROOT / proj / f"{key} {name}.md"
    if new != p and new.exists():
        raise ValueError(f"{new.name} gibt es schon.")
    new.parent.mkdir(parents=True, exist_ok=True)
    _atomic(p, "---\n" + "\n".join(set_fm(lines, upd) + ["---"]) + "\n" + body)
    if new != p:
        os.replace(p, new)  # eine atomare Umbenennung, nie zwei Dateien gleichzeitig
    return read(new)


def _template_body():
    if not TEMPLATE.exists():
        TEMPLATE.parent.mkdir(parents=True, exist_ok=True)
        TEMPLATE.write_text(DEFAULT_BODY)
    return split(TEMPLATE.read_text())[1]


def _fm_lines(project, key, status, prio, labels, archived=False):
    """Frontmatter eines neuen Tickets (gemeinsam fuer new und migrate)."""
    return set_fm([], {"status": status, "prio": prio, "created": date.today().isoformat(),
                       "archived": "true" if archived else None, "aliases": [key],
                       "tags": _tags(project, status, prio, labels)})


def _file_text(lines, body):
    """Dateitext eines neuen Tickets (gemeinsam fuer new und migrate)."""
    return "---\n" + "\n".join(lines + ["---"]) + "\n\n" + body


def _check_wip(tickets, me=None):
    full = sorted((t for t in tickets if t["status"] == "in-arbeit" and not t["archived"]
                   and t["key"] != me), key=lambda t: (t["project"], t["num"]))
    if len(full) >= WIP:
        raise ValueError(f"In Arbeit ist voll ({len(full)}/{WIP}): "
                         + ", ".join(t["key"] for t in full) + ". Erst eins weiterschieben.")


def _check_enum(name, value, allowed):
    if value not in allowed:
        raise ValueError(f"{name} muss eins von {', '.join(allowed)} sein.")


def new(project, title, prio="mittel", labels=(), status="todo"):
    project, title = clean_project(project), clean_title(title)
    _check_enum("Prio", prio, PRIOS)
    _check_enum("Status", status, STATUSES)
    with locked():
        tickets = scan()["tickets"]
        if status == "in-arbeit":
            _check_wip(tickets)
        key = f"{project}-{next_num(project, tickets)}"
        body = _template_body()
        lines = _fm_lines(project, key, status, prio, clean_labels(labels))
        path = ROOT / project / f"{key} {title}.md"
        if path.exists():
            raise ValueError(f"{path.name} gibt es schon.")
        path.parent.mkdir(parents=True, exist_ok=True)
        _atomic(path, _file_text(lines, body))
        LAST.parent.mkdir(parents=True, exist_ok=True)
        LAST.write_text(project + "\n")
    return key


def migrate(data, missions):
    """Einmaliger Import der Missionen als WORK-<id>; kein WIP-Limit, kein LAST."""
    items = json.loads(Path(data).read_text())["items"]
    made = []
    with locked():
        folder = ROOT / "WORK"
        if any(folder.glob("*.md")):
            raise ValueError("Tickets/WORK enthaelt schon Tickets; Migration abgebrochen.")
        folder.mkdir(parents=True, exist_ok=True)
        for it in items:
            key, text = f"WORK-{it['id']}", it["text"]
            try:
                title = clean_title(text)
            except ValueError:
                title, text = f"Mission {it['id']}", " ".join(text.split()) or ""
            body, note = DEFAULT_BODY, Path(missions) / f"Mission-{it['id']}.md"
            if note.exists():
                src = note.read_text()
                i = src.find("## Ziel")
                if i >= 0:
                    body = "".join(l for l in src[i:].splitlines(True)
                                   if not l.startswith("> Aufgabenstatus und Titel"))
            if text and title != " ".join(text.split()):  # gekuerzt/bereinigt: voller Text bleibt
                body = body.replace("## Ziel\n", "## Ziel\n" + text + "\n", 1)
            status = "fertig" if it.get("done") else "in-arbeit" if it.get("focus") else "todo"
            lines = _fm_lines("WORK", key, status, "mittel", [], bool(it.get("archived")))
            _atomic(folder / f"{key} {title}.md", _file_text(lines, body))
            made.append(key)
    return made


def set_field(key, field, value):
    if field == "project":
        value = clean_project(value)
    elif field == "status":
        _check_enum("Status", value, STATUSES)
    elif field == "prio":
        _check_enum("Prio", value, PRIOS)
    elif field == "archived":
        _check_enum("archived", value, ("ja", "nein"))
    elif field not in ("title", "labels"):
        raise ValueError("Feld muss eins von status, prio, title, project, labels, archived sein.")
    with locked():
        tickets = scan()["tickets"]
        t = find(key, tickets)
        if field == "status" and value == "in-arbeit" and t["status"] != "in-arbeit":
            _check_wip(tickets, t["key"])
        if field == "title":
            r = write(t, {}, title=value)
        elif field == "project":
            r = write(t, {}, project=value)
        elif field == "labels":
            r = write(t, {"labels": clean_labels(value.split())})
        elif field == "archived":
            r = write(t, {"archived": "true" if value == "ja" else None})
        else:
            r = write(t, {field: value})
    return r["key"]


def delete(key):
    """Ticket in den Obsidian-Papierkorb (<Vault>/.trash) verschieben; -> Zielpfad."""
    with locked():
        p = Path(find(key, scan()["tickets"])["path"])
        trash = VAULT / ".trash"
        trash.mkdir(parents=True, exist_ok=True)
        dst, n = trash / p.name, 1
        while dst.exists():
            n += 1
            dst = trash / f"{p.name[:-3]} ({n}).md"
        os.replace(p, dst)
    return dst


def list_lines(project=None, status=None):
    """Zeilen fuer `list`: Kennung, Status, Prio, Titel, Labels (ohne archivierte)."""
    ts = [t for t in scan()["tickets"] if not t["archived"]
          and (project is None or t["project"] == project.upper())
          and (status is None or t["status"] == status)]
    ts.sort(key=lambda t: (PRIOS.index(t["prio"]), t["project"], t["num"]))
    return [f"{t['key']:<12}{t['status']:<11}{t['prio']:<8}{t['title']}"
            + "".join(" #" + l for l in t["labels"]) for t in ts]


def parse_quick(text, last):
    """'PROJ: Titel #label !prio' -> (Projekt, Titel, Labels, Prio)."""
    text, proj = text.strip(), last or "WORK"
    m = re.match(r"^([A-Za-z][A-Za-z0-9]*):\s*", text)
    if m:
        proj, text = m.group(1).upper(), text[m.end():]
    labels = re.findall(r"(?<!\S)#(\S+)", text)
    pr = re.findall(r"(?<!\S)!(hoch|mittel|niedrig)(?!\S)", text)
    text = re.sub(r"(?<!\S)(#\S+|!(?:hoch|mittel|niedrig))(?!\S)", " ", text)
    title = " ".join(text.split())
    if not title:
        raise ValueError("Titel ist leer.")
    return proj, title, labels, pr[-1] if pr else "mittel"


def quick(status, text):
    last = LAST.read_text().strip() if LAST.exists() else None
    proj, title, labels, prio = parse_quick(text, last)
    return new(proj, title, prio, labels, status)


def watch():
    ppid, w = os.getppid(), Watcher()
    while os.getppid() == ppid:
        st = w.poll()
        if st is not None:
            print(json.dumps(st, ensure_ascii=False), flush=True)
        time.sleep(1)


def main(argv):
    import argparse
    ap = argparse.ArgumentParser(prog="ticket.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("list")
    s.add_argument("project", nargs="?")
    s.add_argument("status", nargs="?")
    sub.add_parser("show").add_argument("key")
    s = sub.add_parser("new")
    s.add_argument("project")
    s.add_argument("title")
    s.add_argument("-p", "--prio", default="mittel")
    s.add_argument("-l", "--label", action="append", default=[])
    s.add_argument("-s", "--status", default="todo")
    s = sub.add_parser("set")
    s.add_argument("key")
    s.add_argument("field")
    s.add_argument("value")
    sub.add_parser("delete").add_argument("key")
    s = sub.add_parser("quick")
    s.add_argument("args", nargs="*", help="[STATUS TEXT]; ohne: Text von stdin, Status todo")
    sub.add_parser("open").add_argument("key")
    sub.add_parser("watch")
    sub.add_parser("migrate")
    sub.add_parser("selftest")
    a = ap.parse_args(argv)
    if a.cmd == "list":
        print("\n".join(list_lines(a.project, a.status)))
    elif a.cmd == "show":
        t = find(a.key, scan()["tickets"])
        print(t["path"] + "\n\n" + Path(t["path"]).read_text(), end="")
    elif a.cmd == "new":
        print(new(a.project, a.title, a.prio, a.label, a.status))
    elif a.cmd == "set":
        print(set_field(a.key, a.field, a.value))
    elif a.cmd == "delete":
        delete(a.key)
        print(f"{a.key} in den Papierkorb verschoben")
    elif a.cmd == "quick":
        if a.args:
            print(quick(a.args[0], " ".join(a.args[1:])))
        else:
            try:
                print(quick("todo", sys.stdin.read()))
            except ValueError as e:
                subprocess.run(["notify-send", "Tickets", str(e)])
                raise
    elif a.cmd == "open":
        t = find(a.key, scan()["tickets"])
        subprocess.Popen(["sh", "-c", 'xdg-open "$1"; sleep 1; swaymsg "[app_id=obsidian] focus"', "-",
                          "obsidian://open?path=" + quote(t["path"])],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif a.cmd == "watch":
        watch()
    elif a.cmd == "migrate":
        print(" ".join(migrate(Path.home() / ".local/share/missions/data.json", VAULT / "Missionen")))
    else:
        selftest()


def selftest():
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        use_vault(Path(tmp), Path(tmp) / "last")
        k = new("WORK", "Atlas MCP anpassen", labels=["mcp"])
        assert k == "WORK-1" and (ROOT / "WORK" / "WORK-1 Atlas MCP anpassen.md").exists()
        assert TEMPLATE.exists() and LAST.read_text().strip() == "WORK"
        t = find("work-1", scan()["tickets"])
        assert (t["status"], t["prio"], t["labels"], t["aliases"]) == ("todo", "mittel", ["mcp"], ["WORK-1"])
        assert parse_fm(split(Path(t["path"]).read_text())[0])["tags"] == ["ticket", "projekt/work", "status/todo", "prio/mittel", "mcp"]
        # WIP-Limit
        for n in range(3):
            set_field(new("WORK", f"A{n}"), "status", "in-arbeit")
        try:
            set_field("WORK-1", "status", "in-arbeit"); raise AssertionError("WIP fehlt")
        except ValueError as e:
            assert "WORK-2" in str(e) and "WORK-4" in str(e)
        # Projektwechsel + keine Wiederverwendung (Review Focus 1)
        assert set_field("WORK-4", "project", "aurora") == "AURORA-1"
        assert find("WORK-4", scan()["tickets"])["key"] == "AURORA-1"
        assert find("AURORA-1", scan()["tickets"])["aliases"] == ["WORK-4", "AURORA-1"]
        assert new("WORK", "Danach") == "WORK-5"
        # Titel mit Sonderzeichen (Review Focus 5)
        assert set_field("WORK-1", "title", "Bericht 'Q3': $(false) / λ") == "WORK-1"
        assert (ROOT / "WORK" / "WORK-1 Bericht 'Q3' $(false) λ.md").exists()
        for bad in ("???", " / ", ".."):
            try:
                clean_title(bad); raise AssertionError("leerer Titel")
            except ValueError:
                pass
        assert clean_title(".versteckt") == "versteckt" and len(clean_title("wort " * 40)) <= 80
        # Fremde Zeilen + Text byte-gleich, Obsidian-Blocklisten (Review Focus 3)
        p = Path(find("WORK-1", scan()["tickets"])["path"])
        fm, body = split(p.read_text())
        p.write_text("---\nstatus: todo\nquelle: \"Jan\"  # Kommentar\ntags:\n  - ticket\n  - mcp\naliases:\n  - WORK-1\n---\n" + body)
        set_field("WORK-1", "labels", "docs ki")
        fm2, body2 = split(p.read_text())
        assert body2 == body and 'quelle: "Jan"  # Kommentar' in fm2
        assert find("WORK-1", scan()["tickets"])["labels"] == ["docs", "ki"]
        p.write_text("---\nstatus: todo\ntags:\n---\n" + body)
        assert find("WORK-1", scan()["tickets"])["labels"] == []
        p.write_text("---\nstatus: todo\n---\n- [ ]\n- [ ] x\n- [x] y\n")   # leerer Punkt zaehlt nicht
        assert find("WORK-1", scan()["tickets"])["check"] == [1, 2]
        # Ungueltig + Hinweise
        p.write_text("---\nstatus: erledigt\n---\n" + body)
        t = find("WORK-1", scan()["tickets"])
        assert t["status"] == "backlog" and "erledigt" in t["bad"]
        (ROOT / "WORK" / "Neue Notiz.md").write_text("x")
        assert "Neue Notiz.md" in scan()["error"]
        assert set_field("WORK-1", "archived", "ja") and find("WORK-1", scan()["tickets"])["archived"] is True
        assert "WORK-1" not in "\n".join(list_lines("WORK"))   # archivierte nicht in list
        try:
            set_field("WORK-5", "project", "1x"); raise AssertionError("Projektname")
        except ValueError as e:
            assert "A-Z" in str(e)
        # Fix-Runde 1: Regressionen
        t = find("WORK-5", scan()["tickets"]); wp = Path(t["path"]); wtxt = wp.read_text()
        wp.write_text("---\nstatus: todo\nWICHTIGER TEXT")
        k = new("WORK", "Foo")
        assert k == "WORK-6" and wp.read_text() == "---\nstatus: todo\nWICHTIGER TEXT"
        wp.write_text(wtxt)
        (ROOT / "AURORA" / "WORK-9 verirrt.md").write_text("x")
        assert new("WORK", "Bar") == "WORK-10"
        try:
            set_field("WORK-5", "title", ""); raise AssertionError("leerer Titel")
        except ValueError as e:
            assert "Titel ist leer." in str(e)
        wp.write_text('---\nstatus: todo\naliases:\n  - "Bericht, Q3"\n  - "Ziel: Q3"\n---\n')
        set_field("WORK-5", "prio", "hoch")
        assert find("WORK-5", scan()["tickets"])["aliases"] == ["Bericht, Q3", "Ziel: Q3", "WORK-5"]
        set_field("WORK-5", "title", "Neu")
        assert not wp.exists() and (ROOT / "WORK" / "WORK-5 Neu.md").exists()
        # Task 2: quick / Watcher
        assert parse_quick("aurora: Docs fixen #mcp !hoch", "WORK") == ("AURORA", "Docs fixen", ["mcp"], "hoch")
        assert parse_quick("Nur Titel", None) == ("WORK", "Nur Titel", [], "mittel")
        assert parse_quick("Nur Titel", "AURORA")[0] == "AURORA"
        for bad in ("#nurlabel", "AURORA:  !hoch", "   "):
            try:
                parse_quick(bad, None); raise AssertionError("leer")
            except ValueError:
                pass
        w = Watcher()
        first = w.poll(); assert first is not None and w.poll() is None          # unveraendert -> nichts
        p = Path(find("WORK-5", first["tickets"])["path"])
        p.rename(p.with_name("WORK-5 Umbenannt.md"))                              # Review Focus 2
        s = w.poll(); assert [t["title"] for t in s["tickets"] if t["key"] == "WORK-5"] == ["Umbenannt"]
        good = p.with_name("WORK-5 Umbenannt.md").read_text()
        p.with_name("WORK-5 Umbenannt.md").write_text("---\nstatus: todo\n")     # halb gespeichert, Review Focus 4
        os.utime(p.with_name("WORK-5 Umbenannt.md"), (time.time() + 5,) * 2)
        s = w.poll(); assert any(t["key"] == "WORK-5" for t in s["tickets"]) and "WORK-5" in s["error"]
        p.with_name("WORK-5 Umbenannt.md").unlink()
        s = w.poll(); assert not any(t["key"] == "WORK-5" for t in s["tickets"])
        main(["quick", "review", "AURORA: Aus dem Board #ui"])
        assert find("AURORA-2", scan()["tickets"])["status"] == "review"
        # Task 6b: loeschen in den Papierkorb
        k = new("WORK", "Weg damit")
        p = Path(find(k, scan()["tickets"])["path"])
        dst = delete(k)
        assert not p.exists() and dst == VAULT / ".trash" / p.name and dst.exists()
        assert not any(t["key"] == k for t in scan()["tickets"])
        assert new("WORK", "Danach") != k                      # Nummer nicht wiederverwendet
        k2 = new("WORK", "Weg damit")
        d2 = delete(k2); assert d2.exists() and d2 != dst
        try:
            delete("WORK-999"); raise AssertionError("nicht gefunden")
        except ValueError:
            pass
        k3 = new("WORK", "Doppelt"); p3 = Path(find(k3, scan()["tickets"])["path"])
        (VAULT / ".trash" / p3.name).write_text("alt")
        assert delete(k3).name == p3.name[:-3] + " (2).md"
        k4 = new("WORK", "Doppelt"); p4 = Path(find(k4, scan()["tickets"])["path"])
        (VAULT / ".trash" / p4.name).write_text("alt"); (VAULT / ".trash" / (p4.name[:-3] + " (2).md")).write_text("alt")
        assert delete(k4).name == p4.name[:-3] + " (3).md"
        (VAULT / ".trash" / "PROJX-7 Alt.md").write_text("x")  # Papierkorb zaehlt fuer die Nummer
        assert new("PROJX", "Neu") == "PROJX-8"
        main(["delete", "--", new("WORK", "Per CLI")])
        use_vault(Path(tmp) / "leer", Path(tmp) / "last2")
        assert Watcher().poll() == {"projects": [], "tickets": [], "wip": 0, "error": ""}
    # Task 3: migrate (eigener Vault)
    with tempfile.TemporaryDirectory() as tmp:
        use_vault(Path(tmp), Path(tmp) / "last")
        src = Path(tmp) / "data.json"
        src.write_text(json.dumps({"items": [
            {"id": 3, "text": "Atlas MCP anpassen", "done": False},
            {"id": 9, "text": "MCP Debuging " + "sehr lang " * 15, "done": False, "focus": True},
            {"id": 11, "text": "Reto Skill", "done": True},
            {"id": 17, "text": "ENET grill-me", "done": False, "archived": True}]}))
        ms = Path(tmp) / "Missionen"; ms.mkdir()
        (ms / "Mission-3.md").write_text("---\nmission_id: 3\n---\n\n# Atlas MCP anpassen\n\n## Ziel\nEigenes Ziel\n\n> Aufgabenstatus und Titel verwaltest du im Missionen-Panel. Diese Notiz bleibt frei bearbeitbar.\n")
        assert migrate(src, ms) == ["WORK-3", "WORK-9", "WORK-11", "WORK-17"]
        ts = {t["key"]: t for t in scan()["tickets"]}
        assert ts["WORK-3"]["body"].lstrip("\n").startswith("## Ziel\nEigenes Ziel") and "Aufgabenstatus" not in ts["WORK-3"]["body"]
        assert ts["WORK-9"]["status"] == "in-arbeit" and len(ts["WORK-9"]["title"]) <= 80
        assert ts["WORK-9"]["body"].lstrip("\n").startswith("## Ziel\nMCP Debuging sehr lang")
        assert ts["WORK-11"]["status"] == "fertig" and ts["WORK-17"]["archived"] and ts["WORK-17"]["status"] == "todo"
        assert new("WORK", "Neu") == "WORK-18"
        try:
            migrate(src, ms); raise AssertionError("zweiter Lauf")
        except ValueError:
            pass
        # nur Sonderzeichen: Titel "Mission <id>", voller Text unter ## Ziel; kein LAST, kein WIP-Limit
        for f in (ROOT / "WORK").glob("*.md"):
            f.unlink()
        LAST.unlink()
        src.write_text(json.dumps({"items": [{"id": n, "text": "???" if n == 5 else f"F{n}", "done": False, "focus": True}
                                             for n in (5, 6, 7, 8)]}))
        assert migrate(src, ms) == ["WORK-5", "WORK-6", "WORK-7", "WORK-8"] and not LAST.exists()
        ts = {t["key"]: t for t in scan()["tickets"]}
        assert ts["WORK-5"]["title"] == "Mission 5" and ts["WORK-5"]["body"].lstrip("\n").startswith("## Ziel\n???\n")
        assert ts["WORK-5"]["body"].startswith("\n## Ziel") and new("WORK", "Gleich") == "WORK-9"
        assert find("WORK-9", scan()["tickets"])["body"].startswith("\n## Ziel")  # gleiches Layout wie migrate
    print("selftest ok: Kern (new/set/list/find, WIP, Projektwechsel, Frontmatter)")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (ValueError, OSError) as e:
        print(f"Fehler: {e}", file=sys.stderr)
        sys.exit(1)
