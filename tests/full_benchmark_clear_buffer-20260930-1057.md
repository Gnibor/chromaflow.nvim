# ChromaFlow Full Benchmark

This report measures the same theme in four separate ChromaFlow setup scenarios, then compares every probe by semantic category. Each scenario is a complete independent benchmark pass; results from different categories overlap by design and **must not be added together**.

## Benchmark setup

- Theme root: `examples/themes`
- Default / active theme: `dark` / `dark`
- Theme shape: **32 modules**, **938 compiled actions**, **32 active module files**, **0 fallback files**, **0 runtime modules**.
- Runtime: Neovim 0.12.5, Linux/x64, JIT=LuaJIT 2.1.1788856981 x64/Linux, logical CPUs=8.
- Measurement engine: `tests/benchmark.lua`; GC is collected before each benchmark and every probe performs its listed warmup before timed samples.
- Every probe keeps 100 statistical samples. Batch size is adapted to the operation cost: 1 for ms/editor work, 5 for medium work, 100/1000 for µs paths and 10,000 only for pure colour math.
- `start()` temporarily replaces the caller's active ChromaFlow setup with each scenario below and restores the original setup afterwards.

## Setup scenarios

| Scenario | Setup difference | Picker | ColorTrace |
| --- | --- | ---: | ---: |
| Minimal | `theme_path` | false | false |
| Picker | `theme_path + picker=true` | true | false |
| ColorTrace | `theme_path + diagnostic.color_trace=true` | false | true |
| Picker + ColorTrace | `theme_path + picker=true + diagnostic.color_trace=true` | true | true |

The scenario order is intentional: minimal first, then picker only, ColorTrace only, then picker+ColorTrace. This makes the extra cost of each feature and their interaction visible without mixing setup states.

## User-facing comparison

These are the first numbers to inspect. They represent complete operations a user can actually feel.

### Average

| Operation | Minimal | Picker | ColorTrace | Picker + ColorTrace | Meaning |
| --- | ---: | ---: | ---: | ---: | --- |
| `cf.reload()` | 12.814 ms | 18.872 ms | 20.146 ms | 23.057 ms | Public reload path |
| `load_theme() [diagnostic + theme.load]` | 12.297 ms | 23.347 ms | 20.266 ms | 22.916 ms | Theme load plus diagnostic cycle |
| `theme.load()` | 12.191 ms | 23.221 ms | 19.835 ms | 23.029 ms | Compile + apply |
| `theme.compile()` | 6.736 ms | 12.587 ms | 10.606 ms | 13.258 ms | Compile only |
| `theme.apply(precompiled)` | 4.796 ms | 7.346 ms | 7.318 ms | 7.962 ms | Apply an already compiled theme |

### p99

| Operation | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| `cf.reload()` | 22.055 ms | 33.311 ms | 34.338 ms | 36.287 ms |
| `load_theme() [diagnostic + theme.load]` | 21.116 ms | 38.481 ms | 33.959 ms | 37.468 ms |
| `theme.load()` | 21.150 ms | 37.429 ms | 33.027 ms | 38.504 ms |
| `theme.compile()` | 15.469 ms | 25.539 ms | 22.678 ms | 27.262 ms |
| `theme.apply(precompiled)` | 11.580 ms | 16.119 ms | 16.368 ms | 18.922 ms |

### Average feature cost vs minimal

Positive values mean the feature scenario took longer than the minimal setup; negative values mean the measured average happened to be lower. Treat small deltas near normal run-to-run jitter as noise rather than a speedup.

| Operation | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: |
| `cf.reload()` | +6.058 ms (+47.3%) | +7.332 ms (+57.2%) | +10.244 ms (+79.9%) |
| `load_theme() [diagnostic + theme.load]` | +11.050 ms (+89.9%) | +7.969 ms (+64.8%) | +10.619 ms (+86.4%) |
| `theme.load()` | +11.030 ms (+90.5%) | +7.643 ms (+62.7%) | +10.838 ms (+88.9%) |
| `theme.compile()` | +5.852 ms (+86.9%) | +3.870 ms (+57.5%) | +6.522 ms (+96.8%) |
| `theme.apply(precompiled)` | +2.550 ms (+53.2%) | +2.522 ms (+52.6%) | +3.166 ms (+66.0%) |

## Detailed decomposition

Every probe below is shown once. Metrics are vertical and the four setup scenarios are side by side, so differences can be compared directly without scanning one long inline number string.

## Measurement baseline

Timer/closure floor for the same benchmark engine. Use it only to judge very small measurements; it is not subtracted from results.

### empty Lua call

- Measures: Measures the benchmark loop with an empty Lua closure.
- Represents: Reference floor for sub-microsecond probes; it is not subtracted from any result.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.000 µs | 0.000 µs | 0.000 µs | 0.000 µs |
| Avg | 0.000 µs | 0.000 µs | 0.000 µs | 0.000 µs |
| p50 | 0.000 µs | 0.000 µs | 0.000 µs | 0.000 µs |
| p90 | 0.000 µs | 0.000 µs | 0.000 µs | 0.000 µs |
| p95 | 0.000 µs | 0.000 µs | 0.000 µs | 0.000 µs |
| p99 | 0.001 µs | 0.001 µs | 0.002 µs | 0.002 µs |
| Max | 0.002 µs | 0.002 µs | 0.002 µs | 0.002 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | timer-floor dominated |

## User-facing end-to-end

The operations a user actually feels: reload, complete load, compile and apply. These are the first numbers to compare between machines or releases.

### cf.reload()

- Measures: Calls the public cf.reload() path on the selected theme.
- Represents: Closest single number to the cost a user pays for a normal ChromaFlow reload: diagnostic cycle, theme load/apply, watcher scope update when active, and cached LineBlend refresh.
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 8.961 ms | 11.424 ms | 14.769 ms | 17.491 ms |
| Avg | 12.814 ms | 18.872 ms | 20.146 ms | 23.057 ms |
| p50 | 10.963 ms | 17.166 ms | 17.442 ms | 19.531 ms |
| p90 | 20.445 ms | 28.406 ms | 31.839 ms | 34.884 ms |
| p95 | 20.548 ms | 31.123 ms | 32.899 ms | 35.723 ms |
| p99 | 22.055 ms | 33.311 ms | 34.338 ms | 36.287 ms |
| Max | 22.094 ms | 33.712 ms | 34.365 ms | 36.711 ms |
| Tail | 1.72× avg (tight) | 1.77× avg (visible tails) | 1.70× avg (tight) | 1.57× avg (tight) |

### load_theme() [diagnostic + theme.load]

- Measures: Calls the internal reload helper around theme.load(), including diagnostic clear/flush.
- Represents: Shows ChromaFlow's theme work before watcher/LineBlend post-work from cf.reload().
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 8.886 ms | 17.160 ms | 15.870 ms | 17.555 ms |
| Avg | 12.297 ms | 23.347 ms | 20.266 ms | 22.916 ms |
| p50 | 10.340 ms | 19.763 ms | 17.315 ms | 19.231 ms |
| p90 | 20.289 ms | 36.324 ms | 32.116 ms | 35.254 ms |
| p95 | 20.579 ms | 36.954 ms | 33.269 ms | 36.510 ms |
| p99 | 21.116 ms | 38.481 ms | 33.959 ms | 37.468 ms |
| Max | 22.578 ms | 39.871 ms | 34.239 ms | 37.885 ms |
| Tail | 1.72× avg (tight) | 1.65× avg (tight) | 1.68× avg (tight) | 1.64× avg (tight) |

### theme.load()

- Measures: Compiles the theme and immediately applies the compiled result.
- Represents: Core load cost without the public reload wrapper.
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 8.631 ms | 17.490 ms | 15.061 ms | 16.765 ms |
| Avg | 12.191 ms | 23.221 ms | 19.835 ms | 23.029 ms |
| p50 | 10.204 ms | 19.584 ms | 17.255 ms | 19.608 ms |
| p90 | 20.064 ms | 35.804 ms | 30.261 ms | 35.584 ms |
| p95 | 20.565 ms | 36.826 ms | 31.322 ms | 36.631 ms |
| p99 | 21.150 ms | 37.429 ms | 33.027 ms | 38.504 ms |
| Max | 21.944 ms | 38.319 ms | 34.758 ms | 38.845 ms |
| Tail | 1.73× avg (tight) | 1.61× avg (tight) | 1.67× avg (tight) | 1.67× avg (tight) |

### theme.compile()

- Measures: Discovers theme files, executes the DSL and produces the compiled theme object.
- Represents: Front half of a reload; no Neovim highlight application is included.
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 4.518 ms | 8.471 ms | 7.221 ms | 8.928 ms |
| Avg | 6.736 ms | 12.587 ms | 10.606 ms | 13.258 ms |
| p50 | 5.139 ms | 10.015 ms | 8.359 ms | 10.185 ms |
| p90 | 13.413 ms | 22.618 ms | 20.620 ms | 26.151 ms |
| p95 | 13.966 ms | 24.966 ms | 21.711 ms | 26.978 ms |
| p99 | 15.469 ms | 25.539 ms | 22.678 ms | 27.262 ms |
| Max | 15.682 ms | 26.055 ms | 23.455 ms | 30.226 ms |
| Tail | 2.30× avg (visible tails) | 2.03× avg (visible tails) | 2.14× avg (visible tails) | 2.06× avg (visible tails) |

### theme.apply(precompiled)

- Measures: Applies an already compiled theme object.
- Represents: Back half of a reload: highlight reset/apply, runtime bookkeeping, events and configured consumers.
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 3.645 ms | 5.328 ms | 5.270 ms | 5.948 ms |
| Avg | 4.796 ms | 7.346 ms | 7.318 ms | 7.962 ms |
| p50 | 4.300 ms | 6.861 ms | 6.635 ms | 7.287 ms |
| p90 | 5.628 ms | 8.542 ms | 9.479 ms | 8.785 ms |
| p95 | 8.328 ms | 11.103 ms | 12.377 ms | 13.920 ms |
| p99 | 11.580 ms | 16.119 ms | 16.368 ms | 18.922 ms |
| Max | 12.060 ms | 18.350 ms | 17.776 ms | 20.168 ms |
| Tail | 2.41× avg (visible tails) | 2.19× avg (visible tails) | 2.24× avg (visible tails) | 2.38× avg (visible tails) |

## Theme discovery and source loading

Filesystem discovery, reserved files, Lua chunk loading/execution and the initial compiler setup. This decomposes the front half of theme.compile().

### theme.selection()

- Measures: Reads and resolves the .cf-theme default/active selection.
- Represents: Theme-selection filesystem overhead.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 7.616 µs | 13.398 µs | 12.828 µs | 13.448 µs |
| Avg | 9.819 µs | 15.015 µs | 14.157 µs | 14.460 µs |
| p50 | 8.055 µs | 13.928 µs | 13.415 µs | 13.924 µs |
| p90 | 10.636 µs | 16.833 µs | 14.949 µs | 15.679 µs |
| p95 | 18.643 µs | 21.878 µs | 16.683 µs | 16.148 µs |
| p99 | 39.199 µs | 27.339 µs | 29.853 µs | 23.828 µs |
| Max | 39.617 µs | 33.570 µs | 37.388 µs | 26.218 µs |
| Tail | 3.99× avg (wide tails) | 1.82× avg (visible tails) | 2.11× avg (visible tails) | 1.65× avg (tight) |

### theme.available()

