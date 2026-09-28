# Heading 1

Normal text, **bold**, *italic*, ***bold italic***, ~~strikethrough~~, and `inline_code()`.

## Heading 2

[inline link](https://example.com) · <https://example.com> · ![image alt](https://example.com/image.png)

> Blockquote with **bold** and `code`.

### Heading 3

- unordered item
  - nested item
    - deeply nested item
- [x] done task
- [ ] open task

1. ordered item
2. second item
   1. nested ordered item

#### Heading 4

| left | center | right |
| :--- | :----: | ----: |
| `one` | **two** | *three* |

---

##### Heading 5

```lua
local value = string.upper("lua")
```

```c
int value = 42;
```

```python
value = f"{42}"
```

```bash
printf '%s\n' "shell"
```

###### Heading 6

Escaped \*asterisks\*, \[brackets\], \# hash, and <kbd>Ctrl</kbd> + <kbd>K</kbd>.

[reference link][theme] and a footnote reference.[^note]

<details>
<summary>HTML block</summary>

Inline <em>HTML</em> remains directly comparable to Markdown emphasis.
</details>

[theme]: https://example.com/theme "reference title"
[^note]: Footnote syntax, when the Markdown parser supports it.
