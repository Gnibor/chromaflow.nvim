vim.opt.runtimepath:prepend(vim.fn.getcwd())

require("cf")
local diagnostic = require("cf.diagnostic")
local runtime = require("cf.hl.runtime")
local theme = require("cf.theme")

assert(diagnostic.configure({
	debug = false,
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
	"    typemods = {",
	"      cf_independent_mod = { italic = true },",
	"    },",
	"  }),",
	"  l:group('variable', {",
	"    style_targets = { vim = false, ts = true, lsp = false },",
	"    pipeline = { hl.lighten.fg(5) },",
	"    typemods = {",
	"      cf_missing_mod = { fg = '#224466', pipeline = { hl.lighten.fg(5) } },",
	"    },",
	"  }),",
	"})",
}, module_path)

local compiled = assert(theme.load(root))
local validation_file
for _, file in ipairs(compiled.module_files) do
	if file.name == "validation.cf" then
		validation_file = file
		break
	end
end
assert(validation_file, "validation module missing from compiled file list")
assert(validation_file.failed ~= true, "local group validation still failed the complete module")

assert(runtime.group_style("CFValidationBefore") ~= nil, "declaration before invalid typemod was lost")
assert(runtime.group_style("CFValidationAfter") ~= nil, "declaration after invalid typemod was lost")
assert(runtime.group_style("CFValidationPartial") ~= nil, "valid group base was lost because one typemod was invalid")
assert(runtime.group_style("CFValidationGood") ~= nil, "valid typemod sibling was lost")
assert(runtime.group_style("CFValidationBroken") == nil, "invalid typemod leaked a partial action")
assert(runtime.group_style("CFValidationBadTypemods") ~= nil, "invalid typemods field incorrectly discarded the valid base")
assert(runtime.group_style("CFValidationBadTypes") ~= nil, "invalid types alias incorrectly discarded the primary group")
assert(vim.api.nvim_get_hl(0, { name = "CFValidationAliasA", link = true, create = false }).link == "CFValidationBadTypes", "valid types alias before an invalid alias was lost")
assert(vim.api.nvim_get_hl(0, { name = "CFValidationAliasB", link = true, create = false }).link == "CFValidationBadTypes", "valid types alias after an invalid alias was lost")
assert(runtime.group_style("@function.lua") ~= nil, "style without a color was incorrectly rejected")
assert(runtime.group_style("@parameter.lua") == nil, "invalid base style unexpectedly materialized")
assert(next(vim.api.nvim_get_hl(0, { name = "@variable.parameter.cf_independent_mod.lua", link = true, create = false })) ~= nil, "independent colorless typemod was lost with an invalid base")

-- Missing colour is not a group error. Only this concrete pipeline operation is
-- invalid because it asks to manipulate fg when neither the group nor an
-- inherited style provides fg. The independent typemod still survives because
-- a typemod carrying its own fg+pipeline is independent and must still survive.
assert(runtime.group_style("@variable.lua") == nil, "invalid pipeline-only base unexpectedly materialized")
assert(runtime.group_style("@variable.cf_missing_mod.lua") ~= nil, "independent unresolved typemod was not materialized")

local bad_typemod_error
local missing_base_error
local unresolved_hint
for _, record in ipairs(diagnostic.history()) do
	if record.source.file == vim.fs.normalize(module_path) then
		if record.severity == diagnostic.severity.ERROR
			and record.source.line == 6
			and record.message:find("not_a_highlight_field", 1, true)
		then
			bad_typemod_error = record
		elseif record.severity == diagnostic.severity.ERROR
			and record.message:find("fg has no color to manipulate", 1, true)
		then
			missing_base_error = record
		elseif record.severity == diagnostic.severity.HINT
			and record.message:find("cf_missing_mod", 1, true)
			and record.message:find("literal fallback", 1, true)
		then
			unresolved_hint = record
		end
	end
end

assert(bad_typemod_error, "invalid typemod did not enqueue an ERROR diagnostic")
assert(bad_typemod_error.source.line == 6, "invalid typemod diagnostic lost the group source line")
assert(missing_base_error, "pipeline operation without its required colour did not enqueue an ERROR diagnostic")
assert(unresolved_hint, "unresolved typemod did not enqueue a HINT diagnostic")
assert(not vim.tbl_contains(unresolved_hint.tags, diagnostic.tag.UNNECESSARY), "unresolved literal hint was incorrectly tagged UNNECESSARY")

vim.fn.delete(root, "rf")
print("cf.nvim group validation tests: OK")
