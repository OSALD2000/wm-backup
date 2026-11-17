// Test des Trainers (tools/nav-trainer.html): node tests/trainer.cjs
// Spielt in jedem Level Runden mit dem angezeigten kuerzesten Weg; jede Aufgabe
// muss damit gelingen (kein verlorenes Leben, keine Fehltaste).
const fs = require("fs"), vm = require("vm"), assert = require("assert")
const html = fs.readFileSync(__dirname + "/../tools/nav-trainer.html", "utf8")
const script = html.match(/<script>([\s\S]*)<\/script>/)[1]
const el = () => ({ textContent: "", innerHTML: "", hidden: false, className: "", style: {}, dataset: {},
                    classList: { add() {}, remove() {} }, offsetWidth: 0 })
const els = {}, elementIds = new Set([...html.matchAll(/id="([\w-]+)"/g)].map(x => x[1]))
const timers = new Map()
let timerId = 0
const sb = { document: { body: {}, getElementById: id => {
               assert.ok(elementIds.has(id), `HTML-Element fehlt: ${id}`)
               return els[id] ||= el()
             }, addEventListener() {} },
             localStorage: { getItem: () => null, setItem() {} }, performance, console,
             setTimeout: f => { timers.set(++timerId, f); return timerId },
             clearTimeout: id => timers.delete(id), setInterval() {} }
vm.createContext(sb)
vm.runInContext(fs.readFileSync(__dirname + "/../quickshell/nav.js", "utf8"), sb)
vm.runInContext(script + ";this.T = () => ({ task, log, miss, lives, newRound, handleKey, LEVELS, MAKERS, COMMANDS, desk, snap, busy, learning, store, proceed, showHint, startKind, command })", sb)

const commands = Object.keys(JSON.parse(fs.readFileSync(__dirname + "/../quickshell/commands/commands.json", "utf8")))
assert.deepStrictEqual(Array.from(vm.runInContext("COMMANDS", sb)).sort(), commands.sort(), "Trainer muss alle echten Befehle anbieten")

function type(text) {
  for (const k of text) {
    if (sb.T().busy) break
    if (k === "⏎") sb.T().handleKey("Enter", "")
    else if (k === "⇥") sb.T().handleKey("Tab", "")
    else sb.T().handleKey("", k)
  }
}
function tick() {
  for (const [id, f] of [...timers]) { timers.delete(id); f() }
}

// Befehlseffekte mit festen Erwartungen, unabhaengig von den Aufgabengeneratoren.
const fixture = () => ({
  ws: { a1: [{ id: 1, name: "Firefox", title: "Alt", group: 0 }], s2: [{ id: 2, group: 0 }], d6: [{ id: 3, group: 0 }] },
  visible: { a: 1, s: 2, d: 6 }, here: "a", focus: 1, full: 0, last: {}, prev: null, parked: {}, notes: {}, tickets: []
})
const run = (d, text) => sb.T().command(d, JSON.parse(JSON.stringify(d)), text)
const d = fixture()
run(d, "park Mittagspause")
assert.deepStrictEqual(JSON.parse(JSON.stringify(d.parked.Mittagspause)), { 1: "a1", 2: "s2" })
assert.deepStrictEqual(Array.from(d.ws.d6, x => x.id).sort(), [1, 2, 3])
run(d, "unpark Mittagspause")
assert.deepStrictEqual(Array.from(d.ws.a1, x => x.id), [1])
assert.deepStrictEqual(Array.from(d.ws.s2, x => x.id), [2])
assert.deepStrictEqual(Array.from(d.ws.d6, x => x.id), [3])
assert.ok(!d.parked.Mittagspause)
for (const name of ["constructor", "__proto__"]) {
  const special = fixture()
  run(special, "park " + name)
  assert.ok(Object.hasOwn(special.parked, name), "Sessionnamen muessen normale Schluessel sein: " + name)
  run(special, "unpark " + name)
  assert.deepStrictEqual(Array.from(special.ws.a1, x => x.id), [1])
  assert.ok(!Object.hasOwn(special.parked, name))
}
run(d, "note Trading/Ideen/NQ Bias #idee #arbeit")
assert.deepStrictEqual(Array.from(d.notes["Trading/Ideen/NQ Bias.md"].tags), ["idee", "arbeit"])
run(d, "note Trading/Ideen/NQ Bias #neu")
assert.deepStrictEqual(Array.from(d.notes["Trading/Ideen/NQ Bias.md"].tags), ["idee", "arbeit"], "Existierende Notizen nur oeffnen")
run(d, "ticket PRIVATE: Neue Idee #eins #zwei !niedrig !hoch")
assert.deepStrictEqual(JSON.parse(JSON.stringify(d.tickets[0])), {
  project: "PRIVATE", title: "Neue Idee", labels: ["eins", "zwei"], prio: "hoch", status: "todo"
})
run(d, "open Firefox > s s")
assert.ok(d.ws.s2.some(w => w.name === "Firefox" && w.id !== 1))
assert.strictEqual(d.here, "s")
assert.throws(() => run(d, "open UnbekannteApp"), /keine App/)
assert.throws(() => run(d, "open Firefox > x"), /Ziel/)
assert.throws(() => run(d, "note #tag"), /Titel/)
assert.throws(() => run(d, "ticket WORK: #tag !hoch"), /Titel/)

