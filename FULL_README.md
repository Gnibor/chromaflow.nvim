# cf.nvim v0.0.8

Clean-room ChromaFlow core for compiling `.cf` theme modules into Neovim
highlight groups.

The design goal is simple: theme files get one compact DSL with enough control
for Vim, Tree-sitter, LSP, UI, plugin and literal highlight groups. The runtime
layer reuses those compiled/materialized targets without feeding anything back
through semantic resolution.

## Runtime layout

```text
cf.config
    plugin/runtime options: alpha, theme_path, watch, picker, autoreload, diagnostic, lineblend

cf.debug
    one debug-mode lifecycle entrypoint
    .cf debug keymaps + debug-on-view refresh
    activates colour tracing only while debug is enabled

cf.diagnostic
    queued HINT/WARN/ERROR diagnostics + INFO/OK user messages
    current-tab vim.diagnostic rendering + ASSERT fallback
    history/pending/flush policy

cf.color
    packed 0xAARRGGBB colour math
    ARGB/hex <-> xterm-256 palette conversion

cf.colortrace
    shared colour-pipeline trace feature for debug + picker
    debug consumes traces directly; picker alone owns the persistent trace cache

cf.hl.pipeline
    pipeline builders + execution on fg/bg/sp and independent cfg/cbg

cf.hl.setup
    public .cf module environment
    l/p/u/raw DSL
    callable runtime DSL/loader
    target/clear hierarchy
    link/group/typemod compilation
    stable compile priority
    complete hl_set construction
    session-lifetime style interning

cf.hl.resolver
    semantic Vim / Tree-sitter / LSP resolution for language/plugin/UI modules
    naming-deviation + writable policy
    type/typemod ownership-aware set/clear/link operations
    literal autofallback for unresolved semantic targets

cf.hl.runtime
    actual nvim_set_hl backend
    raw literal set/link operations
    normal base-style/materialization cache
    cache-independent sparse runtime writes
    config-level global clear

cf.fn.runtime
    one process-wide runtime state
    apply / replace / reset / clear
    stable semantic target + action handles
    picker Style previews reuse the same sparse runtime cache and normal style interning

cf.picker
    CFPick semantic reverse lookup + picker feature lifecycle
    Edit -> Style tri-state editor (unset/true/false) with live runtime preview/commit
    includes dim/conceal; blend is numeric 0..100 (unset is distinct from 0)
    blend: +/- changes by 1, Alt--/Alt-+ by 10; Space unsets the value
    enables exact source ranges and picker colour/source caches for persistence
    TypeMods lists only existing session highlights for the selected Type/filetype
    = toggles exact Type style; x toggles exclusion; CR opens the existing TypeMod editor
    CFPick resolves cursor axes once; only Type -> TypeMods enumerates session combinations
    Mod -> Style creates missing rules in the cursor Type's already resolved module
    no extra resolver path; discovery is picker-local and refreshed when the menu opens

cf.save
    cold-path CFSave writer for confirmed picker edits
    derives source changes from picker identity + compiled base style + sparse runtime state
    rewrites only affected Style fields, then the normal theme reload owns cache invalidation
    TypeMod fields whose live unset has no exact parent-relative DSL form stay unchanged in source
    confirmed TypeMod rules and newly edited Mods/TypeMods are written into their source tables

cf.picker_pipeline
    lazy five-column FG/BG/SP/CFG/CBG editor using cf.fn.float
    Enter on Base/mix opens the active resolved color.cf palette (including nested keys)
    inherited bases are active without generating explicit source overrides
    unset channels are dimmed; CFG/CBG show their FG/BG fallback separately
    n/Enter-new inserts, d removes, +/- adjusts, Alt +/- adjusts by ten
    gamma is displayed in hundredths (110 means 1.10); 1..5 select channels
    a commits the draft; BS cancels/back; q/Esc cancels/closes; CFSave persists
    existing DSL executes previews; cf.colortrace provides source pipeline traces
    no new persistent colour/style cache; pending records describe source edits
    global operation order is preserved despite the per-channel display

cf.theme
    .cf-theme selection
    color/config fallback
    setup-identity module fallback
    full module compile before apply
    full Neovim colorscheme rebuild on load/reload

cf.watcher
    active/default directory watching
    active/root/default runtime/ directory watching
    one 250 ms sliding-debounce batch per event burst

cf.snippets
    optional LuaSnip snippets for .cf modules/declarations
    normal-Lua cfruntime helper

cf.usr_cmd
    CFReload / CFTheme / CFPick / CFSave
    LineBlend user commands
```

`*.cf` files are registered as `filetype=lua`, so normal Lua syntax,
Tree-sitter and LuaLS work while editing a theme.

---

# Plugin setup

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
        severity = { hint = false, warn = false, error = true },
        messages = { info = true, ok = true },
    },
    lineblend = {
        autostart = true,
        blend = 50,
    },
})
```

`alpha` is explicit. ChromaFlow does not try to guess whether the active GUI
supports alpha colours.

`autoreload.lsp` and `autoreload.treesitter` default to `false`. They are
explicit opt-ins for consumers that really need a full semantic-token refresh
or Tree-sitter highlighter restart after theme apply/reload. During setup,
ChromaFlow also disables an enabled flag when the required Neovim API is
unavailable.

LineBlend is configured through `setup()`:

```lua
lineblend = {
    autostart = true, -- default
    blend = 50,       -- default, 0..100
}
```

The LineBlend rendering engine remains self-contained in `cf.fn.lineblend`.
ChromaFlow configures and starts/stops it, but does **not** hard-reload its
session caches during normal theme reloads.

User commands:

```text
:CFReload
:CFTheme <theme-name> [default=true]

