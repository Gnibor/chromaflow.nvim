vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cf = require("cf")
local config = require("cf.config")
local diagnostic = require("cf.diagnostic")
local runtime = require("cf.hl.runtime")
local theme = require("cf.theme")

-- Root setup owns the policy, while consumer autoreload is opt-in by default.
cf.setup({
	watch = false,
	lineblend = { autostart = false },
	diagnostic = {
		debug = false,
		severity_bias = 7,
		severity = { hint = false, warn = true, error = true },
		messages = { info = false, ok = true },
	},
})
assert(config.autoreload.lsp == false)
assert(config.autoreload.treesitter == false)
local policy = diagnostic.policy()
assert(policy.severity_bias == 7)
assert(policy.severity.hint == false and policy.severity.warn == true and policy.severity.error == true)
assert(policy.messages.info == false and policy.messages.ok == true)
assert(diagnostic.configure({ severity_bias = 0, severity = { hint = true } }))

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/dark", "p")

local function write(path, lines)
	vim.fn.writefile(lines, path)
end

write(root .. "/.cf-theme", { "dark", "dark" })
write(root .. "/dark/color.cf", {
	"return { fg = '#aabbcc', bg = '#101018' }",
})
write(root .. "/dark/config.cf", { "return {}" })
write(root .. "/dark/01-good.cf", {
	"local hl = require('cf.hl.setup')",
	"local raw = hl.raw",
	"return hl.ui.setup({",
	"  raw:group('CFDiagnosticGood', { bold = true }),",
	"})",
})
write(root .. "/dark/02-useless.cf", {
	"local hl = require('cf.hl.setup')",
	"local raw = hl.raw",
	"return hl.ui.setup({",
	"    raw:group('CFDiagnosticUseless', {}),",
	"})",
})
write(root .. "/dark/03-bad.cf", {
	"local hl = require('cf.hl.setup')",
	"local raw = hl.raw",
	"error('diagnostic wiring boom')",
	"return hl.ui.setup({ raw:group('Never', { bold = true }) })",
})
write(root .. "/dark/04-bad-dsl.cf", {
	"local hl = require('cf.hl.setup')",
	"local raw = hl.raw",
	"return hl.ui.setup({",
	"  raw:group('BadDSL', { not_a_highlight_field = true }),",
	"})",
})
write(root .. "/dark/05-not-a-module.cf", {
	"return 42",
})
write(root .. "/dark/06-typo.cf", {
	"local hl = require('cf.hl.setup')",
	"local l = hl.language",
	"local raw = hl.raw",
	"return l.setup('lua', {",
	"  raw:group('CFTypoBefore', { bold = true }),",
	"  l:goup('keyword', { italic = true }),",
	"  raw:group('CFTypoAfter', { italic = true }),",
	"})",
})

-- Show only the useless-HINT source in the current tabpage. The bad module must use
-- ASSERT fallback even if its file exists on disk.
vim.cmd("edit " .. vim.fn.fnameescape(root .. "/dark/02-useless.cf"))
diagnostic.clear()

local notifications = {}
local old_notify = vim.notify
vim.notify = function(message, level, opts)
	notifications[#notifications + 1] = { message = message, level = level, opts = opts }
end
cf.setup({ theme_path = root, watch = false, lineblend = { autostart = false } })
vim.notify = old_notify

local compiled = assert(theme.current())
assert(runtime.group_style("CFDiagnosticGood") ~= nil, "a bad sibling module aborted the complete theme")
assert(runtime.group_style("CFTypoBefore") ~= nil, "a typo aborted declarations before it")
assert(runtime.group_style("CFTypoAfter") ~= nil, "a skipped typo swallowed declarations after its nil hole")
local file_state = {}
for _, file in ipairs(compiled.module_files) do
	file_state[file.name] = file
end
assert(file_state["03-bad.cf"].failed == true and file_state["03-bad.cf"].ignored ~= true)
assert(file_state["04-bad-dsl.cf"].failed == true and file_state["04-bad-dsl.cf"].ignored ~= true)
assert(file_state["05-not-a-module.cf"].ignored == true and file_state["05-not-a-module.cf"].failed ~= true)
assert(file_state["06-typo.cf"].failed ~= true and file_state["06-typo.cf"].ignored ~= true)
assert(#diagnostic.pending() == 0, "cf.setup() did not flush the completed diagnostic cycle")

local records = diagnostic.history()
assert(#records == 2, "disabled HINT producers should exit before allocating records")
local runtime_error_record, dsl_error_record
for _, record in ipairs(records) do
	if record.source.file:match("03%-bad%.cf$") then
		runtime_error_record = record
	elseif record.source.file:match("04%-bad%-dsl%.cf$") then
		dsl_error_record = record
	end
end
assert(runtime_error_record and runtime_error_record.severity == diagnostic.severity.ERROR)
assert(runtime_error_record.source.line == 3 and runtime_error_record.source.col == 1)
assert(dsl_error_record and dsl_error_record.severity == diagnostic.severity.ERROR)
assert(dsl_error_record.source.line == 4 and dsl_error_record.source.col == 3)
assert(diagnostic.output_form(runtime_error_record) == diagnostic.form.ASSERT)
assert(diagnostic.output_form(dsl_error_record) == diagnostic.form.ASSERT)

local ns = vim.api.nvim_create_namespace("cf.nvim.diagnostic")
local buf = vim.api.nvim_get_current_buf()
local inline = vim.diagnostic.get(buf, { namespace = ns })
assert(#inline == 0)
-- Root setup restored hint=false, so internal HINT producers exited before record/source refinement.
-- The two real errors still use ASSERT output.
assert(#notifications == 2)
assert(notifications[1].level == vim.log.levels.ERROR and notifications[2].level == vim.log.levels.ERROR)
local notification_text = notifications[1].message .. "\n" .. notifications[2].message
assert(notification_text:find("03-bad.cf", 1, true))
assert(notification_text:find("04-bad-dsl.cf", 1, true))
assert(not notification_text:find("05-not-a-module.cf", 1, true))

vim.fn.delete(root, "rf")
print("cf.nvim diagnostic wiring tests: OK")
