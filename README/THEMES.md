# Themes, fallback and reload

## Theme root

A ChromaFlow theme root looks like this:

```text
themes/
├── .cf-theme
├── color.cf                 # optional root fallback
├── config.cf                # optional root fallback
├── runtime/                 # optional shared runtime modules
│   └── pulse.cf
├── dark/
│   ├── color.cf
│   ├── config.cf
│   ├── generic.cf
│   ├── lang-lua.cf
│   └── core-ui.cf
└── light/
    └── ...
```

A valid theme directory contains at least one `*.cf` file. `runtime/` is reserved
infrastructure and is never offered as a selectable theme.

## `.cf-theme`

The root `.cf-theme` contains exactly two non-empty lines:

```text
<default-theme-folder>
<active-theme-folder>
```

The default theme is the fallback source. If the requested active directory is
missing/invalid, ChromaFlow applies the default theme while retaining the
requested name as selection state.

## Reserved files

Only two filenames are reserved:

```text
color.cf
config.cf
```

Every other `*.cf` filename is organizational only. The returned setup identity
decides what a module represents.

### `color.cf`

`color.cf` returns one palette table shared by every compiled module:

```lua
return {
    bg = "#0f121b",
    fg = "#cfcfcf",
    accent = "#feac33",
    syntax = {
        string = "#b5cc99",
        keyword = "#b4a2cd",
    },
}
```

Keys and nesting are unrestricted. `#RRGGBB` and `#RRGGBBAA` strings are
normalized to packed `0xAARRGGBB` integers before modules run.

Palette lookup order:

```text
active/color.cf
-> root/color.cf
-> default/color.cf
```

### `config.cf`

`config.cf` defines theme-level target policy:

```lua
return {
    style_targets = {
        vim = true,
        ts = true,
        lsp = true,
    },

    style_targets_clear = {
        -- vim = true,
        -- ts = true,
        -- lsp = true,
    },

    only_style_target = nil, -- "vim" | "ts" | "lsp" | nil
}
```

Config lookup order is the same:

```text
active/config.cf
-> root/config.cf
-> default/config.cf
```

`style_targets` is the hard upper permission boundary. A module/group may narrow
or choose targets inside it but cannot re-enable a system disabled by config.
`only_style_target` is a convenience hard restriction and also schedules the
other systems for the config-level global clear.

`style_targets_clear` is an action, not inheritance. Config-level clear runs once
before theme materialization; module/group clears affect only the semantic targets
that declaration would address. Target selection and clearing are independent.

## Module identities

Normal theme files return exactly one of:

```lua
hl.language.setup(...)
hl.plugin.setup(...)
hl.ui.setup(...)
```

Language identity is its filetype/language argument:

```lua
l.setup("lua", { ... })
l.setup(nil, { ... }) -- global syntax module
```

Plugin identity is only a fallback/runtime scope name, not a filetype:

```lua
p.setup("telescope", { ... })
```

UI has one global identity:

```lua
u.setup({ ... })
```

An empty module is legal and useful when a theme deliberately covers an identity
without creating additional groups:

```lua
return p.setup("project-manager", {})
```

## Fallback is by setup identity, not filename

ChromaFlow first compiles every active module and records its semantic setup
identities. Duplicate identities inside the active theme are allowed, so one
language/plugin can be split across several files.

Only after the complete active pass is collected does the default pass begin.
During that pass:

```text
active has l.setup("lua", ...)
-> every default l.setup("lua", ...) is skipped

active has p.setup("telescope", ...)
-> every default p.setup("telescope", ...) is skipped

active has u.setup(...)
-> every default u.setup(...) is skipped
```

If the active theme does not define an identity, all default modules for that
identity may compile. There is no per-file or per-group merge between active and
default modules.

This is demonstrated by:

- `examples/themes/fallback/` — partial Lua + CodeMap identity replacement;
- `examples/themes/palette/` — active palette with complete default module/config fallback;
- `examples/themes/ts-only/` — active config boundary with palette/module fallback.

## Runtime module lookup

A requested runtime module `hl.runtime("pulse")` resolves one file, first hit
wins:

```text
active/runtime/pulse.cf
-> root/runtime/pulse.cf
-> default/runtime/pulse.cf
```

Runtime modules are not merged across levels.

## Compile/apply lifecycle

A reload is transactional up to the visible colorscheme rebuild. ChromaFlow
resolves reserved resources, compiles/validates active modules, freezes the
active identity registry, compiles uncovered fallback modules and resolves every
requested runtime module before destructive highlight reset begins.

When compilation is ready, apply performs the real colorscheme lifecycle:

```text
ColorSchemePre
-> :highlight clear
-> :syntax reset (when syntax is enabled)
-> refresh highlight catalog + resolver cache
-> config-level global clear
-> stable apply of all compiled style/link/clear actions
-> set g:colors_name
-> ColorScheme
-> rebuild/reapply active sparse runtime overrides
-> optional Tree-sitter restart
-> optional LSP semantic-token refresh
-> redraw!
-> cached LineBlend refresh
```

Individual broken normal `*.cf` modules are reported and skipped locally when
possible; valid siblings continue. Missing required reserved resources, requested
runtime-module failures and other non-recoverable contracts still abort before
visible application.

## Watcher

With `watch=true`, edits to active/default theme files and relevant runtime
locations use the exact same reload path as `:CFReload`. Event bursts are folded
into one 250 ms sliding-debounce reload.

## Reference themes

The executable reference set lives under `examples/themes/`:

```text
dark/       full integration theme
fallback/   setup-identity fallback behavior
palette/    reserved palette override
runtime/    shared runtime actions
ts-only/    target boundary/global clear behavior
```

Start with `examples/themes/README.md`; `dark/` is the most useful source when
writing a real theme.