- Measures: Scans the theme root for valid selectable themes.
- Represents: Cost of populating the theme list/menu, not a per-highlight hot path.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 255.073 µs | 396.659 µs | 402.284 µs | 394.661 µs |
| Avg | 355.800 µs | 551.160 µs | 550.208 µs | 526.718 µs |
| p50 | 268.825 µs | 434.809 µs | 434.331 µs | 419.188 µs |
| p90 | 507.770 µs | 593.613 µs | 620.056 µs | 576.406 µs |
| p95 | 879.284 µs | 1.424 ms | 1.024 ms | 1.075 ms |
| p99 | 1.041 ms | 1.968 ms | 2.005 ms | 2.173 ms |
| Max | 1.066 ms | 2.219 ms | 2.105 ms | 2.202 ms |
| Tail | 2.93× avg (visible tails) | 3.57× avg (wide tails) | 3.64× avg (wide tails) | 4.13× avg (wide tails) |

### theme_names()

- Measures: Enumerates candidate theme directory names used by the compiler.
- Represents: Low-level directory-name discovery cost.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 3.480 µs | 5.570 µs | 5.560 µs | 5.620 µs |
| Avg | 3.829 µs | 5.824 µs | 6.973 µs | 5.914 µs |
| p50 | 3.545 µs | 5.662 µs | 5.802 µs | 5.746 µs |
| p90 | 3.619 µs | 5.811 µs | 9.174 µs | 5.865 µs |
| p95 | 4.450 µs | 6.645 µs | 11.947 µs | 6.667 µs |
| p99 | 11.298 µs | 9.524 µs | 22.690 µs | 9.674 µs |
| Max | 15.494 µs | 10.733 µs | 31.824 µs | 10.700 µs |
| Tail | 2.95× avg (visible tails) | 1.64× avg (tight) | 3.25× avg (wide tails) | 1.64× avg (tight) |

### list_cf(active) [32 files]

- Measures: Lists .cf modules in the active theme directory.
- Represents: Filesystem cost of discovering active theme modules.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 24.956 µs | 39.121 µs | 38.776 µs | 40.038 µs |
| Avg | 25.860 µs | 40.822 µs | 41.259 µs | 42.424 µs |
| p50 | 25.640 µs | 40.173 µs | 40.565 µs | 41.582 µs |
| p90 | 26.612 µs | 42.277 µs | 43.018 µs | 44.688 µs |
| p95 | 26.987 µs | 45.159 µs | 46.118 µs | 46.741 µs |
| p99 | 28.771 µs | 48.433 µs | 47.286 µs | 53.384 µs |
| Max | 33.342 µs | 56.443 µs | 52.881 µs | 56.757 µs |
| Tail | 1.11× avg (very tight) | 1.19× avg (very tight) | 1.15× avg (very tight) | 1.26× avg (tight) |
| Avg / file | 0.808 µs | 1.276 µs | 1.289 µs | 1.326 µs |

### valid_theme_dir(default)

- Measures: Validates a candidate theme directory.
- Represents: Selection/fallback validation cost.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 26.928 µs | 40.252 µs | 41.455 µs | 42.487 µs |
| Avg | 27.937 µs | 43.265 µs | 44.304 µs | 44.944 µs |
| p50 | 27.691 µs | 41.810 µs | 43.849 µs | 44.291 µs |
| p90 | 28.743 µs | 46.477 µs | 45.893 µs | 47.521 µs |
| p95 | 29.384 µs | 47.046 µs | 47.287 µs | 48.663 µs |
| p99 | 31.951 µs | 50.956 µs | 51.758 µs | 52.609 µs |
| Max | 33.653 µs | 51.236 µs | 58.619 µs | 54.839 µs |
| Tail | 1.14× avg (very tight) | 1.18× avg (very tight) | 1.17× avg (very tight) | 1.17× avg (very tight) |

### valid_theme_dir(active)

- Measures: Validates a candidate theme directory.
- Represents: Selection/fallback validation cost.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 26.595 µs | 40.526 µs | 40.489 µs | 40.894 µs |
| Avg | 28.017 µs | 42.551 µs | 41.953 µs | 44.369 µs |
| p50 | 27.860 µs | 42.144 µs | 41.448 µs | 42.342 µs |
| p90 | 28.664 µs | 44.011 µs | 43.054 µs | 46.709 µs |
| p95 | 28.784 µs | 45.617 µs | 46.326 µs | 48.310 µs |
| p99 | 30.367 µs | 47.899 µs | 49.240 µs | 54.653 µs |
| Max | 34.019 µs | 49.227 µs | 50.590 µs | 148.482 µs |
| Tail | 1.08× avg (very tight) | 1.13× avg (very tight) | 1.17× avg (very tight) | 1.23× avg (very tight) |

### resolve_reserved(color+config)

- Measures: Resolves color.cf and config.cf across active/default fallback rules.
- Represents: Reserved-file lookup cost for one compile.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 7.857 µs | 11.757 µs | 11.722 µs | 11.888 µs |
| Avg | 8.563 µs | 12.494 µs | 12.994 µs | 12.690 µs |
| p50 | 8.175 µs | 12.289 µs | 12.041 µs | 12.296 µs |
| p90 | 8.878 µs | 12.976 µs | 14.148 µs | 13.484 µs |
| p95 | 10.154 µs | 13.610 µs | 18.473 µs | 14.625 µs |
| p99 | 15.608 µs | 17.063 µs | 27.392 µs | 18.615 µs |
| Max | 24.162 µs | 17.118 µs | 35.883 µs | 20.613 µs |
| Tail | 1.82× avg (visible tails) | 1.37× avg (tight) | 2.11× avg (visible tails) | 1.47× avg (tight) |

### module_files(active+fallback) [32 files]

- Measures: Builds active/default module file lists with fallback scope metadata.
- Represents: Module-discovery cost before source execution.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 48.664 µs | 72.051 µs | 72.745 µs | 73.472 µs |
| Avg | 62.728 µs | 75.236 µs | 80.878 µs | 76.711 µs |
| p50 | 50.531 µs | 74.690 µs | 75.714 µs | 76.019 µs |
| p90 | 64.845 µs | 77.361 µs | 95.923 µs | 79.626 µs |
| p95 | 106.060 µs | 80.397 µs | 103.050 µs | 81.705 µs |
| p99 | 281.355 µs | 82.604 µs | 114.722 µs | 84.423 µs |
| Max | 308.271 µs | 83.173 µs | 120.011 µs | 86.335 µs |
| Tail | 4.49× avg (wide tails) | 1.10× avg (very tight) | 1.42× avg (tight) | 1.10× avg (very tight) |
| Avg / file | 1.960 µs | 2.351 µs | 2.527 µs | 2.397 µs |

### loadfile(color+config)

- Measures: Compiles reserved color/config Lua chunks with loadfile(), without executing them.
- Represents: Lua parser/loader cost for reserved files.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 14.767 µs | 20.835 µs | 22.506 µs | 22.380 µs |
| Avg | 15.233 µs | 21.795 µs | 23.856 µs | 23.499 µs |
| p50 | 15.127 µs | 21.500 µs | 23.343 µs | 23.037 µs |
| p90 | 15.429 µs | 22.616 µs | 24.729 µs | 24.521 µs |
| p95 | 15.948 µs | 23.196 µs | 25.811 µs | 25.299 µs |
| p99 | 16.076 µs | 25.709 µs | 32.203 µs | 29.976 µs |
| Max | 21.939 µs | 27.732 µs | 36.879 µs | 30.861 µs |
| Tail | 1.06× avg (very tight) | 1.18× avg (very tight) | 1.35× avg (tight) | 1.28× avg (tight) |

### execute(color+config)

- Measures: Loads and executes color.cf/config.cf through ChromaFlow's source wrapper.
- Represents: Reserved source execution plus ChromaFlow source bookkeeping.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 20.563 µs | 40.083 µs | 42.947 µs | 49.148 µs |
| Avg | 21.635 µs | 42.100 µs | 49.882 µs | 52.936 µs |
| p50 | 21.371 µs | 41.713 µs | 45.537 µs | 52.261 µs |
| p90 | 22.182 µs | 44.152 µs | 59.759 µs | 55.580 µs |
| p95 | 22.883 µs | 45.715 µs | 68.924 µs | 57.668 µs |
| p99 | 26.753 µs | 48.278 µs | 99.259 µs | 61.740 µs |
| Max | 28.603 µs | 48.561 µs | 103.174 µs | 62.463 µs |
| Tail | 1.24× avg (very tight) | 1.15× avg (very tight) | 1.99× avg (visible tails) | 1.17× avg (very tight) |

### loadfile(all modules) [32 files]

- Measures: Runs loadfile() for every active/fallback theme module.
- Represents: Lua parse/load cost for the complete module set, excluding module execution.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.032 ms | 1.602 ms | 1.603 ms | 1.550 ms |
| Avg | 1.370 ms | 1.967 ms | 2.028 ms | 1.921 ms |
| p50 | 1.171 ms | 1.702 ms | 1.718 ms | 1.642 ms |
| p90 | 1.516 ms | 2.153 ms | 2.261 ms | 2.127 ms |
| p95 | 2.763 ms | 2.431 ms | 2.354 ms | 2.272 ms |
| p99 | 4.352 ms | 5.879 ms | 6.316 ms | 6.090 ms |
| Max | 4.384 ms | 7.861 ms | 6.340 ms | 7.376 ms |
| Tail | 3.18× avg (wide tails) | 2.99× avg (visible tails) | 3.11× avg (wide tails) | 3.17× avg (wide tails) |
| Avg / file | 42.817 µs | 61.471 µs | 63.369 µs | 60.028 µs |

### execute preloaded module chunks [32 files]

- Measures: Executes already-loaded real module chunks through active/fallback compiler phases.
- Represents: DSL execution cost with filesystem parsing removed.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 2.906 ms | 5.768 ms | 4.311 ms | 6.119 ms |
| Avg | 4.626 ms | 9.096 ms | 6.854 ms | 9.759 ms |
| p50 | 3.477 ms | 6.630 ms | 5.177 ms | 7.509 ms |
| p90 | 8.428 ms | 17.937 ms | 12.825 ms | 18.419 ms |
| p95 | 8.922 ms | 19.046 ms | 13.102 ms | 18.808 ms |
| p99 | 9.270 ms | 19.601 ms | 13.721 ms | 20.074 ms |
| Max | 9.633 ms | 19.641 ms | 14.919 ms | 21.126 ms |
| Tail | 2.00× avg (visible tails) | 2.16× avg (visible tails) | 2.00× avg (visible tails) | 2.06× avg (visible tails) |
| Avg / file | 144.552 µs | 284.236 µs | 214.194 µs | 304.984 µs |

### hl._begin(colors, config)

- Measures: Initializes the highlight compiler with the already loaded colours and theme config.
- Represents: Fixed compiler setup cost per compile.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.320 µs | 0.978 µs | 0.390 µs | 0.412 µs |
| Avg | 0.515 µs | 1.265 µs | 0.666 µs | 0.668 µs |
| p50 | 0.392 µs | 1.047 µs | 0.447 µs | 0.464 µs |
| p90 | 0.476 µs | 1.138 µs | 0.550 µs | 0.548 µs |
| p95 | 0.537 µs | 1.719 µs | 1.883 µs | 1.703 µs |
| p99 | 3.520 µs | 5.337 µs | 4.841 µs | 5.244 µs |
| Max | 5.309 µs | 7.852 µs | 7.165 µs | 6.293 µs |
| Tail | 6.83× avg (wide tails) | 4.22× avg (wide tails) | 7.27× avg (wide tails) | 7.85× avg (wide tails) |

## DSL compiler

Replays captured real declarations from the selected theme through the actual internal compiler functions. Aggregate probes report a per-item cost where possible.