:LineBlendToggle
:LineBlend 0..100
:LineBlendReload
```

`CFReload` uses the same reload path as the watcher. `CFTheme` persists the
selected active theme in `.cf-theme` and applies it once. `default=true` also
replaces the default/fallback theme. ChromaFlow stops its watcher before
writing `.cf-theme`, so a command-driven theme switch cannot re-enter through
the filesystem watcher as a second delayed reload. Theme-name completion is
provided from valid theme directories below `theme_path`.

`LineBlendToggle` toggles the existing LineBlend instance. `LineBlend` changes
the blend amount without changing enabled state. `LineBlendReload` is the
explicit hard-reload path: it discards/rebuilds LineBlend's generated highlight
cache and current render state.

Initial theme compilation/application never runs before `VimEnter`. If `setup()`
is called during startup, ChromaFlow waits for `VimEnter` and schedules the first
load after that event has finished, so plugins creating highlight groups during
startup/VimEnter are visible to the resolver. Calling `setup()` after `VimEnter`
loads immediately.

`cf.diagnostic` is configured through the `diagnostic` setup block. Diagnostic
severity is only `HINT`, `WARN`, or `ERROR`; `INFO` and `OK` are separate user
messages, while `DEPRECATED` and `UNNECESSARY` are orthogonal tags. Diagnostics
use a sparse internal 0..255 severity space (`64/128/192`), and
`severity_bias` shifts the effective diagnostic severity without changing the
producer's base severity. `debug = true` opens the normal visibility filters and
also shows records marked debug-only.

Every stored output requires `file`, 1-based `line`, and 1-based `col`. Producers
only enqueue records; the completed theme load/reload flushes them afterwards so
diagnostic UI never runs in parser/resolver hot paths. If the source file is
visible in a window of the **current tabpage**, the record is rendered through
`vim.diagnostic` in that buffer. Otherwise the same HINT/WARN/ERROR is rendered
through the ASSERT fallback so an error cannot disappear merely because its file
is hidden or only visible in another tabpage. ASSERT is an output form, not a
fourth severity and not Lua `assert()`.

DSL declarations also keep source provenance. `l/p/u/raw` `group()`/`link()`
calls, the corresponding module `setup(...)`, and runtime `r:group()` /
`r.setup(...)` carry:

```lua
source = {
    file = "...",
    line = 12,
    col = 2,
    end_line = 16,
    end_col = 4,
}
```

Start coordinates are 1-based. `end_line`/`end_col` are also stored as 1-based
coordinates but remain **end-exclusive**, matching Tree-sitter/Neovim text-range
semantics after subtracting one. Full ranges are resolved with the Lua
Tree-sitter parser and cached per source-file signature. Tree-sitter is optional
for this metadata: if the Lua parser is unavailable, normal theme compilation
and start-only diagnostics continue to work and only `end_line`/`end_col` are
omitted.

Compiled normal modules retain their module `source` plus their declaration
tables; runtime definitions retain module `source`, declaration tables and
per-group sources. This provenance is internal infrastructure for tooling such
as inspectors/editors, not a replacement for the public DSL.
With picker enabled, normal modules also retain a reference to their `mods`
declarations for editing their original pipelines; this is not a copy of styles.

The Pipeline editor currently edits literal pipeline tables containing direct
standard colour-operation calls. Unchanged expressions are retained; edited
arguments are replaced and added palette references stay as the module-local
`c.*` DSL references. Existing operation text comes from the compile/colortrace
function start/end ranges instead of rediscovering the calls during save.
Comments are retained (standalone/inter-operation comments are collected at the
top when a pipeline's structure is rewritten). A source file changed after the
editor opened is rejected by CFSave rather than overwritten. Computed pipeline
tables, arbitrary callbacks and linked styles are not silently converted: the
editor reports them as unsupported; for a link, edit its owning style instead.
Save validates the complete generated Lua before touching files.

Theme-module execution failures are local: the failing module is marked
`failed`, reported as `ERROR`, and skipped while sibling modules continue. A `.cf`
file that executes successfully but does not return an `l.setup(...)`,
`p.setup(...)`, or `u.setup(...)` theme module is marked `ignored`, reported only
as a `HINT`, and is not treated as a failed module.
The existing "useless" DSL notices are routed through the same manager as
`HINT` records tagged `UNNECESSARY`. Fatal theme/resource errors and programmer
contract assertions remain fatal where meaningful processing cannot continue.

---

# Reload lifecycle

`cf.reload()` is a real colorscheme rebuild inside the running Neovim session,
not only a recompile of ChromaFlow tables. Compilation and validation complete
first; only then does visible state change:

```text
compile + validate complete theme
    -> ColorSchemePre
    -> :highlight clear
    -> :syntax reset (when syntax highlighting is enabled)
    -> invalidate only runtime materialization state
    -> rebuild CF catalog/resolver state
    -> config-level global clear
    -> apply every compiled style/link/clear action
    -> set g:colors_name to the selected theme folder
    -> ColorScheme
    -> lazily rebuild only target data used by active runtime overrides
    -> reapply the sparse runtime diff against the new theme base
    -> optionally restart active Tree-sitter highlighters (autoreload.treesitter=true)
    -> optionally force-refresh active LSP semantic tokens (autoreload.lsp=true)
    -> redraw!
    -> cached LineBlend refresh (when active; no LineBlend cache reset)
