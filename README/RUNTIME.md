# Runtime modules

ChromaFlow runtime actions are a sparse post-theme layer. They operate on the
semantic targets already known by the compiled theme and do not feed changes
back through normal semantic resolution on every update.

## Loading a runtime module

Runtime modules are loaded by logical name:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime("mystyleactions")
```

Lookup order:

```text
active/runtime/mystyleactions.cf
-> root/runtime/mystyleactions.cf
-> default/runtime/mystyleactions.cf
```

The first match wins. Runtime modules are not merged.

Loading returns one stable module handle. Its backing definition may be rebound
when the theme changes, while public action/target handles remain stable.

## Defining actions

Inside a runtime `*.cf` file, `hl.runtime` becomes a module-scoped DSL proxy:

```lua
local hl = require("cf.hl.setup")
local c = hl.colors
local r = hl.runtime

return r.setup({
    r:group("dim", {
        pipeline = { hl.brightness.fg(-20) },
    }),

    r:group("focus", {
        fg = c.orange,
        bold = true,
    }),
})
```

Runtime action groups contain only ordinary highlight fields and a pipeline.
They do not contain `types`, TypeMods, links, priorities or target masks.

After the module is loaded:

```lua
local r = hl.runtime("mystyleactions")
local dim = r.groups.dim
local same = r.g.dim -- short alias
```

## Semantic targets

Normal DSL namespaces also expose runtime targets through dot indexing:

```lua
hl.language.lua.variable
hl.language.lua.variable.readonly
hl.plugin.codemap.CodeMap
hl.plugin.codemap.CodeMap.keyword
hl.ui.Normal
hl.raw.SomeExactGroup
```

Targets are stable lazy handles. Concrete highlight names are discovered only
when a runtime override actually needs them.

## Four operations

```lua
r.apply(target, action)
r.replace(target, action)
r.reset(target)
r.clear(target)
```

### `apply`

Builds from the current normal theme base, then applies the runtime action.
Repeated `apply()` calls do not accumulate pipeline drift; composition always
starts from the theme base plus the active runtime action stack.

### `replace`

Uses the runtime action as the target style without inheriting the normal theme
base.

### `reset`

Removes this target's runtime override and shows the current normal theme base
again.

### `clear`

Stores an explicit runtime clear for the concrete highlight groups owned by that
semantic target.

Internally the visible layer is equivalent to:

```text
nil    no runtime override
false  explicitly cleared
style  runtime style override
```

The normal theme/materialization cache is not replaced by this layer. Runtime
state therefore remains sparse and is recalculated against the new base after a
normal theme reload or theme switch.

## Timed runtime functions

A runtime module may export a Lua function and explicitly adapt it into an action
pipeline:

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime

function r.alert(style, ctx)
    if ctx.frame % 2 == 0 then
        style.bold = true
        style.fg = hl.colors.red
    else
        style.bold = false
        style.dim = true
    end
    return style
end

return r.setup({
    r:group("panic", {
        pipeline = {
            r:func("alert")[300],
        },
    }),
})
```

`r:func("alert")` evaluates whenever the action is recomposed. The optional
`[300]` suffix requests reevaluation every 300 ms.

The callback receives:

```text
ctx.frame    zero-based frame number; frame 0 is immediate
ctx.tick     requested interval in ms, or nil
ctx.delta    actual ms since the previous tick
ctx.elapsed  actual ms since this action started
```

It may mutate the provided complete style and return `nil`, or return a complete
replacement style table. Runtime functions are the explicit dynamic boundary;
raw Lua functions are not accepted directly as pipeline entries.

One runtime action has one frame clock. Multiple timed functions inside the same
action may share an interval but cannot request conflicting tick intervals.
Resetting/clearing/replacing the override stops or replaces its timer. Theme
reloads rebind the module implementation and restart active timing against the
new theme base.

Assignments to the runtime proxy are module exports:

```lua
function r.alert(...) ... end
r.some_value = 42
```

They are later available from the public module handle:

```lua
local panic = hl.runtime("panic")
print(panic.alert, panic.some_value)
```

## Lua example

```lua
local hl = require("cf.hl.setup")
local r = hl.runtime("mystyleactions")
local lua = hl.language.lua

r.apply(lua.variable, r.g.dim)
r.apply(lua.function, r.g.focus)

-- later
r.reset(lua.variable)
r.clear(lua.function)
```

See `examples/themes/runtime/mystyleactions.cf`, `panic.cf`, `lsd.cf` and
`examples/showcase/lsd.lua` for complete examples.

## Command-line interface

The same core operations are exposed as commands:

```text
:CFApply   r.mystyleactions.dim l.lua.variable
:CFReplace r.mystyleactions.focus l.lua.function
:CFReset   l.lua.variable
:CFClear   l.lua.function
```

Supported command target prefixes:

```text
l.<language>.<type>[.<typemod>]
p.<plugin>.<type>[.<typemod>]
u.<type>[.<typemod>]
```
