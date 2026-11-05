# Ticket-Board in Quickshell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mission Control durch ein Jira-artiges Ticket-Board ersetzen: Tickets als Markdown im Obsidian-Vault, CLI `ticket.py` fuer Board und Agenten, Vollbild-Board in Quickshell auf `Super+m`.

**Architecture:** `sway/scripts/ticket.py` (nur stdlib) ist die einzige Stelle, die Ticket-Dateien liest und schreibt. `ticket.py watch` streamt den Stand als JSON-Zeilen. `quickshell/Tickets.qml` (+ `TicketCard.qml`, `TicketDetail.qml`) zeigt ihn und ruft fuer jede Aktion `ticket.py` mit Argument-Array auf. Agenten nutzen dasselbe CLI ueber den Symlink `~/.local/bin/ticket`.

**Tech Stack:** Python 3 stdlib, Quickshell 0.3.2 (QtQuick, QtQuick.Effects, QtQuick.Shapes, Quickshell.Io, Quickshell.I3, Quickshell.Wayland), sway, eww (nur Aufraeumen).

**Spec:** `docs/superpowers/specs/2026-11-05-tickets-quickshell-design.md` (vor jeder Aufgabe den passenden Abschnitt lesen; die Spec ist massgeblich fuer alle Werte, Texte und Tastenbelegungen).

## Global Constraints

- Repo `~/Private/wm-backup`, Branch `master`, linear. Commits: `HL2: <was, deutsch>`, nie `feat:`; jede Commit-Message endet mit
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` und `Claude-Session: https://claude.ai/code/session_017AUJ8WkAT6TFuyXieWqfMb`.
- Kommentare und Commits deutsch, Umlaute als ae/oe/ue (auch in UI-Texten in Code, wie im Rest des Repos).
- **Live editieren, zurueck syncen:** Dateien unter `~/.config/{sway,quickshell,eww}/` aendern, ansehen, dann
  `S=.claude/skills/theme-switch/scripts/theme.sh; $S sync-back`, `git status`/`git diff` pruefen (nur erwartete Dateien), committen.
  Geloeschte Dateien zusaetzlich live loeschen und im Repo per `git rm` (sync-back loescht nicht).
- Python: `#!/usr/bin/python3`, nur stdlib (kein PyYAML), ausfuehrbar (`chmod +x`). Muster wie `todo.py`/`note.py`: Selbsttest als `ticket.py selftest` mit `assert`, Ausgabe `selftest ok: …`.
- Vault `~/Private/obsidian-vault`, Root `Tickets/`, Vorlage `Templates/Ticket.md`, letztes Projekt `~/.local/state/tickets-last`.
- Status `backlog | todo | in-arbeit | review | fertig`, Prio `hoch | mittel | niedrig` (Standard `mittel`), WIP-Limit 3 auf `in-arbeit` (nicht archivierte, alle Projekte).
- Freitext nie durch eine Shell-Zeile: in QML nur Argument-Arrays, in Python `subprocess` mit Liste.
- Schreiben atomar (`<datei>.tmp` + `os.replace`), alle Schreibbefehle unter `flock` auf `Tickets/.lock`. Text unter dem Frontmatter wird nie veraendert; fremde Frontmatter-Zeilen bleiben byte-gleich.
- Quickshell-Farben/Schrift nur aus `root` in `shell.qml` (`hud bg font barBg edge box fill hover`); Federn `SpringAnimation` spring 4-5, damping 0.25-0.32; Endlos-Animationen nur `running: open`.
- QML-Pruefung ohne Tastatur-Injektion (kein wtype/ydotool): `quickshell ipc call tickets …`, Screenshot `grim -o <Monitor> /tmp/claude-1000/…/scratchpad/<name>.png` und ansehen, `~/.local/bin/quickshell log` ohne neue Fehler. Quickshell laedt `~/.config/quickshell/` bei Aenderung selbst neu.
- Kein Push, kein Tag ohne ausdrueckliches OK von Osa.

## Review Focus

1. **Nummer nach Projektwechsel:** WORK-21 (hoechste) wandert nach AURORA; das naechste neue WORK-Ticket darf nicht WORK-21 sein (Alias waere doppelt). -> Test in Task 1.
2. **Umbenennen/Loeschen in Obsidian:** Datei umbenannt oder geloescht -> Board zeigt den neuen Stand, keine Geisterkarte. -> Test in Task 2 (`watch`-Diff ueber Pfadmenge).
3. **Obsidian schreibt Listen um:** `tags`/`aliases` als Blockliste (`tags:` + `  - a`), Werte in `"…"`, leeres `tags:`; fremde Zeilen bleiben byte-gleich. -> Test in Task 1.
4. **Halb gespeicherte Datei:** `watch` liest eine Datei mitten im Speichern (kein schliessendes `---`) -> letzter guter Stand bleibt, Karte verschwindet nicht, nichts wird zurueckgeschrieben. -> Test in Task 2.
5. **Titel, der leer wird:** `???`, `/`, nur `#label`, fuehrender `.` -> abgelehnt mit `Titel ist leer.` bzw. Punkt entfernt. -> Test in Task 1 (und `quick` in Task 2).

---

### Task 1: `ticket.py` Kern – Datei lesen/schreiben, `new`, `set`, `list`, `show`

**Files:**
- Create: `~/.config/sway/scripts/ticket.py` (Repo: `sway/scripts/ticket.py`)