### setup() replay all [32 calls]

- Measures: Replays every captured language/plugin/ui setup call from the real theme.
- Represents: Aggregate public DSL setup/compiler cost for this exact theme.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 2.290 ms | 4.480 ms | 3.286 ms | 4.586 ms |
| Avg | 3.357 ms | 6.860 ms | 4.772 ms | 6.651 ms |
| p50 | 2.563 ms | 5.585 ms | 3.681 ms | 5.073 ms |
| p90 | 7.298 ms | 13.522 ms | 9.409 ms | 12.308 ms |
| p95 | 7.657 ms | 15.469 ms | 9.934 ms | 15.901 ms |
| p99 | 8.174 ms | 16.653 ms | 10.450 ms | 16.816 ms |
| Max | 9.105 ms | 16.712 ms | 10.515 ms | 17.470 ms |
| Tail | 2.43× avg (visible tails) | 2.43× avg (visible tails) | 2.19× avg (visible tails) | 2.53× avg (visible tails) |
| Avg / call | 104.918 µs | 214.365 µs | 149.132 µs | 207.854 µs |

### compile_language_module all [15 calls]

- Measures: Calls the internal language-module compiler for every captured language declaration.
- Represents: Language-specific DSL compile contribution.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.181 ms | 2.388 ms | 1.919 ms | 2.364 ms |
| Avg | 1.671 ms | 3.469 ms | 2.615 ms | 3.522 ms |
| p50 | 1.268 ms | 2.656 ms | 2.065 ms | 2.621 ms |
| p90 | 2.254 ms | 4.020 ms | 2.941 ms | 4.178 ms |
| p95 | 3.931 ms | 9.209 ms | 5.701 ms | 9.908 ms |
| p99 | 5.298 ms | 12.836 ms | 9.265 ms | 13.093 ms |
| Max | 5.640 ms | 13.795 ms | 9.335 ms | 13.460 ms |
| Tail | 3.17× avg (wide tails) | 3.70× avg (wide tails) | 3.54× avg (wide tails) | 3.72× avg (wide tails) |
| Avg / call | 111.375 µs | 231.270 µs | 174.339 µs | 234.776 µs |

### compile_resolved_module all [17 calls]

- Measures: Calls the plugin/ui resolved-module compiler for every captured declaration.
- Represents: Plugin/UI DSL compile contribution.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 741.006 µs | 1.410 ms | 1.110 ms | 1.285 ms |
| Avg | 1.189 ms | 2.191 ms | 1.712 ms | 2.022 ms |
| p50 | 821.067 µs | 1.556 ms | 1.218 ms | 1.455 ms |
| p90 | 1.413 ms | 2.295 ms | 2.082 ms | 2.137 ms |
| p95 | 4.024 ms | 5.923 ms | 4.794 ms | 5.767 ms |
| p99 | 5.417 ms | 9.756 ms | 7.802 ms | 9.174 ms |
| Max | 5.639 ms | 10.436 ms | 8.854 ms | 9.970 ms |
| Tail | 4.55× avg (wide tails) | 4.45× avg (wide tails) | 4.56× avg (wide tails) | 4.54× avg (wide tails) |
| Avg / call | 69.960 µs | 128.885 µs | 100.695 µs | 118.926 µs |

### module_declarations all [32 calls]

- Measures: Extracts declaration tables from every module spec.
- Represents: Cost of turning user DSL tables into compiler declaration streams.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 18.397 µs | 27.194 µs | 25.184 µs | 25.419 µs |
| Avg | 19.364 µs | 28.571 µs | 26.646 µs | 26.654 µs |
| p50 | 19.054 µs | 27.901 µs | 26.142 µs | 26.291 µs |
| p90 | 20.292 µs | 29.937 µs | 27.503 µs | 27.522 µs |
| p95 | 20.795 µs | 33.269 µs | 28.074 µs | 27.809 µs |
| p99 | 24.025 µs | 34.764 µs | 34.787 µs | 32.619 µs |
| Max | 24.317 µs | 35.673 µs | 38.797 µs | 33.060 µs |
| Tail | 1.24× avg (very tight) | 1.22× avg (very tight) | 1.31× avg (tight) | 1.22× avg (very tight) |
| Avg / call | 0.605 µs | 0.893 µs | 0.833 µs | 0.833 µs |

### compile_module_mods all [32 calls]

- Measures: Replays per-module modifier compilation.
- Represents: Modifier declaration overhead across the selected theme.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 7.077 µs | 16.356 µs | 14.213 µs | 13.918 µs |
| Avg | 7.751 µs | 17.264 µs | 14.962 µs | 14.800 µs |
| p50 | 7.550 µs | 16.854 µs | 14.663 µs | 14.485 µs |
| p90 | 8.189 µs | 17.750 µs | 15.491 µs | 15.820 µs |
| p95 | 8.896 µs | 18.739 µs | 16.535 µs | 16.436 µs |
| p99 | 10.749 µs | 23.822 µs | 19.295 µs | 19.425 µs |
| Max | 10.869 µs | 25.626 µs | 21.814 µs | 21.245 µs |
| Tail | 1.39× avg (tight) | 1.38× avg (tight) | 1.29× avg (tight) | 1.31× avg (tight) |
| Avg / call | 0.242 µs | 0.539 µs | 0.468 µs | 0.462 µs |

### compile_resolved_group all [520 calls]

- Measures: Replays every captured resolved highlight group compiler call.
- Represents: One of the main inner DSL compilation loops; per-item cost is useful here.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.775 ms | 3.435 ms | 2.882 ms | 3.489 ms |
| Avg | 2.735 ms | 5.352 ms | 4.153 ms | 5.260 ms |
| p50 | 2.022 ms | 4.073 ms | 3.209 ms | 3.964 ms |
| p90 | 6.043 ms | 8.015 ms | 5.873 ms | 9.931 ms |
| p95 | 7.322 ms | 15.429 ms | 11.060 ms | 13.237 ms |
| p99 | 7.509 ms | 15.900 ms | 11.600 ms | 15.761 ms |
| Max | 8.277 ms | 16.060 ms | 12.231 ms | 16.783 ms |
| Tail | 2.75× avg (visible tails) | 2.97× avg (visible tails) | 2.79× avg (visible tails) | 3.00× avg (visible tails) |
| Avg / call | 5.259 µs | 10.292 µs | 7.987 µs | 10.116 µs |

### build_style all [702 calls]

- Measures: Builds every captured style object from the real theme.
- Represents: Style normalization/pipeline/cache lookup contribution during DSL compilation.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 723.631 µs | 1.766 ms | 1.268 ms | 1.697 ms |
| Avg | 1.038 ms | 2.665 ms | 1.670 ms | 2.546 ms |
| p50 | 777.398 µs | 2.049 ms | 1.385 ms | 1.917 ms |
| p90 | 1.291 ms | 3.841 ms | 1.913 ms | 3.734 ms |
| p95 | 2.292 ms | 5.823 ms | 3.166 ms | 5.677 ms |
| p99 | 4.415 ms | 9.936 ms | 5.661 ms | 9.811 ms |
| Max | 4.559 ms | 9.990 ms | 5.911 ms | 9.875 ms |
| Tail | 4.25× avg (wide tails) | 3.73× avg (wide tails) | 3.39× avg (wide tails) | 3.85× avg (wide tails) |
| Avg / call | 1.479 µs | 3.796 µs | 2.379 µs | 3.626 µs |

### intern_style all [702 calls]

- Measures: Interns every captured normalized style into the session style cache.
- Represents: Style deduplication/cache contribution.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 404.014 µs | 848.680 µs | 860.233 µs | 842.774 µs |
| Avg | 540.829 µs | 1.001 ms | 1.091 ms | 1.016 ms |
| p50 | 427.741 µs | 873.549 µs | 903.226 µs | 891.448 µs |
| p90 | 612.014 µs | 1.081 ms | 1.203 ms | 1.077 ms |
| p95 | 1.275 ms | 1.439 ms | 2.462 ms | 1.469 ms |
| p99 | 2.007 ms | 3.104 ms | 3.243 ms | 3.052 ms |
| Max | 2.125 ms | 3.291 ms | 3.740 ms | 3.239 ms |
| Tail | 3.71× avg (wide tails) | 3.10× avg (wide tails) | 2.97× avg (visible tails) | 3.00× avg (wide tails) |
| Avg / call | 0.770 µs | 1.425 µs | 1.555 µs | 1.447 µs |

### bind_action_owner all [32 modules]

- Measures: Binds compiled actions to their language/plugin/ui owners.
- Represents: Runtime/picker ownership metadata cost per compiled module.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 17.080 µs | 26.451 µs | 23.021 µs | 27.796 µs |
| Avg | 17.412 µs | 27.262 µs | 23.599 µs | 28.532 µs |
| p50 | 17.191 µs | 26.779 µs | 23.160 µs | 28.101 µs |
| p90 | 17.833 µs | 27.853 µs | 23.921 µs | 29.026 µs |
| p95 | 18.126 µs | 31.241 µs | 27.352 µs | 30.365 µs |
| p99 | 21.484 µs | 32.395 µs | 29.398 µs | 33.210 µs |
| Max | 21.947 µs | 36.514 µs | 29.442 µs | 35.739 µs |
| Tail | 1.23× avg (very tight) | 1.19× avg (very tight) | 1.25× avg (very tight) | 1.16× avg (very tight) |
| Avg / module | 0.544 µs | 0.852 µs | 0.737 µs | 0.892 µs |

## Highlight resolver

Hot cached resolver shapes plus one deliberately cold cache-rebuild path. The variants show the cost of type, modifier, TypeMod, filetype, literal and target filtering.

### cold type after clear

- Measures: Clears resolver caches and resolves a type on every measured call.
- Represents: Deliberately cold resolver rebuild cost; compare with the hot resolver variants below.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 3.251 µs | 5.069 µs | 5.069 µs | 5.040 µs |
| Avg | 3.632 µs | 5.195 µs | 5.213 µs | 5.335 µs |
| p50 | 3.620 µs | 5.142 µs | 5.146 µs | 5.244 µs |
| p90 | 3.809 µs | 5.277 µs | 5.297 µs | 5.659 µs |
| p95 | 3.912 µs | 5.326 µs | 5.480 µs | 5.733 µs |
| p99 | 4.386 µs | 5.473 µs | 5.843 µs | 5.963 µs |
| Max | 4.399 µs | 8.048 µs | 7.848 µs | 7.355 µs |
| Tail | 1.21× avg (very tight) | 1.05× avg (very tight) | 1.12× avg (very tight) | 1.12× avg (very tight) |

### type only

- Measures: Resolves a normal semantic type using a cached style object.
- Represents: Baseline hot type resolver path.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.809 µs | 1.234 µs | 1.191 µs | 1.278 µs |
| Avg | 1.069 µs | 1.506 µs | 1.473 µs | 1.548 µs |
| p50 | 0.954 µs | 1.300 µs | 1.248 µs | 1.334 µs |
| p90 | 1.148 µs | 1.579 µs | 1.645 µs | 1.646 µs |
| p95 | 1.794 µs | 2.164 µs | 2.728 µs | 2.380 µs |
| p99 | 2.975 µs | 4.576 µs | 4.052 µs | 4.516 µs |
| Max | 3.514 µs | 4.697 µs | 4.112 µs | 4.554 µs |
| Tail | 2.78× avg (visible tails) | 3.04× avg (wide tails) | 2.75× avg (visible tails) | 2.92× avg (visible tails) |

### modifier only

