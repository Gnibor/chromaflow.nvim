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
| `cf.reload()` | 12.284 ms | 15.659 ms | 20.318 ms | 23.078 ms | Public reload path |
| `load_theme() [diagnostic + theme.load]` | 11.801 ms | 20.826 ms | 20.361 ms | 22.993 ms | Theme load plus diagnostic cycle |
| `theme.load()` | 11.901 ms | 22.635 ms | 20.627 ms | 23.242 ms | Compile + apply |
| `theme.compile()` | 6.417 ms | 14.472 ms | 11.728 ms | 13.446 ms | Compile only |
| `theme.apply(precompiled)` | 4.781 ms | 7.670 ms | 8.297 ms | 7.228 ms | Apply an already compiled theme |

### p99

| Operation | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| `cf.reload()` | 20.259 ms | 25.213 ms | 32.836 ms | 36.642 ms |
| `load_theme() [diagnostic + theme.load]` | 19.547 ms | 34.983 ms | 32.718 ms | 37.244 ms |
| `theme.load()` | 20.175 ms | 35.084 ms | 33.468 ms | 38.058 ms |
| `theme.compile()` | 14.160 ms | 36.560 ms | 23.819 ms | 25.894 ms |
| `theme.apply(precompiled)` | 10.861 ms | 15.985 ms | 19.768 ms | 15.794 ms |

### Average feature cost vs minimal

Positive values mean the feature scenario took longer than the minimal setup; negative values mean the measured average happened to be lower. Treat small deltas near normal run-to-run jitter as noise rather than a speedup.

| Operation | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: |
| `cf.reload()` | +3.375 ms (+27.5%) | +8.034 ms (+65.4%) | +10.794 ms (+87.9%) |
| `load_theme() [diagnostic + theme.load]` | +9.025 ms (+76.5%) | +8.560 ms (+72.5%) | +11.192 ms (+94.8%) |
| `theme.load()` | +10.734 ms (+90.2%) | +8.726 ms (+73.3%) | +11.341 ms (+95.3%) |
| `theme.compile()` | +8.056 ms (+125.5%) | +5.311 ms (+82.8%) | +7.030 ms (+109.6%) |
| `theme.apply(precompiled)` | +2.889 ms (+60.4%) | +3.516 ms (+73.5%) | +2.447 ms (+51.2%) |

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
| Avg | 0.000 µs | 0.000 µs | 0.001 µs | 0.000 µs |
| p50 | 0.000 µs | 0.000 µs | 0.000 µs | 0.000 µs |
| p90 | 0.000 µs | 0.000 µs | 0.001 µs | 0.000 µs |
| p95 | 0.000 µs | 0.000 µs | 0.001 µs | 0.000 µs |
| p99 | 0.002 µs | 0.002 µs | 0.002 µs | 0.002 µs |
| Max | 0.004 µs | 0.002 µs | 0.004 µs | 0.003 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | timer-floor dominated |

## User-facing end-to-end

The operations a user actually feels: reload, complete load, compile and apply. These are the first numbers to compare between machines or releases.

### cf.reload()

- Measures: Calls the public cf.reload() path on the selected theme.
- Represents: Closest single number to the cost a user pays for a normal ChromaFlow reload: diagnostic cycle, theme load/apply, watcher scope update when active, and cached LineBlend refresh.
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 8.786 ms | 10.852 ms | 14.836 ms | 17.081 ms |
| Avg | 12.284 ms | 15.659 ms | 20.318 ms | 23.078 ms |
| p50 | 10.464 ms | 13.314 ms | 17.660 ms | 19.972 ms |
| p90 | 19.215 ms | 23.717 ms | 30.652 ms | 34.380 ms |
| p95 | 19.660 ms | 24.628 ms | 31.656 ms | 35.036 ms |
| p99 | 20.259 ms | 25.213 ms | 32.836 ms | 36.642 ms |
| Max | 20.393 ms | 25.551 ms | 33.139 ms | 36.807 ms |
| Tail | 1.65× avg (tight) | 1.61× avg (tight) | 1.62× avg (tight) | 1.59× avg (tight) |

### load_theme() [diagnostic + theme.load]

- Measures: Calls the internal reload helper around theme.load(), including diagnostic clear/flush.
- Represents: Shows ChromaFlow's theme work before watcher/LineBlend post-work from cf.reload().
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 8.427 ms | 12.578 ms | 15.787 ms | 17.357 ms |
| Avg | 11.801 ms | 20.826 ms | 20.361 ms | 22.993 ms |
| p50 | 10.213 ms | 18.141 ms | 17.403 ms | 19.376 ms |
| p90 | 18.683 ms | 31.262 ms | 30.734 ms | 34.394 ms |
| p95 | 19.196 ms | 33.066 ms | 32.062 ms | 35.756 ms |
| p99 | 19.547 ms | 34.983 ms | 32.718 ms | 37.244 ms |
| Max | 19.925 ms | 36.166 ms | 34.727 ms | 40.328 ms |
| Tail | 1.66× avg (tight) | 1.68× avg (tight) | 1.61× avg (tight) | 1.62× avg (tight) |

### theme.load()

- Measures: Compiles the theme and immediately applies the compiled result.
- Represents: Core load cost without the public reload wrapper.
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 8.465 ms | 16.634 ms | 15.937 ms | 17.371 ms |
| Avg | 11.901 ms | 22.635 ms | 20.627 ms | 23.242 ms |
| p50 | 10.209 ms | 19.280 ms | 17.536 ms | 19.814 ms |
| p90 | 19.316 ms | 34.199 ms | 31.360 ms | 34.797 ms |
| p95 | 19.639 ms | 34.719 ms | 32.061 ms | 35.216 ms |
| p99 | 20.175 ms | 35.084 ms | 33.468 ms | 38.058 ms |
| Max | 20.360 ms | 35.438 ms | 34.229 ms | 38.194 ms |
| Tail | 1.70× avg (tight) | 1.55× avg (tight) | 1.62× avg (tight) | 1.64× avg (tight) |

### theme.compile()

- Measures: Discovers theme files, executes the DSL and produces the compiled theme object.
- Represents: Front half of a reload; no Neovim highlight application is included.
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 4.290 ms | 9.310 ms | 8.346 ms | 9.133 ms |
| Avg | 6.417 ms | 14.472 ms | 11.728 ms | 13.446 ms |
| p50 | 4.780 ms | 11.832 ms | 9.000 ms | 10.409 ms |
| p90 | 13.158 ms | 24.123 ms | 22.663 ms | 24.484 ms |
| p95 | 13.903 ms | 25.977 ms | 23.298 ms | 24.919 ms |
| p99 | 14.160 ms | 36.560 ms | 23.819 ms | 25.894 ms |
| Max | 14.209 ms | 39.839 ms | 24.200 ms | 26.930 ms |
| Tail | 2.21× avg (visible tails) | 2.53× avg (visible tails) | 2.03× avg (visible tails) | 1.93× avg (visible tails) |

### theme.apply(precompiled)

- Measures: Applies an already compiled theme object.
- Represents: Back half of a reload: highlight reset/apply, runtime bookkeeping, events and configured consumers.
- Profile: 100 samples × 1 call; warmup 10 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 3.642 ms | 5.654 ms | 6.010 ms | 4.907 ms |
| Avg | 4.781 ms | 7.670 ms | 8.297 ms | 7.228 ms |
| p50 | 4.218 ms | 7.172 ms | 7.703 ms | 6.716 ms |
| p90 | 5.742 ms | 8.677 ms | 9.514 ms | 8.657 ms |
| p95 | 9.692 ms | 12.619 ms | 13.349 ms | 11.944 ms |
| p99 | 10.861 ms | 15.985 ms | 19.768 ms | 15.794 ms |
| Max | 11.519 ms | 18.119 ms | 20.392 ms | 17.271 ms |
| Tail | 2.27× avg (visible tails) | 2.08× avg (visible tails) | 2.38× avg (visible tails) | 2.18× avg (visible tails) |

## Theme discovery and source loading

Filesystem discovery, reserved files, Lua chunk loading/execution and the initial compiler setup. This decomposes the front half of theme.compile().

### theme.selection()

- Measures: Reads and resolves the .cf-theme default/active selection.
- Represents: Theme-selection filesystem overhead.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 8.009 µs | 13.667 µs | 14.228 µs | 12.754 µs |
| Avg | 9.105 µs | 16.169 µs | 15.933 µs | 15.889 µs |
| p50 | 8.580 µs | 14.360 µs | 15.174 µs | 13.760 µs |
| p90 | 10.563 µs | 21.082 µs | 18.056 µs | 22.978 µs |
| p95 | 11.989 µs | 25.817 µs | 19.333 µs | 25.568 µs |
| p99 | 15.464 µs | 34.669 µs | 24.773 µs | 36.085 µs |
| Max | 19.342 µs | 40.725 µs | 26.841 µs | 36.895 µs |
| Tail | 1.70× avg (tight) | 2.14× avg (visible tails) | 1.55× avg (tight) | 2.27× avg (visible tails) |

### theme.available()

- Measures: Scans the theme root for valid selectable themes.
- Represents: Cost of populating the theme list/menu, not a per-highlight hot path.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 250.692 µs | 398.715 µs | 423.204 µs | 380.256 µs |
| Avg | 350.969 µs | 565.821 µs | 585.291 µs | 541.405 µs |
| p50 | 262.981 µs | 447.289 µs | 454.000 µs | 421.243 µs |
| p90 | 372.779 µs | 616.408 µs | 702.368 µs | 597.079 µs |
| p95 | 954.873 µs | 1.055 ms | 1.401 ms | 1.320 ms |
| p99 | 1.266 ms | 2.234 ms | 1.951 ms | 2.086 ms |
| Max | 1.609 ms | 2.318 ms | 2.265 ms | 2.188 ms |
| Tail | 3.61× avg (wide tails) | 3.95× avg (wide tails) | 3.33× avg (wide tails) | 3.85× avg (wide tails) |

### theme_names()

- Measures: Enumerates candidate theme directory names used by the compiler.
- Represents: Low-level directory-name discovery cost.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 3.859 µs | 5.537 µs | 5.913 µs | 5.285 µs |
| Avg | 4.320 µs | 6.133 µs | 8.825 µs | 5.827 µs |
| p50 | 3.994 µs | 5.697 µs | 9.229 µs | 5.420 µs |
| p90 | 4.723 µs | 6.401 µs | 11.437 µs | 6.198 µs |
| p95 | 6.045 µs | 7.283 µs | 12.066 µs | 6.864 µs |
| p99 | 11.128 µs | 17.948 µs | 16.448 µs | 15.475 µs |
| Max | 13.804 µs | 20.243 µs | 23.463 µs | 21.351 µs |
| Tail | 2.58× avg (visible tails) | 2.93× avg (visible tails) | 1.86× avg (visible tails) | 2.66× avg (visible tails) |

### list_cf(active) [32 files]

- Measures: Lists .cf modules in the active theme directory.
- Represents: Filesystem cost of discovering active theme modules.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 25.431 µs | 39.594 µs | 39.655 µs | 37.513 µs |
| Avg | 26.720 µs | 41.404 µs | 42.034 µs | 39.445 µs |
| p50 | 26.402 µs | 40.756 µs | 40.701 µs | 38.959 µs |
| p90 | 27.958 µs | 42.928 µs | 44.644 µs | 40.683 µs |
| p95 | 29.210 µs | 46.000 µs | 49.041 µs | 42.588 µs |
| p99 | 31.494 µs | 46.831 µs | 56.763 µs | 45.912 µs |
| Max | 31.580 µs | 47.443 µs | 73.030 µs | 46.255 µs |
| Tail | 1.18× avg (very tight) | 1.13× avg (very tight) | 1.35× avg (tight) | 1.16× avg (very tight) |
| Avg / file | 0.835 µs | 1.294 µs | 1.314 µs | 1.233 µs |

