# Highlight resolver

## Contents

- [The three resolver layers](#the-three-resolver-layers)
- [Resolver knowledge is intentionally small](#resolver-knowledge-is-intentionally-small)
- [Existing names are canonicalized](#existing-names-are-canonicalized)
- [Built-in type naming deviations](#built-in-type-naming-deviations)
- [Why some mapped groups are non-writable](#why-some-mapped-groups-are-non-writable)
- [Filetype-specific resolution](#filetype-specific-resolution)
- [Global language modules](#global-language-modules)
- [Type resolution](#type-resolution)
- [Additional `types`](#additional-types)
- [Modifiers](#modifiers)
- [Modifier naming deviations](#modifier-naming-deviations)
- [Type + modifier combinations](#type--modifier-combinations)
- [TypeMod `false`](#typemod-false)
- [Standalone module `mods`](#standalone-module-mods)
- [Names with no existing resolved type](#names-with-no-existing-resolved-type)
- [Names with no existing standalone modifier](#names-with-no-existing-standalone-modifier)
- [Type + modifier fallback](#type--modifier-fallback)
- [Resolver literal handling is not `raw`](#resolver-literal-handling-is-not-raw)
- [`style_targets`](#style_targets)
- [`style_targets_clear` is independent](#style_targets_clear-is-independent)
- [Non-writable fallbacks are not cleared](#non-writable-fallbacks-are-not-cleared)
- [Style materialization uses anchors](#style-materialization-uses-anchors)
- [Identical styles may reuse an existing anchor](#identical-styles-may-reuse-an-existing-anchor)
- [Deduplication does not redefine semantic hierarchy](#deduplication-does-not-redefine-semantic-hierarchy)
- [Existing semantic anchors can shorten materialization](#existing-semantic-anchors-can-shorten-materialization)
- [Why `:Inspect` can look like the chain was flattened](#why-inspect-can-look-like-the-chain-was-flattened)
- [Semantic links](#semantic-links)
- [Semantic links and clears](#semantic-links-and-clears)
- [Links to unknown target types](#links-to-unknown-target-types)
- [The resolver does not own diagnostics](#the-resolver-does-not-own-diagnostics)
- [Resolution caches](#resolution-caches)
- [Cache invalidation on theme apply](#cache-invalidation-on-theme-apply)
- [The resolver does not own styles](#the-resolver-does-not-own-styles)
- [Runtime target discovery reuses resolver semantics](#runtime-target-discovery-reuses-resolver-semantics)
- [CFPick uses resolver naming knowledge in reverse](#cfpick-uses-resolver-naming-knowledge-in-reverse)
- [Tree-sitter dotted names are not automatically LSP modifiers](#tree-sitter-dotted-names-are-not-automatically-lsp-modifiers)
- [Missing Tree-sitter TypeMods are not invented by normal fallback](#missing-tree-sitter-typemods-are-not-invented-by-normal-fallback)
- [Target masks affect style reuse](#target-masks-affect-style-reuse)
- [Unchanged names still belong to source layers](#unchanged-names-still-belong-to-source-layers)
- [A complete type example](#a-complete-type-example)
- [A non-writable fallback example](#a-non-writable-fallback-example)
- [A broad Tree-sitter fallback example](#a-broad-tree-sitter-fallback-example)
- [A TypeMod example](#a-typemod-example)
- [A semantic link example](#a-semantic-link-example)
- [Resolver priority is action priority, not resolver priority](#resolver-priority-is-action-priority-not-resolver-priority)
- [Physical groups are an implementation detail](#physical-groups-are-an-implementation-detail)
- [Performance design](#performance-design)
- [Practical rules](#practical-rules)

The resolver is the part of ChromaFlow that turns semantic declarations into
real Neovim highlight names.

Most theme code never calls it directly. You write something like:

```lua
l:group("variable", { fg = c.variable })
```

and the resolver decides which Vim/Syntax, Tree-sitter, and LSP groups represent
that semantic type in the current context.

Conceptually, its job is simple:

```text
semantic type / modifier / TypeMod
              |
              v
      resolve concrete names
              |
              v
   Vim/Syntax -> Tree-sitter -> LSP
              |
              v
      materialize only what is needed
```

The large part is not the basic idea. It is preserving the correct naming,
fallback, ownership, target, filetype, link, and deduplication rules for all of
those forms without flattening them into one giant table of hard-coded highlight
names.

The public module APIs that feed the resolver are documented separately:

- [`language.md`](language.md)
- [`plugin.md`](plugin.md)
- [`ui.md`](ui.md)
- [`raw.md`](raw.md)
- [`runtime.md`](runtime.md)

## The three resolver layers

ChromaFlow treats resolved highlight names as three ordered layers:

| Layer | Source system |
| ---: | --- |
| 1 | Vim / syntax |
| 2 | Tree-sitter |
| 3 | LSP semantic tokens |

The normal layer direction is:

```text
LSP -> Tree-sitter -> Vim/Syntax
```

For example, the global semantic type `variable` normally resolves to:

```text
Identifier
@variable
@lsp.type.variable
```

and a normal materialization can therefore be equivalent to:

```lua
vim.api.nvim_set_hl(0, "Identifier", { fg = 0x8FB4FF })
vim.api.nvim_set_hl(0, "@variable", { link = "Identifier" })
vim.api.nvim_set_hl(0, "@lsp.type.variable", { link = "@variable" })
```

For a language module such as Lua, the same semantic chain becomes:

```text
luaIdentifier
@variable.lua
@lsp.type.variable.lua
```

with an equivalent write shape such as:

```lua
vim.api.nvim_set_hl(0, "luaIdentifier", { fg = 0x8FB4FF })
vim.api.nvim_set_hl(0, "@variable.lua", { link = "luaIdentifier" })
vim.api.nvim_set_hl(0, "@lsp.type.variable.lua", { link = "@variable.lua" })
```

The important invariant is not that all three physical groups must always be
written. The invariant is that **when the resolver builds the semantic chain, it
does not flatten LSP directly to the Vim/Syntax layer**.

If all three layers are needed, the semantic order stays:

```text
LSP -> Tree-sitter -> Vim/Syntax
```

Style deduplication can still change the final physical anchor. That is covered
later in this chapter.

## Resolver knowledge is intentionally small

The resolver is not built around one exhaustive list of allowed types, modifiers,
TypeMods, Tree-sitter captures, or LSP tokens.

The real highlight environment comes from Neovim. ChromaFlow builds the current
highlight-name catalog outside the resolver, and the resolver asks that catalog
which candidate names already exist.

The small tables near the top of `resolver.lua` contain only the places where the
normal spelling is not enough:

| Resolver table | Contains |
| --- | --- |
| `TYPE_MAP` | Type spelling deviations and broad non-writable fallbacks |
| `LSP_TYPE_TOKEN` | LSP type-token spelling deviations |
| `TYPEMOD_MAP` | Source-specific modifier-token spelling deviations |

For example, `function`, `keyword`, `string`, `number`, `comment`, and arbitrary
custom names do not need entries merely to be usable. Without a deviation, the
resolver starts from the name exactly as it was given and applies the normal
Vim/Tree-sitter/LSP naming form around it.

The tables are therefore **exceptions to normal name construction, not a list of
what ChromaFlow supports**. This is what keeps the resolver generic instead of
turning it into a permanently maintained catalog of every highlight known to
Neovim, Tree-sitter, LSP servers, plugins, and user themes.

The separate `known_lsp_modifier()` knowledge has one narrow job: it recognizes
standard standalone LSP modifier targets of the form:

```text
@lsp.mod.<modifier>
```

It is not a TypeMod whitelist and it does not describe
`@lsp.typemod.<type>.<modifier>` combinations.

## Existing names are canonicalized

Before theme modules are applied, ChromaFlow builds a catalog of Neovim's
current highlight names.

Lookups against that catalog are case-insensitive, while the canonical spelling
already present in Neovim is preserved.

For example, the semantic spelling:

```text
function
```

can resolve the Vim candidate to:

```text
Function
```

rather than creating a second differently-cased name.

When no existing name is available and a rule allows a new concrete target to
be created, ChromaFlow uses the generated spelling as written.

## Built-in type naming deviations

Most types use their semantic spelling directly. The following mappings exist
because one or more source systems use a different name or because a broad
fallback must not be overwritten.

| Semantic type | Vim/Syntax candidate | Tree-sitter token | LSP type token | Important ownership rule |
| --- | --- | --- | --- | --- |
| `variable` | `Identifier` | `variable` | `variable` | Vim target is writable |
| `parameter` | `Identifier` | `variable.parameter` | `parameter` | `Identifier` is fallback-only, not writable |
| `method` | `Function` | `function.method` | `method` | `Function` is fallback-only, not writable |
| `namespace` | semantic spelling | `module` | `namespace` | normal writable TS mapping |
| `regexp` | semantic spelling | `string.regexp` | `regexp` | normal writable TS mapping |
| `class` | semantic spelling | `type` | `class` | broad `@type` fallback is not writable |
| `enum` | semantic spelling | `type` | `enum` | broad `@type` fallback is not writable |
| `interface` | semantic spelling | `type` | `interface` | broad `@type` fallback is not writable |
| `struct` | semantic spelling | `type` | `struct` | broad `@type` fallback is not writable |
| `modifier` | semantic spelling | `keyword.modifier` | `modifier` | broad TS fallback is not writable |

Two LSP type spellings also need case conversion:

| Semantic name | LSP token spelling |
| --- | --- |
| `enummember` | `enumMember` |
| `typeparameter` | `typeParameter` |

These tables are **naming knowledge**, not a promise that every candidate exists
in every Neovim setup.

The current environment still confirms which candidates are actually present.

## Why some mapped groups are non-writable

Some semantic concepts have a useful broad fallback but should not own that
fallback.

For example:

```text
class -> @type
```

is useful as a fallback relationship, but styling `class` must not casually
rewrite the global `@type` capture for every other type.

The same issue exists with:

| Semantic type | Vim/Syntax fallback |
| --- | --- |
| `parameter` | `Identifier` |
| `method` | `Function` |

`Identifier` and `Function` are valid lower-level fallbacks, but they are much
broader than the semantic concepts `parameter` and `method`.

The resolver therefore tracks not only a concrete name, but whether that name is
**writable for this semantic declaration**.

A non-writable fallback may participate in resolution and anchoring, but the
resolver does not use that declaration to overwrite or clear the broad group.

This distinction is important for both `style_targets` and
`style_targets_clear`.

## Filetype-specific resolution

Language modules add a filetype context.

The resolver first resolves the generic semantic names and then derives the
filetype forms from those resolved names.

The rules are:

| Layer | Filetype-local form |
| --- | --- |
| Vim/Syntax | `<filetype><resolved-name>` |
| Tree-sitter | `<resolved-name>.<filetype>` |
| LSP | `<resolved-name>.<filetype>` |

For Lua `variable`:

| Generic name | Lua-local name |
| --- | --- |
| `Identifier` | `luaIdentifier` |
| `@variable` | `@variable.lua` |
| `@lsp.type.variable` | `@lsp.type.variable.lua` |

For Lua `method`:

| Generic name | Lua-local name |
| --- | --- |
| `Function` | `luaFunction` |
| `@function.method` | `@function.method.lua` |
| `@lsp.type.method` | `@lsp.type.method.lua` |

The writability of the generic semantic mapping is preserved. So the derived
`luaFunction` remains a fallback-only Vim/Syntax representation for `method`;
it does not suddenly become writable just because a filetype suffix was added.

An already existing filetype-specific group keeps the canonical spelling from
the environment catalog. A missing writable target can be created with the
deterministic generated name.

## Global language modules

`l.setup(nil, ...)` has no filetype context.

The resolver therefore uses the generic forms directly:

```text
Identifier
@variable
@lsp.type.variable
```

This is different from `l.setup("lua", ...)`, where the filetype-specific forms
are derived.

## Type resolution

A plain semantic group such as:

```lua
l:group("variable", {
  fg = c.variable,
})
```

is compiled as a resolver style action for one semantic type.

At apply time the resolver:

1. resolves the Vim/Syntax candidate,
2. resolves the Tree-sitter candidate,
3. resolves the LSP candidate,
4. applies the requested clear mask,
5. selects a suitable style anchor,
6. links higher semantic layers through that anchor.

With all three writable targets selected, the most obvious result is:

| Name | Materialization |
| --- | --- |
| `Identifier` | Owns the style |
| `@variable` | Links to `Identifier` |
| `@lsp.type.variable` | Links to `@variable` |

But the exact physical result can be smaller when a compatible style already
exists.

## Additional `types`

A group may declare additional semantic types:

```lua
l:group("function", {
  fg = c.func,
  types = {
    "constructor",
    "method",
  },
})
```

The primary type owns the style or external link.

Additional types do not duplicate the style definition. They are compiled as
semantic links to the primary type:

| Additional type | Semantic link target |
| --- | --- |
| `constructor` | `function` |
| `method` | `function` |

Each of those links is still resolved per target layer.

This keeps one explicit style anchor for the declaration while allowing several
semantic types to share it.

## Modifiers

Modifiers can exist without a type. Module-level `mods` are the public example of
that shape.

The resolver tries the modifier in the three normal source forms:

| Layer | Standalone modifier form |
| --- | --- |
| Vim/Syntax | `<modifier>` |
| Tree-sitter | `@<ts-modifier-token>` |
| LSP | `@lsp.mod.<lsp-modifier-token>` |

For Vim/Syntax and Tree-sitter, an ordinary modifier candidate has to exist in the
current highlight environment before it is used.

Standalone LSP modifiers are slightly different. The resolver knows the standard
LSP modifier tokens:

```text
abstract
async
declaration
definition
deprecated
documentation
modification
readonly
static
```

so `@lsp.mod.<modifier>` may be addressed even when that exact highlight group was
not present when the environment catalog was built. This knowledge applies to the
standalone `@lsp.mod.*` form only.

## Modifier naming deviations

Only source-specific spelling differences need a mapping:

| Semantic modifier | Tree-sitter token | LSP token |
| --- | --- | --- |
| `builtin` | `builtin` | `defaultLibrary` |
| `defaultlibrary` | `builtin` | `defaultLibrary` |

For every other modifier, the given spelling is already the token used by normal
name construction. A modifier does not become "unknown" merely because it is not
listed in `TYPEMOD_MAP`.

## Type + modifier combinations

A TypeMod is one concrete combination of a type and a modifier. It is not the same
thing as a standalone modifier.

For example:

```text
variable + readonly
```

uses the resolved source tokens to form the two TypeMod namespaces:

| Layer | TypeMod form |
| --- | --- |
| Tree-sitter | `@<ts-type-token>.<ts-modifier-token>` |
| LSP | `@lsp.typemod.<lsp-type-token>.<lsp-modifier-token>` |

There is no ordinary Vim/Syntax TypeMod namespace.

The important point is that "literal" does not describe a second resolver mode.
It only means that a token is used unchanged instead of being replaced by one of
the naming deviations above. The resolver may still combine those tokens into one
Tree-sitter or LSP TypeMod name.

### Normal TypeMod resolution

A TypeMod whose style remains owned by the type -- for example:

```lua
typemods = {
  readonly = true,
}
```

uses the normal resolved TypeMod candidates.

For Tree-sitter, a concrete dotted combination is reused only when that exact
combination exists in the current highlight environment. The resolver does not
create every syntactically possible `@<type>.<modifier>` capture merely because
the two tokens can be concatenated.

If the type is known but that TypeMod combination is not, and the TypeMod does
not own its own style, Tree-sitter falls back to the modifier target instead:

```text
@<ts-modifier-token>
```

It does **not** manufacture `@<ts-type-token>.<ts-modifier-token>` for that case.

For LSP, once both normal LSP components are available, the TypeMod spelling is
deterministic:

```text
@lsp.typemod.<type-token>.<modifier-token>
```

so that concrete LSP TypeMod name can be used even if the combined name itself was
not already present. The `known_lsp_modifier()` list still belongs to standalone
`@lsp.mod.*` resolution; it must not be read as a registry of allowed
`@lsp.typemod.*` combinations.

If neither normal TypeMod representation can carry the request, the existing
resolver fallback rules continue from the original modifier/type information
rather than inventing a new semantic mapping.

### A styled TypeMod owns its concrete combination

A TypeMod table with its own style or pipeline is different because that style
belongs to the concrete type+modifier combination itself:

```lua
l:group("variable", {
  fg = c.variable,

  typemods = {
    readonly = {
      italic = true,
    },
  },
})
```

The TypeMod style is built from the finished base style when one exists, then its
own fields/pipeline are applied. The base type is naming context; it does not have
to be materialized as a style target just to style the TypeMod.

Because this declaration explicitly owns the concrete combination, the resolver
can build its Tree-sitter/LSP names directly from the already selected tokens:

```text
@variable.readonly
@lsp.typemod.variable.readonly
```

The same rule keeps custom TypeMods possible. A custom type or modifier does not
need to be added to one of ChromaFlow's mapping tables first; those tables only
change spellings where the source systems differ.

`style_targets` is already resolved outside this naming logic and is passed in as
the target mask. It decides which of the resulting source layers are actually
written; it is not another resolver path. In particular, `ts = true, lsp = false`
materializes the Tree-sitter combination without also materializing an LSP
TypeMod.

If a requested concrete target had to be created rather than reused from the
current environment, the resolver can return `unresolved_literal` so the
diagnostic layer can report that fact. Here `literal` still means that the
constructed target used the supplied/resolved tokens as concrete names; it does
not mean that every token became a separate `nvim_set_hl()` operation.

## TypeMod `false`

A TypeMod may be explicitly removed:

```lua
l:group("variable", {
  typemods = {
    readonly = false,
  },
})
```

This compiles to a resolver clear action for that semantic combination.

Unlike a style action, no cached style object is needed: the whole point is to
remove the writable resolved targets.

A broken TypeMod entry is isolated from its siblings. ChromaFlow rolls back only
the failing TypeMod compilation scope, so a valid base group and other valid
TypeMods remain intact.

## Standalone module `mods`

A module-level `mods` table resolves modifiers without an owning type:

```lua
return l.setup("lua", {
  mods = {
    readonly = {
      italic = true,
    },
  },
})
```

The resolver receives the modifier with no `type_name` and resolves whatever
normal modifier targets are available for the selected systems.

Module-level modifier entries inherit the module target policy and cannot define
their own `style_targets` or `style_targets_clear`.

See the language/plugin/UI module chapters for the public DSL restrictions
around module `mods`.

## Names with no existing resolved type

A type does not fail merely because none of its normal candidates already exists.

When the normal lookup cannot confirm a representation, the resolver keeps the
input spelling and builds the ordinary type forms from it. For:

```text
MissingType
```

the generic names are:

```text
MissingType
@MissingType
@lsp.type.MissingType
```

and with Lua filetype context:

```text
luaMissingType
@MissingType.lua
@lsp.type.MissingType.lua
```

This is the precise meaning of literal handling in the resolver: `MissingType` is
used as `MissingType`; it is not translated through semantic naming knowledge that
does not exist. The surrounding Vim/Tree-sitter/LSP name construction still
works normally.

The resolver returns:

```text
unresolved_literal
```

so the higher diagnostic layer may report that unchanged-name fallback was
required without putting source diagnostics into the resolver hot path.

## Names with no existing standalone modifier

A standalone modifier has no three-layer type chain of its own. If normal
modifier resolution cannot produce a usable target, the modifier spelling itself
is used as the fallback highlight name.

For example:

```text
MissingMod
```

falls back to:

```text
MissingMod
```

Its spelling still identifies the source layer when it is already source-shaped:

| Name shape | Source layer |
| --- | --- |
| `normal name` | Vim/Syntax |
| `@name` | Tree-sitter |
| `@lsp....` | LSP |

The active target mask decides whether that layer is written.

## Type + modifier fallback

Type and modifier lookup stay separate. A normal type-owned TypeMod does not turn
two missing pieces into an arbitrary new semantic mapping. If its base type itself
has no normal resolved representation, the type's unchanged-name chain remains
the fallback identity.

A styled TypeMod is the deliberate concrete-combination case described above: it
owns that `type + modifier` target and can therefore build the TS/LSP combination
from the selected tokens directly.

## Resolver literal handling is not `raw`

`raw:*` and resolver literal handling both involve names that are not semantically
remapped, but they enter the system at different levels.

`raw:group()` means:

> This is already the complete Neovim highlight name. Do not run resolver naming
> rules around it.

Resolver literal handling means:

> Use this type/modifier token exactly as supplied because no naming deviation
> replaces it; normal resolver construction may still produce the corresponding
> Vim, Tree-sitter, LSP, or concrete TypeMod name.

So an unchanged type token `Foo` may participate in:

```text
Foo
@Foo
@lsp.type.Foo
```

while raw `@Foo` means exactly one already-complete highlight name: `@Foo`.

For a TypeMod, unchanged tokens still do not imply that the dotted combination is
always created. If `Foo` is a known type, `custom` has no matching TypeMod for
that type, and the TypeMod has no style of its own, a Tree-sitter target falls
back to:

```text
@custom
```

rather than manufacturing `@Foo.custom`.

Only a TypeMod that owns its own concrete style may deliberately build the
`@Foo.custom` combination from those tokens. "Literal" therefore describes how
a token is used, not whether a particular combined TypeMod target is created.

See [`raw.md`](raw.md).

## `style_targets`

The resolver ultimately receives a write mask for the three layers:

```text
vim
ts
lsp
```

At the low-level resolver boundary:

```text
targets = nil
```

means all three layers are selected.

Theme modules normally pass an already-computed effective target table based on
`config.cf`, module settings, and group settings.

For example:

```lua
style_targets = {
  vim = false,
  ts = true,
  lsp = true,
}
```

for `variable` in Lua can produce:

```lua
vim.api.nvim_set_hl(0, "@variable.lua", { fg = 0x8FB4FF })
vim.api.nvim_set_hl(0, "@lsp.type.variable.lua", { link = "@variable.lua" })
```

The unselected Vim/Syntax layer is not written merely because it exists in the
semantic chain.

For the public precedence rules between config/module/group target policies, see
the module chapters.

## `style_targets_clear` is independent

The clear mask and the write mask are intentionally independent.

For example:

```lua
style_targets = {
  vim = false,
  ts = true,
  lsp = false,
}

style_targets_clear = {
  vim = true,
  lsp = true,
}
```

can mean:

```text
clear writable Vim representation
clear writable LSP representation
write only the Tree-sitter representation
```

The resolver performs applicable clears before the new materialization.

This remains true even when the write mask is empty.

That makes configurations such as this meaningful:

```lua
style_targets = {}
style_targets_clear = { ts = true, lsp = true }
```

No new semantic style is written, but the requested writable TS/LSP targets are
still cleared.

## Non-writable fallbacks are not cleared

Clear independence does not override semantic ownership.

If a semantic mapping marks a broad fallback as non-writable, that declaration
will not clear it either.

For example, clearing the TS representation of `class` must not erase the broad
shared `@type` capture merely because `class` can fall back through it.

This is why the resolver tracks `name + writable`, not just `name`.

## Style materialization uses anchors

ChromaFlow does not need to write the same complete style table into every
semantic layer.

Instead it chooses one style anchor and links other layers through it.

The simple all-target `variable` case is:

| Name | Materialization |
| --- | --- |
| `Identifier` | Style anchor |
| `@variable` | Links to `Identifier` |
| `@lsp.type.variable` | Links to `@variable` |

If Vim is disabled:

| Name | Materialization |
| --- | --- |
| `@variable` | Style anchor |
| `@lsp.type.variable` | Links to `@variable` |

If only LSP is enabled:

```text
@lsp.type.variable        style anchor
```

This keeps the number of full `nvim_set_hl()` style writes smaller and preserves
the semantic layer relationship.

## Identical styles may reuse an existing anchor

ChromaFlow interns complete styles. If another already-materialized highlight at
an eligible layer owns the exact same interned style object, the resolver may
link a new base group to that existing style target instead of writing the same
style again.

Conceptually, instead of:

```text
SomeGroup = { complete style A }
```

it may use:

```text
SomeGroup -> ExistingGroupWithStyleA
```

This deduplication is based on the full normalized style, not merely one colour
field.

The semantic identity of `SomeGroup` still exists. Only its physical style
storage is reused.

## Deduplication does not redefine semantic hierarchy

Style reuse can add another physical link below the semantic chain.

For example:

```text
@lsp.type.variable
        -> @variable
        -> Identifier
        -> ExistingGroupWithSameStyle
```

is possible.

That does **not** mean the resolver decided that the LSP group semantically maps
to `ExistingGroupWithSameStyle`.

It means:

1. LSP still links to its Tree-sitter representation,
2. Tree-sitter still links to its Vim/Syntax representation,
3. the final style storage was deduplicated to an existing compatible anchor.

Runtime or CFPick can temporarily materialize a concrete group directly while a
full theme reload may deduplicate the finished style again.

## Existing semantic anchors can shorten materialization

If a semantic layer already directly owns the exact style, the resolver can use
that layer as the anchor and avoid rewriting lower layers unnecessarily.

For example, if `@variable` already directly owns the requested style, a later
resolution can keep it as the anchor and only ensure the LSP layer points to it.

This is another reason the exact physical link graph should not be treated as
the public semantic model.

## Why `:Inspect` can look like the chain was flattened

Neovim's inspection output may show a transformed/final link target rather than
the immediate link ChromaFlow wrote.

Suppose ChromaFlow has:

```text
@lsp.type.variable.lua -> @variable.lua
@variable.lua          -> luaIdentifier
luaIdentifier          -> Identifier
```

`:Inspect` may display the LSP group as linking to the final `Identifier` target.

That does not prove ChromaFlow wrote:

```text
@lsp.type.variable.lua -> Identifier
```

To inspect the immediate direct highlight definition, use:

```lua
vim.api.nvim_get_hl(0, {
  name = "@lsp.type.variable.lua",
  link = true,
  create = false,
})
```

For the chain above, the direct result contains:

```lua
{
  link = "@variable.lua",
}
```

This distinction is useful when debugging resolver behavior.

## Semantic links

A declaration such as:

```lua
l:link("character", "string")
```

is not one raw Neovim link.

Both the source and target are resolved semantically.

For each selected writable source layer, ChromaFlow links to the best available
representation of the target at the same or a lower layer.

Conceptually, when all matching representations exist:

| Source layer | Link behavior |
| --- | --- |
| Vim | Character source → string target |
| Tree-sitter | Character source → string target |
| LSP | Character source → string target |

If the same-layer target representation is unavailable, the resolver can use a
lower target layer rather than inventing an invalid semantic source hierarchy.

A semantic link therefore preserves source-system meaning as far as the target
semantics allow.

## Semantic links and clears

A semantic link receives the same independent target and clear masks as a style
action.

For each writable source layer:

1. the clear mask may clear the source,
2. the target mask may then write the semantic link,
3. a source is never linked to itself.

The target semantic type is only used to choose link destinations. The link
action does not separately style the target type.

## Links to unknown target types

If the target semantic type cannot be resolved normally, its literal type chain
is still available as the semantic link target.

The link can therefore remain functional while the resolver returns
`unresolved_literal` for the diagnostic layer.

The same diagnostic status is returned if the source side itself required
unchanged-name fallback.

## The resolver does not own diagnostics

The resolver intentionally returns only a compact status:

```text
nil
```

for normal resolution, or:

```text
unresolved_literal
```

when unchanged-name fallback occurred.

It does not allocate and queue rich diagnostics itself.

`cf.hl.setup` knows the source file/declaration location and turns that compact
status into the appropriate source-aware hint when that diagnostic severity is
enabled.

This keeps source reporting out of the resolver's hot path.

## Resolution caches

The resolver maintains caches for:

```text
types
modifiers
TypeMods
literal names
filetype-derived types
filetype-derived modifiers
filetype-derived TypeMods
literal type chains
explicit concrete TypeMods
```

Those caches contain **resolution results and names**, not style objects owned by
the resolver.

The style cache/materialization catalog belongs to the highlight runtime backend.

This separation matters because the resolver can invalidate naming knowledge
without throwing away session-lifetime style interning.

## Cache invalidation on theme apply

A full ChromaFlow theme apply performs a destructive Neovim highlight reset.

After that reset ChromaFlow:

1. rebuilds the current highlight-name catalog,
2. clears resolver name caches,
3. applies global clear policy,
4. applies the compiled module actions.

As new groups are materialized, the backend immediately adds them to the live
catalog. An uncached later resolution can therefore see names created earlier in
the same apply. Resolver entries that were already cached are intentionally not
re-resolved mid-pass; the full cache is rebuilt at the next resolver invalidation.

Cached canonical names from an older highlight environment are therefore not
blindly reused after a full colorscheme rebuild.

## The resolver does not own styles

The resolver receives an already-built cached style object.

It does not normalize colours, run pipelines, inherit TypeMod fields, or mutate
that style.

Those jobs happen before the resolver action executes.

The resolver only decides things such as:

```text
which concrete names?
which layers are writable?
which layers are selected?
which layers are cleared?
where should the style be anchored?
which groups should link?
```

This separation is one reason the resolver can stay comparatively small despite
covering many naming combinations.

## Runtime target discovery reuses resolver semantics

Runtime semantic targets need to know which concrete Neovim names belong to a
theme action.

The resolver exposes target-discovery helpers for that purpose, but those helpers
**do not apply styles and do not call the setter**.

They reuse the resolver's already-built naming caches and return the concrete
writable names selected by the original target/clear policy.

That keeps Runtime aligned with normal theme semantics without performing a
second materialization pass.

Runtime discovery is lazy, so a normal theme reload does not pay this work for
every semantic action. It is needed only for runtime targets that are actually
used.

See [`runtime.md`](runtime.md).

## CFPick uses resolver naming knowledge in reverse

The normal resolver direction is:

```text
semantic name -> source-specific highlight names
```

CFPick sometimes needs the opposite direction:

```text
source-specific token -> ChromaFlow semantic spelling
```

The resolver therefore also contains small reverse naming helpers for semantic
type and TypeMod tokens.

Examples include:

| Concrete name/token | Semantic name |
| --- | --- |
| LSP `enumMember` | `enummember` |
| LSP `typeParameter` | `typeparameter` |
| TS `function.method` | `method` |
| TS `variable.parameter` | `parameter` |

Only real naming deviations belong in those maps. CFPick still handles its own
source collection, concrete-capture interpretation, priority, and save logic.

That full behavior belongs in [`picker.md`](picker.md).

## Tree-sitter dotted names are not automatically LSP modifiers

Tree-sitter dotted captures and LSP modifiers are different namespaces:

```text
@function.call
@function.method
@variable.parameter
```

are Tree-sitter capture names/hierarchy. A suffix after a Tree-sitter dot is not
automatically an LSP semantic-token modifier.

That is why the resolver keeps type-token mapping, standalone modifier mapping,
and TypeMod combination logic separate instead of treating every dotted capture
as the same kind of object.

CFPick's reverse interpretation follows the same rule and adds its own picker-local
parsing where needed.

## Missing Tree-sitter TypeMods are not invented by normal fallback

For an ordinary type-owned TypeMod (`typemods = { name = true }`), the resolver
uses a Tree-sitter `@<type>.<modifier>` combination only when that exact capture is
already present in the current environment.

If the type is known but that combination is not, Tree-sitter falls back to the
modifier target `@<modifier>` instead of inventing `@<type>.<modifier>`.

This rule prevents normal fallback from manufacturing Tree-sitter captures merely
because their spelling is possible. It does **not** make the mapping tables a
whitelist, and it does not prevent a deliberately styled/custom TypeMod from
owning and creating its concrete combination.

## Target masks affect style reuse

Style deduplication only considers an existing style anchor when its layer is
compatible with the current target mask and the maximum layer the new base is
allowed to link through.

A declaration targeting only Tree-sitter should not silently reuse an LSP-only
style anchor just because the style objects are identical.

The layer ordering remains part of the deduplication decision.

## Unchanged names still belong to source layers

When the resolver uses an unchanged fallback name, ChromaFlow still classifies
that complete name by source layer:

| Name | Source layer |
| --- | --- |
| `Foo` | Vim/Syntax |
| `@foo` | Tree-sitter |
| `@lsp.type.foo` | LSP |
| `@lsp.typemod.foo.readonly` | LSP |

That classification lets `style_targets` and `style_targets_clear` keep their
normal meaning. For example, `@Something` is not written when only `vim = true`
is selected.

## A complete type example

Consider:

```lua
return l.setup("lua", {
  style_targets = {
    vim = true,
    ts = true,
    lsp = true,
  },

  l:group("variable", {
    fg = c.variable,
  }),
})
```

The resolver sees:

```text
type     = variable
filetype = lua
```

Generic semantic names:

| Layer | Resolved name |
| --- | --- |
| Vim | `Identifier` |
| Tree-sitter | `@variable` |
| LSP | `@lsp.type.variable` |

Filetype forms:

| Layer | Filetype-local name |
| --- | --- |
| Vim | `luaIdentifier` |
| Tree-sitter | `@variable.lua` |
| LSP | `@lsp.type.variable.lua` |

Typical materialization:

```lua
vim.api.nvim_set_hl(0, "luaIdentifier", {
  fg = 0x8FB4FF,
})

vim.api.nvim_set_hl(0, "@variable.lua", {
  link = "luaIdentifier",
})

vim.api.nvim_set_hl(0, "@lsp.type.variable.lua", {
  link = "@variable.lua",
})
```

An existing equal style anchor can change the final physical storage, but the
semantic naming decision remains the same.

## A non-writable fallback example

Consider Lua `method`:

```lua
l:group("method", {
  fg = c.func,
})
```

The semantic candidates are based on:

| Layer | Name | Writable for `method` |
| --- | --- | ---: |
| Vim fallback | `Function` | no |
| Tree-sitter | `@function.method` | yes |
| LSP | `@lsp.type.method` | yes |

For Lua:

```text
luaFunction
@function.method.lua
@lsp.type.method.lua
```

Because the Vim representation is a broad fallback rather than owned by
`method`, the normal style anchor is typically the Tree-sitter method group:

| Name | Materialization |
| --- | --- |
| `@function.method.lua` | Style anchor |
| `@lsp.type.method.lua` | Links to `@function.method.lua` |

The resolver does not rewrite `luaFunction` merely to make the chain visually
symmetrical.

## A broad Tree-sitter fallback example

For `class`, Tree-sitter normally falls back through broad `@type` semantics:

```text
class -> @type
```

but `@type` is marked non-writable for this mapping.

So a `class` declaration may style a more specific writable representation such
as its LSP type without overwriting every Tree-sitter type in the editor.

If `@type` already directly owns the exact style, it may still be useful as an
existing semantic anchor. Non-writable means "do not claim and rewrite this
broad group", not "pretend this fallback does not exist".

## A TypeMod example

Consider:

```lua
l:group("variable", {
  fg = c.variable,

  typemods = {
    readonly = {
      italic = true,
    },
  },
})
```

The base style is built first.

The TypeMod style inherits that finished base style and adds `italic = true`.

For Lua, the explicit combination targets are conceptually:

```text
@variable.readonly.lua
@lsp.typemod.variable.readonly.lua
```

There is no ordinary Vim/Syntax TypeMod target.

If those concrete targets were not previously known, ChromaFlow can materialize
them because the explicit TypeMod style owns the combination, while still
emitting the literal-fallback hint through diagnostics.

## A semantic link example

Consider:

```lua
l:link("character", "string")
```

The resolver does not blindly write:

```text
character -> string
```

as one raw group link.

Instead it resolves source and target semantics at each selected layer.

A possible conceptual result is:

| Source | Semantic link target |
| --- | --- |
| Character-like Vim source | `String` |
| `@character` | `@string` |
| `@lsp.type.character` | `@lsp.type.string` |

Exact existing names determine the real result, and a missing same-layer target
can fall back to a lower target representation.

## Resolver priority is action priority, not resolver priority

The resolver itself does not run a second priority system.

Theme compilation assigns every action its declaration priority. The complete
action list is later sorted so higher-priority actions execute later and can
replace earlier results.

Therefore two semantic declarations that ultimately touch the same concrete
highlight are resolved in normal action order.

For equal priority, later declaration/action order wins.

The resolver only executes the action it is given; it does not reorder semantic
names internally based on style importance.

## Physical groups are an implementation detail

A theme should reason primarily in terms of semantic declarations:

```text
variable
method
parameter
readonly
variable + readonly
```

rather than depending on the exact number of `nvim_set_hl()` calls produced by a
particular reload.

The physical result can legitimately vary because of:

```text
selected targets
existing environment names
filetype context
non-writable fallbacks
existing direct semantic anchors
style deduplication
unchanged-name fallback
priority/order
```

What must stay stable is the semantic contract and the visible final style.

## Performance design

The resolver is deliberately optimized for repeated theme work.

Its hot caches use compact positional entries rather than allocating descriptive
tables on every lookup. Filetype forms are cached separately after the generic
semantic resolution has already been performed.

Warm common resolve calls are regression-tested with LuaJIT allocation elision
disabled. Across 10,000 calls, the tested paths are expected to stay below
1 KiB of observed Lua allocation.

The checked-in clean-state benchmark also gives the hot-path timings some scale:
across its two reference runs, a warm normal Type resolve averages about
**1.05-1.07 µs**, Type + Modifier about **1.16-1.17 µs**, while already-warm
single-target filtering sits around **0.07-0.10 µs**. These are reference numbers
for the documented i5-10310U host, not fixed performance guarantees.

The resolver also avoids owning style copies: it reads the interned style object
from the compiler/runtime cache and passes that same reference to the backend.

This is why a feature with a lot of semantic cases can still remain a small part
of the full theme reload cost.

## Practical rules

When writing a theme, the useful mental model is:

```text
Use semantic groups when the concept is semantic.
Use style_targets to choose the source systems you actually own.
Use explicit TypeMod tables when the combination itself needs its own style.
Use raw:* when you already know the exact Neovim highlight name.
Do not infer resolver correctness from :Inspect's final transformed link alone.
Do not depend on a specific deduplication anchor as public API.
```

The resolver's purpose is to let the theme describe **what** a style means while
ChromaFlow handles **where** that meaning should be materialized in Neovim.