- Measures: Resolves a modifier without an owning type.
- Represents: Hot free-modifier path.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.477 µs | 0.682 µs | 0.650 µs | 0.670 µs |
| Avg | 0.582 µs | 0.809 µs | 0.751 µs | 0.814 µs |
| p50 | 0.541 µs | 0.712 µs | 0.668 µs | 0.705 µs |
| p90 | 0.613 µs | 0.882 µs | 0.853 µs | 0.886 µs |
| p95 | 0.657 µs | 1.338 µs | 1.034 µs | 1.648 µs |
| p99 | 1.545 µs | 2.224 µs | 2.002 µs | 2.221 µs |
| Max | 1.662 µs | 2.376 µs | 2.402 µs | 2.434 µs |
| Tail | 2.66× avg (visible tails) | 2.75× avg (visible tails) | 2.67× avg (visible tails) | 2.73× avg (visible tails) |

### type + modifier

- Measures: Resolves one type+modifier combination using a cached style object.
- Represents: Common hot semantic-token TypeMod path.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.897 µs | 1.302 µs | 1.305 µs | 1.369 µs |
| Avg | 1.155 µs | 1.595 µs | 1.570 µs | 1.662 µs |
| p50 | 1.031 µs | 1.390 µs | 1.340 µs | 1.453 µs |
| p90 | 1.230 µs | 1.752 µs | 1.681 µs | 1.772 µs |
| p95 | 2.182 µs | 2.210 µs | 2.959 µs | 2.600 µs |
| p99 | 3.262 µs | 4.416 µs | 4.279 µs | 4.415 µs |
| Max | 3.326 µs | 4.756 µs | 4.583 µs | 5.354 µs |
| Tail | 2.82× avg (visible tails) | 2.77× avg (visible tails) | 2.73× avg (visible tails) | 2.66× avg (visible tails) |

### type + 2 modifiers

- Measures: Resolves one type with two modifiers using a cached style object.
- Represents: Hot multi-modifier resolver cost.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.779 µs | 2.809 µs | 2.639 µs | 2.840 µs |
| Avg | 2.250 µs | 3.410 µs | 3.191 µs | 3.444 µs |
| p50 | 2.009 µs | 3.031 µs | 2.734 µs | 3.026 µs |
| p90 | 2.608 µs | 3.648 µs | 3.669 µs | 3.840 µs |
| p95 | 4.376 µs | 5.868 µs | 5.920 µs | 6.302 µs |
| p99 | 5.106 µs | 8.756 µs | 8.151 µs | 8.979 µs |
| Max | 5.502 µs | 8.993 µs | 8.155 µs | 9.040 µs |
| Tail | 2.27× avg (visible tails) | 2.57× avg (visible tails) | 2.55× avg (visible tails) | 2.61× avg (visible tails) |

### type + filetype

- Measures: Resolves a type with filetype-specific semantic context.
- Represents: Hot filetype-qualified resolver path.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.277 µs | 2.068 µs | 1.883 µs | 1.985 µs |
| Avg | 1.628 µs | 2.476 µs | 2.292 µs | 2.411 µs |
| p50 | 1.447 µs | 2.173 µs | 1.954 µs | 2.096 µs |
| p90 | 1.885 µs | 2.640 µs | 2.623 µs | 2.521 µs |
| p95 | 2.447 µs | 3.957 µs | 4.530 µs | 4.883 µs |
| p99 | 4.266 µs | 7.099 µs | 5.607 µs | 7.350 µs |
| Max | 4.606 µs | 7.720 µs | 6.744 µs | 7.407 µs |
| Tail | 2.62× avg (visible tails) | 2.87× avg (visible tails) | 2.45× avg (visible tails) | 3.05× avg (wide tails) |

### explicit TypeMod

- Measures: Resolves a style owned by one explicit type+modifier combination.
- Represents: Hot TypeMod-style path, distinct from a free modifier.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.918 µs | 1.530 µs | 1.340 µs | 1.478 µs |
| Avg | 1.176 µs | 1.810 µs | 1.650 µs | 1.787 µs |
| p50 | 1.057 µs | 1.608 µs | 1.416 µs | 1.580 µs |
| p90 | 1.277 µs | 1.919 µs | 1.864 µs | 1.923 µs |
| p95 | 2.112 µs | 2.770 µs | 3.335 µs | 3.179 µs |
| p99 | 3.023 µs | 5.054 µs | 4.221 µs | 4.815 µs |
| Max | 3.487 µs | 5.097 µs | 4.634 µs | 5.059 µs |
| Tail | 2.57× avg (visible tails) | 2.79× avg (visible tails) | 2.56× avg (visible tails) | 2.70× avg (visible tails) |

### literal

- Measures: Resolves an unknown/literal highlight name instead of a normal semantic type.
- Represents: Literal escape-path cost for names outside the standard semantic chain.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.461 µs | 2.189 µs | 2.049 µs | 2.339 µs |
| Avg | 1.839 µs | 2.614 µs | 2.475 µs | 2.785 µs |
| p50 | 1.648 µs | 2.310 µs | 2.179 µs | 2.466 µs |
| p90 | 2.041 µs | 2.849 µs | 2.768 µs | 2.953 µs |
| p95 | 3.588 µs | 4.247 µs | 4.686 µs | 4.758 µs |
| p99 | 4.128 µs | 6.774 µs | 6.192 µs | 7.167 µs |
| Max | 4.290 µs | 7.602 µs | 6.616 µs | 7.305 µs |
| Tail | 2.24× avg (visible tails) | 2.59× avg (visible tails) | 2.50× avg (visible tails) | 2.57× avg (visible tails) |

### target=vim

- Measures: Resolves a type while materializing only one target mask.
- Represents: Fast target-filtered resolver path after session caches are warm.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.088 µs | 0.106 µs | 0.105 µs | 0.104 µs |
| Avg | 0.089 µs | 0.108 µs | 0.107 µs | 0.107 µs |
| p50 | 0.089 µs | 0.107 µs | 0.106 µs | 0.106 µs |
| p90 | 0.090 µs | 0.110 µs | 0.108 µs | 0.108 µs |
| p95 | 0.091 µs | 0.110 µs | 0.110 µs | 0.108 µs |
| p99 | 0.100 µs | 0.129 µs | 0.121 µs | 0.125 µs |
| Max | 0.119 µs | 0.151 µs | 0.139 µs | 0.137 µs |
| Tail | 1.11× avg (very tight) | 1.19× avg (very tight) | 1.13× avg (very tight) | 1.17× avg (very tight) |

### target=ts

- Measures: Resolves a type while materializing only one target mask.
- Represents: Fast target-filtered resolver path after session caches are warm.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.090 µs | 0.111 µs | 0.106 µs | 0.110 µs |
| Avg | 0.091 µs | 0.114 µs | 0.109 µs | 0.112 µs |
| p50 | 0.090 µs | 0.113 µs | 0.108 µs | 0.112 µs |
| p90 | 0.092 µs | 0.115 µs | 0.112 µs | 0.114 µs |
| p95 | 0.093 µs | 0.118 µs | 0.113 µs | 0.115 µs |
| p99 | 0.117 µs | 0.141 µs | 0.138 µs | 0.139 µs |
| Max | 0.118 µs | 0.150 µs | 0.139 µs | 0.143 µs |
| Tail | 1.28× avg (tight) | 1.23× avg (very tight) | 1.26× avg (tight) | 1.23× avg (very tight) |

### target=lsp

- Measures: Resolves a type while materializing only one target mask.
- Represents: Fast target-filtered resolver path after session caches are warm.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.091 µs | 0.119 µs | 0.112 µs | 0.119 µs |
| Avg | 0.096 µs | 0.122 µs | 0.115 µs | 0.122 µs |
| p50 | 0.095 µs | 0.120 µs | 0.114 µs | 0.122 µs |
| p90 | 0.097 µs | 0.124 µs | 0.117 µs | 0.123 µs |
| p95 | 0.099 µs | 0.125 µs | 0.119 µs | 0.124 µs |
| p99 | 0.121 µs | 0.148 µs | 0.130 µs | 0.152 µs |
| Max | 0.126 µs | 0.164 µs | 0.143 µs | 0.157 µs |
| Tail | 1.26× avg (tight) | 1.22× avg (very tight) | 1.13× avg (very tight) | 1.24× avg (very tight) |

### resolver.clear_cache()

- Measures: Drops resolver session lookup caches.
- Represents: Invalidation cost paid only when the resolver cache must be rebuilt.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 2.457 µs | 3.899 µs | 3.893 µs | 3.921 µs |
| Avg | 2.678 µs | 4.041 µs | 4.032 µs | 4.076 µs |
| p50 | 2.662 µs | 4.072 µs | 4.069 µs | 4.088 µs |
| p90 | 2.816 µs | 4.122 µs | 4.096 µs | 4.128 µs |
| p95 | 2.912 µs | 4.125 µs | 4.108 µs | 4.189 µs |
| p99 | 3.078 µs | 4.157 µs | 4.153 µs | 5.125 µs |
| Max | 3.195 µs | 4.168 µs | 4.164 µs | 5.252 µs |
| Tail | 1.15× avg (very tight) | 1.03× avg (very tight) | 1.03× avg (very tight) | 1.26× avg (tight) |

## Colour engine and pipeline

Packed-RGBA conversion/manipulation and prebuilt pipeline execution. Pure operations use large batches because they are near the timer floor.

### dynamic input baseline

- Measures: Mutates the packed colour input with one BitOp xor and stores it for the next call.
- Represents: Control cost used to keep pure colour probes data-dependent so LuaJIT cannot constant-fold the operation away.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.048 µs | 0.001 µs | 0.046 µs | 0.001 µs |
| Avg | 0.062 µs | 0.001 µs | 0.047 µs | 0.001 µs |
| p50 | 0.054 µs | 0.001 µs | 0.047 µs | 0.001 µs |
| p90 | 0.105 µs | 0.001 µs | 0.048 µs | 0.001 µs |
| p95 | 0.111 µs | 0.001 µs | 0.048 µs | 0.001 µs |
| p99 | 0.112 µs | 0.003 µs | 0.050 µs | 0.003 µs |
| Max | 0.114 µs | 0.004 µs | 0.050 µs | 0.003 µs |
| Tail | 1.81× avg (visible tails) | timer-floor dominated | 1.05× avg (very tight) | timer-floor dominated |

### string input baseline

- Measures: Alternates between two existing hex-string references.
- Represents: Control cost for the dynamic from_hex() probe; not subtracted automatically.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.052 µs | 0.004 µs | 0.048 µs | 0.004 µs |
| Avg | 0.054 µs | 0.004 µs | 0.050 µs | 0.004 µs |
| p50 | 0.054 µs | 0.004 µs | 0.050 µs | 0.004 µs |
| p90 | 0.056 µs | 0.004 µs | 0.051 µs | 0.004 µs |
| p95 | 0.057 µs | 0.004 µs | 0.051 µs | 0.004 µs |
| p99 | 0.058 µs | 0.006 µs | 0.052 µs | 0.006 µs |
| Max | 0.059 µs | 0.008 µs | 0.053 µs | 0.006 µs |
| Tail | 1.08× avg (very tight) | timer-floor dominated | 1.04× avg (very tight) | timer-floor dominated |

### from_hex(dynamic)

