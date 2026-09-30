# Runtime modules

## Contents

- [Runtime modules are opt-in](#runtime-modules-are-opt-in)
- [Runtime files and fallback](#runtime-files-and-fallback)
- [Defining a runtime module](#defining-a-runtime-module)
- [Runtime groups are actions](#runtime-groups-are-actions)
- [`r.groups` and `r.g`](#rgroups-and-rg)
- [What a runtime group may contain](#what-a-runtime-group-may-contain)
- [Runtime targets](#runtime-targets)
- [Semantic targets address all concrete names](#semantic-targets-address-all-concrete-names)
- [`apply()`](#apply)
- [`replace()`](#replace)
- [`clear()`](#clear)
- [`reset()`](#reset)
- [One runtime state, not one state per module](#one-runtime-state-not-one-state-per-module)
- [Overlapping targets](#overlapping-targets)
- [Runtime is a sparse diff](#runtime-is-a-sparse-diff)
- [Runtime survives theme reloads](#runtime-survives-theme-reloads)
- [Runtime actions are validated before destructive reload](#runtime-actions-are-validated-before-destructive-reload)
- [Runtime and `ColorScheme`](#runtime-and-colorscheme)
- [Runtime changes are transactional](#runtime-changes-are-transactional)
- [Runtime functions](#runtime-functions)
- [Runtime function signature](#runtime-function-signature)
- [Function context](#function-context)
- [Timed runtime functions](#timed-runtime-functions)
- [One tick interval per runtime action](#one-tick-interval-per-runtime-action)
- [Timer lifecycle](#timer-lifecycle)
- [Unrelated runtime changes do not reevaluate dynamic actions](#unrelated-runtime-changes-do-not-reevaluate-dynamic-actions)
- [Runtime functions are module-local](#runtime-functions-are-module-local)
- [Custom runtime exports](#custom-runtime-exports)
- [Runtime and pipelines](#runtime-and-pipelines)
- [A complete static runtime example](#a-complete-static-runtime-example)
- [A complete timed runtime example](#a-complete-timed-runtime-example)
- [Raw runtime targets](#raw-runtime-targets)
- [Commands](#commands)
- [Runtime modules and the watcher](#runtime-modules-and-the-watcher)
- [Runtime versus Picker previews](#runtime-versus-picker-previews)
- [Practical design rule](#practical-design-rule)

Runtime modules are ChromaFlow's dynamic highlight layer.

Normal language, plugin, and UI modules build the theme itself; `raw:*` declarations
inside those modules can write exact Neovim highlight names. Runtime modules add a
sparse dynamic layer on top of the highlight state that currently exists in Neovim.
They can temporarily apply, replace, clear, or reset styles while Neovim is running.

For semantic language/plugin/UI targets, that base comes from the materialized
ChromaFlow theme. A raw runtime target is different: it may bind directly to an
exact highlight group that already exists in Neovim even when ChromaFlow never
created that group with `raw:group()`.

Typical uses include:

- temporary focus or selection states,
- mode-dependent highlighting,
- plugin state that changes after startup,
- short-lived visual emphasis,
- stateful highlight transformations,
- and deliberately animated effects.

The important mental model is:

```text
normal ChromaFlow theme
        ↓
final ColorScheme callbacks
        ↓
runtime sparse overlay
```

Runtime does not rebuild the whole theme for every change. It keeps a sparse
set of overrides and only rewrites the concrete highlight groups affected by
those overrides.

## Runtime modules are opt-in

A runtime module is loaded only after its logical name has been requested.

From normal Lua code:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime("actions")
```

This requests the runtime module named `actions`.

The returned `r` is a stable runtime-module handle. It may be created before a
theme has been applied; ChromaFlow can resolve the actual runtime file later
when the active/default theme is known.

The same handle also works when requested after a theme is already active. In
that case ChromaFlow loads the matching runtime module lazily.

Runtime module names are logical names, not paths:

```lua
hl.runtime("actions")
hl.runtime("focus")
hl.runtime("status")
```

Do not include `.cf`:

```lua
-- wrong
hl.runtime("actions.cf")
```

and do not use path separators in the name.

## Runtime files and fallback

For a requested module named:

```text
actions
```

ChromaFlow looks for exactly:

```text
runtime/actions.cf
```

through this fallback chain:

```text
active theme/runtime/actions.cf
        ↓
theme root/runtime/actions.cf
        ↓
default theme/runtime/actions.cf
```

The **first existing file wins**.

For example:

```text
themes/
├── .cf-theme
├── runtime/
│   └── actions.cf
├── dark/
│   ├── color.cf
│   └── runtime/
│       └── actions.cf
└── fallback/
    ├── color.cf
    └── runtime/
        └── actions.cf
```

If `dark` is active and contains `dark/runtime/actions.cf`, that file is used.
The root and default versions are ignored.

If the active file is absent, the root file is used. If that is also absent,
the default file is used.

Runtime definitions are **not merged across the fallback chain**.

If the root version contains only:

```lua
r:group("focus", { underline = true })
```

then an action named `dim` that exists only in the default version is not
silently added to the root definition.

This differs from normal theme modules, where fallback is based on semantic
language/plugin/UI identity. Runtime modules are explicitly requested by name,
so their filename is part of their identity.

The top-level `runtime/` directory is infrastructure and is not a selectable
theme.

## Defining a runtime module

Inside a runtime file, use `hl.runtime` without a module-name argument:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime

return r.setup({
  r:group("dim", {
    pipeline = {
      hl.brightness.fg(-20),
    },
  }),

  r:group("focus", {
    bold = true,
  }),
})
```

During loading, ChromaFlow temporarily turns `hl.runtime` into the definition
object for that one runtime module.

That gives the runtime file:

```text
r:group(...)
r:func(...)
r.setup(...)
```

and its own module-local export namespace.

The file must return:

```lua
r.setup({ ... })
```

A runtime module may call `r.setup()` only once per load.

## Runtime groups are actions

A declaration such as:

```lua
r:group("focus", {
  bold = true,
  underline = true,
})
```

defines a reusable **runtime action** named `focus`.

It does not target a highlight group by itself.

The target is chosen later:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime("actions")

r.apply(hl.ui.NormalFloat, r.groups.focus)
```

This separation is intentional:

| Term | Meaning |
| --- | --- |
| Runtime action | What style transformation to perform |
| Runtime target | Which semantic highlight target to modify |

The same action can therefore be reused for different targets.

## `r.groups` and `r.g`

Runtime actions are exposed through:

```lua
r.groups.<name>
```

For example:

```lua
r.groups.dim
r.groups.focus
```

`r.g` is an alias:

```lua
r.g == r.groups
```

so this is equivalent:

```lua
r.apply(target, r.g.focus)
```

The action handle is stable. If a later theme reload selects a different
`runtime/actions.cf` through active/root/default fallback, the same public
handle resolves against the newly selected definition.

## What a runtime group may contain

A runtime group may contain normal `nvim_set_hl()` style fields and/or a
ChromaFlow pipeline:

```lua
r:group("focus", {
  fg = c.accent,
  bold = true,
  nocombine = true,

  pipeline = {
    hl.lighten.fg(10),
  },
})
```

Runtime groups are deliberately smaller than normal theme declarations.
They are not resolver declarations and do not have their own semantic target
metadata.

For example, a runtime action does not define:

```text
style_targets
style_targets_clear
types
typemods
priority
link
clear
```

Runtime actions do not choose their own target. The caller applies them to a
runtime target handle. Semantic language/plugin/UI targets must already exist in
the materialized ChromaFlow theme; raw targets may instead refer to any exact
highlight group that currently exists in Neovim.

## Runtime targets

Normal ChromaFlow DSL namespaces also expose runtime target handles when they
are indexed outside a `setup()` declaration.

### UI target

```lua
local target = hl.ui.NormalFloat
```

### Language target

```lua
local target = hl.language.lua.variable
```

### Language TypeMod target

```lua
local target = hl.language.lua.variable.readonly
```

### Plugin target

```lua
local target = hl.plugin["example-plugin"].ExampleItem
```

### Plugin TypeMod target

```lua
local target = hl.plugin["example-plugin"].ExampleItem.active
```

### Raw target

```lua
local target = hl.raw["ExampleExactGroup"]
```

These are opaque handles. Merely creating one does not write a highlight.

Creating a runtime handle never creates a new highlight group by itself.

For semantic language/plugin/UI targets, a normal runtime operation requires the
target to be materialized by the current ChromaFlow theme. For example:

```lua
local target = hl.ui.DoesNotExist
```

is a valid handle, but applying a runtime action fails if the current theme never
materialized that semantic target.

Raw targets use a different rule. `hl.raw["Name"]` addresses the exact Neovim
highlight name. If that group already exists, runtime can adopt its current
effective style as the base even when no ChromaFlow `raw:group("Name", ...)`
declaration exists. If the exact group does not exist, the runtime operation
fails rather than inventing it.

## Semantic targets address all concrete names

Runtime targets preserve ChromaFlow's semantic identity.

Suppose the normal Lua theme contains:

```lua
l:group("variable", {
  fg = c.variable,
})
```

and that declaration materializes the semantic chain:

```text
luaIdentifier
@variable.lua
@lsp.type.variable.lua
```

Then:

```lua
local target = hl.language.lua.variable
r.replace(target, r.groups.focus)
```

addresses all concrete highlight groups belonging to that materialized target.

Runtime does **not** run the resolver again to rediscover semantic mappings.
It uses the concrete names already produced by the compiled theme action.

That keeps runtime work small and makes the normal theme remain the source of
truth for semantic targets. Raw targets instead use the exact existing Neovim
highlight as their base.

## `apply()`

`apply()` builds the runtime action on top of the target's captured base style.
For semantic targets this is the normal theme style; for an external raw target
it is the effective style read from Neovim:

```lua
r.apply(target, r.groups.dim)
```

For example, if the theme base is conceptually:

```lua
{
  fg = 0x6080A0,
  bg = 0x101010,
}
```

and the runtime action is:

```lua
r:group("focus", {
  bold = true,
})
```

then:

```lua
r.apply(target, r.groups.focus)
```

produces conceptually:

```lua
{
  fg = 0x6080A0,
  bg = 0x101010,
  bold = true,
}
```

The untouched base fields remain.

### `apply()` does not accumulate drift

Every `apply()` starts from the captured base for that target, not from the
previous runtime result.

So an action such as:

```lua
r:group("dim", {
  pipeline = {
    hl.brightness.fg(-20),
  },
})
```

can safely be applied repeatedly:

```lua
r.apply(target, r.groups.dim)
r.apply(target, r.groups.dim)
r.apply(target, r.groups.dim)
```

The color is not darkened three times.

Each call recomputes the action from the same current theme base.

## `replace()`

`replace()` builds the action without inheriting the captured base style:

```lua
r.replace(target, r.groups.focus)
```

If `focus` is:

```lua
r:group("focus", {
  bold = true,
})
```

then the runtime style contains only that action's result.

Theme-base `fg`, `bg`, and other fields are not kept unless the action itself
sets or creates them.

This makes the difference concise:

| Operation | Result |
| --- | --- |
| `apply` | Theme base + runtime action |
| `replace` | Runtime action only |

## `clear()`

`clear()` temporarily clears the concrete highlight groups represented by a
runtime target:

```lua
r.clear(target)
```

Conceptually, the affected groups receive an empty highlight definition.

For a semantic target, every concrete name belonging to that target is cleared.

The clear itself becomes part of the runtime overlay and survives until it is
reset or replaced.

## `reset()`

`reset()` removes the runtime override for one target:

```lua
r.reset(target)
```

It returns:

| Return | Meaning |
| --- | --- |
| `true` | An override existed and was removed |
| `false` | That target had no runtime override |

After reset, ChromaFlow restores the target from its captured base, taking other
still-active overlapping runtime overrides into account. For semantic targets
that base comes from the normal theme. For a raw target adopted from Neovim it is
the effective style that existed before the runtime override was applied.

The normal theme does not need to be recompiled or re-applied.

## One runtime state, not one state per module

Runtime overrides belong to one process-wide runtime layer.

The runtime module handle only supplies named actions. The target itself has
one current override slot.

For example:

```lua
local a = hl.runtime("actions")
local b = hl.runtime("effects")
local target = hl.ui.NormalFloat

a.apply(target, a.groups.dim)
b.replace(target, b.groups.focus)
```

The second operation replaces the runtime override for that same semantic
target.

Likewise, `reset()` and `clear()` are global target operations even though they
are conveniently exposed on every runtime-module handle.

## Overlapping targets

Different semantic targets can sometimes resolve to overlapping concrete
highlight names.

ChromaFlow keeps runtime overrides in change order. When affected groups are
recomposed, later runtime changes win on concrete names where active overrides
overlap.

If the later override is reset, an earlier still-active override can become
visible again.

This is different from repeatedly transforming the visible result. Runtime
recomposition always rebuilds from captured bases plus the currently active
override set.

## Runtime is a sparse diff

The normal materialized theme remains untouched in ChromaFlow's base caches.
External raw bases are likewise read from Neovim without turning them into normal
ChromaFlow theme declarations.

Runtime keeps only the concrete highlight names it currently overrides:

| State | Contents |
| --- | --- |
| Semantic theme base / existing raw base | Unchanged |
| Runtime overlay | Only modified targets |
| Neovim visible state | Base + runtime overlay |

This matters for both correctness and performance.

Resetting a runtime target does not need to reconstruct the entire colorscheme.
ChromaFlow can remove the sparse diff and write the current semantic base back
directly.

It also means runtime changes do not become the new base for later runtime
`apply()` calls.

## Runtime survives theme reloads

Normal runtime action state survives a normal ChromaFlow theme reload.

Suppose:

```lua
r.apply(hl.ui.NormalFloat, r.groups.dim)
```

is active and the theme is then reloaded with a different base color.

ChromaFlow:

1. rebuilds the normal theme,
2. resolves the runtime module again through active/root/default fallback,
3. lets the complete `ColorScheme` callback chain finish,
4. captures the new final base for every surviving override,
5. re-evaluates the active runtime action against that base,
6. and restores the sparse runtime overlay.

For semantic targets the new base comes from the freshly applied theme. For an
external raw target ChromaFlow re-reads the exact Neovim highlight after the
callbacks, so a plugin or colorscheme callback may establish a new raw base. The
old runtime-rendered color is not used as the new base.

That prevents drift across reloads.

## Runtime actions are validated before destructive reload

An active `apply()` or `replace()` override refers to a named runtime action.
If a newly compiled runtime module no longer contains that action, the new
theme compile fails before the destructive colorscheme apply begins.

For example, if this override is active:

```lua
r.apply(target, r.groups.dim)
```

and a new `runtime/actions.cf` removes `dim`, ChromaFlow rejects that reload
instead of first destroying the visible theme and discovering the missing
action afterwards.

This keeps active runtime state transactional across theme changes.

## Runtime and `ColorScheme`

Runtime has explicit handling for Neovim's `ColorScheme` transition.

During a ChromaFlow apply, the order is conceptually:

```text
ColorSchemePre
↓
normal highlight reset
↓
normal ChromaFlow theme materialization
↓
ColorScheme callbacks
↓
runtime overlay recomposition
↓
Tree-sitter/LSP consumer refresh
```

Runtime calls made from a `ColorScheme` callback update runtime state, but their
visible writes are deferred until the entire callback chain has completed.

That matters when another later callback modifies the same normal highlight.
Runtime then uses the **final callback result** as its base rather than an
intermediate state.

For example:

```lua
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    r.apply(hl.ui.NormalFloat, r.groups.dim)
  end,
})
```

is safe even if another `ColorScheme` callback registered later adjusts
`NormalFloat`. The runtime action is composed after the normal callback chain
finishes.

## Runtime changes are transactional

Outside a colorscheme transition, ChromaFlow validates the concrete target
before publishing a new override.

So this:

```lua
r.apply(hl.ui.DoesNotExist, r.groups.focus)
```

cannot leave behind a half-created runtime override if the semantic target is
not materialized by the current theme. The same transactional rule applies to a
raw target whose exact Neovim highlight name does not exist.

Likewise, if style computation fails, ChromaFlow restores the previous override
state instead of committing the failed replacement.

During a `ColorScheme` callback, target resolution is intentionally deferred
until the final normal theme state exists. This permits runtime state to be set
for a target that is being introduced by the theme currently transitioning
into place.

## Runtime functions

Runtime actions may contain functions that are evaluated while the runtime
style is built.

Define a function as an export on the runtime definition object:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime

function r.emphasize(style, ctx)
  style.bold = true
  return style
end

return r.setup({
  r:group("focus", {
    pipeline = {
      r:func("emphasize"),
    },
  }),
})
```

`r:func("emphasize")` is the explicit adapter that places the exported runtime
function into a ChromaFlow pipeline.

A plain Lua function is not a valid pipeline operation:

```lua
-- invalid
r:group("focus", {
  pipeline = {
    function(style)
      style.bold = true
      return style
    end,
  },
})
```

Use:

```lua
r:func("emphasize")
```

instead.

## Runtime function signature

A runtime function receives:

```lua
function(style, ctx)
  ...
end
```

`style` is the full style built up to that point in the pipeline.

The function may mutate it:

```lua
function r.emphasize(style)
  style.bold = true
end
```

Returning `nil` keeps the mutated style.

Or it may return a replacement style table:

```lua
function r.emphasize(style)
  return {
    fg = style.fg,
    bold = true,
  }
end
```

Returned/mutated styles are validated against supported `nvim_set_hl()` style
fields.

For GUI colors, ChromaFlow's normal internal representation remains packed
numeric color values. Hex strings returned by a function are accepted and
normalized at the style boundary when needed.

`ctermfg` and `ctermbg` are exposed to runtime functions as actual terminal
palette indices, not ChromaFlow's temporary packed working colors.

## Function context

The second argument contains timing information:

```lua
function r.effect(style, ctx)
  print(ctx.frame)
  print(ctx.tick)
  print(ctx.delta)
  print(ctx.elapsed)
  return style
end
```

The fields are:

| Context field | Meaning |
| --- | --- |
| `frame` | Current frame number, starting at `0` |
| `tick` | This runtime function's configured interval in milliseconds, or `nil` |
| `delta` | Milliseconds since the previous timed evaluation |
| `elapsed` | Milliseconds since this override's timing started |

For a normal untimed runtime function, the first evaluation has:

| Context field | Initial value |
| --- | --- |
| `frame` | `0` |
| `tick` | `nil` |
| `delta` | `0` |
| `elapsed` | `0` |

## Timed runtime functions

A runtime function becomes timed by indexing the `r:func()` operation with a
positive integer number of milliseconds:

```lua
r:func("pulse")[100]
```

For example:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime

function r.pulse(style, ctx)
  style.bold = (ctx.frame % 2) == 0
  return style
end

return r.setup({
  r:group("pulse", {
    pipeline = {
      r:func("pulse")[100],
    },
  }),
})
```

When that action is applied:

```lua
local runtime = hl.runtime("effects")
runtime.apply(hl.ui.NormalFloat, runtime.groups.pulse)
```

ChromaFlow evaluates frame `0` immediately, then reevaluates the action at the
configured interval.

The timer belongs to the active target override, not to the runtime module as a
whole.

## One tick interval per runtime action

A runtime action has one timing clock.

Multiple runtime functions inside the same action may share the same interval:

```lua
pipeline = {
  r:func("a")[100],
  r:func("b")[100],
}
```

but conflicting intervals in one action are rejected:

```lua
-- invalid
pipeline = {
  r:func("a")[100],
  r:func("b")[250],
}
```

Otherwise `frame`, `delta`, and `elapsed` would have no unambiguous action
clock.

## Timer lifecycle

When an active timed override is changed or removed, its previous timer is
stopped.

That includes:

```text
apply another action to the same target
replace the target
clear the target
reset the target
theme reload
```

After a normal theme reload, surviving timed overrides restart from a fresh
runtime timing context against the new theme base.

If a timed reevaluation throws an error, ChromaFlow stops that timer rather
than continuing to fire a broken action indefinitely.

## Unrelated runtime changes do not reevaluate dynamic actions

Runtime recomposition is affected-target based.

If target A has a dynamic runtime function and target B changes independently,
ChromaFlow first checks whether A's concrete names intersect the affected set.
If they do not, A's runtime function is not evaluated again.

This is important for runtime functions with state or nontrivial work:

```text
change target B
    ↓
find affected concrete names
    ↓
ignore override A if it does not intersect
    ↓
rebuild only relevant overrides
```

Runtime therefore remains sparse not only in what it writes, but also in which
dynamic actions it reevaluates.

## Runtime functions are module-local

Two runtime modules may export a function with the same name:

| Runtime module | Export |
| --- | --- |
| `runtime/actions.cf` | `r.alert` |
| `runtime/effects.cf` | `r.alert` |

They remain separate definitions.

An `r:func("alert")` operation belongs to the runtime module in which it was
created and may not be inserted into a different runtime module's action.

This avoids accidental function-namespace collisions between runtime files.

## Custom runtime exports

A runtime definition may export additional values and functions by assigning
them to `r`:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime

r.calls = 0

function r.mark(style)
  r.calls = r.calls + 1
  style.bold = true
  return style
end

return r.setup({
  r:group("mark", {
    pipeline = {
      r:func("mark"),
    },
  }),
})
```

After the module is loaded, those exports are visible through its normal
runtime handle:

```lua
local runtime = hl.runtime("actions")
print(runtime.calls)
```

Exports are module-local and follow the currently loaded runtime definition.

These names are reserved by the runtime API and cannot be replaced by custom
exports:

```text
group
func
setup
groups
g
apply
replace
reset
clear
```

## Runtime and pipelines

A runtime group uses the normal ChromaFlow pipeline engine:

```lua
r:group("dim", {
  pipeline = {
    hl.brightness.fg(-20),
    hl.opacity.bg(90),
  },
})
```

Operations execute in list order, exactly like normal theme pipelines.

Runtime functions may be mixed with normal pipeline operations:

```lua
r:group("dynamic", {
  pipeline = {
    hl.lighten.fg(5),
    r:func("adjust"),
    hl.mix.bg(10, c.black),
  },
})
```

The runtime function sees the style produced by all earlier operations and its
result becomes the input for later operations.

For ordinary pipeline behavior, see [`pipeline.md`](pipeline.md).

## A complete static runtime example

Runtime file:

```text
active-theme/runtime/actions.cf
```

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local r = hl.runtime

return r.setup({
  r:group("dim", {
    pipeline = {
      hl.brightness.fg(-18),
      hl.brightness.bg(-8),
    },
  }),

  r:group("focus", {
    fg = c.accent,
    bold = true,
  }),
})
```

Normal Lua code:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime("actions")
local target = hl.ui.NormalFloat

r.apply(target, r.groups.dim)

-- later
r.replace(target, r.groups.focus)

-- later
r.reset(target)
```

The normal theme remains the base throughout the sequence.

## A complete timed runtime example

Runtime file:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime

function r.blink(style, ctx)
  style.bold = (ctx.frame % 2) == 0
  style.underline = (ctx.frame % 2) ~= 0
  return style
end

return r.setup({
  r:group("blink", {
    pipeline = {
      r:func("blink")[250],
    },
  }),
})
```

Consumer:

```lua
local hl = require("cf.hl.setup")
local effects = hl.runtime("effects")

local target = hl.ui.Search

effects.apply(target, effects.groups.blink)

-- stop the timer and restore the normal theme target
effects.reset(target)
```

## Raw runtime targets

The Lua runtime API also accepts raw target handles:

```lua
local target = hl.raw["ExampleExactGroup"]
r.apply(target, r.groups.focus)
```

Raw still means literal: there is no semantic Vim/Tree-sitter/LSP expansion for
that target.

A raw runtime target does **not** require a matching `raw:group()` declaration.
If the exact highlight group already exists in Neovim, ChromaFlow reads its
current effective style and uses that as the runtime base:

```lua
-- created by Neovim, another colorscheme, or a plugin
vim.api.nvim_set_hl(0, "ExampleExactGroup", { fg = 0x80A0C0 })

local target = hl.raw["ExampleExactGroup"]
r.apply(target, r.groups.focus)
r.reset(target) -- restores the captured effective style
```

Raw runtime still does not create arbitrary groups implicitly. If the exact
highlight name does not currently exist, `apply()`, `replace()`, or `clear()`
fails instead of materializing it.

After a theme reload, the raw target catalog is rebuilt after the complete
`ColorScheme` callback chain. A plugin that recreates or changes the group in a
callback therefore establishes the new raw base before surviving runtime
overrides are recomposed.

For literal theme declarations, see [`raw.md`](raw.md).

## Commands

ChromaFlow also exposes runtime operations as user commands.

Apply an action:

```vim
:CFApply r.actions.dim u.NormalFloat
```

Replace a target:

```vim
:CFReplace r.actions.focus l.lua.variable
```

Reset a target:

```vim
:CFReset l.lua.variable
```

Clear a target:

```vim
:CFClear u.NormalFloat
```

Command action syntax is:

```text
r.<module>.<action>
```

Command target syntax is:

```text
l.<language>.<type>[.<typemod>]
p.<plugin>.<type>[.<typemod>]
u.<type>[.<typemod>]
```

The command parser currently exposes language, plugin, and UI targets. Raw
runtime targets are available through the Lua API instead.

## Runtime modules and the watcher

ChromaFlow's filesystem watcher treats runtime directories as their own watch
scope.

It watches runtime files in the same three fallback locations:

```text
active theme/runtime/
theme root/runtime/
default theme/runtime/
```

A runtime directory that appears after watcher startup can also be picked up
without rebuilding the entire watcher from scratch.

This keeps runtime definitions part of the normal theme-editing workflow while
preserving their separate loading semantics.

## Runtime versus Picker previews

CFPick also uses ChromaFlow's sparse runtime machinery for live style previews,
but picker previews have a deliberately different lifecycle.

Picker edits are temporary preview state. A normal theme reload discards those
preview writes.

Explicit runtime action overrides created through:

```lua
r.apply(...)
r.replace(...)
r.clear(...)
```

are persistent runtime state and are recomposed after a normal theme reload.

So although both paths share the efficient sparse-write infrastructure, they
are not the same kind of state.

The picker-specific workflow is documented separately in
[`picker.md`](picker.md).

## Practical design rule

Use normal theme modules for stable theme policy:

```text
language / plugin / ui
+ raw:* declarations when an exact highlight name is needed
```

Use runtime modules when the final style depends on session state after the
theme already exists:

| Need | Use |
| --- | --- |
| Stable theme declaration | Normal module |
| Live temporary state | Runtime action |

Runtime is intentionally a post-theme layer rather than a second theme system.
The base remains inspectable and resettable, semantic targets keep their normal
identity, and only the highlights that actually change need to be recomposed.
