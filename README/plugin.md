# Plugin modules

## Contents

- [`p.setup(name, spec)`](#psetupname-spec)
- [Targets first: plugin modules default to no writable target](#targets-first-plugin-modules-default-to-no-writable-target)
- [Target precedence](#target-precedence)
- [`style_targets_clear`](#style_targets_clear)
- [What a Vim-style plugin group becomes](#what-a-vim-style-plugin-group-becomes)
- [Plugin groups still use the resolver](#plugin-groups-still-use-the-resolver)
- [Tree-sitter plugin captures](#tree-sitter-plugin-captures)
- [`p:group(name, spec)`](#pgroupname-spec)
- [`types`](#types)
- [`typemods`](#typemods)
- [Module-level `mods`](#module-level-mods)
- [`p:link(source, target)`](#plinksource-target)
- [Style fields and pipeline](#style-fields-and-pipeline)
- [`link` inside a group](#link-inside-a-group)
- [`priority`](#priority)
- [`style_targets_clear` at group level](#style_targets_clear-at-group-level)
- [`raw` inside a plugin module](#raw-inside-a-plugin-module)
- [Error isolation](#error-isolation)
- [Plugin fallback identity is semantic, not a filename rule](#plugin-fallback-identity-is-semantic-not-a-filename-rule)
- [A practical Vim-highlight plugin module](#a-practical-vim-highlight-plugin-module)
- [A practical Tree-sitter plugin module](#a-practical-tree-sitter-plugin-module)
- [Choosing between plugin, UI, language, and raw](#choosing-between-plugin-ui-language-and-raw)
- [Minimal template](#minimal-template)

Plugin modules describe highlight groups owned by Neovim plugins or by any
other feature that is best treated as one named, theme-level identity.

A typical module looks like this:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local p = hl.plugin

return p.setup("nvim-cmp", {
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  p:group("CmpItemAbbr", { fg = c.fg }),
  p:group("CmpItemAbbrMatch", { fg = c.orange, bold = true }),
})
```

The filename is not the module identity. The string passed to `p.setup()` is:

```lua
p.setup("nvim-cmp", { ... })
```

That name is ChromaFlow's **plugin/fallback identity**.

It is not a filetype, and ChromaFlow does not append it to resolved highlight
names as a language suffix would.

For theme loading and fallback rules, see
[`theme-structure.md`](theme-structure.md).

## `p.setup(name, spec)`

The first argument must be a non-empty string:

```lua
return p.setup("gitsigns", {
  ...
})
```

The module table may contain:

```lua
return p.setup("example-plugin", {
  style_targets = { ... },
  style_targets_clear = { ... },
  mods = { ... },

  p:group(...),
  p:link(...),
  raw:group(...),
  raw:link(...),
})
```

Array entries are declarations. Named fields configure the module itself.

The plugin name is also the identity used by active/default fallback. Multiple
active files may return the same plugin identity and are all compiled. After the
complete active pass, default modules with an identity already present in the
active theme are skipped.

An empty module is therefore meaningful:

```lua
return p.setup("some-plugin", {})
```

It performs no highlight action, but the active theme now owns the
`"some-plugin"` identity and can intentionally suppress fallback modules with
that identity.

## Targets first: plugin modules default to no writable target

Plugin modules differ from language and UI modules in one important way:

| Target | Plugin default |
| --- | ---: |
| `vim` | `false` |
| `ts` | `false` |
| `lsp` | `false` |

That is deliberate. A plugin name does not tell ChromaFlow whether its names
belong to ordinary Vim highlight groups, Tree-sitter captures, LSP groups, or a
mixture of them.

For ordinary plugin highlight groups, declare the policy near the top:

```lua
return p.setup("nvim-cmp", {
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  p:group("CmpItemAbbr", { fg = c.fg }),
})
```

For a plugin exposing Tree-sitter captures:

```lua
return p.setup("example-parser", {
  style_targets = {
    vim = false,
    ts = true,
    lsp = false,
  },

  ...
})
```

A plugin may target more than one system when that is actually what its
highlight surface uses:

```lua
return p.setup("example-plugin", {
  style_targets = {
    vim = true,
    ts = true,
    lsp = true,
  },

  ...
})
```

### Group-local targets are allowed

A plugin module does not have to define module-wide targets if every resolved
group supplies its own policy:

```lua
return p.setup("mixed-plugin", {
  p:group("PluginNormal", {
    fg = c.fg,
    style_targets = { vim = true },
  }),

  p:group("PluginCapture", {
    fg = c.keyword,
    style_targets = { ts = true },
  }),
})
```

When `p.setup()` has no module-level `style_targets`, every normal `p:group()`
that needs resolver targets must provide `style_targets` itself.

This makes mixed modules possible without pretending all declarations belong to
the same target system.

### `p:link()` needs module targets

A standalone link declaration has no group table in which a local target policy
could be stored:

```lua
p:link("PluginAlias", "PluginBase")
```

Therefore `p:link()` requires module-level `style_targets`:

```lua
return p.setup("example-plugin", {
  style_targets = { vim = true },

  p:link("PluginAlias", "PluginBase"),
})
```

The same rule applies to module-level `mods`: plugin `mods` require explicit
module `style_targets`.

## Target precedence

`config.cf` remains the hard upper boundary for all resolved modules.

For a target that is globally enabled, a plugin group chooses its effective
value in this order:

1. Group `style_targets` value, if explicitly present.
2. Module `style_targets` value, if explicitly present.
3. Plugin default: `false`.

After that, the global config boundary is enforced. A target disabled by
`config.cf` cannot be re-enabled by a module or group.

For example:

```lua
return p.setup("mixed-plugin", {
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  p:group("PluginCapture", {
    fg = c.keyword,
    style_targets = { ts = true },
  }),
})
```

The group enables Tree-sitter over the module default, provided Tree-sitter is
still globally allowed by `config.cf`.

## `style_targets_clear`

Clearing is independent from writing.

```lua
return p.setup("example-plugin", {
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  style_targets_clear = {
    ts = true,
    lsp = true,
  },

  p:group("PluginThing", { fg = c.fg }),
})
```

The write mask says:

| Target | Result |
| --- | --- |
| Vim | Write |
| Tree-sitter | Do not write |
| LSP | Do not write |

The clear mask separately asks ChromaFlow to clear matching resolved
Tree-sitter and LSP targets.

Module and group clear masks are additive. A group may add clears with its own
`style_targets_clear`, but it does not cancel a module clear.

Global `style_targets_clear` from `config.cf` is handled at theme level before
module application.

## What a Vim-style plugin group becomes

Consider a normal plugin group:

```lua
return p.setup("nvim-cmp", {
  style_targets = { vim = true },

  p:group("CmpItemAbbr", {
    fg = c.fg,
  }),
})
```

`CmpItemAbbr` is passed through the resolver, but with only the Vim target
enabled the effective result is conceptually:

```lua
vim.api.nvim_set_hl(0, "CmpItemAbbr", {
  fg = "...",
})
```

If several names should share the same plugin style:

```lua
p:group("CmpItemAbbrMatch", {
  fg = c.orange,
  bold = true,

  types = {
    "CmpItemAbbrMatchFuzzy",
  },
})
```

the primary name owns the style and the additional `types` link to it:

```lua
vim.api.nvim_set_hl(0, "CmpItemAbbrMatch", {
  fg = "...",
  bold = true,
})

vim.api.nvim_set_hl(0, "CmpItemAbbrMatchFuzzy", {
  link = "CmpItemAbbrMatch",
})
```

These examples show the semantic shape, not a promise that every final theme
will contain exactly these physical writes. ChromaFlow interns equal styles and
the resolver may link a group to an already materialized group with the same
complete style instead of duplicating the style table.

That deduplication changes storage/link shape, not the identity of the plugin
declaration.

## Plugin groups still use the resolver

`p:group()` is not an alias for raw `nvim_set_hl()`.

The name is treated as a resolver base name and `style_targets` decides which
forms are writable.

For an unknown base name such as:

```text
PluginThing
```

the literal resolver forms are conceptually:

| Layer | Concrete name |
| --- | --- |
| Vim | `PluginThing` |
| Tree-sitter | `@PluginThing` |
| LSP | `@lsp.type.PluginThing` |

If all three targets are enabled and a style must be materialized, the normal
layering shape is:

```lua
vim.api.nvim_set_hl(0, "PluginThing", {
  fg = "...",
})

vim.api.nvim_set_hl(0, "@PluginThing", {
  link = "PluginThing",
})

vim.api.nvim_set_hl(0, "@lsp.type.PluginThing", {
  link = "@PluginThing",
})
```

So resolved plugin groups participate in the same general target/layer model as
other resolver-backed declarations.

This is also why plugin modules must say which systems they intend to own
instead of assuming that every plugin name is a Vim highlight group.

## Tree-sitter plugin captures

Plugins may define their own Tree-sitter captures. In that case a plugin module
can deliberately use the TS target:

```lua
return p.setup("example-parser", {
  style_targets = { ts = true },

  p:group("PluginSyntax", {
    typemods = {
      keyword = {
        fg = c.keyword,
        bold = true,
      },

      comment = {
        fg = c.comment,
      },
    },
  }),
})
```

Here the concrete TypeMod names are conceptually:

```text
@PluginSyntax.keyword
@PluginSyntax.comment
```

and can become writes such as:

```lua
vim.api.nvim_set_hl(0, "@PluginSyntax.keyword", {
  fg = "...",
  bold = true,
})

vim.api.nvim_set_hl(0, "@PluginSyntax.comment", {
  fg = "...",
})
```

The base `PluginSyntax` group does not need to have a style merely because its
TypeMods do.

That is useful for plugins whose public surface consists of concrete captures
rather than one styled base capture.

## `p:group(name, spec)`

A plugin group accepts the same resolved-group style surface used by UI
modules.

A compact example:

```lua
p:group("PluginSelection", {
  fg = c.fg,
  bg = c.selection,
  bold = true,

  pipeline = {
    hl.opacity.bg(20),
  },

  priority = 10,
})
```

The table may contain normal `nvim_set_hl()` style fields plus ChromaFlow
metadata such as:

```text
pipeline
types
typemods
style_targets
style_targets_clear
link
priority
```

`link` is mutually exclusive with style fields and `pipeline`.

## `types`

`types` adds more resolver base names that should follow the primary group:

```lua
p:group("GitSignsAdd", {
  fg = c.green,

  types = {
    "GitSignsAddNr",
    "GitSignsAddCul",
    "GitSignsStagedAdd",
  },
})
```

The primary group owns the style. Additional types link to the primary semantic
target rather than each receiving a duplicated style declaration.

With Vim-only plugin targets, the shape is conceptually:

```lua
vim.api.nvim_set_hl(0, "GitSignsAdd", {
  fg = "...",
})

vim.api.nvim_set_hl(0, "GitSignsAddNr", {
  link = "GitSignsAdd",
})

vim.api.nvim_set_hl(0, "GitSignsAddCul", {
  link = "GitSignsAdd",
})
```

Again, style deduplication may choose an equivalent existing style anchor.

## `typemods`

`typemods` describes concrete `type + modifier` combinations:

```lua
p:group("PluginSyntax", {
  typemods = {
    keyword = {
      fg = c.keyword,
      bold = true,
    },

    entry = {
      fg = c.comment,
    },
  },
})
```

Each TypeMod entry may be:

```text
true
false
style table
link table
```

### `true`

```lua
typemods = {
  selected = true,
}
```

reuses the finished base-group style.

This requires the base group itself to have a style.

### `false`

```lua
typemods = {
  selected = false,
}
```

requests removal/clear of that concrete TypeMod target.

### Style table

```lua
typemods = {
  selected = {
    bold = true,
    pipeline = {
      hl.brightness.fg(10),
    },
  },
}
```

starts from the finished base style and applies the TypeMod fields/pipeline on
top of it.

### Link table

```lua
typemods = {
  selected = {
    link = "PluginOther",
  },
}
```

creates a resolver-backed link for that concrete TypeMod.

A TypeMod cannot define its own `types`, nested `typemods`,
`style_targets`, or `style_targets_clear`. It inherits the effective targets of
its parent group.

## Module-level `mods`

`mods` describes modifiers without one concrete parent type:

```lua
return p.setup("semantic-plugin", {
  style_targets = {
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

Plugin `mods` require module-level `style_targets`.

That restriction is intentional: unlike `p:group()`, a module mod has no parent
group from which a per-group target policy could be inherited.

A mod may be:

```text
false
style table
link table
```

but it cannot override targets itself.

For most plugins exposing ordinary named Vim highlight groups, `mods` are not
needed. They are useful when the plugin surface genuinely participates in
semantic TS/LSP modifier naming.

## `p:link(source, target)`

A plugin link uses resolver names, not raw literal writes:

```lua
return p.setup("telescope", {
  style_targets = { vim = true },

  p:group("TelescopeNormal", {
    fg = c.fg,
    bg = c.line,
  }),

  p:link("TelescopeResultsNormal", "TelescopeNormal"),
})
```

With a Vim-only target policy the result is conceptually:

```lua
vim.api.nvim_set_hl(0, "TelescopeResultsNormal", {
  link = "TelescopeNormal",
})
```

If TS/LSP targets are enabled, the resolver applies the link across the
selected semantic layers as appropriate.

Because `p:link()` has no local spec table, it always uses the module-level
target policy.

## Style fields and pipeline

Plugin groups use the same immutable full-style model as other ChromaFlow
groups.

For example:

```lua
p:group("GitSignsAddLn", {
  bg = c.green,

  pipeline = {
    hl.opacity.bg(8),
  },
})
```

The explicit style fields are built first. Pipeline operations are then applied
in list order to that current style.

For the full pipeline model, see [`pipeline.md`](pipeline.md).

Low-level `cf.color.*` calls may still be used anywhere as ordinary Lua
functions, but they do not participate in ChromaFlow's pipeline ordering.

## `link` inside a group

A group may express its link inline:

```lua
p:group("GitSignsAddPreview", {
  link = "DiffAdd",
})
```

This is equivalent in intent to a resolver-backed link declaration for that
group.

Do not combine `link` with style fields or a pipeline:

```lua
-- invalid
p:group("PluginThing", {
  link = "OtherThing",
  fg = c.red,
})
```

A group is either styled or linked.

## `priority`

Every compiled action has a numeric priority.

```lua
p:group("PluginThing", {
  fg = c.blue,
  priority = 10,
})
```

Higher priority runs later and can therefore override lower-priority work.

For equal priority, declaration/action order is stable: later compiled actions
run later.

The ordering is global across the compiled theme rather than being reset for
each individual plugin file.

This matters when several modules intentionally address the same concrete
highlight target.

## `style_targets_clear` at group level

A group can add a clear policy locally:

```lua
p:group("PluginThing", {
  fg = c.fg,

  style_targets = {
    vim = true,
    ts = false,
  },

  style_targets_clear = {
    ts = true,
  },
})
```

The group writes the Vim target while separately clearing its resolved
Tree-sitter target.

The clear mask does not mean "clear before setting the same selected target
only." It is its own policy.

## `raw` inside a plugin module

Sometimes you do not want semantic target expansion at all.

Use the raw API:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local p = hl.plugin
local raw = hl.raw

return p.setup("example-plugin", {
  raw:group("ExactPluginGroup", {
    fg = c.orange,
  }),

  raw:link("ExactPluginAlias", "ExactPluginGroup"),
})
```

`raw:group()` and `raw:link()` use the exact names supplied.

They do **not**:

- classify the name as Vim/TS/LSP,
- expand it into other target systems,
- append a filetype,
- use plugin `style_targets`,
- use plugin `style_targets_clear`.

A raw declaration therefore has no `style_targets` fields.

For a raw group, the explicit pre-write clear switch is instead:

```lua
raw:group("ExactPluginGroup", {
  clear = true,
  fg = c.orange,
})
```

Conceptually:

```lua
vim.api.nvim_set_hl(0, "ExactPluginGroup", {})
vim.api.nvim_set_hl(0, "ExactPluginGroup", {
  fg = "...",
})
```

Use `raw` when the literal highlight name itself is the contract. Use
`p:group()` when you want ChromaFlow's resolver and target model.

## Error isolation

While a `.cf` theme file is being compiled, ChromaFlow isolates independently
compiled scopes so one invalid declaration does not unnecessarily discard
valid siblings.

A broken group rolls back that group's actions.

Inside a valid group, one broken TypeMod rolls back only that TypeMod; the base
group and valid sibling TypeMods can remain.

Diagnostics report the failed source location according to the configured
diagnostic policy.

Direct low-level use outside the loaded `.cf` environment retains the normal
assert/error contract.

## Plugin fallback identity is semantic, not a filename rule

These files may all be plugin modules:

```text
cmp.cf
completion.cf
my-ui-patches.cf
anything.cf
```

What matters is what they return:

```lua
return p.setup("nvim-cmp", { ... })
```

The `"nvim-cmp"` string defines the module identity.

Therefore two active files may both return:

```lua
p.setup("nvim-cmp", ...)
```

and both are compiled.

After all active modules have been seen, default-theme plugin modules named
`"nvim-cmp"` are suppressed because the active theme already owns that
identity.

This lets a plugin surface be split across multiple files without changing its
fallback semantics.

## A practical Vim-highlight plugin module

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local p = hl.plugin

return p.setup("gitsigns", {
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  p:group("GitSignsAdd", {
    fg = c.green,

    types = {
      "GitSignsAddNr",
      "GitSignsAddCul",
      "GitSignsStagedAdd",
    },
  }),

  p:group("GitSignsChange", {
    fg = c.yellow,
  }),

  p:group("GitSignsDelete", {
    fg = c.red,
  }),

  p:group("GitSignsAddLn", {
    bg = c.green,

    pipeline = {
      hl.opacity.bg(8),
    },
  }),

  p:group("GitSignsAddPreview", {
    link = "DiffAdd",
  }),
})
```

This is the common plugin case: explicit Vim ownership, grouped aliases, normal
style fields, links, and optional pipelines.

## A practical Tree-sitter plugin module

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local p = hl.plugin

return p.setup("example-parser", {
  style_targets = {
    ts = true,
  },

  p:group("PluginSyntax", {
    typemods = {
      keyword = {
        fg = c.keyword,
        bold = true,
      },

      comment = {
        fg = c.comment,
      },

      ["function"] = {
        fg = c.func,
        bold = true,
      },

      string = {
        fg = c.string,
      },
    },
  }),
})
```

This is intentionally different from the Vim-only case: the plugin owns
concrete Tree-sitter capture combinations, so the target policy says so
explicitly.

## Choosing between plugin, UI, language, and raw

Use a plugin module when:

- the highlight surface belongs to one plugin/feature identity,
- that identity should participate in active/default fallback,
- and the declarations should use the resolver target model.

Use a UI module when the groups are global editor UI rather than one plugin.

Use a language module when the declarations are semantic syntax for a filetype
or the global language layer.

Use `raw` declarations when the exact literal highlight group name is the
contract and no resolver expansion is desired.

The filename itself does not decide any of these. The returned setup call does.

## Minimal template

For a normal Vim-highlight plugin:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local p = hl.plugin

return p.setup("plugin-name", {
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },

  p:group("PluginGroup", {
    fg = c.fg,
  }),
})
```

For a plugin-owned Tree-sitter surface:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local p = hl.plugin

return p.setup("plugin-name", {
  style_targets = {
    vim = false,
    ts = true,
    lsp = false,
  },

  p:group("PluginCapture", {
    ...
  }),
})
```

The explicit target declaration is the important part: a plugin identity alone
does not imply how its highlight names should be materialized.