- Measures: Parses #RRGGBB into ChromaFlow's packed 0xAARRGGBB representation.
- Represents: Colour-string boundary conversion.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.061 µs | 0.052 µs | 0.067 µs | 0.052 µs |
| Avg | 0.066 µs | 0.053 µs | 0.069 µs | 0.054 µs |
| p50 | 0.067 µs | 0.053 µs | 0.068 µs | 0.054 µs |
| p90 | 0.068 µs | 0.054 µs | 0.070 µs | 0.055 µs |
| p95 | 0.069 µs | 0.054 µs | 0.070 µs | 0.055 µs |
| p99 | 0.072 µs | 0.060 µs | 0.072 µs | 0.058 µs |
| Max | 0.081 µs | 0.069 µs | 0.093 µs | 0.070 µs |
| Tail | 1.09× avg (very tight) | 1.12× avg (very tight) | 1.04× avg (very tight) | 1.08× avg (very tight) |

### to_rgb_hex(dynamic packed)

- Measures: Formats packed RGBA as #RRGGBB.
- Represents: Final GUI highlight colour rendering cost.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.104 µs | 0.066 µs | 0.111 µs | 0.064 µs |
| Avg | 0.110 µs | 0.068 µs | 0.113 µs | 0.066 µs |
| p50 | 0.110 µs | 0.068 µs | 0.112 µs | 0.066 µs |
| p90 | 0.113 µs | 0.068 µs | 0.117 µs | 0.067 µs |
| p95 | 0.114 µs | 0.068 µs | 0.117 µs | 0.067 µs |
| p99 | 0.122 µs | 0.074 µs | 0.119 µs | 0.072 µs |
| Max | 0.139 µs | 0.074 µs | 0.127 µs | 0.089 µs |
| Tail | 1.11× avg (very tight) | 1.09× avg (very tight) | 1.05× avg (very tight) | 1.09× avg (very tight) |

### to_cterm(dynamic packed)

- Measures: Quantizes packed RGB to the nearest xterm-256 palette entry.
- Represents: Terminal colour quantization cost.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.063 µs | 0.011 µs | 0.061 µs | 0.012 µs |
| Avg | 0.067 µs | 0.011 µs | 0.064 µs | 0.012 µs |
| p50 | 0.067 µs | 0.011 µs | 0.063 µs | 0.012 µs |
| p90 | 0.068 µs | 0.012 µs | 0.066 µs | 0.012 µs |
| p95 | 0.068 µs | 0.012 µs | 0.067 µs | 0.012 µs |
| p99 | 0.069 µs | 0.014 µs | 0.069 µs | 0.015 µs |
| Max | 0.070 µs | 0.020 µs | 0.082 µs | 0.020 µs |
| Tail | 1.03× avg (very tight) | 1.22× avg (very tight) | 1.07× avg (very tight) | 1.24× avg (very tight) |

### from_cterm(67/188)

- Measures: Decodes an xterm-256 palette index to packed RGBA.
- Represents: Terminal pipeline input conversion.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.057 µs | 0.094 µs | 0.061 µs | 0.096 µs |
| Avg | 0.061 µs | 0.096 µs | 0.062 µs | 0.100 µs |
| p50 | 0.061 µs | 0.095 µs | 0.062 µs | 0.100 µs |
| p90 | 0.063 µs | 0.096 µs | 0.062 µs | 0.102 µs |
| p95 | 0.063 µs | 0.097 µs | 0.063 µs | 0.103 µs |
| p99 | 0.066 µs | 0.099 µs | 0.074 µs | 0.121 µs |
| Max | 0.069 µs | 0.118 µs | 0.085 µs | 0.151 µs |
| Tail | 1.08× avg (very tight) | 1.04× avg (very tight) | 1.20× avg (very tight) | 1.20× avg (very tight) |

### mix(35)

- Measures: Mixes two packed colours using the numeric RGB/RGBA path.
- Represents: One mix pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.060 µs | 0.095 µs | 0.063 µs | 0.098 µs |
| Avg | 0.063 µs | 0.098 µs | 0.065 µs | 0.100 µs |
| p50 | 0.063 µs | 0.098 µs | 0.064 µs | 0.100 µs |
| p90 | 0.064 µs | 0.099 µs | 0.066 µs | 0.101 µs |
| p95 | 0.064 µs | 0.100 µs | 0.067 µs | 0.102 µs |
| p99 | 0.067 µs | 0.105 µs | 0.070 µs | 0.104 µs |
| Max | 0.074 µs | 0.123 µs | 0.078 µs | 0.124 µs |
| Tail | 1.06× avg (very tight) | 1.07× avg (very tight) | 1.08× avg (very tight) | 1.04× avg (very tight) |

### opacity(85)

- Measures: Computes effective alpha and pre-composited RGB against a background.
- Represents: One opacity pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.066 µs | 0.103 µs | 0.070 µs | 0.106 µs |
| Avg | 0.071 µs | 0.108 µs | 0.072 µs | 0.108 µs |
| p50 | 0.071 µs | 0.108 µs | 0.071 µs | 0.107 µs |
| p90 | 0.072 µs | 0.109 µs | 0.072 µs | 0.109 µs |
| p95 | 0.073 µs | 0.109 µs | 0.073 µs | 0.110 µs |
| p99 | 0.074 µs | 0.114 µs | 0.087 µs | 0.112 µs |
| Max | 0.088 µs | 0.151 µs | 0.088 µs | 0.133 µs |
| Tail | 1.05× avg (very tight) | 1.05× avg (very tight) | 1.21× avg (very tight) | 1.04× avg (very tight) |

### brightness(+20)

- Measures: Applies signed brightness to packed RGB channels.
- Represents: One brightness pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.061 µs | 0.093 µs | 0.062 µs | 0.098 µs |
| Avg | 0.064 µs | 0.095 µs | 0.063 µs | 0.103 µs |
| p50 | 0.064 µs | 0.095 µs | 0.063 µs | 0.102 µs |
| p90 | 0.065 µs | 0.096 µs | 0.064 µs | 0.104 µs |
| p95 | 0.066 µs | 0.096 µs | 0.064 µs | 0.105 µs |
| p99 | 0.067 µs | 0.108 µs | 0.066 µs | 0.109 µs |
| Max | 0.074 µs | 0.126 µs | 0.076 µs | 0.121 µs |
| Tail | 1.04× avg (very tight) | 1.14× avg (very tight) | 1.04× avg (very tight) | 1.06× avg (very tight) |

### lighten(20)

- Measures: Applies the one-direction brightness convenience primitive.
- Represents: One lighten/darken pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.061 µs | 0.092 µs | 0.061 µs | 0.101 µs |
| Avg | 0.064 µs | 0.094 µs | 0.063 µs | 0.103 µs |
| p50 | 0.064 µs | 0.093 µs | 0.062 µs | 0.103 µs |
| p90 | 0.065 µs | 0.094 µs | 0.063 µs | 0.104 µs |
| p95 | 0.066 µs | 0.095 µs | 0.063 µs | 0.105 µs |
| p99 | 0.067 µs | 0.097 µs | 0.076 µs | 0.107 µs |
| Max | 0.079 µs | 0.142 µs | 0.111 µs | 0.108 µs |
| Tail | 1.05× avg (very tight) | 1.03× avg (very tight) | 1.20× avg (very tight) | 1.04× avg (very tight) |

### darken(20)

- Measures: Applies the one-direction brightness convenience primitive.
- Represents: One lighten/darken pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.056 µs | 0.089 µs | 0.059 µs | 0.095 µs |
| Avg | 0.062 µs | 0.092 µs | 0.061 µs | 0.100 µs |
| p50 | 0.062 µs | 0.091 µs | 0.060 µs | 0.100 µs |
| p90 | 0.064 µs | 0.093 µs | 0.061 µs | 0.101 µs |
| p95 | 0.065 µs | 0.093 µs | 0.062 µs | 0.102 µs |
| p99 | 0.067 µs | 0.106 µs | 0.072 µs | 0.104 µs |
| Max | 0.070 µs | 0.121 µs | 0.082 µs | 0.123 µs |
| Tail | 1.06× avg (very tight) | 1.15× avg (very tight) | 1.19× avg (very tight) | 1.04× avg (very tight) |

### shiftHue(45)

- Measures: Converts RGB↔HSL internally and rotates hue on a packed colour.
- Represents: The mathematically heaviest normal colour primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.089 µs | 0.139 µs | 0.102 µs | 0.139 µs |
| Avg | 0.094 µs | 0.143 µs | 0.105 µs | 0.141 µs |
| p50 | 0.094 µs | 0.143 µs | 0.103 µs | 0.141 µs |
| p90 | 0.096 µs | 0.143 µs | 0.108 µs | 0.143 µs |
| p95 | 0.097 µs | 0.144 µs | 0.108 µs | 0.143 µs |
| p99 | 0.099 µs | 0.148 µs | 0.110 µs | 0.144 µs |
| Max | 0.123 µs | 0.151 µs | 0.133 µs | 0.151 µs |
| Tail | 1.05× avg (very tight) | 1.04× avg (very tight) | 1.05× avg (very tight) | 1.02× avg (very tight) |

### gamma(1.10)

- Measures: Applies gamma correction to packed RGB channels.
- Represents: One gamma pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.110 µs | 0.171 µs | 0.132 µs | 0.164 µs |
| Avg | 0.117 µs | 0.174 µs | 0.134 µs | 0.170 µs |
| p50 | 0.116 µs | 0.172 µs | 0.133 µs | 0.170 µs |
| p90 | 0.119 µs | 0.180 µs | 0.135 µs | 0.172 µs |
| p95 | 0.120 µs | 0.181 µs | 0.135 µs | 0.173 µs |
| p99 | 0.128 µs | 0.189 µs | 0.148 µs | 0.174 µs |
| Max | 0.142 µs | 0.193 µs | 0.150 µs | 0.184 µs |
| Tail | 1.10× avg (very tight) | 1.08× avg (very tight) | 1.11× avg (very tight) | 1.03× avg (very tight) |

### construct shiftHue.fg(45)

- Measures: Creates one pipeline operation table through the public channel API.
- Represents: The allocation cost paid while compiling/creating a pipeline, not while applying a prebuilt pipeline.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.070 µs | 0.109 µs | 0.074 µs | 0.109 µs |
| Avg | 0.118 µs | 0.150 µs | 0.145 µs | 0.140 µs |
| p50 | 0.079 µs | 0.117 µs | 0.080 µs | 0.116 µs |
| p90 | 0.168 µs | 0.222 µs | 0.213 µs | 0.215 µs |
| p95 | 0.234 µs | 0.239 µs | 0.535 µs | 0.225 µs |
| p99 | 0.708 µs | 0.324 µs | 0.938 µs | 0.246 µs |
| Max | 0.748 µs | 0.481 µs | 1.002 µs | 0.278 µs |
| Tail | 5.99× avg (wide tails) | 2.17× avg (visible tails) | 6.47× avg (wide tails) | 1.76× avg (visible tails) |

### apply nil

- Measures: Calls pipeline.apply() with no operations.
- Represents: Early-return floor for styles without a pipeline.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.058 µs | 0.087 µs | 0.052 µs | 0.085 µs |
| Avg | 0.060 µs | 0.090 µs | 0.053 µs | 0.089 µs |
| p50 | 0.060 µs | 0.089 µs | 0.052 µs | 0.088 µs |
| p90 | 0.061 µs | 0.091 µs | 0.053 µs | 0.089 µs |
| p95 | 0.062 µs | 0.095 µs | 0.054 µs | 0.090 µs |
| p99 | 0.064 µs | 0.105 µs | 0.057 µs | 0.103 µs |
| Max | 0.113 µs | 0.137 µs | 0.099 µs | 0.148 µs |
| Tail | 1.05× avg (very tight) | 1.17× avg (very tight) | 1.08× avg (very tight) | 1.17× avg (very tight) |

### apply 1 op