**Interfaces:**
- Produces (Modul-Ebene, spaetere Tasks nutzen genau diese Namen):
  - Konstanten `STATUSES = ("backlog", "todo", "in-arbeit", "review", "fertig")`, `PRIOS = ("hoch", "mittel", "niedrig")`, `WIP = 3`, `MANAGED = ("status", "prio", "created", "archived", "aliases", "tags")`, `DEFAULT_BODY` (Inhalt der Vorlage aus der Spec, ohne Frontmatter).
  - Globale Pfade `VAULT, ROOT, TEMPLATE, LAST` + `use_vault(vault: Path, last: Path | None = None) -> None` (setzt alle vier; Standard `~/Private/obsidian-vault`, `~/.local/state/tickets-last`). Der Selbsttest ruft `use_vault(<tmp>)`.
  - `split(text: str) -> tuple[list[str], str]`: Frontmatter-Zeilen (ohne `---`) + Text danach (unveraendert). Kein Frontmatter -> `([], text)`. Oeffnendes ohne schliessendes `---` -> `ValueError("Frontmatter ohne schliessendes ---")`.
  - `parse_fm(lines: list[str]) -> dict[str, str | list[str]]`: `key: wert`, `[a, b]`, Blockliste, Anfuehrungszeichen entfernt, leeres `key:` ohne Listenzeilen -> `[]`.
  - `set_fm(lines: list[str], updates: dict[str, str | list[str] | None]) -> list[str]`: ersetzt nur den Block (Schluesselzeile + folgende eingerueckte/`- `-Zeilen) der genannten Schluessel, `None` entfernt ihn, fehlende werden angehaengt; Listen immer als `key: [a, b]`.
  - `clean_title(s: str) -> str`: `/ \ : * ? " < > | # ^ [ ]` -> Leerzeichen, Folgen zusammenziehen, `strip(" .")`, an Wortgrenze auf 80 Zeichen; leer -> `ValueError("Titel ist leer.")`.
  - `read(path: Path) -> dict`: Ticket im Format von `watch` (Spec, Abschnitt `watch`): `key project num title status prio labels archived aliases check created mtime path body bad`. Unbekannter Status -> `status="backlog"`, unbekannte Prio -> `"mittel"`, `bad` nennt den Grund. Wirft `ValueError` bei kaputtem Frontmatter.
  - `scan() -> dict`: `{"projects", "tickets", "wip", "error"}`; Projekte = Ordner unter `ROOT` mit Namen `[A-Z][A-Z0-9]*` (alphabetisch, auch leere); Dateien ohne `<PROJ>-<N> `-Praefix, doppelte Kennungen und kaputte Dateien -> Hinweis in `error` (eine Zeile je Fall, `; `-getrennt). Fehlt `ROOT` -> leerer Stand.
  - `find(key: str, tickets: list[dict]) -> dict`: gross/klein egal; aktuelle Kennung vor Alias; sonst `ValueError(f"Ticket {key} nicht gefunden.")`.
  - `next_num(project: str, tickets: list[dict]) -> int`: max ueber Kennungen **und** Aliase mit Praefix `<project>-` in allen Tickets, + 1.
  - `write(t: dict, fields: dict, title: str | None = None, project: str | None = None) -> dict`: schreibt Felder + neu berechnete verwaltete Tags (`ticket`, `projekt/<proj klein>`, `status/<s>`, `prio/<p>`, dann Labels), benennt bei `title`/`project` um bzw. verschiebt (neuer Ordner bei Bedarf), haelt Aliase aktuell (alte Kennung bleibt, neue kommt dazu). Atomar. Gibt das neu gelesene Ticket zurueck.
  - `new(project: str, title: str, prio: str = "mittel", labels: list[str] = (), status: str = "todo") -> str` (gibt Kennung zurueck; legt `TEMPLATE` mit `DEFAULT_BODY` an, falls fehlt; `created` = heute; schreibt `LAST`).
  - `set_field(key: str, field: str, value: str) -> str` (Felder `status prio title project labels archived`; `archived` nimmt `ja|nein`; gibt die (ggf. neue) Kennung zurueck).
  - `class locked` (Kontextmanager, `flock` auf `ROOT/.lock`, legt `ROOT` an).
  - CLI in `main(argv: list[str]) -> None`: `list [PROJ] [STATUS]`, `show KEY`, `new PROJ TITEL [-p PRIO] [-l LABEL]... [-s STATUS]` (argparse), `set KEY FELD WERT`, `selftest`. Fehler: `ValueError`/`OSError` -> stderr, Exit 1.
  - `list`-Zeile: `f"{key:<12}{status:<11}{prio:<8}{title}" + "".join(" #" + l for l in labels)`, ohne archivierte, sortiert wie die Board-Spalten (Prio, dann Nummer).

- [ ] **Step 1: Selbsttest zuerst schreiben** (`selftest()` in `ticket.py`, nur das Geruest von `main` + `selftest` + leere Funktionen mit den Signaturen oben, damit der Test laeuft und scheitert). Asserts (alle in einem `tempfile.TemporaryDirectory()`, `use_vault(Path(tmp), Path(tmp) / "last")`):

```python
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
```

  (`list_lines(project: str | None = None, status: str | None = None) -> list[str]` ist die Formatierung von `list`; `main` druckt sie.)

