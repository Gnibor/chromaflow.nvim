-- From the cf.nvim directory:
-- /path/to/mini-nvim/AppRun --headless -u NONE -l tests/semantic_theme_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")
local theme = require("cf.theme")
local runtime = require("cf.hl.runtime")
local color = require("cf.color")
local root = vim.fs.joinpath(vim.fn.getcwd(), "examples", "themes")
local compiled = theme.load(root)
local c = compiled.colors
local function rgb(value) return tonumber(color.to_rgb_hex(value):sub(2), 16) end
local function style(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end
local function eq(actual, expected, label)
	assert(vim.deep_equal(actual, expected), label .. ": " .. vim.inspect(actual) .. " != " .. vim.inspect(expected))
end
local function fg(name, value) eq(style(name).fg, rgb(value), name .. ".fg") end
local actions, typemods = 0, 0
for _, module in ipairs(compiled.modules) do
	for _, action in ipairs(module.actions) do
		actions = actions + 1
		assert(not action.kind:match("^raw_"), "theme bypasses resolver: " .. action.kind)
		if action.kind == "resolver_style" and action.typemod_style then typemods = typemods + 1 end
		if action.typemod and (action.typemod:find("%.") or action.type_name == "punctuation" or action.type_name == "markup") then
			assert(action.targets.ts and not action.targets.vim and not action.targets.lsp, "TS syntax leaked into other target systems")
		end
	end
end
assert(typemods > 100, "theme does not exercise owned typemod styles")
local function_base = color.darken(c.func, 3)
local function_builtin = color.mix(22, c.yellow, function_base)
local variable_builtin = color.mix(24, c.builtin, c.variable)
local type_builtin = color.mix(25, c.builtin, c.type)
assert(function_builtin ~= variable_builtin and variable_builtin ~= type_builtin)
for _, language in ipairs({ "", "lua", "c", "cpp", "python", "arduino" }) do
	local suffix = language == "" and "" or "." .. language
	fg("@function" .. suffix, function_base)
	fg("@function.builtin" .. suffix, function_builtin)
	fg("@lsp.typemod.function.defaultLibrary" .. suffix, function_builtin)
	fg("@function.method.builtin" .. suffix, function_builtin)
	fg("@lsp.typemod.method.defaultLibrary" .. suffix, function_builtin)
	fg("@variable.builtin" .. suffix, variable_builtin)
	fg("@lsp.typemod.variable.defaultLibrary" .. suffix, variable_builtin)
	fg("@type.builtin" .. suffix, type_builtin)
	fg("@lsp.typemod.type.defaultLibrary" .. suffix, type_builtin)
	fg("@lsp.typemod.variable.readonly" .. suffix, color.mix(45, c.constant, c.variable))
	fg("@lsp.typemod.property.readonly" .. suffix, color.mix(24, c.constant, c.property))
	fg("@lsp.typemod.parameter.readonly" .. suffix, color.mix(18, c.constant, c.parameter))
	eq(style("@lsp.typemod.parameter.readonly" .. suffix).italic, true, "readonly parameter")
	eq(style("@lsp.typemod.variable.readonly" .. suffix).bg, rgb((color.opacity(c.constant, 5, c.bg))), "readonly variable background")
	assert(style("@lsp.typemod.property.readonly" .. suffix).bg == nil, "readonly property acquired variable background")
	fg("@lsp.typemod.function.static" .. suffix, color.mix(16, c.constant, function_base))
	fg("@lsp.typemod.variable.static" .. suffix, color.mix(12, c.type, c.variable))
	eq(style("@lsp.typemod.function.async" .. suffix).italic, true, "async function")
	local deprecated = style("@lsp.mod.deprecated" .. suffix)
	assert(deprecated.strikethrough and deprecated.fg == nil and deprecated.bg == nil, "deprecated overlay overwrote type colours")
end
-- Narrow method/parameter declarations must not overwrite the broad Vim anchors.
fg("Function", function_base)
fg("Identifier", c.variable)
fg("@keyword.directive.define.c", c.keyword)
assert(style("@keyword.directive.define.c").bold)
fg("@variable.member.lua", c.property)
fg("@CodeMap.keyword", c.keyword)
fg("@MyMarker.entry", c.comment)
assert(runtime.group_style("@CodeMap") == nil, "typemod-only plugin materialized a base style")
for i = 1, 6 do
	eq(style("@markup.heading." .. i .. ".markdown").fg, style("RenderMarkdownH" .. i).fg, "rendered Markdown heading " .. i)
	eq(style("VimwikiHeader" .. i).fg, style("RenderMarkdownH" .. i).fg, "Vimwiki heading " .. i)
end
assert(style("@markup.strong.markdown_inline").bold)
assert(style("@markup.italic.markdown_inline").italic)
fg("@markup.link.label.markdown_inline", c.type)
-- Real Neovim links are valid styles: compare effective highlights, not only
-- the runtime's direct-materialization index (unlike the obsolete old test).
local names = { "Normal", "Function", "@function.builtin.lua", "@lsp.typemod.variable.readonly.lua", "@CodeMap.keyword", "RenderMarkdownCode" }
local before = {}
for _, name in ipairs(names) do before[name] = style(name) end
local function find_style(t)
	for _, module in ipairs(t.modules) do
		if module.kind == "language" and module.name == "lua" then
			for _, action in ipairs(module.actions) do
				if action.kind == "resolver_style" and action.type_name == "function" and action.typemod == "builtin" then return action.style end
			end
		end
	end
end
local interned = assert(find_style(compiled))
compiled = theme.load(root)
assert(find_style(compiled) == interned, "reload lost session style interning")
for _, name in ipairs(names) do eq(style(name), before[name], "reload " .. name) end
print(("Semantic theme: %d modules, %d actions, %d owned typemods; targets, styles and reload OK"):format(#compiled.modules, actions, typemods))
