vim.opt.runtimepath:prepend(vim.fn.getcwd())
local native = require("cf.completion.native")
local bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_buf_set_name(bufnr, "/tmp/cf-native-completion-probe.cf")
vim.bo[bufnr].filetype = "lua"
vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
vim.wo.virtualedit = "all" -- Place the cursor after the final character in headless Normal mode.

local function complete(lines, row, base)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, { row, #lines[row] })
	local start = native.complete(1, base or "")
	local result = native.complete(0, base or "")
	return start, result.words
end

native.setup({ autocomplete = true })
assert(vim.bo[bufnr].completefunc == "v:lua.require'cf.completion.native'.complete")
assert(vim.bo[bufnr].omnifunc == "v:lua.vim.lsp.omnifunc", "omnifunc was overwritten")
assert(vim.bo[bufnr].complete:match("^F,"), "completefunc source was not enabled")
assert(vim.bo[bufnr].autocomplete, "autocomplete was not enabled")
native.setup({ autocomplete = true })
assert(select(2, vim.bo[bufnr].complete:gsub("F", "")) == 1, "duplicate completefunc source")

local start, items = complete({
	"local l = hl.language",
	"return l.setup('lua', {",
	"  ",
	"})",
}, 3)
assert(start == 2 and #items == 0, vim.inspect(items))

start, items = complete({
	"local l = hl.language",
	"return l.setup('lua', {",
	"  gr",
	"})",
}, 3, "gr")
assert(start == 2 and #items == 1 and items[1].abbr == "group", vim.inspect(items))
assert(items[1].word == 'l:group("name", {}),' and items[1].equal == 1)

local original_complete, calls = native.complete, 0
native.complete = function(...)
	calls = calls + 1
	return original_complete(...)
end
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("A<C-x><C-u>", true, false, true), "xt", false)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "xt", false)
native.complete = original_complete
assert(calls >= 2, "<C-x><C-u> did not call the native completefunc")

_, items = complete({
	"local l = hl.language",
	"local raw = hl.raw",
	"return l.setup('lua', {",
	"  raw",
	"})",
}, 4, "raw")
assert(#items == 2 and items[1].word == 'raw:group("name", {}),', vim.inspect(items))

_, items = complete({
	"local r = hl.runtime",
	"return r.setup({",
	"  gr",
	"})",
}, 3, "gr")
assert(#items == 1 and items[1].abbr == "group", vim.inspect(items))

_, items = complete({
	"local l = hl.language",
	"return l.setup('lua', {",
	"  l:group('foo', {",
	"    fg",
	"  }),",
	"})",
}, 4, "fg")
assert(#items == 0, "declarations leaked into a style table")

local ordinary = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(ordinary, "/tmp/cf-native-completion-probe.lua")
vim.api.nvim_set_current_buf(ordinary)
assert(vim.bo[ordinary].completefunc == "", "native completion attached to ordinary Lua")
assert(vim.bo[ordinary].complete:find("F", 1, true) == nil, "F source attached to ordinary Lua")

native.setup()
local manual = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(manual, "/tmp/cf-native-completion-manual.cf")
vim.api.nvim_set_current_buf(manual)
assert(vim.bo[manual].completefunc == "v:lua.require'cf.completion.native'.complete")
assert(vim.bo[manual].complete:find("F", 1, true) == nil, "manual setup enabled automatic completion")
assert(not vim.bo[manual].autocomplete, "manual setup enabled autocomplete")

print("cf.nvim native completion: OK")