- [ ] **Step 2: Laufen lassen, muss scheitern**

Run: `~/.config/sway/scripts/ticket.py selftest`
Expected: `AssertionError` oder `NotImplementedError`/`TypeError` aus den leeren Funktionen, Exit != 0.

- [ ] **Step 3: Implementieren** – Funktionen mit den Signaturen oben. Hinweise, wo die Signatur nichts festlegt:
  - Dateinamen-Muster: `re.compile(r"^([A-Z][A-Z0-9]*)-(\d+) (.+)\.md$")`; Projekt aus dem Muster muss dem Ordnernamen entsprechen, sonst Hinweis in `error`.
  - `read` zaehlt Checkliste mit `re.findall(r"^\s*- \[( |x|X)\]", body, re.M)`.
  - `set_field(... "status", "in-arbeit")` prueft das Limit gegen `scan()` unter `locked`; Meldung: `In Arbeit ist voll (3/3): WORK-2, WORK-3, WORK-4. Erst eins weiterschieben.`
  - `write` mit Titel-/Projektwechsel: erst neue Datei atomar schreiben, dann alte entfernen (`os.replace` auf den neuen Namen, wenn gleicher Ordner).
  - `ROOT.mkdir(parents=True, exist_ok=True)` nur in `locked`/`new`, nie in `scan`.
  - Projektname: `upper()`, dann `[A-Z][A-Z0-9]*`, sonst `ValueError("Projektname nur A-Z und 0-9, Beginn mit Buchstabe.")` (gilt fuer `new` und `set … project`).

- [ ] **Step 4: Selbsttest gruen**

Run: `~/.config/sway/scripts/ticket.py selftest`
Expected: `selftest ok: …`, Exit 0.

- [ ] **Step 5: CLI von Hand pruefen (Temp-Vault ueber `use_vault` ist nur im Selbsttest; deshalb hier echtes Projekt TEST, danach weg)**

```sh
T=~/.config/sway/scripts/ticket.py
$T new TEST "Probe 'eins'" -p hoch -l a -l b && $T list TEST && $T show TEST-1 && $T set TEST-1 status review && $T list TEST review
rm -r ~/Private/obsidian-vault/Tickets/TEST
```
Expected: `TEST-1`, eine Tabellenzeile mit `hoch` und ` #a #b`, `show` zeigt Pfad + Frontmatter + Text, Status danach `review`.

- [ ] **Step 6: Commit**

```bash
S=.claude/skills/theme-switch/scripts/theme.sh; $S sync-back
git status --short   # nur sway/scripts/ticket.py
git add sway/scripts/ticket.py
git commit -m "HL2: ticket.py – Tickets als Markdown im Vault (new/set/list/show, WIP-Limit, Projektwechsel)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_017AUJ8WkAT6TFuyXieWqfMb"
```

---

### Task 2: `ticket.py` – `quick`, `open`, `watch` + Symlink fuer Agenten

**Files:**
- Modify: `~/.config/sway/scripts/ticket.py`
- Create (ausserhalb des Repos): Symlink `~/.local/bin/ticket` -> `~/.config/sway/scripts/ticket.py`

**Interfaces:**
- Consumes: alles aus Task 1.
- Produces:
  - `parse_quick(text: str, last: str | None) -> tuple[str, str, list[str], str]`: `(projekt, titel, labels, prio)`; `PROJ:` am Anfang (`^([A-Za-z][A-Za-z0-9]*):\s*`) -> Projekt gross; sonst `last` oder `"WORK"`; `#label` -> Labels; `!hoch|!mittel|!niedrig` -> Prio; Titel = Rest (leer -> `ValueError("Titel ist leer.")`).
  - `Watcher` mit `poll() -> dict | None`: haelt `{path: (mtime, ticket)}`; gibt den neuen Stand nur zurueck, wenn sich Pfadmenge oder eine mtime geaendert hat; liest nur geaenderte Dateien; schlaegt das Lesen einer bekannten Datei fehl, bleibt ihr letzter guter Stand (Hinweis in `error`). `scan()` aus Task 1 bleibt fuer `list`/`set`.
  - CLI: `quick [STATUS TEXT]` (ohne Argumente: Text von stdin, Status `todo`, bei Fehler zusaetzlich `notify-send Tickets <meldung>`; mit Argumenten nutzt das Board es fuer `n`, Status = Spalte, ohne `notify-send`), `open KEY` (Obsidian-Aufruf wie `note.py`: `sh -c 'xdg-open "$1"; sleep 1; swaymsg "[app_id=obsidian] focus"' - obsidian://open?path=<quote(path)>`, `Popen` mit `DEVNULL`), `watch` (jede Sekunde `poll()`, Zeile mit `json.dumps(..., ensure_ascii=False)` + `flush`; beendet sich, wenn `os.getppid()` sich gegenueber dem Start aendert).

- [ ] **Step 1: Asserts im Selbsttest ergaenzen**

```python
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
use_vault(Path(tmp) / "leer", Path(tmp) / "last2")
assert Watcher().poll() == {"projects": [], "tickets": [], "wip": 0, "error": ""}
```

- [ ] **Step 2: Laufen lassen, muss scheitern**

Run: `~/.config/sway/scripts/ticket.py selftest` — Expected: `NameError: parse_quick` (o. ae.), Exit != 0.

