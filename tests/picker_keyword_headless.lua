vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")
require("cf.config").setup({ picker = true })
local picker, menu = require("cf.picker"), require("cf.menu")
local theme = require("cf.theme")
picker.start()
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/dark", "p")
vim.fn.writefile({ "dark", "dark" }, root .. "/.cf-theme")
vim.fn.writefile({ 'return { fg = "#abcdef" }' }, root .. "/dark/color.cf")
vim.fn.writefile({
  'local l = require("cf.hl.setup").language',
  'return l.setup("lua", {',
  ' l:group("keyword", { fg = "#abcdef" }),',
  ' l:group("keyword", { style_targets = { vim = false, ts = true, lsp = false },',
  '   typemods = { ["function"] = { bold = true }, ["return"] = { italic = true }, ["operator"] = { underline = true } },',
  ' }),',
  '})',
}, root .. "/dark/lua.cf")
theme.load(vim.g.cf_keyword_example and (vim.fn.getcwd() .. "/examples/themes") or root)
vim.bo.filetype = "lua"
if not vim.g.cf_keyword_example then
  for _, name in ipairs({ "function", "return", "operator" }) do
    vim.api.nvim_set_hl(0, "@keyword." .. name .. ".lua", { fg = 0xabcdef })
  end
end
local old_open, old_inspect, old_tokens = menu.open, vim.inspect_pos, vim.lsp.semantic_tokens.get_at_pos
local current
menu.open = function(opts) current = opts; return old_open(opts) end
vim.inspect_pos = function() return { treesitter = { { capture = "keyword" } }, syntax = {} } end
vim.lsp.semantic_tokens.get_at_pos = function() return {} end
local function key(k) vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "mx", false) end
picker.open()
key("<CR>")
assert(current.items[3] == "TypeMods")
key("jj<CR>")
assert(current.title == " TypeMods: keyword ")
local rows = {}
for i, label in ipairs(current.items) do rows[label:match("^...([^ ]+)")] = { index = i, label = label } end
assert(rows["function"] and rows.operator and rows["return"], "keyword TypeMods missing: " .. vim.inspect(current.items))
assert(rows["return"].label:find("group: Style", 1, true), "return incorrectly labelled empty")
for _ = 2, rows["return"].index do key("j") end
key("<CR>")
assert(current.title == " Edit: keyword.return ")
key("j<CR>")
assert(current.title == " Styles: keyword.return ")
key("<BS>")
assert(current.title == " Edit: keyword.return ")
key("<BS>")
assert(current.title == " TypeMods: keyword ")
key("<BS>")
assert(current.title == " Edit: keyword " and current.items[3] == "TypeMods", "Type menu lost TypeMods after return")
if not vim.g.cf_keyword_example then
  key("jj<CR>")
  for _ = 2, rows["return"].index do key("j") end
  key("x")
  local plan = require("cf.save").plan()
  assert(#plan.files == 1)
  local output = plan.files[1].content
  assert(output:find('l:group("keyword", { fg = "#abcdef" }),', 1, true), "rule changed the base declaration")
  assert(output:find('["return"] = false', 1, true), "rule missed the TypeMod declaration")
  assert(loadstring(output), "rule produced invalid Lua")
end
menu.close()
menu.open, vim.inspect_pos, vim.lsp.semantic_tokens.get_at_pos = old_open, old_inspect, old_tokens
picker.stop()
vim.fn.delete(root, "rf")
print("cf.nvim keyword TypeMods navigation tests: OK")
