# ChromaFlow clean-state benchmark report

Two clean Neovim runs of the same ChromaFlow benchmark were compared. The only intentional editor-state difference was the current buffer:

- **Empty-buffer run:** no file opened before starting `full_benchmark`.
- **Code-buffer run:** `:e tests/benchmark.lua` executed immediately before starting `full_benchmark`.

Both runs benchmark the same `dark` reference theme: 32 modules, 938 compiled actions, 32 active module files, no fallback files, and no runtime modules.

## Host

| Item | Value |
| --- | --- |
| Host | `tp-bot` |
| CPU | Intel Core i5-10310U @ 1.70 GHz |
| Topology | 4 cores / 8 threads |
| Max CPU frequency | 4.4 GHz |
| Cache | L1d 128 KiB, L1i 128 KiB, L2 1 MiB, L3 6 MiB |
| Architecture | x86_64 |
| OS | Arch Linux |
| Kernel | Linux 7.2.6-arch2-1, PREEMPT_DYNAMIC |
| Neovim | 0.12.5 |
| LuaJIT | 2.1.1788856981 x64/Linux |

## Reproduction

The clean-state launch used the standalone repository path documented by ChromaFlow:

```sh
cd /path/to/cf.nvim
nvim -u NONE -i NONE --cmd 'set runtimepath^=.'
```

For the code-buffer run only:

```vim
:e tests/benchmark.lua
```

Then start the formatted Markdown benchmark report:

```vim
:lua dofile(vim.api.nvim_get_runtime_file("tests/full_benchmark.lua", false)[1]).start()
```

The benchmark engine collects 100 statistical samples per probe, performs the configured warmup first, and runs GC before each benchmark. Probe batch sizes are adapted to the operation cost; category results overlap by design and must not be added together.

## End-to-end results

The current buffer does **not** introduce a consistent end-to-end slowdown across the four feature scenarios. Some measurements move upward, others downward, which is the expected shape of normal run-to-run variation at these durations.

### `cf.reload()` average

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 12.284 ms | 12.814 ms | +4.3% |
| Picker | 15.659 ms | 18.872 ms | +20.5% |
| ColorTrace | 20.318 ms | 20.146 ms | -0.8% |
| Picker + ColorTrace | 23.078 ms | 23.057 ms | -0.1% |

### `load_theme() [diagnostic + theme.load]` average

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 11.801 ms | 12.297 ms | +4.2% |
| Picker | 20.826 ms | 23.347 ms | +12.1% |
| ColorTrace | 20.361 ms | 20.266 ms | -0.5% |
| Picker + ColorTrace | 22.993 ms | 22.916 ms | -0.3% |

### `theme.load()` average

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 11.901 ms | 12.191 ms | +2.4% |
| Picker | 22.635 ms | 23.221 ms | +2.6% |
| ColorTrace | 20.627 ms | 19.835 ms | -3.8% |
| Picker + ColorTrace | 23.242 ms | 23.029 ms | -0.9% |

### `theme.compile()` average

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 6.417 ms | 6.736 ms | +5.0% |
| Picker | 14.472 ms | 12.587 ms | -13.0% |
| ColorTrace | 11.728 ms | 10.606 ms | -9.6% |
| Picker + ColorTrace | 13.446 ms | 13.258 ms | -1.4% |

### `theme.apply(precompiled)` average

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 4.781 ms | 4.796 ms | +0.3% |
| Picker | 7.670 ms | 7.346 ms | -4.2% |
| ColorTrace | 8.297 ms | 7.318 ms | -11.8% |
| Picker + ColorTrace | 7.228 ms | 7.962 ms | +10.2% |

### `cf.reload()` p99

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 20.259 ms | 22.055 ms | +8.9% |
| Picker | 25.213 ms | 33.311 ms | +32.1% |
| ColorTrace | 32.836 ms | 34.338 ms | +4.6% |
| Picker + ColorTrace | 36.642 ms | 36.287 ms | -1.0% |