- [ ] **Step 3: Implementieren** (`parse_quick`, `Watcher`, CLI-Zweige `quick`/`open`/`watch`).

- [ ] **Step 4: Selbsttest gruen** — Run: `~/.config/sway/scripts/ticket.py selftest` — Expected: `selftest ok: …`.

- [ ] **Step 5: Von Hand pruefen**

```sh
T=~/.config/sway/scripts/ticket.py
echo "test: Quick 'eins' #x !hoch" | $T quick && $T list TEST
timeout 3 $T watch | head -c 300; echo
echo "#nur" | $T quick; echo "exit=$?"
rm -r ~/Private/obsidian-vault/Tickets/TEST
ln -sf ~/.config/sway/scripts/ticket.py ~/.local/bin/ticket && ticket list | head -3
```
Expected: `TEST-1` mit `hoch` und ` #x`; `watch` druckt eine JSON-Zeile mit `"projects"`; `#nur` -> `Titel ist leer.` auf stderr, Pickup erscheint, `exit=1`; `ticket list` laeuft.

- [ ] **Step 6: Commit** (wie Task 1, Message `HL2: ticket.py quick/open/watch`).

---

### Task 3: `ticket.py migrate`

**Files:**
- Modify: `~/.config/sway/scripts/ticket.py`

**Interfaces:**
- Consumes: `new`-Bausteine (`clean_title`, `set_fm`, `write`-Pfad), `ROOT`, `TEMPLATE`.
- Produces: `migrate(data: Path, missions: Path) -> list[str]` (angelegte Kennungen) und CLI `migrate` mit `data = ~/.local/share/missions/data.json`, `missions = VAULT / "Missionen"`.
  Regeln (Spec, Abschnitt Migration): Mission `<id>` -> `WORK-<id>`; Status: `focus` -> `in-arbeit`, `done` -> `fertig`, sonst `todo`; `archived` -> `archived: true`; `prio: mittel`, `created` = heute, keine Labels, `aliases: [WORK-<id>]`. Text: aus `Mission-<id>.md` ab der Zeile `## Ziel` (ohne Zeile, die mit `> Aufgabenstatus und Titel` beginnt), sonst `DEFAULT_BODY`; wurde der Titel gekuerzt, steht der volle Missionstext als erste Zeile unter `## Ziel`. Bricht mit `ValueError("Tickets/WORK enthaelt schon Tickets; Migration abgebrochen.")` ab, wenn `ROOT/WORK` schon `*.md` hat. WIP-Limit gilt bei der Migration nicht (Ist-Zustand uebernehmen).

- [ ] **Step 1: Asserts ergaenzen** (eigener Temp-Vault):

```python
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
assert ts["WORK-3"]["body"].startswith("## Ziel\nEigenes Ziel") and "Aufgabenstatus" not in ts["WORK-3"]["body"]
assert ts["WORK-9"]["status"] == "in-arbeit" and len(ts["WORK-9"]["title"]) <= 80
assert ts["WORK-9"]["body"].startswith("## Ziel\nMCP Debuging sehr lang")
assert ts["WORK-11"]["status"] == "fertig" and ts["WORK-17"]["archived"] and ts["WORK-17"]["status"] == "todo"
assert new("WORK", "Neu") == "WORK-18"
try:
    migrate(src, ms); raise AssertionError("zweiter Lauf")
except ValueError:
    pass
```

- [ ] **Step 2: Scheitern sehen** — `ticket.py selftest` -> `NameError: migrate`.
- [ ] **Step 3: Implementieren.**
- [ ] **Step 4: Gruen** — `ticket.py selftest` -> `selftest ok: …`.
- [ ] **Step 5: Probelauf gegen eine Kopie der echten Daten** (nicht der echte Vault):

```sh
D=/tmp/claude-1000/-home-osa-Private-wm-backup/7f8c579e-d7e0-4150-bcb1-aaa07b2d09ba/scratchpad/migtest
rm -rf $D && mkdir -p $D && cp -r ~/Private/obsidian-vault/Missionen $D/
python3 -c "import sys; sys.path.insert(0, '$HOME/.config/sway/scripts'); import ticket as t; from pathlib import Path; t.use_vault(Path('$D'), Path('$D/last')); print(t.migrate(Path('$HOME/.local/share/missions/data.json'), Path('$D/Missionen')))"
ls "$D/Tickets/WORK" | head -20
```
Expected: 18 Kennungen `WORK-1` … `WORK-21` (Luecken wie die IDs), Dateinamen lesbar, `WORK-3`/`WORK-4` mit Text aus der Missionsnotiz.

- [ ] **Step 6: Commit** (`HL2: ticket.py migrate – Missionen werden WORK-Tickets`).

---

### Task 4: Board in Quickshell (funktional)

**Files:**
- Create: `~/.config/quickshell/Tickets.qml`, `~/.config/quickshell/TicketCard.qml`, `~/.config/quickshell/TicketDetail.qml`
- Modify: `~/.config/quickshell/shell.qml` (vor der schliessenden `}` von `ShellRoot`: `Tickets { shell: root }`; Kopfkommentar um eine Zeile "Dazu das Ticket-Board (Super+m), siehe Tickets.qml" ergaenzen)

