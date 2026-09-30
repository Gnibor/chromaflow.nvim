# Float

## Contents

- [Minimal example](#minimal-example)
- [Creating a float](#creating-a-float)
- [Rendering content](#rendering-content)
  - [`set_line()`](#set_line)
  - [`set_lines()`](#set_lines)
- [Reference-based line caching](#reference-based-line-caching)
  - [`flush()`](#flush)
- [Clearing content](#clearing-content)
  - [`clear_line()`](#clear_line)
  - [`clear()`](#clear)
- [Opening, hiding and closing](#opening-hiding-and-closing)
  - [`open()`](#open)
  - [`hide()`](#hide)
  - [`close()`](#close)
- [Reconfiguring an existing float](#reconfiguring-an-existing-float)
- [Cursor highlight](#cursor-highlight)
  - [CursorLine and selection rendering](#cursorline-and-selection-rendering)
- [Buffer and window handles](#buffer-and-window-handles)
  - [`buf()`](#buf)
  - [`win()`](#win)
  - [`is_open()`](#is_open)
- [Highlight namespaces](#highlight-namespaces)
  - [Performance reference](#performance-reference)
- [Complete API](#complete-api)

`cf.fn.float` is a small standalone floating-window renderer built on Neovim's
floating-window and extmark APIs.

It is used internally by ChromaFlow menus and editors, but it does not depend on
theme compilation, the resolver, pipelines or any other ChromaFlow-specific
state. It can also be required and used directly by other Lua code.

```lua
local Float = require("cf.fn.float")
```

The module renders rows made from independently positioned highlighted spans.
It keeps those rows cached, so a float can be hidden and reopened or selectively
updated without rebuilding all of its content.

---

## Minimal example

```lua
local Float = require("cf.fn.float")

local float = Float.new({
    width = 32,
    height = 3,
    relative = "editor",
    row = 4,
    col = 8,
    border = "rounded",
    title = " Example ",
    enter = true,
})

float:set_lines(1, {
    {
        { col = 0,  text = "Name",  hl = "Title" },
        { col = 12, text = "Value", hl = "Comment" },
    },
    {
        { col = 0,  text = "alpha" },
        { col = 12, text = "42", hl = "Number" },
    },
    {
        { col = 0, text = "Press q to close", hl = "Comment" },
    },
})

float:open()

vim.keymap.set("n", "q", function()
    float:close()
end, {
    buffer = float:buf(),
    nowait = true,
    silent = true,
})
```

Rows are **1-based**. Span columns are **0-based screen-cell columns**.

The renderer uses virtual-text overlays anchored to empty buffer rows, so span
positions are display positions rather than byte offsets into stored text.

---

# Creating a float

```lua
local float = Float.new(opts)
```

All options are optional.

```lua
local float = Float.new({
    width = 40,
    height = 10,
    relative = "editor",
    row = 2,
    col = 4,
    anchor = "NW",
    border = "rounded",
    title = " Inspector ",
    title_pos = "center",
    focusable = true,
    zindex = 50,
    enter = true,
    cursor_hl = "Visual",
})
```

Defaults:

| Option | Default |
| --- | --- |
| `width` | `1` |
| `height` | `1` |
| `relative` | `"editor"` |
| `row` | `0` |
| `col` | `0` |
| `anchor` | `"NW"` |
| `border` | `"none"` |
| `title` | `""` |
| `title_pos` | `"left"` |
| `focusable` | `true` |
| `zindex` | `50` |
| `enter` | `false` |
| `cursor_hl` | `false` |

`relative` accepts:

```text
editor
cursor
win
```

When `relative = "win"` is used, `win` may be supplied with the target Neovim
window ID.

`anchor` accepts:

```text
NW
NE
SW
SE
```

`border` is a Neovim border style name. `title_pos` may be `left`, `center` or
`right`.

`enter` controls the `enter` argument passed when the window is opened. It is
not part of the persistent Neovim window config, so it may be changed without
moving or resizing an already open float.

The created window uses Neovim's `minimal` window style and has wrapping
disabled.

---

# Rendering content

A line is an array of spans:

```lua
local line = {
    { col = 0,  text = "left",   hl = "NormalFloat" },
    { col = 16, text = "middle", hl = "Comment" },
    { col = 30, text = "right",  hl = "Special" },
}
```

Each span has:

| Span field | Requirement |
| --- | --- |
| `col` | Required; non-negative integer screen column |
| `text` | Required; single-line string |
| `hl` | Optional highlight-group name |

`text` may not contain a newline.

The float does not require spans to be adjacent. This makes it useful for small
tables, inspectors, menus and editors where each cell can be positioned directly.

## `set_line()`

```lua
float:set_line(row, line)
```

Sets or replaces one cached row.

```lua
float:set_line(2, {
    { col = 0, text = "Status" },
    { col = 12, text = "ready", hl = "DiagnosticOk" },
})
```

Rows are 1-based positive integers.

The backing buffer is created lazily when content is first written or when the
float is opened.

## `set_lines()`

```lua
float:set_lines(start_row, lines)
```

Updates consecutive rows starting at `start_row`.

```lua
float:set_lines(3, {
    { { col = 0, text = "row three" } },
    { { col = 0, text = "row four" } },
})
```

Only the supplied rows are updated. Existing cached rows outside that range are
left untouched.

If a later render contains fewer rows than before, remove the old rows explicitly
with `clear_line()` or `clear()` as appropriate.

---

# Reference-based line caching

`Float` deliberately caches the Lua table reference passed for each line.

If the exact same line table is passed again, `set_line()` does nothing:

```lua
local line = {
    { col = 0, text = "unchanged" },
}

float:set_line(1, line)
float:set_line(1, line) -- no repaint
```

`set_lines()` applies the same rule independently to every row.

This makes repeated renders cheap when unchanged line tables are reused.

If a cached line table is modified **in place**, explicitly repaint it with
`flush()`:

```lua
local line = {
    { col = 0, text = "before", hl = "Normal" },
}

float:set_line(1, line)

line[1].text = "after"
line[1].hl = "Special"

float:flush(1)
```

Alternatively, construct a new line table and pass it to `set_line()`.

## `flush()`

Repaint one cached row:

```lua
float:flush(4)
```

Repaint every cached row:

```lua
float:flush()
```

`flush()` does not create new content. It reapplies the line data already cached
by the float.

It is mainly useful when cached line tables have intentionally been mutated in
place or when an explicit repaint is desired.

---

# Clearing content

## `clear_line()`

```lua
float:clear_line(3)
```

Removes the cached spans for one row.

Calling it for a row that has no cached content is harmless.

## `clear()`

```lua
float:clear()
```

Removes all cached rows and their rendered extmarks while keeping the float
object usable.

The configured window height is retained.

---

# Opening, hiding and closing

## `open()`

```lua
float:open()
```

Creates the backing buffer if necessary and opens the floating window.

Calling `open()` again while the window is already valid reuses the existing
window.

## `hide()`

```lua
float:hide()
```

Closes only the floating window.

The backing buffer and cached line data are retained, so the same float can be
shown again cheaply:

```lua
float:hide()
-- later
float:open()
```

## `close()`

```lua
float:close()
```

Closes the window, deletes the backing buffer and discards all cached content.
The `Float` object itself remains reusable, but reopening it starts with no cached
lines.

Use `hide()` for temporary visibility changes and `close()` when the float's
current contents are no longer needed.

---

# Reconfiguring an existing float

```lua
float:configure(opts)
```

Any creation option may be changed later.

```lua
float:configure({
    width = 60,
    height = 14,
    row = 1,
    col = 10,
    title = " Updated ",
})
```

If the float is open, changed Neovim window-config values are applied immediately
with `nvim_win_set_config()`.

Unchanged config values do not cause a window reconfiguration.

This makes it practical to recompute geometry during each render:

```lua
local width = math.max(20, math.min(80, vim.o.columns - 4))
local height = math.max(5, math.min(16, vim.o.lines - 4))

float:configure({
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
})
```

---

# Cursor highlight

A focused float may request a cursor highlight independently from the user's
cursor shape:

```lua
local float = Float.new({
    width = 30,
    height = 8,
    enter = true,
    cursor_hl = "Visual",
})
```

While that float owns focus, `cursor_hl` is appended to `guicursor` as an
all-modes highlight override. The user's existing cursor shapes and blink
settings are retained.

When focus leaves the float, the float is hidden/closed, or another float takes
cursor ownership, the previously saved `guicursor` value is restored.

Only one `Float` instance can own this temporary global cursor override at a
time.

Disable it with:

```lua
float:configure({ cursor_hl = false })
```

`cursor_hl` accepts a highlight-group name. Names beginning with Neovim
`guicursor` directives such as `block`, `ver`, `hor`, `blinkwait`, `blinkon` or
`blinkoff` are rejected so they cannot accidentally be parsed as cursor-shape
configuration.

## CursorLine and selection rendering

`Float` does not use `CursorLine` as its selection mechanism. Its window is opened
with Neovim's `style = "minimal"`, and rows/cells are drawn explicitly from the
highlight groups attached to their spans.

For interactive floats this means the visible selection is normally rendered by
the caller, while the real Neovim cursor only tracks the focused row. `cursor_hl`
can then make that cursor visually match the rendered selection instead of leaving
a differently highlighted cursor cell on top of it.

For example, ChromaFlow's normal menus render the selected row with `Visual`, keep
`cursorline` disabled, and use:

```lua
cursor_hl = "Visual"
```

The selected row and the physical cursor therefore use the same highlight.

The pipeline editor renders its active cell separately and instead uses:

```lua
cursor_hl = "NormalFloat"
```

so the physical cursor stays visually neutral while navigation still moves the
real window cursor to the active row.

A caller may enable `cursorline` manually through the returned window ID if native
Neovim `CursorLine` behavior is desired. It remains an ordinary window option and
is independent from the span highlights rendered by `Float`.

---

# Buffer and window handles

## `buf()`

```lua
local bufnr = float:buf()
```

Returns the loaded backing buffer number, or `nil` while no valid backing buffer
exists.

This is useful for buffer-local keymaps and autocmds:

```lua
float:open()

vim.keymap.set("n", "<Esc>", function()
    float:hide()
end, {
    buffer = float:buf(),
    silent = true,
})
```

The buffer is a scratch buffer with swap and undo disabled.

## `win()`

```lua
local winid = float:win()
```

Returns the current floating-window ID, or `nil` when the float is not open.

It can be used with normal Neovim window APIs:

```lua
float:open()

vim.api.nvim_set_option_value("cursorline", false, {
    win = float:win(),
})
```

## `is_open()`

```lua
if float:is_open() then
    -- window currently exists
end
```

Returns whether the floating window itself is currently valid.

A hidden float therefore returns `false` even though its buffer and cached rows
may still exist.

---

# Highlight namespaces

`Float` only assigns the highlight group named by each span. It does not manage
a window highlight namespace itself.

A caller may attach its own namespace normally:

```lua
local ns = vim.api.nvim_create_namespace("my-float")

vim.api.nvim_set_hl(ns, "MyCell", {
    fg = "#ffffff",
    bg = "#303040",
})

local float = Float.new({
    width = 20,
    height = 3,
})

float:set_line(1, {
    { col = 0, text = "hello", hl = "MyCell" },
})

float:open()
vim.api.nvim_win_set_hl_ns(float:win(), ns)
```

The same applies to ordinary `winhighlight`, cursor options, buffer-local
keymaps and other normal Neovim APIs. `Float` intentionally stays a renderer
rather than trying to become a complete menu or widget framework.

## Performance reference

The reusable renderer is also part of `full_benchmark.lua` and has its own focused
`float_benchmark.lua`. In the checked-in clean-state runs, a same-reference
`set_line()` no-op averages about **0.006 µs**, replacing three spans about
**3.5-3.6 µs**, and a 20-row × 3-span bulk update about **57-60 µs** in the Minimal
scenario. Those values explain why reference equality and batched row updates are
part of the API design; they are not performance guarantees for other machines or
UIs.

---

# Complete API

```lua
local Float = require("cf.fn.float")

local float = Float.new(opts)

float:open()
float:hide()
float:close()

float:set_line(row, line)
float:set_lines(start_row, lines)
float:clear_line(row)
float:clear()
float:flush(row) -- row optional

float:configure(opts)

float:is_open()
float:buf()
float:win()
```

The corresponding LuaLS metadata is included with ChromaFlow, so these public
methods and option/span types are available to LuaLS when the bundled meta
library is configured.
