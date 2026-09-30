# Colors and palettes

## Contents

- [`color.cf`](#colorcf)
- [Palette fallback](#palette-fallback)
- [`hl.colors`](#hlcolors)
- [Hex colors are normalized once](#hex-colors-are-normalized-once)
- [Colors can also be written directly in styles](#colors-can-also-be-written-directly-in-styles)
- [Alpha colors](#alpha-colors)
- [Low-level color functions vs. pipeline wrappers](#low-level-color-functions-vs-pipeline-wrappers)
- [The public color API](#the-public-color-api)
- [Terminal colors](#terminal-colors)
- [Palette naming is intentionally a theme decision](#palette-naming-is-intentionally-a-theme-decision)
- [A practical pattern](#a-practical-pattern)

ChromaFlow keeps palette definition separate from highlight structure.

`color.cf` chooses the colors for one theme load. Language, plugin, UI and
runtime code can then reuse those values through `hl.colors` instead of copying
hex strings through every module.

This chapter covers the palette contract, color representation and the public
`cf.color` helpers. Pipeline composition is covered separately in
[`pipeline.md`](pipeline.md).

## `color.cf`

`color.cf` is one of ChromaFlow's two reserved filenames. Unlike ordinary
module files, its name is part of the theme contract.

It must return a table:

```lua
return {
  bg = "#0f121b",
  fg = "#cfcfcf",

  comment = "#7890ab",
  variable = "#b8d2c3",
  ["function"] = "#d4aa78",
  type = "#8ebfc9",
  string = "#b5cc99",
  keyword = "#b4a2cd",
}
```

The key names are yours. ChromaFlow does not require a fixed palette schema.
You can keep a very small palette, use semantic names, split colors into nested
tables, or add aliases that make the theme easier to read.

For example:

```lua
local c = {
  bg = "#0f121b",
  fg = "#cfcfcf",

  syntax = {
    comment = "#7890ab",
    callable = "#d4aa78",
    type = "#8ebfc9",
  },
}

c.func = c.syntax.callable
return c
```

The only palette key with built-in color-processing meaning is `bg`: ChromaFlow
uses `hl.colors.bg` as the theme-wide backdrop when an opacity operation needs a
background and the current style does not provide a more local one.

`bg` is not required merely to load a theme, but a pipeline such as
`hl.opacity.bg(...)` or an opacity operation without another available backdrop
needs one.

## Palette fallback

ChromaFlow resolves `color.cf` before compiling any normal theme module.

The lookup order is:

```text
active theme -> theme root -> default theme
```

The first existing `color.cf` wins.

Unlike `config.cf`, a palette is mandatory. If no `color.cf` exists anywhere in
that chain, theme compilation fails.

This lets a theme variant override only its colors while inheriting all module
structure from the default theme:

```text
themes/
├── .cf-theme
├── base/
│   ├── color.cf
│   ├── generic.cf
│   ├── lua.cf
│   └── ui.cf
└── violet/
    └── color.cf
```

If `violet` is active and `base` is the default theme, `violet/color.cf` is
selected first. The language/UI modules may still fall back completely to
`base`, but those fallback modules receive the **violet palette**, not the base
palette.

Palette selection and normal-module fallback are therefore independent.

For the complete theme fallback model, see
[`theme-structure.md`](theme-structure.md).

## `hl.colors`

Inside a `.cf` module, the resolved palette is exposed as:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
```

A language module can then use the palette directly:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language

return l.setup("lua", {
  l:group("comment", {
    fg = c.comment,
    italic = true,
  }),

  l:group("function", {
    fg = c.func,
  }),
})
```

Every module in one compile receives the exact same resolved `hl.colors` table
reference.

That includes fallback modules. ChromaFlow does not compile a default module
against one palette and an active module against another palette within the
same theme load.

## Hex colors are normalized once

When a theme compile starts, ChromaFlow walks the resolved palette table
recursively.

Strings in either accepted hex form are converted in place:

```text
#RRGGBB
#RRGGBBAA
```

Internally ChromaFlow stores them as packed numeric colors:

```text
0xAARRGGBB
```

A six-digit color becomes fully opaque (`AA = FF`).

For example:

```lua
-- color.cf source
return {
  accent = "#6c9ee8",
  soft = "#6c9ee880",
}
```

is available to compiled modules as packed color values through `hl.colors`.

This conversion happens once at the palette boundary so color operations do
not need to repeatedly parse the same hex strings in hot paths.

Nested palette tables are normalized too:

```lua
return {
  ui = {
    border = "#31384d",
    selection = "#2d3f76",
  },
}
```

Strings that are not `#RRGGBB` or `#RRGGBBAA` are left alone. Other values are
also left untouched.

## Colors can also be written directly in styles

You do not have to put every one-off color into `color.cf`.

Style fields `fg`, `bg` and `sp` accept the same hex forms directly:

```lua
l:group("error", {
  fg = "#e06c75",
  sp = "#e06c75",
  undercurl = true,
})
```

ChromaFlow normalizes those style colors at the style boundary as well.

For a reusable theme, `hl.colors` is usually preferable because it keeps color
selection in one place. Direct literals are still useful for intentionally
local values, experiments and generated modules.

## Alpha colors

ChromaFlow accepts eight-digit colors as:

```text
#RRGGBBAA
```

Internally that is still stored as:

```text
0xAARRGGBB
```

The public setup option:

```lua
require("cf").setup({
  alpha = true,
})
```

selects alpha-capable rendering paths where ChromaFlow supports both an alpha
and a pre-composited representation.

With `alpha = false` (the default), normal rendered GUI colors use RGB output.
With `alpha = true`, packed colors are rendered with their alpha channel where
that output path is supported.

Opacity operations are slightly different because they can calculate both
forms explicitly: an opaque color pre-composited against a background and an
alpha-preserving color. The pipeline chapter covers how ChromaFlow chooses
between them.

## Low-level color functions vs. pipeline wrappers

ChromaFlow exposes the same color operations at two different levels. They are
related, but they are **not interchangeable execution models**.

Low-level functions come directly from `cf.color`:

```lua
local color = require("cf.color")

local darker = color.darken(c.blue, 12)
local mixed = color.mix(20, c.black, c.blue)
```

They are ordinary Lua functions. You may call them anywhere: in `color.cf`, in
a module, in runtime code, or in your own helper functions. They execute
immediately when Lua evaluates the call. ChromaFlow does not place those calls
into a style pipeline and does not add any ordering semantics beyond the order
your Lua code itself establishes.

Pipeline wrappers live on `hl`:

```lua
pipeline = {
  hl.mix.fg(20, c.black),
  hl.opacity.fg(70),
}
```

These calls do **not** transform a color immediately. They create pipeline
operations. ChromaFlow later applies those operations to the current style in
exact list order. Every operation therefore sees the result produced by the
operations before it.

That difference matters whenever an operation depends on another style field.
For example, foreground opacity chooses its backdrop from the **current** style:

```text
hl.opacity.fg(...)
  -> current style.bg, if one exists
  -> otherwise hl.colors.bg
```

If an earlier pipeline operation changed `bg`, a later `hl.opacity.fg(...)`
uses that updated background.

The same local-background rule applies to `sp`; background opacity uses the
theme backdrop directly. The full per-channel behavior and operation ordering
are documented in [`pipeline.md`](pipeline.md).

If you intentionally want to blend a channel against a specific color instead
of the automatic opacity backdrop, use `mix`:

```lua
pipeline = {
  hl.mix.fg(20, c.black),
}
```

There is therefore no separate "opacity backdrop" argument in the pipeline
wrapper: automatic compositing belongs to `opacity`, while an explicit second
color belongs to `mix`.

## The public color API

Low-level color helpers live in:

```lua
local color = require("cf.color")
```

These are the immediate, ordinary-Lua functions described above. They can be
used anywhere, but they do not participate in ChromaFlow's ordered style
pipeline. For normal theme styling, the corresponding `hl.*` pipeline wrappers
are usually the more convenient form when several transformations must happen
sequentially.

Public color functions accept packed `0xAARRGGBB` values, and transformation
functions also accept `#RRGGBB` / `#RRGGBBAA` strings where their `CFColor`
parameter is used.

They return packed numeric colors so several operations can be composed in Lua
without converting back to strings between each step.

### `from_hex()`

Convert a hex string to packed `0xAARRGGBB`:

```lua
local blue = color.from_hex("#6c9ee8")
local soft_blue = color.from_hex("#6c9ee880")
```

Only `#RRGGBB` and `#RRGGBBAA` are accepted.

### `to_hex()`

Convert a packed color back to hex:

```lua
color.to_hex(blue)            -- #6c9ee8
color.to_hex(soft_blue)       -- #6c9ee880
color.to_hex(blue, true)      -- #6c9ee8ff
```

Opaque colors normally use six digits. `force_alpha = true` always emits the
alpha byte too.

### `to_rgb_hex()` and `to_rgba_hex()`

Use an explicit output format when the caller already knows what it needs:

```lua
color.to_rgb_hex(value)   -- always #RRGGBB
color.to_rgba_hex(value)  -- always #RRGGBBAA
```

`to_rgb_hex()` drops alpha; it does not composite the color against a
background first.

### `mix()`

Mix a percentage of one color into another:

```lua
local result = color.mix(25, c.blue, c.variable)
```

The argument order is:

```text
mix(percent, added_color, base_color)
```

So the example means "25% blue mixed into the variable color".

Percentages are clamped to the `0..100` range.

### `opacity()`

Apply opacity to a color over a background:

```lua
local opaque, alpha = color.opacity(c.blue, 60, c.bg)
```

It returns **two** packed colors:

1. an opaque result pre-composited against the background,
2. the original RGB with the requested effective alpha.

Existing source alpha participates in the calculation; requested opacity does
not simply overwrite it.

This dual result is what allows the higher-level pipeline to support both RGB
and alpha-capable output paths without repeating the compositing calculation.

The low-level function requires the background explicitly because it has no
style context. The pipeline wrapper does have that context:

```lua
hl.opacity.fg(60)
```

For `fg`, it first uses the style's current `bg`; only when that is absent does
it fall back to `hl.colors.bg`. To blend against some other explicit color,
prefer `hl.mix.fg(percent, color)` instead of trying to override opacity's
automatic backdrop selection.

### `brightness()`

Adjust brightness with a signed percentage:

```lua
local brighter = color.brightness(c.blue, 20)
local darker = color.brightness(c.blue, -20)
```

Positive values move channels toward white. Negative values move them toward
black.

### `lighten()` and `darken()`

Convenience forms for one-direction brightness changes:

```lua
local lighter = color.lighten(c.blue, 12)
local darker = color.darken(c.blue, 12)
```

Both expect a non-negative percentage.

### `shiftHue()`

Rotate hue while preserving the source alpha:

```lua
local shifted = color.shiftHue(c.blue, 45)
local shifted_back = color.shiftHue(c.blue, -45)
```

The argument is measured in degrees and wraps around the hue circle.

### `gamma()`

Apply gamma correction:

```lua
local darker = color.gamma(c.blue, 1.10)
local lighter = color.gamma(c.blue, 0.90)
```

The value must be greater than zero.

| Gamma | Effect |
| ---: | --- |
| `> 1` | Darker |
| `< 1` | Lighter |
| `= 1` | Unchanged |

## Terminal colors

ChromaFlow can also move between packed RGB colors and xterm-256 palette
indices.

### `to_cterm()`

```lua
local index = color.to_cterm(c.blue)
```

This chooses the nearest xterm-256 color by RGB distance.

The conversion deliberately avoids ANSI slots `0..15`, because terminals may
customize those colors. Generated results use the xterm color cube or grayscale
range instead.

Alpha is discarded. Composite first when transparency matters.

### `from_cterm()`

```lua
local packed = color.from_cterm(75)
```

This converts a palette index `0..255` to an opaque packed color.

For indices `0..15`, ChromaFlow uses the conventional xterm defaults. It does
not query the user's terminal for customized ANSI slot colors.

These functions are especially useful in runtime actions that manipulate
`ctermfg`/`ctermbg` alongside GUI colors.

## Palette naming is intentionally a theme decision

ChromaFlow does not prescribe names such as `red1`, `base03`, `accent`,
`function` or `syntax.callable`.

A semantic palette is often convenient:

```lua
return {
  bg = "#0f121b",
  fg = "#cfcfcf",
  comment = "#7890ab",
  variable = "#b8d2c3",
  ["function"] = "#d4aa78",
  type = "#8ebfc9",
  string = "#b5cc99",
  number = "#ceaa91",
  keyword = "#b4a2cd",
}
```

A smaller base palette plus derived pipelines is equally valid.

What matters is that modules consume one shared palette for the complete theme
compile, so changing the selected `color.cf` can recolor fallback modules
without copying or rewriting their structure.

## A practical pattern

A useful `color.cf` can define canonical values and aliases once:

```lua
local c = {
  bg = "#0f121b",
  fg = "#cfcfcf",

  red = "#e06c75",
  yellow = "#e5c07b",
  green = "#c3e88d",
  blue = "#6c9ee8",

  variable = "#b8d2c3",
  ["function"] = "#d4aa78",
  type = "#8ebfc9",
  constant = "#bd9eb5",
}

c.func = c["function"]
return c
```

Then modules focus on structure instead of hex strings:

```lua
l:group("function", {
  fg = c.func,
})

l:group("type", {
  fg = c.type,
})

l:group("constant", {
  fg = c.constant,
})
```

And pipelines derive variants from those same base values instead of expanding
the palette for every small visual difference:

```lua
l:group("function", {
  fg = c.func,
  pipeline = {
    hl.darken.fg(3),
  },
})
```

That separation is the subject of the next chapter:
[`pipeline.md`](pipeline.md).
