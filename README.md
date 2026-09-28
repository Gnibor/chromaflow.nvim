# ChromaFlow.nvim

ChromaFlow is a semantic theme engine for Neovim. Themes are written as normal
Lua in `*.cf` files and compiled into Vim, Tree-sitter and LSP highlight groups.
One semantic declaration can cover several highlight systems, filetype variants,
TypeMods, plugin/UI groups and runtime effects without hard-coding every concrete
Neovim group name.


## Highlights

- semantic `language`, `plugin` and `ui` DSLs plus an exact `raw` escape hatch;
- one style can target Vim, Tree-sitter and LSP independently;
- Type aliases, TypeMods, Mod-only rules, links, clears and stable compile priority;
- colour pipelines for `fg`, `bg`, `sp`, `ctermfg` and `ctermbg`;
- theme inheritance by semantic module identity instead of filename;
- watched live reloads with the same transactional compile/apply path as `:CFReload`;
- sparse runtime overrides with `apply`, `replace`, `reset` and `clear`;
- optional `:CFPick` editor with live preview and `:CFSave` source persistence;
- optional diagnostics/debug tracing, LineBlend and LuaSnip helpers.

`*.cf` is registered as `filetype=lua`, so normal Lua syntax highlighting,
Tree-sitter and LuaLS can be used while authoring a theme.

## Installation

### packer.nvim

```lua
use "Gnibor/chromaflow.nvim"
```

### lazy.nvim

```lua
{
    "Gnibor/chromaflow.nvim",
}
```

### Neovim `vim.pack`

```lua
vim.pack.add({
    "https://github.com/Gnibor/chromaflow.nvim",
})
```

### vim-plug

```vim
Plug 'Gnibor/chromaflow.nvim'
```

Then configure ChromaFlow normally:

```lua
require("cf").setup({
    theme_path = vim.fn.stdpath("config") .. "/chromaflow",
    watch = true,
    picker = false,
})
```

See [Configuration](README/CONFIGURATION.md) for every option and command.

## Theme layout

A theme root contains `.cf-theme`, one or more theme folders, and optionally a
shared `runtime/` directory:

```text
chromaflow/
├── .cf-theme
├── runtime/
│   └── pulse.cf
├── dark/
│   ├── color.cf
│   ├── config.cf
│   ├── generic.cf
│   ├── lang-lua.cf
│   ├── core-ui.cf
│   └── plugin-telescope.cf
└── light/
    └── ...
```

`.cf-theme` contains exactly two non-empty lines: the default/fallback theme and
the active theme.

```text
dark
dark
```

Only `color.cf` and `config.cf` are reserved filenames. Every other `*.cf` file
is simply a module; its `setup()` call defines what it is. Active themes may be
partial: missing reserved files and module identities fall back to the default
theme. See [Themes and fallback](README/THEMES.md).

## Minimal theme

`color.cf` returns the shared palette:

```lua
return {
    bg = "#0f121b",
    fg = "#cfcfcf",
    comment = "#7890ab",
    func = "#d4aa78",
    keyword = "#b4a2cd",
    type = "#8ebfc9",
}
```

`config.cf` defines the hard target boundary:

```lua
return {
    style_targets = {
        vim = true,
        ts = true,
        lsp = true,
    },
}
```

A language module uses semantic names rather than concrete highlight names:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language

return l.setup("lua", {
    mods = {
        deprecated = { strikethrough = true },
    },

    l:group("comment", {
        fg = c.comment,
        italic = true,
    }),

    l:group("function", {
        fg = c.func,
        types = { "method" },
        pipeline = {
            hl.darken.fg(3),
        },
        typemods = {
            builtin = {
                pipeline = { hl.mix.fg(22, c.keyword) },
            },
            declaration = { bold = true },
        },
    }),

    l:group("type", {
        fg = c.type,
        types = { "class", "struct", "enum", "interface" },
    }),
})
```

ChromaFlow resolves the semantic requests to the usable Vim, Tree-sitter and
LSP forms for that language. A `types` entry becomes an alias of the primary
semantic Type. `typemods` describe `Type + TypeMod`; module-level `mods` describe
a Mod without a concrete Type.

Plugin modules use the same resolver without a filetype context and explicitly
select the systems they own:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local p = hl.plugin

return p.setup("telescope", {
    style_targets = { vim = true },

    p:group("TelescopeNormal", { fg = c.fg, bg = c.bg }),
    p:group("TelescopeTitle", { fg = c.keyword, bold = true }),
})
```

