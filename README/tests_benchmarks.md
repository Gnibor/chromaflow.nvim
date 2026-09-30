# Tests and benchmarks

## Contents

- [Regression tests](#regression-tests)
- [What the tests cover](#what-the-tests-cover)
- [Benchmarks](#benchmarks)
  - [Full ChromaFlow benchmark](#full-chromaflow-benchmark)
  - [Reading benchmark numbers](#reading-benchmark-numbers)
  - [Samples, batches, warmup and GC](#samples-batches-warmup-and-gc)
  - [Interpreting the four full-benchmark scenarios](#interpreting-the-four-full-benchmark-scenarios)
  - [Comparing benchmark runs](#comparing-benchmark-runs)
  - [Troubleshooting poor benchmark results](#troubleshooting-poor-benchmark-results)
  - [ColorTrace benchmark](#colortrace-benchmark)
  - [Float benchmark](#float-benchmark)
  - [`tests/benchmark.lua` and `:ModuleBenchmark`](#testsbenchmarklua-and-modulebenchmark)
  - [Which benchmark should I use?](#which-benchmark-should-i-use)

ChromaFlow keeps its regression tests and performance probes under `tests/`.
The test suite is deliberately plain: the headless tests are Lua scripts built from
normal Neovim APIs and `assert()`, while the benchmark files use the shared
`tests/benchmark.lua` measurement engine.

Run the commands in this document from the **cf.nvim repository root** unless a
section explicitly says otherwise. Several tests resolve `examples/themes/` and
other files through `vim.fn.getcwd()`.

The complete regression suite also expects a working Lua Tree-sitter parser for the
source-range tests used by picker/save tooling. Normal ChromaFlow compilation does
not require that parser merely to keep start positions, but tests that verify full
source ranges intentionally require it.

---

## Regression tests

A regression test succeeds when every assertion completes. Most scripts print an
`OK` line at the end. An assertion error, Lua error or non-zero Neovim exit status
means the test failed.

Each test should normally get its own Neovim process. This prevents caches,
highlights, runtime overrides, watchers or previous test state from leaking into the
next test.

### Run one test

From the plugin root:

```sh
nvim --headless -u NONE -i NONE -l tests/resolver_headless.lua
```

Replace the filename with the test you want to run.

`vimenter_headless.lua` is the exception. It must execute as the init file so the
test can call `cf.setup()` before `VimEnter`:

```sh
nvim --headless -i NONE -u tests/vimenter_headless.vim
```

### Run the complete suite

```sh
set -e

for test in tests/*_headless.lua; do
    [ "$test" = "tests/vimenter_headless.lua" ] && continue
    echo "==> $test"
    nvim --headless -u NONE -i NONE -l "$test"
done

nvim --headless -u NONE -i NONE -l tests/real_theme_smoke.lua
nvim --headless -i NONE -u tests/vimenter_headless.vim
```

The loop intentionally starts a fresh Neovim for every file. `real_theme_smoke.lua`
is run separately because it is a smoke test rather than an `_headless.lua` file.

---

## What the tests cover

The filenames are intentionally narrow. When a regression appears, run the closest
focused test first and then the broader integration tests around it.

### Resolver, highlight compilation and theme application

| Test | Main coverage |
| --- | --- |
| `resolver_headless.lua` | Resolver contracts, normal/filetype forms, Type/Mod/TypeMod handling, target filtering, fallback materialization and warm-call allocation behavior. |
| `highlight_headless.lua` | Group/style compilation, links, direct-style caching, style interning, priorities, clears and useless-group diagnostics. |
| `theme_headless.lua` | Theme selection, palette/config use, active/default fallback by setup identity, raw groups, language/plugin/UI modules and applied styles. |
| `semantic_theme_headless.lua` | Broad integration pass over the bundled semantic reference theme, including target ownership, many TypeMods, reload behavior and style interning. |
| `dark_theme_headless.lua` | Bundled `dark` theme smoke/regression checks for core Vim, Tree-sitter and LSP highlight results. |
| `dark_theme_hint_headless.lua` | Ensures known dark-theme TypeMods do not incorrectly produce unresolved fallback hints. |
| `reference_themes_headless.lua` | The small reference themes: selection, reserved-file fallback, setup-identity fallback and target configuration. |
| `real_theme_smoke.lua` | Large bundled-theme smoke test: module/action count and representative Vim/TS/LSP/diagnostic highlights. |
| `group_validation_headless.lua` | Invalid group fields/containers/pipelines, declaration-local failure behavior and diagnostic reporting. |
| `group_type_hint_headless.lua` | Type-only unresolved fallback materialization and the corresponding hint behavior. |
| `typemod_rollback_headless.lua` | Invalid TypeMods roll back only their own action and do not discard valid base/sibling actions. |
| `cterm_headless.lua` | xterm-256 conversion, terminal pipeline channels and cterm behavior through compiled/runtime styles. |

### Reload, startup and watcher lifecycle

| Test | Main coverage |
| --- | --- |
| `reload_headless.lua` | Full colorscheme rebuild lifecycle, `ColorSchemePre`/`ColorScheme`, complete highlight reset, style-cache persistence and optional TS/LSP consumer refresh. |
| `vimenter_headless.lua` + `vimenter_headless.vim` | Initial setup before `VimEnter`; verifies ChromaFlow waits until the event has fully completed before resolving/applying the theme. |
| `theme_switch_watcher_headless.lua` | Watcher recovery when a theme switch/default-theme change fails. |
| `runtime_watcher_headless.lua` | File watching for active/root/default `runtime/` locations and watcher batching. |

### Runtime modules

| Test | Main coverage |
| --- | --- |
| `runtime_headless.lua` | Runtime apply/replace/reset/clear, reload rebasing, raw/resolved targets, runtime module lookup and public runtime behavior. |
| `runtime_setup_headless.lua` | Runtime DSL setup, module-local functions, timed callbacks, frame timing, group aliases and invalid pipeline/tick combinations. |
| `runtime_affected_headless.lua` | A runtime change only recomputes the affected target instead of unrelated overrides. |
| `runtime_override_transaction_headless.lua` | Failed runtime operations do not partially mutate or discard existing override state. |
| `lsd_demo_headless.lua` | The bundled runtime colour-fade showcase: apply, timed advance and restoration of the normal theme base. |

### Diagnostics and ColorTrace

| Test | Main coverage |
| --- | --- |
| `diagnostic_headless.lua` | Severity/message policy, bias, visible-buffer diagnostics, hidden/other-tab ASSERT fallback and batching. |
| `diagnostic_wiring_headless.lua` | Root configuration wiring, producer gating, module-local failures/ignored files, flush lifecycle and ASSERT batching. |
| `colortrace_headless.lua` | ColorTrace lifecycle, picker-backed trace cache reuse, visible/hidden source behavior and failed-compile cache safety. |
| `colortrace_diagnostic_headless.lua` | Per-pipeline-operation source ranges, diagnostic ordering/codes and buffer flushing of ColorTrace output. |

### Picker, source ranges and save

| Test | Main coverage |
| --- | --- |
| `picker_headless.lua` | Main CFPick edit/style menu flow and cursor-derived targets. |
| `picker_style_headless.lua` | Tri-state style editing, sparse runtime preview/cancel/commit and reuse of normal style interning. |
| `picker_mods_headless.lua` | Session Mod/TypeMod discovery, menu state, TypeMod creation/removal and source persistence. |
| `picker_keyword_headless.lua` | Keyword TypeMod navigation and saving a TypeMod rule without rewriting the base declaration. |
| `picker_ts_reverse_headless.lua` | Tree-sitter capture classification used by picker reverse lookup. |
| `picker_cursor_sources_headless.lua` | Cursor source collection/selection from the available inspection sources. |
| `picker_source_choice_headless.lua` | Choosing the correct language/generic source owner when creating or detaching editable rules. |
| `picker_priority_headless.lua` | Priority handling when picker resolves/editable actions compete. |
| `picker_pipeline_headless.lua` | Five-channel pipeline editor, palette selection, FG/BG fallbacks for CFG/CBG, gamma UI scaling, preview/cancel and source persistence. |
| `source_ranges_headless.lua` | Full declaration/source ranges while picker is enabled, runtime-group ranges and start-only fallback when the Lua parser is unavailable. |
| `save_headless.lua` | `CFSave` rewriting of styles, Mods and TypeMods; unchanged/unrepresentable edits; syntax validation; command registration. |
| `menu_headless.lua` | Shared float-menu controls: numeric adjustment, Space, Backspace and cancel behavior. |

`luals_module_demo.lua` is a LuaLS/DSL example file, not a headless regression test.

---

# Benchmarks

Benchmarks answer a different question from the regression suite. A test asks
whether behavior is correct; a benchmark repeatedly executes a known operation and
reports its timing distribution.

The canonical files are:

| File | Purpose |
| --- | --- |
| `tests/full_benchmark.lua` | Full ChromaFlow benchmark and formatted Markdown report |
| `tests/colortrace_benchmark.lua` | Focused ColorTrace decomposition |
| `tests/float_benchmark.lua` | Focused `cf.fn.float` renderer benchmark |
| `tests/benchmark.lua` | Shared measurement engine |
| `tests/benchmark.md` | Benchmark helper/reference notes |

`tests/benchmark.lua` is the common measurement engine. The other benchmark files
decide what to measure and which sample/batch profile makes sense for that work.

---

## Full ChromaFlow benchmark

`full_benchmark.lua` is the main benchmark to use when comparing ChromaFlow
versions or checking whether a change moved work between subsystems.

It measures the same theme in four separate setup scenarios:

| Scenario | Picker | ColorTrace |
| --- | ---: | ---: |
| Minimal | off | off |
| Picker | on | off |
| ColorTrace | off | on |
| Picker + ColorTrace | on | on |

Every scenario starts from the same explicit ChromaFlow benchmark setup. The caller's
previous configuration is restored when the report is finished.

### Run it

Run it from a normal Neovim session after `VimEnter`. No previous `cf.setup()` is
required; `start()` performs the benchmark setup itself.

For an installed plugin, the important command is:

```vim
:lua dofile(vim.api.nvim_get_runtime_file("tests/full_benchmark.lua", false)[1]).start()
```

That uses the bundled `examples/themes` tree.

To benchmark another ChromaFlow theme root:

```vim
:lua dofile(vim.api.nvim_get_runtime_file("tests/full_benchmark.lua", false)[1]).start("/path/to/themes")
```

When running directly from a checkout that is not already on `runtimepath`, start
Neovim from the repository root with the checkout on `runtimepath`, for example:

```sh
cd /path/to/cf.nvim
nvim -u NONE -i NONE --cmd 'set runtimepath^=.'
```

Then run the same `:lua ...start()` command.

### Output

The full benchmark opens a scratch buffer named:

```text
ChromaFlowBenchmark://full
```

Its `filetype` is `markdown`. The report is deliberately formatted as Markdown so
it can be read directly in Neovim or copied as a complete benchmark report.

The report starts with the user-facing operations, then gives the white-box
breakdown and the four-scenario comparisons.

### What it benchmarks

The full report groups probes by purpose:

| Section | What is measured |
| --- | --- |
| Measurement baseline | Empty Lua closure through the same benchmark engine. |
| User-facing end-to-end | `cf.reload()`, complete load, `theme.load()`, compile-only and apply of a precompiled theme. |
| Theme discovery/source loading | Theme selection, directory/file discovery, reserved files, `loadfile()`, chunk execution and initial compiler setup. |
| DSL compiler | Real captured declarations replayed through setup/module/group/style compiler functions. |
| Highlight resolver | Cold resolve after cache clear plus hot Type, Mod, TypeMod, filetype, unchanged/literal and per-target variants. |
| Colour engine/pipeline | Packed-colour conversion/manipulation, cterm conversion, pipeline construction and pipeline execution with different operation counts. |
| Highlight apply | Reset/catalog/cache-clear/global-clear, action flatten/sort, action execution and cached/cold `_apply_modules` paths. |
| Editor consumers/redraw | Tree-sitter refresh, LSP semantic-token refresh, redraw and configured combinations. |
| Runtime/picker/LineBlend/watcher | Runtime module loading, picker style state/write, LineBlend refresh/reload and watcher state/update calls. |
| Diagnostics/source tracing | Diagnostic gates/queues/flush and ColorTrace/picker source-trace cache paths active in that scenario. |
| Float renderer | Same-reference line update, span replacement, bulk line update/flush and hide/open behavior. |

The detailed sections intentionally overlap. For example, `theme.load()`, compile,
apply and individual compiler/apply probes can all include some of the same work at
different boundaries. **Do not add the detailed timings together.** They are
alternative views of the same execution path, not pieces of one accounting total.

### Checked-in reference runs

The repository includes a reproducible clean-state comparison under `tests/`:

- [`clean_state_benchmark_report_20260930-1045.md`](../tests/clean_state_benchmark_report_20260930-1045.md) — summary, host data and A/B interpretation;
- the two `full_benchmark_*.md` files next to it — complete raw reports.

The reference machine is an Intel i5-10310U (4 cores / 8 threads) running Neovim
0.12.5 with LuaJIT 2.1.1788856981. The bundled `dark` theme in that report contains
32 modules and 938 compiled actions. With `tests/benchmark.lua` open, average
`cf.reload()` is about **12.8 ms** Minimal, **18.9 ms** with Picker, **20.1 ms** with
ColorTrace and **23.1 ms** with both enabled.

These numbers are a comparison baseline, not a target every machine must match.
Use the raw reports to compare distributions and subsystem probes, and use the
clean-state procedure below before treating a large local difference as a
ChromaFlow regression.

---

## Reading benchmark numbers

A result from `tests/benchmark.lua` contains multiple statistical samples. A sample
may itself contain several real calls.

For example:

```text
count : 100 samples × 1000 calls
```

means the function was called 1000 times inside each timed sample. The measured
sample duration is divided by 1000 before it enters the statistics, so every shown
time is still **time per real call**, not time for the whole batch.

The fields mean:

| Field | Meaning |
| --- | --- |
| `min` | Fastest measured sample; useful as a lower bound, not as the typical cost. |
| `avg` | Arithmetic mean across all samples. |
| `p50` | Median; half of samples are at or below this value. |
| `p90` | 90% of samples are at or below this value. |
| `p95` | 95% of samples are at or below this value. |
| `p99` | 99% of samples are at or below this value. |
| `max` | Slowest sample; very sensitive to scheduler/GC/OS noise. |

The percentile implementation uses nearest-rank selection.

For user-visible operations such as reload, `avg` and `p50` describe the normal
cost, while `p95`/`p99` make tail behavior visible. A change that barely moves the
average but substantially worsens p99 can still be noticeable during repeated
interactive use.

For tiny resolver/colour/cache paths, compare the result to the measurement
baseline. The baseline is shown to make timer/closure cost visible; it is **not**
automatically subtracted from benchmark results.

---

## Samples, batches, warmup and GC

The shared engine supports four important measurement controls:

```lua
{
    count = 100,
    batch = 10,
    warmup = 25,
    collect_gc = true,
}
```

`count` is the number of statistical samples. `batch` is the number of real calls
inside each sample. Large batches are useful for sub-microsecond/microsecond work
because the timer boundary would otherwise be a significant part of the result.

`warmup` executes the function before timed samples. This matters especially under
LuaJIT and for paths that initialize caches or JIT traces on first use.

Unless disabled for a particular probe, the engine performs a full Lua garbage
collection before setup/warmup. It does not subtract later GC or scheduler effects
from the samples; those remain part of the observed distribution.

The full benchmark keeps **100 samples for every probe** so p99 has a direct
sample behind it. Its batch size changes with expected operation cost:

| Batch size | Typical probe class |
| ---: | --- |
| `1` | ms/editor/end-to-end work |
| `5` | Medium filesystem/API work |
| `100` | Low-microsecond internals |
| `1000` | Very small cached/session paths |
| `10000` | Pure colour/math primitives |

This is why `count` is comparable across the full report while the `× calls` value
changes between probes.

---

## Interpreting the four full-benchmark scenarios

The four scenarios are separate complete passes. They are useful for identifying
feature overhead without mixing states in one run.

Compare `Minimal` with `Picker` to see work introduced by picker support. Compare
`Minimal` with `ColorTrace` for diagnostic source tracing. `Picker + ColorTrace`
shows their combined behavior, including places where ColorTrace can reuse picker
trace data instead of repeating work.

Do not interpret a delta in one internal probe as the total cost of that feature.
The user-facing end-to-end rows are the best place to judge the overall effect;
the detailed probe that moved is where to investigate why.

---

## Comparing benchmark runs

For meaningful before/after measurements, keep the environment as similar as
possible: same machine, Neovim/LuaJIT build, theme root, terminal/GUI and comparable
system load.

The full report records the selected theme, theme shape, Neovim version, platform,
JIT information and logical CPU count so benchmark reports remain interpretable
later.

A useful comparison normally looks at three levels:

1. user-facing `cf.reload()` / load / compile / apply numbers;
2. the scenario delta (`Minimal`, `Picker`, `ColorTrace`, `Picker + ColorTrace`);
3. the detailed subsystem probe that explains the movement.

Avoid optimizing from `min` alone. For tiny paths also check the baseline; for
interactive paths also check p95/p99.

---

## Troubleshooting poor benchmark results

ChromaFlow's internal hot paths are intentionally kept very small, so large local
slowdowns or unusually wide timing distributions are often worth checking against
the surrounding Neovim configuration as well as ChromaFlow itself.

Common sources of benchmark noise include:

- **Heavy `ColorSchemePre` / `ColorScheme` autocommands.** These callbacks run
  synchronously during theme application. Plugin or user callbacks that do
  substantial work therefore appear directly in user-facing load/reload timings.
- **Expensive redraw consumers.** Statuslines, winbars, tablines or other UI
  components that do non-trivial work during redraw can inflate the `redraw!`
  probe and any end-to-end path that finishes with a redraw.
- **Timers, watchers and other event-loop load.** Background jobs, active timers,
  filesystem watchers or unrelated async work can widen averages and tail latency
  by introducing scheduler/context-switch noise while samples are being timed.
- **Different Neovim/LuaJIT or system state.** CPU power management, thermal load,
  terminal/GUI choice, JIT warmup and other machine-level differences can move
  especially small timings. Compare reports from as similar an environment as
  possible.

If a local report looks unexpectedly slow, repeat it from a clean Neovim started
from the repository root:

```sh
cd /path/to/cf.nvim
nvim -u NONE -i NONE --cmd 'set runtimepath^=.'
```

Then start the full Markdown benchmark inside that clean session with:

```vim
:lua dofile(vim.api.nvim_get_runtime_file("tests/full_benchmark.lua", false)[1]).start()
```

If the clean run is substantially better, re-enable your normal configuration in
parts and look first at `ColorSchemePre`/`ColorScheme`, redraw-heavy UI components,
and persistent background work. If both runs regress in the same subsystem, use
the detailed full-benchmark probes or the focused benchmark for that subsystem to
narrow the change further.

---

## ColorTrace benchmark

`colortrace_benchmark.lua` is a focused decomposition of the one-file ColorTrace
seed path. It is useful when full-benchmark diagnostics/source-trace numbers move
and you need to see which part changed.

It measures:

- filesystem source signature
- source ranges: cached
- source ranges: cold read + Lua Tree-sitter parse + collect
- one module execution with ColorTrace OFF
- one module execution with ColorTrace ON, ranges warm
- one module execution with ColorTrace ON, ranges cold
- `theme.color_trace_file` producer only
- producer + `diagnostic.flush_buffer`
- `diagnostic.flush_buffer` on already seeded records

It expects a ChromaFlow theme to already be loaded. If the current buffer is one of
the active theme's module files, that module is used; otherwise it uses the first
module file from the active theme.

Run it inside Neovim with:

```vim
:lua dofile(vim.api.nvim_get_runtime_file("tests/colortrace_benchmark.lua", false)[1]).run()
```

Custom sample/batch settings can be supplied:

```vim
:lua dofile(vim.api.nvim_get_runtime_file("tests/colortrace_benchmark.lua", false)[1]).run({ count = 100, batch = 10 })
```

The benchmark uses the normal `ModuleBenchmark` result buffer/session formatting.

---

## Float benchmark

`float_benchmark.lua` isolates the reusable `cf.fn.float` renderer from the rest of
ChromaFlow UI.

It includes same-reference no-op updates, one/multiple-span replacement, grow/
shrink cases, line flushes, bulk `set_lines`, window/config changes and hide/open
behavior. This makes it useful when picker/menu work becomes slower but the full
benchmark does not make it obvious whether the cost is in the UI logic or in the
float renderer itself.

Run it with:

```vim
:lua dofile(vim.api.nvim_get_runtime_file("tests/float_benchmark.lua", false)[1]).run()
```

A custom sample count may be passed through its options table:

```vim
:lua dofile(vim.api.nvim_get_runtime_file("tests/float_benchmark.lua", false)[1]).run({ count = 100 })
```

---

## `tests/benchmark.lua` and `:ModuleBenchmark`

`tests/benchmark.lua` is the small generic engine shared by the ChromaFlow
benchmarks. It can also benchmark arbitrary Lua module functions.

From a normal plugin checkout/install, load the local engine and register its user
command with:

```vim
:lua dofile(vim.api.nvim_get_runtime_file("tests/benchmark.lua", false)[1]).setup()
```

Then, for example:

```vim
:ModuleBenchmark 100 batch=10 cf reload()
```

This means 100 statistical samples with 10 actual `cf.reload()` calls per sample,
normalized back to time per call.

Multiple functions from the same module may be measured in one command:

```vim
:ModuleBenchmark 100 batch=100 cf.color to_cterm(0xffff0000) from_cterm(196)
```

For a collected session:

```vim
:ModuleBenchmark start
:ModuleBenchmark 100 batch=10 cf reload()
:ModuleBenchmark 1000 batch=100 some.module hot_path()
:ModuleBenchmark stop
```

`stop` opens the collected results in `ModuleBenchmark://results`.

The command evaluates function arguments as Lua expressions through `load()`. It is
therefore intended for local trusted benchmark commands, not untrusted input.

For the complete engine API (`run`, `bench`, `compare`, `baseline`, `call`,
formatting, sessions and hooks), see [`tests/benchmark.md`](../tests/benchmark.md).

---

## Which benchmark should I use?

| Question | Use |
| --- | --- |
| Did this change make ChromaFlow faster/slower overall? | `full_benchmark.lua` |
| Is Picker or ColorTrace responsible for the difference? | Full benchmark scenario comparison |
| Which compile/resolver/apply subsystem moved? | Full benchmark detailed sections |
| Why did ColorTrace/source tracing move? | `colortrace_benchmark.lua` |
| Did the reusable float renderer regress? | `float_benchmark.lua` |
| How fast is one specific Lua module function? | `tests/benchmark.lua` / `:ModuleBenchmark` |
| Is behavior correct rather than fast? | Headless regression tests |

Tests and benchmarks complement each other: a performance improvement is only useful
if the regression suite still passes, and a passing regression suite says nothing
about whether a hot path became slower.
