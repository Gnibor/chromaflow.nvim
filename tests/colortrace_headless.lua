vim.opt.runtimepath:prepend(vim.fn.getcwd())

local api = vim.api
local config = require("cf.config")
local diagnostic = require("cf.diagnostic")
local debug_feature = require("cf.debug")
local picker = require("cf.picker")
local colortrace = require("cf.colortrace")
local pipeline = require("cf.hl.pipeline")
local theme = require("cf.theme")

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/default", "p")
vim.fn.mkdir(root .. "/active", "p")

local function write(path, lines)
	vim.fn.writefile(lines, path)
end

write(root .. "/.cf-theme", { "default", "active" })
write(root .. "/default/color.cf", { "return { bg = '#101010', fg = '#d0d0d0' }" })
write(root .. "/active/color.cf", { "return { bg = '#101010', fg = '#d0d0d0' }" })

local visible_path = root .. "/active/visible.cf"
local hidden_path = root .. "/active/hidden.cf"
write(visible_path, {
	"local hl = require('cf.hl.setup')",
	"local u = hl.ui",
	"return u.setup({",
	"\tu:group('TraceVisible', {",
	"\t\tfg = hl.colors.fg,",
	"\t\tpipeline = { hl.brightness.fg(10), hl.opacity.fg(50) },",
	"\t}),",
	"})",
})
write(hidden_path, {
	"local hl = require('cf.hl.setup')",
	"local u = hl.ui",
	"return u.setup({",
	"\tu:group('TraceHidden', {",
	"\t\tfg = hl.colors.fg,",
	"\t\tpipeline = { hl.darken.fg(7) },",
	"\t}),",
	"})",
})

config.setup({ picker = true, diagnostic = { debug = true } })
assert(diagnostic.configure({ debug = true }))
picker.start()
debug_feature.start()

local visible_buf = vim.fn.bufadd(visible_path)
vim.fn.bufload(visible_buf)
api.nvim_win_set_buf(0, visible_buf)

local old_debug_apply = pipeline.debug_apply
local trace_calls = 0
pipeline.debug_apply = function(...)
	trace_calls = trace_calls + 1
	return old_debug_apply(...)
end

local compiled = theme.compile(root)
assert(trace_calls == 3, "picker did not trace every pipeline operation across visible + hidden files")
theme.apply(compiled)

local visible_cache = assert(colortrace._cached(visible_path, compiled), "visible picker trace missing")
local hidden_cache = assert(colortrace._cached(hidden_path, compiled), "hidden picker trace missing")
assert(#visible_cache.records == 2, "visible picker trace operation count mismatch")
assert(#hidden_cache.records == 1, "hidden picker trace operation count mismatch")
assert(visible_cache.records[1].pipeline_index == 1 and visible_cache.records[2].pipeline_index == 2, "visible pipeline indices mismatch")
assert(hidden_cache.records[1].pipeline_index == 1, "hidden pipeline index mismatch")
assert(hidden_cache.records[1].trace.name == "darken", "hidden picker trace operation mismatch")
assert(hidden_cache.records[1].owner and hidden_cache.records[1].owner.file == vim.fs.normalize(hidden_path))

diagnostic.clear_pending()
local hidden_buf = vim.fn.bufadd(hidden_path)
vim.fn.bufload(hidden_buf)
api.nvim_win_set_buf(0, hidden_buf)

local before_replay = trace_calls
assert(debug_feature._seed(hidden_buf) == true, "debug seed failed for cached hidden file")
assert(trace_calls == before_replay, "debug retraced a picker-cached colour pipeline")

local ns = api.nvim_create_namespace("cf.nvim.diagnostic")
local rendered = vim.diagnostic.get(hidden_buf, { namespace = ns })
assert(#rendered == 1, "cached picker trace was not rendered as one debug diagnostic")
assert(rendered[1].message:find("darken.fg", 1, true), "cached debug diagnostic has wrong operation")
assert(rendered[1].code == 1, "cached debug diagnostic did not preserve pipeline-local code")

pipeline.debug_apply = old_debug_apply
diagnostic.clear()
debug_feature.stop()
picker.stop()
assert(diagnostic.configure({ debug = false }))
vim.fn.delete(root, "rf")
print("cf.nvim colortrace tests: OK")