UI modules default to Vim highlights. `hl.raw` bypasses semantic resolution and
addresses exact Neovim highlight-group names. The full language is documented in
[DSL reference](README/DSL.md).

## Colour pipelines

Direct style fields are applied first, then pipeline operations run in order:

```lua
l:group("function", {
    fg = c.func,
    bg = c.bg,
    pipeline = {
        hl.shiftHue.fg(-5),
        hl.brightness.fg(20),
        hl.opacity.bg(8),
    },
})
```

Available operations are `mix`, `opacity`, `brightness`, `lighten`, `darken`,
`shiftHue` and `gamma`. Every operation supports `fg`, `bg`, `sp`, `cfg` and
`cbg`; `cfg`/`cbg` manipulate `ctermfg`/`ctermbg` without changing RGB fields.

## Runtime overrides

Runtime modules live in `runtime/<name>.cf` and define reusable actions. Lua code
loads them by logical name:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime("mystyleactions")

r.apply(hl.language.lua.variable, r.g.dim)
r.replace(hl.language.lua.function, r.g.focus)
r.reset(hl.language.lua.variable)
r.clear(hl.language.lua.function)
```

Runtime state is a sparse layer over the normal theme; it is recomposed against
the new base after theme reloads instead of keeping a second full theme cache.
Timed runtime functions are supported as explicit runtime pipeline operations.
See [Runtime modules](README/RUNTIME.md).

## Picker and saving

With `picker = true`, `:CFPick` inspects the semantic highlight under the cursor
and can edit Style, TypeMods and colour pipelines with live runtime preview.
Confirmed edits remain runtime-only until `:CFSave` rewrites the owning `*.cf`
source and performs the normal theme reload.

`CFSave` validates the generated Lua before replacing files and refuses stale
source snapshots. Source persistence requires the Lua Tree-sitter parser. See
[Picker and CFSave](README/PICKER.md).

## Commands

| Command | Purpose |
| --- | --- |
| `:CFTheme` | Open the theme menu. |
| `:CFTheme <name> [default=true]` | Select a theme; optionally make it the fallback too. |
| `:CFReload` | Compile and fully re-apply the selected theme. |
| `:CFPick` | Open the semantic picker when `picker=true`. |
| `:CFSave` | Persist confirmed picker edits when `picker=true`. |
| `:CFApply` / `:CFReplace` | Apply a runtime action from the command line. |
| `:CFReset` / `:CFClear` | Remove or clear a runtime target override. |
| `:LineBlendToggle` | Toggle LineBlend. |
| `:LineBlend <0..100>` | Change the LineBlend amount. |
| `:LineBlendReload` | Explicitly rebuild LineBlend's generated state. |

## Reference themes

`examples/themes/dark/` is the complete integration/reference theme. It covers
language, UI and plugin modules; Vim/Tree-sitter/LSP targets; semantic aliases;
TypeMods; TS-only captures; pipelines; links; runtime modules and fallback
behavior. The sibling `fallback`, `palette` and `ts-only` themes demonstrate the
three main fallback/target-policy cases.

Start with [examples/themes/README.md](examples/themes/README.md), then use the
actual `*.cf` files as executable examples.

## Documentation

- [Configuration and commands](README/CONFIGURATION.md)
- [Theme layout, selection, fallback and reload](README/THEMES.md)
- [DSL reference](README/DSL.md)
- [Runtime modules](README/RUNTIME.md)
- [Picker and CFSave](README/PICKER.md)
