-- ./AppRun --headless -u NONE -i NONE --cmd 'cd cf.nvim' -l tests/picker_ts_reverse_headless.lua
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
vim.lsp.semantic_tokens.get_at_pos = function() return {} end

local function labels_for(capture)
  vim.inspect_pos = function()
    return { treesitter = { { capture = capture } }, syntax = {} }
  end
  local items = items_at_cursor()
  local labels = {}
  for i = 1, #items do labels[i] = items[i].label end
  return labels
end

local function eq(got, expected, name)
  assert(vim.deep_equal(got, expected), name .. ": " .. vim.inspect(got))
end

-- Default TS hierarchy: the concrete capture is one editable TypeMod. Do not
-- invent standalone Type/Mod rows which are not themselves active captures.
eq(labels_for("@function.call"), {
  "TypeMod  function.call",
}, "function.call")

eq(labels_for("@variable.member"), {
  "TypeMod  variable.member",
}, "variable.member")

-- Reverse exceptions turn hierarchical TS spellings into semantic Types.
eq(labels_for("@function.method"), {
  "Type     method",
}, "function.method")

eq(labels_for("@variable.parameter"), {
  "Type     parameter",
}, "variable.parameter")

-- The heuristic continues after an exceptional Type prefix.
eq(labels_for("@function.method.call"), {
  "TypeMod  method.call",
}, "function.method.call")

eq(labels_for("@variable.parameter.builtin"), {
  "TypeMod  parameter.builtin",
}, "variable.parameter.builtin")

-- Plain captures remain plain Types.
eq(labels_for("@variable"), {
  "Type     variable",
}, "variable")

vim.lsp.semantic_tokens.get_at_pos, vim.inspect_pos = old_tokens, old_inspect
picker.stop()
print("cf.nvim picker TS reverse tests: OK")