### valid_theme_dir(default)

- Measures: Validates a candidate theme directory.
- Represents: Selection/fallback validation cost.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 27.644 µs | 41.552 µs | 43.505 µs | 39.813 µs |
| Avg | 28.634 µs | 43.237 µs | 45.057 µs | 41.939 µs |
| p50 | 28.348 µs | 42.516 µs | 44.368 µs | 41.918 µs |
| p90 | 29.796 µs | 45.498 µs | 46.652 µs | 43.583 µs |
| p95 | 30.885 µs | 47.558 µs | 49.501 µs | 44.423 µs |
| p99 | 32.713 µs | 49.952 µs | 52.304 µs | 48.020 µs |
| Max | 33.083 µs | 55.047 µs | 52.515 µs | 48.644 µs |
| Tail | 1.14× avg (very tight) | 1.16× avg (very tight) | 1.16× avg (very tight) | 1.14× avg (very tight) |

### valid_theme_dir(active)

- Measures: Validates a candidate theme directory.
- Represents: Selection/fallback validation cost.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 27.908 µs | 41.275 µs | 43.458 µs | 39.323 µs |
| Avg | 29.873 µs | 43.513 µs | 45.068 µs | 41.286 µs |
| p50 | 28.571 µs | 42.755 µs | 44.375 µs | 40.798 µs |
| p90 | 29.831 µs | 45.226 µs | 46.834 µs | 42.309 µs |
| p95 | 31.856 µs | 47.947 µs | 49.192 µs | 43.247 µs |
| p99 | 34.056 µs | 51.259 µs | 52.059 µs | 47.332 µs |
| Max | 123.858 µs | 52.819 µs | 52.232 µs | 48.087 µs |
| Tail | 1.14× avg (very tight) | 1.18× avg (very tight) | 1.16× avg (very tight) | 1.15× avg (very tight) |

### resolve_reserved(color+config)

- Measures: Resolves color.cf and config.cf across active/default fallback rules.
- Represents: Reserved-file lookup cost for one compile.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 8.046 µs | 11.852 µs | 12.425 µs | 11.650 µs |
| Avg | 8.951 µs | 12.669 µs | 13.065 µs | 12.560 µs |
| p50 | 8.326 µs | 12.272 µs | 12.760 µs | 12.210 µs |
| p90 | 10.282 µs | 13.591 µs | 13.689 µs | 13.306 µs |
| p95 | 11.560 µs | 15.269 µs | 14.145 µs | 14.748 µs |
| p99 | 16.496 µs | 17.987 µs | 18.079 µs | 17.224 µs |
| Max | 25.114 µs | 18.558 µs | 19.377 µs | 18.475 µs |
| Tail | 1.84× avg (visible tails) | 1.42× avg (tight) | 1.38× avg (tight) | 1.37× avg (tight) |

### module_files(active+fallback) [32 files]

- Measures: Builds active/default module file lists with fallback scope metadata.
- Represents: Module-discovery cost before source execution.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 51.092 µs | 73.627 µs | 72.865 µs | 69.941 µs |
| Avg | 66.348 µs | 76.725 µs | 77.468 µs | 72.924 µs |
| p50 | 53.405 µs | 76.003 µs | 76.131 µs | 72.434 µs |
| p90 | 76.473 µs | 80.541 µs | 81.735 µs | 75.731 µs |
| p95 | 107.925 µs | 82.239 µs | 82.914 µs | 76.988 µs |
| p99 | 263.355 µs | 85.021 µs | 90.888 µs | 82.051 µs |
| Max | 271.826 µs | 85.076 µs | 93.554 µs | 84.806 µs |
| Tail | 3.97× avg (wide tails) | 1.11× avg (very tight) | 1.17× avg (very tight) | 1.13× avg (very tight) |
| Avg / file | 2.073 µs | 2.398 µs | 2.421 µs | 2.279 µs |

### loadfile(color+config)

- Measures: Compiles reserved color/config Lua chunks with loadfile(), without executing them.
- Represents: Lua parser/loader cost for reserved files.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 14.778 µs | 22.409 µs | 22.207 µs | 21.438 µs |
| Avg | 15.407 µs | 23.301 µs | 23.373 µs | 22.479 µs |
| p50 | 15.233 µs | 22.988 µs | 23.001 µs | 22.112 µs |
| p90 | 15.836 µs | 23.964 µs | 24.430 µs | 23.786 µs |
| p95 | 16.103 µs | 24.526 µs | 25.221 µs | 24.329 µs |
| p99 | 16.430 µs | 29.274 µs | 28.593 µs | 27.029 µs |
| Max | 26.988 µs | 29.534 µs | 28.944 µs | 28.354 µs |
| Tail | 1.07× avg (very tight) | 1.26× avg (tight) | 1.22× avg (very tight) | 1.20× avg (very tight) |

### execute(color+config)

- Measures: Loads and executes color.cf/config.cf through ChromaFlow's source wrapper.
- Represents: Reserved source execution plus ChromaFlow source bookkeeping.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 20.344 µs | 42.194 µs | 56.509 µs | 52.954 µs |
| Avg | 21.555 µs | 44.184 µs | 60.837 µs | 57.592 µs |
| p50 | 21.416 µs | 43.719 µs | 59.909 µs | 57.173 µs |
| p90 | 22.308 µs | 46.021 µs | 63.464 µs | 60.442 µs |
| p95 | 23.075 µs | 48.290 µs | 67.725 µs | 63.065 µs |
| p99 | 24.092 µs | 51.667 µs | 75.709 µs | 66.098 µs |
| Max | 25.672 µs | 51.897 µs | 93.022 µs | 66.782 µs |
| Tail | 1.12× avg (very tight) | 1.17× avg (very tight) | 1.24× avg (very tight) | 1.15× avg (very tight) |

### loadfile(all modules) [32 files]

- Measures: Runs loadfile() for every active/fallback theme module.
- Represents: Lua parse/load cost for the complete module set, excluding module execution.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.067 ms | 1.601 ms | 1.606 ms | 1.606 ms |
| Avg | 1.362 ms | 1.987 ms | 1.984 ms | 1.953 ms |
| p50 | 1.152 ms | 1.655 ms | 1.695 ms | 1.657 ms |
| p90 | 1.470 ms | 2.217 ms | 2.228 ms | 2.134 ms |
| p95 | 2.431 ms | 2.764 ms | 2.631 ms | 2.252 ms |
| p99 | 4.318 ms | 5.698 ms | 6.777 ms | 6.237 ms |
| Max | 4.752 ms | 7.927 ms | 7.089 ms | 7.254 ms |
| Tail | 3.17× avg (wide tails) | 2.87× avg (visible tails) | 3.42× avg (wide tails) | 3.19× avg (wide tails) |
| Avg / file | 42.570 µs | 62.091 µs | 62.007 µs | 61.040 µs |

### execute preloaded module chunks [32 files]

- Measures: Executes already-loaded real module chunks through active/fallback compiler phases.
- Represents: DSL execution cost with filesystem parsing removed.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 2.746 ms | 5.783 ms | 5.032 ms | 6.372 ms |
| Avg | 4.611 ms | 9.027 ms | 7.816 ms | 9.694 ms |
| p50 | 3.485 ms | 6.638 ms | 6.025 ms | 7.130 ms |
| p90 | 8.427 ms | 17.940 ms | 13.703 ms | 18.619 ms |
| p95 | 8.744 ms | 18.333 ms | 14.354 ms | 19.580 ms |
| p99 | 9.254 ms | 19.481 ms | 14.781 ms | 20.090 ms |
| Max | 9.870 ms | 19.951 ms | 14.783 ms | 20.431 ms |
| Tail | 2.01× avg (visible tails) | 2.16× avg (visible tails) | 1.89× avg (visible tails) | 2.07× avg (visible tails) |
| Avg / file | 144.102 µs | 282.100 µs | 244.265 µs | 302.949 µs |

### hl._begin(colors, config)

- Measures: Initializes the highlight compiler with the already loaded colours and theme config.
- Represents: Fixed compiler setup cost per compile.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.286 µs | 0.867 µs | 0.480 µs | 0.833 µs |
| Avg | 0.518 µs | 1.126 µs | 0.766 µs | 1.105 µs |
| p50 | 0.324 µs | 0.917 µs | 0.551 µs | 0.892 µs |
| p90 | 0.396 µs | 1.007 µs | 0.631 µs | 0.962 µs |
| p95 | 1.974 µs | 1.498 µs | 1.938 µs | 1.182 µs |
| p99 | 3.857 µs | 4.923 µs | 5.125 µs | 5.025 µs |
| Max | 5.335 µs | 7.687 µs | 6.813 µs | 12.039 µs |
| Tail | 7.45× avg (wide tails) | 4.37× avg (wide tails) | 6.69× avg (wide tails) | 4.55× avg (wide tails) |

## DSL compiler

Replays captured real declarations from the selected theme through the actual internal compiler functions. Aggregate probes report a per-item cost where possible.

### setup() replay all [32 calls]

- Measures: Replays every captured language/plugin/ui setup call from the real theme.
- Represents: Aggregate public DSL setup/compiler cost for this exact theme.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 2.085 ms | 4.533 ms | 3.909 ms | 4.961 ms |
| Avg | 3.118 ms | 6.731 ms | 5.419 ms | 7.282 ms |
| p50 | 2.403 ms | 5.417 ms | 4.262 ms | 5.723 ms |
| p90 | 6.290 ms | 13.785 ms | 9.819 ms | 14.376 ms |
| p95 | 7.657 ms | 15.415 ms | 11.888 ms | 15.823 ms |
| p99 | 8.117 ms | 15.928 ms | 12.364 ms | 17.008 ms |
| Max | 8.668 ms | 16.302 ms | 12.531 ms | 18.836 ms |
| Tail | 2.60× avg (visible tails) | 2.37× avg (visible tails) | 2.28× avg (visible tails) | 2.34× avg (visible tails) |
| Avg / call | 97.441 µs | 210.354 µs | 169.353 µs | 227.569 µs |

### compile_language_module all [15 calls]

- Measures: Calls the internal language-module compiler for every captured language declaration.
- Represents: Language-specific DSL compile contribution.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.165 ms | 2.379 ms | 2.199 ms | 2.500 ms |
| Avg | 1.651 ms | 3.432 ms | 2.935 ms | 3.637 ms |
| p50 | 1.234 ms | 2.554 ms | 2.312 ms | 2.820 ms |
| p90 | 1.886 ms | 3.906 ms | 3.116 ms | 4.052 ms |
| p95 | 5.207 ms | 10.051 ms | 8.681 ms | 9.035 ms |
| p99 | 5.636 ms | 12.089 ms | 9.124 ms | 13.168 ms |
| Max | 6.364 ms | 12.783 ms | 9.193 ms | 13.917 ms |
| Tail | 3.41× avg (wide tails) | 3.52× avg (wide tails) | 3.11× avg (wide tails) | 3.62× avg (wide tails) |
| Avg / call | 110.097 µs | 228.803 µs | 195.662 µs | 242.437 µs |

