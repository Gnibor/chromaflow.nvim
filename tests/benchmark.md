# `benchmark.lua`

`benchmark.lua` ist das gemeinsame kleine Benchmark-Modul der portablen Neovim-Umgebung und der ChromaFlow-Tests.

Es misst synchrone Lua-/Neovim-Aufrufe mit `vim.uv.hrtime()`, erzeugt statistische Samples und gibt `min`, `avg`, `p50`, `p90`, `p95`, `p99` und `max` aus.

Die beiden verwendeten Kopien sollen dieselbe Implementierung enthalten:

```text
config/nvim/lua/tools/benchmark.lua
nvim-plugins/cf.nvim/tests/benchmark.lua
```

Die Kopie unter `tests/` erlaubt den ChromaFlow-Benchmarks, dieselbe Messlogik direkt neben den Tests zu verwenden. `full_benchmark.lua`, `colortrace_benchmark.lua` und `float_benchmark.lua` bevorzugen diese lokale Kopie und fallen nur auf `tools.benchmark` zurück, wenn sie nicht vorhanden ist.

---

## Grundidee

Ein Benchmark besteht aus mehreren **statistischen Samples**. Ein Sample kann wiederum mehrere echte Funktionsaufrufe enthalten.

Beispiel:

```vim
:ModuleBenchmark 100 batch=10 cf reload()
```

bedeutet:

```text
100 Samples × 10 echte cf.reload()-Aufrufe pro Sample
```

Die Zeit eines Samples wird durch die Anzahl der Aufrufe im Batch geteilt. Die ausgegebene Zeit ist daher immer die durchschnittliche Zeit **pro echtem Funktionsaufruf**, nicht die Gesamtzeit des Batches.

`batch` ist besonders für sehr kleine Funktionen wichtig, weil dadurch der Anteil der Timer-Grenzen an der Messung kleiner wird.

---

## Ausgabe

Eine typische Ausgabe sieht so aus:

```text
cf.reload()
  count : 100 samples × 10 calls
  min   : 18.624 ms
  avg   : 23.244 ms
  p50   : 23.545 ms
  p90   : 25.052 ms
  p95   : 25.328 ms
  p99   : 25.733 ms
  max   : 27.307 ms
```

Die Werte bedeuten:

| Wert | Bedeutung |
| --- | --- |
| `count` | Anzahl statistischer Samples; bei `batch > 1` zusätzlich Aufrufe pro Sample |
| `min` | schnellstes Sample |
| `avg` | arithmetischer Mittelwert aller Samples |
| `p50` | Median / 50. Perzentil |
| `p90` | 90 % der Samples liegen höchstens bei diesem Wert |
| `p95` | 95. Perzentil |
| `p99` | 99. Perzentil |
| `max` | langsamstes Sample |

Die Perzentile verwenden die einfache **nearest-rank**-Variante mit `ceil(n * p)`.

Die interne Messgröße ist Mikrosekunden pro Aufruf. Die Ausgabe formatiert automatisch als `µs`, `ms` oder `s`.

---

# `:ModuleBenchmark`

Nach `require("tools.benchmark").setup()` steht der User-Command `:ModuleBenchmark` zur Verfügung.

## Syntax

```vim
:ModuleBenchmark <count> [batch=<n>] <module> <function(args...)> [...]
```

Beispiel:

```vim
:ModuleBenchmark 100 batch=10 cf reload()
```

Ohne Batch:

```vim
:ModuleBenchmark 1000 cf reload()
```

Mehrere Funktionen desselben Moduls können in einem Aufruf gemessen werden:

```vim
:ModuleBenchmark 100 batch=10 my.module first() second(1, "test")
```

Jede Funktion bekommt dabei einen eigenen Benchmark und eigene Statistik.

## Argumente

Funktionsargumente werden als Lua-Ausdruck ausgewertet.

Beispiele:

```vim
:ModuleBenchmark 100 my.module foo(123)
:ModuleBenchmark 100 my.module foo("text", true)
:ModuleBenchmark 100 my.module foo({ 1, 2, 3 })
```

Leerzeichen innerhalb von Strings, Tabellen, Klammern und anderen geschachtelten Lua-Ausdrücken werden vom Command-Parser berücksichtigt.

Die Argumente werden intern über `load()` ausgewertet. Der Command ist daher für lokale, vertrauenswürdige Benchmark-Aufrufe gedacht und nicht für ungeprüfte fremde Eingaben.

