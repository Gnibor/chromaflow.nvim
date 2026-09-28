# ChromaFlow DSL

Every normal theme module starts from the same object:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
```

Public theme surfaces:

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

`hl.colors` is the single normalized `color.cf` table for the current compile.

## Module kinds

### Language

```lua
local l = hl.language

return l.setup("lua", {
    l:group("comment", { fg = c.comment, italic = true }),
})
```

The first argument is the language/filetype context used to derive
language-specific Vim, Tree-sitter and LSP forms.

Global semantic syntax uses an explicit `nil` first argument:

```lua
return l.setup(nil, {
    l:group("string", { fg = c.string }),
})
```

Language modules inherit the target systems allowed by `config.cf` unless the
module/group narrows them.

### Plugin

```lua
local p = hl.plugin

return p.setup("telescope", {
    style_targets = { vim = true },
    p:group("TelescopeNormal", { fg = c.fg, bg = c.bg }),
})
```

The setup name is the plugin/fallback identity only; it is not a filetype. Plugin
modules have no implicit writable target system. Resolver-backed groups must
therefore get `style_targets` from the module or group. `p:link()` and module
`mods` require module-level targets.

### UI

```lua
local u = hl.ui

return u.setup({
    u:group("Normal", { fg = c.fg, bg = c.bg }),
    u:group("NormalFloat", { fg = c.fg, bg = c.surface }),
})
```

UI defaults to:

```lua
{ vim = true, ts = false, lsp = false }
```

That is only a default; normal target overrides still apply inside the config
boundary.

### Raw

`hl.raw` is an exact literal escape hatch usable inside any normal module:

```lua
local raw = hl.raw

