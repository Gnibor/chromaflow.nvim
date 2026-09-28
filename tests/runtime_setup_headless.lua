-- From the cf.nvim directory:
-- /path/to/mini-nvim/AppRun --headless -u NONE -l tests/runtime_setup_headless.lua
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

local function style(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end

write(root .. "/.cf-theme", "only\nonly\n")
write(root .. "/only/color.cf", [[
return { bg = "#101010", fg = "#6080a0", red = "#ff2020" }
]])
write(root .. "/only/lang.cf", [[
local hl = require("cf.hl.setup")
local l = hl.language
return l.setup("lua", {
	style_targets = { vim = true, ts = true, lsp = true },
	l:group("variable", { fg = hl.colors.fg }),
})
]])
write(root .. "/only/runtime/panic.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
assert(r.g == r.groups)

r.calls = 0
r.last_frame = -1
r.last_tick = false
r.last_delta = -1
r.last_elapsed = -1

function r.alert(style, ctx)
	r.calls = r.calls + 1
	r.last_frame = ctx.frame
	r.last_tick = ctx.tick or false
	r.last_delta = ctx.delta
	r.last_elapsed = ctx.elapsed
	style.bold = (ctx.frame % 2) == 0
	return style
end

function r.once(style, ctx)
	r.once_calls = (r.once_calls or 0) + 1
	assert(ctx.frame == 0 and ctx.tick == nil)
	style.italic = true
	return style
end

return r.setup({
	r:group("blink", {
		pipeline = { r:func("alert")[30] },
	}),
	r:group("once", {
		pipeline = { r:func("once") },
	}),
})
]])

local r = hl.runtime("panic")
assert(r.g == r.groups, "runtime r.g alias is not the groups namespace")
local target = hl.language.lua.variable
local compiled = theme.load(root)
assert(compiled.runtime_modules.panic.definition.group_ticks.blink == 30)
assert(type(r.alert) == "function", "runtime function export is not visible on the loaded module")

-- One semantic apply spans Vim/TS/LSP, but a stateful function must run only
-- once for the identical semantic base style, not once per concrete hl_group.
r.apply(target, r.groups.once)
assert(r.once_calls == 1, "runtime function ran once per concrete target instead of once per base style")
for _, name in ipairs({ "luaIdentifier", "@variable.lua", "@lsp.type.variable.lua" }) do
	assert(style(name).italic == true, "runtime function missed " .. name)
end
r.reset(target)

r.apply(target, r.groups.blink)
assert(r.calls == 1, "timed runtime function did not render frame 0 immediately")
assert(r.last_frame == 0 and r.last_tick == 30)
assert(r.last_delta == 0 and r.last_elapsed == 0)

local advanced = vim.wait(500, function()
	return (r.last_frame or -1) >= 2
end, 10)
assert(advanced, "runtime tick did not advance")
assert(r.calls >= 3, "runtime tick did not re-evaluate the action")
assert(r.last_delta > 0 and r.last_elapsed > 0, "runtime timing context did not advance")

local calls_before_reset = r.calls
assert(r.reset(target) == true)
vim.wait(120)
assert(r.calls == calls_before_reset, "runtime tick kept running after reset")

-- Runtime function namespaces are module-local even when two files export the
-- same name. The public stable module handle resolves the matching definition.
write(root .. "/only/runtime/other.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
function r.alert(style)
	style.underline = true
	return style
end
return r.setup({ r:group("mark", { pipeline = { r:func("alert") } }) })
]])
local other = hl.runtime("other")
assert(type(other.alert) == "function" and other.alert ~= r.alert, "runtime module function namespaces collided")
other.apply(target, other.groups.mark)
assert(style("@variable.lua").underline == true, "second runtime module function did not apply")
other.reset(target)

-- Plain Lua functions remain invalid pipeline entries. r:func() is the explicit
-- adapter from the runtime module function namespace into the style pipeline.
write(root .. "/only/runtime/bad.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
return r.setup({
	r:group("bad", { pipeline = { function(style) return style end } }),
})
]])
local bad = hl.runtime("bad")
local bad_ok, bad_err = pcall(bad.apply, target, bad.groups.bad)
assert(not bad_ok and tostring(bad_err):find("pipeline entries must be operations", 1, true), "raw Lua pipeline function was accepted")

-- One action has one tick. Multiple functions may share it, but conflicting
-- intervals would make the action's frame clock ambiguous and are rejected.
write(root .. "/only/runtime/conflict.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
function r.a(style) return style end
function r.b(style) return style end
return r.setup({
	r:group("bad", { pipeline = { r:func("a")[20], r:func("b")[30] } }),
})
]])
local conflict_ok, conflict_err = pcall(function() hl.runtime("conflict") end)
assert(not conflict_ok and tostring(conflict_err):find("different func tick intervals", 1, true), "conflicting runtime ticks were accepted")

vim.fn.delete(root, "rf")
print("cf.nvim runtime setup tests: OK")
