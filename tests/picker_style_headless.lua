-- From the cf.nvim directory:
-- nvim --headless -u NONE -l tests/picker_style_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")

local config = require("cf.config")
local hl = require("cf.hl.setup")
local theme = require("cf.theme")
local color = require("cf.color")
local hl_runtime = require("cf.hl.runtime")
local runtime = require("cf.fn.runtime")
local picker = require("cf.picker")

config.setup({ picker = true })
picker.start()

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/active", "p")
vim.fn.mkdir(root .. "/default", "p")

local function write(path, data)
	local fd = assert(io.open(path, "wb"))
	assert(fd:write(data))
	fd:close()
end

local function style(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end

local function rgb(value)
	return tonumber(color.to_rgb_hex(value):sub(2), 16)
end

write(root .. "/.cf-theme", "default\nactive\n")
write(root .. "/default/color.cf", [[
return { base = "#345678", bg = "#101010" }
]])
write(root .. "/active/color.cf", [[
return { base = "#345678", bg = "#101010" }
]])

local source = [[
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language
return l.setup("lua", {
	mods = {
		readonly = { italic = true },
	},
	l:group("variable", {
		fg = c.base,
		italic = false,
		underline = true,
		typemods = {
			readonly = { bold = true },
		},
	}),
})
]]
write(root .. "/default/lua.cf", source)
write(root .. "/active/lua.cf", source)

local compiled = theme.load(root)
local variable = runtime.target("language", "lua", "variable", nil)
local readonly = runtime.target("language", "lua", nil, "readonly")
local variable_readonly = runtime.target("language", "lua", "variable", "readonly")

local state = runtime._picker_style_state(variable)
assert(type(state.base) == "table", "picker Type style base missing")
assert(state.base.underline == true, "picker Type style base lost underline")
assert(state.base.italic == false, "picker Type style base lost explicit false")
assert(state.current == state.base, "picker Type style unexpectedly started in runtime")
assert(state.has_runtime == false, "picker Type style incorrectly reported runtime diff")

local cached_base = hl_runtime.group_style("@variable.lua") or hl_runtime.group_style("luaIdentifier")
assert(cached_base ~= nil, "compiled style cache did not expose variable base")
local cache_size = hl._style_cache_size()
local edited = {}
for key, value in pairs(state.current) do edited[key] = value end
edited.bold = true
edited.underline = nil
local canonical = runtime._picker_set_style(variable, edited)
assert(runtime._overlay_size() > 0, "picker Style did not use runtime sparse cache")
runtime._picker_restore_style(variable, state)
assert(runtime._overlay_size() == 0, "picker Style cancel left a redundant runtime diff")
local restored = runtime._picker_style_state(variable)
assert(restored.has_runtime == false, "picker Style cancel did not restore sparse absence")
assert(restored.current.underline == true and restored.current.bold ~= true, "picker Style cancel did not restore source style")
canonical = runtime._picker_set_style(variable, edited)
assert(canonical.bold == true, "picker Style canonical value lost explicit true")
assert(canonical.italic == false, "picker Style canonical value lost explicit false")
assert(canonical.underline == nil, "picker Style canonical value lost unset/inherit state")
assert(hl._style_cache_size() >= cache_size, "picker Style bypassed style interning cache")
assert((hl_runtime.group_style("@variable.lua") or hl_runtime.group_style("luaIdentifier")) == cached_base, "picker Style polluted compiled base style cache")

for _, name in ipairs({ "luaIdentifier", "@variable.lua", "@lsp.type.variable.lua" }) do
	local value = style(name)
	if next(value) ~= nil then
		assert(value.bold == true, "picker Style missed semantic target " .. name)
		assert(value.underline ~= true, "picker Style failed to unset underline on " .. name)
		assert(value.fg == rgb(color.from_hex("#345678")), "picker Style lost base colour on " .. name)
	end
end

local again = runtime._picker_style_state(variable)
assert(again.has_runtime == true and again.current == canonical, "picker Style runtime cache was not readable")
assert(again.current.italic == false and again.current.underline == nil, "picker Style runtime cache collapsed tri-state values")
-- A status read reuses the existing style references without collecting raw
-- highlight/undo snapshots. The target is already resolved above.
local old_get_hl = vim.api.nvim_get_hl
local reads = 0
vim.api.nvim_get_hl = function(...)
	reads = reads + 1
	return old_get_hl(...)
end
local status = runtime._picker_style_state(variable, false)
vim.api.nvim_get_hl = old_get_hl
assert(reads == 0, "status read queried highlight snapshots")
assert(status.snapshots == nil, "status read allocated undo snapshots")
assert(status.base == again.base and status.current == canonical and status.runtime == again.runtime,
	"status read copied or changed style state")
assert(status.current.bold == true and status.current.italic == false and status.current.underline == nil,
	"status read lost true/false/unset")
assert(again.snapshots and next(again.snapshots), "default editor/save path lost snapshots")
local second = {}
for key, value in pairs(again.current) do second[key] = value end
second.italic = true
runtime._picker_set_style(variable, second)
runtime._picker_restore_style(variable, again)
local restored_runtime = runtime._picker_style_state(variable)
assert(restored_runtime.has_runtime == true and restored_runtime.current == canonical, "picker Style cancel did not restore prior runtime diff")

-- Mod-only and TypeMod handles use the same runtime target/cache machinery.
local mod_state = runtime._picker_style_state(readonly)
assert(type(mod_state.current) == "table" and mod_state.current.italic == true, "picker Mod style target is not readable")
local typemod_state = runtime._picker_style_state(variable_readonly)
assert(type(typemod_state.current) == "table" and typemod_state.current.bold == true, "picker TypeMod style target is not readable")

-- Picker preview state is intentionally ephemeral: recompiling the theme drops
-- direct picker runtime-cache writes and restores the newly compiled source.
compiled = theme.load(root)
local after_reload = runtime._picker_style_state(variable)
assert(after_reload.has_runtime == false, "picker Style runtime preview survived theme reload")
assert(after_reload.current.underline == true and after_reload.current.bold ~= true, "picker Style reload did not restore source style")
assert(runtime._current_theme() == compiled, "runtime did not adopt reloaded theme")

-- Picker-mode actions retain the exact declaration source for later save.
local found_source, found_action
for i = 1, #compiled.modules do
	for j = 1, #compiled.modules[i].actions do
		local action = compiled.modules[i].actions[j]
		if action.type_name == "variable" and action.typemod == nil then
			found_source = action._cf_source
			found_action = action
			break
		end
	end
	if found_source then break end
end
assert(found_source and found_source.file and found_source.end_line and found_source.end_col, "picker action source range missing")

-- Exercise the real Style float and its buffer-local mappings, without needing
-- a Tree-sitter capture underneath the test cursor.
local function upvalue(fn, wanted)
	for i = 1, 100 do
		local name, value = debug.getupvalue(fn, i)
		if name == wanted then return value end
		if not name then break end
	end
	error("missing upvalue " .. wanted)
end
local open_pick = upvalue(picker.open, "open_pick")
local open_edit = upvalue(open_pick, "open_edit")
local open_style = upvalue(open_edit, "open_style")
picker._style_edits() -- normal CFPick initializes this theme's reverse cache
local entry = {
	target = variable, name = "variable", kind = "Type", type_name = "variable",
	source = found_source, action = found_action,
}
local function key(value)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(value, true, false, true), "mx", false)
end
local function current_blend()
	return runtime._picker_style_state(variable).current.blend