- Measures: Applies one prebuilt pipeline operation to packed colours.
- Represents: Single-operation runtime pipeline cost with construction excluded.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.113 µs | 0.161 µs | 0.365 µs | 0.450 µs |
| Avg | 0.120 µs | 0.168 µs | 0.379 µs | 0.455 µs |
| p50 | 0.119 µs | 0.165 µs | 0.368 µs | 0.453 µs |
| p90 | 0.120 µs | 0.171 µs | 0.382 µs | 0.463 µs |
| p95 | 0.122 µs | 0.177 µs | 0.437 µs | 0.465 µs |
| p99 | 0.146 µs | 0.222 µs | 0.461 µs | 0.471 µs |
| Max | 0.228 µs | 0.328 µs | 0.845 µs | 0.480 µs |
| Tail | 1.22× avg (very tight) | 1.32× avg (tight) | 1.21× avg (very tight) | 1.03× avg (very tight) |

### apply 7 ops

- Measures: Applies a prebuilt seven-operation mixed pipeline.
- Represents: Representative multi-operation pipeline execution cost.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.321 µs | 0.503 µs | 2.543 µs | 2.367 µs |
| Avg | 0.426 µs | 0.518 µs | 2.592 µs | 2.453 µs |
| p50 | 0.342 µs | 0.505 µs | 2.578 µs | 2.456 µs |
| p90 | 0.368 µs | 0.515 µs | 2.636 µs | 2.522 µs |
| p95 | 0.375 µs | 0.520 µs | 2.667 µs | 2.553 µs |
| p99 | 0.391 µs | 0.563 µs | 2.681 µs | 2.634 µs |
| Max | 8.453 µs | 1.545 µs | 2.936 µs | 3.170 µs |
| Tail | 0.92× avg (very tight) | 1.09× avg (very tight) | 1.03× avg (very tight) | 1.07× avg (very tight) |

## Highlight apply

Action flatten/sort, resolver/raw actions and theme apply bookkeeping. This is the back half of a compiled theme load before editor consumers redraw.

### ColorSchemePre autocmd

- Measures: Executes only the ColorSchemePre event used by theme.apply().
- Represents: External autocmd contribution before highlight replacement.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.362 µs | 0.520 µs | 0.469 µs | 0.511 µs |
| Avg | 0.523 µs | 0.727 µs | 0.675 µs | 0.718 µs |
| p50 | 0.389 µs | 0.549 µs | 0.502 µs | 0.547 µs |
| p90 | 0.443 µs | 0.585 µs | 0.569 µs | 0.598 µs |
| p95 | 0.469 µs | 0.680 µs | 0.593 µs | 0.634 µs |
| p99 | 2.770 µs | 3.764 µs | 3.636 µs | 3.728 µs |
| Max | 10.392 µs | 9.728 µs | 13.724 µs | 12.337 µs |
| Tail | 5.29× avg (wide tails) | 5.18× avg (wide tails) | 5.39× avg (wide tails) | 5.19× avg (wide tails) |

### reset_highlights() [steady repeated]

- Measures: Clears/reinitializes highlights in the same steady repeated state used by apply.
- Represents: Neovim highlight reset contribution.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 136.907 µs | 204.108 µs | 204.071 µs | 204.308 µs |
| Avg | 148.240 µs | 212.150 µs | 207.447 µs | 212.019 µs |
| p50 | 148.528 µs | 212.593 µs | 206.154 µs | 208.274 µs |
| p90 | 155.390 µs | 215.767 µs | 211.560 µs | 219.158 µs |
| p95 | 161.976 µs | 218.963 µs | 214.391 µs | 225.653 µs |
| p99 | 163.264 µs | 222.391 µs | 222.071 µs | 280.149 µs |
| Max | 167.075 µs | 226.710 µs | 226.668 µs | 304.833 µs |
| Tail | 1.10× avg (very tight) | 1.05× avg (very tight) | 1.07× avg (very tight) | 1.32× avg (tight) |

### refresh_catalog()

- Measures: Refreshes the runtime highlight catalog.
- Represents: Runtime lookup/catalog maintenance after theme changes.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 578.570 µs | 853.129 µs | 784.599 µs | 948.213 µs |
| Avg | 808.572 µs | 1.224 ms | 1.118 ms | 1.317 ms |
| p50 | 634.671 µs | 984.503 µs | 863.715 µs | 1.059 ms |
| p90 | 1.376 ms | 2.311 ms | 1.973 ms | 2.454 ms |
| p95 | 1.457 ms | 2.531 ms | 2.090 ms | 2.772 ms |
| p99 | 1.546 ms | 2.640 ms | 2.250 ms | 2.822 ms |
| Max | 1.554 ms | 2.657 ms | 2.439 ms | 2.895 ms |
| Tail | 1.91× avg (visible tails) | 2.16× avg (visible tails) | 2.01× avg (visible tails) | 2.14× avg (visible tails) |

### runtime.global_clear()

- Measures: Propagates the compiler's global clear state into runtime state.
- Represents: Runtime clear bookkeeping during apply.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.063 µs | 0.093 µs | 0.058 µs | 0.103 µs |
| Avg | 0.067 µs | 0.198 µs | 0.141 µs | 0.109 µs |
| p50 | 0.065 µs | 0.097 µs | 0.059 µs | 0.106 µs |
| p90 | 0.067 µs | 0.104 µs | 0.099 µs | 0.108 µs |
| p95 | 0.068 µs | 0.142 µs | 0.107 µs | 0.110 µs |
| p99 | 0.071 µs | 3.897 µs | 0.502 µs | 0.111 µs |
| Max | 0.276 µs | 5.804 µs | 7.328 µs | 0.387 µs |
| Tail | 1.06× avg (very tight) | 19.65× avg (wide tails) | 3.56× avg (wide tails) | 1.02× avg (very tight) |

### flatten + sort actions [938 actions]

- Measures: Flattens all module actions and sorts them by apply priority.
- Represents: Pure Lua action scheduling cost before Neovim writes.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 426.197 µs | 657.193 µs | 648.653 µs | 662.151 µs |
| Avg | 475.544 µs | 664.338 µs | 655.506 µs | 673.033 µs |
| p50 | 476.450 µs | 660.211 µs | 651.873 µs | 667.690 µs |
| p90 | 488.733 µs | 670.278 µs | 660.430 µs | 692.760 µs |
| p95 | 501.049 µs | 671.601 µs | 665.210 µs | 702.168 µs |
| p99 | 516.841 µs | 725.888 µs | 709.749 µs | 705.000 µs |
| Max | 557.290 µs | 759.843 µs | 726.851 µs | 709.888 µs |
| Tail | 1.09× avg (very tight) | 1.09× avg (very tight) | 1.08× avg (very tight) | 1.05× avg (very tight) |
| Avg / action | 0.507 µs | 0.708 µs | 0.699 µs | 0.718 µs |

### run_action all [938 actions]

- Measures: Executes every already-sorted compiled action one by one.
- Represents: Core action execution cost for the complete theme.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 937.300 µs | 1.499 ms | 1.408 ms | 1.314 ms |
| Avg | 1.178 ms | 1.727 ms | 1.661 ms | 1.572 ms |
| p50 | 1.062 ms | 1.599 ms | 1.506 ms | 1.453 ms |
| p90 | 1.421 ms | 1.871 ms | 1.815 ms | 1.778 ms |
| p95 | 1.985 ms | 2.171 ms | 2.656 ms | 1.949 ms |
| p99 | 2.826 ms | 3.676 ms | 3.887 ms | 3.810 ms |
| Max | 3.487 ms | 4.715 ms | 4.347 ms | 3.989 ms |
| Tail | 2.40× avg (visible tails) | 2.13× avg (visible tails) | 2.34× avg (visible tails) | 2.42× avg (visible tails) |
| Avg / action | 1.256 µs | 1.841 µs | 1.771 µs | 1.676 µs |

### resolver.clear_cache + _apply_modules [938 actions]

- Measures: Clears resolver caches and then applies every compiled module.
- Represents: Cold full-module apply path after resolver invalidation.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.913 ms | 2.649 ms | 2.631 ms | 2.701 ms |
| Avg | 2.461 ms | 3.419 ms | 3.281 ms | 3.464 ms |
| p50 | 2.164 ms | 3.114 ms | 2.896 ms | 3.165 ms |
| p90 | 2.979 ms | 3.771 ms | 3.597 ms | 3.973 ms |
| p95 | 4.648 ms | 5.117 ms | 6.429 ms | 5.071 ms |
| p99 | 5.980 ms | 9.547 ms | 8.463 ms | 9.238 ms |
| Max | 6.243 ms | 10.232 ms | 8.793 ms | 10.035 ms |
| Tail | 2.43× avg (visible tails) | 2.79× avg (visible tails) | 2.58× avg (visible tails) | 2.67× avg (visible tails) |
| Avg / action | 2.624 µs | 3.644 µs | 3.498 µs | 3.693 µs |

### _apply_modules cached [938 actions]

- Measures: Applies every compiled module with resolver session caches already warm.
- Represents: Steady repeated module-apply path.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.363 ms | 2.255 ms | 2.068 ms | 2.214 ms |
| Avg | 1.678 ms | 2.624 ms | 2.560 ms | 2.502 ms |
| p50 | 1.565 ms | 2.469 ms | 2.460 ms | 2.394 ms |
| p90 | 1.943 ms | 2.896 ms | 2.826 ms | 2.821 ms |
| p95 | 2.475 ms | 4.208 ms | 3.690 ms | 2.925 ms |
| p99 | 3.138 ms | 5.643 ms | 5.200 ms | 4.886 ms |
| Max | 4.137 ms | 5.650 ms | 5.450 ms | 5.394 ms |
| Tail | 1.87× avg (visible tails) | 2.15× avg (visible tails) | 2.03× avg (visible tails) | 1.95× avg (visible tails) |
| Avg / action | 1.789 µs | 2.798 µs | 2.729 µs | 2.667 µs |

### resolver_style [834 actions]

- Measures: Executes only the compiled actions of the named action kind.
- Represents: Breakdown of total action execution by resolver/raw style/link/clear kind.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 850.584 µs | 1.373 ms | 1.301 ms | 1.291 ms |
| Avg | 1.068 ms | 1.642 ms | 1.528 ms | 1.553 ms |
| p50 | 988.782 µs | 1.531 ms | 1.403 ms | 1.427 ms |
| p90 | 1.402 ms | 1.800 ms | 1.948 ms | 1.820 ms |
| p95 | 1.565 ms | 2.549 ms | 2.441 ms | 2.436 ms |
| p99 | 1.902 ms | 3.045 ms | 2.629 ms | 3.043 ms |
| Max | 1.912 ms | 3.203 ms | 2.645 ms | 3.256 ms |
| Tail | 1.78× avg (visible tails) | 1.85× avg (visible tails) | 1.72× avg (tight) | 1.96× avg (visible tails) |
| Avg / action | 1.281 µs | 1.969 µs | 1.832 µs | 1.863 µs |

### resolver_link [104 actions]

- Measures: Executes only the compiled actions of the named action kind.
- Represents: Breakdown of total action execution by resolver/raw style/link/clear kind.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 88.366 µs | 119.340 µs | 123.157 µs | 120.488 µs |
| Avg | 123.148 µs | 167.283 µs | 169.479 µs | 155.783 µs |
| p50 | 97.242 µs | 128.642 µs | 136.399 µs | 128.432 µs |
| p90 | 136.888 µs | 184.328 µs | 188.628 µs | 179.290 µs |
| p95 | 266.578 µs | 369.136 µs | 328.374 µs | 209.876 µs |
| p99 | 459.183 µs | 638.348 µs | 645.026 µs | 623.560 µs |
| Max | 515.291 µs | 652.430 µs | 774.312 µs | 645.365 µs |
| Tail | 3.73× avg (wide tails) | 3.82× avg (wide tails) | 3.81× avg (wide tails) | 4.00× avg (wide tails) |
| Avg / action | 1.184 µs | 1.608 µs | 1.630 µs | 1.498 µs |