The largest average difference in the public reload path occurs in the Picker-only run (+20.5%), but the neighboring decomposition does not show a matching buffer-wide increase: `theme.compile()` is actually lower in that same run while other scenarios remain almost unchanged. That makes it a poor candidate for a buffer-cost conclusion by itself.

## Redraw and editor consumers

### `redraw! only` average

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 166.092 µs | 174.322 µs | +5.0% |
| Picker | 234.633 µs | 210.063 µs | -10.5% |
| ColorTrace | 236.801 µs | 244.698 µs | +3.3% |
| Picker + ColorTrace | 249.750 µs | 202.252 µs | -19.0% |

### `treesitter + lsp + redraw!` average

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 163.948 µs | 169.102 µs | +3.1% |
| Picker | 231.549 µs | 216.517 µs | -6.5% |
| ColorTrace | 233.441 µs | 221.509 µs | -5.1% |
| Picker + ColorTrace | 248.328 µs | 216.104 µs | -13.0% |

### `refresh_consumers() no redraw` average

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 0.566 µs | 0.436 µs | -23.0% |
| Picker | 0.411 µs | 0.602 µs | +46.5% |
| ColorTrace | 0.585 µs | 0.618 µs | +5.6% |
| Picker + ColorTrace | 0.582 µs | 0.610 µs | +4.8% |

The redraw-facing probes stay in the same general range and do not move in one direction across all scenarios. Opening the Lua file therefore does not expose a stable redraw penalty in this clean setup.

## LineBlend is the clear buffer-sensitive case

`lineblend.reload() [current state]` is the one result that changes strongly and consistently when a real code buffer is present:

| Scenario | Empty buffer | `tests/benchmark.lua` open | Change |
| --- | ---: | ---: | ---: |
| Minimal | 13.707 µs | 64.585 µs | +371.2% |
| Picker | 19.285 µs | 97.003 µs | +403.0% |
| ColorTrace | 19.845 µs | 95.799 µs | +382.7% |
| Picker + ColorTrace | 17.343 µs | 97.117 µs | +460.0% |

That is expected behavior rather than benchmark noise: an empty buffer gives LineBlend very little current-buffer state to rebuild, while an actual source buffer creates real line/highlight work. Even then, the measured cost remains below 0.1 ms on average in all four scenarios.

`lineblend.refresh() [current state]` remains tiny in both runs, so the visible difference is specifically the explicit hard-reload/rebuild path rather than the normal cached refresh path.

## Hot-path interpretation

The resolver, color primitives, pipeline operations, action application, diagnostics helpers, watcher helpers, and float renderer remain microsecond/sub-microsecond work in both reports. Individual tiny probes shift between runs because many of them sit close to timer/JIT/event-loop noise; those differences should not be interpreted as effects of merely having a file open unless they are large, directional, and repeat across scenarios.

The clean-state comparison therefore supports three practical conclusions:

1. **Normal ChromaFlow load/reload cost is largely insensitive to whether the current buffer is empty or contains `tests/benchmark.lua`.**
2. **A real buffer predictably increases LineBlend hard-reload work**, because that path rebuilds buffer-dependent state.
3. **Small low-level deltas are measurement noise unless they reproduce consistently.** The full report already exposes p50/p90/p95/p99 so regressions should be judged from shape and repetition, not a single average.

## Reference files

- [`full_benchmark_clear_buffer-20260930-1057.md`](full_benchmark_clear_buffer-20260930-1057.md) — clean run with no file opened.
- [`full_benchmark_not_empty_buffer-20260930-1101.md`](full_benchmark_not_empty_buffer-20260930-1101.md) — clean run with `tests/benchmark.lua` opened before the benchmark.

For performance issues reported by users, these clean-state runs are the baseline to compare against before attributing slow `ColorScheme` callbacks, redraw consumers, timers, watchers, or other personal Neovim configuration to ChromaFlow.
