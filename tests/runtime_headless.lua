-- From the cf.nvim directory:
-- /path/to/mini-nvim/AppRun --headless -u NONE -l tests/runtime_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")

local hl = require("cf.hl.setup")
local theme = require("cf.theme")
local color = require("cf.color")
local hl_runtime = require("cf.hl.runtime")
local runtime_state = require("cf.fn.runtime")

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/default/runtime", "p")
vim.fn.mkdir(root .. "/active/runtime", "p")
vim.fn.mkdir(root .. "/runtime", "p")

local function write(path, data)
	local fd = assert(io.open(path, "wb"))
	assert(fd:write(data))
	fd:close()
end

local function style(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end

local function exact(name)
	return vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
end

local function rgb(value)
	return tonumber(color.to_rgb_hex(value):sub(2), 16)
end

write(root .. "/.cf-theme", "default\nactive\n")
write(root .. "/default/color.cf", [[
return { bg = "#101010", base = "#203040", accent = "#884422" }
]])
write(root .. "/active/color.cf", [[
return { bg = "#111111", base = "#406080", accent = "#aa5522" }
]])

local module_source = [[
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language
local u = hl.ui
return u.setup({
	u:group("RuntimeThing", { fg = c.base, bg = c.bg }),
})
]]
write(root .. "/default/core.cf", module_source)
write(root .. "/active/core.cf", module_source)

local language_source = [[
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language
return l.setup("lua", {
	l:group("variable", { fg = c.base }),
})
]]
write(root .. "/default/lang.cf", language_source)
write(root .. "/active/lang.cf", language_source)

write(root .. "/default/runtime/actions.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
return r.setup({
	r:group("dim", { pipeline = { hl.brightness.fg(-5) } }),
	r:group("focus", { italic = true }),
})
]])
write(root .. "/runtime/actions.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
return r.setup({
	r:group("focus", { underline = true }),
})
]])
write(root .. "/active/runtime/actions.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
return r.setup({
	r:group("dim", { pipeline = { hl.brightness.fg(-20) } }),
	r:group("focus", { bold = true }),
	r:group("module", { strikethrough = true }),
})
]])

-- Request before the first theme exists: the handle is stable and resolution is
-- deferred until theme.compile() knows active/root/default.
local r = hl.runtime("actions")
local ui_target = hl.ui.RuntimeThing
local lua_variable = hl.language.lua.variable

local compiled = theme.load(root)
assert(compiled.runtime_modules.actions.source == "active", "runtime active fallback did not win")

local base = color.from_hex("#406080")
local bg = color.from_hex("#111111")
assert(style("RuntimeThing").fg == rgb(base))
assert(style("RuntimeThing").bg == rgb(bg))
assert(runtime_state._overlay_size() == 0, "runtime diff was not empty before the first modification")
local cached_base = hl_runtime.group_style("RuntimeThing")

-- Raw runtime targets are exact Neovim highlight names. They do not need a
-- raw:group() declaration in the theme: an already-existing highlight can be
-- adopted directly and its current effective style becomes the runtime base.
local raw_external = hl.raw.RuntimeExternalRaw
local raw_base = color.from_hex("#90b0d0")
local raw_bg = color.from_hex("#182028")
vim.api.nvim_set_hl(0, "RuntimeExternalRaw", { fg = rgb(raw_base), bg = rgb(raw_bg), italic = true })
assert(hl_runtime.group_style("RuntimeExternalRaw") == nil, "external raw group unexpectedly entered the theme cache")
r.apply(raw_external, r.groups.dim)
local raw_dimmed = style("RuntimeExternalRaw")
assert(raw_dimmed.fg == rgb(color.brightness(raw_base, -20)), "raw runtime target did not read the existing Neovim style")
assert(raw_dimmed.bg == rgb(raw_bg) and raw_dimmed.italic == true, "raw runtime apply lost fields from the external base")
assert(r.reset(raw_external) == true, "raw runtime reset did not remove the external override")
local raw_restored = style("RuntimeExternalRaw")
assert(raw_restored.fg == rgb(raw_base) and raw_restored.bg == rgb(raw_bg) and raw_restored.italic == true, "raw runtime reset did not restore the external Neovim base")