```


Watcher-triggered theme edits use the same `cf.reload()` path as an explicit
reload. They do not perform a second LineBlend reload/refresh of their own.
LineBlend's own activation and `ColorScheme` handling remain internal to the
LineBlend tool; ChromaFlow only issues the final cached `refresh()` after a
normal CF reload. Numeric `0` is not used as a false flag because Lua treats
`0` as truthy.

The session-lifetime style interning cache is deliberately **not** cleared.
Identical complete `hl_set` objects therefore keep the same Lua reference across
reloads, while every direct highlight is still materialized again after
`:highlight clear`. This removes stale groups from deleted/changed theme files
and guarantees that watcher-driven live edits produce the fresh visible result.

---

# Bundled reference themes

`examples/themes/dark/` remains the complete integration/reference theme. It
contains the full palette/config, core UI + generic syntax, language modules and
plugin modules and deliberately exercises Vim, Tree-sitter, LSP, filetype
variants, types, typemods, custom captures, typemod-owned styles, links,
pipelines and style interning.

Three intentionally small themes sit next to it and stress fallback behavior:

```text
examples/themes/
    .cf-theme             # default + active selection
    runtime/              # shared theme-aware runtime modules
    dark/                 # complete default/integration theme
    fallback/             # partial lua + codemap identities only
    palette/              # color.cf only
    ts-only/              # config.cf only
```

- `fallback` proves that module fallback is by `setup()` identity, not filename
  or individual group. Its active Lua/CodeMap identities replace those default
  identities while every unrelated module falls back from `dark`.
- `palette` overrides only the reserved palette. Every module and config entry
  falls back, but the fallback modules receive the active palette.
- `ts-only` overrides only config with `only_style_target = "ts"`; palette and
  modules fall back while the target boundary/global-clear path is exercised.

See `examples/themes/README.md` and each theme's local README for the exact test
intent. `tests/semantic_theme_headless.lua` remains the full dark-theme
acceptance test.

Load it from a checkout with:

```lua
require("cf").setup({
    theme_path = vim.fn.getcwd() .. "/examples/themes",
    watch = true,
})
```

`generic.cf` is `l.setup(nil, ...)`; `lang-lua.cf` is `l.setup("lua", ...)`.
The integration theme therefore exercises both global syntax groups and
language-specific Vim/Tree-sitter/LSP forms.

---

# Theme root

Only two `.cf` filenames are reserved:

```text
color.cf
config.cf
```

Every other `.cf` filename is purely organizational. These are all valid:

```text
lua.cf
meinsuperluatheme.cf
ui-dark.cf
git-zeugs.cf
whatever.cf
```

The file itself declares its role by returning one of:

```lua
l.setup(...)
p.setup(...)
u.setup(...)
```

## `.cf-theme`

The theme root contains `.cf-theme` with exactly two non-empty lines:

```text
default-theme-folder
active-theme-folder
```

Folder names are used exactly as written.

## Reserved-file fallback

Palette:

```text
active/color.cf
    -> root/color.cf
    -> default/color.cf
```

Config:

```text
active/config.cf
    -> root/config.cf
    -> default/config.cf
```

## Module fallback is by setup identity, never filename

The active theme is compiled completely first. During that pass setup
identities are only collected; they do not suppress another active file.
Therefore all of these may compile together:

```lua
-- active/lua-base.cf
return l.setup("lua", { ... })

-- active/lua-docs.cf
return l.setup("lua", { ... })
```

Only after the complete active pass succeeds does the registry become the
fallback filter:

```text
l.setup("lua", ...)
    -> language identity "lua"

p.setup("render-markdown", ...)
    -> plugin identity "render-markdown"

u.setup(...)
    -> one UI identity
```

During the default/fallback pass:

```text
active registered language "lua"
    -> every default l.setup("lua", ...) returns immediately

active registered plugin "cmp"
    -> every default p.setup("cmp", ...) returns immediately

active registered UI
    -> every default u.setup(...) returns immediately
```

The fallback pass never extends the active registry. So if active contains no
Lua setup, several default files may all return `l.setup("lua", ...)` and all
of them compile.

This gives the active theme full freedom to split one language/plugin/UI theme
across as many arbitrarily named files as it wants.

---

# One require for a theme module

A normal `.cf` module only needs:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language
```

The same object exposes everything needed by theme code:

```text
hl.colors
hl.language
hl.plugin
hl.ui
hl.raw
hl.runtime

hl.mix
hl.opacity
hl.brightness
hl.lighten
hl.darken
hl.shiftHue
hl.gamma
```

`hl.colors` is the exact resolved `color.cf` table for the current compile.
It is shared by every module; it is not copied per file.

The colour-operation tables are direct references from `cf.hl.pipeline`.
`cf.hl.setup` only exposes them conveniently.

---

# Runtime theme modules

Runtime modules are ordinary `.cf` files under a `runtime/` directory. They are
loaded by logical module name, never by filename/path:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime("mystyleactions")

