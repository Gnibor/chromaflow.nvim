-- From the cf.nvim directory:
-- nvim --headless -u NONE -l tests/save_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local path = root .. "/lua.cf"

local source = [[
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language
return l.setup("lua", {
	mods = { deprecated = { strikethrough = true, underline = false } },
	l:group("variable", {
		fg = c.base,
		bold = true, -- keep this comment
		underline = true,
		typemods = {
			["readonly"] = { italic = true, undercurl = false },
			static = true,
		},
	}),
})
]]

local function write(data)
	local fd = assert(io.open(path, "wb"))
	assert(fd:write(data))
	fd:close()
end

local function read()
	local fd = assert(io.open(path, "rb"))
	local data = fd:read("*a")
	fd:close()
	return data
end

local function source_at(needle)
	local first = assert(source:find(needle, 1, true))
	local before = source:sub(1, first - 1)
	local line = 1
	local last_nl = 0
	for pos in before:gmatch("()\n") do
		line = line + 1
		last_nl = pos
	end
	return { file = path, line = line, col = first - last_nl }
end

write(source)
local setup_source = source_at('l.setup("lua"')
local group_source = source_at('l:group("variable"')

local base_action = {
	kind = "resolver_style",
	type_name = "variable",
	typemod = nil,
	style = { fg = 0xFF112233, bold = true, underline = true },
	_cf_source = group_source,
}
local readonly_action = {
	kind = "resolver_style",
	type_name = "variable",
	typemod = "readonly",
	style = { fg = 0xFF112233, bold = true, underline = true, italic = true, undercurl = false },
	_cf_source = group_source,
}
local static_action = {
	kind = "resolver_style",
	type_name = "variable",
	typemod = "static",
	style = { fg = 0xFF112233, bold = true, underline = true },
	_cf_source = group_source,
}
local mod_action = {
	kind = "resolver_style",
	type_name = nil,
	typemod = "deprecated",
	style = { strikethrough = true, underline = false },
	_cf_source = setup_source,
}

local edits = {
	base = { target = "base", source = group_source, action = base_action, kind = "Type", name = "variable", type_name = "variable" },
	readonly = { target = "readonly", source = group_source, action = readonly_action, kind = "TypeMod", name = "variable.readonly", type_name = "variable", typemod = "readonly" },
	static = { target = "static", source = group_source, action = static_action, kind = "TypeMod", name = "variable.static", type_name = "variable", typemod = "static" },
	mod = { target = "mod", source = setup_source, action = mod_action, kind = "Mod", name = "deprecated", typemod = "deprecated" },
}

local states = {
	base = {
		base = base_action.style,
		current = { fg = 0xFF112233, bold = false, italic = true, blend = 35, dim = true, conceal = false },
	},
	readonly = {
		base = readonly_action.style,
		current = { fg = 0xFF112233, bold = false, underline = true, undercurl = true },
	},
	static = {
		base = static_action.style,
		current = { fg = 0xFF112233, bold = false, underline = true },
	},
	mod = {
		base = mod_action.style,
		current = { underline = true },
	},
}

package.loaded["cf.picker"] = {
	_style_fields = function()
		return { "bold", "italic", "underline", "undercurl", "strikethrough", "dim", "conceal", "blend" }
	end,
	_style_edits = function() return edits end,
}
package.loaded["cf.fn.runtime"] = {
	_picker_style_state = function(target)
		return assert(states[target], "missing fake runtime state " .. tostring(target))
	end,
}
package.loaded["cf.theme"] = {
	current = function()
		return { modules = { { actions = { base_action, readonly_action, static_action, mod_action } } } }
	end,
}

