# palette reference theme

Purpose: exercise **reserved-file override + complete module fallback**.

The active theme contains only `color.cf`. It has no modules and no
`config.cf`. Therefore:

- palette comes from `palette/color.cf`;
- config falls back to the default theme;
- every language/plugin/UI module falls back to the default theme;
- those fallback modules all see the active palette table.

This is useful for proving that module fallback does not pin default-theme
colors.

Use:

```vim
:CFTheme palette
```
