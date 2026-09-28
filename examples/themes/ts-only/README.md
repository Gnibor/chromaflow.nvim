# ts-only reference theme

Purpose: exercise **reserved config override, hard target boundaries and global
clear behavior**.

The active theme contains only `config.cf`; palette and every module fall back
to the default theme. `only_style_target = "ts"` disables Vim/LSP writes and
requests their global clear path while keeping Tree-sitter enabled.

Use:

```vim
:CFTheme ts-only
```

Switch back with `:CFTheme dark`. Use `:CFTheme dark default=true` if you also
want to make `dark` the persisted fallback/default theme.