**Interfaces:**
- Consumes: `ticket.py watch` (JSON wie Spec), `ticket.py new|set|open` (Exit-Code + stderr), Farben aus `root`.
- Produces:
  - `Tickets.qml`: Wurzel `Scope { required property var shell }`. Zustand: `open: bool`, `output: string`, `state: {projects, tickets, wip, error}`, `tab: string` (`""` = ALLE), `col: int` (0-4), `key: string` (gewaehlte Kennung), `detail: bool`, `editing: string` (`"" | "new" | "title" | "labels" | "project" | "filter"`), `filter: string`, `showArchive: bool`, `err: string`.
  - `cards(status: string) -> list` (gefiltert nach `tab`, `filter`, `showArchive`; sortiert: Prio hoch->niedrig, dann `num`; `fertig` nach `mtime` absteigend).
  - `run(args: list<string>)`: neuer `Process` je Aufruf ueber `Component.createObject` (`command: [ticketPy, ...args]`, `stderr: StdioCollector`), `onExited(code)`: `code !== 0` -> `err = stderr.text.trim()`; danach `destroy()`. `ticketPy = Quickshell.env("HOME") + "/.config/sway/scripts/ticket.py"`.
  - `handle(name: string): bool` – einzige Tastenlogik (Tabelle unten); `Keys.onPressed` uebersetzt Qt-Tasten in Namen (`ev.text` fuer Buchstaben/Ziffern inkl. Grossbuchstaben, sonst `Return Escape Tab Backtab Left Right Up Down`).
  - `IpcHandler { target: "tickets" }`: `toggle()`, `open()`, `close()`, `press(name: string)` -> `handle(name)`, `type(text: string)` -> Text des offenen Eingabefelds, `info(): string` -> `JSON.stringify({open, tab, col, key, detail, editing, err})`.
  - `TicketCard.qml`: `required property var t`, `property bool selected`; Signale `clicked()`. Inhalt laut Spec (Kennung, Prio-Zeichen ▲●▼, Titel max. 3 Zeilen, Label-Chips, `☑ a/b`, gedimmt wenn archiviert, roter Rand wenn `t.bad`).
  - `TicketDetail.qml`: `required property var t`; Signale `setField(field: string, value: string)`, `openNote()`, `closed()`. Inhalt laut Spec, Notiztext `textFormat: Text.MarkdownText` in `Flickable`.
- Maus (Spec, Abschnitt Tasten): Hover waehlt, Klick auf Karte = Detail, Klick auf Reiter / Filter-× / Archiv-Schalter / ✕ / Chips im Popup wie die Tasten. Drag & Drop kommt in Task 6.
- Fenster wie `gridWin` in `shell.qml`: `PanelWindow`, Overlay, alle Kanten, `ExclusionMode.Ignore`, `WlrKeyboardFocus.Exclusive`, Namespace `tickets`, Abdunkelung `Qt.rgba(0.08, 0.075, 0.06, 0.72)` mit MouseArea = schliessen, Board mit 40 px Rand (oben 30 + 40 wegen Waybar), Kasten `root.bg` + Rand `Qt.rgba(1, 0.86, 0, 0.5)`. `output` beim Oeffnen = `I3.focusedMonitor.name`. Board ploppt (scale 0.92 -> 1, OutBack 260 ms) wie das Raster; Auswahlrahmen gleitet federnd (wie Raster-Auswahl).
- `watch`-Prozess: `Process { running: true; command: [ticketPy, "watch"]; stdout: SplitParser { onRead: data => state = JSON.parse(data) } }`; `onExited` -> `Timer` 2 s -> `running = true`.
- Tasten -> Aufrufe (`K` = gewaehlte Kennung, `S` = `STATUSES`):

| Name | Wirkung |
|---|---|
| `h` `Left` / `l` `Right` | `col` +-1 (0..4), `key` = erste Karte der Spalte bzw. naechste nach Position |
| `j` `Down` / `k` `Up` | naechste / vorige Karte in `cards(S[col])` |
| `H` / `L` | `in-arbeit` voll (`state.wip >= 3`, Ziel `in-arbeit`, Karte nicht schon dort) -> `err = "Drei reichen fuer jetzt"`, kein Aufruf; sonst `run(["set", K, "status", S[col-1 / col+1]])`, `col` folgt |
| `Return` | `detail = true` (im Eingabefeld: absenden) |
| `Escape` | Eingabe abbrechen > Detail zu > Board zu |
| `n` | `editing = "new"`; absenden: `run(["quick", S[col], (tab && !/^[A-Za-z][A-Za-z0-9]*:/.test(text) ? tab + ": " : "") + text])` |
| `e` / `t` / `P` | `editing = "title" / "labels" / "project"`, Feld mit aktuellem Wert vorbelegt; absenden -> `run(["set", K, "title"/"labels"/"project", text])` |
| `p` | `run(["set", K, "prio", naechste])` (hoch -> mittel -> niedrig -> hoch) |
| `a` / `A` | `run(["set", K, "archived", t.archived ? "nein" : "ja"])` / `showArchive = !showArchive` |
| `o` | `run(["open", K])`, `open = false` |
| `Tab` `Backtab`, `0`-`9` | Reiter weiter/zurueck, `0` = ALLE, `n` = n-tes Projekt |
| `/` | `editing = "filter"`; absenden setzt `filter` (leer = aus) |

- [ ] **Step 1: Testdaten anlegen** (vor der Migration ist `Tickets/` leer):