### runtime _theme_prepare()

- Measures: Prepares sparse runtime overlays for an incoming compiled theme.
- Represents: Runtime pre-apply bookkeeping.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.068 µs | 0.079 µs | 0.104 µs | 0.115 µs |
| Avg | 0.305 µs | 0.559 µs | 0.332 µs | 0.316 µs |
| p50 | 0.082 µs | 0.123 µs | 0.162 µs | 0.142 µs |
| p90 | 0.162 µs | 0.268 µs | 0.284 µs | 0.232 µs |
| p95 | 0.185 µs | 1.405 µs | 0.384 µs | 0.415 µs |
| p99 | 8.357 µs | 10.884 µs | 4.454 µs | 5.335 µs |
| Max | 9.096 µs | 11.982 µs | 8.293 µs | 5.477 µs |
| Tail | 27.40× avg (wide tails) | 19.46× avg (wide tails) | 13.42× avg (wide tails) | 16.86× avg (wide tails) |

### ColorScheme autocmd

- Measures: Executes only the ColorScheme event.
- Represents: External autocmd contribution after highlights are applied.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 2.240 µs | 2.911 µs | 5.033 µs | 4.972 µs |
| Avg | 2.523 µs | 3.328 µs | 5.467 µs | 5.505 µs |
| p50 | 2.324 µs | 3.054 µs | 5.211 µs | 5.181 µs |
| p90 | 2.523 µs | 3.422 µs | 5.825 µs | 5.878 µs |
| p95 | 3.295 µs | 4.280 µs | 6.606 µs | 6.854 µs |
| p99 | 5.033 µs | 7.003 µs | 8.648 µs | 9.253 µs |
| Max | 10.262 µs | 10.792 µs | 11.246 µs | 16.142 µs |
| Tail | 1.99× avg (visible tails) | 2.10× avg (visible tails) | 1.58× avg (tight) | 1.68× avg (tight) |

### runtime _theme_applied()

- Measures: Rebinds/recomposes surviving sparse runtime overlays after apply.
- Represents: Runtime post-apply bookkeeping.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.044 µs | 0.060 µs | 0.063 µs | 0.049 µs |
| Avg | 0.186 µs | 0.209 µs | 0.216 µs | 0.348 µs |
| p50 | 0.048 µs | 0.071 µs | 0.069 µs | 0.090 µs |
| p90 | 0.060 µs | 0.100 µs | 0.083 µs | 0.180 µs |
| p95 | 0.096 µs | 0.145 µs | 0.149 µs | 1.461 µs |
| p99 | 4.426 µs | 5.656 µs | 6.184 µs | 6.778 µs |
| Max | 5.406 µs | 7.143 µs | 7.504 µs | 6.874 µs |
| Tail | 23.81× avg (wide tails) | 27.00× avg (wide tails) | 28.66× avg (wide tails) | 19.46× avg (wide tails) |

## Editor consumers and redraw

Tree-sitter/LSP refresh hooks and Neovim redraw. These are intentionally low-batch because they are external editor work, not a tight Lua hot loop.

### refresh_consumers() no redraw

- Measures: Runs only configured Tree-sitter/LSP consumer refreshes, excluding redraw.
- Represents: Optional editor-consumer cost controlled by autoreload settings.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.056 µs | 0.072 µs | 0.077 µs | 0.064 µs |
| Avg | 0.436 µs | 0.602 µs | 0.618 µs | 0.610 µs |
| p50 | 0.060 µs | 0.075 µs | 0.079 µs | 0.067 µs |
| p90 | 0.133 µs | 0.177 µs | 0.200 µs | 0.156 µs |
| p95 | 0.158 µs | 0.193 µs | 0.224 µs | 0.181 µs |
| p99 | 0.878 µs | 1.260 µs | 1.555 µs | 0.831 µs |
| Max | 35.765 µs | 50.078 µs | 50.766 µs | 52.314 µs |
| Tail | 2.01× avg (visible tails) | 2.09× avg (visible tails) | 2.52× avg (visible tails) | 1.36× avg (tight) |

### treesitter only

- Measures: Forces the Tree-sitter refresh helper in the current editor state.
- Represents: External Tree-sitter refresh cost; highly buffer/config dependent.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.067 µs | 0.088 µs | 0.094 µs | 0.079 µs |
| Avg | 0.322 µs | 0.666 µs | 0.525 µs | 0.465 µs |
| p50 | 0.071 µs | 0.092 µs | 0.099 µs | 0.083 µs |
| p90 | 0.190 µs | 0.161 µs | 0.256 µs | 0.241 µs |
| p95 | 0.261 µs | 0.388 µs | 0.301 µs | 0.340 µs |
| p99 | 1.045 µs | 19.924 µs | 1.094 µs | 1.164 µs |
| Max | 22.367 µs | 33.875 µs | 39.745 µs | 34.776 µs |
| Tail | 3.25× avg (wide tails) | 29.92× avg (wide tails) | 2.08× avg (visible tails) | 2.51× avg (visible tails) |

### lsp semantic tokens only

- Measures: Forces the semantic-token refresh helper in the current editor state.
- Represents: External LSP semantic-token refresh cost; highly client/buffer dependent.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.163 µs | 0.105 µs | 0.108 µs | 0.096 µs |
| Avg | 0.599 µs | 0.933 µs | 0.912 µs | 0.915 µs |
| p50 | 0.187 µs | 0.107 µs | 0.112 µs | 0.098 µs |
| p90 | 0.353 µs | 0.420 µs | 0.428 µs | 0.423 µs |
| p95 | 0.439 µs | 0.485 µs | 0.490 µs | 0.441 µs |
| p99 | 3.282 µs | 1.111 µs | 1.540 µs | 1.361 µs |
| Max | 31.974 µs | 77.627 µs | 74.369 µs | 76.572 µs |
| Tail | 5.48× avg (wide tails) | 1.19× avg (very tight) | 1.69× avg (tight) | 1.49× avg (tight) |

### redraw! only

- Measures: Runs Neovim redraw! with no ChromaFlow work around it.
- Represents: Editor redraw cost ChromaFlow cannot meaningfully optimize internally.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 143.058 µs | 192.632 µs | 197.083 µs | 189.817 µs |
| Avg | 174.322 µs | 210.063 µs | 244.698 µs | 202.252 µs |
| p50 | 156.677 µs | 205.921 µs | 227.216 µs | 196.670 µs |
| p90 | 217.859 µs | 223.583 µs | 293.572 µs | 219.006 µs |
| p95 | 239.697 µs | 229.435 µs | 317.653 µs | 235.066 µs |
| p99 | 261.218 µs | 255.784 µs | 349.288 µs | 255.801 µs |
| Max | 263.925 µs | 258.477 µs | 359.309 µs | 264.740 µs |
| Tail | 1.50× avg (tight) | 1.22× avg (very tight) | 1.43× avg (tight) | 1.26× avg (tight) |

### treesitter + lsp + redraw!

- Measures: Runs all consumer refresh helpers followed by redraw!.
- Represents: Upper consumer-side combination in the current editor state.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 148.944 µs | 194.814 µs | 195.815 µs | 195.722 µs |
| Avg | 169.102 µs | 216.517 µs | 221.509 µs | 216.104 µs |
| p50 | 155.224 µs | 211.461 µs | 219.625 µs | 203.969 µs |
| p90 | 222.362 µs | 230.363 µs | 237.773 µs | 279.011 µs |
| p95 | 244.734 µs | 241.687 µs | 245.724 µs | 287.382 µs |
| p99 | 257.339 µs | 266.224 µs | 257.008 µs | 311.768 µs |
| Max | 278.018 µs | 326.170 µs | 331.734 µs | 333.865 µs |
| Tail | 1.52× avg (tight) | 1.23× avg (very tight) | 1.16× avg (very tight) | 1.44× avg (tight) |

### refresh_consumers() [configured]

- Measures: Runs the exact consumer policy currently configured in cf.config.
- Represents: Consumer tail included by theme.apply() for this benchmark setup.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 130.358 µs | 203.427 µs | 207.208 µs | 204.871 µs |
| Avg | 153.491 µs | 240.435 µs | 230.326 µs | 246.513 µs |
| p50 | 147.897 µs | 223.933 µs | 221.412 µs | 221.975 µs |
| p90 | 173.111 µs | 305.929 µs | 265.856 µs | 310.514 µs |
| p95 | 192.992 µs | 318.638 µs | 294.565 µs | 322.261 µs |
| p99 | 245.781 µs | 322.713 µs | 315.192 µs | 331.523 µs |
| Max | 258.475 µs | 354.501 µs | 331.911 µs | 359.272 µs |
| Tail | 1.60× avg (tight) | 1.34× avg (tight) | 1.37× avg (tight) | 1.34× avg (tight) |

## Runtime, picker, LineBlend and watcher

Session-state helpers and optional runtime/UI integration. This section makes the cost of sparse runtime state and surrounding services visible separately from core compile/apply.

### picker style state

- Measures: Reads the current sparse picker/runtime state for one real compiled target.
- Represents: Picker inspection cost before editing a style.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.566 µs | 0.852 µs | 0.879 µs | 0.861 µs |
| Avg | 0.988 µs | 1.508 µs | 1.532 µs | 1.506 µs |
| p50 | 0.631 µs | 0.939 µs | 0.977 µs | 0.983 µs |
| p90 | 1.341 µs | 1.688 µs | 1.902 µs | 1.714 µs |
| p95 | 3.514 µs | 3.424 µs | 4.408 µs | 4.006 µs |
| p99 | 4.216 µs | 7.674 µs | 7.238 µs | 8.122 µs |
| Max | 5.135 µs | 8.109 µs | 7.454 µs | 8.459 µs |
| Tail | 4.27× avg (wide tails) | 5.09× avg (wide tails) | 4.73× avg (wide tails) | 5.39× avg (wide tails) |

### picker style write

- Measures: Writes one style through the runtime picker overlay path.
- Represents: Cost of one live picker style update, excluding UI key handling/rendering.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.648 µs | 3.222 µs | 3.083 µs | 3.127 µs |
| Avg | 2.054 µs | 3.912 µs | 3.663 µs | 3.738 µs |
| p50 | 1.847 µs | 3.466 µs | 3.293 µs | 3.384 µs |
| p90 | 2.211 µs | 4.856 µs | 3.884 µs | 3.913 µs |
| p95 | 3.275 µs | 6.360 µs | 6.522 µs | 6.207 µs |
| p99 | 4.633 µs | 8.505 µs | 8.552 µs | 8.505 µs |
| Max | 5.214 µs | 11.081 µs | 8.779 µs | 9.367 µs |
| Tail | 2.26× avg (visible tails) | 2.17× avg (visible tails) | 2.33× avg (visible tails) | 2.28× avg (visible tails) |

### lineblend.refresh() [current state]