### compile_resolved_module all [17 calls]

- Measures: Calls the plugin/ui resolved-module compiler for every captured declaration.
- Represents: Plugin/UI DSL compile contribution.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 666.861 µs | 1.427 ms | 1.341 ms | 1.535 ms |
| Avg | 1.111 ms | 2.127 ms | 1.927 ms | 2.282 ms |
| p50 | 746.700 µs | 1.525 ms | 1.446 ms | 1.656 ms |
| p90 | 1.351 ms | 2.366 ms | 2.223 ms | 2.432 ms |
| p95 | 3.766 ms | 5.895 ms | 5.281 ms | 5.861 ms |
| p99 | 5.489 ms | 9.618 ms | 7.650 ms | 9.854 ms |
| Max | 5.993 ms | 10.509 ms | 8.074 ms | 10.908 ms |
| Tail | 4.94× avg (wide tails) | 4.52× avg (wide tails) | 3.97× avg (wide tails) | 4.32× avg (wide tails) |
| Avg / call | 65.352 µs | 125.139 µs | 113.328 µs | 134.238 µs |

### module_declarations all [32 calls]

- Measures: Extracts declaration tables from every module spec.
- Represents: Cost of turning user DSL tables into compiler declaration streams.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 18.813 µs | 34.095 µs | 34.680 µs | 33.163 µs |
| Avg | 19.576 µs | 35.781 µs | 36.125 µs | 35.062 µs |
| p50 | 19.238 µs | 35.210 µs | 35.741 µs | 34.599 µs |
| p90 | 20.230 µs | 37.021 µs | 37.790 µs | 36.803 µs |
| p95 | 22.589 µs | 37.809 µs | 39.160 µs | 37.626 µs |
| p99 | 24.553 µs | 42.582 µs | 40.272 µs | 42.481 µs |
| Max | 24.648 µs | 44.385 µs | 41.291 µs | 44.407 µs |
| Tail | 1.25× avg (tight) | 1.19× avg (very tight) | 1.11× avg (very tight) | 1.21× avg (very tight) |
| Avg / call | 0.612 µs | 1.118 µs | 1.129 µs | 1.096 µs |

### compile_module_mods all [32 calls]

- Measures: Replays per-module modifier compilation.
- Represents: Modifier declaration overhead across the selected theme.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 6.846 µs | 14.932 µs | 15.044 µs | 15.488 µs |
| Avg | 7.678 µs | 16.018 µs | 16.803 µs | 17.394 µs |
| p50 | 7.465 µs | 15.576 µs | 15.518 µs | 16.076 µs |
| p90 | 8.450 µs | 16.947 µs | 19.103 µs | 19.527 µs |
| p95 | 9.863 µs | 19.658 µs | 21.733 µs | 21.184 µs |
| p99 | 11.089 µs | 21.662 µs | 36.081 µs | 38.064 µs |
| Max | 11.092 µs | 25.696 µs | 43.564 µs | 42.957 µs |
| Tail | 1.44× avg (tight) | 1.35× avg (tight) | 2.15× avg (visible tails) | 2.19× avg (visible tails) |
| Avg / call | 0.240 µs | 0.501 µs | 0.525 µs | 0.544 µs |

### compile_resolved_group all [520 calls]

- Measures: Replays every captured resolved highlight group compiler call.
- Represents: One of the main inner DSL compilation loops; per-item cost is useful here.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.682 ms | 3.476 ms | 3.182 ms | 3.799 ms |
| Avg | 2.620 ms | 5.147 ms | 4.558 ms | 5.618 ms |
| p50 | 1.946 ms | 3.911 ms | 3.649 ms | 4.370 ms |
| p90 | 4.809 ms | 8.080 ms | 6.682 ms | 9.686 ms |
| p95 | 6.031 ms | 11.696 ms | 10.760 ms | 15.506 ms |
| p99 | 7.426 ms | 11.835 ms | 11.813 ms | 16.141 ms |
| Max | 7.590 ms | 12.385 ms | 11.889 ms | 16.307 ms |
| Tail | 2.83× avg (visible tails) | 2.30× avg (visible tails) | 2.59× avg (visible tails) | 2.87× avg (visible tails) |
| Avg / call | 5.038 µs | 9.898 µs | 8.766 µs | 10.803 µs |

### build_style all [702 calls]

- Measures: Builds every captured style object from the real theme.
- Represents: Style normalization/pipeline/cache lookup contribution during DSL compilation.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 674.148 µs | 1.801 ms | 1.292 ms | 1.727 ms |
| Avg | 1.025 ms | 2.651 ms | 1.779 ms | 2.605 ms |
| p50 | 787.289 µs | 1.981 ms | 1.479 ms | 1.906 ms |
| p90 | 1.368 ms | 3.350 ms | 2.457 ms | 4.115 ms |
| p95 | 2.281 ms | 7.155 ms | 3.672 ms | 7.510 ms |
| p99 | 4.037 ms | 9.377 ms | 5.675 ms | 9.544 ms |
| Max | 4.263 ms | 9.838 ms | 5.729 ms | 9.777 ms |
| Tail | 3.94× avg (wide tails) | 3.54× avg (wide tails) | 3.19× avg (wide tails) | 3.66× avg (wide tails) |
| Avg / call | 1.460 µs | 3.776 µs | 2.534 µs | 3.711 µs |

### intern_style all [702 calls]

- Measures: Interns every captured normalized style into the session style cache.
- Represents: Style deduplication/cache contribution.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 430.715 µs | 894.337 µs | 873.080 µs | 825.266 µs |
| Avg | 580.242 µs | 1.042 ms | 1.095 ms | 995.218 µs |
| p50 | 463.591 µs | 913.035 µs | 903.331 µs | 866.986 µs |
| p90 | 649.210 µs | 1.125 ms | 1.173 ms | 1.073 ms |
| p95 | 1.280 ms | 1.481 ms | 2.548 ms | 1.204 ms |
| p99 | 2.344 ms | 2.988 ms | 3.309 ms | 3.171 ms |
| Max | 2.576 ms | 3.273 ms | 3.643 ms | 3.527 ms |
| Tail | 4.04× avg (wide tails) | 2.87× avg (visible tails) | 3.02× avg (wide tails) | 3.19× avg (wide tails) |
| Avg / call | 0.827 µs | 1.485 µs | 1.560 µs | 1.418 µs |

### bind_action_owner all [32 modules]

- Measures: Binds compiled actions to their language/plugin/ui owners.
- Represents: Runtime/picker ownership metadata cost per compiled module.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 18.325 µs | 24.429 µs | 26.237 µs | 26.929 µs |
| Avg | 18.793 µs | 26.387 µs | 26.892 µs | 27.764 µs |
| p50 | 18.432 µs | 24.829 µs | 26.501 µs | 27.310 µs |
| p90 | 19.414 µs | 31.580 µs | 27.505 µs | 28.509 µs |
| p95 | 20.873 µs | 34.571 µs | 29.137 µs | 31.067 µs |
| p99 | 21.800 µs | 42.081 µs | 31.882 µs | 32.632 µs |
| Max | 23.044 µs | 43.854 µs | 32.237 µs | 33.822 µs |
| Tail | 1.16× avg (very tight) | 1.59× avg (tight) | 1.19× avg (very tight) | 1.18× avg (very tight) |
| Avg / module | 0.587 µs | 0.825 µs | 0.840 µs | 0.868 µs |

## Highlight resolver

Hot cached resolver shapes plus one deliberately cold cache-rebuild path. The variants show the cost of type, modifier, TypeMod, filetype, literal and target filtering.

### cold type after clear

- Measures: Clears resolver caches and resolves a type on every measured call.
- Represents: Deliberately cold resolver rebuild cost; compare with the hot resolver variants below.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 3.056 µs | 4.406 µs | 4.919 µs | 4.711 µs |
| Avg | 3.401 µs | 4.499 µs | 5.051 µs | 4.835 µs |
| p50 | 3.434 µs | 4.472 µs | 4.990 µs | 4.785 µs |
| p90 | 3.559 µs | 4.592 µs | 5.115 µs | 4.892 µs |
| p95 | 3.630 µs | 4.679 µs | 5.170 µs | 4.985 µs |
| p99 | 3.724 µs | 4.935 µs | 5.420 µs | 5.141 µs |
| Max | 3.958 µs | 5.018 µs | 8.568 µs | 7.805 µs |
| Tail | 1.10× avg (very tight) | 1.10× avg (very tight) | 1.07× avg (very tight) | 1.06× avg (very tight) |

### type only

- Measures: Resolves a normal semantic type using a cached style object.
- Represents: Baseline hot type resolver path.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.826 µs | 1.179 µs | 1.252 µs | 1.227 µs |
| Avg | 1.048 µs | 1.436 µs | 1.517 µs | 1.505 µs |
| p50 | 0.916 µs | 1.232 µs | 1.295 µs | 1.290 µs |
| p90 | 1.121 µs | 1.533 µs | 1.646 µs | 1.575 µs |
| p95 | 1.886 µs | 2.045 µs | 3.401 µs | 2.784 µs |
| p99 | 3.059 µs | 4.548 µs | 3.957 µs | 4.765 µs |
| Max | 3.361 µs | 4.848 µs | 4.284 µs | 4.946 µs |
| Tail | 2.92× avg (visible tails) | 3.17× avg (wide tails) | 2.61× avg (visible tails) | 3.17× avg (wide tails) |

### modifier only

- Measures: Resolves a modifier without an owning type.
- Represents: Hot free-modifier path.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.465 µs | 0.653 µs | 0.724 µs | 0.691 µs |
| Avg | 0.568 µs | 0.778 µs | 0.817 µs | 0.825 µs |
| p50 | 0.526 µs | 0.680 µs | 0.743 µs | 0.724 µs |
| p90 | 0.599 µs | 0.815 µs | 0.883 µs | 0.875 µs |
| p95 | 0.856 µs | 1.156 µs | 1.013 µs | 1.270 µs |
| p99 | 1.459 µs | 2.026 µs | 2.009 µs | 2.328 µs |
| Max | 1.754 µs | 2.533 µs | 2.221 µs | 2.560 µs |
| Tail | 2.57× avg (visible tails) | 2.60× avg (visible tails) | 2.46× avg (visible tails) | 2.82× avg (visible tails) |

### type + modifier

- Measures: Resolves one type+modifier combination using a cached style object.
- Represents: Common hot semantic-token TypeMod path.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.941 µs | 1.347 µs | 1.391 µs | 1.392 µs |
| Avg | 1.172 µs | 1.665 µs | 1.669 µs | 1.661 µs |
| p50 | 1.054 µs | 1.479 µs | 1.443 µs | 1.457 µs |
| p90 | 1.225 µs | 1.773 µs | 1.846 µs | 1.721 µs |
| p95 | 1.831 µs | 2.549 µs | 3.493 µs | 2.633 µs |
| p99 | 3.346 µs | 5.149 µs | 4.532 µs | 4.334 µs |
| Max | 3.693 µs | 5.651 µs | 4.566 µs | 5.521 µs |
| Tail | 2.86× avg (visible tails) | 3.09× avg (wide tails) | 2.72× avg (visible tails) | 2.61× avg (visible tails) |

### type + 2 modifiers

