vim.opt.runtimepath:prepend(vim.fn.getcwd())
local completion = require("cf.completion.cmp")
local source = completion.new()
local bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_buf_set_name(bufnr, "/tmp/cf-completion-probe.cf")
vim.bo[bufnr].filetype = "lua"

local function complete(lines, row)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	local items
	source:complete({ context = {
		bufnr = bufnr,
		cursor = { row = row, col = #lines[row] + 1 },
	} }, function(result) items = result.items end)
	return items
end

local blank = complete({
	"local l = hl.language",
	"return l.setup('lua', {",
	"  ",
	"})",
}, 3)
assert(#blank == 0, "cf completion modified a whitespace-only declaration line")

local language = complete({
	"local l = hl.language",
	"return l.setup('lua', {",
	"  gr",
	"})",
}, 3)
assert(#language == 2 and language[1].label == "group" and language[2].label == "link", vim.inspect(language))
assert(language[1].insertText:find("l:group", 1, true))

local with_raw = complete({
	"local l = hl.language",
	"local raw = hl.raw",
	"return l.setup('lua', {",
	"  raw",
	"})",
}, 4)
assert(#with_raw == 4 and with_raw[3].insertText:find("raw:group", 1, true))

local plugin = complete({
	"local p = hl.plugin",
	"return p.setup('foo', {",
	"  p",
	"})",
}, 3)
assert(#plugin == 2 and plugin[1].insertText:find("p:group", 1, true))

local ui = complete({
	"local u = hl.ui",
	"return u.setup({",
	"  u",
	"})",
}, 3)
assert(#ui == 2 and ui[2].insertText:find("u:link", 1, true))

local runtime = complete({
	"local r = hl.runtime",
	"return r.setup({",
	"  r",
	"})",
}, 3)
assert(#runtime == 1 and runtime[1].label == "group")

local nested = complete({
	"local l = hl.language",
	"return l.setup('lua', {",
	"  l:group('foo', {",
	"    fg",
	"  }),",
	"})",
}, 4)
assert(#nested == 0, "declaration snippets leaked into a style table")

local entry = { get_completion_item = function() return { label = "setup(language, spec)" } end }
local filter = completion.lsp_entry_filter(function() return true end)
local context = { bufnr = bufnr, cursor = { row = 4 }, cursor_before_line = "l:" }
assert(not filter(entry, context), "invalid colon setup was not filtered")
for _, pair in ipairs({ { "p", "plugin" }, { "u", "ui" }, { "r", "runtime" } }) do
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
		"local " .. pair[1] .. " = hl." .. pair[2],
		"return " .. pair[1] .. ".setup({",
		"  ",
		"})",
	})
	context.cursor_before_line = pair[1] .. ":"
	assert(not filter(entry, context), pair[1] .. ":setup was not filtered")
end
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local l = hl.language", "return l.setup('lua', {", "  ", "})" })
context.cursor_before_line = "l."
assert(filter(entry, context), "valid dot setup was filtered")
context.cursor_before_line = "other:"
assert(filter(entry, context), "unrelated setup method was filtered")
assert(not completion.lsp_entry_filter(function() return false end)(entry, context), "previous filter was ignored")

vim.api.nvim_buf_set_name(bufnr, "/tmp/cf-completion-probe.lua")
assert(not source:is_available(), "source was enabled for normal Lua files")
assert(#complete({ "local l = hl.language", "return l.setup('lua', {", "  ", "})" }, 3) == 0)
assert(filter(entry, { bufnr = bufnr, cursor = { row = 4 }, cursor_before_line = "l:" }))

print("cf.nvim completion: OK")
