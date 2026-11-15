// Test des Trainers (tools/nav-trainer.html): node tests/trainer.cjs
// Spielt in jedem Level Runden mit dem angezeigten kuerzesten Weg; jede Aufgabe
// muss damit gelingen (kein verlorenes Leben, keine Fehltaste).
const fs = require("fs"), vm = require("vm"), assert = require("assert")
const html = fs.readFileSync(__dirname + "/../tools/nav-trainer.html", "utf8")
const script = html.match(/<script>([\s\S]*)<\/script>/)[1]
const el = () => ({ textContent: "", innerHTML: "", hidden: false, className: "", style: {}, dataset: {},
                    classList: { add() {}, remove() {} }, offsetWidth: 0 })
const els = {}
const sb = { document: { getElementById: id => els[id] ||= el(), addEventListener() {} },
             localStorage: { getItem: () => null, setItem() {} }, performance, console,
             setTimeout: f => f(), setInterval() {} }
vm.createContext(sb)
vm.runInContext(fs.readFileSync(__dirname + "/../quickshell/nav.js", "utf8"), sb)
vm.runInContext(script + ";this.T = () => ({ task, log, miss, lives, newRound, handleKey })", sb)

for (let level = 0; level < 7; level++) {
  for (let round = 0; round < 40; round++) {
    sb.T().newRound(level)
    for (let guard = 0; sb.T().task; guard++) {
      assert.ok(guard < 100, "Runde endet nicht")
      const t = sb.T().task
      for (const k of t.sol) {
        if (sb.T().task !== t) break
        k === "⏎" ? sb.T().handleKey("Enter", "") : sb.T().handleKey("", k)
      }
      assert.notStrictEqual(sb.T().task, t, `haengt: ${t.kind} ${t.text} -> ${t.sol}`)
    }
    const { log, miss } = sb.T()
    const bad = log.filter(x => !x.ok)
    assert.ok(!bad.length && !miss, `Level ${level}: ${miss} Fehltasten, Fehler: ${JSON.stringify(bad[0])}`)
    assert.strictEqual(log.length, 20)
  }
}
console.log("ok")
