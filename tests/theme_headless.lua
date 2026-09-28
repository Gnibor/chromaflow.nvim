vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cf = require("cf")
local theme = require("cf.theme")
local runtime = require("cf.hl.runtime")
local color = require("cf.color")

local function assert_effective(name, expected)
	local actual = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
	for key, value in pairs(expected) do
		assert(actual[key] == value, name .. ": unexpected effective " .. key)
	end
	return actual
end

local function assert_absent(name)
	local actual = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
	assert(next(actual) == nil, name .. ": suppressed module left a style or link")
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/default", "p")
vim.fn.mkdir(root .. "/active", "p")

local function write(path, data)
	local fd = assert(io.open(path, "wb"))
	fd:write(data)
	fd:close()
end

write(root .. "/.cf-theme", "default\nactive\n")
write(root .. "/default/color.cf", [[
return {
	bg = "#101010",
	accent = "#202020",
}
]])
write(root .. "/active/color.cf", [[
return {
	bg = "#111122",
	accent = "#a06020",
}
]])

-- Root config wins when the active theme has no config.cf.
write(root .. "/config.cf", [[
return {
	style_targets = {
		vim = true,
		ts = true,
		lsp = true,
	},
}
]])

-- Active may split one semantic language across multiple arbitrarily named
-- files. Both must compile; registration is only a collection pass here.
write(root .. "/active/anything-a.cf", [[
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language
local raw = hl.raw
return l.setup("lua", {
	raw:group("ActiveLuaOne", { fg = c.accent }),
	raw:group("@cf.raw.lua", { fg = c.accent }),
})
]])
write(root .. "/active/anything-b.cf", [[
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language
local raw = hl.raw
return l.setup("lua", {
	raw:group("ActiveLuaTwo", { fg = c.accent, italic = true }),
})
]])

write(root .. "/active/plugin-active.cf", [[
local hl = require("cf.hl.setup")
local p = hl.plugin
return p.setup("demo-plugin", {
	style_targets = { vim = true, ts = false, lsp = false },
	p:group("ActivePlugin", { bold = true }),
})
]])
write(root .. "/active/plugin-active-extra.cf", [[
local hl = require("cf.hl.setup")
local p = hl.plugin
return p.setup("demo-plugin", {
	style_targets = { vim = true, ts = false, lsp = false },
	p:group("ActivePluginExtra", { italic = true }),
})
]])

write(root .. "/active/ui-active.cf", [[
local hl = require("cf.hl.setup")
local u = hl.ui
return u.setup({
	u:group("ActiveUI", { underline = true }),
})
]])
write(root .. "/active/ui-active-extra.cf", [[
local hl = require("cf.hl.setup")
local u = hl.ui
return u.setup({
	u:group("ActiveUIExtra", { italic = true }),
})
]])

-- Same filename on both sides must not imply fallback shadowing. The setup
-- identity is different, therefore both are valid.
write(root .. "/active/shared-name.cf", [[
local hl = require("cf.hl.setup")
local p = hl.plugin
return p.setup("active-shared", {
	style_targets = { vim = true, ts = false, lsp = false },
	p:group("ActiveShared", { bold = true }),
})
]])
write(root .. "/default/shared-name.cf", [[
local hl = require("cf.hl.setup")
local p = hl.plugin
return p.setup("fallback-shared", {
	style_targets = { vim = true, ts = false, lsp = false },
	p:group("FallbackShared", { italic = true }),
})
]])

-- Active registered lua/demo-plugin/ui, so every matching fallback setup must
-- return immediately without compiling its specification.
write(root .. "/default/lua-fallback-a.cf", [[
local hl = require("cf.hl.setup")
local l = hl.language
local raw = hl.raw
return l.setup("lua", {
	raw:group("DefaultLuaShouldSkipOne", { bold = true }),
})
]])
write(root .. "/default/lua-fallback-b.cf", [[
local hl = require("cf.hl.setup")
local l = hl.language
local raw = hl.raw
return l.setup("lua", {
	style_targets = "this invalid value must never be inspected",
	raw:group("", nil),
})
]])
write(root .. "/default/plugin-demo.cf", [[
local hl = require("cf.hl.setup")
local p = hl.plugin
return p.setup("demo-plugin", {
	style_targets = { vim = true, ts = false, lsp = false },
	p:group("DefaultPluginShouldSkip", { bold = true }),
})
]])
write(root .. "/default/ui-default.cf", [[
local hl = require("cf.hl.setup")
local u = hl.ui
return u.setup({
	u:group("DefaultUIShouldSkip", { bold = true }),
})
]])