- Measures: Resolves one type with two modifiers using a cached style object.
- Represents: Hot multi-modifier resolver cost.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.792 µs | 2.822 µs | 2.798 µs | 2.751 µs |
| Avg | 2.292 µs | 3.381 µs | 3.413 µs | 3.359 µs |
| p50 | 2.047 µs | 2.986 µs | 2.962 µs | 2.958 µs |
| p90 | 2.958 µs | 3.544 µs | 3.788 µs | 3.593 µs |
| p95 | 4.070 µs | 5.288 µs | 5.906 µs | 5.380 µs |
| p99 | 5.558 µs | 9.038 µs | 7.935 µs | 9.070 µs |
| Max | 5.987 µs | 9.228 µs | 8.345 µs | 9.087 µs |
| Tail | 2.42× avg (visible tails) | 2.67× avg (visible tails) | 2.33× avg (visible tails) | 2.70× avg (visible tails) |

### type + filetype

- Measures: Resolves a type with filetype-specific semantic context.
- Represents: Hot filetype-qualified resolver path.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.251 µs | 1.879 µs | 1.972 µs | 1.870 µs |
| Avg | 1.627 µs | 2.292 µs | 2.444 µs | 2.284 µs |
| p50 | 1.442 µs | 2.016 µs | 2.056 µs | 1.961 µs |
| p90 | 1.697 µs | 2.406 µs | 2.678 µs | 2.455 µs |
| p95 | 3.291 µs | 4.887 µs | 4.363 µs | 3.462 µs |
| p99 | 4.319 µs | 6.393 µs | 6.399 µs | 6.993 µs |
| Max | 4.347 µs | 6.432 µs | 6.487 µs | 7.180 µs |
| Tail | 2.66× avg (visible tails) | 2.79× avg (visible tails) | 2.62× avg (visible tails) | 3.06× avg (wide tails) |

### explicit TypeMod

- Measures: Resolves a style owned by one explicit type+modifier combination.
- Represents: Hot TypeMod-style path, distinct from a free modifier.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.877 µs | 1.329 µs | 1.446 µs | 1.464 µs |
| Avg | 1.121 µs | 1.579 µs | 1.728 µs | 1.762 µs |
| p50 | 1.015 µs | 1.385 µs | 1.501 µs | 1.553 µs |
| p90 | 1.208 µs | 1.682 µs | 1.942 µs | 1.921 µs |
| p95 | 1.779 µs | 2.300 µs | 3.239 µs | 2.724 µs |
| p99 | 2.993 µs | 4.512 µs | 4.558 µs | 4.907 µs |
| Max | 3.101 µs | 4.573 µs | 4.628 µs | 5.328 µs |
| Tail | 2.67× avg (visible tails) | 2.86× avg (visible tails) | 2.64× avg (visible tails) | 2.79× avg (visible tails) |

### literal

- Measures: Resolves an unknown/literal highlight name instead of a normal semantic type.
- Represents: Literal escape-path cost for names outside the standard semantic chain.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.455 µs | 2.095 µs | 2.139 µs | 2.184 µs |
| Avg | 1.848 µs | 2.478 µs | 2.592 µs | 2.670 µs |
| p50 | 1.648 µs | 2.190 µs | 2.209 µs | 2.357 µs |
| p90 | 1.965 µs | 2.566 µs | 3.072 µs | 2.926 µs |
| p95 | 3.554 µs | 4.379 µs | 4.675 µs | 4.096 µs |
| p99 | 5.001 µs | 6.681 µs | 6.222 µs | 6.825 µs |
| Max | 5.053 µs | 7.410 µs | 6.321 µs | 7.195 µs |
| Tail | 2.71× avg (visible tails) | 2.70× avg (visible tails) | 2.40× avg (visible tails) | 2.56× avg (visible tails) |

### target=vim

- Measures: Resolves a type while materializing only one target mask.
- Represents: Fast target-filtered resolver path after session caches are warm.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.069 µs | 0.068 µs | 0.105 µs | 0.098 µs |
| Avg | 0.071 µs | 0.070 µs | 0.108 µs | 0.100 µs |
| p50 | 0.071 µs | 0.069 µs | 0.107 µs | 0.099 µs |
| p90 | 0.071 µs | 0.071 µs | 0.109 µs | 0.102 µs |
| p95 | 0.073 µs | 0.073 µs | 0.110 µs | 0.107 µs |
| p99 | 0.082 µs | 0.092 µs | 0.134 µs | 0.114 µs |
| Max | 0.082 µs | 0.096 µs | 0.136 µs | 0.135 µs |
| Tail | 1.15× avg (very tight) | 1.31× avg (tight) | 1.24× avg (very tight) | 1.15× avg (very tight) |

### target=ts

- Measures: Resolves a type while materializing only one target mask.
- Represents: Fast target-filtered resolver path after session caches are warm.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.070 µs | 0.071 µs | 0.113 µs | 0.105 µs |
| Avg | 0.073 µs | 0.073 µs | 0.116 µs | 0.109 µs |
| p50 | 0.072 µs | 0.072 µs | 0.115 µs | 0.108 µs |
| p90 | 0.074 µs | 0.072 µs | 0.118 µs | 0.110 µs |
| p95 | 0.077 µs | 0.075 µs | 0.119 µs | 0.111 µs |
| p99 | 0.085 µs | 0.089 µs | 0.143 µs | 0.135 µs |
| Max | 0.097 µs | 0.097 µs | 0.145 µs | 0.145 µs |
| Tail | 1.17× avg (very tight) | 1.22× avg (very tight) | 1.23× avg (very tight) | 1.24× avg (very tight) |

### target=lsp

- Measures: Resolves a type while materializing only one target mask.
- Represents: Fast target-filtered resolver path after session caches are warm.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.071 µs | 0.074 µs | 0.120 µs | 0.112 µs |
| Avg | 0.074 µs | 0.077 µs | 0.124 µs | 0.115 µs |
| p50 | 0.073 µs | 0.075 µs | 0.123 µs | 0.114 µs |
| p90 | 0.075 µs | 0.078 µs | 0.126 µs | 0.115 µs |
| p95 | 0.076 µs | 0.082 µs | 0.128 µs | 0.116 µs |
| p99 | 0.085 µs | 0.101 µs | 0.151 µs | 0.140 µs |
| Max | 0.107 µs | 0.112 µs | 0.164 µs | 0.156 µs |
| Tail | 1.15× avg (very tight) | 1.32× avg (tight) | 1.21× avg (very tight) | 1.22× avg (very tight) |

### resolver.clear_cache()

- Measures: Drops resolver session lookup caches.
- Represents: Invalidation cost paid only when the resolver cache must be rebuilt.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 2.183 µs | 3.525 µs | 3.897 µs | 3.897 µs |
| Avg | 2.384 µs | 3.655 µs | 4.104 µs | 3.959 µs |
| p50 | 2.364 µs | 3.665 µs | 4.078 µs | 3.924 µs |
| p90 | 2.496 µs | 3.703 µs | 4.248 µs | 4.075 µs |
| p95 | 2.646 µs | 3.713 µs | 4.261 µs | 4.083 µs |
| p99 | 2.783 µs | 3.727 µs | 4.365 µs | 4.129 µs |
| Max | 2.897 µs | 3.737 µs | 4.373 µs | 4.197 µs |
| Tail | 1.17× avg (very tight) | 1.02× avg (very tight) | 1.06× avg (very tight) | 1.04× avg (very tight) |

## Colour engine and pipeline

Packed-RGBA conversion/manipulation and prebuilt pipeline execution. Pure operations use large batches because they are near the timer floor.

### dynamic input baseline

- Measures: Mutates the packed colour input with one BitOp xor and stores it for the next call.
- Represents: Control cost used to keep pure colour probes data-dependent so LuaJIT cannot constant-fold the operation away.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.030 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| Avg | 0.032 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p50 | 0.031 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p90 | 0.036 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p95 | 0.036 µs | 0.001 µs | 0.001 µs | 0.001 µs |
| p99 | 0.039 µs | 0.003 µs | 0.003 µs | 0.004 µs |
| Max | 0.045 µs | 0.010 µs | 0.003 µs | 0.007 µs |
| Tail | 1.20× avg (very tight) | timer-floor dominated | timer-floor dominated | timer-floor dominated |

### string input baseline

- Measures: Alternates between two existing hex-string references.
- Represents: Control cost for the dynamic from_hex() probe; not subtracted automatically.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.029 µs | 0.004 µs | 0.003 µs | 0.004 µs |
| Avg | 0.032 µs | 0.004 µs | 0.004 µs | 0.004 µs |
| p50 | 0.032 µs | 0.004 µs | 0.003 µs | 0.004 µs |
| p90 | 0.034 µs | 0.004 µs | 0.003 µs | 0.004 µs |
| p95 | 0.034 µs | 0.004 µs | 0.004 µs | 0.004 µs |
| p99 | 0.035 µs | 0.006 µs | 0.005 µs | 0.006 µs |
| Max | 0.037 µs | 0.010 µs | 0.006 µs | 0.010 µs |
| Tail | 1.08× avg (very tight) | timer-floor dominated | timer-floor dominated | timer-floor dominated |

### from_hex(dynamic)

- Measures: Parses #RRGGBB into ChromaFlow's packed 0xAARRGGBB representation.
- Represents: Colour-string boundary conversion.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.042 µs | 0.034 µs | 0.054 µs | 0.050 µs |
| Avg | 0.045 µs | 0.035 µs | 0.058 µs | 0.052 µs |
| p50 | 0.045 µs | 0.034 µs | 0.057 µs | 0.052 µs |
| p90 | 0.048 µs | 0.035 µs | 0.059 µs | 0.053 µs |
| p95 | 0.049 µs | 0.036 µs | 0.060 µs | 0.053 µs |
| p99 | 0.051 µs | 0.043 µs | 0.063 µs | 0.057 µs |
| Max | 0.058 µs | 0.056 µs | 0.078 µs | 0.070 µs |
| Tail | 1.13× avg (very tight) | 1.23× avg (very tight) | 1.09× avg (very tight) | 1.10× avg (very tight) |

### to_rgb_hex(dynamic packed)

- Measures: Formats packed RGBA as #RRGGBB.
- Represents: Final GUI highlight colour rendering cost.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.076 µs | 0.068 µs | 0.063 µs | 0.065 µs |
| Avg | 0.081 µs | 0.070 µs | 0.067 µs | 0.066 µs |
| p50 | 0.081 µs | 0.070 µs | 0.067 µs | 0.066 µs |
| p90 | 0.083 µs | 0.071 µs | 0.068 µs | 0.067 µs |
| p95 | 0.085 µs | 0.071 µs | 0.068 µs | 0.068 µs |
| p99 | 0.086 µs | 0.075 µs | 0.070 µs | 0.070 µs |
| Max | 0.087 µs | 0.077 µs | 0.070 µs | 0.074 µs |
| Tail | 1.06× avg (very tight) | 1.06× avg (very tight) | 1.06× avg (very tight) | 1.06× avg (very tight) |

### to_cterm(dynamic packed)

- Measures: Quantizes packed RGB to the nearest xterm-256 palette entry.
- Represents: Terminal colour quantization cost.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.041 µs | 0.012 µs | 0.011 µs | 0.011 µs |
| Avg | 0.045 µs | 0.012 µs | 0.011 µs | 0.012 µs |
| p50 | 0.045 µs | 0.012 µs | 0.011 µs | 0.012 µs |
| p90 | 0.046 µs | 0.012 µs | 0.012 µs | 0.012 µs |
| p95 | 0.046 µs | 0.013 µs | 0.012 µs | 0.012 µs |
| p99 | 0.048 µs | 0.015 µs | 0.014 µs | 0.014 µs |
| Max | 0.052 µs | 0.022 µs | 0.020 µs | 0.025 µs |
| Tail | 1.06× avg (very tight) | 1.21× avg (very tight) | 1.22× avg (very tight) | 1.19× avg (very tight) |

