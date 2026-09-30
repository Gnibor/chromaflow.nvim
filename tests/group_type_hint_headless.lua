vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cf = require("cf")
local diagnostic = require("cf.diagnostic")
local theme = require("cf.theme")

assert(vim.fn.hlexists("Normal") == 1, "test requires the builtin Normal group")
assert(vim.fn.hlexists("TermCursorNC") == 0, "test requires TermCursorNC to be absent before the theme")

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/dark", "p")

vim.fn.writefile({ "dark", "dark" }, root .. "/.cf-theme")
vim.fn.writefile({ "return { fg = '#d0d0d0', bg = '#101018' }" }, root .. "/dark/color.cf")
vim.fn.writefile({ "return {}" }, root .. "/dark/config.cf")
vim.fn.writefile({
	"local hl = require('cf.hl.setup')",
	"local u = hl.ui",
	"return u.setup({",
	"  u:group('Normal', { bold = true, typemods = { CFNoSuchTypeMod = { italic = true } } }),",
	"  u:group('TermCursorNC', { italic = true }),",
	"})",
}, root .. "/dark/types.cf")

diagnostic.clear()
cf.setup({
	theme_path = root,
	watch = false,
	lineblend = { autostart = false },
	diagnostic = {
		color_trace = false,
		severity = { hint = true, warn = false, error = true },
		messages = { info = false, ok = false },
	},
})

assert(theme.current() ~= nil)
assert(vim.fn.hlexists("TermCursorNC") == 1, "unresolved type was not materialized")

local records = diagnostic.history()
local hints = {}
for i = 1, #records do
	if records[i].severity == diagnostic.severity.HINT then
		hints[#hints + 1] = records[i]
	end
end

assert(#hints == 1, "expected exactly one type fallback hint, got " .. #hints)
assert(hints[1].message == 'type "TermCursorNC" uses literal fallback')
assert(hints[1].source.file:match("types%.cf$"))
assert(not hints[1].message:find("typemod", 1, true), "typemod existence leaked into type-only hints")

vim.fn.delete(root, "rf")
print("cf.nvim group type hint tests: OK")
