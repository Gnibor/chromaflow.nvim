# Theme structure and fallback

## Contents

- [Theme root](#theme-root)
- [`.cf-theme`](#cf-theme)
- [Reserved files](#reserved-files)
- [Ordinary module files](#ordinary-module-files)
- [Module identity](#module-identity)
- [The active pass comes first](#the-active-pass-comes-first)
- [Fallback is decided only after the full active pass](#fallback-is-decided-only-after-the-full-active-pass)
- [Several fallback modules for one uncovered identity are allowed](#several-fallback-modules-for-one-uncovered-identity-are-allowed)
- [File order and declaration order](#file-order-and-declaration-order)
- [Active/default identity filtering is separate from action precedence](#activedefault-identity-filtering-is-separate-from-action-precedence)
- [Root fallback is not module fallback](#root-fallback-is-not-module-fallback)
- [Runtime modules](#runtime-modules)
- [Practical variant patterns](#practical-variant-patterns)
- [Summary](#summary)

ChromaFlow separates three different kinds of fallback:

1. reserved-file fallback for `color.cf` and `config.cf`,
2. semantic fallback for ordinary theme modules,
3. name-based fallback for opt-in runtime modules.

They deliberately do not use the same rules. Understanding that distinction is
the key to structuring small theme variants without copying an entire theme.

## Theme root

A theme root is the directory configured through `theme_path`.

A larger setup can look like this:

```text
themes/
├── .cf-theme
├── color.cf
├── config.cf
├── runtime/
│   └── pulse.cf
├── base/
│   ├── color.cf
│   ├── config.cf
│   ├── lua-core.cf
│   ├── lua-extra.cf
│   ├── ui.cf
│   └── runtime/
│       └── pulse.cf
└── dusk/
    ├── color.cf
    ├── lua.cf
    ├── lua-special.cf
    ├── telescope.cf
    └── runtime/
        └── pulse.cf
```

Only `color.cf` and `config.cf` have fixed meanings based on their filenames.
All other normal `.cf` module filenames are free.

The root-level `runtime/` directory is reserved for shared runtime modules.
`runtime` therefore cannot be used as a theme name.

Normal language/plugin/UI modules are loaded from theme directories, not from
the theme root itself. A root-level `.cf` file other than the two reserved files
is not a normal theme module.

## `.cf-theme`

`.cf-theme` contains exactly two non-empty lines:

```text
base
dusk
```

The first line is the **default** theme. The second line is the **active**
theme.

The default theme must be a valid theme directory. A theme directory is valid
when it exists and contains at least one top-level `.cf` file.

Files only inside `runtime/` do not make a directory a valid normal theme,
because runtime modules are a separate opt-in subsystem.

Normally `:CFTheme` only writes valid selections. If `.cf-theme` is edited by
hand and the requested active theme no longer exists or contains no top-level
`.cf` files, compilation falls back to the default theme as the active theme for
that load.

## Reserved files

`color.cf` and `config.cf` are not ordinary modules. They are resolved by
filename before any language/plugin/UI module is executed.

Both use the same lookup order:

```text
active theme -> theme root -> default theme
```

The first existing file wins.

### `color.cf`

A palette is required. ChromaFlow must find a `color.cf` somewhere in the
reserved-file fallback chain.

The selected file must return a table:

```lua
return {
  bg = "#111318",
  fg = "#d6d6d6",
  comment = "#73829a",
}
```

The returned table becomes the palette shared by all modules compiled during
that theme load.

A root-level `color.cf` is therefore useful when several themes intentionally
share one palette unless they override it locally.

### `config.cf`

`config.cf` is optional. If none exists in the fallback chain, ChromaFlow uses
an empty config internally.

When a `config.cf` exists, it must return a table.

A local file containing only:

```lua
return {}
```

is meaningful: it stops root/default config fallback while keeping the normal
default target behavior.

This is useful when the default theme has a restrictive `config.cf`, but the
active theme should not inherit those restrictions.

The individual `config.cf` fields are described in
[`getting-started.md`](getting-started.md).

## Ordinary module files

Every other top-level `.cf` file inside a theme directory is treated as a module
candidate.

The filename does not determine the module kind. The returned setup call does:

```lua
return l.setup("lua", { ... })
```

is a Lua language module regardless of whether the file is named:

```text
lua.cf
lang-lua.cf
syntax.cf
anything.cf
```

Likewise:

```lua
return p.setup("telescope", { ... })
```

is a plugin module, and:

```lua
return u.setup({ ... })
```

is a UI module.

A `.cf` file that does not return a valid language/plugin/UI module is ignored
as a normal theme module and reported as a diagnostic hint. A module that fails
to compile is reported as an error without turning its filename into a fallback
identity.

## Module identity

Fallback for ordinary modules is based on **semantic module identity**, not on
filenames.

The identities are:

| Setup call | Module identity |
| --- | --- |
| `l.setup("lua", ...)` | Language identity `"lua"` |
| `l.setup("python", ...)` | Language identity `"python"` |
| `l.setup(nil, ...)` | Global-language identity |
| `p.setup("telescope", ...)` | Plugin identity `"telescope"` |
| `u.setup(...)` | UI identity |

This means a file named `a.cf` in one theme can replace a file named `b.cf` in
the default theme when both return the same module identity.

Conversely, two files with identical filenames do not replace one another when
they return different identities.

## The active pass comes first

ChromaFlow first enumerates the active theme's top-level `.cf` module files in
filename order and compiles **all** of them.

During this pass module identities are collected, but they do not suppress
other active modules.

Therefore this is valid:

```text
dusk/
├── 10-lua-base.cf
├── 20-lua-extra.cf
└── 30-lua-special.cf
```

when all three files return:

```lua
l.setup("lua", { ... })
```

All three active Lua modules are compiled.

The same is true for several active plugin modules with the same plugin name and
for several active UI modules.

This lets a theme split one semantic scope across several files without making
the filename part of the API.

## Fallback is decided only after the full active pass

Only after every active module has been compiled does ChromaFlow start the
default-theme fallback pass.

At that point the completed active identity registry becomes a skip filter.

For example, if the active theme contains even one:

```lua
l.setup("lua", { ... })
```

then **all** default-theme modules with language identity `"lua"` are skipped.

Fallback is therefore not a per-group merge.

If the active Lua module defines only `comment`, ChromaFlow does not later pull
`function`, `variable` or other missing Lua groups from the default Lua module.
The active theme has claimed the complete Lua module identity.

The same rule applies to plugin identities and to the UI identity.

## Several fallback modules for one uncovered identity are allowed

Fallback modules do not extend the active registry.

That detail is intentional.

If the active theme contains no Lua module and the default theme contains:

```text
base/
├── lua-base.cf
├── lua-extra.cf
└── lua-special.cf
```

with all three returning `l.setup("lua", ...)`, all three fallback modules are
allowed to compile.

The fallback pass asks only one question:

> Was this identity claimed by the active theme?

It does not ask whether an earlier fallback file already used the identity.

## File order and declaration order

Top-level `.cf` module filenames are sorted before compilation.

Within a module, declarations keep their declaration order.

ChromaFlow then applies all compiled highlight actions in one global stable
priority pass.

The ordering rule is:

| Priority | Compile order |
| --- | --- |
| Lower | Earlier |
| Higher | Later |

and for equal priorities:

| Declaration order | Apply order |
| --- | --- |
| Earlier compiled action | Earlier |
| Later compiled action | Later |

Because the later write sees the same concrete highlight target last, it wins a
normal same-priority collision.

So for two active files:

```text
10-lua-base.cf
20-lua-extra.cf
```

if both ultimately style the same target with the same priority, the relevant
action from `20-lua-extra.cf` is later in the global sequence and therefore wins.

A higher explicit action priority wins regardless of filename order.

Priority is therefore the deliberate override mechanism; filename/declaration
order is the stable tie-breaker.

## Active/default identity filtering is separate from action precedence

The active/default registry decides **which modules exist in the compiled
set**. It is not a second highlight-priority system.

Once the allowed active and fallback modules have been compiled, their actions
all participate in the same global priority/sequence pass.

Normally semantic identities keep those modules naturally separated. If two
different module identities intentionally target the same concrete highlight,
normal priority and sequence rules decide the final result.

## Root fallback is not module fallback

The theme root itself participates in fallback only for the reserved resources:

```text
color.cf
config.cf
runtime/<name>.cf
```

It is not scanned as another directory of ordinary language/plugin/UI modules.

This distinction makes the root useful for shared infrastructure without
silently injecting normal theme modules into every theme.

## Runtime modules

Runtime modules live below a `runtime/` directory and use logical names.

For a requested runtime module named `pulse`, ChromaFlow searches:

```text
active theme/runtime/pulse.cf
-> theme root/runtime/pulse.cf
-> default theme/runtime/pulse.cf
```

The first existing file wins.

Runtime modules are not part of the normal eager module scan. They are loaded
only when that logical runtime module has actually been requested through the
runtime API.

A runtime file must return a runtime definition created with
`hl.runtime.setup(...)`.

This keeps normal static themes from paying for runtime modules they never use.

Runtime modules are covered in detail in [`runtime.md`](runtime.md).

## Practical variant patterns

The fallback model supports several useful layouts.

### Palette-only variant

An active theme can provide only a different `color.cf` and inherit ordinary
module identities from the default theme.

```text
base/
├── color.cf
├── lua.cf
└── ui.cf

warm/
└── color.cf
```

With `base` as default and `warm` as active, `warm/color.cf` supplies the
palette while the Lua/UI modules come from `base`.

### Config-only variant

An active theme can provide only `config.cf` and inherit the default palette and
modules.

### Replace one language only

An active theme can provide one or several `l.setup("lua", ...)` modules.
Those active Lua modules all compile, while every default Lua module is skipped.
Other uncovered default language/plugin/UI identities still fall back normally.

### Split one active identity across files

A large language scope can be split across several freely named files:

```text
10-lua-core.cf
20-lua-builtins.cf
30-lua-special.cf
```

All may return `l.setup("lua", ...)`. Same-priority collisions follow normal
stable order; explicit priorities can override that order when needed.

## Summary

The important rules are:

- `.cf-theme` selects a default and an active theme.
- `color.cf` and `config.cf` are reserved filenames.
- reserved files use `active -> root -> default` fallback.
- `color.cf` is required; `config.cf` is optional.
- `return {}` in a local `config.cf` deliberately blocks config fallback.
- ordinary module filenames are free.
- ordinary fallback is based on `l.setup` / `p.setup` / `u.setup` identity.
- all active modules compile before fallback is considered.
- duplicate identities inside the active theme are allowed.
- an identity claimed by active suppresses every default module of that identity.
- fallback modules do not suppress other fallback modules of the same uncovered identity.
- final highlight collisions are resolved globally by priority, then stable action order.
- runtime modules use their own `active -> root -> default` name lookup and are opt-in.