r.apply(hl.language.lua.variable, r.groups.dim)
r.replace(hl.language.lua.variable, r.g.focus) -- `g` is the short alias for `groups`
r.reset(hl.language.lua.variable)
r.clear(hl.language.lua.variable)
```

`hl.runtime` is callable outside runtime files and becomes a module-scoped DSL
proxy while one runtime `.cf` file is being loaded. That proxy stays captured by
functions declared in the file, so its functions/state belong to that runtime
module instead of a process-global declaration table:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime

local pulse = 0

function r.alert(style, ctx)
    pulse = pulse + 1
    style.bold = ctx.frame % 2 == 0
    return style
end

return r.setup({
    r:group("dim", {
        pipeline = { hl.brightness.fg(-20) },
    }),

    r:group("panic", {
        pipeline = {
            r:func("alert")[300],
        },
    }),
})
```

`r:func("name")` is the explicit adapter from a normal Lua function stored on
that runtime module (`r.name`) into a full-style pipeline operation. Raw Lua
functions are deliberately not accepted as pipeline entries. The function gets
the current working highlight style and a context table and may mutate the style
in place and return `nil`, or return a replacement style table.

The optional numeric suffix is a millisecond tick:

```lua
r:func("alert")       -- evaluate when apply/replace/recompose runs
r:func("alert")[300]  -- also re-evaluate the action every 300 ms
```

Timed callbacks receive:

```text
ctx.frame    0, 1, 2, ... (frame 0 is rendered immediately)
ctx.tick     the function's requested interval in milliseconds, or nil
ctx.delta    actual milliseconds since the previous tick
ctx.elapsed  actual milliseconds since this runtime action started
```

A runtime action has one frame clock, so multiple timed functions in the same
action may share one interval but cannot request conflicting intervals. `reset`,
`clear`, or replacing the target with another action stops/replaces its timer.
Normal theme reloads rebind the action/function implementation and restart its
clock against the new theme base.

Assignments such as `function r.alert(...) ... end` are module exports. After
loading, the same function is available on the public module handle:

```lua
local panic = hl.runtime("panic")
print(panic.alert)
```

Functions captured from the runtime file can also use that module's normal
runtime API (`r.apply`, `r.replace`, `r.reset`, `r.clear`, `r.groups.*` / `r.g.*`) because
the proxy remains bound to its logical module.

For `hl.runtime("mystyleactions")` ChromaFlow resolves exactly one file:

```text
<theme-root>/<active>/runtime/mystyleactions.cf
    -> if absent: <theme-root>/runtime/mystyleactions.cf
    -> if absent: <theme-root>/<default>/runtime/mystyleactions.cf
```

The first hit wins; runtime files are not merged across levels. `runtime/` is a
reserved infrastructure directory and is not returned by `cf.theme.available()`.
The watcher has dedicated non-recursive handles for all three runtime locations,
so edits use the normal `cf.reload()` path.

Runtime does not capture every materialized action during a normal theme load.
The normal theme stays on the original fast materialization path. Only when a
semantic target is actually modified does Runtime inspect the resolver's already
built name caches for that target and build a tiny target entry. Stable handles
such as `hl.language.lua.variable`, `hl.plugin.codemap.CodeMap.keyword`,
`hl.ui.Normal` and `hl.raw.SomeExactGroup` therefore stay lazy until used.

The visible runtime state is a sparse diff over the normal theme:

```text
runtime[name] == nil    no runtime modification
runtime[name] == false  explicitly cleared by runtime
runtime[name] == style  runtime style override
```

Runtime writes never replace the normal `cf.hl.runtime` base-style cache. A
normal theme reload therefore pays no per-action runtime capture cost; only
currently active runtime targets are recalculated afterwards.

The four operations are deliberately small:

```text
apply(target, action)
    current theme base + runtime action/pipeline

replace(target, action)
    runtime action only; the theme base is not inherited

reset(target)
    remove this runtime diff entry and make the current theme base visible again

clear(target)
    clear the concrete highlight groups for this semantic target
```

`apply()` always recomputes from the theme base, not from the previous runtime
result, so repeated calls cannot accumulate pipeline drift. Runtime overrides
survive normal theme reloads/theme switches and are recalculated against the new
base. Public module/action/target handles stay stable while their theme-specific
backing data changes. All runtime modules and plugin-internal users share the
same single `cf.fn.runtime` state.

---

# `color.cf`

`color.cf` returns only a palette table:

```lua
local c = {
    fg = "#c3c3c3",
    bg = 0xff050a1b,
    ["function"] = 0xffa58a20,
    black = "#080808",
}

return c
```

Colour names are conventions, not restrictions. Any keys/nested tables are
allowed.

Internally colours are packed `0xAARRGGBB` integers. `#RRGGBB` becomes fully
opaque; `#RRGGBBAA` is converted to the corresponding packed alpha value.

---

# `config.cf`

`config.cf` is theme policy, separate from the palette:

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

## `style_targets`

Targets are permission/default policy:

```text
config.cf
    hard upper boundary
        ↓
module
    default inside that boundary
        ↓
group()
    local override inside that boundary
```

For each of `vim`, `ts`, `lsp`:

```text
config=false
    -> always false

otherwise group explicitly set
    -> group value

otherwise module explicitly set
    -> module value

otherwise
    -> module-kind default/config value
```

Language modules fall back to the config target value. UI modules insert a
Vim-only default (`vim=true, ts=false, lsp=false`) beneath ordinary module/group
overrides. Plugin modules insert an all-false default and therefore must opt in
with `style_targets` for every resolver-backed declaration, either at module or
group level. The config remains the hard upper boundary in every case.

`only_style_target` is a global hard restriction. Every other system is also
scheduled for the config-level global clear.

## `style_targets_clear`

Clear is an action, not target inheritance:

```text
config clear
    -> once globally before theme materialization

module clear
    -> before every group/typemod/link this module handles

group clear
    -> before this group's resolved targets are materialized
```

Module and group clear values are additive.

Most importantly, clear is independent from target selection:

```lua
style_targets = {
    vim = true,
    ts = false,
    lsp = false,
},

style_targets_clear = {
    ts = true,
    lsp = true,
},
```

means:

```text
TS   -> clear, do not set again
LSP  -> clear, do not set again
Vim  -> set/link normally
```

The semantic resolver still respects ownership/writable information. A broad
fallback group that the semantic resolve would not itself write is not removed
by a local clear.

Within `style_targets_clear` policy, only `config.cf` performs a global
syntax-target clear. Module/group clears only touch what that module/group would
itself address. This is separate from the full `:highlight clear` that starts
every colorscheme rebuild described in the reload lifecycle above.

---

# Module kinds

## Language

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language

return l.setup("lua", {
    ...
})
```

The first argument is semantic: it is the language/filetype context used for
language-specific Vim, Tree-sitter and LSP forms.

Global syntax module:

```lua
return l.setup(nil, {
    ...
})
```

A language module clear therefore naturally means:

```text
language present -> language-specific syntax hl_groups
language nil     -> global syntax hl_groups
```

## Plugin

```lua
local p = require("cf.hl.setup").plugin

return p.setup("render-markdown", {
    style_targets = { vim = true, ts = false, lsp = false },
    ...
})
```

The first argument is the plugin/fallback identity only. It is not a filetype.
Plugin declarations use the normal resolver with no filetype context;
`style_targets` tells it which Vim/Tree-sitter/LSP forms this plugin uses.

Plugins have no implicit target system. A resolved `p:group()` must therefore
get `style_targets` either from `p.setup()` or from that group itself. `p:link()`
and module mods use module targets and therefore require module-level
`style_targets`. Identity-only or raw-only plugin modules need no target mask.

For example, a Vim-only plugin may use `p:group("ITHNormal", ...)`, while a
Tree-sitter plugin can select `ts` and use the resolver base name for its
capture. Literal full names remain the job of `raw`.

## UI

```lua
local u = require("cf.hl.setup").ui

return u.setup({
    ...
})
```

UI has one setup identity and therefore needs no first name parameter. Its
normal target default is Vim only:

```lua
{ vim = true, ts = false, lsp = false }
```

That is only a default. The ordinary module/group `style_targets` flags can
override it, so an individual `u:group()` may deliberately target Tree-sitter
or LSP as well.

---

# Semantic resolver invariants

`l`, `p` and `u` declarations pass **semantic names** to the resolver. `raw` is
the only API whose names are always treated as exact literal hl_group names.
The semantic resolver may still materialize a literal name as an autofallback
when no usable semantic representation exists.

The resolver keeps four concerns separate:

```text
semantic name
    -> naming knowledge / aliases
    -> environment existence
    -> writable ownership
    -> requested Vim / TS / LSP target mask
```

A name being a valid semantic fallback does **not** automatically make it a
writable destination.

## Naming deviations are knowledge, not write permission

Only real naming deviations live in the resolver maps. Examples:

```text
method
    Vim  -> Function          (known fallback, not writable as method)
    TS   -> function.method
    LSP  -> method

builtin
    TS   -> builtin
    LSP  -> defaultLibrary
```

Likewise, known LSP modifiers such as `readonly`, `static`, `deprecated` and
`async` may be addressed as LSP modifier names even when the concrete
`@lsp.mod.*` group was not present in the initial environment catalog.

The environment catalog still decides whether an ordinary mapped candidate
actually exists. A broad fallback marked non-writable may be used for semantic
resolution/link targeting, but a narrower declaration must not overwrite or
clear that broad fallback. For example, styling semantic `method` must never
turn the shared Vim `Function` fallback into the method-specific style.

## Type and TypeMod are distinct requests

The public DSL can produce three useful semantic shapes:

```text
type only
    l:group("function", ...)

typemod only
    setup mods = { readonly = ... }

type + typemod
    l:group("variable", {
        typemods = { readonly = ... },
    })
