# fallback reference theme

Purpose: exercise **module fallback by setup identity**.

This theme intentionally has no `color.cf` and no `config.cf`, so both reserved
files fall back to the default theme. It provides only two active modules:

- `l.setup("lua", ...)`
- `p.setup("codemap", ...)`

Those identities suppress the corresponding default modules completely. Every
other language/plugin/UI identity falls back from the default theme. The Lua
module is intentionally incomplete so it is obvious that fallback is not a
per-file or per-group merge.

Use:

```vim
:CFTheme fallback
```
