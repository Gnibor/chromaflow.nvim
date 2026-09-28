vim.opt.runtimepath:prepend(vim.fn.getcwd())

local diagnostic = require("cf.diagnostic")
local api = vim.api

assert(diagnostic.severity.HINT == 64)
assert(diagnostic.severity.WARN == 128)
assert(diagnostic.severity.ERROR == 192)
assert(diagnostic.message.INFO == "info")
assert(diagnostic.message.OK == "ok")
assert(diagnostic.tag.DEPRECATED == "deprecated")
assert(diagnostic.tag.UNNECESSARY == "unnecessary")

local ok, err = diagnostic.configure({
	debug = false,
	severity_bias = 0,
	severity = { hint = true, warn = true, error = true },
	messages = { info = true, ok = true },
})
assert(ok, err)

local visible_file = vim.fn.tempname() .. ".cf"
local other_tab_file = vim.fn.tempname() .. ".cf"
local hidden_file = vim.fn.tempname() .. ".cf"
vim.fn.writefile({ "one", "two", "three" }, visible_file)
vim.fn.writefile({ "other" }, other_tab_file)
vim.fn.writefile({ "hidden" }, hidden_file)

local visible_buf = vim.fn.bufadd(visible_file)
vim.fn.bufload(visible_buf)
api.nvim_win_set_buf(0, visible_buf)
local active_tab = api.nvim_get_current_tabpage()

vim.cmd("tabnew " .. vim.fn.fnameescape(other_tab_file))
local other_tab = api.nvim_get_current_tabpage()
assert(other_tab ~= active_tab)
api.nvim_set_current_tabpage(active_tab)

local hint = assert(diagnostic.report("hint", {
	message = 'unknown type "demo" uses literal fallback',
	context = { kind = "theme", name = "lang-lua" },
	tags = { diagnostic.tag.UNNECESSARY },
	source = { file = visible_file, line = 2, col = 3, end_line = 3, end_col = 2 },
}))
assert(hint.source.end_line == 3 and hint.source.end_col == 2)
assert(hint.form == diagnostic.form.DIAGNOSTIC)
assert(diagnostic.output_form(hint) == diagnostic.form.DIAGNOSTIC)

local other_tab_error = assert(diagnostic.report("error", {
	message = "error lives in another tab",
	source = { file = other_tab_file, line = 1, col = 1 },
}))
assert(diagnostic.output_form(other_tab_error) == diagnostic.form.ASSERT)

local hidden_warn = assert(diagnostic.report("warn", {
	message = "hidden source warning",
	source = { file = hidden_file, line = 1, col = 1 },
}))
assert(diagnostic.output_form(hidden_warn) == diagnostic.form.ASSERT)

local debug_only = assert(diagnostic.report("warn", {
	message = "debug-only resolver detail",
	debug = true,
	source = { file = visible_file, line = 1, col = 1 },
}))
assert(diagnostic.visible(debug_only) == false)

local user_info = assert(diagnostic.info({
	message = 'theme "dark" selected',
	source = { file = visible_file, line = 1, col = 1 },
}))
assert(user_info.form == diagnostic.form.MESSAGE)
assert(user_info.severity == nil)

-- Missing columns remain invalid for every stored output.
local bad, bad_err = diagnostic.report("hint", {
	message = "missing column",
	source = { file = visible_file, line = 1 },
})
assert(bad == nil)
assert(type(bad_err) == "string" and bad_err:find("source.col", 1, true))

assert(diagnostic.configure({ severity_bias = 40 }))
assert(diagnostic.effective_severity(diagnostic.severity.HINT) == 104)
assert(diagnostic.classify(diagnostic.effective_severity(diagnostic.severity.HINT)) == "warn")
assert(diagnostic.configure({ severity_bias = 0 }))

local notifications = {}
local original_notify = vim.notify
vim.notify = function(message, level, opts)
	notifications[#notifications + 1] = { message = message, level = level, opts = opts }
end

local rendered = diagnostic.flush()
vim.notify = original_notify
assert(rendered == 4) -- visible hint + two ASSERT fallbacks + INFO; debug-only filtered.

local ns = api.nvim_create_namespace("cf.nvim.diagnostic")
local current = vim.diagnostic.get(visible_buf, { namespace = ns })
assert(#current == 1)
assert(current[1].severity == vim.diagnostic.severity.HINT)
assert(current[1].lnum == 1 and current[1].col == 2)
assert(#notifications == 3) -- two off-tab ASSERT fallbacks + INFO.
assert(notifications[1].message:find(other_tab_file, 1, true) or notifications[2].message:find(other_tab_file, 1, true))

-- A clean cycle must clear old in-buffer diagnostics.
assert(diagnostic.flush() == 0)
assert(#vim.diagnostic.get(visible_buf, { namespace = ns }) == 0)

-- Debug mode opens all normal gates.
assert(diagnostic.configure({
	debug = true,
	severity = { hint = false, warn = false, error = false },
	messages = { info = false, ok = false },
}))
local debug_warn = assert(diagnostic.report("warn", {
	message = "visible in debug",
	debug = true,
	source = { file = visible_file, line = 1, col = 1 },
}))
assert(diagnostic.visible(debug_warn) == true)

assert(#diagnostic.history() >= 6)
diagnostic.clear()
assert(#diagnostic.pending() == 0)
assert(#diagnostic.history() == 0)

api.nvim_set_current_tabpage(other_tab)
vim.cmd("tabclose")
vim.fn.delete(visible_file)
vim.fn.delete(other_tab_file)
vim.fn.delete(hidden_file)
print("cf.nvim diagnostic policy tests: OK")
