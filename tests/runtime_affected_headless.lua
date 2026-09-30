-- From the cf.nvim directory:
-- /path/to/mini-nvim/AppRun --headless -u NONE -l tests/runtime_affected_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")

local hl = require("cf.hl.setup")
local theme = require("cf.theme")

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/only/runtime", "p")

local function write(path, data)
	local fd = assert(io.open(path, "wb"))
	assert(fd:write(data))
	fd:close()
end

write(root .. "/.cf-theme", "only\nonly\n")
write(root .. "/only/color.cf", [[
return { fg = "#6080a0" }
]])
write(root .. "/only/core.cf", [[
local hl = require("cf.hl.setup")
local u = hl.ui
return u.setup({
	u:group("RuntimeA", { fg = hl.colors.fg }),
	u:group("RuntimeB", { fg = hl.colors.fg }),
})
]])
write(root .. "/only/runtime/actions.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
r.a_calls = 0

function r.a_once(style)
	r.a_calls = r.a_calls + 1
	assert(r.a_calls == 1, "unrelated runtime override A was evaluated again")
	style.bold = true
	return style
end

return r.setup({
	r:group("dynamic_a", { pipeline = { r:func("a_once") } }),
	r:group("static_b", { underline = true }),
})
]])

local r = hl.runtime("actions")
local target_a = hl.ui.RuntimeA
local target_b = hl.ui.RuntimeB
theme.load(root)

r.apply(target_a, r.groups.dynamic_a)
assert(r.a_calls == 1, "runtime override A did not run exactly once on its own apply")

local b_ok, b_err = pcall(r.apply, target_b, r.groups.static_b)
assert(b_ok, "changing unrelated runtime target B evaluated A: " .. tostring(b_err))
assert(r.a_calls == 1, "changing unrelated runtime target B re-evaluated A")

r.reset(target_b)
r.reset(target_a)
vim.fn.delete(root, "rf")
print("cf.nvim runtime affected-set regression: OK")
