# ChromaFlow reference themes

The bundled root intentionally contains several themes with different jobs.
`dark` is the complete integration theme and default fallback. The others are
small test fixtures built to stress selection/fallback rules without duplicating
the full theme.

| Theme | Purpose |
| --- | --- |
| `dark` | Full integration/reference theme. |
| `fallback` | Partial active modules; verifies fallback by `setup()` identity. |
| `palette` | Active `color.cf` only; verifies reserved palette override while all modules fall back. |
| `ts-only` | Active `config.cf` only; verifies `only_style_target`, target boundaries and global clears. |

Switch at runtime with:

```vim
:CFTheme fallback
:CFTheme palette
:CFTheme ts-only
:CFTheme dark
```

The optional flag also replaces the default/fallback line in `.cf-theme`:

```vim
:CFTheme dark default=true
```

## Shared runtime modules

`runtime/` is reserved for theme-aware runtime `.cf` modules. It is not a theme
directory. Runtime lookup uses active theme -> this shared root -> default theme,
with the first matching module winning. The bundled `runtime/mystyleactions.cf`
is a small reference module for `apply()`/`replace()` experiments.

The bundled `runtime/lsd.cf` plus `examples/showcase/lsd.lua` demonstrate the
normal Lua integration path with a timed runtime colour fade. The portable dev
config sources the showcase script, so `:LSD` toggles the effect on the Lua
semantic types.
