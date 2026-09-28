vim.opt.runtimepath:prepend(vim.fn.getcwd())

local api = vim.api
local diagnostic = require("cf.diagnostic")
local hl = require("cf.hl.setup")
local debug_feature = require("cf.debug")
local theme = require("cf.theme")

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/default", "p")
vim.fn.mkdir(root .. "/active", "p")

local function write(path, lines)
	vim.fn.writefile(type(lines) == "table" and lines or vim.split(lines, "\n", { plain = true }), path)
end

write(root .. "/.cf-theme", { "default", "active" })
write(root .. "/default/color.cf", {
	"return { bg = '#101010', fg = '#d0d0d0' }",
})
write(root .. "/active/color.cf", {
	"return { bg = '#101010', fg = '#d0d0d0' }",
})

local visible_path = root .. "/active/visible.cf"
local hidden_path = root .. "/active/hidden.cf"
local pipeline_line = "\t\tpipeline = {    hl.brightness.fg(10),   hl.opacity.fg(50) },"
write(visible_path, {
	"local hl = require('cf.hl.setup')",
	"local r = hl.ui",
	"return r.setup({",
	"\tr:group('DebugVisible', {",
	"\t\tfg = hl.colors.fg,",
	pipeline_line,
	"\t}),",
	"})",
})
write(hidden_path, {
	"local hl = require('cf.hl.setup')",
	"local r = hl.ui",
	"return r.setup({ r:group('DebugHidden', { fg = hl.colors.fg, pipeline = { hl.brightness.fg(5) } }) })",
})

assert(diagnostic.configure({ debug = true }))
debug_feature.start()

-- The debug producer must only do source-range/trace work for a module that is
-- actually visible in the active tabpage.
local visible_buf = vim.fn.bufadd(visible_path)
vim.fn.bufload(visible_buf)
api.nvim_win_set_buf(0, visible_buf)

local compiled = theme.compile(root)
theme.apply(compiled)
diagnostic.clear_pending()

assert(theme.debug_file(hidden_path) == true)
assert(#diagnostic.pending() == 0, "hidden module produced debug diagnostics")

assert(theme.debug_file(visible_path) == true)
local pending = diagnostic.pending()
assert(#pending == 2, "expected one diagnostic per pipeline operation")

local b_start, b_end = assert(pipeline_line:find("hl.brightness.fg(10)", 1, true))
local o_start, o_end = assert(pipeline_line:find("hl.opacity.fg(50)", 1, true))
local expected = {
	{ col = b_start, end_col = b_end + 1, name = "brightness" },
	{ col = o_start, end_col = o_end + 1, name = "opacity" },
}
for i = 1, 2 do
	local record = pending[i]
	assert(record.debug == true)
	assert(record.source.file == vim.fs.normalize(visible_path))
	assert(record.source.line == 6)
	assert(record.source.col == expected[i].col, ("operation %d col: got %d expected %d"):format(i, record.source.col, expected[i].col))
	assert(record.source.end_col == expected[i].end_col, ("operation %d end_col: got %d expected %d"):format(i, record.source.end_col, expected[i].end_col))
	assert(record.message:find(expected[i].name, 1, true), "wrong operation diagnostic order")
	assert(record.code == i, ("operation %d pipeline code mismatch"):format(i))
end

assert(diagnostic.flush_buffer(visible_buf) == 2)
local ns = api.nvim_create_namespace("cf.nvim.diagnostic")
local rendered = vim.diagnostic.get(visible_buf, { namespace = ns })
assert(#rendered == 2, "flush_buffer did not render both operation diagnostics")
assert(rendered[1].col == b_start - 1 and rendered[1].end_col == b_end)
assert(rendered[2].col == o_start - 1 and rendered[2].end_col == o_end)
assert(rendered[1].code == 1 and rendered[2].code == 2, "rendered codes are not pipeline-local")

-- A targeted flush must not consume records belonging to another file.
local other = assert(diagnostic.report("hint", {
	message = "keep me pending",
	debug = true,
	source = { file = hidden_path, line = 1, col = 1 },
}))
assert(other)
assert(diagnostic.flush_buffer(visible_buf) == 0)
local left = diagnostic.pending()
assert(#left == 1 and left[1].message == "keep me pending")

diagnostic.clear()
debug_feature.stop()
vim.fn.delete(root, "rf")
print("cf.nvim debug diagnostic tests: OK")