local missing_raw = hl.raw.RuntimeMissingRaw
local missing_raw_ok, missing_raw_err = pcall(r.apply, missing_raw, r.groups.dim)
assert(not missing_raw_ok, "runtime raw apply unexpectedly accepted a missing Neovim highlight")
assert(tostring(missing_raw_err):find("target is not materialized by the current theme", 1, true), "runtime raw apply returned the wrong missing-target error")
assert(r.reset(missing_raw) == false, "failed raw runtime apply leaked override state")

r.apply(ui_target, r.groups.dim)
assert(runtime_state._overlay_size() == 1, "runtime diff did not contain exactly the modified UI target")
assert(hl_runtime.group_style("RuntimeThing") == cached_base, "runtime apply polluted the normal base style cache")
local dimmed = color.brightness(base, -20)
assert(style("RuntimeThing").fg == rgb(dimmed), "apply did not manipulate the theme base")
assert(style("RuntimeThing").bg == rgb(bg), "apply lost untouched base fields")

-- apply() always starts at the theme base, never at the previous runtime result.
r.apply(ui_target, r.groups.dim)
assert(style("RuntimeThing").fg == rgb(dimmed), "apply drifted when repeated")

r.replace(ui_target, r.groups.focus)
local replaced = style("RuntimeThing")
assert(replaced.bold == true, "replace did not use runtime style")
assert(replaced.fg == nil and replaced.bg == nil, "replace kept theme-base colors")

assert(r.reset(ui_target) == true)
assert(runtime_state._overlay_size() == 0, "reset did not remove the sparse runtime diff")
assert(hl_runtime.group_style("RuntimeThing") == cached_base, "reset changed the normal base style cache")
assert(style("RuntimeThing").fg == rgb(base) and style("RuntimeThing").bg == rgb(bg), "reset did not restore theme base")

-- Public handles carry no implementation metadata fields, so action/typemod
-- names cannot collide with internals such as `module` or `kind`.
r.replace(ui_target, r.groups.module)
assert(style("RuntimeThing").strikethrough == true, "runtime action name collided with handle metadata")
r.reset(ui_target)
assert(tostring(hl.language.lua.variable.kind):match("%.kind$"), "runtime typemod name collided with target metadata")

r.clear(ui_target)
assert(next(exact("RuntimeThing")) == nil, "clear did not clear the concrete group")
assert(r.reset(ui_target) == true)
assert(style("RuntimeThing").fg == rgb(base), "reset after clear failed")

-- One semantic language handle addresses every concrete target materialized for
-- the resolver action, without running resolver semantics again at runtime.
r.replace(lua_variable, r.groups.focus)
for _, name in ipairs({ "luaIdentifier", "@variable.lua", "@lsp.type.variable.lua" }) do
	assert(style(name).bold == true, "semantic runtime target missed " .. name)
end
r.reset(lua_variable)

-- Active -> root -> default, first hit wins and the public module/action handles
-- stay valid while their backing definition changes.
vim.fn.delete(root .. "/active/runtime/actions.cf")
compiled = theme.load(root)
assert(compiled.runtime_modules.actions.source == "root", "runtime root fallback did not win")
r.replace(ui_target, r.groups.focus)
assert(style("RuntimeThing").underline == true, "stable action handle did not pick root definition")
r.reset(ui_target)
local merged_ok = pcall(r.apply, ui_target, r.groups.dim)
assert(not merged_ok, "runtime actions were merged across root/default instead of taking the first module")

vim.fn.delete(root .. "/runtime/actions.cf")
compiled = theme.load(root)
assert(compiled.runtime_modules.actions.source == "default", "runtime default fallback did not win")
r.replace(ui_target, r.groups.focus)
assert(style("RuntimeThing").italic == true, "stable action handle did not pick default definition")
r.reset(ui_target)