---

# Benchmark-Sessions

Mehrere Benchmarks können gesammelt und anschließend gemeinsam in einem Scratch-Buffer angezeigt werden.

```vim
:ModuleBenchmark start
:ModuleBenchmark 100 batch=10 cf reload()
:ModuleBenchmark 1000 batch=100 my.module foo()
:ModuleBenchmark stop
```

`start` leert die bisherige Session und aktiviert das Sammeln.

Während einer aktiven Session werden Ergebnisse nicht sofort gedruckt, sondern gespeichert.

`stop` öffnet einen Scratch-Buffer:

```text
ModuleBenchmark://results
```

mit allen gesammelten Ergebnissen.

Der Buffer ist:

```text
buftype=nofile
bufhidden=wipe
swapfile=false
filetype=benchmark
```

Enthält die Session keine Ergebnisse, wird nur eine Info-Meldung ausgegeben.

---

# Lua-API

## `benchmark.run(name, fn, opts)`

Führt einen Benchmark aus und gibt das Ergebnis als Tabelle zurück.

```lua
local benchmark = require("tools.benchmark")

local result = benchmark.run(
    "my benchmark",
    function()
        work()
    end,
    {
        count = 100,
        batch = 10,
        warmup = 25,
    }
)
```

`run()` erzeugt selbst **keine Ausgabe** und speichert das Ergebnis auch nicht automatisch in einer Session.

### Optionen

```lua
{
    count = 1000,
    batch = 1,
    warmup = 25,
    collect_gc = true,
    setup = nil,
    before = nil,
    after = nil,
    teardown = nil,
}
```

### `count`

Anzahl der statistischen Samples.

Standard:

```lua
1000
```

Muss eine positive Ganzzahl sein.

### `batch`

Anzahl echter Funktionsaufrufe pro Sample.

Standard:

```lua
1
```

Muss eine positive Ganzzahl sein.

Ein Sample misst:

```text
start timer
fn()
fn()
...
fn()
stop timer
```

und speichert anschließend:

```text
Gesamtzeit / batch
```

Dadurch bleiben die Statistiken auf **Zeit pro Aufruf** normiert.

### `warmup`

Anzahl ungemessener Aufrufe vor der eigentlichen Messung.

Standard:

```lua
25
```

Muss eine nichtnegative Ganzzahl sein.

Warmup ist unter LuaJIT besonders wichtig, damit erstmalige Pfade, Caches und JIT-Aufwärmung die eigentlichen Samples weniger stark verzerren.

### `collect_gc`

Standardmäßig wird **einmal vor Setup und Warmup** ausgeführt:

```lua
collectgarbage("collect")
```

Mit:

```lua
collect_gc = false
```

kann das abgeschaltet werden.

Es findet bewusst **kein GC vor jedem Sample** statt. GC-Pausen, die während einer realen Messserie auftreten, bleiben daher in den Verteilungswerten sichtbar.

### `setup`

Wird einmal vor dem Warmup ausgeführt.

```lua
setup = function()
    -- Testzustand vorbereiten
end
```

### `before`

Wird einmal **nach dem Warmup und unmittelbar vor der Messung** ausgeführt.

```lua
before = function()
    -- Zustand nach dem Warmup zurücksetzen
end
```

Das ist nützlich, wenn der Warmup Zustand verändert, der Messlauf aber von einem definierten Zustand beginnen soll.

### `after`

Wird einmal unmittelbar nach der Messung ausgeführt.

```lua
after = function()
    -- Messergebnis-unabhängige Nacharbeit
end
```

### `teardown`

Wird nach `after` ausgeführt.

```lua
teardown = function()
    -- temporären Testzustand aufräumen
end
```

### Reihenfolge

Die vollständige Reihenfolge von `run()` ist:

```text
optional collectgarbage("collect")
setup()
warmup: fn() × warmup
before()
measurement: count Samples × batch Aufrufe
after()
teardown()
```

Nur der Bereich `measurement` wird gemessen.

---

## `benchmark.bench(name, fn, opts)`

Wie `run()`, gibt das Ergebnis aber zusätzlich aus.

```lua
benchmark.bench("reload", function()
    cf.reload()
end, {
    count = 100,
    batch = 10,
})
```

Ist eine Benchmark-Session aktiv, wird das Ergebnis stattdessen in der Session gesammelt.