```

A typemod-only request does not invent a type. For example, global
`readonly` can still resolve to source-specific forms such as the LSP modifier
`@lsp.mod.readonly`.

A type-only request owns the type style. If no semantic representation exists,
the resolver may materialize the selected literal type forms (Vim, TS and/or
LSP, with filetype variants where applicable) and returns
`"unresolved_literal"` internally so a diagnostic producer can classify that
autofallback without changing resolver semantics.

## Group typemod style ownership

The distinction between `true` and a typemod style table is intentional and
must be preserved through compilation:

```lua
p:group("SomeType", {
    fg = c.fg,
    typemods = {
        inherited = true,
        owned = { fg = c.red },
    },
})
```

`inherited = true` means **the style belongs to the type**. The typemod reuses
the exact finished base-style object and stays on the legacy/type-owned resolver
path. `nil` at the internal resolver API remains equivalent to this old/default
behavior for backwards compatibility.

`owned = { ... }` means **the style belongs to that concrete type+typemod
combination**. The type name is naming context only. Its base hl_group does not
need to exist and ChromaFlow must not materialize/style the base type merely to
style the typemod.

For example:

```lua
p:group("CodeMap", {
    style_targets = { ts = true },
    typemods = {
        keyword = { fg = c.keyword },
        entry = { fg = c.comment },
    },
})
```

has no base `CodeMap` style action. The typemod-owned path can materialize:

```text
@CodeMap.keyword
@CodeMap.entry
```

without first materializing `@CodeMap` as a ChromaFlow style target. With LSP
enabled, the same rule applies to the deterministic typemod spelling:

```text
@lsp.typemod.<type-token>.<modifier-token>
```

The resolver builds these concrete TS/LSP typemod names from the semantic tokens,
so the base type is allowed to be absent. If a requested concrete combination
had to be created, the resolver returns `"unresolved_literal"` internally.

This ownership distinction currently applies to **styled group typemods**.
TypeMod links and `false` clears continue through the semantic link/clear
resolver paths.

Neovim's `@capture` hierarchy may register a cleared parent when a dotted
capture is created. Therefore Neovim can show:

```text
@CodeMap          xxx cleared
@CodeMap.keyword  xxx ...
```

even though ChromaFlow never issued a base-style action for `@CodeMap`. That
Neovim parent registration does not change the typemod-owned resolver path.

---

# Group styles

A group style is the complete final `nvim_set_hl()` style, plus ChromaFlow DSL
metadata:

```lua
l:group("function", {
    fg = c["function"],
    sp = c.red,
    bold = true,
    undercurl = true,

    pipeline = {
        hl.opacity.sp(75),
        hl.shiftHue.fg(10),
    },
})
```

Direct highlight fields are assembled first, then `fg/bg/sp` are run through
the pipeline, then the complete `hl_set` is interned.

Identical complete styles share the exact same Lua table reference for the
whole Neovim session. That interning cache lives in `cf.hl.setup` and survives
theme reloads. The separate runtime materialization index is invalidated during
a full reload, so unchanged styles are still written again after Neovim's
highlight reset.

The runtime cache only records **directly materialized styles**:

```text
Function  = STYLE A
@function -> Function

cache:
Function  -> STYLE A
@function -> nil
```

Links are not cached by ChromaFlow. They remain Neovim state plus resolver
output. If `Function` later changes to another style, `@function` follows that
link naturally without any stale effective-style snapshot in the Lua cache.
This also guarantees that `style_target()` can only return real style anchors,
never link aliases.

---

# `types`

`types` adds more type names to one group declaration, but the style/link anchor is
not duplicated.

Language example:

```lua
l:group("function", {
    fg = c["function"],
    types = {
        "method",
        "constructor",
    },
})
```

Conceptually:

```text
method -----------┐
constructor ------┤
                  ▼
              function
                  │
                STYLE
```

The actual Vim/TS/LSP forms are resolved per semantic group.

Plugin/UI groups use the same resolver/anchor rule without a filetype context. Raw groups alone are exact/literal.

---

# Explicit links

There are three ways to link deliberately.

## Setup declaration links

```lua
l:link("method", "function")
p:link("PluginAlias", "PluginBase")
u:link("NormalFloat", "Normal")
raw:link("@foo.bar", "@function")
```

`l:link()` resolves both source and target semantically for the language
context.

`p:link()` and `u:link()` use the same resolver without a filetype context and
respect their module target/clear policy.

`raw:link()` is completely literal and bypasses semantic target selection.

## Link a group anchor

```lua
l:group("method", {
    link = "function",
    types = {
        "constructor",
    },
})
```

Conceptually:

```text
constructor -> method -> function
```

A group is either styled or linked. `link` is therefore mutually exclusive
with direct style fields/pipeline.

## Link a typemod

```lua
l:group("variable", {
    fg = c.variable,

    typemods = {
        readonly = {
            link = "constant",
        },
    },
})
```

The base group may be styled while a typemod links, or the base group may
link while another typemod owns a completely independent style.

---

# TypeMods

## Module mods = Mod without a Type

```lua
return l.setup("lua", {
    mods = {
        deprecated = {
            sp = c.red,
            undercurl = true,
            pipeline = {
                hl.opacity.sp(75),
            },
        },
    },
})
```

For a language setup, these are language-specific Mods without a concrete
Type. Plugin/UI setups may also use module mods; because their setup name is
not a filetype, those use global forms. The resolver maps them to the appropriate
Vim/Tree-sitter/LSP representation, including LSP `@lsp.mod.*` where applicable.

A module mod may also be `false` for explicit removal, or use `link`.

## Group typemods = Type + TypeMod

```lua
l:group("variable", {
    fg = c.variable,

    pipeline = {
        hl.brightness.fg(5),
    },

    typemods = {
        readonly = true,

        deprecated = false,

        static = {
            fg = c.black,
            undercurl = true,
            pipeline = {
                hl.opacity.sp(75),
            },
        },
    },
})
```

Meaning:

```text
true
    -> use the exact finished group style object
    -> style ownership stays with the type

