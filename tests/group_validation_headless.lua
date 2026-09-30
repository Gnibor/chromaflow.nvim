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
local module_path = theme_dir .. "/validation.cf"
vim.fn.mkdir(theme_dir, "p")
vim.fn.writefile({ "dark", "dark" }, root .. "/.cf-theme")
vim.fn.writefile({ "return { fg = '#aabbcc', bg = '#101018' }" }, theme_dir .. "/color.cf")
vim.fn.writefile({ "return {}" }, theme_dir .. "/config.cf")
vim.fn.writefile({
	"local hl = require('cf.hl.setup')",
	"local l = hl.language",
	"local raw = hl.raw",
	"return l.setup('lua', {",
	"  raw:group('CFValidationBefore', { bold = true }),",
	"  raw:group('CFValidationPartial', {",
	"    fg = '#334455',",
	"    typemods = {",
	"      CFValidationBroken = { not_a_highlight_field = true },",
	"      CFValidationGood = { fg = '#abcdef' },",
	"    },",
	"  }),",
	"  raw:group('CFValidationAfter', { italic = true }),",
	"  raw:group('CFValidationBadTypemods', { bold = true, typemods = 42 }),",
	"  raw:group('CFValidationBadTypes', { italic = true, types = { 'CFValidationAliasA', 42, 'CFValidationAliasB' } }),",
	"  l:group('function', {",
	"    bold = true,",
	"    style_targets = { vim = false, ts = true, lsp = false },",
	"  }),",
	"  l:group('parameter', {",
	"    not_a_highlight_field = true,",
	"    style_targets = { vim = false, ts = true, lsp = false },",
	"    typemods = { cf_independent_mod = { italic = true } },",
	"  }),",
	"  l:group('variable', {",
	"    style_targets = { vim = false, ts = true, lsp = false },",
	"    pipeline = { hl.lighten.fg(5) },",
	"    typemods = { cf_missing_mod = { fg = '#224466', pipeline = { hl.lighten.fg(5) } } },",
	"  }),",
	"})",
}, module_path)

local compiled = assert(theme.load(root))
local validation_file
for _, file in ipairs(compiled.module_files) do
	if file.name == "validation.cf" then validation_file = file break end
end
assert(validation_file, "validation module missing from compiled file list")
assert(validation_file.failed ~= true, "one invalid declaration incorrectly failed the complete module")

-- A broken nested typemod owns only its own rollback scope.
assert(runtime.group_style("CFValidationBefore") ~= nil, "declaration before broken typemod was lost")
assert(runtime.group_style("CFValidationAfter") ~= nil, "declaration after broken typemod was lost")
assert(runtime.group_style("CFValidationPartial") ~= nil, "valid group base was lost because one typemod was invalid")
assert(runtime.group_style("CFValidationGood") ~= nil, "valid typemod sibling was lost")
assert(runtime.group_style("CFValidationBroken") == nil, "invalid typemod leaked a partial action")

-- Invalid group-level structure invalidates that declaration as a unit. There is
-- no trustworthy partial meaning for a non-table typemods field or malformed types array.
assert(runtime.group_style("CFValidationBadTypemods") == nil, "invalid typemods container leaked a partial group")
assert(runtime.group_style("CFValidationBadTypes") == nil, "invalid types array leaked a partial group")
assert(next(vim.api.nvim_get_hl(0, { name = "CFValidationAliasA", link = true, create = false })) == nil, "invalid types array leaked alias A")
assert(next(vim.api.nvim_get_hl(0, { name = "CFValidationAliasB", link = true, create = false })) == nil, "invalid types array leaked alias B")

-- A style does not require a colour: pure attributes remain valid.
assert(next(vim.api.nvim_get_hl(0, { name = "@function.lua", link = false, create = false })) ~= nil, "colorless style was incorrectly rejected")

-- A broken base invalidates its complete declaration, including nested typemods.
assert(next(vim.api.nvim_get_hl(0, { name = "@parameter.lua", link = true, create = false })) == nil, "invalid base style unexpectedly materialized")
assert(next(vim.api.nvim_get_hl(0, { name = "@variable.parameter.cf_independent_mod.lua", link = true, create = false })) == nil, "typemod escaped an invalid base declaration")
assert(next(vim.api.nvim_get_hl(0, { name = "@variable.lua", link = true, create = false })) == nil, "invalid pipeline-only base unexpectedly materialized")
assert(next(vim.api.nvim_get_hl(0, { name = "@variable.cf_missing_mod.lua", link = true, create = false })) == nil, "typemod escaped an invalid pipeline base declaration")

local messages = {}
for _, record in ipairs(diagnostic.history()) do
	if record.source.file == vim.fs.normalize(module_path) and record.severity == diagnostic.severity.ERROR then
		messages[#messages + 1] = record.message
	end
end
local function has_message(fragment)
	for i = 1, #messages do if messages[i]:find(fragment, 1, true) then return true end end
	return false
end
assert(has_message("not_a_highlight_field"), "invalid highlight field did not report an ERROR")
assert(has_message("typemods must be a table"), "invalid typemods container did not report an ERROR")
assert(has_message("types entry"), "invalid types array did not report an ERROR")
assert(has_message("fg has no color to manipulate"), "invalid pipeline base did not report an ERROR")

vim.fn.delete(root, "rf")
print("cf.nvim group validation tests: OK")