### from_cterm(67/188)

- Measures: Decodes an xterm-256 palette index to packed RGBA.
- Represents: Terminal pipeline input conversion.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.036 µs | 0.062 µs | 0.102 µs | 0.093 µs |
| Avg | 0.039 µs | 0.064 µs | 0.104 µs | 0.097 µs |
| p50 | 0.039 µs | 0.063 µs | 0.104 µs | 0.096 µs |
| p90 | 0.041 µs | 0.064 µs | 0.105 µs | 0.100 µs |
| p95 | 0.041 µs | 0.064 µs | 0.106 µs | 0.101 µs |
| p99 | 0.042 µs | 0.065 µs | 0.109 µs | 0.102 µs |
| Max | 0.050 µs | 0.092 µs | 0.128 µs | 0.123 µs |
| Tail | 1.07× avg (very tight) | 1.03× avg (very tight) | 1.04× avg (very tight) | 1.05× avg (very tight) |

### mix(35)

- Measures: Mixes two packed colours using the numeric RGB/RGBA path.
- Represents: One mix pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.040 µs | 0.064 µs | 0.101 µs | 0.095 µs |
| Avg | 0.043 µs | 0.067 µs | 0.103 µs | 0.098 µs |
| p50 | 0.043 µs | 0.067 µs | 0.102 µs | 0.097 µs |
| p90 | 0.044 µs | 0.067 µs | 0.103 µs | 0.099 µs |
| p95 | 0.044 µs | 0.068 µs | 0.104 µs | 0.099 µs |
| p99 | 0.045 µs | 0.069 µs | 0.106 µs | 0.101 µs |
| Max | 0.059 µs | 0.099 µs | 0.119 µs | 0.117 µs |
| Tail | 1.06× avg (very tight) | 1.04× avg (very tight) | 1.03× avg (very tight) | 1.04× avg (very tight) |

### opacity(85)

- Measures: Computes effective alpha and pre-composited RGB against a background.
- Represents: One opacity pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.045 µs | 0.073 µs | 0.119 µs | 0.103 µs |
| Avg | 0.049 µs | 0.074 µs | 0.120 µs | 0.106 µs |
| p50 | 0.048 µs | 0.073 µs | 0.120 µs | 0.105 µs |
| p90 | 0.050 µs | 0.074 µs | 0.121 µs | 0.106 µs |
| p95 | 0.051 µs | 0.075 µs | 0.122 µs | 0.107 µs |
| p99 | 0.051 µs | 0.076 µs | 0.124 µs | 0.108 µs |
| Max | 0.063 µs | 0.097 µs | 0.140 µs | 0.182 µs |
| Tail | 1.06× avg (very tight) | 1.04× avg (very tight) | 1.04× avg (very tight) | 1.02× avg (very tight) |

### brightness(+20)

- Measures: Applies signed brightness to packed RGB channels.
- Represents: One brightness pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.040 µs | 0.065 µs | 0.104 µs | 0.094 µs |
| Avg | 0.042 µs | 0.065 µs | 0.106 µs | 0.097 µs |
| p50 | 0.042 µs | 0.065 µs | 0.106 µs | 0.096 µs |
| p90 | 0.044 µs | 0.066 µs | 0.107 µs | 0.099 µs |
| p95 | 0.044 µs | 0.066 µs | 0.107 µs | 0.099 µs |
| p99 | 0.046 µs | 0.068 µs | 0.108 µs | 0.119 µs |
| Max | 0.056 µs | 0.094 µs | 0.118 µs | 0.124 µs |
| Tail | 1.07× avg (very tight) | 1.03× avg (very tight) | 1.02× avg (very tight) | 1.23× avg (very tight) |

### lighten(20)

- Measures: Applies the one-direction brightness convenience primitive.
- Represents: One lighten/darken pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.040 µs | 0.063 µs | 0.096 µs | 0.095 µs |
| Avg | 0.043 µs | 0.064 µs | 0.099 µs | 0.100 µs |
| p50 | 0.043 µs | 0.064 µs | 0.098 µs | 0.099 µs |
| p90 | 0.044 µs | 0.064 µs | 0.102 µs | 0.101 µs |
| p95 | 0.044 µs | 0.065 µs | 0.102 µs | 0.102 µs |
| p99 | 0.045 µs | 0.066 µs | 0.104 µs | 0.112 µs |
| Max | 0.063 µs | 0.091 µs | 0.116 µs | 0.118 µs |
| Tail | 1.05× avg (very tight) | 1.03× avg (very tight) | 1.05× avg (very tight) | 1.12× avg (very tight) |

### darken(20)

- Measures: Applies the one-direction brightness convenience primitive.
- Represents: One lighten/darken pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.037 µs | 0.062 µs | 0.094 µs | 0.093 µs |
| Avg | 0.040 µs | 0.062 µs | 0.096 µs | 0.099 µs |
| p50 | 0.040 µs | 0.062 µs | 0.096 µs | 0.099 µs |
| p90 | 0.041 µs | 0.063 µs | 0.096 µs | 0.100 µs |
| p95 | 0.042 µs | 0.063 µs | 0.097 µs | 0.101 µs |
| p99 | 0.043 µs | 0.065 µs | 0.098 µs | 0.101 µs |
| Max | 0.053 µs | 0.077 µs | 0.108 µs | 0.106 µs |
| Tail | 1.06× avg (very tight) | 1.04× avg (very tight) | 1.03× avg (very tight) | 1.02× avg (very tight) |

### shiftHue(45)

- Measures: Converts RGB↔HSL internally and rotates hue on a packed colour.
- Represents: The mathematically heaviest normal colour primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.066 µs | 0.106 µs | 0.143 µs | 0.135 µs |
| Avg | 0.070 µs | 0.107 µs | 0.149 µs | 0.139 µs |
| p50 | 0.069 µs | 0.106 µs | 0.149 µs | 0.138 µs |
| p90 | 0.074 µs | 0.110 µs | 0.150 µs | 0.140 µs |
| p95 | 0.076 µs | 0.111 µs | 0.151 µs | 0.141 µs |
| p99 | 0.077 µs | 0.112 µs | 0.156 µs | 0.143 µs |
| Max | 0.088 µs | 0.145 µs | 0.161 µs | 0.150 µs |
| Tail | 1.11× avg (very tight) | 1.04× avg (very tight) | 1.05× avg (very tight) | 1.03× avg (very tight) |

### gamma(1.10)

- Measures: Applies gamma correction to packed RGB channels.
- Represents: One gamma pipeline primitive.
- Profile: 100 samples × 10000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.089 µs | 0.137 µs | 0.169 µs | 0.161 µs |
| Avg | 0.092 µs | 0.139 µs | 0.171 µs | 0.167 µs |
| p50 | 0.092 µs | 0.138 µs | 0.170 µs | 0.168 µs |
| p90 | 0.094 µs | 0.139 µs | 0.173 µs | 0.170 µs |
| p95 | 0.095 µs | 0.140 µs | 0.174 µs | 0.171 µs |
| p99 | 0.095 µs | 0.145 µs | 0.175 µs | 0.172 µs |
| Max | 0.101 µs | 0.188 µs | 0.176 µs | 0.183 µs |
| Tail | 1.04× avg (very tight) | 1.04× avg (very tight) | 1.03× avg (very tight) | 1.03× avg (very tight) |

### construct shiftHue.fg(45)

- Measures: Creates one pipeline operation table through the public channel API.
- Represents: The allocation cost paid while compiling/creating a pipeline, not while applying a prebuilt pipeline.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.050 µs | 0.075 µs | 0.110 µs | 0.105 µs |
| Avg | 0.095 µs | 0.122 µs | 0.192 µs | 0.150 µs |
| p50 | 0.057 µs | 0.082 µs | 0.125 µs | 0.113 µs |
| p90 | 0.134 µs | 0.176 µs | 0.249 µs | 0.213 µs |
| p95 | 0.257 µs | 0.199 µs | 0.637 µs | 0.237 µs |
| p99 | 0.592 µs | 0.584 µs | 1.017 µs | 0.438 µs |
| Max | 0.767 µs | 0.719 µs | 1.455 µs | 0.581 µs |
| Tail | 6.23× avg (wide tails) | 4.79× avg (wide tails) | 5.28× avg (wide tails) | 2.92× avg (visible tails) |

### apply nil

- Measures: Calls pipeline.apply() with no operations.
- Represents: Early-return floor for styles without a pipeline.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.039 µs | 0.051 µs | 0.147 µs | 0.135 µs |
| Avg | 0.040 µs | 0.052 µs | 0.152 µs | 0.143 µs |
| p50 | 0.040 µs | 0.052 µs | 0.149 µs | 0.139 µs |
| p90 | 0.040 µs | 0.052 µs | 0.156 µs | 0.143 µs |
| p95 | 0.040 µs | 0.054 µs | 0.159 µs | 0.152 µs |
| p99 | 0.046 µs | 0.057 µs | 0.167 µs | 0.234 µs |
| Max | 0.078 µs | 0.082 µs | 0.201 µs | 0.238 µs |
| Tail | 1.14× avg (very tight) | 1.09× avg (very tight) | 1.11× avg (very tight) | 1.64× avg (tight) |

### apply 1 op

- Measures: Applies one prebuilt pipeline operation to packed colours.
- Represents: Single-operation runtime pipeline cost with construction excluded.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.093 µs | 0.126 µs | 0.477 µs | 0.482 µs |
| Avg | 0.098 µs | 0.128 µs | 0.507 µs | 0.508 µs |
| p50 | 0.097 µs | 0.126 µs | 0.507 µs | 0.508 µs |
| p90 | 0.098 µs | 0.129 µs | 0.512 µs | 0.518 µs |
| p95 | 0.099 µs | 0.130 µs | 0.522 µs | 0.522 µs |
| p99 | 0.121 µs | 0.153 µs | 0.535 µs | 0.536 µs |
| Max | 0.214 µs | 0.261 µs | 0.561 µs | 0.550 µs |
| Tail | 1.23× avg (very tight) | 1.19× avg (very tight) | 1.05× avg (very tight) | 1.05× avg (very tight) |

### apply 7 ops

- Measures: Applies a prebuilt seven-operation mixed pipeline.
- Represents: Representative multi-operation pipeline execution cost.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.292 µs | 0.443 µs | 2.724 µs | 2.543 µs |
| Avg | 0.371 µs | 0.456 µs | 2.766 µs | 2.622 µs |
| p50 | 0.308 µs | 0.448 µs | 2.748 µs | 2.631 µs |
| p90 | 0.334 µs | 0.465 µs | 2.814 µs | 2.685 µs |
| p95 | 0.351 µs | 0.474 µs | 2.828 µs | 2.715 µs |
| p99 | 0.557 µs | 0.488 µs | 3.042 µs | 2.785 µs |
| Max | 6.067 µs | 0.923 µs | 3.073 µs | 3.166 µs |
| Tail | 1.50× avg (tight) | 1.07× avg (very tight) | 1.10× avg (very tight) | 1.06× avg (very tight) |

## Highlight apply

Action flatten/sort, resolver/raw actions and theme apply bookkeeping. This is the back half of a compiled theme load before editor consumers redraw.

### ColorSchemePre autocmd