- Measures: Runs LineBlend's cached refresh in the current state.
- Represents: Normal ChromaFlow post-reload LineBlend interaction.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.425 µs | 0.601 µs | 0.546 µs | 0.582 µs |
| Avg | 0.640 µs | 0.826 µs | 0.789 µs | 0.805 µs |
| p50 | 0.483 µs | 0.639 µs | 0.591 µs | 0.636 µs |
| p90 | 0.566 µs | 0.680 µs | 0.628 µs | 0.698 µs |
| p95 | 0.585 µs | 0.709 µs | 0.649 µs | 0.716 µs |
| p99 | 4.995 µs | 7.083 µs | 5.630 µs | 5.265 µs |
| Max | 8.178 µs | 11.981 µs | 12.128 µs | 11.646 µs |
| Tail | 7.80× avg (wide tails) | 8.58× avg (wide tails) | 7.13× avg (wide tails) | 6.54× avg (wide tails) |

### lineblend.reload() [current state]

- Measures: Runs LineBlend's hard reload path.
- Represents: Expensive diagnostic comparison only; ChromaFlow intentionally does not hard-reload LineBlend on normal reloads.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 57.924 µs | 86.547 µs | 82.641 µs | 85.268 µs |
| Avg | 64.585 µs | 97.003 µs | 95.799 µs | 97.117 µs |
| p50 | 60.013 µs | 89.461 µs | 89.425 µs | 89.620 µs |
| p90 | 79.787 µs | 115.534 µs | 120.774 µs | 120.220 µs |
| p95 | 87.335 µs | 130.322 µs | 129.007 µs | 129.748 µs |
| p99 | 96.980 µs | 146.160 µs | 138.023 µs | 157.171 µs |
| Max | 120.729 µs | 149.709 µs | 156.406 µs | 163.749 µs |
| Tail | 1.50× avg (tight) | 1.51× avg (tight) | 1.44× avg (tight) | 1.62× avg (tight) |

### watcher.is_running()

- Measures: Checks watcher state.
- Represents: Tiny service-state query.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.000 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| Avg | 0.001 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p50 | 0.000 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p90 | 0.000 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p95 | 0.001 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p99 | 0.013 µs | 0.019 µs | 0.020 µs | 0.020 µs |
| Max | 0.034 µs | 0.025 µs | 0.024 µs | 0.026 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | timer-floor dominated |

### watcher.set_themes()

- Measures: Updates watcher default/active theme scopes without rebuilding the watcher.
- Represents: Normal watcher bookkeeping after a reload when watching is active.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.048 µs | 0.069 µs | 0.066 µs | 0.065 µs |
| Avg | 0.152 µs | 0.221 µs | 0.322 µs | 0.224 µs |
| p50 | 0.050 µs | 0.070 µs | 0.067 µs | 0.066 µs |
| p90 | 0.052 µs | 0.081 µs | 0.072 µs | 0.075 µs |
| p95 | 0.108 µs | 0.153 µs | 0.146 µs | 0.162 µs |
| p99 | 4.240 µs | 6.126 µs | 7.542 µs | 6.611 µs |
| Max | 5.217 µs | 7.839 µs | 16.610 µs | 7.846 µs |
| Tail | 27.82× avg (wide tails) | 27.67× avg (wide tails) | 23.44× avg (wide tails) | 29.53× avg (wide tails) |

## Diagnostics and source tracing

Diagnostic gates/queues and picker/ColorTrace source tracing in the currently active feature configuration.

### _enabled(error+hint)

- Measures: Runs the diagnostic policy gate for two severities.
- Represents: Producer-side early-out cost in the active severity configuration.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.000 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| Avg | 0.001 µs | 0.002 µs | 0.002 µs | 0.002 µs |
| p50 | 0.000 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p90 | 0.001 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p95 | 0.001 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p99 | 0.015 µs | 0.029 µs | 0.020 µs | 0.023 µs |
| Max | 0.056 µs | 0.124 µs | 0.094 µs | 0.134 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | timer-floor dominated |

### clear_pending()

- Measures: Clears the pending diagnostic queue.
- Represents: Per-theme-cycle queue reset cost.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.000 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| Avg | 0.001 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p50 | 0.000 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p90 | 0.000 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p95 | 0.000 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p99 | 0.018 µs | 0.018 µs | 0.017 µs | 0.019 µs |
| Max | 0.018 µs | 0.026 µs | 0.027 µs | 0.028 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | timer-floor dominated |

### flush() empty

- Measures: Flushes an empty diagnostic queue after clearing it.
- Represents: No-record end-of-cycle diagnostic overhead.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.004 µs | 0.005 µs | 0.005 µs | 0.005 µs |
| Avg | 0.004 µs | 0.006 µs | 0.006 µs | 0.006 µs |
| p50 | 0.004 µs | 0.005 µs | 0.005 µs | 0.005 µs |
| p90 | 0.004 µs | 0.006 µs | 0.005 µs | 0.006 µs |
| p95 | 0.004 µs | 0.006 µs | 0.006 µs | 0.006 µs |
| p99 | 0.017 µs | 0.026 µs | 0.022 µs | 0.025 µs |
| Max | 0.023 µs | 0.036 µs | 0.033 µs | 0.041 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | timer-floor dominated |

### _source_mode(current flags)

- Measures: Determines source tracing mode for one real theme file.
- Represents: ColorTrace/picker source-trace gate cost.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.415 µs | 1.970 µs | 4.387 µs | 4.393 µs |
| Avg | 2.372 µs | 3.342 µs | 7.380 µs | 7.332 µs |
| p50 | 1.631 µs | 2.203 µs | 5.468 µs | 5.349 µs |
| p90 | 4.921 µs | 6.581 µs | 13.569 µs | 14.680 µs |
| p95 | 5.877 µs | 9.182 µs | 13.994 µs | 16.391 µs |
| p99 | 6.833 µs | 10.506 µs | 14.449 µs | 17.111 µs |
| Max | 6.940 µs | 11.208 µs | 14.630 µs | 17.241 µs |
| Tail | 2.88× avg (visible tails) | 3.14× avg (wide tails) | 1.96× avg (visible tails) | 2.33× avg (visible tails) |

### _cached(file)

- Measures: Looks up cached source-trace data for one real theme file.
- Represents: Hot picker/ColorTrace source cache lookup.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | — | 1.933 µs | — | 1.912 µs |
| Avg | — | 3.244 µs | — | 3.151 µs |
| p50 | — | 2.158 µs | — | 2.112 µs |
| p90 | — | 6.506 µs | — | 6.553 µs |
| p95 | — | 8.499 µs | — | 8.010 µs |
| p99 | — | 10.271 µs | — | 11.036 µs |
| Max | — | 10.913 µs | — | 11.651 µs |
| Tail | — | 3.17× avg (wide tails) | — | 3.50× avg (wide tails) |

### scan cached records [8]

- Measures: Iterates the cached source-trace records for one real file.
- Represents: Cost of consuming trace metadata after lookup.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | — | 0.123 µs | — | 0.114 µs |
| Avg | — | 0.129 µs | — | 0.116 µs |
| p50 | — | 0.128 µs | — | 0.115 µs |
| p90 | — | 0.132 µs | — | 0.118 µs |
| p95 | — | 0.134 µs | — | 0.119 µs |
| p99 | — | 0.142 µs | — | 0.139 µs |
| Max | — | 0.168 µs | — | 0.145 µs |
| Tail | — | 1.10× avg (very tight) | — | 1.20× avg (very tight) |

## Float renderer

The reusable float diff renderer used by ChromaFlow UI. Same-reference, span replacement, bulk line updates and window open/hide are measured separately.

### set_line same reference

- Measures: Sets a float line to the exact same span-table reference.
- Represents: Best-case early-out of the float diff renderer.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.002 µs | 0.002 µs | 0.002 µs | 0.002 µs |
| Avg | 0.006 µs | 0.007 µs | 0.007 µs | 0.007 µs |
| p50 | 0.002 µs | 0.002 µs | 0.002 µs | 0.002 µs |
| p90 | 0.002 µs | 0.003 µs | 0.003 µs | 0.003 µs |
| p95 | 0.002 µs | 0.003 µs | 0.003 µs | 0.003 µs |
| p99 | 0.148 µs | 0.186 µs | 0.192 µs | 0.184 µs |
| Max | 0.267 µs | 0.304 µs | 0.331 µs | 0.296 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | timer-floor dominated |

### replace 3 spans

- Measures: Alternates one float line between two three-span layouts.
- Represents: Typical small diff/update cost.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 3.231 µs | 4.852 µs | 4.818 µs | 4.821 µs |
| Avg | 3.583 µs | 4.941 µs | 4.968 µs | 4.883 µs |
| p50 | 3.537 µs | 4.888 µs | 4.853 µs | 4.854 µs |
| p90 | 3.760 µs | 5.037 µs | 5.011 µs | 4.996 µs |
| p95 | 3.819 µs | 5.126 µs | 5.677 µs | 5.082 µs |
| p99 | 4.054 µs | 5.629 µs | 7.063 µs | 5.174 µs |
| Max | 6.224 µs | 7.192 µs | 7.235 µs | 5.569 µs |
| Tail | 1.13× avg (very tight) | 1.14× avg (very tight) | 1.42× avg (tight) | 1.06× avg (very tight) |

### set_lines 20x3 spans

- Measures: Alternates twenty lines containing three spans each.
- Represents: Bulk float model-update cost before explicit flush.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 54.224 µs | 81.298 µs | 80.904 µs | 81.709 µs |
| Avg | 59.621 µs | 83.452 µs | 83.993 µs | 83.218 µs |
| p50 | 59.718 µs | 82.802 µs | 84.474 µs | 83.011 µs |
| p90 | 60.739 µs | 86.028 µs | 85.864 µs | 85.491 µs |
| p95 | 61.005 µs | 86.155 µs | 86.745 µs | 86.427 µs |
| p99 | 61.327 µs | 86.852 µs | 88.601 µs | 87.355 µs |
| Max | 62.531 µs | 89.264 µs | 89.974 µs | 89.422 µs |
| Tail | 1.03× avg (very tight) | 1.04× avg (very tight) | 1.05× avg (very tight) | 1.05× avg (very tight) |

### flush all 20x3 spans

- Measures: Flushes the current twenty-line/three-span float state to Neovim.
- Represents: Bulk renderer→Neovim write cost.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 56.764 µs | 80.740 µs | 80.413 µs | 81.154 µs |
| Avg | 60.053 µs | 83.828 µs | 83.557 µs | 84.704 µs |
| p50 | 59.555 µs | 84.184 µs | 81.741 µs | 85.041 µs |
| p90 | 61.229 µs | 85.662 µs | 88.405 µs | 86.679 µs |
| p95 | 63.270 µs | 87.509 µs | 88.814 µs | 88.102 µs |
| p99 | 64.475 µs | 88.341 µs | 91.698 µs | 89.549 µs |
| Max | 66.572 µs | 90.943 µs | 117.661 µs | 90.623 µs |
| Tail | 1.07× avg (very tight) | 1.05× avg (very tight) | 1.10× avg (very tight) | 1.06× avg (very tight) |

### hide + open

- Measures: Hides and reopens the same float window.
- Represents: Window lifecycle cost rather than line diff cost.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 15.756 µs | 22.597 µs | 24.237 µs | 23.941 µs |
| Avg | 17.923 µs | 26.142 µs | 29.014 µs | 28.463 µs |
| p50 | 16.075 µs | 23.176 µs | 24.781 µs | 24.412 µs |
| p90 | 17.598 µs | 26.630 µs | 35.297 µs | 29.883 µs |
| p95 | 24.175 µs | 43.107 µs | 63.460 µs | 57.469 µs |
| p99 | 48.642 µs | 66.658 µs | 79.568 µs | 79.099 µs |
| Max | 68.192 µs | 94.519 µs | 93.909 µs | 115.653 µs |
| Tail | 2.71× avg (visible tails) | 2.55× avg (visible tails) | 2.74× avg (visible tails) | 2.78× avg (visible tails) |

