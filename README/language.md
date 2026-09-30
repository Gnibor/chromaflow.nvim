# Language modules

## Contents

- [`l.setup(language, spec)`](#lsetuplanguage-spec)
- [Targets first: `style_targets` and `style_targets_clear`](#targets-first-style_targets-and-style_targets_clear)
- [What a semantic group becomes](#what-a-semantic-group-becomes)
- [Semantic groups](#semantic-groups)
- [`types`: several semantic types, one anchor](#types-several-semantic-types-one-anchor)
- [`typemods`: style a concrete Type + Mod combination](#typemods-style-a-concrete-type--mod-combination)
- [`mods`: modifiers without a concrete Type](#mods-modifiers-without-a-concrete-type)
- [Semantic links](#semantic-links)
- [Priorities and repeated declarations](#priorities-and-repeated-declarations)
- [`l.setup(nil, ...)`: global semantic syntax](#lsetupnil--global-semantic-syntax)
- [Raw escape hatch inside a language module](#raw-escape-hatch-inside-a-language-module)
- [Error isolation while loading `.cf` files](#error-isolation-while-loading-cf-files)
- [A practical generic + language-specific layout](#a-practical-generic--language-specific-layout)
- [CFPick and language modules](#cfpick-and-language-modules)
- [Next](#next)

Language modules are the main semantic theme surface in ChromaFlow.

Instead of writing raw highlight names such as:

```text
@variable.lua
@lsp.type.variable.lua
Identifier
```

you describe semantic types such as `variable`, `function`, `method`, or
`keyword`. The resolver turns those semantic declarations into the applicable
Vim/Syntax, Tree-sitter, and LSP highlight groups for the selected language.

A typical language module starts like this:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language

return l.setup("lua", {
  l:group("variable", { fg = c.variable }),
  l:group("function", { fg = c.func }),
  l:group("keyword", { fg = c.keyword }),
})
```

The filename is irrelevant. `lua.cf`, `lang-lua.cf`, `syntax.cf`, or any other
normal `.cf` filename can all return the same `l.setup("lua", ...)` module.

For theme loading and fallback rules, see
[`theme-structure.md`](theme-structure.md).

## `l.setup(language, spec)`

The first argument is the language/filetype context:

```lua
return l.setup("lua", { ... })
```

ChromaFlow resolves semantic highlight names in the Lua context and creates or
links the corresponding filetype-specific groups where needed.

The first argument is positional. Use an explicit `nil` for a global language
module:

```lua
return l.setup(nil, { ... })
```

Do not confuse `l.setup(nil, ...)` with theme fallback. It is a real module with
its own **global-language identity** and no filetype suffix/context.

The module table can contain:

```lua
return l.setup("lua", {
  style_targets = { vim = true, ts = true, lsp = true },
  style_targets_clear = { ... },
  mods = { ... },

  l:group(...),
  l:link(...),
})
```

The array entries are declarations. Named fields configure the module itself.

## Targets first: `style_targets` and `style_targets_clear`

Every resolved module should make its target policy understandable near the
module declaration itself. The same target model is used by language, plugin,
and UI modules; the defaults differ by module kind, but the precedence rules
are the same.

For a language module, omitting `style_targets` inherits the globally enabled
targets from `config.cf`:

```lua
return l.setup("lua", {
  l:group("variable", { fg = c.variable }),
})
```

An explicit module policy looks like this:

```lua
return l.setup("lua", {
  style_targets = {
    vim = true,
    ts = true,
    lsp = true,
  },

  l:group("variable", { fg = c.variable }),
})
```

`config.cf` is the hard upper boundary. If a target is disabled globally, no
module or group can enable it again. For a globally enabled target, the
effective value is chosen in this order:

1. Group `style_targets` value, if explicitly present.
2. Module `style_targets` value, if explicitly present.
3. Global config value.

That means a group may override the module policy for a target as long as the
target is still globally allowed:

```lua
return l.setup("lua", {
  style_targets = { vim = true, ts = false, lsp = false },

  l:group("variable", {
    fg = c.variable,
    style_targets = { ts = true },
  }),
})
```

Here Tree-sitter is enabled again for this group because the group value wins
over the module value. This would still remain disabled if `config.cf` had
`ts = false`.

### Clearing is independent from setting

`style_targets_clear` does not select where the new style is written. It selects
which resolved target systems are cleared before/alongside this declaration:

```lua
return l.setup("lua", {
  style_targets = { vim = false, ts = true, lsp = true },
  style_targets_clear = { vim = true },

  l:group("variable", { fg = c.variable }),
})
```

The clear mask is independent from the write mask, so the Vim/Syntax target can
be cleared even though the declaration does not write a new Vim/Syntax style.

Module and group clear masks are additive: a group may add more clears, but it
does not cancel a module clear. Global `style_targets_clear` is handled at the
theme level before module application.

`mods` inherit the module target policy and cannot define their own
`style_targets` or `style_targets_clear`. Group declarations may define both.

## What a semantic group becomes

A language declaration is not one `nvim_set_hl()` call. ChromaFlow first
resolves the semantic name into the enabled Vim/Syntax, Tree-sitter, and LSP
targets, then materializes only the style anchor it needs and links the higher
layers through it.

For example:

```lua
return l.setup("lua", {
  style_targets = { vim = true, ts = true, lsp = true },

  l:group("variable", {
    fg = c.variable,
  }),
})
```

For the normal Lua `variable` mapping, the resolver targets are conceptually:

| Layer | Concrete highlight |
| --- | --- |
| Vim/Syntax | `luaIdentifier` |
| Tree-sitter | `@variable.lua` |
| LSP | `@lsp.type.variable.lua` |

If no equivalent style is already materialized elsewhere, the resulting
backend writes are equivalent to:

```lua
vim.api.nvim_set_hl(0, "luaIdentifier", { fg = "..." })
vim.api.nvim_set_hl(0, "@variable.lua", { link = "luaIdentifier" })
vim.api.nvim_set_hl(0, "@lsp.type.variable.lua", { link = "@variable.lua" })
```

So the intended chain is:

```text
LSP -> Tree-sitter -> Vim/Syntax
```

With only Tree-sitter and LSP selected:

```lua
style_targets = { vim = false, ts = true, lsp = true }
```

the equivalent shape becomes:

```lua
vim.api.nvim_set_hl(0, "@variable.lua", { fg = "..." })
vim.api.nvim_set_hl(0, "@lsp.type.variable.lua", { link = "@variable.lua" })
```

And a clear request such as:

```lua
style_targets_clear = { vim = true }
```

may additionally produce:

```lua
vim.api.nvim_set_hl(0, "luaIdentifier", {})
```

These examples show the resolver shape, not a promise that every style is
always materialized on exactly that group. ChromaFlow deduplicates identical
styles: if the same complete style already exists on a suitable target, the
resolver may link to that existing style anchor instead of writing a duplicate.
The semantic targets and target-selection rules remain the same.

This distinction also explains why inspecting the final Neovim link can look
different from the semantic declaration. Resolver details and inspection
behaviour are covered separately in [`resolver.md`](resolver.md).

## Semantic groups

Create a group with:

```lua
l:group("variable", {
  fg = c.variable,
})
```

The name is a **semantic type**, not a literal highlight group name.

For a language module ChromaFlow asks the resolver for the Vim/Syntax,
Tree-sitter, and LSP representations of that type in the current filetype
context.

For example, `variable` may ultimately involve groups from several systems, but
the theme declaration stays:

```lua
l:group("variable", { ... })
```

This is important because the exact raw names and fallback chain are resolver
concerns, not theme-module concerns.

### Style fields

A group accepts normal supported `nvim_set_hl()` style fields:

```lua
l:group("comment", {
  fg = c.comment,
  italic = true,
})
```

It may also contain a pipeline:

```lua
l:group("function", {
  fg = c.func,
  pipeline = {
    hl.shiftHue.fg(-5),
    hl.brightness.fg(20),
  },
})
```

Pipeline operations run after the explicit style fields. See
[`pipeline.md`](pipeline.md).

## `types`: several semantic types, one anchor

`types` lets one declaration own several semantic base types:

```lua
l:group("function", {
  fg = c.func,
  types = { "method" },
})
```

The first name, here `function`, is the primary type. Additional names are
linked semantically to that primary type instead of receiving duplicate style
assignments.

Conceptually:

| Type | Result |
| --- | --- |
| `function` | Owns the style |
| `method` | Links to `function` |

This keeps one explicit style anchor while still allowing several semantic
types to share it.

The same pattern is useful for larger families:

```lua
l:group("type", {
  fg = c.type,
  types = { "class", "struct", "enum", "interface" },
})
```

Duplicate names inside `types` are ignored.

### TypeMods also apply to additional `types`

A `typemods` table on such a group applies to **every semantic type owned by the
group**.

For example:

```lua
l:group("function", {
  fg = c.func,
  types = { "method" },
  typemods = {
    declaration = { bold = true },
  },
})
```

covers both the function/declaration and method/declaration combinations that
the resolver can represent for the selected targets.

## `typemods`: style a concrete Type + Mod combination

`typemods` belongs to a group and describes a modifier/specialization in the
context of that type:

```lua
l:group("variable", {
  fg = c.variable,
  typemods = {
    readonly = { fg = c.constant },
    static = { italic = true },
  },
})
```

The keys are semantic TypeMod suffixes. ChromaFlow combines them with the group
type through the resolver.

A TypeMod style inherits the **finished base-group style** first and then
applies its own fields and pipeline.

For example:

```lua
l:group("function", {
  fg = c.func,
  pipeline = {
    hl.darken.fg(3),
  },
  typemods = {
    builtin = {
      pipeline = {
        hl.mix.fg(22, c.yellow),
      },
    },
  },
})
```

`builtin` starts from the already darkened function style, then applies its own
pipeline.

### TypeMod values

A TypeMod entry can be a table, `true`, or `false`.

#### Table: derive or replace the TypeMod style

```lua
readonly = {
  italic = true,
  pipeline = {
    hl.mix.fg(18, c.constant),
  },
}
```

The table inherits the base style and may add/replace style fields or run a
pipeline.

It may also set its own priority:

```lua
readonly = {
  priority = 10,
  bold = true,
}
```

If omitted, the TypeMod inherits the group's priority.

#### `true`: use exactly the base style

```lua
typemods = {
  readonly = true,
}
```

`true` requires the group itself to have a style. It tells ChromaFlow to use
that base style for the TypeMod without defining an additional derived style.

#### `false`: clear the TypeMod

```lua
typemods = {
  readonly = false,
}
```

This explicitly clears the resolved TypeMod targets.

### A group may contain only TypeMods

A group does not need its own base style when its only purpose is to configure
specific combinations:

```lua
l:group("keyword", {
  style_targets = { vim = false, ts = true, lsp = false },
  typemods = {
    ["function"] = { fg = c.keyword, bold = true },
    ["return"] = { fg = c.keyword },
    ["operator"] = { fg = c.operator },
  },
})
```

This is especially useful for target-specific Tree-sitter captures or other
concrete semantic combinations without changing the base type.

## `mods`: modifiers without a concrete Type

Module-level `mods` are different from group `typemods`.

A module mod has no base type attached to it:

```lua
return l.setup("lua", {
  mods = {
    deprecated = { strikethrough = true },
  },

  l:group("variable", { fg = c.variable }),
})
```

Conceptually:

| Declaration | Meaning |
| --- | --- |
| `mods.deprecated` | Modifier on its own |
| `typemods.readonly` | Current group type + `readonly` |

The resolver maps a module mod to the applicable standalone Vim/TS/LSP
representations in the current language context.

For LSP, the modifier name does not have to be pre-registered by ChromaFlow or
already exist as a highlight group. Server-specific modifiers are valid standalone
Mods and can be materialized directly as:

```text
@lsp.mod.<modifier>.<filetype>
```

For example, `mods.functionScope` in a C language module can own
`@lsp.mod.functionScope.c` even when clangd's group was not present when the
theme environment was catalogued.

Vim/Syntax and Tree-sitter standalone modifier targets remain environment-driven,
and this standalone LSP rule does not imply that every Type + custom modifier
combination is automatically created as a TypeMod.

A module mod can contain style fields, a pipeline, a semantic `link`, and a
priority:

```lua
mods = {
  deprecated = {
    strikethrough = true,
    priority = 5,
  },
}
```

or:

```lua
mods = {
  deprecated = {
    link = "comment",
  },
}
```

Use `false` to clear a module mod:

```lua
mods = {
  deprecated = false,
}
```

Module mods use the module's target configuration. They do not have their own
`style_targets` or `style_targets_clear` fields.

## Semantic links

There are two ways to create semantic links.

### Link a whole group

A group may use `link` instead of a style:

```lua
l:group("character", {
  link = "string",
})
```

A linked group cannot also contain style fields or a pipeline.

### `l:link(source, target)`

For a declaration that is only a semantic link, use:

```lua
l:link("character", "string")
```

Inside `l.setup("lua", ...)`, the source and target are resolved in the same
Lua/filetype context.

The source and target must be different.

A TypeMod table may also link to another semantic base type:

```lua
l:group("variable", {
  fg = c.variable,
  typemods = {
    documentation = { link = "comment" },
  },
})
```

`link` is mutually exclusive with style fields and pipelines for that entry.

## Priorities and repeated declarations

Every group and mod defaults to priority `0`.

A higher priority runs later:

```lua
l:group("variable", {
  priority = 10,
  bold = true,
})
```

After compilation ChromaFlow sorts all actions globally by:

```text
1. priority
2. declaration sequence
```

So for equal priority, the later declaration wins when two actions affect the
same concrete highlight.

This means repeated groups are valid and useful:

```lua
l:group("variable", {
  fg = c.variable,
})

l:group("variable", {
  style_targets = { vim = false, ts = true, lsp = false },
  typemods = {
    member = { fg = c.property },
  },
})
```

Likewise, several active `.cf` files may all return `l.setup("lua", ...)`.
They are all compiled. Only after the complete active pass does that language
identity suppress matching modules from the default theme.

For the full module-fallback rules, see
[`theme-structure.md`](theme-structure.md).

## `l.setup(nil, ...)`: global semantic syntax

A global language module is written explicitly with `nil`:

```lua
return l.setup(nil, {
  l:group("comment", { fg = c.comment, italic = true }),
  l:group("string", { fg = c.string }),
  l:group("number", { fg = c.number }),
})
```

This does not apply a filetype suffix/context. It is useful as the generic
semantic layer of a theme.

A real theme can therefore have both:

```lua
l.setup(nil, { ... })    -- generic semantic layer
l.setup("lua", { ... }) -- Lua-specific layer
```

They are different module identities and may coexist.

The selected active theme's module-identity fallback still applies: an active
`l.setup("lua", ...)` suppresses default-theme Lua modules, while an active
global-language module suppresses the default global-language modules.

## Raw escape hatch inside a language module

A language module may contain `raw:group()` or `raw:link()` declarations when
a literal highlight group really is required:

```lua
local raw = hl.raw

return l.setup("lua", {
  l:group("variable", { fg = c.variable }),

  raw:group("SomeLiteralGroup", {
    fg = c.special,
  }),
})
```

Raw declarations bypass semantic resolution completely. Use them only when the
highlight truly cannot be expressed semantically.

Raw groups are documented separately in the API/reference material.

## Error isolation while loading `.cf` files

ChromaFlow isolates independently compiled declarations while a real `.cf`
module is loading.

If one group is invalid, another valid group in the same module can still be
compiled and applied.

TypeMods have an even smaller failure boundary: a broken TypeMod rolls back
only itself. The valid base group and valid sibling TypeMods remain intact.

For example, an invalid entry should not destroy the valid parts around it:

```lua
l:group("variable", {
  fg = c.variable,
  typemods = {
    readonly = { italic = true },
    broken = 42, -- diagnostic error for this entry
    static = { bold = true },
  },
})
```

The invalid entry is reported through ChromaFlow diagnostics rather than
silently changing the meaning of the valid declarations.

Direct low-level use of the setup API outside a loaded `.cf` file keeps the
normal assert/error contract.

## A practical generic + language-specific layout

A useful pattern is to put the common semantic vocabulary into a global module:

```lua
-- generic.cf
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language

return l.setup(nil, {
  mods = {
    deprecated = { strikethrough = true },
  },

  l:group("variable", { fg = c.variable }),
  l:group("function", {
    fg = c.func,
    types = { "method" },
  }),
  l:group("type", {
    fg = c.type,
    types = { "class", "struct", "enum", "interface" },
  }),
  l:group("keyword", { fg = c.keyword }),
})
```

and keep language-specific differences in another file:

```lua
-- the filename is arbitrary; this one happens to be lang-lua.cf
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language

return l.setup("lua", {
  l:group("function", {
    fg = c.func,
    types = { "method" },
    pipeline = {
      hl.shiftHue.fg(-5),
      hl.brightness.fg(20),
    },
  }),

  l:group("variable", {
    style_targets = { vim = false, ts = true, lsp = false },
    typemods = {
      member = { fg = c.property },
    },
  }),
})
```

This keeps semantic intent readable while still allowing precise source- and
language-specific control when it is actually needed.

## CFPick and language modules

`CFPick` is designed to make language modules practical to build without
constantly copying names from `:Inspect`.

At the cursor it collects the actual semantic targets reported by Neovim and
lets you edit the corresponding CF type/mod/typemod directly.

When the current language module does not own a target but the generic module
does, CFPick can ask whether the change should be written to the language module
or to generic. This keeps **style resolution** and **write ownership** separate.

That workflow is covered in detail in the dedicated picker chapter.

## Next

Language modules are intentionally semantic. The details of how names map to
Vim/Syntax, Tree-sitter, and LSP groups belong to the resolver, not to the
module DSL.

Continue with:

- `plugin.md` for plugin-scoped resolver modules,
- `ui.md` for UI-oriented modules,
- `resolver.md` for semantic name resolution and link chains,
- `picker.md` for interactive theme editing.