- Measures: Executes only the ColorSchemePre event used by theme.apply().
- Represents: External autocmd contribution before highlight replacement.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.317 µs | 0.473 µs | 0.506 µs | 0.502 µs |
| Avg | 0.526 µs | 0.697 µs | 0.708 µs | 0.607 µs |
| p50 | 0.337 µs | 0.510 µs | 0.540 µs | 0.524 µs |
| p90 | 0.362 µs | 0.577 µs | 0.590 µs | 0.554 µs |
| p95 | 0.418 µs | 0.592 µs | 0.623 µs | 0.571 µs |
| p99 | 2.624 µs | 4.705 µs | 3.651 µs | 3.683 µs |
| Max | 14.770 µs | 11.422 µs | 12.607 µs | 4.988 µs |
| Tail | 4.99× avg (wide tails) | 6.75× avg (wide tails) | 5.16× avg (wide tails) | 6.07× avg (wide tails) |

### reset_highlights() [steady repeated]

- Measures: Clears/reinitializes highlights in the same steady repeated state used by apply.
- Represents: Neovim highlight reset contribution.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 133.380 µs | 198.873 µs | 199.007 µs | 199.435 µs |
| Avg | 140.304 µs | 205.898 µs | 201.939 µs | 203.325 µs |
| p50 | 139.585 µs | 201.206 µs | 199.869 µs | 200.144 µs |
| p90 | 146.680 µs | 225.735 µs | 205.340 µs | 212.487 µs |
| p95 | 149.066 µs | 225.998 µs | 209.841 µs | 225.004 µs |
| p99 | 150.047 µs | 227.406 µs | 226.685 µs | 226.246 µs |
| Max | 160.425 µs | 236.383 µs | 227.619 µs | 230.449 µs |
| Tail | 1.07× avg (very tight) | 1.10× avg (very tight) | 1.12× avg (very tight) | 1.11× avg (very tight) |

### refresh_catalog()

- Measures: Refreshes the runtime highlight catalog.
- Represents: Runtime lookup/catalog maintenance after theme changes.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 579.133 µs | 759.072 µs | 767.905 µs | 795.448 µs |
| Avg | 827.923 µs | 1.082 ms | 1.095 ms | 1.142 ms |
| p50 | 678.676 µs | 845.879 µs | 886.468 µs | 867.041 µs |
| p90 | 1.324 ms | 2.055 ms | 1.846 ms | 2.235 ms |
| p95 | 1.423 ms | 2.208 ms | 2.059 ms | 2.384 ms |
| p99 | 1.534 ms | 2.410 ms | 2.224 ms | 2.535 ms |
| Max | 1.585 ms | 2.533 ms | 2.230 ms | 2.758 ms |
| Tail | 1.85× avg (visible tails) | 2.23× avg (visible tails) | 2.03× avg (visible tails) | 2.22× avg (visible tails) |

### runtime.global_clear()

- Measures: Propagates the compiler's global clear state into runtime state.
- Represents: Runtime clear bookkeeping during apply.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.009 µs | 0.059 µs | 0.096 µs | 0.100 µs |
| Avg | 0.108 µs | 0.172 µs | 0.152 µs | 0.220 µs |
| p50 | 0.010 µs | 0.061 µs | 0.100 µs | 0.102 µs |
| p90 | 0.063 µs | 0.105 µs | 0.151 µs | 0.150 µs |
| p95 | 0.071 µs | 0.114 µs | 0.153 µs | 0.160 µs |
| p99 | 2.140 µs | 4.211 µs | 0.553 µs | 4.145 µs |
| Max | 3.941 µs | 6.120 µs | 3.973 µs | 6.394 µs |
| Tail | 19.75× avg (wide tails) | 24.55× avg (wide tails) | 3.65× avg (wide tails) | 18.84× avg (wide tails) |

### flatten + sort actions [938 actions]

- Measures: Flattens all module actions and sorts them by apply priority.
- Represents: Pure Lua action scheduling cost before Neovim writes.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 466.262 µs | 684.945 µs | 680.403 µs | 668.688 µs |
| Avg | 496.201 µs | 693.744 µs | 689.585 µs | 677.122 µs |
| p50 | 489.602 µs | 689.875 µs | 684.671 µs | 672.403 µs |
| p90 | 526.663 µs | 703.148 µs | 700.364 µs | 685.158 µs |
| p95 | 536.530 µs | 714.033 µs | 703.357 µs | 696.616 µs |
| p99 | 539.568 µs | 740.379 µs | 748.366 µs | 729.068 µs |
| Max | 542.200 µs | 752.970 µs | 771.545 µs | 735.633 µs |
| Tail | 1.09× avg (very tight) | 1.07× avg (very tight) | 1.09× avg (very tight) | 1.08× avg (very tight) |
| Avg / action | 0.529 µs | 0.740 µs | 0.735 µs | 0.722 µs |

### run_action all [938 actions]

- Measures: Executes every already-sorted compiled action one by one.
- Represents: Core action execution cost for the complete theme.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 968.342 µs | 1.537 ms | 1.481 ms | 1.477 ms |
| Avg | 1.318 ms | 1.781 ms | 1.765 ms | 1.717 ms |
| p50 | 1.182 ms | 1.674 ms | 1.659 ms | 1.629 ms |
| p90 | 1.608 ms | 1.928 ms | 1.892 ms | 1.876 ms |
| p95 | 2.544 ms | 2.175 ms | 2.971 ms | 2.006 ms |
| p99 | 3.120 ms | 4.136 ms | 3.830 ms | 3.707 ms |
| Max | 3.163 ms | 4.434 ms | 3.866 ms | 4.422 ms |
| Tail | 2.37× avg (visible tails) | 2.32× avg (visible tails) | 2.17× avg (visible tails) | 2.16× avg (visible tails) |
| Avg / action | 1.405 µs | 1.898 µs | 1.882 µs | 1.831 µs |

### resolver.clear_cache + _apply_modules [938 actions]

- Measures: Clears resolver caches and then applies every compiled module.
- Represents: Cold full-module apply path after resolver invalidation.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.930 ms | 2.606 ms | 2.822 ms | 2.638 ms |
| Avg | 2.520 ms | 3.282 ms | 3.504 ms | 3.309 ms |
| p50 | 2.220 ms | 2.997 ms | 3.167 ms | 2.959 ms |
| p90 | 3.115 ms | 3.510 ms | 3.918 ms | 3.588 ms |
| p95 | 4.574 ms | 7.644 ms | 6.661 ms | 5.668 ms |
| p99 | 6.307 ms | 8.548 ms | 8.375 ms | 8.825 ms |
| Max | 6.581 ms | 8.670 ms | 9.334 ms | 9.495 ms |
| Tail | 2.50× avg (visible tails) | 2.60× avg (visible tails) | 2.39× avg (visible tails) | 2.67× avg (visible tails) |
| Avg / action | 2.686 µs | 3.499 µs | 3.735 µs | 3.527 µs |

### _apply_modules cached [938 actions]

- Measures: Applies every compiled module with resolver session caches already warm.
- Represents: Steady repeated module-apply path.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.377 ms | 2.241 ms | 2.245 ms | 2.148 ms |
| Avg | 1.671 ms | 2.557 ms | 2.559 ms | 2.675 ms |
| p50 | 1.554 ms | 2.487 ms | 2.398 ms | 2.484 ms |
| p90 | 1.963 ms | 2.799 ms | 2.789 ms | 3.106 ms |
| p95 | 2.329 ms | 2.964 ms | 3.376 ms | 3.415 ms |
| p99 | 3.425 ms | 4.726 ms | 5.026 ms | 5.313 ms |
| Max | 3.534 ms | 5.361 ms | 5.278 ms | 5.729 ms |
| Tail | 2.05× avg (visible tails) | 1.85× avg (visible tails) | 1.96× avg (visible tails) | 1.99× avg (visible tails) |
| Avg / action | 1.782 µs | 2.726 µs | 2.729 µs | 2.852 µs |

### resolver_style [834 actions]

- Measures: Executes only the compiled actions of the named action kind.
- Represents: Breakdown of total action execution by resolver/raw style/link/clear kind.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 825.465 µs | 1.364 ms | 1.156 ms | 1.341 ms |
| Avg | 1.044 ms | 1.648 ms | 1.429 ms | 1.640 ms |
| p50 | 960.183 µs | 1.534 ms | 1.329 ms | 1.549 ms |
| p90 | 1.387 ms | 1.992 ms | 1.670 ms | 1.818 ms |
| p95 | 1.729 ms | 2.583 ms | 2.191 ms | 2.650 ms |
| p99 | 1.795 ms | 2.936 ms | 2.488 ms | 3.036 ms |
| Max | 1.806 ms | 3.207 ms | 2.782 ms | 3.232 ms |
| Tail | 1.72× avg (tight) | 1.78× avg (visible tails) | 1.74× avg (tight) | 1.85× avg (visible tails) |
| Avg / action | 1.252 µs | 1.976 µs | 1.714 µs | 1.966 µs |

### resolver_link [104 actions]

- Measures: Executes only the compiled actions of the named action kind.
- Represents: Breakdown of total action execution by resolver/raw style/link/clear kind.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 87.642 µs | 118.772 µs | 118.175 µs | 119.270 µs |
| Avg | 124.533 µs | 168.414 µs | 166.271 µs | 156.722 µs |
| p50 | 95.948 µs | 129.322 µs | 123.984 µs | 130.217 µs |
| p90 | 140.171 µs | 200.263 µs | 200.653 µs | 184.773 µs |
| p95 | 336.685 µs | 384.789 µs | 481.514 µs | 193.673 µs |
| p99 | 473.672 µs | 636.280 µs | 582.848 µs | 562.330 µs |
| Max | 474.640 µs | 696.572 µs | 653.489 µs | 723.782 µs |
| Tail | 3.80× avg (wide tails) | 3.78× avg (wide tails) | 3.51× avg (wide tails) | 3.59× avg (wide tails) |
| Avg / action | 1.197 µs | 1.619 µs | 1.599 µs | 1.507 µs |

### runtime _theme_prepare()

- Measures: Prepares sparse runtime overlays for an incoming compiled theme.
- Represents: Runtime pre-apply bookkeeping.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.065 µs | 0.129 µs | 0.091 µs | 0.160 µs |
| Avg | 0.254 µs | 0.431 µs | 0.392 µs | 0.255 µs |
| p50 | 0.084 µs | 0.177 µs | 0.121 µs | 0.189 µs |
| p90 | 0.152 µs | 0.254 µs | 0.251 µs | 0.228 µs |
| p95 | 0.392 µs | 1.706 µs | 0.314 µs | 0.249 µs |
| p99 | 4.996 µs | 4.675 µs | 4.317 µs | 0.702 µs |
| Max | 5.665 µs | 9.040 µs | 16.330 µs | 5.803 µs |
| Tail | 19.67× avg (wide tails) | 10.86× avg (wide tails) | 11.03× avg (wide tails) | 2.76× avg (visible tails) |

### ColorScheme autocmd

- Measures: Executes only the ColorScheme event.
- Represents: External autocmd contribution after highlights are applied.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 2.306 µs | 3.084 µs | 4.909 µs | 4.909 µs |
| Avg | 2.583 µs | 3.505 µs | 5.371 µs | 5.372 µs |
| p50 | 2.416 µs | 3.227 µs | 5.045 µs | 5.037 µs |
| p90 | 2.633 µs | 3.804 µs | 5.567 µs | 5.214 µs |
| p95 | 3.557 µs | 4.692 µs | 7.056 µs | 6.921 µs |
| p99 | 5.058 µs | 6.527 µs | 11.511 µs | 11.702 µs |
| Max | 6.702 µs | 12.969 µs | 13.217 µs | 13.375 µs |
| Tail | 1.96× avg (visible tails) | 1.86× avg (visible tails) | 2.14× avg (visible tails) | 2.18× avg (visible tails) |

