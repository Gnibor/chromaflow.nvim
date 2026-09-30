# Pipelines

## Contents

- [Pipeline wrappers are not low-level color calls](#pipeline-wrappers-are-not-low-level-color-calls)
- [Where a pipeline starts](#where-a-pipeline-starts)
- [Available operations](#available-operations)
- [Opacity backdrop rules](#opacity-backdrop-rules)
- [Alpha output](#alpha-output)
- [Terminal pipeline channels: `cfg` and `cbg`](#terminal-pipeline-channels-cfg-and-cbg)
- [TypeMod pipelines inherit the finished base style](#typemod-pipelines-inherit-the-finished-base-style)
- [Pipelines and links are mutually exclusive](#pipelines-and-links-are-mutually-exclusive)
- [Runtime functions can also be pipeline entries](#runtime-functions-can-also-be-pipeline-entries)
- [ColorTrace follows the same pipeline path](#colortrace-follows-the-same-pipeline-path)
- [Practical patterns](#practical-patterns)
- [When to use a pipeline](#when-to-use-a-pipeline)

ChromaFlow pipelines transform a highlight style **after its current colors are
known**.

They are useful when a style should be derived from another style or palette
color instead of repeating another fixed color value.

![CFPick Pipeline editor](screenshots/ChromaFlow-Pick_pipeline.png)

*With `CFPick`, the same FG/BG/SP/CFG/CBG pipeline channels can be edited and
previewed live.*

A pipeline is an ordered Lua array:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors

l:group("function", {
  fg = c.func,
  pipeline = {
    hl.shiftHue.fg(-5),
    hl.brightness.fg(20),
  },
})
```

The two operations are not independent. ChromaFlow first shifts the current
foreground hue and then applies brightness to the result of that shift.

For the low-level color functions used underneath pipelines, see
[`colors.md`](colors.md).

## Pipeline wrappers are not low-level color calls

The public low-level color API is available through:

```lua
local color = require("cf.color")
```

For example:

```lua
local result = color.mix(20, c.black, c.func)
```

That is an ordinary Lua function call. It executes immediately, can be used
anywhere, and follows only the evaluation order of your Lua code.

Pipeline wrappers instead live on `hl`:

```lua
hl.mix.fg(20, c.black)
hl.opacity.bg(8)
hl.gamma.fg(1.1)
```

Those calls do **not** immediately transform a color. They create pipeline
operations that ChromaFlow evaluates later against the current highlight
style.

That gives a pipeline its important property:

> Pipeline operations execute in the exact order in which they appear in the
> `pipeline = { ... }` array.

Use `cf.color.*` when you want an immediate color calculation. Use `hl.*`
pipeline wrappers when the result should depend on the current style and on
operations that came before it.

## Where a pipeline starts

For a normal style declaration ChromaFlow builds the style in this order:

```text
inherited/base style, if one exists
-> explicit style fields from the declaration
-> pipeline operations, in array order
```

For example:

```lua
l:group("function", {
  fg = c.func,
  bg = c.panel,
  pipeline = {
    hl.darken.bg(10),
    hl.opacity.fg(70),
  },
})
```

The first operation changes `bg`. The second operation therefore sees that
**already darkened background** when it calculates foreground opacity.

A pipeline-only declaration needs a color to work on. This is valid when the
style inherits that color from a parent/base style, but a base group such as:

```lua
l:group("function", {
  pipeline = {
    hl.darken.fg(10),
  },
})
```

has no foreground of its own to darken and therefore fails with a missing
channel error.

## Available operations

Every standard operation is available on the same five channels:

| Channel | Meaning |
| --- | --- |
| `fg` | GUI foreground |
| `bg` | GUI background |
| `sp` | GUI special color |
| `cfg` | Terminal foreground / `ctermfg` |
| `cbg` | Terminal background / `ctermbg` |

The operation families are:

| Wrapper | Meaning |
| --- | --- |
| `hl.mix.<channel>(percent, color)` | Mix an explicit color into the current channel |
| `hl.opacity.<channel>(percent)` | Apply opacity using the automatic backdrop for that channel |
| `hl.brightness.<channel>(percent)` | Signed brightness adjustment |
| `hl.lighten.<channel>(percent)` | Brighten by a non-negative percentage |
| `hl.darken.<channel>(percent)` | Darken by a non-negative percentage |
| `hl.shiftHue.<channel>(degrees)` | Rotate hue |
| `hl.gamma.<channel>(value)` | Gamma correction; value must be greater than zero |

So these are all valid:

```lua
pipeline = {
  hl.mix.fg(20, c.black),
  hl.opacity.bg(8),
  hl.lighten.sp(10),
  hl.gamma.cfg(1.2),
  hl.darken.cbg(8),
}
```

### `mix`

`mix` takes the percentage of the **added** color:

```lua
hl.mix.fg(20, c.black)
```

means:

```text
mix 20% black into the current foreground
```

The current channel is the base color. This mirrors the low-level call:

```lua
color.mix(20, c.black, current_fg)
```

Use `mix` when you intentionally want to blend against a specific color.

### `opacity`

`opacity` deliberately does not accept an explicit backdrop argument:

```lua
hl.opacity.fg(70)
```

The backdrop comes from the current style and theme state. If you want to blend
against an explicitly chosen color, use `hl.mix.*` instead.

### `brightness`, `lighten`, and `darken`

`brightness` accepts signed values:

```lua
hl.brightness.fg(20)
hl.brightness.fg(-20)
```

`lighten` and `darken` are the one-direction convenience forms:

```lua
hl.lighten.fg(20)
hl.darken.fg(20)
```

### `shiftHue`

Hue shifts use degrees and may be positive or negative:

```lua
hl.shiftHue.fg(30)
hl.shiftHue.fg(-5)
```

### `gamma`

Gamma values must be greater than zero:

```lua
hl.gamma.fg(1.10) -- darker
hl.gamma.fg(0.90) -- lighter
```

`1.0` leaves the color unchanged.

## Opacity backdrop rules

Opacity is the operation where the current style context matters most.

The backdrop is selected per channel:

| Channel | Backdrop |
| --- | --- |
| `fg` | current `style.bg`, otherwise `hl.colors.bg` |
| `bg` | `hl.colors.bg` |
| `sp` | current `style.bg`, otherwise `hl.colors.bg` |
| `cfg` | current terminal background, then current GUI `bg`, then `hl.colors.bg` |
| `cbg` | `hl.colors.bg` |

The word **current** is important. Earlier pipeline operations may already have
changed one of those colors.

For example:

```lua
pipeline = {
  hl.darken.bg(10),
  hl.opacity.fg(60),
}
```

`hl.opacity.fg(60)` composites against the darkened background produced by the
first operation.

If the style has no usable local backdrop, the theme-wide `hl.colors.bg` is the
fallback. An opacity operation fails if no required background can be found.

## Alpha output

Opacity computes both an opaque pre-composited result and an alpha-preserving
result.

For the normal GUI channels (`fg`, `bg`, `sp`):

| `alpha` | Result |
| --- | --- |
| `false` | Use the opaque pre-composited result |
| `true` | Preserve the calculated alpha |

The setting comes from normal ChromaFlow setup:

```lua
require("cf").setup({
  alpha = true,
})
```

Terminal channels always use the opaque/composited result because they must
ultimately become palette indices.

## Terminal pipeline channels: `cfg` and `cbg`

`cfg` and `cbg` manipulate terminal colors independently from the GUI colors.

A terminal channel starts from its explicit numeric palette index when one is
present:

```lua
{
  ctermfg = 196,
  pipeline = {
    hl.darken.cfg(20),
  },
}
```

ChromaFlow decodes the palette index to an internal RGB working color, performs
the pipeline operations at full RGB precision, and converts back to an
xterm-256 index **once at the end**.

If no explicit `ctermfg`/`ctermbg` exists, the terminal working channel falls
back to the corresponding current GUI color:

| Missing terminal channel | Falls back to |
| --- | --- |
| `cfg` | Current `fg` |
| `cbg` | Current `bg` |

Once a terminal channel has been touched, it keeps its own working value for
later `cfg`/`cbg` operations.

This means GUI and terminal operations may be interleaved deliberately:

```lua
pipeline = {
  hl.lighten.fg(10),
  hl.darken.cfg(20),
  hl.darken.fg(30),
  hl.gamma.cfg(1.2),
}
```

The global array order is preserved, but the GUI foreground and terminal
foreground become separate working channels once `cfg` has been initialized.

When manipulating an explicit `ctermfg` or `ctermbg`, use a numeric `0..255`
palette index. Named terminal color strings are not converted by the pipeline.

## TypeMod pipelines inherit the finished base style

A TypeMod does not need to repeat the base type color merely to modify it.

For example:

```lua
l:group("function", {
  fg = c.func,

  typemods = {
    builtin = {
      pipeline = {
        hl.mix.fg(22, c.yellow),
      },
    },

    abstract = {
      italic = true,
      pipeline = {
        hl.opacity.fg(85),
      },
    },
  },
})
```

The TypeMod pipeline starts from the **finished base-group style**. It can then
add explicit fields and transform the inherited colors.

This is why a TypeMod can contain only a pipeline even though a standalone base
group cannot manipulate a missing foreground.

The same principle is useful for small variations: keep the canonical base
color in one place, then derive variants instead of copying slightly different
hex strings through the theme.

## Pipelines and links are mutually exclusive

A declaration may contain normal style fields plus a pipeline:

```lua
l:group("comment", {
  fg = c.comment,
  italic = true,
  pipeline = {
    hl.opacity.fg(80),
  },
})
```

But a `link` is a different kind of declaration. It cannot be combined with
style fields or a pipeline:

```lua
-- valid
l:group("something", {
  link = "comment",
})
```

```lua
-- invalid
l:group("something", {
  link = "comment",
  pipeline = {
    hl.darken.fg(10),
  },
})
```

If a group should look like another group **with a modification**, use normal
style inheritance/semantic grouping or define the desired derived style rather
than combining a link with a transformation.

## Runtime functions can also be pipeline entries

Runtime modules add one extra kind of pipeline entry: a user function that can
manipulate the complete highlight style.

For example:

```lua
local hl = require("cf.hl.setup")
local color = require("cf.color")
local r = hl.runtime

function r.colorfade(style, ctx)
  if style.fg ~= nil then
    style.fg = color.shiftHue(style.fg, ctx.frame * 3)
  end
  return style
end

return r.setup({
  r:group("colorfade", {
    fg = hl.colors.red,
    pipeline = {
      r:func("colorfade")[40],
    },
  }),
})
```

A runtime function executes at exactly its position in the pipeline and may
return a complete replacement style or mutate and return the supplied style.
The optional `[40]` requests a 40 ms tick interval.

Runtime function entries are valid only in runtime actions. Normal language,
plugin and UI theme modules use the standard `hl.*` color operations.

Runtime modules and their timing/context rules are covered separately in
[`runtime.md`](runtime.md).

## ColorTrace follows the same pipeline path

ColorTrace does not implement a second color engine. When tracing is enabled,
ChromaFlow applies the same operations one by one and records information such
as:

```text
operation
channel
input color
arguments
backdrop
result color
```

That is why the trace can explain an ordered pipeline without changing its
result.

See [`colortrace.md`](colortrace.md) for tracing and diagnostics.

For scale, the checked-in clean-state benchmark keeps the numeric color engine near
the LuaJIT floor on its i5-10310U reference host: `shiftHue(45)` averages roughly
**0.07-0.09 µs**, `gamma(1.10)` roughly **0.09-0.12 µs**, and applying a prebuilt
seven-operation pipeline roughly **0.37-0.43 µs** in the Minimal scenario. Use the
full benchmark report for distributions rather than treating these values as
machine-independent constants.

## Practical patterns

### Tint an inherited TypeMod

```lua
typemods = {
  builtin = {
    pipeline = {
      hl.mix.fg(20, c.builtin),
    },
  },
}
```

### Produce a subtle background from a strong palette color

```lua
p:group("GitSignsAddLn", {
  bg = c.green,
  pipeline = {
    hl.opacity.bg(8),
  },
})
```

### Chain several transformations

```lua
pipeline = {
  hl.shiftHue.fg(-5),
  hl.brightness.fg(20),
  hl.mix.fg(10, c.white),
}
```

Each line sees the result of the previous line.

### Use an explicit blend color instead of opacity's automatic backdrop

```lua
pipeline = {
  hl.mix.fg(25, c.black),
}
```

Do this when you intentionally want black to be the second color. Use
`hl.opacity.fg(...)` when the foreground should instead be composited against
the current style background or the theme background fallback.

## When to use a pipeline

A pipeline is a good fit when:

- one style is a predictable variation of another style,
- a TypeMod should alter its inherited base color,
- operation order matters,
- opacity should react to the current style background,
- GUI and terminal colors need controlled independent transformations,
- or CFPick should be able to edit a sequence of transformations directly.

A direct palette value is simpler when a color is already final and does not
depend on style context.

A direct `cf.color.*` call is useful when you want to calculate a color in Lua
outside the ordered style pipeline.

The three forms therefore have different jobs:

| Use | Best fit |
| --- | --- |
| Palette value | Fixed reusable color |
| `cf.color.*` | Immediate low-level calculation |
| `hl.*` pipeline wrapper | Ordered transformation of the current style |