table
    -> start from the finished group style when one exists
    -> apply direct typemod overrides
    -> run the typemod pipeline afterwards
    -> intern/set the resulting complete style
    -> style ownership belongs to this concrete type+typemod
    -> the base type is naming context and need not exist

false
    -> do not set this typemod
    -> clear it through the semantic clear path

{ link = "..." }
    -> link this typemod through the semantic link path
```

The order for a styled typemod is therefore:

```text
group direct values
    -> group pipeline
    -> finished group style
    -> typemod overrides
    -> typemod pipeline
    -> finished typemod style
```

If the group itself has no base style, a typemod table may still provide its
own complete style. That is the typemod-owned case described above: only the
requested concrete TS/LSP type+typemod targets are styled (there is no separate
Vim typemod naming layer), while the base type remains untouched by ChromaFlow.
`true` specifically requires an existing base style
because it means "inherit this type's finished style".

For language, plugin and UI groups typemod keys are semantic TypeMod names
handled by the same resolver. Only raw typemod keys are full literal
hl_group names.

---

# `raw`

`raw` is an escape hatch available inside every module setup:

```lua
local hl = require("cf.hl.setup")
local raw = hl.raw
```

It performs no semantic resolution at all.

```lua
raw:group("@function", {
    fg = c["function"],

    types = {
        "SomePluginGroup",
        "@lsp.type.function",
    },
})
```

The exact names above are all that ChromaFlow sees. No Vim/TS/LSP chain and no
filetype suffix/prefix is invented.

`raw:group()` supports the normal style fields, pipeline, types, typemods,
link and priority, but deliberately has no `style_targets` or
`style_targets_clear`.

Use a literal clear flag instead:

```lua
raw:group("@foo", {
    clear = true,
    fg = c.red,
})
```

`clear=true` clears each literal base/group/typemod target immediately before
that target is set/linked.

Raw typemod keys are themselves full literal group names:

```lua
raw:group("@foo", {
    fg = c.fg,

    typemods = {
        ["@lsp.typemod.function.readonly"] = true,

        ["@some.custom.group"] = {
            fg = c.black,
            pipeline = {
                hl.opacity.fg(70),
            },
        },

        ["@another.group"] = {
            link = "@constant",
        },

        ["@remove.this"] = false,
    },
})
```

`raw:link(source, target)` is the corresponding exact literal link declaration.

---

# Compile priority

`priority` is ChromaFlow compile priority, not a Neovim `nvim_set_hl()` field.
It is stripped before a style object is created.

```lua
l:group("function", {
    priority = 127,
    fg = c["function"],

    typemods = {
        readonly = {
            priority = 180,
            fg = c.const,
        },
    },
})
```

Rules:

```text
higher priority
    -> materialized later, therefore wins conflicts

equal priority
    -> later compile declaration wins

typemod without priority
    -> inherits its group priority
```

Priority applies equally to style, link and clear actions generated by a group
or typemod.

The theme is first compiled/validated, then all current-theme actions are
stably ordered by `(priority, compile order)` and applied.

---

# Useless group hint

Nothing except the logically required arguments is mandatory.

This is enough:

```lua
l:group("function", {
    fg = c["function"],
})
```

Optional capabilities are only used when present.

However, a `*:group()` that cannot produce any highlight action emits a `HINT`:

```lua
p:group("Nothing", {
    types = { "StillNothing" },
    priority = 127,
})
```

`types`, priority, target metadata or clear metadata alone do not make a useful
group. A real style, link or typemod action must exist.

Unknown callable DSL names inside a loaded `.cf` file are local authoring mistakes,
not module failures. For example, `l:goup(...)` emits a `HINT`, yields no
declaration, and the remaining entries in the surrounding setup array continue to
compile. Normal runtime target access such as `l.lua.variable` is unaffected.

A group containing only meaningful typemod actions is valid even when the
base group itself has no style.

---

# Pipeline

The pipeline module only knows colours and pipeline operations:

```text
fg + bg + sp + optional cfg/cbg working colours + operations
    -> independently manipulated colours