### runtime _theme_applied()

- Measures: Rebinds/recomposes surviving sparse runtime overlays after apply.
- Represents: Runtime post-apply bookkeeping.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.067 µs | 0.063 µs | 0.062 µs | 0.133 µs |
| Avg | 0.246 µs | 0.248 µs | 0.214 µs | 0.272 µs |
| p50 | 0.085 µs | 0.071 µs | 0.067 µs | 0.146 µs |
| p90 | 0.156 µs | 0.090 µs | 0.092 µs | 0.316 µs |
| p95 | 0.264 µs | 0.346 µs | 0.145 µs | 0.344 µs |
| p99 | 5.355 µs | 5.727 µs | 6.053 µs | 3.028 µs |
| Max | 6.612 µs | 7.216 µs | 7.486 µs | 5.799 µs |
| Tail | 21.77× avg (wide tails) | 23.08× avg (wide tails) | 28.32× avg (wide tails) | 11.12× avg (wide tails) |

## Editor consumers and redraw

Tree-sitter/LSP refresh hooks and Neovim redraw. These are intentionally low-batch because they are external editor work, not a tight Lua hot loop.

### refresh_consumers() no redraw

- Measures: Runs only configured Tree-sitter/LSP consumer refreshes, excluding redraw.
- Represents: Optional editor-consumer cost controlled by autoreload settings.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.077 µs | 0.084 µs | 0.077 µs | 0.166 µs |
| Avg | 0.566 µs | 0.411 µs | 0.585 µs | 0.582 µs |
| p50 | 0.082 µs | 0.091 µs | 0.082 µs | 0.193 µs |
| p90 | 0.169 µs | 0.188 µs | 0.198 µs | 0.204 µs |
| p95 | 0.229 µs | 0.225 µs | 0.233 µs | 0.235 µs |
| p99 | 8.195 µs | 1.069 µs | 0.738 µs | 2.098 µs |
| Max | 37.476 µs | 29.443 µs | 48.244 µs | 36.808 µs |
| Tail | 14.48× avg (wide tails) | 2.60× avg (visible tails) | 1.26× avg (tight) | 3.60× avg (wide tails) |

### treesitter only

- Measures: Forces the Tree-sitter refresh helper in the current editor state.
- Represents: External Tree-sitter refresh cost; highly buffer/config dependent.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.094 µs | 0.107 µs | 0.099 µs | 0.170 µs |
| Avg | 0.576 µs | 0.443 µs | 0.605 µs | 0.439 µs |
| p50 | 0.099 µs | 0.116 µs | 0.108 µs | 0.178 µs |
| p90 | 0.155 µs | 0.303 µs | 0.272 µs | 0.289 µs |
| p95 | 0.470 µs | 0.336 µs | 0.394 µs | 0.336 µs |
| p99 | 16.159 µs | 1.285 µs | 16.001 µs | 2.941 µs |
| Max | 21.499 µs | 29.180 µs | 29.892 µs | 20.827 µs |
| Tail | 28.08× avg (wide tails) | 2.90× avg (visible tails) | 26.47× avg (wide tails) | 6.69× avg (wide tails) |

### lsp semantic tokens only

- Measures: Forces the semantic-token refresh helper in the current editor state.
- Represents: External LSP semantic-token refresh cost; highly client/buffer dependent.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.197 µs | 0.117 µs | 0.113 µs | 0.432 µs |
| Avg | 1.050 µs | 1.229 µs | 1.495 µs | 1.616 µs |
| p50 | 0.252 µs | 0.120 µs | 0.117 µs | 0.499 µs |
| p90 | 0.423 µs | 0.556 µs | 0.468 µs | 2.972 µs |
| p95 | 2.403 µs | 0.845 µs | 10.250 µs | 5.796 µs |
| p99 | 16.842 µs | 29.628 µs | 28.745 µs | 30.337 µs |
| Max | 34.424 µs | 64.455 µs | 58.780 µs | 37.214 µs |
| Tail | 16.04× avg (wide tails) | 24.11× avg (wide tails) | 19.23× avg (wide tails) | 18.78× avg (wide tails) |

### redraw! only

- Measures: Runs Neovim redraw! with no ChromaFlow work around it.
- Represents: Editor redraw cost ChromaFlow cannot meaningfully optimize internally.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 157.281 µs | 225.871 µs | 227.476 µs | 237.826 µs |
| Avg | 166.092 µs | 234.633 µs | 236.801 µs | 249.750 µs |
| p50 | 159.603 µs | 229.380 µs | 231.087 µs | 243.673 µs |
| p90 | 179.220 µs | 247.935 µs | 255.976 µs | 267.224 µs |
| p95 | 190.680 µs | 259.621 µs | 268.818 µs | 279.949 µs |
| p99 | 243.197 µs | 280.937 µs | 290.708 µs | 287.678 µs |
| Max | 261.129 µs | 281.619 µs | 290.875 µs | 300.550 µs |
| Tail | 1.46× avg (tight) | 1.20× avg (very tight) | 1.23× avg (very tight) | 1.15× avg (very tight) |

### treesitter + lsp + redraw!

- Measures: Runs all consumer refresh helpers followed by redraw!.
- Represents: Upper consumer-side combination in the current editor state.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 154.334 µs | 226.634 µs | 228.872 µs | 239.772 µs |
| Avg | 163.948 µs | 231.549 µs | 233.441 µs | 248.328 µs |
| p50 | 159.989 µs | 228.547 µs | 231.013 µs | 243.178 µs |
| p90 | 170.876 µs | 236.827 µs | 238.648 µs | 255.300 µs |
| p95 | 180.161 µs | 239.531 µs | 240.482 µs | 271.069 µs |
| p99 | 203.456 µs | 256.224 µs | 257.311 µs | 282.101 µs |
| Max | 228.391 µs | 301.854 µs | 296.804 µs | 380.077 µs |
| Tail | 1.24× avg (very tight) | 1.11× avg (very tight) | 1.10× avg (very tight) | 1.14× avg (very tight) |

### refresh_consumers() [configured]

- Measures: Runs the exact consumer policy currently configured in cf.config.
- Represents: Consumer tail included by theme.apply() for this benchmark setup.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 134.322 µs | 218.103 µs | 228.440 µs | 240.033 µs |
| Avg | 147.242 µs | 227.047 µs | 231.848 µs | 243.588 µs |
| p50 | 142.521 µs | 227.818 µs | 230.637 µs | 241.545 µs |
| p90 | 160.440 µs | 231.278 µs | 233.782 µs | 248.693 µs |
| p95 | 164.179 µs | 234.732 µs | 238.818 µs | 250.425 µs |
| p99 | 190.699 µs | 241.378 µs | 251.323 µs | 252.400 µs |
| Max | 215.759 µs | 251.714 µs | 262.086 µs | 287.935 µs |
| Tail | 1.30× avg (tight) | 1.06× avg (very tight) | 1.08× avg (very tight) | 1.04× avg (very tight) |

## Runtime, picker, LineBlend and watcher

Session-state helpers and optional runtime/UI integration. This section makes the cost of sparse runtime state and surrounding services visible separately from core compile/apply.

### picker style state

- Measures: Reads the current sparse picker/runtime state for one real compiled target.
- Represents: Picker inspection cost before editing a style.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.578 µs | 0.772 µs | 0.791 µs | 0.825 µs |
| Avg | 1.002 µs | 1.326 µs | 1.407 µs | 1.365 µs |
| p50 | 0.645 µs | 0.827 µs | 0.853 µs | 0.911 µs |
| p90 | 1.406 µs | 1.444 µs | 1.864 µs | 1.632 µs |
| p95 | 3.378 µs | 3.904 µs | 5.435 µs | 4.019 µs |
| p99 | 4.494 µs | 5.978 µs | 6.945 µs | 6.790 µs |
| Max | 4.795 µs | 6.016 µs | 7.011 µs | 7.569 µs |
| Tail | 4.49× avg (wide tails) | 4.51× avg (wide tails) | 4.93× avg (wide tails) | 4.98× avg (wide tails) |

### picker style write

- Measures: Writes one style through the runtime picker overlay path.
- Represents: Cost of one live picker style update, excluding UI key handling/rendering.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.659 µs | 2.994 µs | 3.050 µs | 3.180 µs |
| Avg | 2.101 µs | 3.612 µs | 3.689 µs | 3.602 µs |
| p50 | 1.914 µs | 3.225 µs | 3.339 µs | 3.305 µs |
| p90 | 2.292 µs | 4.128 µs | 4.008 µs | 3.791 µs |
| p95 | 3.154 µs | 5.884 µs | 6.625 µs | 4.111 µs |
| p99 | 5.032 µs | 8.154 µs | 7.622 µs | 7.926 µs |
| Max | 5.235 µs | 9.173 µs | 8.542 µs | 8.724 µs |
| Tail | 2.40× avg (visible tails) | 2.26× avg (visible tails) | 2.07× avg (visible tails) | 2.20× avg (visible tails) |

### lineblend.refresh() [current state]

- Measures: Runs LineBlend's cached refresh in the current state.
- Represents: Normal ChromaFlow post-reload LineBlend interaction.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.428 µs | 0.584 µs | 0.585 µs | 0.561 µs |
| Avg | 0.631 µs | 1.149 µs | 0.829 µs | 0.813 µs |
| p50 | 0.473 µs | 0.919 µs | 0.623 µs | 0.600 µs |
| p90 | 0.517 µs | 1.119 µs | 0.698 µs | 0.670 µs |
| p95 | 0.537 µs | 1.158 µs | 1.003 µs | 0.705 µs |
| p99 | 4.061 µs | 11.932 µs | 7.665 µs | 2.375 µs |
| Max | 11.878 µs | 18.173 µs | 9.975 µs | 18.378 µs |
| Tail | 6.44× avg (wide tails) | 10.38× avg (wide tails) | 9.24× avg (wide tails) | 2.92× avg (visible tails) |

### lineblend.reload() [current state]

- Measures: Runs LineBlend's hard reload path.
- Represents: Expensive diagnostic comparison only; ChromaFlow intentionally does not hard-reload LineBlend on normal reloads.
- Profile: 100 samples × 1 call; warmup 15 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 8.250 µs | 12.106 µs | 12.272 µs | 12.695 µs |
| Avg | 13.707 µs | 19.285 µs | 19.845 µs | 17.343 µs |
| p50 | 9.641 µs | 13.184 µs | 13.975 µs | 13.781 µs |
| p90 | 24.463 µs | 36.297 µs | 36.565 µs | 24.073 µs |
| p95 | 29.779 µs | 39.711 µs | 49.040 µs | 36.754 µs |
| p99 | 40.276 µs | 60.311 µs | 61.183 µs | 49.493 µs |
| Max | 65.493 µs | 87.938 µs | 61.756 µs | 50.290 µs |
| Tail | 2.94× avg (visible tails) | 3.13× avg (wide tails) | 3.08× avg (wide tails) | 2.85× avg (visible tails) |

### watcher.is_running()

