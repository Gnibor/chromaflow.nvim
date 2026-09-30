-- ./AppRun --headless -u NONE -i NONE --cmd 'cd cf.nvim' -l tests/picker_cursor_sources_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")
local picker = require("cf.picker")
require("cf.config").setup({ picker = true })
picker.start()

local function up(fn, name)
  for i = 1, 100 do
    local key, value = debug.getupvalue(fn, i)
    if key == name then return value end
    if not key then break end
  end
  error("missing upvalue " .. name)
end

local items_at_cursor = up(picker.open, "items_at_cursor")
local old_tokens, old_inspect = vim.lsp.semantic_tokens.get_at_pos, vim.inspect_pos

vim.lsp.semantic_tokens.get_at_pos = function()
  return { { type = "variable", modifiers = { readonly = true } } }
end
vim.inspect_pos = function()
  return {
    treesitter = { { capture = "@variable.documentation" } },
    syntax = {},
  }
end

local items = items_at_cursor()
local labels = {}
for i = 1, #items do labels[i] = items[i].label end
assert(vim.deep_equal(labels, {
  "Type     variable",
  "Mod      readonly",
  "TypeMod  variable.readonly",
  "TypeMod  variable.documentation",
}), "cursor picker did not combine LSP + Tree-sitter: " .. vim.inspect(labels))

vim.lsp.semantic_tokens.get_at_pos, vim.inspect_pos = old_tokens, old_inspect
picker.stop()
print("cf.nvim picker cursor source tests: OK")