package.loaded["cf.save"] = nil
local save = require("cf.save")
local plan = save.plan()
assert(plan.count == 4, "CFSave plan did not include all four confirmed style edits")
assert(#plan.files == 1 and plan.files[1].path == path, "CFSave plan did not coalesce one source file")
assert(read() == source, "CFSave plan touched disk before commit")

save.write(plan)
local saved = read()
assert(saved:find("bold = false, %-%- keep this comment"), "CFSave did not replace an existing base style in place")
assert(not saved:find("underline = true,%s*\n%stypemods"), "CFSave did not remove base underline")
assert(saved:find("italic = true"), "CFSave did not add a missing base style")
assert(saved:find("blend = 35"), "CFSave did not persist numeric blend")
assert(saved:find("dim = true"), "CFSave did not persist dim")
assert(saved:find("conceal = false"), "CFSave did not persist explicit conceal=false")
assert(saved:find('readonly"] = {[^\n]*undercurl = true'), "CFSave did not update bracket-key TypeMod style")
assert(saved:find('readonly"] = {[^\n]*bold = false'), "CFSave did not add inherited TypeMod override")
assert(not saved:find('readonly"] = {[^\n]*italic = true'), "CFSave did not remove direct TypeMod style back to inheritance")
assert(saved:find("static = { bold = false }"), "CFSave did not expand TypeMod=true into an override table")
assert(saved:find("deprecated = {[^\n]*underline = true"), "CFSave did not update module Mod style")
assert(not saved:find("deprecated = {[^\n]*strikethrough = true"), "CFSave did not remove module Mod style")
assert(loadfile(path), "CFSave wrote invalid Lua")

-- A live unset below a parent-provided Type style has no equivalent in a
-- TypeMod source table: omitting the key would inherit the parent value again.
-- CFSave therefore leaves only that field untouched while still saving other
-- representable edits from the same TypeMod.
write(source)
edits = {
	static = { target = "partial", source = group_source, action = static_action, kind = "TypeMod", name = "variable.static", type_name = "variable", typemod = "static" },
}
states.partial = {
	base = static_action.style,
	current = { fg = 0xFF112233, underline = true, italic = true }, -- inherited bold=true intentionally absent
}
local partial = save.plan()
assert(partial.count == 1 and #partial.files == 1, "CFSave dropped representable TypeMod edits beside inherited unset")
save.write(partial)
local partial_saved = read()
assert(partial_saved:find("static = { italic = true }", 1, true), "CFSave did not save representable TypeMod edit")
assert(not partial_saved:match("static = {[^\n]*bold"), "CFSave invented a value for unrepresentable inherited unset")

-- If the TypeMod already owns an override for such a field, an unrepresentable
-- live unset must not delete or rewrite that source value either.
local owned_source = source:gsub("static = true", "static = { bold = false }")
write(owned_source)
edits = {
	static = { target = "owned_unset", source = group_source, action = static_action, kind = "TypeMod", name = "variable.static", type_name = "variable", typemod = "static" },
}
states.owned_unset = {
	base = { fg = 0xFF112233, bold = false, underline = true },
	current = { fg = 0xFF112233, underline = true },
}
local skipped = save.plan()
assert(skipped.count == 0 and #skipped.files == 0, "CFSave rewrote an unrepresentable TypeMod unset")
assert(read() == owned_source, "CFSave touched an unrepresentable TypeMod unset")

write(source)

-- No runtime/base difference means no write and no reload-worthy plan.
edits = {
	base = { target = "same", source = group_source, action = base_action, kind = "Type", name = "variable", type_name = "variable" },
}
states.same = { base = base_action.style, current = base_action.style }
local empty = save.plan()
assert(empty.count == 0 and #empty.files == 0, "CFSave planned an unchanged style")

-- Adjacent inline removals share a separator when the last field has no
-- trailing comma. Removing it twice must not eat the closing brace.
source = 'return l:group("keyword", { fg = c.keyword, bold = true,italic = true})\n'
write(source)
local inline_source = source_at('l:group("keyword"')
edits = { inline = { target = "inline", source = inline_source,
  action = { kind = "resolver_style", type_name = "keyword", _cf_source = inline_source },
  kind = "Type", name = "keyword", type_name = "keyword" } }
states.inline = { base = { fg = 0xff123456, bold = true, italic = true }, current = { fg = 0xff123456 } }
local inline_plan = save.plan()
assert(load(inline_plan.files[1].content), "adjacent style removals produced invalid Lua: " .. inline_plan.files[1].content)
save.write(inline_plan)
assert(loadfile(path), "inline removal damaged closing brace")

-- Regression: the shared Mod/TypeMod source-entry writer must preserve the
-- distinction between module `mods` and group `typemods`, including when the
-- corresponding container does not exist yet.
source = [[
local hl = require("cf.hl.setup")
local l = hl.language
return l.setup("lua", {
	l:group("variable", {
		bold = true,
	}),
})
]]
write(source)
setup_source = source_at('l.setup("lua"')
group_source = source_at('l:group("variable"')

local missing_base_action = {
	kind = "resolver_style",
	type_name = "variable",
	typemod = nil,
	style = { bold = true },
	_cf_source = group_source,
}
local missing_mod_action = {
	kind = "resolver_style",
	type_name = nil,
	typemod = "deprecated",
	style = {},
	_cf_source = setup_source,
}
local missing_typemod_action = {
	kind = "resolver_style",
	type_name = "variable",
	typemod = "readonly",
	style = { bold = true },
	_cf_source = group_source,
}

edits = {
	missing_mod = {
		target = "missing_mod", source = setup_source, action = missing_mod_action,
		kind = "Mod", name = "deprecated", typemod = "deprecated",
	},
	missing_typemod = {
		target = "missing_typemod", source = group_source, action = missing_typemod_action,
		kind = "TypeMod", name = "variable.readonly", type_name = "variable", typemod = "readonly",
	},
}
states.missing_mod = { base = {}, current = { italic = true } }
states.missing_typemod = { base = missing_typemod_action.style, current = { bold = true, underline = true } }
package.loaded["cf.theme"].current = function()
	return { modules = { { actions = { missing_base_action, missing_mod_action, missing_typemod_action } } } }
end

local missing_containers = save.plan()
assert(missing_containers.count == 2 and #missing_containers.files == 1,
	"CFSave did not plan both missing Mod/TypeMod containers")
save.write(missing_containers)
local missing_saved = read()
assert(missing_saved:find('mods = { ["deprecated"] = { italic = true } }', 1, true),
	"CFSave did not create module mods container")
assert(missing_saved:find('typemods = { ["readonly"] = { underline = true } }', 1, true),
	"CFSave did not create group typemods container")
assert(loadfile(path), "missing Mod/TypeMod container rewrite produced invalid Lua")

vim.fn.delete(root, "rf")

-- Command wiring stays picker-only and does not load the save writer during
-- normal setup; the handler owns the actual save/reload lifecycle.
package.loaded["cf.picker"] = nil
package.loaded["cf.fn.runtime"] = nil
package.loaded["cf.theme"] = nil
local config = require("cf.config")
local usr_cmd = require("cf.usr_cmd")
local calls = 0
config.setup({ picker = true })
usr_cmd.setup({
	reload = function() end,
	save = function() calls = calls + 1; return 1, 1 end,
	set_theme = function() end,
	theme_menu = function() end,
})
assert(vim.fn.exists(":CFSave") == 2, "CFSave command missing in picker mode")
vim.cmd("CFSave")
assert(calls == 1, "CFSave command did not call the wired save handler")
config.setup({ picker = false })
usr_cmd.setup({
	reload = function() end,
	save = function() error("disabled CFSave was called") end,
	set_theme = function() end,
	theme_menu = function() end,
})
assert(vim.fn.exists(":CFSave") == 0, "CFSave command leaked into picker=false mode")

print("cf.nvim CFSave style writer tests: OK")