```sh
T=~/.config/sway/scripts/ticket.py
for s in backlog todo in-arbeit review fertig; do $T new TEST "Karte $s mit einem etwas laengeren Titel" -s $s -l ui; done
$T new TEST2 "Zweites Projekt" -p hoch
```

- [ ] **Step 2: QML-Dateien schreiben** (Interfaces oben, Layout/Texte aus der Spec, Abschnitt Board).

- [ ] **Step 3: Pruefen per IPC + Screenshot**

```sh
Q=~/.local/bin/quickshell; P=/tmp/claude-1000/-home-osa-Private-wm-backup/7f8c579e-d7e0-4150-bcb1-aaa07b2d09ba/scratchpad
M=$(swaymsg -t get_outputs | jq -r '.[] | select(.focused).name')
$Q ipc call tickets open && sleep 0.6 && grim -o $M $P/board.png
$Q ipc call tickets press l; $Q ipc call tickets press L; sleep 1.2; $Q ipc call tickets info
$Q ipc call tickets press Return && sleep 0.5 && grim -o $M $P/detail.png && $Q ipc call tickets press Escape
$Q ipc call tickets press n; $Q ipc call tickets type "Neu aus IPC #x !hoch"; $Q ipc call tickets press Return; sleep 1.5
~/.config/sway/scripts/ticket.py list TEST
$Q ipc call tickets press Tab; $Q ipc call tickets info
$Q log | tail -20
```
Expected: `board.png` zeigt Kopf mit `ALLE`, `TEST`, `TEST2`, fuenf Spalten mit je einer Karte; nach `l L` ist die ToDo-Karte in `IN ARBEIT` (`info` zeigt `col: 2`); `detail.png` zeigt das Popup mit gerendertem Markdown (`## Ziel` als Ueberschrift); `list TEST` enthaelt `Neu aus IPC` mit `hoch` und `#x` in Spalte ToDo bzw. der gewaehlten Spalte; `Tab` setzt `tab: "TEST"`; im Log keine `ERROR`/`TypeError`/`ReferenceError`. Screenshots ansehen (Read).

- [ ] **Step 4: WIP- und Fehlerpfad**

```sh
T=~/.config/sway/scripts/ticket.py; $T new TEST "W1" -s in-arbeit; $T new TEST "W2" -s in-arbeit
$Q ipc call tickets press h; $Q ipc call tickets press L; $Q ipc call tickets info     # err = "Drei reichen fuer jetzt"
$Q ipc call tickets press P; $Q ipc call tickets type "1x"; $Q ipc call tickets press Return; sleep 1; $Q ipc call tickets info
```
Expected: erstes `info` mit `err` "Drei reichen fuer jetzt" (kein Aufruf); nach Projekt `1x` enthaelt `err` die stderr-Meldung `Projektname nur A-Z und 0-9, Beginn mit Buchstabe.` aus `ticket.py`.

- [ ] **Step 5: Aufraeumen + Commit**

```sh
rm -r ~/Private/obsidian-vault/Tickets/TEST ~/Private/obsidian-vault/Tickets/TEST2
$S sync-back; git status --short   # quickshell/{shell,Tickets,TicketCard,TicketDetail}.qml, sway/scripts/ticket.py
```
Commit: `HL2: Ticket-Board in Quickshell (Spalten, Tasten, Detail-Popup)`.

---

### Task 5: Umstellung – Migration, Tasten, Mission Control raus

**Files:**
- Modify: `~/.config/sway/config:445` und `:447`
- Modify: `~/.config/eww/eww.yuck` (Zeilen 106-177 Mission-Block raus; Zeile 463 `info`)
- Modify: `~/.config/eww/eww.scss`
- Delete: `~/.config/eww/scripts/todo.py` (Repo: `git rm eww/scripts/todo.py`)

**Interfaces:**
- Consumes: `ticket.py migrate`, `ticket.py quick`, IPC `tickets toggle`.

- [ ] **Step 1: Echte Migration**

Run: `~/.config/sway/scripts/ticket.py migrate && ~/.config/sway/scripts/ticket.py list WORK`
Expected: 15 Zeilen (18 Missionen minus 3 archivierte); `ls ~/Private/obsidian-vault/Tickets/WORK | wc -l` = 18; `data.json` und `Missionen/` unveraendert (`git`-frei, per `ls -l` Zeitstempel pruefen).

- [ ] **Step 2: sway-Binds**

```
bindsym $mod+Ctrl+m exec --no-startup-id sh -c '~/.config/sway/scripts/ask.sh "NEUES TICKET" | ~/.config/sway/scripts/ticket.py quick'
bindsym $mod+m exec --no-startup-id ~/.local/bin/quickshell ipc call tickets toggle
```
Run: `sway -C -c ~/.config/sway/config && swaymsg reload` — Expected: keine Ausgabe von `sway -C`, Reload ok. Danach `swaymsg exec '~/.local/bin/quickshell ipc call tickets toggle'` + Screenshot zeigt das Board mit den WORK-Tickets.

