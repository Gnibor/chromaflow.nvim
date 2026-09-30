vim.opt.runtimepath:prepend(vim.fn.getcwd())

local api = vim.api
local config = require("cf.config")
local diagnostic = require("cf.diagnostic")
local colortrace_view = require("cf.colortrace_view")
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

config.setup({ picker = true, diagnostic = { color_trace = true, messages = { info = false } } })
assert(diagnostic.configure(config.diagnostic))
assert(diagnostic.policy().messages.info == false, "test requires normal INFO messages to be disabled")
assert(diagnostic._enabled("hint") == false, "color_trace changed HINT visibility")
assert(diagnostic._enabled("warn") == false, "color_trace changed WARN visibility")
assert(diagnostic._enabled("error") == true, "color_trace changed ERROR visibility")
picker.start()
colortrace.set_enabled(config.diagnostic.color_trace)
colortrace_view.start()

local visible_buf = vim.fn.bufadd(visible_path)
vim.fn.bufload(visible_buf)
api.nvim_win_set_buf(0, visible_buf)

local old_color_trace_apply = pipeline.color_trace_apply
local trace_calls = 0
pipeline.color_trace_apply = function(...)
	trace_calls = trace_calls + 1
	return old_color_trace_apply(...)
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
assert(colortrace_view._seed(hidden_buf) == true, "ColorTrace seed failed for cached hidden file")
assert(trace_calls == before_replay, "ColorTrace retraced a picker-cached colour pipeline")

local ns = api.nvim_create_namespace("cf.nvim.diagnostic")
local rendered = vim.diagnostic.get(hidden_buf, { namespace = ns })
assert(#rendered == 1, "cached picker trace was not rendered as one INFO message")
assert(rendered[1].severity == vim.diagnostic.severity.INFO, "ColorTrace message was not rendered as INFO")
assert(rendered[1].message:find("darken.fg", 1, true), "cached ColorTrace message has wrong operation")
assert(rendered[1].code == 1, "cached ColorTrace message did not preserve pipeline-local code")

local old_abort = colortrace._compile_abort
local abort_calls = 0
colortrace._compile_abort = function(...)
	abort_calls = abort_calls + 1
	return old_abort(...)
end
write(root .. "/active/color.cf", "error('colortrace compile abort probe')\n")
local failed_ok = pcall(theme.compile, root)
colortrace._compile_abort = old_abort
assert(failed_ok == false, "broken color.cf unexpectedly compiled")
assert(abort_calls == 1, "failed compile did not abort ColorTrace staging")
assert(colortrace._cached(hidden_path, compiled) ~= nil, "failed compile damaged active ColorTrace cache")

pipeline.color_trace_apply = old_color_trace_apply
diagnostic.clear()
colortrace_view.stop()
colortrace.set_enabled(false)
picker.stop()
vim.fn.delete(root, "rf")
print("cf.nvim colortrace tests: OK")
