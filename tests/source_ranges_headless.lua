-- From the cf.nvim directory:
-- nvim --headless -u NONE -l tests/source_ranges_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local config = require("cf.config")
local hl = require("cf.hl.setup")
local picker = require("cf.picker")

config.setup({ picker = true })
picker.start()

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")

local function write(name, lines)
	local path = root .. "/" .. name
	vim.fn.writefile(lines, path)
	return path
end

local function execute(path)
	local token = hl._source_begin(path)
	local ok, result = pcall(assert(loadfile(path)))
	hl._source_end(token)
	assert(ok, result)
	return result
end

local function range_text(source)
	assert(source and source.end_line and source.end_col, "source range missing")
	local lines = vim.fn.readfile(source.file)
	local out = {}
	for row = source.line, source.end_line do
		local line = lines[row] or ""
		if source.line == source.end_line then
			out[#out + 1] = line:sub(source.col, source.end_col - 1)
		elseif row == source.line then
			out[#out + 1] = line:sub(source.col)
		elseif row == source.end_line then
			out[#out + 1] = line:sub(1, source.end_col - 1)
		else
			out[#out + 1] = line
		end
	end
	return table.concat(out, "\n")
end

hl._begin({}, {})
hl._active_begin()

local language_path = write("language.cf", {
	'local hl = require("cf.hl.setup")',
	"local l = hl.language",
	"local raw = hl.raw",
	"",
	'return l.setup("lua", {',
	'\tl:group("function", {',
	"\t\tbold = true,",
	"\t}),",
	'\tl:link("method", "function"),',
	'\traw:group("ExactGroup", {',
	"\t\titalic = true,",
	"\t}),",
	"})",
})
local language = execute(language_path)
assert(range_text(language.source) == table.concat({
	'l.setup("lua", {',
	'\tl:group("function", {',
	"\t\tbold = true,",
	"\t}),",
	'\tl:link("method", "function"),',
	'\traw:group("ExactGroup", {',
	"\t\titalic = true,",
	"\t}),",
	"})",
}, "\n"))
assert(range_text(language.declarations[1].source) == table.concat({
	'l:group("function", {',
	"\t\tbold = true,",
	"\t})",
}, "\n"))
assert(range_text(language.declarations[2].source) == 'l:link("method", "function")')
assert(range_text(language.declarations[3].source) == table.concat({
	'raw:group("ExactGroup", {',
	"\t\titalic = true,",
	"\t})",
}, "\n"))

for i = 1, #language.actions do
	assert(language.actions[i]._cf_source ~= nil, "picker compile action lost source ownership")
end

local plugin_path = write("plugin.cf", {
	'local hl = require("cf.hl.setup")',
	"local p = hl.plugin",
	"",
	'return p.setup("demo", {',
	"\tstyle_targets = { vim = true },",
	'\tp:group("DemoGroup", { bold = true }),',
	"})",
})
local plugin = execute(plugin_path)
assert(range_text(plugin.source):match('^p%.setup%('))
assert(range_text(plugin.declarations[1].source) == 'p:group("DemoGroup", { bold = true })')

local ui_path = write("ui.cf", {
	'local hl = require("cf.hl.setup")',
	"local u = hl.ui",
	"",
	"return u.setup({",
	'\tu:group("Normal", { italic = true }),',
	"})",
})
local ui = execute(ui_path)
assert(range_text(ui.source):match('^u%.setup%('))
assert(range_text(ui.declarations[1].source) == 'u:group("Normal", { italic = true })')

hl._compile_end()

local runtime_path = write("runtime.cf", {
	'local hl = require("cf.hl.setup")',
	"local r = hl.runtime",
	"",
	"return r.setup({",
	'\tr:group("focus", {',
	"\t\tbold = true,",
	"\t}),",
	"})",
})
local runtime_token = hl._runtime_begin("source-range-test")
local runtime = execute(runtime_path)
hl._runtime_end(runtime_token)
assert(range_text(runtime.source):match('^r%.setup%('))
assert(range_text(runtime.group_sources.focus) == table.concat({
	'r:group("focus", {',
	"\t\tbold = true,",
	"\t})",
}, "\n"))
assert(runtime.group_sources.focus == runtime.declarations[1].source)

config.setup({ picker = false })
picker.stop()
hl._active_begin()
local ranges_off_path = write("ranges-off.cf", {
	'local hl = require("cf.hl.setup")',
	"local l = hl.language",
	'return l.setup("go", {',
	'\tl:group("keyword", { bold = true }),',
	"})",
})
local ranges_off = execute(ranges_off_path)
hl._compile_end()
for i = 1, #ranges_off.actions do
	assert(ranges_off.actions[i]._cf_source == nil, "picker source metadata leaked into picker=false compile")
end
assert(ranges_off.declarations[1].source.line == 4)
assert(ranges_off.declarations[1].source.end_line == nil and ranges_off.declarations[1].source.end_col == nil)
config.setup({ picker = true })
picker.start()

-- Full ranges are optional. Without a Lua Tree-sitter parser, the old start
-- source survives and compilation remains usable; only end_line/end_col vanish.
local no_ts_path = write("no-ts.cf", {
	'local hl = require("cf.hl.setup")',
	"local l = hl.language",
	"return l.setup(\"python\", {",
	'\tl:group("keyword", { bold = true }),',
	"})",
})
local original_get_string_parser = vim.treesitter.get_string_parser
vim.treesitter.get_string_parser = function()
	error("simulated missing parser")
end
hl._active_begin()
local no_ts = execute(no_ts_path)
hl._compile_end()
vim.treesitter.get_string_parser = original_get_string_parser
assert(no_ts.declarations[1].source.file == vim.fs.normalize(no_ts_path))
assert(no_ts.declarations[1].source.line == 4)
assert(no_ts.declarations[1].source.end_line == nil and no_ts.declarations[1].source.end_col == nil)

picker.stop()
vim.fn.delete(root, "rf")
print("cf.nvim source ranges: OK")