`bench()` gibt die Ergebnistabelle zusätzlich zurück.

---

## `benchmark.compare(tests, opts)`

Misst mehrere Tests mit gemeinsamen Optionen.

```lua
local results = benchmark.compare({
    {
        name = "old",
        fn = old_impl,
    },
    {
        name = "new",
        fn = new_impl,
        opts = {
            warmup = 50,
        },
    },
}, {
    count = 1000,
    batch = 100,
})
```

Jeder Eintrag braucht mindestens:

```lua
{
    fn = function() end,
}
```

Optional:

```lua
name = "..."
opts = { ... }
```

`test.opts` überschreibt die gemeinsamen Optionen für genau diesen Test.

`compare()` gibt nur die Ergebnisliste zurück. Es druckt und cached sie nicht automatisch.

---

## `benchmark.baseline(opts)`

Misst eine leere Lua-Funktion:

```lua
local baseline = benchmark.baseline({
    count = 1000,
    batch = 1000,
})
```

Die Baseline wird **nicht automatisch** von anderen Ergebnissen abgezogen.

Das ist absichtlich so: Bei sehr kleinen Messwerten kann automatisches Subtrahieren mehr verfälschen als helfen. Die Baseline ist nur ein separater Referenzwert für den Mess-Overhead.

---

## `benchmark.call(name, module_name, function_name, opts, ...)`

Hilfsfunktion zum direkten Benchmarken einer exportierten Modulfunktion.

```lua
local result = benchmark.call(
    "reload",
    "cf",
    "reload",
    {
        count = 100,
        batch = 10,
    }
)
```

Mit Argumenten:

```lua
benchmark.call(
    "lookup",
    "my.module",
    "lookup",
    {
        count = 1000,
        batch = 100,
    },
    "value",
    42
)
```

Das Modul wird einmal vor der Messung mit `require()` geladen. Der Funktionslookup geschieht ebenfalls vor der Messung.

Die Argumente werden vorab gebunden, damit der gemessene Hotpath nicht jedes Mal Tabellen für einen generischen Aufruf erzeugen muss. Für ein bis vier Argumente existieren spezialisierte Wrapper; breitere Aufrufe verwenden einen LuaJIT-5.1-kompatiblen `unpack`-Fallback.

---

## `benchmark.format(result)`

Formatiert ein einzelnes Ergebnis oder eine Ergebnisliste als String.

```lua
local text = benchmark.format(result)
```

Auch möglich:

```lua
local text = benchmark.format(results)
```

wenn `results` eine Liste von Benchmark-Ergebnissen ist.

---

## `benchmark.print(result)`

Formatiert das Ergebnis mit `benchmark.format()` und gibt es mit `print()` aus.

```lua
benchmark.print(result)
```

---

## `benchmark.start()`

Startet eine Sammel-Session.

```lua
benchmark.start()
```

Eine bereits vorhandene Ergebnisliste wird dabei verworfen.

---

## `benchmark.stop()`

Beendet die aktive Session und öffnet den Ergebnis-Scratch-Buffer.

```lua
benchmark.stop()
```

Ohne aktive Session wird nur eine Warnung ausgegeben.

---

## `benchmark.is_active()`

Gibt zurück, ob gerade eine Session aktiv ist.

```lua
if not benchmark.is_active() then
    benchmark.start()
end
```

Das wird beispielsweise von größeren Benchmark-Suites benutzt, damit sie eine bereits vom Benutzer gestartete Session nicht übernehmen oder vorzeitig beenden.

---

## `benchmark.setup(opts)`

Registriert den User-Command:

```text
:ModuleBenchmark
```

```lua
require("tools.benchmark").setup({
    warmup = 25,
    collect_gc = true,
})
```

Die übergebenen Optionen werden als Defaults für Benchmarks verwendet, die über `:ModuleBenchmark` gestartet werden.

Der Command überschreibt dabei selbst:

```text
count
batch
```

mit den Werten aus der Kommandozeile.

Für den Warmup gilt beim Command zusätzlich:

```lua
warmup = math.min(configured_warmup, count)
```

Ein Benchmark mit nur fünf Samples bekommt bei einem Standard-Warmup von 25 also höchstens fünf Warmup-Aufrufe.

---

# Ergebnisstruktur

`run()`, `bench()`, `baseline()` und `call()` liefern eine Tabelle dieser Form:

```lua
{
    name = "benchmark name",
    batch = 10,
    count = 100,
    min = ...,
    avg = ...,
    p50 = ...,
    p90 = ...,
    p95 = ...,
    p99 = ...,
    max = ...,
}
```

Die Zeitwerte sind intern **Mikrosekunden pro echtem Aufruf**.

---

# Was tatsächlich gemessen wird

Das Modul misst synchrone Laufzeit zwischen zwei `vim.uv.hrtime()`-Aufrufen.

Das bedeutet:

- Lua-Code wird normal gemessen.
- synchrone Neovim-API-Aufrufe werden normal gemessen.
- `require()` gehört nur dann zur Messung, wenn es innerhalb von `fn` steht.
- Setup, Argument-Binding und Funktionslookup gehören bei `benchmark.call()` nicht zur Messung.
- nur das Einplanen asynchroner Arbeit misst **nicht** automatisch deren spätere Ausführung.

Eine Funktion wie:

```lua
function()
    vim.schedule(expensive_work)
end
```

misst im Wesentlichen nur `vim.schedule()`, nicht `expensive_work`.

Für asynchrone Abläufe muss der Benchmark selbst einen synchron messbaren Abschluss definieren.

---

# Zustandsbehaftete Benchmarks

Die Benchmark-Funktion wird sehr oft ausgeführt:

```text
warmup + count × batch
```

Bei:

```lua
{
    warmup = 25,
    count = 100,
    batch = 10,
}
```

sind das insgesamt:

```text
25 + 1000 = 1025 Aufrufe
```

Deshalb muss bei mutierenden Funktionen bewusst entschieden werden, ob jeder Aufruf auf dem Zustand des vorherigen aufbauen darf.

Das Modul besitzt absichtlich keinen automatischen Reset zwischen Samples oder Calls. Ein solcher Reset wäre selbst Teil der Messung oder würde die tatsächliche Semantik des zu testenden Codes verstecken.

Wenn ein definierter Startzustand benötigt wird, können `setup`, `before`, `after` und `teardown` verwendet werden. Für einen Reset **vor jedem einzelnen gemessenen Aufruf** muss dieser Reset ausdrücklich Bestandteil der Benchmark-Funktion oder der zu benchmarkenden Testhülle sein.

---

# Interpretation der Zahlen

Für Optimierungsarbeit sind `avg` und `p50` nützlich, aber nicht ausreichend.

Gerade bei Neovim/LuaJIT können einzelne Samples durch folgende Dinge langsamer werden:

- Garbage Collection,
- JIT-Kompilierung oder Trace-Wechsel,
- Dateisystemzugriffe,
- Autocmds,
- Scheduler-/Eventloop-Arbeit,
- Kernel-Scheduling,
- kalte Caches.

Darum sind besonders `p90`, `p95`, `p99` und `max` wichtig, wenn nicht nur der Mittelwert, sondern auch die Stabilität eines Hotpaths beurteilt werden soll.

Ein kleineres `min` allein bedeutet nicht automatisch, dass eine Implementierung insgesamt schneller geworden ist.

Für Vergleiche sollten möglichst dieselben Bedingungen verwendet werden:

```text
selbe Neovim-Instanz / Umgebung
selber Theme-/Plugin-Zustand
selbe count-/batch-/warmup-Werte
selbe optionalen Features
möglichst keine parallelen externen Lastspitzen
```

---

# Designregeln des Moduls

Das Benchmark-Modul ist bewusst klein gehalten.

Es soll:

- für Mikrobenchmarks wenig eigenen Overhead erzeugen,
- LuaJIT-freundlich bleiben,
- keine automatische statistische „Korrektur“ vornehmen,
- Samples und echte Calls klar voneinander trennen,
- dieselbe Messlogik für einzelne Tests und große Benchmark-Suites bereitstellen,
- auch ohne aktive Session direkt benutzbar sein.

Daraus folgen einige bewusste Entscheidungen:

- kein automatisches Baseline-Subtrahieren,
- kein GC zwischen Samples,
- kein automatischer State-Reset,
- kein asynchrones Warten,
- kein Ranking oder künstlicher „Score“,
- keine versteckte Änderung der gemessenen Funktion.

Die Statistik soll möglichst direkt zeigen, **was unter den gewählten Bedingungen tatsächlich passiert ist**.