- [ ] **Step 3: eww aufraeumen**
  - `eww.yuck`: `deflisten missions`, `defvar mission_tab`, `mission-row`, `mission-list`, `defwindow mission` samt Kommentarzeile davor entfernen. `info`-Zeile 463 -> `(key :k "Super+m / Super+Ctrl+m" :d "Ticket-Board / Ticket schnell eintragen")`.
  - `eww.scss` entfernen: `.ms-item` (beide Zeilen 107-108), `.ms-item.focused`, `.ms-item.done .ms-text`, `.ms-text`, `.ms-check`, `.ms-actions`, `.ms-progress trough`, `.ms-progress progress`, `.ms-summary`, `.ms-empty`, `.ms-empty-symbol`, `.ms-foot`. **Behalten:** `.mission`, `.mission button:focus`, `.mission scrollbar slider`, `.ms-head .ms-lambda .ms-title .ms-subtitle .ms-tabs .ms-tab(.selected/:disabled) .ms-action(.selected) .ms-add(:hover/:disabled) .ms-error`. In den Sammel-Selektoren Zeile 116 (`.ms-action:hover, .ms-tab:hover, .ms-check:hover`) und 131 (`.ms-action, .ms-tab, .ms-check, .ms-add, .win, .btn`) nur `.ms-check` streichen.
  - `rm ~/.config/eww/scripts/todo.py`.

Run: `grep -n "ms-item\|ms-check\|ms-text\|ms-progress\|ms-summary\|ms-empty\|ms-foot\|ms-actions\|todo.py\|mission_tab\|missions" ~/.config/eww/eww.yuck ~/.config/eww/eww.scss; eww reload; sleep 1; eww open journal --screen "$M" && sleep 0.5 && grim -o $M $P/journal.png && eww close journal`
Expected: grep ohne Treffer; `journal.png` sieht aus wie vorher (Kopf, Reiter, Knoepfe gestylt). `eww logs | tail` ohne Fehler zu `.ms-`.

- [ ] **Step 4: Commit**

```sh
$S sync-back; git rm -q eww/scripts/todo.py; git status --short   # sway/config, eww/eww.yuck, eww/eww.scss, eww/scripts/todo.py (D)
```
Commit: `HL2: Super+m = Ticket-Board, Missionen migriert, Mission Control entfernt`.

---

### Task 6: Drag & Drop und Mikroanimationen

**Files:**
- Modify: `~/.config/quickshell/Tickets.qml`, `TicketCard.qml`, `TicketDetail.qml`

**Interfaces:**
- Consumes: `run`, `handle`, `cards`, IPC aus Task 4.
- Produces: keine neuen Schnittstellen; Drag & Drop ruft dieselbe Logik wie `H`/`L` (Funktion `moveTo(key: string, status: string)` in `Tickets.qml`, die `H`/`L` danach auch benutzen, inkl. WIP-Pruefung).

- [ ] **Step 1: `moveTo` herausziehen, `H`/`L` darauf umstellen; Drag & Drop** – Karte mit `Drag.active` auf `MouseArea.drag`, je Spalte eine `DropArea`; Loslassen ueber anderer Spalte -> `moveTo`, sonst zurueckfedern. Klick ohne Ziehen bleibt Detail-Popup (Schwelle `drag.threshold`).
- [ ] **Step 2: Animationen laut Spec, Abschnitt Animationen**, alle Punkte: Oeffnen/Schliessen (gestaffelte Spalten/Karten, λ atmet, Schliessen rueckwaerts und erst danach `visible = false`), Navigation (Rahmen ueber Spalten, Reiter-Markierung streckt sich, Reiterwechsel seitlich), Karten bewegen (fliegende Kopie, Luecke schliesst federnd, Ziehen hebt + kippt, Zielspalte leuchtet, WIP voll: Abprallen + `3/3` wackelt rot + Hinweis, Fertig: ~8 Funken + Haken mit `QtQuick.Shapes`, Zaehler rollen, Badge huepft), Karten (Ploppen mit Gluehen, Archiv klappt zusammen, Hover hebt, Prio-hoch-Strich atmet, Prio-Pfeil dreht, Checklisten-Zaehler blitzt), Detail-Popup waechst aus der Karte, Chips gleiten/druecken ein, Eingabefelder klappen federnd auf mit Caret, Fehlerzeile schuettelt/pulsiert/blendet nach 4 s aus, leere Spalte mit pulsierendem gestricheltem Rahmen. Weitere passende Mikroanimationen sind erlaubt (Osa: "ich liebe micro animation").
- [ ] **Step 3: Pruefen** – mit Testprojekt wie Task 4 Step 2 (Name `TEST`, danach loeschen):

```sh
$Q ipc call tickets open; sleep 0.15; grim -o $M $P/intro-mid.png; sleep 0.8; grim -o $M $P/intro-end.png
$Q ipc call tickets press L; sleep 0.15; grim -o $M $P/fly.png; sleep 1.2; grim -o $M $P/after.png
$Q ipc call tickets press Return; sleep 0.1; grim -o $M $P/detail-grow.png; $Q ipc call tickets press Escape
$Q ipc call tickets close; sleep 0.1; $Q ipc call tickets info; sleep 0.4; $Q log | grep -i "error\|warn" | tail
```
Expected: `intro-mid.png` zeigt einen Zwischenstand (Spalten noch nicht alle da), `intro-end.png` das fertige Board, `fly.png` die Karte zwischen zwei Spalten, `after.png` die Karte in der neuen Spalte; `detail-grow.png` ein Popup kleiner als final; nach `close` ist `info.open` false; Log ohne neue Fehler/Warnungen aus `Tickets*.qml`. Drag & Drop und Gefuehl testet Osa (Task 7).

- [ ] **Step 4: Aufraeumen + Commit** (`HL2: Ticket-Board – Drag & Drop und Mikroanimationen`).

