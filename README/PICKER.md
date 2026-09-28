# Picker and CFSave

The picker is an optional authoring/editor layer. Enable it explicitly:

```lua
require("cf").setup({
    theme_path = "/path/to/themes",
    picker = true,
})
```

This enables `:CFPick`, `:CFSave`, exact DSL source-range tracking and the colour
trace/cache needed to persist edits. With `picker=false`, that infrastructure is
not kept alive.

## `:CFPick`

`:CFPick` inspects the highlight axes under the cursor and maps existing concrete
Vim/Tree-sitter/LSP groups back to ChromaFlow semantic targets. The picker does
not create another resolver path; it reuses the compiled resolver/runtime state
and keeps discovery/editor caches local to the picker feature.

The main picker can descend into:

```text
Edit
├── Pipeline
├── Style
└── TypeMods   (when the selected rule can own TypeMods)
```

Picker edits use the same sparse runtime layer as normal runtime actions, so
preview does not modify the normal theme cache.

## General menu controls

Common menu controls:

```text
j / Down      next item
k / Up        previous item
Enter         open/select
Backspace     back
q / Esc       cancel/close
```

Where a menu exposes tri-state style fields:

```text
=             set/mark true
x             set/mark false
Space         unset
```

Numeric fields use:

```text
- / +         adjust by 1
Alt-- / Alt-+ adjust by 10
Space         unset
```

## Style editor

The Style editor works on ChromaFlow's complete highlight style state and can
preview direct field changes live. `unset`, `true` and `false` remain distinct,
which matters for boolean `nvim_set_hl()` fields and for numeric `blend`.

Changes are staged as picker edits; they do not touch source files until
`:CFSave`.

## TypeMods

For a selected Type, the picker lists TypeMods that actually exist for that
Type/filetype in the current session. It does not enumerate every theoretical
modifier combination.

The editor preserves ChromaFlow's ownership model:

```text
TypeMod = true
    reuse the finished Type style

TypeMod = { ... }
    concrete Type+TypeMod owns its style

TypeMod = false
    semantic clear
```

When a Mod/TypeMod rule is missing but has an unambiguous owning module, picker
edits can create the corresponding source entry instead of inventing a separate
runtime-only semantic rule.

## Pipeline editor

The Pipeline editor is a five-channel view:

```text
1 FG
2 BG
3 SP
4 CFG
5 CBG
```

`CFG`/`CBG` edit `ctermfg`/`ctermbg`. When no explicit terminal channel exists,
CFG/CBG show their inherited FG/BG fallback.

Controls:

```text
h / Left      previous channel
l / Right     next channel
1..5          jump to channel
j / Down      next operation
k / Up        previous operation
Enter         choose base colour / edit mix colour / insert at "new"
n             insert an operation
d             delete selected operation
- / +         adjust value by 1
Alt-- / Alt-+ adjust value by 10
a             accept draft
Backspace     discard and return to previous picker menu
q / Esc       discard and close
```

Available operations:

```text
mix
opacity
brightness
lighten
darken
shiftHue
gamma
```

Picker value ranges are intentionally canonical/effective ranges:

```text
mix / opacity / lighten / darken   0..100
brightness                         -100..100
shiftHue                           -180..180
gamma                              0.01..100
```

Gamma is displayed in hundredths in the compact cell (`110` means `1.10`).
`+/-` changes it by `0.01`; Alt adjustment changes it by `0.10`.

The editor preserves the global operation order even though operations are shown
per channel. Inserting/editing a pipeline uses the real ChromaFlow pipeline
executor for preview; it does not reimplement colour math.

The base/`mix` colour picker reads the complete active `color.cf` table,
including nested palette keys.

## `:CFSave`

`:CFSave` turns confirmed picker deltas into source edits, then uses the normal
full theme reload. It is deliberately a cold-path source editor rather than a
second theme representation.

The save process:

```text
collect confirmed picker edits
-> read owning source files
-> verify pipeline/source snapshots are still current
-> rewrite only affected fields/rules/pipelines
-> parse generated source with the Lua Tree-sitter parser
-> validate generated Lua with loadstring()
-> stage temporary files
-> atomically replace the originals
-> normal ChromaFlow reload
```

If a file changed on disk after the pipeline editor opened, save refuses to
overwrite it. No partial source write is performed before the full plan has been
built and validated.

The Lua Tree-sitter parser is therefore required for source persistence. Normal
ChromaFlow theme compilation itself can still operate without full source-range
metadata.

## Pipeline persistence rules

The source editor is intentionally conservative. It edits literal pipeline
tables made from the standard ChromaFlow colour operations. Unchanged expressions
are retained; edited arguments are rewritten and newly selected palette colours
remain `c.*` references.

Computed pipeline tables, arbitrary callbacks and linked-style ownership are not
silently rewritten into a guessed form. If a style is linked, edit the owning
style instead.

Standalone/inter-operation comments are preserved when possible; if a pipeline's
structure must be rebuilt, collected comments stay with the rewritten pipeline
rather than being silently discarded.

## LineBlend interaction

When the Pipeline editor opens, an active LineBlend overlay is temporarily
stopped so it cannot obscure live colour preview. It is reactivated when the
editor closes.