```

Theme-facing builders are exposed through `hl`:

```lua
pipeline = {
    hl.mix.fg(20, c.red),
    hl.opacity.sp(75),
    hl.brightness.fg(-10),
    hl.lighten.bg(5),
    hl.darken.fg(8),
    hl.shiftHue.fg(10),
    hl.gamma.bg(1.1),
}
```

Every existing `.fg`, `.bg` and `.sp` builder remains unchanged. Each operation
also has **additional** `.cfg` and `.cbg` builders for `ctermfg` and `ctermbg`:

```lua
u:group("Normal", {
    fg = c.fg,
    bg = c.bg,
    pipeline = {
        hl.brightness.cfg(10),
        hl.darken.cbg(5),
        hl.mix.cfg(20, c.red),
    },
})
```

These operations write only the terminal palette fields; `fg`, `bg` and `sp`
stay unchanged. They use an existing numeric `ctermfg`/`ctermbg` index when
present, otherwise the corresponding RGB channel at the first operation on that
channel. Subsequent operations keep RGB precision and convert to a palette index
only at the end of the pipeline. Runtime function callbacks form an explicit
boundary: they receive ordinary numeric cterm indices, and following operations
use any changes made by that callback. Untouched terminal fields remain unchanged.
Missing colours are errors, just as for `.fg`/`.bg`. `mix.cfg/cbg` still accepts
an ARGB/hex colour as its second argument, not a palette index.

Terminal opacity always composites to opaque RGB, even with `alpha = true`.
Its foreground backdrop is the terminal background when present, otherwise
`bg`/the theme background; its background backdrop is the theme background.
There is no `.csp`: Neovim has no `ctermsp` field. Use the existing `.sp` path
for terminals supporting independent underline colours.

Direct conversions are available without using a pipeline:

```lua
local color = require("cf.color")
local index = color.to_cterm(0xffff0000) -- 196; also accepts #RRGGBB/#RRGGBBAA
local argb = color.from_cterm(index)    -- 0xffff0000
```

`to_cterm` chooses the nearest colour by squared RGB distance from the standard
xterm-256 cube and grayscale ramp (indices 16..255), avoiding customizable ANSI
slots 0..15. It drops alpha, like `to_rgb_hex`; composite first with
`color.opacity` when needed. `from_cterm` accepts integer indices 0..255;
indices 0..15 use conventional xterm defaults and cannot reflect a customized
terminal palette. This is a **256-colour** conversion, not automatic 8/16-colour
terminal detection. No terminal options or user palette settings are changed.
The [xterm palette layout](https://invisible-island.net/xterm/xterm.faq.html#color_by_number)
defines the cube and grayscale entries.

The low-level `pipeline.apply(fg, bg, sp, operations, cfg, cbg)` accepts and
returns working ARGB/hex colours, **not cterm indices**, in its optional last two
channels. The normal DSL style builder owns index decoding and final conversion.

`cf.hl.setup` knows which RGB/terminal colours belong to which group/typemod and hands
them to `cf.hl.pipeline`; the pipeline itself knows nothing about groups,
languages, targets or typemods.

Colour tracing is a separate optional layer. `cf.debug` and `cf.picker` activate
`cf.colortrace`; with debug only, visible `.cf` files are traced and consumed
immediately without retention. With picker enabled, every compiled source is
traced and the source snapshot is cached for the active compiled theme. Debug
reuses that picker cache instead of tracing the same colour operations again.
With both features disabled, the normal pipeline builders/execution stay on the
direct path and `cf.colortrace` is not loaded.

---

# Fallback + validation lifecycle

A selected theme is processed in this order:

```text
resolve color.cf
resolve config.cf
install shared hl.colors/config policy

compile every active module
    -> validate module DSL
    -> collect active setup identities

freeze active fallback registry

compile default modules
    -> matching active identity returns immediately
    -> uncovered identities compile normally

resolve every requested runtime module (active -> root -> default)

if compile succeeds:
    refresh runtime hl_group catalog
    clear resolver name cache
    run config-level global clear once
    stable-sort all actions by priority/order
    apply styles/links/clears
```

An individual failing `.cf` module is reported and skipped locally; valid sibling
modules remain in the compiled theme and are applied normally. Reserved resources
(`color.cf`, `config.cf`), requested runtime modules and other genuinely fatal
compile contracts still abort before the destructive colorscheme apply begins.

---

# LuaLS

The archive contains a separate LuaLS meta library under:

```text
luals/library/cf/
```

It describes the public plugin API plus the `.cf` highlight DSL, including:

```text
cf.setup / cf.reload / cf.set_theme
cf.fn.lineblend
cf.theme selection/compile/apply helpers
cf.color conversions + color math
cf.diagnostic policy + management API

hl.colors
l/p/u/raw group + link APIs
hl.runtime callable loader + runtime group DSL
runtime semantic target/action/module types
module/group targets and clears
complete hl_set fields
pipeline builders
types
typemods
link
priority
raw literal clear
config.cf target types
```

The meta files are documentation/type information only; runtime code does not
require them.


## Optional LuaSnip snippets

ChromaFlow does not configure `nvim-cmp`, Neovim's native completion, or any
other completion frontend. Completion policy belongs to the user's editor setup;
the bundled LuaLS meta files only provide public API/DSL type information.

LuaSnip support is a separate optional convenience layer. ChromaFlow never
loads LuaSnip merely because it is installed. The plugin entrypoint only loads
`cf.snippets` after LuaSnip is already present in `package.loaded`; a scheduled
post-startup check catches normal eager setups and an `InsertEnter` retry covers
later lazy-loading. If LuaSnip is absent, no snippet module is loaded and nothing
is changed.

Complete `.cf` module skeletons use full, searchable trigger names:

```text
language    language module (`l.setup`)
plugin      plugin module (`p.setup`)
ui          UI module (`u.setup`)
runtime     runtime module (`r.setup`)
```

Frequent declarations use short triggers:

```text
lg / ll         l:group / l:link
pg / pl         p:group / p:link
ug / ul         u:group / u:link
rg              r:group
rawg / rawl     raw:group / raw:link
```

These snippets are offered only in files ending in `.cf`, even though `.cf` is
registered as `filetype=lua`. Generated indentation uses literal tab characters.

Normal Lua files get one separate helper:

```text
cfruntime
```

which expands to the ChromaFlow runtime-loader boilerplate:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime("module")
```

It is deliberately not offered in `.cf` files.