-- Active did not register python/other-plugin. Fallback registration must NOT
-- grow while compiling, therefore both modules for each uncovered identity run.
write(root .. "/default/python-a.cf", [[
local hl = require("cf.hl.setup")
local l = hl.language
local raw = hl.raw
return l.setup("python", {
	raw:group("FallbackPythonOne", { bold = true }),
})
]])
write(root .. "/default/python-b.cf", [[
local hl = require("cf.hl.setup")
local l = hl.language
local raw = hl.raw
return l.setup("python", {
	raw:group("FallbackPythonTwo", { italic = true }),
})
]])
write(root .. "/default/plugin-other-a.cf", [[
local hl = require("cf.hl.setup")
local p = hl.plugin
return p.setup("other-plugin", {
	style_targets = { vim = true, ts = false, lsp = false },
	p:group("FallbackPluginOne", { bold = true }),
})
]])
write(root .. "/default/plugin-other-b.cf", [[
local hl = require("cf.hl.setup")
local p = hl.plugin
return p.setup("other-plugin", {
	style_targets = { vim = true, ts = false, lsp = false },
	p:group("FallbackPluginTwo", { italic = true }),
})
]])

cf.setup({ theme_path = root, watch = false })
local compiled = assert(theme.current())
assert(compiled.default == "default")
assert(compiled.active == "active")
assert(compiled.requested_active == "active")
assert(compiled.config_path == root .. "/config.cf")

assert(runtime.group_style("ActiveLuaOne") ~= nil, "first active lua module did not compile")
assert(runtime.group_style("ActiveLuaTwo") ~= nil, "second active lua module was incorrectly suppressed")
assert(runtime.group_style("@cf.raw.lua") ~= nil, "raw group did not set the literal hl_group")
assert(runtime.group_style("@cf.raw.lua.lua") == nil, "raw group unexpectedly received language semantics")
assert_effective("ActivePlugin", { bold = true })
assert_effective("ActivePluginExtra", { italic = true })
assert_effective("ActiveUI", { underline = true })
assert_effective("ActiveUIExtra", { italic = true })
assert_effective("ActiveShared", { bold = true })
assert_effective("FallbackShared", { italic = true })

-- Equal styles across module identities are intentionally linked, not suppressed.
local ui_alias = vim.api.nvim_get_hl(0, { name = "ActiveUIExtra", link = true, create = false })
assert(ui_alias.link == "ActivePluginExtra", "identical UI style did not reuse the plugin style anchor")
assert(runtime.group_style("ActiveUIExtra") == nil, "UI alias entered the direct-style cache")

assert_absent("DefaultLuaShouldSkipOne")
assert_absent("DefaultLuaShouldSkipTwo")
assert_absent("DefaultPluginShouldSkip")
assert_absent("DefaultUIShouldSkip")

assert(runtime.group_style("FallbackPythonOne") ~= nil, "first uncovered fallback language module missing")
assert(runtime.group_style("FallbackPythonTwo") ~= nil, "fallback registry incorrectly grew after first python module")
assert_effective("FallbackPluginOne", { bold = true })
assert_effective("FallbackPluginTwo", { italic = true })

local active_style = assert(runtime.group_style("ActiveLuaOne"))
assert(active_style.fg == color.from_hex("#a06020"), "active module did not receive active resolved colors")

-- color.cf/config.cf are the only reserved filenames. Normal filenames carry
-- no fallback identity; l/p/u.setup(...) does.
assert(type(compiled.colors) == "table")
assert(compiled.colors.accent == color.from_hex("#a06020"))

local skipped = 0
for i = 1, #compiled.module_files do
	if compiled.module_files[i].skipped then
		skipped = skipped + 1
	end
end
assert(skipped == 4, "unexpected number of setup-identity fallback skips: " .. skipped)

vim.fn.delete(root, "rf")
print("cf.nvim theme tests: OK")
