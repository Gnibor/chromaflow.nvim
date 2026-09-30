vim.opt.runtimepath:prepend(vim.fn.getcwd())

require("cf")
local diagnostic = require("cf.diagnostic")
local runtime = require("cf.hl.runtime")
local theme = require("cf.theme")

assert(diagnostic.configure({
	severity_bias = 0,
	severity = { hint = true, warn = true, error = true },
}))
diagnostic.clear()

local root = vim.fn.tempname()
local theme_dir = root .. "/dark"
local module_path = theme_dir .. "/typemod-rollback.cf"
vim.fn.mkdir(theme_dir, "p")
vim.fn.writefile({ "dark", "dark" }, root .. "/.cf-theme")
vim.fn.writefile({ "return { fg = '#aabbcc', bg = '#101018' }" }, theme_dir .. "/color.cf")
vim.fn.writefile({ "return {}" }, theme_dir .. "/config.cf")
vim.fn.writefile({
	"local hl = require('cf.hl.setup')",
	"local l = hl.language",
	"local raw = hl.raw",
	"return l.setup('lua', {",
	"  raw:group('CFTypemodRollbackRaw', {",
	"    fg = '#334455',",
	"    typemods = {",
	"      CFTypemodRollbackRawBroken = { not_a_highlight_field = true },",
	"      CFTypemodRollbackRawGood = { fg = '#abcdef' },",
	"    },",
	"  }),",
	"  l:group('function', {",
	"    fg = '#334455',",
	"    style_targets = { vim = false, ts = true, lsp = false },",
	"    typemods = {",
	"      cf_rollback_broken = { not_a_highlight_field = true },",
	"      cf_rollback_good = { fg = '#abcdef' },",
	"    },",
	"  }),",
	"})",
}, module_path)

local compiled = assert(theme.load(root))
local rollback_file
for _, file in ipairs(compiled.module_files) do
	if file.name == "typemod-rollback.cf" then
		rollback_file = file
		break
	end
end
assert(rollback_file, "typemod rollback module missing from compiled file list")
assert(rollback_file.failed ~= true, "invalid typemod still failed the complete module")

assert(runtime.group_style("CFTypemodRollbackRaw") ~= nil, "raw group base was rolled back with invalid typemod")
assert(runtime.group_style("CFTypemodRollbackRawGood") ~= nil, "valid raw typemod sibling was rolled back")
assert(runtime.group_style("CFTypemodRollbackRawBroken") == nil, "invalid raw typemod leaked an action")

assert(runtime.group_style("@function.lua") ~= nil, "resolved group base was rolled back with invalid typemod")
assert(runtime.group_style("@function.cf_rollback_good.lua") ~= nil, "valid resolved typemod sibling was rolled back")
assert(runtime.group_style("@function.cf_rollback_broken.lua") == nil, "invalid resolved typemod leaked an action")

local errors = 0
for _, record in ipairs(diagnostic.history()) do
	if record.source.file == vim.fs.normalize(module_path)
		and record.severity == diagnostic.severity.ERROR
		and record.message:find("not_a_highlight_field", 1, true)
	then
		errors = errors + 1
	end
end
assert(errors == 2, "expected one ERROR per invalid typemod, got " .. errors)

vim.fn.delete(root, "rf")
print("cf.nvim typemod rollback tests: OK")
