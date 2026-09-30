# Raw declarations

## Contents

- [`raw` is not a standalone setup module](#raw-is-not-a-standalone-setup-module)
- [When to use raw](#when-to-use-raw)
- [No `style_targets`](#no-style_targets)
- [`clear = true`](#clear--true)
- [`raw:group(name, spec)`](#rawgroupname-spec)
- [Pipeline support](#pipeline-support)
- [Inline raw links](#inline-raw-links)
- [Standalone `raw:link(source, target)`](#standalone-rawlinksource-target)
- [`types` are exact extra group names](#types-are-exact-extra-group-names)
- [Raw `typemods` are also exact names](#raw-typemods-are-also-exact-names)
- [Raw TypeMod inheritance](#raw-typemod-inheritance)
- [`typemods = { Name = true }`](#typemods---name--true)
- [`typemods = { Name = false }`](#typemods---name--false)
- [Raw TypeMod links](#raw-typemod-links)
- [`clear = true` also applies to raw group children](#clear--true-also-applies-to-raw-group-children)
- [Priority](#priority)
- [Raw does not perform resolver style deduplication](#raw-does-not-perform-resolver-style-deduplication)
- [Raw names are not filetype-scoped](#raw-names-are-not-filetype-scoped)
- [Raw declarations ignore module target masks](#raw-declarations-ignore-module-target-masks)
- [Mixing resolved and raw declarations](#mixing-resolved-and-raw-declarations)
- [Error isolation](#error-isolation)
- [Runtime access to raw targets](#runtime-access-to-raw-targets)
- [Practical example](#practical-example)
- [Minimal template](#minimal-template)

`hl.raw` is ChromaFlow's literal highlight escape hatch.

Use it when the exact Neovim highlight-group name is already the contract and
there is nothing for the resolver to infer.

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui
local raw = hl.raw

return u.setup({
  raw:group("NormalFloat", {
    fg = c.fg,
    bg = c.bg,
  }),

  raw:link("FloatBorder", "NormalFloat"),
})
```

The important property is literalness:

```text
raw:group("NormalFloat", ...)
```

means exactly:

```lua
vim.api.nvim_set_hl(0, "NormalFloat", {
  ...
})
```

There is no semantic target expansion, no filetype suffix, and no
Vim -> Tree-sitter -> LSP resolver chain.

## `raw` is not a standalone setup module

Unlike language, plugin, and UI DSLs, `raw` has no `raw.setup(...)`.

Raw declarations live inside a normal language, plugin, or UI module:

```lua
return u.setup({
  raw:group("Normal", { fg = c.fg, bg = c.bg }),
})
```

```lua
return p.setup("example-plugin", {
  raw:group("ExampleExactGroup", { fg = c.blue }),
})
```

```lua
return l.setup("lua", {
  raw:group("luaExactLegacyGroup", { fg = c.yellow }),
})
```

The surrounding module still provides the theme/fallback identity.

A raw declaration does **not** create an independent fallback identity of its
own.

This also means a `.cf` module still returns `l.setup(...)`, `p.setup(...)`, or
`u.setup(...)`; it does not return a free-standing array of raw declarations.

For module identity and active/default fallback, see
[`theme-structure.md`](theme-structure.md).

## When to use raw

Use `raw` when:

- the exact `hl_group` name is known,
- you do not want ChromaFlow to classify or expand it,
- the group does not need semantic Vim/TS/LSP target handling,
- or an external API/plugin explicitly documents one literal highlight name.

Prefer the normal language/plugin/UI declarations when you want resolver
semantics, target masks, filetype context, Type/Mod mapping, or semantic links.

A useful rule of thumb is:

| Need | Use |
| --- | --- |
| Semantic meaning | `l` / `p` / `u` |
| Exact `hl_group` | `raw` |

## No `style_targets`

Raw declarations do not support:

```lua
style_targets = { ... }
style_targets_clear = { ... }
```

This would be contradictory: raw already means "write this exact name".

For example:

```lua
raw:group("@my.capture", {
  fg = c.orange,
})
```

writes exactly:

```text
@my.capture
```

It does not matter that the name happens to look like a Tree-sitter capture.
Raw does not classify it as Tree-sitter and does not create sibling Vim or LSP
forms.

Likewise:

```lua
raw:group("@lsp.type.variable.lua", {
  fg = c.blue,
})
```

writes that exact name only.

## `clear = true`

Because raw declarations do not use `style_targets_clear`, `raw:group()` has a
literal clear switch instead:

```lua
raw:group("MyExactGroup", {
  clear = true,
  fg = c.orange,
  bold = true,
})
```

Conceptually this performs:

```lua
vim.api.nvim_set_hl(0, "MyExactGroup", {})

vim.api.nvim_set_hl(0, "MyExactGroup", {
  fg = "...",
  bold = true,
})
```

`clear = true` means clear the literal target immediately before its new style
or link is applied.

It is not a target-system clear policy and it does not scan related groups.

Without `clear = true`, ChromaFlow simply applies the requested raw style/link
to the exact group.

## `raw:group(name, spec)`

A basic raw group is:

```lua
raw:group("MyExactGroup", {
  fg = c.fg,
  bg = c.bg,
  bold = true,
})
```

Conceptually:

```lua
vim.api.nvim_set_hl(0, "MyExactGroup", {
  fg = "...",
  bg = "...",
  bold = true,
})
```

Normal `nvim_set_hl()` style fields are supported, together with ChromaFlow
metadata relevant to raw groups:

```text
pipeline
types
typemods
link
priority
clear
```

Raw groups do not support semantic target metadata:

```text
style_targets
style_targets_clear
```

## Pipeline support

Raw styles can use the same ChromaFlow pipeline wrappers as resolved groups:

```lua
raw:group("MyExactGroup", {
  fg = c.fg,
  bg = c.panel,

  pipeline = {
    hl.opacity.fg(80),
    hl.mix.bg(10, c.black),
  },
})
```

The explicit style is built first, then the pipeline operations are applied in
pipeline order.

The result is finally written to the exact raw name.

The distinction described in [`colors.md`](colors.md) and
[`pipeline.md`](pipeline.md) still applies:

- `cf.color.*` is low-level Lua and can be called anywhere,
- `hl.*` pipeline wrappers participate in ChromaFlow's ordered pipeline.

## Inline raw links

A raw group may be a literal link instead of a style:

```lua
raw:group("MyAlias", {
  link = "MyExactGroup",
})
```

Conceptually:

```lua
vim.api.nvim_set_hl(0, "MyAlias", {
  link = "MyExactGroup",
})
```

The source and target are both literal names.

No resolver transformation is performed on either side.

As with other group declarations, `link` cannot be combined with style fields
or a pipeline:

```lua
-- invalid
raw:group("MyAlias", {
  link = "MyExactGroup",
  fg = c.red,
})
```

## Standalone `raw:link(source, target)`

For a simple literal link, use:

```lua
raw:link("MyAlias", "MyExactGroup")
```

Conceptually:

```lua
vim.api.nvim_set_hl(0, "MyAlias", {
  link = "MyExactGroup",
})
```

Again, both names are exact.

This is different from:

```lua
l:link(...)
p:link(...)
u:link(...)
```

Those are resolver-backed semantic links. `raw:link()` bypasses that layer
completely.

A standalone `raw:link()` is intentionally minimal. If you need group metadata
such as `priority` or `clear = true`, use the inline group form:

```lua
raw:group("MyAlias", {
  link = "MyExactGroup",
  priority = 20,
  clear = true,
})
```

## `types` are exact extra group names

Raw `types` are not semantic Types.

They are simply additional full literal highlight-group names linked to the
primary raw group.

```lua
raw:group("MyPrimaryGroup", {
  fg = c.green,
  bold = true,

  types = {
    "MySecondaryGroup",
    "MyThirdGroup",
  },
})
```

Conceptually:

```lua
vim.api.nvim_set_hl(0, "MyPrimaryGroup", {
  fg = "...",
  bold = true,
})

vim.api.nvim_set_hl(0, "MySecondaryGroup", {
  link = "MyPrimaryGroup",
})

vim.api.nvim_set_hl(0, "MyThirdGroup", {
  link = "MyPrimaryGroup",
})
```

The style is anchored once on the primary group. Extra `types` hang off that
primary group as literal links.

There is no target expansion around any of those names.

Duplicate names in `types` are ignored, and repeating the primary name does not
create a second action.

## Raw `typemods` are also exact names

This is one of the most important differences from resolver-backed groups.

Inside a raw group, the keys of `typemods` are **full literal highlight-group
names**.

They are not modifier names appended to the parent group.

For example:

```lua
raw:group("MyBase", {
  fg = c.fg,

  typemods = {
    MySelected = {
      bold = true,
    },

    MyInherited = true,

    MyRemoved = false,
  },
})
```

addresses exactly these names:

```text
MyBase
MySelected
MyInherited
MyRemoved
```

It does **not** invent names such as:

```text
MyBase.MySelected
@MyBase.MySelected
@lsp.type.MyBase.MySelected
```

Raw means literal all the way down.

## Raw TypeMod inheritance

Although the names are literal, raw `typemods` still use ChromaFlow's group
style inheritance model.

Given:

```lua
raw:group("MyBase", {
  fg = c.fg,
  bg = c.panel,

  typemods = {
    MySelected = {
      bold = true,
    },
  },
})
```

`MySelected` starts from the finished `MyBase` style and applies its own fields
on top.

Conceptually its final style contains:

| Field | Comes from |
| --- | --- |
| `fg` | `MyBase` |
| `bg` | `MyBase` |
| `bold` | `MySelected` |

If the base group has a pipeline, the TypeMod inherits the **finished** base
style after that pipeline has run.

A TypeMod-local pipeline then runs on top of that inherited style.

## `typemods = { Name = true }`

`true` copies/reuses the finished base style for that exact raw name:

```lua
raw:group("MyBase", {
  fg = c.blue,

  typemods = {
    MyOtherExactGroup = true,
  },
})
```

`true` requires the base group to have a style.

A link-only or style-less parent cannot provide a base style to inherit.

## `typemods = { Name = false }`

`false` clears that exact literal group:

```lua
raw:group("MyBase", {
  fg = c.blue,

  typemods = {
    ObsoleteExactGroup = false,
  },
})
```

Conceptually:

```lua
vim.api.nvim_set_hl(0, "ObsoleteExactGroup", {})
```

This is a literal clear. No resolver-related sibling targets are involved.

## Raw TypeMod links

A raw TypeMod can also link one exact name to another:

```lua
raw:group("MyBase", {
  fg = c.blue,

  typemods = {
    MySelected = {
      link = "MyOtherGroup",
    },
  },
})
```

Conceptually:

```lua
vim.api.nvim_set_hl(0, "MySelected", {
  link = "MyOtherGroup",
})
```

The TypeMod entry cannot combine `link` with style fields or pipeline
operations.

Raw TypeMod entries also cannot define nested:

```text
types
typemods
style_targets
style_targets_clear
clear
```

Use `false` when the TypeMod itself should be cleared.

## `clear = true` also applies to raw group children

For a raw group such as:

```lua
raw:group("MyBase", {
  clear = true,
  fg = c.fg,

  types = {
    "MyAlias",
  },

  typemods = {
    MySelected = {
      bold = true,
    },
  },
})
```

`clear = true` is carried to the literal style/link actions produced by that
raw group.

So the primary group, generated literal `types` links, and styled/linked raw
TypeMods are cleared immediately before they are materialized.

A `false` raw TypeMod is already an explicit clear action by itself.

## Priority

Raw groups participate in ChromaFlow's normal compiled action ordering:

```lua
raw:group("MyExactGroup", {
  fg = c.blue,
  priority = 20,
})
```

Higher priority runs later.

For equal priority, later compiled actions run later.

Raw TypeMod entries may override the inherited priority:

```lua
raw:group("MyBase", {
  fg = c.fg,
  priority = 10,

  typemods = {
    MySelected = {
      bold = true,
      priority = 30,
    },
  },
})
```

The ordering is global with the other compiled theme actions. Raw does not get a
separate execution phase merely because it bypasses the resolver.

## Raw does not perform resolver style deduplication

Resolver-backed groups may be represented as links to an already materialized
same-style anchor. That is part of the resolver's storage/link optimization.

Raw declarations are different.

```lua
raw:group("RawA", { fg = c.blue })
raw:group("RawB", { fg = c.blue })
```

address two exact groups. ChromaFlow does not reinterpret `RawB` as a semantic
alias of `RawA` just because their complete styles are equal.

Both names remain explicit raw targets.

This is another reason to use raw only when literal ownership is what you want.

## Raw names are not filetype-scoped

Putting a raw declaration inside a language module does not suffix its name:

```lua
return l.setup("lua", {
  raw:group("MyExactGroup", {
    fg = c.orange,
  }),
})
```

still writes:

```text
MyExactGroup
```

not:

```text
MyExactGroup.lua
@MyExactGroup.lua
@lsp.type.MyExactGroup.lua
```

The language module controls fallback ownership and compile context; it does
not change the literal raw name.

## Raw declarations ignore module target masks

Because raw bypasses target resolution, the surrounding module's
`style_targets` does not filter raw declarations.

For example:

```lua
return p.setup("example-plugin", {
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  raw:group("@example.capture", {
    fg = c.orange,
  }),
})
```

still targets the exact literal name:

```text
@example.capture
```

The module target mask applies to `p:group()` / `p:link()` resolver actions,
not to `raw:*` actions.

The same applies to `style_targets_clear`: raw declarations use their own
literal `clear` behavior instead.

## Mixing resolved and raw declarations

A module may contain both forms when that matches the external highlight
surface:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local p = hl.plugin
local raw = hl.raw

return p.setup("example-plugin", {
  style_targets = {
    vim = true,
  },

  p:group("ExampleNormal", {
    fg = c.fg,
  }),

  p:link("ExampleBorder", "ExampleNormal"),

  raw:group("@example.special", {
    fg = c.orange,
  }),
})
```

Here:

- `ExampleNormal` and `ExampleBorder` use plugin resolver semantics,
- `@example.special` is written literally.

There is no requirement that a whole module choose one mode exclusively.

## Error isolation

Raw groups use the same per-declaration compile protection as other theme
groups while `.cf` files are loaded.

If one raw group is invalid, its own actions are rolled back without
necessarily discarding valid sibling groups.

Inside a valid raw group, one broken raw TypeMod is isolated from the base group
and valid sibling TypeMods.

Direct low-level use outside the protected `.cf` loading path retains the
normal assert/error behavior.

## Runtime access to raw targets

`hl.raw` also exposes exact raw highlight targets through its indexed runtime
surface:

```lua
hl.raw.MyExactGroup
```

That is a runtime target handle for the exact group name, not a declaration.

The declaration side documented in this chapter is:

```lua
raw:group(...)
raw:link(...)
```

The runtime handle side is covered in [`runtime.md`](runtime.md), because its
behavior belongs to ChromaFlow's runtime override/composition system rather
than static theme compilation.

## Practical example

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui
local raw = hl.raw

return u.setup({
  raw:group("NormalFloat", {
    fg = c.fg,
    bg = c.panel,
  }),

  raw:group("FloatTitle", {
    fg = c.accent,
    bold = true,
  }),

  raw:group("FloatBorder", {
    link = "NormalFloat",
  }),

  raw:group("DiagnosticVirtualTextHint", {
    fg = c.hint,

    pipeline = {
      hl.opacity.fg(70),
    },
  }),
})
```

Every name above is treated literally.

ChromaFlow still provides style normalization, pipelines, priority handling,
diagnostics, and compile-time isolation, but the semantic resolver does not
participate.

## Minimal template

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui
local raw = hl.raw

return u.setup({
  raw:group("ExactGroup", {
    fg = c.fg,
  }),

  raw:link("ExactAlias", "ExactGroup"),
})
```

Use raw deliberately: it gives precise control over exact Neovim highlight
names, while intentionally giving up ChromaFlow's semantic target resolution.
