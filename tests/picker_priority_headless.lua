-- ./AppRun --headless -u NONE -i NONE --cmd 'cd cf.nvim' -l tests/picker_priority_headless.lua
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

local function labels(items)
  local out = {}
  for i = 1, #items do out[i] = items[i].label end
  return out
end

-- Neovim returns lower-priority entries first and the highest-priority entry
-- last. CFPick must therefore consume each priority-bearing source backwards.
vim.lsp.semantic_tokens.get_at_pos = function()
  return {
    { type = "variable", modifiers = { readonly = true } },
    { type = "function", modifiers = { async = true } },
  }
end
vim.inspect_pos = function()
  return {
    treesitter = {
      { capture = "@variable.documentation" },
      { capture = "@function.method" },
    },
    syntax = {
      { hl_group = "Identifier" },
      { hl_group = "Function" },
    },
  }
end

local got = labels(items_at_cursor())
assert(vim.deep_equal(got, {
  "Type     function",
  "Mod      async",
  "TypeMod  function.async",
  "Type     variable",
  "Mod      readonly",
  "TypeMod  variable.readonly",
  "Type     method",
  "TypeMod  variable.documentation",
}), "semantic priority order is not highest-first: " .. vim.inspect(got))

-- Syntax is only consulted when neither semantic source contributes.
vim.lsp.semantic_tokens.get_at_pos = function() return {} end
vim.inspect_pos = function()
  return {
    treesitter = {},
    syntax = {
      { hl_group = "Identifier" },
      { hl_group = "Function" },
    },
  }
end

local syntax_got = labels(items_at_cursor())
assert(vim.deep_equal(syntax_got, {
  "Type     Function",
  "Type     Identifier",
}), "syntax priority order is not highest-first: " .. vim.inspect(syntax_got))

vim.lsp.semantic_tokens.get_at_pos, vim.inspect_pos = old_tokens, old_inspect
picker.stop()
print("cf.nvim picker priority tests: OK")
