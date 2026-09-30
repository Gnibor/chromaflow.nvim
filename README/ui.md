# UI modules

## Contents

- [Targets first](#targets-first)
- [`style_targets`](#style_targets)
- [Target precedence](#target-precedence)
- [`style_targets_clear`](#style_targets_clear)
- [`u.setup(spec)`](#usetupspec)
- [UI fallback identity](#ui-fallback-identity)
- [Splitting UI across files](#splitting-ui-across-files)
- [`u:group(name, spec)`](#ugroupname-spec)
- [Normal UI styles](#normal-ui-styles)
- [Inline links](#inline-links)
- [Standalone `u:link(source, target)`](#standalone-ulinksource-target)
- [`types`](#types)
- [`typemods`](#typemods)
- [Module-level `mods`](#module-level-mods)
- [Pipelines](#pipelines)
- [`priority`](#priority)
- [Repeated UI declarations](#repeated-ui-declarations)
- [Style deduplication](#style-deduplication)
- [`raw` inside a UI module](#raw-inside-a-ui-module)
- [Error isolation](#error-isolation)
- [Runtime target access](#runtime-target-access)
- [Practical core UI module](#practical-core-ui-module)
- [Minimal template](#minimal-template)

UI modules describe Neovim's global editor interface: normal windows, floating
windows, status lines, menus, search highlights, diagnostics, spelling groups,
and other highlight groups that are not tied to one language or one plugin.

A typical UI module looks like this:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui

return u.setup({
  u:group("Normal", {
    fg = c.fg,
    bg = c.bg,
  }),

  u:group("NormalFloat", {
    fg = c.fg,
    bg = c.line,
  }),

  u:link("NormalNC", "Normal"),
})
```

Unlike language and plugin modules, `u.setup()` has no name argument. All UI
modules belong to one shared **UI fallback identity**.

The filename is still arbitrary. A file called `core-ui.cf`, `editor.cf`, or
anything else ending in `.cf` may return `u.setup({ ... })`.

For theme loading and fallback rules in general, see
[`theme-structure.md`](theme-structure.md).

## Targets first

UI modules have these resolver target defaults:

| Target | UI default |
| --- | ---: |
| `vim` | `true` |
| `ts` | `false` |
| `lsp` | `false` |

That matches the common UI case: groups such as `Normal`, `Visual`, `Pmenu`,
`StatusLine`, and `DiagnosticError` are ordinary Neovim highlight groups.

Therefore this is enough for a normal UI module:

```lua
return u.setup({
  u:group("Normal", {
    fg = c.fg,
    bg = c.bg,
  }),
})
```

You do **not** have to write the default policy explicitly.

The same module could be written as:

```lua
return u.setup({
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  u:group("Normal", {
    fg = c.fg,
    bg = c.bg,
  }),
})
```

Both mean the same thing.

### What that becomes

With the default UI target policy:

```lua
u:group("Normal", {
  fg = c.fg,
  bg = c.bg,
})
```

is conceptually materialized as:

```lua
vim.api.nvim_set_hl(0, "Normal", {
  fg = "...",
  bg = "...",
})
```

A UI link:

```lua
u:link("NormalNC", "Normal")
```

or equivalently:

```lua
u:group("NormalNC", {
  link = "Normal",
})
```

becomes conceptually:

```lua
vim.api.nvim_set_hl(0, "NormalNC", {
  link = "Normal",
})
```

These examples show the semantic shape of the result. ChromaFlow interns equal
complete styles, so the final physical link layout may differ when an identical
style is already materialized elsewhere.

That deduplication does not change the semantic identity of the declaration.

## `style_targets`

`style_targets` controls which resolver layers a UI module may write.

At module level:

```lua
return u.setup({
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  ...
})
```

At group level:

```lua
u:group("ExampleCapture", {
  fg = c.orange,

  style_targets = {
    vim = false,
    ts = true,
    lsp = false,
  },
})
```

For that group the unknown literal resolver name is conceptually:

| Layer | Concrete name |
| --- | --- |
| Vim | `ExampleCapture` |
| Tree-sitter | `@ExampleCapture` |
| LSP | `@lsp.type.ExampleCapture` |

With only the Tree-sitter target enabled, the style is therefore written to the
Tree-sitter form:

```lua
vim.api.nvim_set_hl(0, "@ExampleCapture", {
  fg = "...",
})
```

This is an advanced UI case. Normal editor UI groups generally use the default
Vim-only policy.

## Target precedence

For every target system, ChromaFlow chooses the effective UI target in this
order:

1. Group `style_targets`, if that key is explicitly present.
2. Module `style_targets`, if that key is explicitly present.
3. UI default.

The UI defaults are:

| Target | UI default |
| --- | ---: |
| `vim` | `true` |
| `ts` | `false` |
| `lsp` | `false` |

After that, the global target boundary from `config.cf` is enforced.

So a group may override its module:

```lua
return u.setup({
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  u:group("ExampleCapture", {
    fg = c.orange,

    style_targets = {
      vim = false,
      ts = true,
    },
  }),
})
```

but it still cannot re-enable a target globally disabled by `config.cf`.

The effective hierarchy is therefore:

```text
group -> module -> UI default -> config hard boundary
```

## `style_targets_clear`

Clearing is independent from writing.

```lua
return u.setup({
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  style_targets_clear = {
    ts = true,
    lsp = true,
  },

  u:group("Normal", {
    fg = c.fg,
    bg = c.bg,
  }),
})
```

The write policy says:

| Target | Result |
| --- | --- |
| Vim | Write |
| Tree-sitter | Skip |
| LSP | Skip |

The clear policy separately asks ChromaFlow to clear matching resolved
Tree-sitter and LSP targets.

Conceptually a clear is an empty highlight write:

```lua
vim.api.nvim_set_hl(0, "@SomeTarget", {})
```

when that resolved target is writable/clearable in the resolver.

Module and group clear masks are additive:

```lua
return u.setup({
  style_targets_clear = {
    lsp = true,
  },

  u:group("Example", {
    fg = c.fg,

    style_targets_clear = {
      ts = true,
    },
  }),
})
```

The group inherits the module LSP clear and adds the Tree-sitter clear.

A group-local clear mask does not cancel a module clear.

Global `style_targets_clear` from `config.cf` is separate again and is handled
at theme level before module application.

## `u.setup(spec)`

`u.setup()` takes exactly one module table:

```lua
return u.setup({
  style_targets = { ... },
  style_targets_clear = { ... },
  mods = { ... },

  u:group(...),
  u:link(...),
  raw:group(...),
  raw:link(...),
})
```

Numeric array entries are declarations. Named keys configure the module.

Unlike plugin setup there is no identity string:

```lua
-- UI
u.setup({ ... })

-- plugin
p.setup("plugin-name", { ... })

-- language
l.setup("lua", { ... })
```

All active `u.setup()` modules share the one UI identity.

## UI fallback identity

UI fallback is intentionally coarse-grained.

Suppose the active theme contains two UI files:

```text
active/editor.cf
active/messages.cf
```

and both return `u.setup({ ... })`.

Both active modules are compiled.

After the complete active pass, ChromaFlow records that the active theme owns
the UI identity. Therefore **default-theme UI modules are not added at all**.

In short:

```text
any active u.setup(...)
    -> active theme owns UI
    -> skip all default u.setup(...) modules
```

If the active theme has no UI module, all matching default-theme UI modules may
be loaded.

This means an intentionally empty active module is meaningful:

```lua
return u.setup({})
```

It performs no highlight writes, but it claims the UI identity and therefore
blocks default UI fallback.

That behavior is different from ordinary language/plugin identity fallback,
where each language or plugin has its own name.

## Splitting UI across files

Because multiple active UI modules are allowed, a theme may split the editor UI
however it likes:

```text
windows.cf
menus.cf
messages.cf
diagnostics-ui.cf
```

Each file may return its own:

```lua
return u.setup({
  ...
})
```

All of them are compiled during the active pass.

The split is only organizational. They still collectively represent the single
UI fallback identity.

For example:

```lua
-- windows.cf
return u.setup({
  u:group("Normal", {
    fg = c.fg,
    bg = c.bg,
  }),

  u:group("NormalFloat", {
    fg = c.fg,
    bg = c.line,
  }),
})
```

and:

```lua
-- menus.cf
return u.setup({
  u:group("Pmenu", {
    fg = c.fg,
    bg = c.line,
  }),

  u:group("PmenuSel", {
    fg = c.fg,
    bg = c.selection,
    bold = true,
  }),
})
```

are two modules, but one UI fallback identity.

## `u:group(name, spec)`

A UI group is a resolver-backed group declaration:

```lua
u:group("StatusLine", {
  fg = c.fg,
  bg = c.line,
})
```

The table may contain normal `nvim_set_hl()` style fields and ChromaFlow
metadata.

Common style fields include:

```text
fg
bg
sp
bold
italic
underline
undercurl
underdashed
underdotted
underdouble
strikethrough
reverse
nocombine
blend
ctermfg
ctermbg
cterm
```

ChromaFlow-specific group metadata includes:

```text
pipeline
types
typemods
style_targets
style_targets_clear
priority
link
```

The complete accepted style field surface follows Neovim's `nvim_set_hl()`
model used by ChromaFlow.

## Normal UI styles

A normal styled group is straightforward:

```lua
u:group("FloatBorder", {
  fg = c.border,
  bg = c.line,
})
```

With default UI targets:

```lua
vim.api.nvim_set_hl(0, "FloatBorder", {
  fg = "...",
  bg = "...",
})
```

Another example:

```lua
u:group("SpellBad", {
  sp = c.red,
  undercurl = true,
})
```

becomes conceptually:

```lua
vim.api.nvim_set_hl(0, "SpellBad", {
  sp = "...",
  undercurl = true,
})
```

## Inline links

A group may link instead of defining a style:

```lua
u:group("CursorColumn", {
  link = "CursorLine",
})
```

With default UI targets:

```lua
vim.api.nvim_set_hl(0, "CursorColumn", {
  link = "CursorLine",
})
```

A link group may not also contain style fields or a pipeline:

```lua
-- invalid
u:group("CursorColumn", {
  link = "CursorLine",
  bg = c.line,
})
```

A group is either styled or linked.

## Standalone `u:link(source, target)`

Standalone links are first-class UI declarations:

```lua
u:link("NormalNC", "Normal")
```

```lua
u:link("CursorColumn", "CursorLine")
```

```lua
u:link("CurSearch", "IncSearch")
```

Unlike plugin `p:link()`, UI links do not require explicit module
`style_targets`, because UI has a real default policy.

With the default policy:

```lua
u:link("NormalNC", "Normal")
```

is conceptually:

```lua
vim.api.nvim_set_hl(0, "NormalNC", {
  link = "Normal",
})
```

If the UI module explicitly enables additional target systems, the resolver
applies the semantic link across those selected layers as appropriate.

## `types`

`types` adds more resolver base names that should follow the primary group.

For example:

```lua
u:group("LineNr", {
  fg = c.muted,
  bg = c.bg,

  types = {
    "LineNrAbove",
    "LineNrBelow",
  },
})
```

With Vim-only UI targets, the shape is conceptually:

```lua
vim.api.nvim_set_hl(0, "LineNr", {
  fg = "...",
  bg = "...",
})

vim.api.nvim_set_hl(0, "LineNrAbove", {
  link = "LineNr",
})

vim.api.nvim_set_hl(0, "LineNrBelow", {
  link = "LineNr",
})
```

The primary group owns the style. Additional `types` link to that primary
semantic target rather than receiving duplicate style tables.

This is useful when several UI groups should deliberately remain identical.

## `typemods`

UI groups technically support the same resolver TypeMod mechanism as other
resolved modules.

This is uncommon for normal Neovim UI groups, but it is available when a UI
module deliberately addresses TS/LSP-style semantic targets.

```lua
u:group("ExampleSemantic", {
  fg = c.fg,

  style_targets = {
    vim = false,
    ts = true,
    lsp = true,
  },

  typemods = {
    readonly = {
      italic = true,
    },
  },
})
```

A TypeMod entry may be:

```text
true
false
style table
link table
```

### `true`

```lua
typemods = {
  readonly = true,
}
```

reuses the finished base-group style.

The base group must therefore have a style.

### `false`

```lua
typemods = {
  readonly = false,
}
```

requests removal of that concrete TypeMod target.

### Style table

```lua
typemods = {
  readonly = {
    italic = true,
  },
}
```

starts from the finished base style and applies the TypeMod style/pipeline on
top.

### Link table

```lua
typemods = {
  readonly = {
    link = "ExampleOther",
  },
}
```

creates a resolver-backed link for that concrete TypeMod.

A TypeMod cannot define its own:

```text
types
typemods
style_targets
style_targets_clear
clear
```

It inherits the effective target and clear policy from its parent group.

For ordinary editor UI theming, most themes never need `typemods` here.

## Module-level `mods`

UI modules also support module-level semantic modifiers:

```lua
return u.setup({
  style_targets = {
    vim = false,
    ts = true,
    lsp = true,
  },

  mods = {
    deprecated = {
      strikethrough = true,
    },
  },

  ...
})
```

Unlike plugin modules, UI modules do not require an explicitly written
`style_targets` table before `mods` are accepted. If omitted, the UI defaults
apply.

In practice, module `mods` are normally useful only when the UI module has
intentionally enabled TS/LSP targets. With the default Vim-only UI policy there
is usually no reason to use semantic modifiers.

A module mod may be:

```text
false
style table
link table
```

and may have its own `priority`, but it cannot override targets itself.

## Pipelines

UI groups use the same pipeline model as every other styled group.

```lua
u:group("Pmenu", {
  fg = c.fg,
  bg = c.line,

  pipeline = {
    hl.opacity.bg(95),
  },
})
```

Explicit style fields establish the current style first. Pipeline operations
then run in guaranteed list order.

Another example:

```lua
u:group("Visual", {
  bg = c.selection,

  pipeline = {
    hl.brightness.bg(5),
    hl.opacity.bg(80),
  },
})
```

For the complete pipeline model, including the difference between pipeline
wrappers and low-level `cf.color.*`, see [`pipeline.md`](pipeline.md).

## `priority`

A UI declaration may set an action priority:

```lua
u:group("NormalFloat", {
  fg = c.fg,
  bg = c.line,
  priority = 20,
})
```

Higher priority actions run later and can override lower-priority actions that
resolve to the same concrete highlight target.

For equal priority, later declaration/action order wins.

The sequence is global across the complete compiled theme rather than reset for
each `.cf` file.

This matters when UI is intentionally split across several files and more than
one declaration addresses the same group.

## Repeated UI declarations

This is valid:

```lua
-- windows.cf
return u.setup({
  u:group("NormalFloat", {
    fg = c.fg,
    bg = c.line,
  }),
})
```

```lua
-- overrides.cf
return u.setup({
  u:group("NormalFloat", {
    bg = c.line_alt,
    priority = 10,
  }),
})
```

Both active modules compile.

If both ultimately target the same concrete highlight group, normal global
action ordering decides which final action wins:

| Case | Result |
| --- | --- |
| Different priority | Higher priority decides ordering |
| Same priority | Later action wins |

There is no "one UI file only" restriction.

## Style deduplication

ChromaFlow interns complete styles across the session.

Suppose two groups end with exactly the same complete style:

```lua
u:group("StatusLineNC", {
  fg = c.muted,
  bg = c.line,
})

u:group("TabLine", {
  fg = c.muted,
  bg = c.line,
})
```

The resolver may materialize one style and link the other group to the already
existing style anchor instead of storing the same style table twice.

So the final state may conceptually look more like:

```lua
vim.api.nvim_set_hl(0, "StatusLineNC", {
  fg = "...",
  bg = "...",
})

vim.api.nvim_set_hl(0, "TabLine", {
  link = "StatusLineNC",
})
```

rather than two identical style writes.

The exact anchor is an implementation result, not a semantic relationship you
need to encode in the theme.

This is why inspecting the final highlight graph can occasionally show a link
to a seemingly unrelated group that simply happens to own the same complete
style.

## `raw` inside a UI module

A UI module may contain exact literal highlight declarations through `hl.raw`:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui
local raw = hl.raw

return u.setup({
  u:group("Normal", {
    fg = c.fg,
    bg = c.bg,
  }),

  raw:group("ExactLiteralGroup", {
    fg = c.orange,
  }),

  raw:link("ExactLiteralAlias", "ExactLiteralGroup"),
})
```

`raw:group()` and `raw:link()` use exactly the supplied names.

They do not:

- expand into Vim/TS/LSP variants,
- use UI `style_targets`,
- use UI `style_targets_clear`,
- append a filetype,
- apply semantic type mapping.

For a raw group, the explicit pre-write clear switch is `clear = true`:

```lua
raw:group("ExactLiteralGroup", {
  clear = true,
  fg = c.orange,
})
```

Conceptually:

```lua
vim.api.nvim_set_hl(0, "ExactLiteralGroup", {})
vim.api.nvim_set_hl(0, "ExactLiteralGroup", {
  fg = "...",
})
```

Use `u:group()` when you want the resolver/target model. Use `raw:group()` when
the literal highlight name itself is the contract.

## Error isolation

When a `.cf` file is compiled by the theme loader, independently compiled
scopes are isolated so one bad declaration does not unnecessarily discard valid
siblings.

A broken UI group rolls back that group.

Inside a valid group, one broken TypeMod rolls back only that TypeMod while the
valid base group and valid sibling TypeMods remain.

Configured diagnostics report the failed source location.

Direct low-level DSL use outside the theme loader keeps the normal assert/error
contract.

## Runtime target access

UI groups are also exposed through the runtime target API:

```lua
local normal = hl.ui.Normal
local pmenu = hl.ui.Pmenu
```

These handles address the UI target rather than creating another static theme
declaration.

Runtime overrides, transitions, timers, recomposition, and their transactional
behavior belong to the runtime chapter rather than the static UI DSL, so they
are only mentioned here for orientation.

## Practical core UI module

A compact editor UI module might look like this:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui

return u.setup({
  u:group("Normal", {
    fg = c.fg,
    bg = c.bg,
  }),

  u:link("NormalNC", "Normal"),

  u:group("NormalFloat", {
    fg = c.fg,
    bg = c.line,
  }),

  u:group("FloatBorder", {
    fg = c.border,
    bg = c.line,
  }),

  u:group("CursorLine", {
    bg = c.line,
  }),

  u:link("CursorColumn", "CursorLine"),

  u:group("Visual", {
    bg = c.selection,
  }),

  u:group("LineNr", {
    fg = c.muted,
    bg = c.bg,

    types = {
      "LineNrAbove",
      "LineNrBelow",
    },
  }),

  u:group("CursorLineNr", {
    fg = c.orange,
    bg = c.line,
    bold = true,
  }),

  u:group("Pmenu", {
    fg = c.fg,
    bg = c.line,
  }),

  u:group("PmenuSel", {
    fg = c.fg,
    bg = c.selection,
    bold = true,
  }),

  u:group("Search", {
    fg = c.black,
    bg = c.yellow,
  }),

  u:group("IncSearch", {
    fg = c.black,
    bg = c.orange,
    bold = true,
  }),

  u:link("CurSearch", "IncSearch"),

  u:group("DiagnosticError", {
    fg = c.red,
  }),

  u:group("DiagnosticWarn", {
    fg = c.yellow,
  }),

  u:group("DiagnosticInfo", {
    fg = c.blue,
  }),

  u:group("DiagnosticHint", {
    fg = c.cyan,
  }),
})
```

No module-level `style_targets` is necessary because all groups use the normal
UI default:

| Target | UI default |
| --- | ---: |
| `vim` | `true` |
| `ts` | `false` |
| `lsp` | `false` |

## Minimal template

For the common case:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui

return u.setup({
  u:group("Normal", {
    fg = c.fg,
    bg = c.bg,
  }),
})
```

If the module needs an unusual resolver layer, make that explicit:

```lua
return u.setup({
  style_targets = {
    vim = true,
    ts = true,
    lsp = false,
  },

  ...
})
```

For ordinary Neovim UI highlights, the default Vim-only policy is the intended
path.
