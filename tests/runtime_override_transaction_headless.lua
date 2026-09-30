-- From the cf.nvim directory:
-- /path/to/mini-nvim/AppRun --headless -u NONE -l tests/runtime_override_transaction_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")

local hl = require("cf.hl.setup")
local theme = require("cf.theme")

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/first/runtime", "p")
vim.fn.mkdir(root .. "/second/runtime", "p")

local function write(path, data)
	local fd = assert(io.open(path, "wb"))
	assert(fd:write(data))
	fd:close()
end

local function style(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end

write(root .. "/.cf-theme", "first\nfirst\n")
write(root .. "/first/color.cf", [[
return { fg = "#6080a0" }
]])
write(root .. "/second/color.cf", [[
return { fg = "#6080a0" }
]])
write(root .. "/first/core.cf", [[
local hl = require("cf.hl.setup")
local u = hl.ui
return u.setup({
	u:group("RuntimePresent", { fg = hl.colors.fg }),
})
]])
write(root .. "/second/core.cf", [[
local hl = require("cf.hl.setup")
local u = hl.ui
return u.setup({
	u:group("RuntimePresent", { fg = hl.colors.fg }),
	u:group("RuntimeDeferred", { fg = hl.colors.fg }),
})
]])

local runtime_source = [[
local hl = require("cf.hl.setup")
local r = hl.runtime
return r.setup({
	r:group("mark", { bold = true }),
})
]]
write(root .. "/first/runtime/actions.cf", runtime_source)
write(root .. "/second/runtime/actions.cf", runtime_source)

local r = hl.runtime("actions")
theme.load(root)

-- A failed ordinary change must not publish its replacement into override state.
local missing = hl.ui.RuntimeMissing
local apply_ok, apply_err = pcall(r.apply, missing, r.groups.mark)
assert(not apply_ok, "runtime apply unexpectedly accepted a non-materialized target")
assert(tostring(apply_err):find("target is not materialized by the current theme", 1, true), "runtime apply returned the wrong target error")

local reset_ok, reset_result = pcall(r.reset, missing)
assert(reset_ok, "failed runtime apply leaked override state into reset: " .. tostring(reset_result))
assert(reset_result == false, "failed runtime apply left an override behind")

-- Transition callbacks intentionally may store an override before its target is
-- materialized. A later failed reset must keep that existing override intact.
local deferred = hl.ui.RuntimeDeferred
vim.api.nvim_create_autocmd("ColorScheme", {
	pattern = "first",
	once = true,
	callback = function()
		r.apply(deferred, r.groups.mark)
	end,
})
theme.load(root)

local deferred_reset_ok, deferred_reset_err = pcall(r.reset, deferred)
assert(not deferred_reset_ok, "reset unexpectedly accepted a currently non-materialized target")
assert(tostring(deferred_reset_err):find("target is not materialized by the current theme", 1, true), "runtime reset returned the wrong target error")

theme.select(root, "second")
theme.load(root)
assert(style("RuntimeDeferred").bold == true, "failed runtime reset discarded the existing deferred override")
assert(r.reset(deferred) == true, "deferred override was not preserved after failed reset")

vim.fn.delete(root, "rf")
print("cf.nvim runtime override transaction regression: OK")
