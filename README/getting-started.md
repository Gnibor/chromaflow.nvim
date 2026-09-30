# Getting started

## Contents

- [1. Configure ChromaFlow](#1-configure-chromaflow)
- [2. Select the default and active theme](#2-select-the-default-and-active-theme)
- [3. Create `color.cf`](#3-create-colorcf)
- [4. Configure theme-wide target behavior with `config.cf`](#4-configure-theme-wide-target-behavior-with-configcf)
- [5. Create the first language module](#5-create-the-first-language-module)
- [6. Reload and inspect the result](#6-reload-and-inspect-the-result)
- [7. Design the theme with `CFPick`](#7-design-the-theme-with-cfpick)
- [8. Use the LuaSnip starters if available](#8-use-the-luasnip-starters-if-available)
- [9. Add UI and plugin modules when needed](#9-add-ui-and-plugin-modules-when-needed)
- [10. Understand the basic fallback model](#10-understand-the-basic-fallback-model)
- [11. Shared runtime modules](#11-shared-runtime-modules)
- [12. Useful first commands](#12-useful-first-commands)
- [13. Where to go next](#13-where-to-go-next)

This chapter takes ChromaFlow from an installed plugin to a small working theme.
It intentionally stays on the user-facing path. Resolver internals, pipelines,
runtime modules and the full DSL are covered in later chapters.

## 1. Configure ChromaFlow

Point ChromaFlow at a theme root and enable the picker if you want live editing:

```lua
require("cf").setup({
  theme_path = vim.fn.stdpath("config") .. "/themes",
  picker = true,
})
```

`theme_path` is the directory that contains `.cf-theme` and your theme
directories. Theme watching is enabled by default, so changes to the active
scope normally reload automatically.

`picker = true` enables `:CFPick` and `:CFSave`.

A minimal root looks like this:

```text
themes/
├── .cf-theme
└── mytheme/
    ├── color.cf
    └── lua.cf
```

`lua.cf` is only an example filename. ChromaFlow does not require language,
plugin or UI modules to follow a filename convention.

## 2. Select the default and active theme

`.cf-theme` must contain exactly two non-empty lines:

```text
mytheme
mytheme
```

The first line is the **default** theme. The second line is the **active** theme.

The default theme is also the fallback source when the active theme does not
provide a palette, config or module identity of its own.

You can change the active theme later with:

```vim
:CFTheme other-theme
```

or make the selected theme both active and default:

```vim
:CFTheme other-theme default=true
```

Running `:CFTheme` without arguments opens the theme menu.

## 3. Create `color.cf`

`color.cf` is one of the two reserved theme filenames. It returns the palette
shared by every module compiled for that theme load.

```lua
return {
  bg = "#111318",
  fg = "#d6d6d6",

  comment = "#73829a",
  variable = "#b7ccb9",
  ["function"] = "#d7ad7c",
  type = "#8dbfc8",
  keyword = "#b5a2ce",
}
```

A palette must exist somewhere in the reserved-file fallback chain:

```text
active theme -> theme root -> default theme
```

For a first theme, putting `color.cf` directly inside the theme directory is the
simplest option.

## 4. Configure theme-wide target behavior with `config.cf`

`config.cf` is the other reserved filename. It returns the theme-wide
`CFThemeConfig` table. The file itself is optional, but when it exists it **must
return a table**.

Like `color.cf`, `config.cf` is resolved through the reserved-file fallback
chain:

```text
active theme -> theme root -> default theme
```

The first existing `config.cf` in that chain wins. This means an active theme
that has no `config.cf` may inherit the root or default-theme config. If you
want to stop config fallback without changing any target settings, create an
active-theme `config.cf` containing only:

```lua
return {}
```

A completely empty `config.cf` is not valid: it returns `nil`, while ChromaFlow
requires the file to return a table. With `return {}`, fallback is stopped and
the normal default remains in effect: Vim/Neovim, Tree-sitter and LSP targets
are all writable.

The complete config currently has three fields:

```lua
---@type CFThemeConfig
return {
  style_targets = {
    vim = true,
    ts = true,
    lsp = true,
  },

  style_targets_clear = {
    vim = false,
    ts = false,
    lsp = false,
  },

  -- only_style_target = "ts",
}
```

You normally use only the fields you actually need. `false` entries in
`style_targets_clear` are equivalent to leaving them out.

### `style_targets`

`style_targets` defines the **hard theme-wide upper boundary** for writable
highlight systems:

| Target | Writes to |
| --- | --- |
| `vim` | Classic Vim/Neovim highlight groups |
| `ts` | Tree-sitter captures |
| `lsp` | LSP semantic-token highlight groups |

If the field is omitted, all three targets are enabled. A target explicitly set
to `false` cannot be re-enabled later by a language, plugin, UI module or an
individual group. Modules and groups may narrow the active targets further, but
never widen the boundary established by `config.cf`.

For example:

```lua
---@type CFThemeConfig
return {
  style_targets = {
    vim = true,
    ts = true,
    lsp = false,
  },
}
```

allows Vim and Tree-sitter materialization while making LSP a hard no-write
target for the complete theme.

The explicit all-target version:

```lua
style_targets = { vim = true, ts = true, lsp = true }
```

is therefore equivalent to the default behavior and is mainly useful when you
want the intended boundary to be obvious in the theme itself.

### `style_targets_clear`

`style_targets_clear` is independent from `style_targets`. It tells ChromaFlow
to clear existing highlights from selected target systems **globally before the
new theme modules are applied**.

For example, a deliberately clean Vim-only theme can use:

```lua
---@type CFThemeConfig
return {
  style_targets = {
    vim = true,
    ts = false,
    lsp = false,
  },
  style_targets_clear = {
    ts = true,
    lsp = true,
  },
}
```

The first table prevents the theme from writing TS/LSP styles. The second table
removes already-existing TS/LSP highlight material before the module actions
run.

Because clearing and writing are separate operations, this is also valid:

```lua
return {
  style_targets = { ts = true },
  style_targets_clear = { ts = true },
}
```

Tree-sitter highlights are cleared first and may then be materialized again by
the current theme.

### `only_style_target`

`only_style_target` is the convenience form for themes that intentionally own
only one semantic target system. Valid values are:

```text
"vim"
"ts"
"lsp"
```

For example:

```lua
---@type CFThemeConfig
return {
  only_style_target = "ts",
}
```

disables Vim and LSP as writable targets **and globally clears both of them**.
Only Tree-sitter remains available to the theme.

This is exactly what the bundled `examples/themes/ts-only/config.cf` uses.

`only_style_target` is applied as a hard boundary on top of `style_targets`; it
does not force the selected target back to `true` if you explicitly disabled it
there. In normal use, choose either `only_style_target` by itself or use
`style_targets` when you need a more specific combination.

### Which form should you use?

For most themes, use no `config.cf` at all or keep all three targets enabled.
Use `style_targets` when the theme deliberately should not write one or more
systems. Add `style_targets_clear` when those disabled systems should also be
removed from the current Neovim highlight state. Use `only_style_target` for the
common strict single-system case.

Unlike ordinary modules, `color.cf` and `config.cf` are selected by filename.
Those two names are therefore reserved.

## 5. Create the first language module

Every other `.cf` filename is free. The returned module determines what the
file is.

For example, `lua.cf`, `lang-lua.cf`, `syntax.cf` or `anything.cf` can all be a
Lua language module if they return `l.setup("lua", ...)`.

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language

return l.setup("lua", {
  l:group("comment", {
    fg = c.comment,
    italic = true,
  }),

  l:group("variable", {
    fg = c.variable,
  }),

  l:group("function", {
    fg = c["function"],
    types = { "method" },
  }),

  l:group("type", {
    fg = c.type,
    types = { "class", "struct", "enum", "interface" },
  }),

  l:group("keyword", {
    fg = c.keyword,
  }),
})
```

The important part here is not the filename. It is:

```lua
return l.setup("lua", { ... })
```

Language and plugin fallback also use these setup identities, not filenames.
That allows several files to contribute modules without turning naming
conventions into API rules.

## 6. Reload and inspect the result

After startup, ChromaFlow behaves like a normal colorscheme owner. The selected
theme is available as `vim.g.colors_name`, and normal `ColorSchemePre` /
`ColorScheme` callbacks run during apply.

To reload manually:

```vim
:CFReload
```

With the default `watch = true`, editing a watched theme file normally triggers
the same reload path automatically.

If you are debugging Neovim highlight behavior, remember that `:Inspect` shows
resolved highlight information. A link chain can therefore appear to point
directly at its final destination even when ChromaFlow created intermediate
LSP -> Tree-sitter -> Vim/Syntax links.

## 7. Design the theme with `CFPick`

The picker is intended to replace the repetitive theme-design loop:

```text
:Inspect
-> remember/copy a highlight name
-> switch to the theme
-> edit it
-> reload
-> return to the source
-> repeat
```

With `picker = true`, place the cursor on real code and run:

```vim
:CFPick
```

CFPick inspects the actual highlight information at the cursor and presents the
editable ChromaFlow targets. LSP and Tree-sitter information can both contribute
when both are present.

Picker edits are previewed immediately through the runtime layer. You can keep
adjusting the style while looking at the real source code instead of repeatedly
switching back to the theme file.

When the result is right, save the confirmed edits with:

```vim
:CFSave
```

If a language module exists, the selected target is missing locally, and the
current style is coming from `generic`, CFPick can ask whether the change should
be written to the language module or to the generic source.

The bundled files under:

```text
examples/showcase/
```

are useful theme-design playgrounds because they deliberately contain many
language constructs that can be inspected and edited in place.

## 8. Use the LuaSnip starters if available

ChromaFlow integrates with LuaSnip when LuaSnip is already loaded by your own
configuration. It does not load LuaSnip itself.

The main starter snippets are:

```text
language
plugin
ui
runtime
```

They generate the corresponding `.cf` module skeletons. Smaller group/link
helpers are registered as well.

The snippets only activate for a buffer that already has a real `.cf` filename.
An unnamed new buffer does not count as a `.cf` file yet. Save it first, then use
the snippet.

For example:

```text
:new
:w ~/themes/mytheme/extra.cf
```

After the buffer has a `.cf` path, the ChromaFlow snippets can become available.

## 9. Add UI and plugin modules when needed

The same pattern is used for other module kinds.

A UI module can be stored under any non-reserved `.cf` filename:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui

return u.setup({
  u:group("Normal", { fg = c.fg, bg = c.bg }),
  u:group("Visual", { bg = "#2d3f76" }),
})
```

A plugin module identifies itself through `p.setup()`:

```lua
local hl = require("cf.hl.setup")
local p = hl.plugin

return p.setup("my-plugin", {
  style_targets = { vim = true, ts = false, lsp = false },

  p:group("MyPluginTitle", {
    bold = true,
  }),
})
```

Again, filenames such as `core-ui.cf` or `plugin-my-plugin.cf` are useful
conventions, not requirements.

## 10. Understand the basic fallback model

A ChromaFlow theme root can contain a complete default theme and much smaller
active themes.

Reserved files use this lookup order:

```text
active theme -> theme root -> default theme
```

Lookup stops at the first existing reserved file. In particular, an active
`config.cf` containing only `return {}` deliberately blocks config fallback
while keeping the default target behavior.

Ordinary language/plugin/UI modules use **module identity fallback**.

An active module for an identity replaces the default module scope for that
identity. Fallback is not a per-group merge. For example, if the active theme
contains `l.setup("lua", ...)`, ChromaFlow does not fill missing Lua groups from
the default Lua module afterward.

This makes small variants possible without copying a complete theme. A variant
can provide only a palette, only a config, or a few module identities and let the
rest come from the default theme.

The bundled reference themes demonstrate these cases:

| Example theme | Demonstrates |
| --- | --- |
| `examples/themes/dark/` | Complete reference/default theme |
| `examples/themes/fallback/` | Selected module identities only |
| `examples/themes/palette/` | Palette override only |
| `examples/themes/ts-only/` | Config override only |

## 11. Shared runtime modules

`runtime/` is reserved as a runtime-module directory and is not treated as a
normal theme name.

Runtime modules are loaded only when requested. Their lookup order is:

```text
active theme/runtime -> theme root/runtime -> default theme/runtime
```

You do not need runtime modules to build a normal static theme or to use CFPick,
so they can safely be ignored until you need live programmatic style actions.

## 12. Useful first commands

| Command | Purpose |
| --- | --- |
| `:CFReload` | Reload the selected theme |
| `:CFPick` | Edit the target under the cursor |
| `:CFSave` | Persist confirmed picker edits |
| `:CFTheme` | Open the theme menu |
| `:CFTheme <name>` | Select a theme |
| `:CFTheme <name> default=true` | Select a theme and make it the default |

LineBlend and runtime commands are optional subsystems and are covered in their
own chapters.

## 13. Where to go next

Once the first theme loads, the most useful next topics are:

- **Theme structure and fallback** — active/default themes, reserved files and
  module identity rules.
- **Colors and pipelines** — palette use and reusable style transformations.
- **Language modules** — types, mods, typemods, aliases and style targets.
- **Plugin and UI modules** — literal/plugin/UI highlight scopes.
- **CFPick and CFSave** — live editing, source selection and persistence.
- **Resolver** — Vim/Syntax, Tree-sitter and LSP mapping/materialization.
- **Runtime** — live `apply`, `replace`, `clear` and `reset` actions.
- **Diagnostics and ColorTrace** — theme diagnostics and resolution tracing.
- **Tests and benchmarks** — regression suite and performance methodology.
- **FAQ** — behavior that can look surprising while still being intentional.

For working examples, start with:

```text
examples/themes/dark/
examples/showcase/
tests/full_benchmark.lua
```

The LuaLS metadata under `luals/library/cf/` is also useful as an API reference
while editing `.cf` files.
