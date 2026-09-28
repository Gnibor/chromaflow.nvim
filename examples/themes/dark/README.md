# Semantic dark theme

A usable integration theme for the CF resolver. All declarations use `language`,
`plugin` or `ui`; none use the literal `raw` API. The engine is unchanged.

## Visual rules

Syntax uses muted warm functions, cool types, green-grey variables, mauve
constants and restrained purple keywords. UI surfaces and status colours keep
the existing dark layout. Most code has no token background.

| TypeMod | Type-dependent treatment |
| --- | --- |
| `builtin` | Functions mix towards warm yellow, types towards blue, variables towards blue-grey, constants towards the type colour. |
| `readonly` | Variables mix 45% towards the constant colour with a 5% background tint; properties mix 24% without a background; parameters mix 18% and become italic. |
| `static` | Variables, properties and functions use different small colour shifts and italics. |
| `async` | Functions/methods become italic and mix 20% towards the type colour. |
| `declaration`, `definition` | Functions and types become bold. |
| `abstract` | Functions and types become italic with 85% foreground opacity. |
| `deprecated` | A general strikethrough overlay, with no shared foreground that would erase type distinctions. |

TypeMod pipelines start from the finished group style. For example, function
colours are darkened by 3% before their builtin/static/async transformations.
`types = { "method" }` exercises semantic aliases and applies the same typemod
rules to methods; it must not let a narrower method overwrite Vim's `Function`.

Syntax-only captures such as `keyword.directive.define`, `punctuation.bracket`
and `markup.heading.1` use typemod-owned declarations with explicit TS-only
targets. These exercise parentless typemod styles without creating artificial
LSP modifier groups. The `raw` key under `markup` is a capture name for code
spans; it is unrelated to the `hl.raw` API.

`markdown_inline` has its own language module. Markdown, render-markdown and
Vimwiki share heading colours. CodeMap/MyMarker remain typemod-only plugin
modules, while the other plugin modules use their declared Vim target policy.

## Verify

From the `cf.nvim` directory, using the provided standalone environment:

```sh
/path/to/mini-nvim/AppRun --headless -u NONE -l tests/semantic_theme_headless.lua
```

The new test checks effective Neovim styles (including valid links), semantic
aliases, distinct per-type typemods, TS-only target masks, plugin typemods,
Markdown consistency and reload/style interning. Older tests in this archive
are retained as supplied and are not the acceptance test for this theme.

`examples/showcase/semantic.lua` is a small sample for LuaLS and Tree-sitter.
Use `:Inspect` on builtin calls, parameters, fields and the deprecated method.
The actual token types/modifiers depend on the attached language server and
parser. A created highlight group alone does not prove that a server emits it.
With several simultaneous modifiers, Neovim combines the applicable highlights;
CF compile priority does not change semantic-token extmark priority.
