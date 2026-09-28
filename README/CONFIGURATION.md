# Configuration

ChromaFlow is configured through `require("cf").setup()`.

```lua
require("cf").setup({
    theme_path = "/path/to/themes",
    alpha = false,
    watch = true,
    picker = false,

    autoreload = {
        lsp = false,
        treesitter = false,
    },

    diagnostic = {
        debug = false,
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

    lineblend = {
        autostart = true,
        blend = 50,
    },
})
```

## Options

### `theme_path`

Path to the ChromaFlow theme root. It contains `.cf-theme`, theme folders and
optionally root-level reserved fallbacks/shared runtime modules. ChromaFlow can
be loaded without `theme_path`, but theme loading/reload/theme-selection commands
need it.

### `alpha`

Default: `false`.

When enabled, ChromaFlow may preserve alpha in operations that support both alpha
and pre-composited output. The plugin does not guess whether a GUI supports
transparent colours.

### `watch`

Default: `true`.

Watches the active/default theme and relevant runtime locations. Filesystem event
bursts are merged by a 250 ms sliding debounce and use the same `cf.reload()` path
as an explicit reload.

### `picker`

Default: `false`.

Enables picker/source-tracking infrastructure plus `:CFPick` and `:CFSave`.
Keeping it disabled avoids the extra source-range/picker caches entirely.

### `autoreload`

Both options default to `false`:

```lua
autoreload = {
    lsp = false,
    treesitter = false,
}
```

`lsp=true` force-refreshes semantic tokens after the final theme/runtime state is
installed. `treesitter=true` restarts active Tree-sitter highlighters afterwards.
These are opt-in consumer refreshes, not part of semantic compilation itself.
An option is automatically disabled when the required Neovim API is unavailable.

### `diagnostic`

ChromaFlow has three diagnostic severities: `HINT`, `WARN` and `ERROR`. `INFO`
and `OK` are separate user messages. `DEPRECATED` and `UNNECESSARY` are tags,
not severities.

```lua
diagnostic = {
    debug = false,
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
}
```

Producers enqueue diagnostics while themes are compiled; rendering is flushed only
after the theme operation, keeping UI work out of resolver/parser hot paths. A
source visible in the current tabpage is rendered through `vim.diagnostic`;
otherwise the same diagnostic uses ChromaFlow's ASSERT fallback so it does not
silently disappear in another file/tab.

`debug=true` enables debug-only records and colour tracing used by the debug path.

### `lineblend`

```lua
lineblend = {
    autostart = true,
    blend = 50,
}
```

`blend` is `0..100`. Normal theme reloads call LineBlend's cached `refresh()`;
they do not discard its session cache. `:LineBlendReload` is the explicit hard
reload for that subsystem.

## Startup behavior

If `setup()` runs before `VimEnter`, ChromaFlow waits until `VimEnter` has
finished and schedules the first theme load afterwards. This gives plugins that
create highlight groups during startup a chance to populate the environment
before the resolver catalogs it. Calling `setup()` after `VimEnter` loads
immediately.

Calling `setup()` again updates the current configuration. Before `VimEnter`,
the final configured state wins.

## Commands

### Themes

```text
:CFTheme
:CFTheme <theme-name>
:CFTheme <theme-name> default=true
:CFReload
```

With no argument, `:CFTheme` opens the theme menu. Selecting a theme writes the
active line in `.cf-theme`; `default=true` also replaces the default/fallback
line. The watcher is stopped around ChromaFlow's own file write, preventing the
selection change from returning as a second delayed reload.

### Picker

Available only with `picker=true`:

```text
:CFPick
:CFSave
```

See [PICKER.md](PICKER.md).

### Runtime

```text
:CFApply   r.<module>.<action> <target>
:CFReplace r.<module>.<action> <target>
:CFReset   <target>
:CFClear   <target>
```

Target forms are:

```text
l.<language>.<type>[.<typemod>]
p.<plugin>.<type>[.<typemod>]
u.<type>[.<typemod>]
```

See [RUNTIME.md](RUNTIME.md).

### LineBlend

```text
:LineBlendToggle
:LineBlend 0..100
:LineBlendReload
```

## Optional LuaSnip integration

ChromaFlow does not load or configure LuaSnip. If LuaSnip is already loaded,
ChromaFlow registers convenience snippets for `*.cf` files. A scheduled startup
check and an `InsertEnter` retry cover normal lazy-loaded setups.

Full module skeleton triggers:

```text
language
plugin
ui
runtime
```

Common declaration triggers:

```text
lg / ll
pg / pl
ug / ul
rg
rawg / rawl
```

Normal Lua files also get `cfruntime`, which expands the runtime-loader boilerplate.

## LuaLS metadata

The repository ships public API/DSL metadata under `luals/library/cf/`. It is
editor documentation only and is not required at runtime. Add that directory to
your LuaLS library if your setup does not already discover plugin libraries.