- Measures: Checks watcher state.
- Represents: Tiny service-state query.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.000 µs | 0.001 µs | 0.001 µs | 0.079 µs |
| Avg | 0.001 µs | 0.002 µs | 0.001 µs | 0.081 µs |
| p50 | 0.000 µs | 0.001 µs | 0.001 µs | 0.080 µs |
| p90 | 0.000 µs | 0.001 µs | 0.001 µs | 0.081 µs |
| p95 | 0.000 µs | 0.001 µs | 0.001 µs | 0.082 µs |
| p99 | 0.013 µs | 0.026 µs | 0.017 µs | 0.085 µs |
| Max | 0.017 µs | 0.034 µs | 0.023 µs | 0.094 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | 1.05× avg (very tight) |

### watcher.set_themes()

- Measures: Updates watcher default/active theme scopes without rebuilding the watcher.
- Represents: Normal watcher bookkeeping after a reload when watching is active.
- Profile: 100 samples × 5 calls; warmup 20 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.059 µs | 0.063 µs | 0.067 µs | 0.108 µs |
| Avg | 0.169 µs | 0.205 µs | 0.225 µs | 0.204 µs |
| p50 | 0.059 µs | 0.064 µs | 0.068 µs | 0.111 µs |
| p90 | 0.063 µs | 0.073 µs | 0.073 µs | 0.113 µs |
| p95 | 0.123 µs | 0.144 µs | 0.153 µs | 0.124 µs |
| p99 | 4.192 µs | 5.800 µs | 6.151 µs | 0.681 µs |
| Max | 6.031 µs | 7.030 µs | 8.268 µs | 8.640 µs |
| Tail | 24.80× avg (wide tails) | 28.27× avg (wide tails) | 27.32× avg (wide tails) | 3.35× avg (wide tails) |

## Diagnostics and source tracing

Diagnostic gates/queues and picker/ColorTrace source tracing in the currently active feature configuration.

### _enabled(error+hint)

- Measures: Runs the diagnostic policy gate for two severities.
- Represents: Producer-side early-out cost in the active severity configuration.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.000 µs | 0.001 µs | 0.001 µs | 0.104 µs |
| Avg | 0.001 µs | 0.002 µs | 0.002 µs | 0.108 µs |
| p50 | 0.000 µs | 0.001 µs | 0.001 µs | 0.106 µs |
| p90 | 0.000 µs | 0.001 µs | 0.001 µs | 0.109 µs |
| p95 | 0.001 µs | 0.001 µs | 0.001 µs | 0.110 µs |
| p99 | 0.019 µs | 0.020 µs | 0.028 µs | 0.120 µs |
| Max | 0.069 µs | 0.136 µs | 0.081 µs | 0.227 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | 1.11× avg (very tight) |

### clear_pending()

- Measures: Clears the pending diagnostic queue.
- Represents: Per-theme-cycle queue reset cost.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.000 µs | 0.001 µs | 0.001 µs | 0.081 µs |
| Avg | 0.001 µs | 0.001 µs | 0.001 µs | 0.084 µs |
| p50 | 0.000 µs | 0.001 µs | 0.001 µs | 0.082 µs |
| p90 | 0.000 µs | 0.001 µs | 0.001 µs | 0.087 µs |
| p95 | 0.001 µs | 0.001 µs | 0.001 µs | 0.091 µs |
| p99 | 0.011 µs | 0.018 µs | 0.017 µs | 0.106 µs |
| Max | 0.017 µs | 0.028 µs | 0.026 µs | 0.107 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | 1.26× avg (tight) |

### flush() empty

- Measures: Flushes an empty diagnostic queue after clearing it.
- Represents: No-record end-of-cycle diagnostic overhead.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.003 µs | 0.005 µs | 0.005 µs | 0.005 µs |
| Avg | 0.004 µs | 0.005 µs | 0.006 µs | 0.006 µs |
| p50 | 0.004 µs | 0.005 µs | 0.005 µs | 0.005 µs |
| p90 | 0.004 µs | 0.005 µs | 0.006 µs | 0.005 µs |
| p95 | 0.004 µs | 0.005 µs | 0.006 µs | 0.007 µs |
| p99 | 0.016 µs | 0.023 µs | 0.024 µs | 0.020 µs |
| Max | 0.023 µs | 0.039 µs | 0.040 µs | 0.088 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | timer-floor dominated |

### _source_mode(current flags)

- Measures: Determines source tracing mode for one real theme file.
- Represents: ColorTrace/picker source-trace gate cost.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 1.480 µs | 2.055 µs | 7.928 µs | 7.606 µs |
| Avg | 2.375 µs | 3.507 µs | 12.530 µs | 12.178 µs |
| p50 | 1.643 µs | 2.598 µs | 10.912 µs | 10.125 µs |
| p90 | 4.913 µs | 6.736 µs | 18.041 µs | 19.778 µs |
| p95 | 5.735 µs | 8.848 µs | 18.600 µs | 20.081 µs |
| p99 | 6.429 µs | 10.415 µs | 18.907 µs | 20.705 µs |
| Max | 7.202 µs | 11.040 µs | 19.118 µs | 21.509 µs |
| Tail | 2.71× avg (visible tails) | 2.97× avg (visible tails) | 1.51× avg (tight) | 1.70× avg (tight) |

### _cached(file)

- Measures: Looks up cached source-trace data for one real theme file.
- Represents: Hot picker/ColorTrace source cache lookup.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | — | 2.030 µs | — | 1.892 µs |
| Avg | — | 3.396 µs | — | 3.583 µs |
| p50 | — | 2.672 µs | — | 2.906 µs |
| p90 | — | 6.222 µs | — | 6.718 µs |
| p95 | — | 8.839 µs | — | 8.466 µs |
| p99 | — | 10.608 µs | — | 10.866 µs |
| Max | — | 11.267 µs | — | 13.698 µs |
| Tail | — | 3.12× avg (wide tails) | — | 3.03× avg (wide tails) |

### scan cached records [8]

- Measures: Iterates the cached source-trace records for one real file.
- Represents: Cost of consuming trace metadata after lookup.
- Profile: 100 samples × 1000 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | — | 0.121 µs | — | 0.063 µs |
| Avg | — | 0.132 µs | — | 0.098 µs |
| p50 | — | 0.122 µs | — | 0.108 µs |
| p90 | — | 0.166 µs | — | 0.117 µs |
| p95 | — | 0.194 µs | — | 0.123 µs |
| p99 | — | 0.222 µs | — | 0.138 µs |
| Max | — | 0.227 µs | — | 0.160 µs |
| Tail | — | 1.69× avg (tight) | — | 1.42× avg (tight) |

## Float renderer

The reusable float diff renderer used by ChromaFlow UI. Same-reference, span replacement, bulk line updates and window open/hide are measured separately.

### set_line same reference

- Measures: Sets a float line to the exact same span-table reference.
- Represents: Best-case early-out of the float diff renderer.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 0.002 µs | 0.002 µs | 0.002 µs | 0.002 µs |
| Avg | 0.006 µs | 0.007 µs | 0.008 µs | 0.009 µs |
| p50 | 0.002 µs | 0.002 µs | 0.002 µs | 0.002 µs |
| p90 | 0.002 µs | 0.003 µs | 0.003 µs | 0.003 µs |
| p95 | 0.003 µs | 0.003 µs | 0.003 µs | 0.005 µs |
| p99 | 0.139 µs | 0.175 µs | 0.185 µs | 0.165 µs |
| Max | 0.234 µs | 0.293 µs | 0.348 µs | 0.407 µs |
| Tail | timer-floor dominated | timer-floor dominated | timer-floor dominated | timer-floor dominated |

### replace 3 spans

- Measures: Alternates one float line between two three-span layouts.
- Represents: Typical small diff/update cost.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 3.315 µs | 4.619 µs | 4.671 µs | 5.571 µs |
| Avg | 3.526 µs | 4.779 µs | 4.743 µs | 6.353 µs |
| p50 | 3.493 µs | 4.705 µs | 4.703 µs | 5.664 µs |
| p90 | 3.602 µs | 4.818 µs | 4.886 µs | 6.647 µs |
| p95 | 3.724 µs | 4.958 µs | 4.950 µs | 11.212 µs |
| p99 | 4.247 µs | 5.089 µs | 5.124 µs | 11.405 µs |
| Max | 4.287 µs | 10.283 µs | 5.491 µs | 21.253 µs |
| Tail | 1.20× avg (very tight) | 1.06× avg (very tight) | 1.08× avg (very tight) | 1.80× avg (visible tails) |

### set_lines 20x3 spans

- Measures: Alternates twenty lines containing three spans each.
- Represents: Bulk float model-update cost before explicit flush.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 50.849 µs | 79.287 µs | 78.722 µs | 86.047 µs |
| Avg | 56.994 µs | 82.781 µs | 81.587 µs | 92.947 µs |
| p50 | 57.050 µs | 82.807 µs | 82.037 µs | 92.077 µs |
| p90 | 58.511 µs | 85.009 µs | 83.647 µs | 100.166 µs |
| p95 | 59.463 µs | 85.499 µs | 84.313 µs | 100.981 µs |
| p99 | 61.148 µs | 86.683 µs | 85.903 µs | 104.077 µs |
| Max | 61.191 µs | 87.541 µs | 87.346 µs | 105.565 µs |
| Tail | 1.07× avg (very tight) | 1.05× avg (very tight) | 1.05× avg (very tight) | 1.12× avg (very tight) |

### flush all 20x3 spans

- Measures: Flushes the current twenty-line/three-span float state to Neovim.
- Represents: Bulk renderer→Neovim write cost.
- Profile: 100 samples × 100 calls; warmup 25 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 53.808 µs | 81.514 µs | 78.093 µs | 79.912 µs |
| Avg | 56.456 µs | 86.486 µs | 79.371 µs | 83.064 µs |
| p50 | 56.475 µs | 82.962 µs | 79.276 µs | 83.310 µs |
| p90 | 57.614 µs | 94.470 µs | 80.781 µs | 84.773 µs |
| p95 | 57.964 µs | 96.977 µs | 82.592 µs | 85.590 µs |
| p99 | 58.914 µs | 156.379 µs | 83.288 µs | 88.830 µs |
| Max | 60.094 µs | 162.558 µs | 83.425 µs | 89.359 µs |
| Tail | 1.04× avg (very tight) | 1.81× avg (visible tails) | 1.05× avg (very tight) | 1.07× avg (very tight) |

### hide + open

- Measures: Hides and reopens the same float window.
- Represents: Window lifecycle cost rather than line diff cost.
- Profile: 100 samples × 1 call; warmup 8 calls.

| Metric | Minimal | Picker | ColorTrace | Picker + ColorTrace |
| --- | ---: | ---: | ---: | ---: |
| Min | 16.082 µs | 23.628 µs | 23.955 µs | 24.670 µs |
| Avg | 19.107 µs | 27.379 µs | 27.180 µs | 27.403 µs |
| p50 | 16.967 µs | 24.068 µs | 24.518 µs | 25.250 µs |
| p90 | 22.076 µs | 29.220 µs | 33.751 µs | 28.593 µs |
| p95 | 31.648 µs | 50.927 µs | 36.218 µs | 35.680 µs |
| p99 | 47.224 µs | 78.525 µs | 57.292 µs | 58.941 µs |
| Max | 60.632 µs | 85.056 µs | 76.912 µs | 78.255 µs |
| Tail | 2.47× avg (visible tails) | 2.87× avg (visible tails) | 2.11× avg (visible tails) | 2.15× avg (visible tails) |