// Identische App/Titel muessen anhand der Aufgabenstellung unterscheidbar sein.
const duplicate = fixture()
duplicate.ws = { a1: [{ id: 1, name: "Chrome", title: "Inbox" }], s2: [{ id: 2, name: "Chrome", title: "Inbox" }] }
duplicate.focus = 0; duplicate.treeSeen = 0
const treeTask = sb.T().MAKERS.all(duplicate)
assert.ok(treeTask.where && /^auf (A1|S2) · Fenster 1$/.test(treeTask.where), "Baum-Aufgabe muss das Ziel eindeutig benennen")
duplicate.focus = treeTask.where.includes("A1") ? 1 : 2; duplicate.treeSeen++
assert.ok(treeTask.ok(duplicate), "Ortsangabe muss zum gewerteten Fenster passen")

// Ein alter Test-Timer darf nach einem Moduswechsel keine Lernaufgabe ueberspringen.
sb.T().newRound(0, false)
type(sb.T().task.sol)
assert.ok(sb.T().busy)
sb.T().newRound(3, true)
const afterSwitch = sb.T().task
tick()
assert.strictEqual(sb.T().task, afterSwitch)

// Nach dem Parken muessen Folgeaufgaben wieder echte Ziele ausserhalb von D6 haben.
sb.T().startKind("park")
type(sb.T().task.sol)
sb.T().proceed()
assert.ok(Object.entries(sb.T().snap.ws).some(([k, wins]) => k !== "d6" && wins.length), "Folgeaufgabe nach Parken hat keine Fenster ausserhalb von D6")

// Jede Variante muss ausfuehrbar sein und ein noch nicht erreichtes Ziel haben.
for (const kind of Object.keys(sb.T().MAKERS)) {
  for (let i = 0; i < 25; i++) {
    sb.T().startKind(kind)
    const t = sb.T().task
    assert.strictEqual(t.kind, kind)
    assert.ok(!t.ok(sb.T().desk), `bereits geloest: ${kind}`)
    assert.ok(els.guide.textContent.length > 20, `Erklaerung fehlt: ${kind}`)
    type(t.sol)
    assert.ok(t.ok(sb.T().desk), `Musterloesung scheitert: ${kind} ${t.sol}`)
    assert.ok(sb.T().busy, `Lernmodus wartet nicht auf Weiter: ${kind}`)
    assert.ok(!sb.T().log.some(x => !x.ok), `Fehler: ${kind}`)
  }
}

// Fehler im Lernmodus: lesen, Ausgangszustand wiederherstellen, selbst loesen.
sb.T().startKind("clear")
const original = JSON.stringify(sb.T().desk), failedTask = sb.T().task
type("#only a⏎")
assert.ok(sb.T().busy)
assert.strictEqual(sb.T().task, failedTask)
assert.ok(els.sol.textContent.includes("#clear"))
sb.T().proceed()
assert.strictEqual(JSON.stringify(sb.T().desk), original, "Wiederholen muss alle Fenster zurueckbringen")
assert.strictEqual(sb.T().task, failedTask)
type("#clear⏎")
assert.ok(failedTask.ok(sb.T().desk))

// Lernhilfe und langsames Ueben duerfen die bisherigen Tempo-Bestwerte nicht veraendern.
const before = JSON.stringify({ best: sb.T().store.best, kinds: sb.T().store.kinds, rounds: sb.T().store.rounds })
const learnedBeforeHint = sb.T().store.learned.openTo
sb.T().startKind("openTo")
sb.T().showHint()
assert.ok(els.sol.textContent.includes(sb.T().task.sol))
type(sb.T().task.sol)
sb.T().proceed()
assert.strictEqual(JSON.stringify({ best: sb.T().store.best, kinds: sb.T().store.kinds, rounds: sb.T().store.rounds }), before)
assert.strictEqual(sb.T().store.learned.openTo, learnedBeforeHint, "Mit Hilfe gilt nicht als selbst geloest")

sb.T().newRound(6, true)
while (sb.T().task) {
  type(sb.T().task.sol)
  assert.ok(sb.T().busy)
  sb.T().proceed()
}
assert.strictEqual(sb.T().log.length, Object.keys(sb.T().MAKERS).length)
assert.strictEqual(JSON.stringify({ best: sb.T().store.best, kinds: sb.T().store.kinds, rounds: sb.T().store.rounds }), before)
assert.ok(!els.done.hidden, "Lernrunde muss eine Zusammenfassung anzeigen")

for (let level = 0; level < sb.T().LEVELS.length; level++) {
  for (let round = 0; round < 40; round++) {
    sb.T().newRound(level, false)
    for (let guard = 0; sb.T().task; guard++) {
      assert.ok(guard < 100, "Runde endet nicht")
      const t = sb.T().task
      for (const k of t.sol) {
        if (sb.T().task !== t) break
        type(k)
      }
      tick()
      assert.notStrictEqual(sb.T().task, t, `haengt: ${t.kind} ${t.text} -> ${t.sol}`)
    }
    const { log, miss } = sb.T()
    const bad = log.filter(x => !x.ok)
    assert.ok(!bad.length && !miss, `Level ${level}: ${miss} Fehltasten, Fehler: ${JSON.stringify(bad[0])}`)
    assert.strictEqual(log.length, Math.max(20, sb.T().LEVELS[level][1].length))
    assert.strictEqual(new Set(log.map(x => x.kind)).size, sb.T().LEVELS[level][1].length, "Jeder Typ muss in der Runde vorkommen")
  }
}
console.log(`ok: ${commands.length} Befehle, ${Object.keys(sb.T().MAKERS).length} Aufgabentypen, ${sb.T().LEVELS.length * 40} Tempo-Runden`)