return l.setup("lua", {
    raw:group("@my.exact.capture", { fg = c.accent }),
    raw:link("MyExactAlias", "Normal"),
})
```

Raw names are never semantically expanded, mapped or filetype-qualified.

## Group styles

A group style combines normal `nvim_set_hl()` fields with ChromaFlow metadata:

```lua
l:group("function", {
    fg = c.func,
    bg = c.bg,
    sp = c.red,
    bold = true,
    undercurl = true,

    pipeline = {
        hl.opacity.sp(75),
        hl.shiftHue.fg(10),
    },

    types = { "method" },
    priority = 20,
})
```

Normal highlight fields are collected first, then the pipeline runs, then the
finished complete style is interned. Identical complete styles share one table
for the Neovim session.

A group may be a style or a link, not both:

```lua
l:group("character", {
    link = "string",
})
```

## `types`: additional Types sharing one anchor

```lua
l:group("function", {
    fg = c.func,
    types = { "method", "constructor" },
})
```

The primary `function` owns the style. Additional semantic Types resolve normally
and link to that primary semantic anchor; the style is not duplicated.

The same mechanism works for plugin/UI/raw groups. For `raw`, the entries are
exact literal names.

## TypeMods

There are two intentionally different concepts.

### Module `mods`: Mod without a Type

```lua
return l.setup("lua", {
    mods = {
        deprecated = { strikethrough = true },
        readonly = { link = "constant" },
        static = false,
    },
})
```

These rules have no concrete Type. The resolver maps the Mod to source-specific
forms such as Tree-sitter/LSP modifier groups where available. A module Mod can
be a style, link, or `false` for explicit removal.

### Group `typemods`: Type + TypeMod

```lua
l:group("variable", {
    fg = c.variable,
    pipeline = { hl.brightness.fg(5) },

    typemods = {
        readonly = true,
        deprecated = false,

        static = {
            italic = true,
            pipeline = { hl.mix.fg(18, c.type) },
        },

        documentation = {
            link = "comment",
        },
    },
})
```

`true` reuses the exact finished base-group style and keeps style ownership with
the Type. A table starts from the finished base style when one exists, applies
its direct overrides, then its own pipeline; that concrete Type+TypeMod owns the
result. `false` clears the TypeMod. `{ link = "..." }` creates a semantic link.

A group does not need a base style when its typemod tables provide their own
styles. This is how TS-only captures such as `@CodeMap.keyword` can be authored
without inventing a `@CodeMap` base style.

The build order for a styled TypeMod is:

```text
group direct fields
-> group pipeline
-> finished base style
-> TypeMod direct overrides
-> TypeMod pipeline
-> finished TypeMod style
```

## Explicit links

Every normal surface has declaration links:

```lua
l:link("method", "function")
p:link("PluginAlias", "PluginBase")
u:link("NormalFloat", "Normal")
raw:link("@foo.bar", "@function")
```

`l/p/u` resolve source and target semantically under their target policy. `raw`
is exact literal source -> literal target.

A group or TypeMod may also use `link = "..."` as shown above.

## Target policy

Three systems may be selected:

```lua
style_targets = {
    vim = true,
    ts = true,
    lsp = true,
}
```

The effective target is resolved in this order:

```text
config.cf hard boundary
-> module default/override
-> group override
```

A `false` in config cannot be re-enabled lower down.

Defaults beneath config are:

```text
language: config value
plugin:   all false
ui:       vim=true, ts=false, lsp=false
raw:      not applicable
```

Plugin groups therefore opt into the systems the plugin actually owns.

### Clears

Semantic clears are independent from target selection:

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

This means "clear TS/LSP targets, then only materialize Vim". Module and group
clear masks are additive. Config-level clear is global; local semantic clears
still respect resolver ownership and do not erase a broad fallback that the
narrow semantic declaration would never own.

Raw groups do not use target masks. They instead support literal `clear=true`:

```lua
raw:group("@foo", {
    clear = true,
    fg = c.red,
})
```

## Semantic resolution

`language`, `plugin` and `ui` send semantic base names to the resolver. The
resolver keeps naming knowledge, actual environment existence, writable
ownership and requested target systems separate.

For example, semantic `method` may know that Vim can fall back to `Function`
while Tree-sitter uses `@function.method` and LSP uses the method token. Knowing
a broad fallback does not grant permission for a narrow declaration to overwrite
that broad group. If no usable semantic representation exists for a requested
writable target, ChromaFlow can materialize its deterministic literal fallback
instead.

`raw` is the only API that skips all of this.

## Priority

`priority` is ChromaFlow compile priority, not an `nvim_set_hl()` field:

```lua
l:group("function", {
    priority = 100,
    fg = c.func,
    typemods = {
        readonly = {
            priority = 150,
            fg = c.constant,
        },
    },
})
```

Higher priority is applied later. Equal priority preserves global declaration
order. A TypeMod inherits its group priority unless it sets its own value.
Styles, links and clears all participate in the same stable priority pass.

## Colour pipelines

Pipeline operations are executed in array order:

```lua
pipeline = {
    hl.mix.fg(20, c.red),
    hl.opacity.sp(75),
    hl.brightness.fg(-10),
    hl.lighten.bg(5),
    hl.darken.fg(8),
    hl.shiftHue.fg(10),
    hl.gamma.bg(1.10),
}
```

Operations:

| Operation | Arguments | Meaning |
| --- | --- | --- |
| `mix` | `percent, color` | Mix another colour into the current channel. |
| `opacity` | `percent` | Apply effective opacity against the appropriate background. |
| `brightness` | signed percent | Move toward white/black. |
| `lighten` | percent | Positive brightness adjustment. |
| `darken` | percent | Negative brightness adjustment. |
| `shiftHue` | degrees | Rotate hue. |
| `gamma` | value `> 0` | Gamma correction; `1` is unchanged. |

Every operation exposes five channel builders:

```text
.fg   RGB foreground
.bg   RGB background
.sp   special/underline colour
.cfg  terminal foreground (ctermfg)
.cbg  terminal background (ctermbg)
```

`cfg`/`cbg` work in RGB precision during the pipeline and quantize back to the
xterm-256 palette at the style boundary. They do not modify `fg`/`bg`. There is
no `.csp` because Neovim has no `ctermsp` field.

`opacity` uses the relevant background/backdrop. With `alpha=false`, RGB output
is pre-composited; with `alpha=true`, RGB channels may preserve effective alpha.
Terminal opacity always produces opaque palette colour output.

## Raw TypeMods

Raw typemod keys are already full literal group names:

```lua
raw:group("@foo", {
    fg = c.fg,
    typemods = {
        ["@lsp.typemod.function.readonly"] = true,
        ["@some.custom.group"] = { fg = c.red },
        ["@another.group"] = { link = "@constant" },
        ["@remove.this"] = false,
    },
})
```

`types`, pipelines, priority and links still work; `style_targets` and semantic
clear masks deliberately do not.

## Authoring diagnostics

A declaration that has target metadata/priority/aliases but cannot produce a
style, link or TypeMod action is accepted as useless input and emits a HINT when
that diagnostic is enabled.

Unknown callable DSL names inside a loaded `*.cf` file are treated as local
authoring mistakes: ChromaFlow emits a HINT, leaves a nil hole in the setup array
and continues compiling the remaining declarations where possible.

## Complete examples

The most useful executable references are:

```text
examples/themes/dark/generic.cf
examples/themes/dark/lang-lua.cf
examples/themes/dark/core-ui.cf
examples/themes/dark/plugin-codemap.cf
examples/themes/dark/plugin-telescope.cf
examples/themes/runtime/*.cf
```