---

### Task 7: Doku, Setup ausserhalb des Repos, Abnahme, Tag

**Files:**
- Modify: `CLAUDE.md` und `AGENTS.md` (identisch bis auf die zwei bekannten Zeilen), `.claude/skills/theme-erstellen/SKILL.md` und `.agents/skills/theme-erstellen/SKILL.md` (gleiche Aenderung, dort `AGENTS.md` statt `CLAUDE.md`)
- Modify (ausserhalb): `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`

- [ ] **Step 1: `CLAUDE.md`/`AGENTS.md`**
  - Komponenten-Tabelle: Zeile `sway/scripts/` um `ticket.py` (Tickets im Vault, CLI fuer Board und Agenten) ergaenzen; Zeile `eww/`: `Missionen mission (Super+m)` und `scripts/todo.py …` raus; Zeile `quickshell/`: `Tickets.qml` (+ Karte/Detail) = Ticket-Board Super+m.
  - "Nicht im Repo": `~/.local/bin/ticket` (Symlink), Hinweiszeilen in `~/.claude/CLAUDE.md` und `~/.codex/AGENTS.md`; Vault-Zeile: "Tickets (`Tickets/<PROJEKT>/`)" statt "Missionen-Notizen".
  - Standard-Bedienung: Absatz **Mission Control** ersetzen durch **Ticket-Board** (Kurzfassung der Spec: Ablage, Felder, Spalten, WIP 3, Tasten, Drag & Drop, Detail-Popup, `quick`, `ticket.py`-Befehle, Migration aus Missionen, Fehlerzeile). Tastenliste: `Super+m` = Ticket-Board, `Super+Ctrl+m` = Ticket schnell eintragen (`PROJ: Titel #label !prio`). Einleitungssatz "ergaenzt in HL2-v5 bis HL2-v29" -> `HL2-v30`.
  - Bausteinliste fuer neue Themes: `ticket.py`, `Tickets.qml`/`TicketCard.qml`/`TicketDetail.qml` statt `mission`/`todo.py`; `.ms-*` nur noch "vom Journal-Panel benutzt".
  - Stolperfallen: Satz zu `todo.py new`/`todo.py add` streichen bzw. auf Journal/`ask.sh` beschraenken; `(Mission Control: 10m)` raus.
  - Tag-Tabelle: Zeile `HL2-v30` – "wie v29, Ticket-Board statt Mission Control: Tickets als Markdown im Obsidian-Vault (`Tickets/<PROJEKT>/`), Board mit Backlog/ToDo/In Arbeit/Review/Fertig in Quickshell (Super+m), Prio, Labels, Detail-Popup, Drag & Drop, CLI `ticket` fuer Agenten. **Aktueller Standard** fuer neue Themes"; bei `HL2-v29` die Markierung entfernen.
  Run: `diff <(sed 's/AGENTS.md/CLAUDE.md/g' AGENTS.md) CLAUDE.md` -> nur die bekannten zwei Abschnitte (Zeilen "Codex liest" und "Kopien pflegen").
- [ ] **Step 2: Skill `theme-erstellen` (beide Kopien):** "Missionen Super+m" -> "Ticket-Board Super+m (Quickshell `Tickets.qml`)", "Mission-Schnelleingabe Super+Ctrl+m" -> "Ticket-Schnelleingabe Super+Ctrl+m"; Bausteinliste: Mission Control -> Ticket-Board (Farben ueber `root` in `shell.qml`, `ticket.py` unveraendert); Probeliste: "Super+m (Ticket mit `'` anlegen, H/L schieben, viertes In Arbeit prallt ab, Detail, Obsidian oeffnen, Drag & Drop)"; Satz "Missionen behalten Ansichts-Ueberblendungen" raus.
  Run: `diff <(sed 's/AGENTS.md/CLAUDE.md/g' .agents/skills/theme-erstellen/SKILL.md) .claude/skills/theme-erstellen/SKILL.md` -> nur die bekannte Zeile 56.
- [ ] **Step 3: Agenten-Hinweis** (ausserhalb des Repos, je eine Zeile ans Ende):
  `~/.claude/CLAUDE.md` und `~/.codex/AGENTS.md`: `Tickets/Aufgaben: \`ticket list|show|new|set|quick\` (Obsidian-Vault Tickets/<PROJEKT>/). Status/Prio/Projekt/Labels nur per \`ticket set\`, Notiztext der Datei darf direkt bearbeitet werden. Bei Arbeit an einem Ticket: \`ticket set KEY status in-arbeit\`, fertig -> \`review\`.`
- [ ] **Step 4: Commit Doku** (`HL2: Doku Ticket-Board`).
- [ ] **Step 5: Abnahme durch Osa** – Osa bittet, Super+m auszuprobieren (Liste aus Step 2). Rueckmeldungen als eigene Commits einarbeiten.
- [ ] **Step 6: Tag nach OK von Osa**

```sh
$S sync-back && git status --short   # leer
git tag -a HL2-v30 -m "HL2-v30: Ticket-Board statt Mission Control (Tickets im Obsidian-Vault, Board in Quickshell, CLI fuer Agenten)"
echo HL2-v30 > ~/.local/state/wm-theme && $S status   # sauber
```
Push (`git push origin master HL2-v30`) nur nach ausdruecklichem OK.