end
local function open_blend()
	local opened = open_style(entry, { entry }, 1)
	assert(vim.tbl_contains(picker._style_flags(), "dim"))
	assert(vim.tbl_contains(picker._style_flags(), "conceal"))
	for _ = 1, #picker._style_flags() do key("j") end
	return opened
end
local opened = open_blend()
key("+")
assert(current_blend() == 1, "blend +1 failed")
key("<M-+>")
assert(current_blend() == 11, "blend Alt+10 failed")
key("<M-->")
key("-")
assert(current_blend() == 0, "blend explicit zero was lost")
key("-")
assert(current_blend() == 0, "blend lower bound failed")
for _ = 1, 11 do key("<M-+>") end
assert(current_blend() == 100, "blend upper bound failed")
assert(opened.items[#opened.items]:find("100", 1, true), "blend label is stale")
key("<Space>")
assert(current_blend() == nil, "blend unset failed")
key("+")
key("q")
assert(current_blend() == nil, "blend cancel failed")
assert(not runtime._picker_style_state(variable).has_runtime, "cancel left runtime state")

open_blend()
key("<M-+>")
key("<BS>")
assert(current_blend() == nil, "blend Backspace did not restore")
require("cf.menu").close()
open_blend()
key("<M-+>")
key("<CR>")
require("cf.menu").close()
assert(current_blend() == 10, "blend commit failed")
local save = require("cf.save")
local plan = save.plan()
assert(plan.count > 0, "confirmed blend edit missing from save")
save.write(plan)
theme.load(root)
assert(runtime._picker_style_state(variable).base.blend == 10, "blend save/reload failed")

picker.stop()
vim.fn.delete(root, "rf")
print("cf.nvim picker style runtime/cache tests: OK")
