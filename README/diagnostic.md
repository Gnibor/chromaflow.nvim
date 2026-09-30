# Diagnostics

## Contents

- [Setup](#setup)
- [HINT, WARN, and ERROR](#hint-warn-and-error)
- [`severity_bias`](#severity_bias)
- [INFO and OK messages](#info-and-ok-messages)
- [Where diagnostics appear](#where-diagnostics-appear)
- [Source positions and ranges](#source-positions-and-ranges)
- [Diagnostic lifecycle](#diagnostic-lifecycle)
- [Common authoring diagnostics](#common-authoring-diagnostics)
- [ColorTrace](#colortrace)

ChromaFlow has a central diagnostic layer for theme and DSL problems found while
loading or recompiling a theme.

Diagnostics are collected while the theme is being processed and rendered only
after that load/reload cycle has finished. This keeps diagnostic UI work out of
the parser, resolver, and materialization paths while still keeping recoverable
errors attached to their source `.cf` files.

## Setup

Diagnostic policy is configured through `require("cf").setup()`:

```lua
require("cf").setup({
  diagnostic = {
    color_trace = false,
    severity_bias = 0,

    severity = {
      hint = false,
      warn = false,
      error = true,
    },

    messages = {
      info = true,
      ok = true,
    },
  },
})
```

These are the default values.

`color_trace` enables the separate ColorTrace diagnostic view. It does not
change the normal HINT/WARN/ERROR filters. See [`colortrace.md`](colortrace.md)
for ColorTrace itself.

## HINT, WARN, and ERROR

Normal ChromaFlow diagnostics use three severities:

```text
HINT
WARN
ERROR
```

Each class can be enabled independently:

```lua
diagnostic = {
  severity = {
    hint = true,
    warn = true,
    error = true,
  },
}
```

The default keeps authoring hints and warnings quiet while leaving errors
visible:

| Severity | Default |
| --- | ---: |
| `hint` | `false` |
| `warn` | `false` |
| `error` | `true` |

Typical built-in diagnostics include:

- invalid declarations or invalid nested TypeMod entries,
- theme-module execution failures,
- unknown callable DSL names,
- `.cf` files that execute but do not return a theme module,
- declarations that cannot produce any highlight action,
- and resolver fallback hints for previously unavailable Type names.

Recoverable diagnostics do not automatically abort the complete theme. For
example, a failing theme module is skipped while valid sibling modules continue,
and an invalid nested TypeMod can be rolled back without discarding a valid base
group or its valid sibling TypeMods.

Errors that make meaningful theme processing impossible remain fatal. The
diagnostic system is not a replacement for those hard configuration/resource
contracts.

## `severity_bias`

ChromaFlow keeps space between its three base severities so their effective
classification can be shifted globally:

| Severity | Base value |
| --- | ---: |
| HINT | `64` |
| WARN | `128` |
| ERROR | `192` |

`severity_bias` is added before the enabled severity class is selected. The
result is clamped to `0..255`.

The class boundaries are:

| Effective value | Classified as |
| --- | --- |
| `0..95` | HINT |
| `96..159` | WARN |
| `160..255` | ERROR |

For example:

```lua
diagnostic = {
  severity_bias = 40,
  severity = {
    hint = false,
    warn = true,
    error = true,
  },
}
```

moves a normal HINT from `64` to `104`, so it is treated as WARN for filtering
and rendering.

A negative bias can move diagnostics in the other direction.

## INFO and OK messages

`INFO` and `OK` are user-message kinds, not diagnostic severities:

```lua
diagnostic = {
  messages = {
    info = true,
    ok = true,
  },
}
```

They are independent from `severity_bias` and from the HINT/WARN/ERROR switches.

ColorTrace INFO records are also separate from the normal `messages.info` gate;
their visibility is controlled by `diagnostic.color_trace` instead.

## Where diagnostics appear

ChromaFlow keeps HINT/WARN/ERROR diagnostics for their source files and renders
them through `vim.diagnostic` whenever the corresponding `.cf` file is available
in a buffer.

If the source is already visible in a window of the **current tabpage** when a
completed diagnostic cycle is flushed, the diagnostic appears there immediately:

| Source state at flush | Immediate output |
| --- | --- |
| Visible in the current tabpage | In-buffer `vim.diagnostic` |

If the source is not visible in the current tabpage, the same diagnostic uses the
ASSERT fallback so it is not missed at flush time:

| Source state at flush | Immediate output |
| --- | --- |
| Hidden, or visible only in another tabpage | ASSERT notification fallback |

Opening the source file later still shows its stored diagnostics normally through
`vim.diagnostic`. ASSERT is therefore the immediate fallback for a currently
hidden source, not a replacement for the file's in-buffer diagnostics.

All ASSERT-fallback diagnostics from one flush are batched into one ChromaFlow
notification. The notification uses the highest effective severity present in
that batch.

`ASSERT` is only an output form. It is **not** a fourth severity and it is not a
Lua `assert()`.

INFO/OK messages use the same current-tab source lookup. A visible source can be
shown in-buffer; otherwise the message is emitted as a normal ChromaFlow
notification rather than an ASSERT batch.

## Source positions and ranges

Every stored diagnostic has a source file plus a 1-based start position:

| Position field | Required |
| --- | ---: |
| `file` | yes |
| `line` | yes |
| `col` | yes |

When a full source range is available, ChromaFlow also keeps:

| Range field | Required |
| --- | ---: |
| `end_line` | no |
| `end_col` | no |

The end position is end-exclusive.

The Lua Tree-sitter parser can provide those complete declaration ranges while
`.cf` files are being compiled. It is **not required for normal diagnostics**:
without it, ChromaFlow can still report diagnostics at their start position.

This source information lets Neovim place diagnostics on the declaration that
caused them instead of reducing every problem to a generic theme-load message.

## Diagnostic lifecycle

One normal theme load/reload owns one pending diagnostic cycle:

```text
start theme operation
        -> clear old pending records
        -> compile / resolve / validate
        -> enqueue diagnostics
        -> finish the theme operation
        -> flush once
```

A producer only records the problem. It does not open UI or change control flow
through the diagnostic manager itself.

Before a new flush is rendered, ChromaFlow clears diagnostics that it rendered
in previous cycles. A clean reload therefore also removes stale in-buffer
problems that no longer exist.

If a fatal error occurs after recoverable diagnostics have already been
recorded, ChromaFlow still flushes that completed pending set before propagating
the fatal error.

## Common authoring diagnostics

### Useless declarations

A declaration that cannot produce a highlight action may emit a HINT. Examples
include an empty group or a TypeMod table without a style, pipeline, link, or
explicit `false` clear.

These records are tagged internally as `UNNECESSARY`.

```lua
p:group("Nothing", {
  priority = 100,
})
```

`priority`, `types`, target metadata, or clear metadata alone do not make a group
a useful highlight action.

### Unknown DSL calls

Unknown callable DSL names inside a loaded `.cf` module are reported as HINTs
and ignored locally:

```lua
l:goup("keyword", { italic = true })
```

The surrounding module can continue compiling, so declarations before and after
the typo are not discarded merely because that call was invalid.

### Invalid declaration scopes

Validation errors inside independently compiled declaration scopes are reported
as ERRORs and rolled back at that scope.

For example, one invalid nested TypeMod does not require ChromaFlow to discard a
valid group base and unrelated valid TypeMods. Invalid group-level structure,
on the other hand, invalidates that group declaration as a unit.

### Module failures

If executing one `.cf` theme module raises an error, that module is marked
failed, an ERROR is reported at its source, and valid sibling modules continue.

A file that executes successfully but does not return `l.setup(...)`,
`p.setup(...)`, or `u.setup(...)` is ignored and may emit a HINT when HINTs are
enabled.

## ColorTrace

ColorTrace uses the diagnostic presentation layer for its source-linked trace
output, but it has its own activation and trace lifecycle:

```lua
diagnostic = {
  color_trace = true,
}
```

Enabling ColorTrace does not enable HINT or WARN diagnostics and does not alter
`severity_bias`.

ColorTrace is documented separately in [`colortrace.md`](colortrace.md).