-- Runtime apply state survives a normal theme reload and is recalculated from
-- the new theme base, not from the old runtime result.
write(root .. "/active/runtime/actions.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
return r.setup({
	r:group("dim", { pipeline = { hl.brightness.fg(-30) } }),
	r:group("focus", { bold = true }),
})
]])
write(root .. "/active/color.cf", [[
return { bg = "#121212", base = "#6080a0", accent = "#aa5522" }
]])
r.apply(ui_target, r.groups.dim)
compiled = theme.load(root)
assert(compiled.runtime_modules.actions.source == "active")
local new_base = color.from_hex("#6080a0")
assert(style("RuntimeThing").fg == rgb(color.brightness(new_base, -30)), "reload did not reapply runtime action to new base")
r.reset(ui_target)
assert(style("RuntimeThing").fg == rgb(new_base), "reset after reload did not restore new base")

-- Runtime calls from ColorScheme callbacks update state immediately but defer
-- visible writes. The runtime base must be the final normal theme after every
-- callback, including callbacks registered after the one that calls r.apply().
local callback_base = color.from_hex("#90a0b0")
vim.api.nvim_create_autocmd("ColorScheme", {
	pattern = "active",
	once = true,
	callback = function()
		r.apply(ui_target, r.groups.dim)
	end,
})
vim.api.nvim_create_autocmd("ColorScheme", {
	pattern = "active",
	once = true,
	callback = function()
		vim.api.nvim_set_hl(0, "RuntimeThing", { fg = "#90a0b0", bg = "#121212" })
	end,
})
compiled = theme.load(root)
assert(style("RuntimeThing").fg == rgb(color.brightness(callback_base, -30)), "ColorScheme runtime call did not use final callback base")
r.reset(ui_target)
assert(style("RuntimeThing").fg == rgb(callback_base), "reset did not restore final ColorScheme callback base")

-- External raw targets are rebound after reload against the final Neovim state
-- produced by ColorScheme callbacks, even though no raw:group() exists in CF.
local raw_reload_base = color.from_hex("#b09070")
vim.api.nvim_set_hl(0, "RuntimeExternalRaw", { fg = rgb(raw_base), bg = rgb(raw_bg), italic = true })
r.apply(raw_external, r.groups.dim)
vim.api.nvim_create_autocmd("ColorScheme", {
	pattern = "active",
	once = true,
	callback = function()
		vim.api.nvim_set_hl(0, "RuntimeExternalRaw", { fg = rgb(raw_reload_base), bg = rgb(raw_bg), italic = true })
	end,
})
compiled = theme.load(root)
assert(style("RuntimeExternalRaw").fg == rgb(color.brightness(raw_reload_base, -30)), "raw runtime reload did not use the final external ColorScheme base")
r.reset(raw_external)
local raw_reload_restored = style("RuntimeExternalRaw")
assert(raw_reload_restored.fg == rgb(raw_reload_base) and raw_reload_restored.bg == rgb(raw_bg) and raw_reload_restored.italic == true, "raw runtime reset after reload did not restore the external callback base")

-- If an active runtime override references an action removed by a new runtime
-- module, compilation fails before the destructive ColorScheme apply begins.
r.apply(ui_target, r.groups.dim)
local before_failed_reload = style("RuntimeThing").fg
write(root .. "/active/runtime/actions.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
return r.setup({ r:group("focus", { bold = true }) })
]])
local reload_ok = pcall(theme.load, root)
assert(not reload_ok, "runtime action removal should fail theme compilation")
assert(style("RuntimeThing").fg == before_failed_reload, "failed runtime compile mutated the visible theme")
r.reset(ui_target)

-- runtime/ is infrastructure, not a selectable theme directory.
local available = theme.available(root)
for i = 1, #available do
	assert(available[i] ~= "runtime", "runtime directory leaked into theme.available()")
end

vim.fn.delete(root, "rf")
print("cf.nvim runtime tests: OK")
