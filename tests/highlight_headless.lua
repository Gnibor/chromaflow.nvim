vim.opt.runtimepath:prepend(vim.fn.getcwd())

require("cf")
local hl = require("cf.hl.setup")
local runtime = require("cf.hl.runtime")
local resolver = require("cf.hl.resolver")
local color = require("cf.color")
local config = require("cf.config")

local function link_target(name)
	local hl_value = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
	return hl_value.link
end

-- Semantic targets may reuse an existing style anchor through a Neovim link.
-- Check the visible result, not whether the target owns a direct cache entry.
local function assert_effective(name, expected)
	local actual = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
	for key, value in pairs(expected) do
		assert(actual[key] == value, name .. ": unexpected effective " .. key)
	end
end

local function assert_cleared(name)
	local actual = vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
	assert(next(actual) == nil, name .. ": unexpected style or link")
end

-- Give the resolver deterministic global roots to discover in the standalone
-- Neovim environment.
for _, name in ipairs({
	"Function", "Identifier", "Constant",
	"@function", "@function.method", "@constant", "@variable", "@variable.readonly",
	"@function.readonly", "@function.deprecated", "@function.static",
	"@lsp.type.function", "@lsp.type.method", "@lsp.type.constant", "@lsp.type.variable",
	"@lsp.mod.readonly", "@lsp.mod.deprecated", "@lsp.mod.static",
}) do
	vim.api.nvim_set_hl(0, name, {})
end
runtime.refresh_catalog()
resolver.clear_cache()

local colors = {
	bg = "#101018",
	red = "#ff4040",
	fg = "#c0c0c0",
	black = "#080808",
}
hl._begin(colors, {
	style_targets = { vim = true, ts = true, lsp = true },
})

-- The normal render boundary must pass RGB integers straight to Neovim.
-- ChromaFlow stores colours internally as 0xAARRGGBB, so only the alpha byte
-- is stripped here; converting to #RRGGBB would make nvim_set_hl() parse it
-- straight back into the same integer.
local original_set_hl = vim.api.nvim_set_hl
local rendered_rgb
vim.api.nvim_set_hl = function(ns, name, value)
	if name == "CFRenderIntegerTest" then
		rendered_rgb = value
	end
	return original_set_hl(ns, name, value)
end
local previous_alpha = config.alpha
config.alpha = false
runtime.setter("CFRenderIntegerTest", {
	fg = 0xFF123456,
	bg = 0x80445566,
	sp = 0xFF778899,
}, false)
config.alpha = previous_alpha
vim.api.nvim_set_hl = original_set_hl
assert(rendered_rgb, "RGB render was not observed")
assert(type(rendered_rgb.fg) == "number" and rendered_rgb.fg == 0x123456, "fg was not rendered as RGB integer")
assert(type(rendered_rgb.bg) == "number" and rendered_rgb.bg == 0x445566, "bg was not rendered as RGB integer")
assert(type(rendered_rgb.sp) == "number" and rendered_rgb.sp == 0x778899, "sp was not rendered as RGB integer")
runtime.setter("CFRenderIntegerTest", nil, false)

local l = hl.language
local raw = hl.raw
local before_cache = hl._style_cache_size()
local mod = l.setup("lua", {
	mods = {
		deprecated = {
			sp = colors.red,
			undercurl = true,
			pipeline = { hl.opacity.sp(75) },
		},
	},

	l:group("function", {
		fg = colors.fg,
		bold = true,
		types = { "method" },
		typemods = {
			readonly = true,
			deprecated = {
				fg = colors.black,
				pipeline = { hl.brightness.fg(10) },
			},
			static = false,
		},
	}),

	-- Same complete hl_set as function: the session style cache must intern it.
	l:group("variable", {
		fg = colors.fg,
		bold = true,
	}),
})

-- Seed a concrete typemod so `false` has something real to remove.
local stale = { fg = colors.red }
runtime.setter("@lsp.typemod.function.static.lua", stale, false)

local function_decl_style
local variable_decl_style
local readonly_decl_style
for i = 1, #mod.actions do
	local action = mod.actions[i]
	if action.kind == "resolver_style" and action.type_name == "function" and action.typemod == nil then
		function_decl_style = action.style
	elseif action.kind == "resolver_style" and action.type_name == "variable" and action.typemod == nil then
		variable_decl_style = action.style
	elseif action.kind == "resolver_style" and action.type_name == "function" and action.typemod == "readonly" then
		readonly_decl_style = action.style
	end
end
assert(function_decl_style and variable_decl_style, "base style actions missing")
assert(function_decl_style == variable_decl_style, "identical complete hl_set objects were not interned")
assert(readonly_decl_style == function_decl_style, "typemod=true did not reuse the exact group style object")

mod:apply()

local function_style = assert(runtime.group_style("luaFunction"), "luaFunction was not styled")
assert(function_style == function_decl_style, "direct function cache did not keep the interned style reference")
assert(runtime.group_style("luaIdentifier") == nil, "semantic style alias was incorrectly cached as a direct style")
assert(link_target("luaIdentifier") == "luaFunction", "identical variable style was not linked to the existing direct style anchor")

-- Additional semantic types link to the primary type's semantic chain rather
-- than receiving duplicated style objects.
assert(link_target("@function.method.lua") == "@function.lua", "TS additional group did not link to primary")
assert(link_target("@lsp.type.method.lua") == "@lsp.type.function.lua", "LSP additional group did not link to primary")

assert(runtime.group_style("@lsp.typemod.function.readonly.lua") == nil, "readonly link alias was incorrectly cached as a direct style")
local readonly_effective = vim.api.nvim_get_hl(0, { name = "@lsp.typemod.function.readonly.lua", link = false })
local function_effective = vim.api.nvim_get_hl(0, { name = "luaFunction", link = false })
assert(readonly_effective.fg == function_effective.fg and readonly_effective.bold == function_effective.bold, "typemod=true did not resolve to the group style")

local deprecated = assert(runtime.group_style("@function.deprecated.lua"), "deprecated typemod style anchor missing")
assert(deprecated ~= function_style, "typemod style table did not derive a distinct style")
assert(deprecated.fg ~= function_style.fg, "typemod pipeline did not further manipulate the group result")
assert(runtime.group_style("@lsp.typemod.function.deprecated.lua") == nil, "deprecated LSP alias was incorrectly cached as a direct style")

assert(runtime.group_style("@lsp.typemod.function.static.lua") == nil, "typemod=false did not clear the typemod")
assert(runtime.group_style("@lsp.mod.deprecated.lua") ~= nil, "module mod did not style the general mod")
assert(hl._style_cache_size() > before_cache, "style cache did not receive compiled styles")

-- Group typemod links remain independent from the group's own style.
local typemod_link_mod = l.setup("lua", {
	l:group("variable", {
		fg = colors.red,
		typemods = {
			readonly = { link = "constant" },
		},
	}),
})
typemod_link_mod:apply()
assert(link_target("@variable.readonly.lua") == "@constant.lua", "TS typemod link missing")
assert(link_target("@lsp.typemod.variable.readonly.lua") == "@lsp.type.constant.lua", "LSP typemod link missing")

-- The group itself may link while a typemod independently owns a style.
local group_link_mod = l.setup("lua", {
	l:group("method", {
		link = "function",
		typemods = {
			readonly = {
				fg = colors.black,
				italic = true,
			},
		},
	}),
})
group_link_mod:apply()
assert(link_target("@function.method.lua") == "@function.lua", "group semantic link missing")
local method_readonly = vim.api.nvim_get_hl(0, { name = "@lsp.typemod.method.readonly.lua", link = false })
assert(method_readonly.italic == true, "styled typemod on linked group missing")

-- Direct l:link() resolves both source and target semantically.
local semantic_link_mod = l.setup("lua", {
	l:link("method", "function"),
})
semantic_link_mod:apply()
assert(link_target("@function.method.lua") == "@function.lua", "l:link TS mapping missing")
assert(link_target("@lsp.type.method.lua") == "@lsp.type.function.lua", "l:link LSP mapping missing")

-- Clear is independent from targets: clear TS, then materialize Vim only.
local stale_ts = { fg = colors.red }
runtime.setter("@function.lua", stale_ts, false)
resolver.clear_cache()
local clear_mod = l.setup("lua", {
	l:group("function", {
		fg = colors.fg,
		style_targets = { vim = true, ts = false, lsp = false },
		style_targets_clear = { ts = true },
	}),
})
clear_mod:apply()
assert(runtime.group_style("@function.lua") == nil, "TS clear was incorrectly masked by style_targets")
assert(runtime.group_style("luaFunction") ~= nil, "Vim target was not materialized")

-- Config is a hard target boundary: a group cannot re-enable globally-disabled LSP.
hl._begin(colors, {
	style_targets = { vim = true, ts = true, lsp = false },
})
resolver.clear_cache()
local boundary_mod = l.setup("lua", {
	l:group("variable", {
		fg = colors.red,
		style_targets = { lsp = true },
	}),
})
runtime.setter("@lsp.type.variable.lua", nil, false)
boundary_mod:apply()
assert(runtime.group_style("@lsp.type.variable.lua") == nil, "group re-enabled an LSP target forbidden by config")

-- Plugin/UI modules use the same resolver as language modules. Plugins must
-- select their target systems explicitly; UI defaults to Vim but normal group
-- style_targets can override that default.
hl._begin(colors, {})
local p = hl.plugin
local plugin_mod = p.setup("demo-plugin", {
	style_targets = { vim = true, ts = false, lsp = false },
	p:group("DemoPlugin", {
		fg = colors.red,
		types = { "DemoPluginExtra" },
		style_targets_clear = { ts = true, lsp = true },
	}),
	p:link("PluginAlias", "DemoPlugin"),
})
runtime.setter("DemoPlugin", stale, false)
runtime.setter("@DemoPlugin", stale, false)
runtime.setter("@lsp.type.DemoPlugin", stale, false)
resolver.clear_cache()
plugin_mod:apply()
assert_effective("DemoPlugin", { fg = 0xff4040 })
assert(runtime.group_style("DemoPlugin") == nil, "plugin style alias entered the direct-style cache")
assert(link_target("DemoPlugin") == "luaIdentifier", "plugin did not reuse the existing red style anchor")
assert(runtime.group_style("@DemoPlugin") == nil, "plugin TS target was not cleared")
assert(runtime.group_style("@lsp.type.DemoPlugin") == nil, "plugin LSP target was not cleared")
assert_cleared("@DemoPlugin")
assert_cleared("@lsp.type.DemoPlugin")
assert(link_target("DemoPluginExtra") == "DemoPlugin", "plugin types[] did not resolve/link through Vim")
assert(link_target("PluginAlias") == "DemoPlugin", "p:link did not resolve through the selected Vim target")

-- A plugin may instead opt into Tree-sitter. The resolver derives the TS form
-- from the same base name; there is no separate direct plugin apply path.
runtime.setter("@demo.plugin", stale, false)
resolver.clear_cache()
local ts_plugin_mod = p.setup("demo-ts-plugin", {
	style_targets = { vim = false, ts = true, lsp = false },
	p:group("demo.plugin", { fg = colors.fg }),
})
ts_plugin_mod:apply()
assert_effective("@demo.plugin", { fg = 0xc0c0c0 })
assert(runtime.group_style("demo.plugin") == nil, "plugin TS-only module unexpectedly wrote Vim")

-- A plugin with no module target may still select targets per group.
local group_target_plugin = p.setup("demo-group-target", {
	p:group("demo.group", {
		fg = colors.black,
		style_targets = { ts = true },
	}),
})
group_target_plugin:apply()
assert_effective("@demo.group", { fg = 0x080808 })

local missing_plugin_targets = pcall(function()
	p.setup("demo-missing-targets", {
		p:group("DemoMissingTargets", { fg = colors.red }),
	})
end)
assert(not missing_plugin_targets, "plugin group unexpectedly accepted no style_targets")

local u = hl.ui
local ui_mod = u.setup({
	u:group("DemoUI", {
		fg = colors.fg,
		bg = colors.bg,
	}),
	u:group("demo.ui.capture", {
		fg = colors.red,
		style_targets = { vim = false, ts = true },
	}),
	u:link("DemoUIAlias", "DemoUI"),
})
ui_mod:apply()
assert_effective("DemoUI", { fg = 0xc0c0c0, bg = 0x101018 })
assert(runtime.group_style("@DemoUI") == nil, "UI default unexpectedly wrote Tree-sitter")
assert_effective("@demo.ui.capture", { fg = 0xff4040 })
assert(link_target("DemoUIAlias") == "DemoUI", "u:link did not use the UI Vim default")

-- raw:group() is a literal escape hatch: no resolver, no target filtering, and
-- typemods themselves are full literal hl_group names.
runtime.setter("RawRemove", stale, false)
local raw_mod = l.setup("lua", {
	raw:group("@cf.literal", {
		fg = colors.red,
		types = { "RawSecond" },
		clear = true,
		typemods = {
			["RawSame"] = true,
			["RawDerived"] = {
				fg = colors.black,
				pipeline = { hl.brightness.fg(5) },
			},
			["RawTypeModLink"] = { link = "@cf.literal" },
			["RawRemove"] = false,
		},
	}),
	raw:link("RawTopLink", "@cf.literal"),
})
raw_mod:apply()
assert(runtime.group_style("@cf.literal") ~= nil, "raw literal group missing")
assert(link_target("RawSecond") == "@cf.literal", "raw types[] did not link to primary")
assert(runtime.group_style("RawSame") == runtime.group_style("@cf.literal"), "raw typemod=true did not reuse base style")
assert(runtime.group_style("RawDerived") ~= nil, "raw typemod style missing")
assert(link_target("RawTypeModLink") == "@cf.literal", "raw typemod literal link missing")
assert(runtime.group_style("RawRemove") == nil, "raw typemod=false did not clear exact group")
assert(link_target("RawTopLink") == "@cf.literal", "raw:link missing")
assert(runtime.group_style("@cf.literal.lua") == nil, "raw group unexpectedly received language suffix")

local ok_raw_targets = pcall(function()
	l.setup("lua", {
		raw:group("BadRawTarget", {
			fg = colors.red,
			style_targets = { vim = true },
		}),
	})
end)
assert(not ok_raw_targets, "raw:group unexpectedly accepted style_targets")

-- Priority is ChromaFlow compile priority, never part of the final hl_set.
-- Higher wins; equal priority preserves declaration compile order (later wins).
local low = p.setup("priority-low", {
	raw:group("PriorityDemo", { fg = colors.red, priority = 10 }),
})
local high = p.setup("priority-high", {
	raw:group("PriorityDemo", { fg = colors.black, priority = 100 }),
})
local equal_later = p.setup("priority-equal-later", {
	raw:group("PriorityDemo", { fg = colors.fg, priority = 100 }),
})
hl._apply_modules({ equal_later, low, high })
local priority_style = assert(runtime.group_style("PriorityDemo"))
assert(priority_style.fg == color.from_hex("#c0c0c0"), "equal priority did not preserve later compile order")
assert(priority_style.priority == nil, "priority leaked into the nvim_set_hl style object")

-- A high-priority link also wins over a lower-priority style.
local priority_style_mod = p.setup("priority-style", {
	raw:group("PriorityLink", { fg = colors.red, priority = 1 }),
	raw:group("PriorityTarget", { fg = colors.black, priority = 1 }),
})
local priority_link_mod = p.setup("priority-link", {
	raw:group("PriorityLink", { link = "PriorityTarget", priority = 50 }),
})
hl._apply_modules({ priority_style_mod, priority_link_mod })
assert(link_target("PriorityLink") == "PriorityTarget", "higher-priority link did not win")
assert(runtime.group_style("PriorityLink") == nil, "linked group was incorrectly cached as a direct style")
local priority_link_effective = vim.api.nvim_get_hl(0, { name = "PriorityLink", link = false })
local priority_target_effective = vim.api.nvim_get_hl(0, { name = "PriorityTarget", link = false })
assert(priority_link_effective.fg == priority_target_effective.fg, "Neovim did not resolve the explicit link to the target style")

-- Link state is intentionally not cached. Changing the target style later must
-- be handled by Neovim while the alias remains absent from the direct-style cache.
local cache_style_a = { fg = color.from_hex("#112233") }
local cache_style_b = { fg = color.from_hex("#334455") }
runtime.setter("CacheTarget", cache_style_a, false)
runtime.setter("CacheAlias", "CacheTarget", true)
assert(runtime.group_style("CacheAlias") == nil, "link alias leaked into the direct-style cache")
runtime.setter("CacheTarget", cache_style_b, false)
assert(runtime.group_style("CacheTarget") == cache_style_b, "direct target style cache did not update")
assert(runtime.group_style("CacheAlias") == nil, "link alias gained a stale cached style after target update")
local cache_alias_effective = vim.api.nvim_get_hl(0, { name = "CacheAlias", link = false })
assert(cache_alias_effective.fg == 0x334455, "Neovim link did not follow the updated target style")

-- Useless declarations enqueue a HINT/UNNECESSARY diagnostic and no action.
-- Rendering belongs to a later flush, not the compiler's hotpath.
local diagnostic = require("cf.diagnostic")
assert(diagnostic.configure({ severity = { hint = true } }))
diagnostic.clear_pending()
local old_notify = vim.notify
local notified = false
vim.notify = function() notified = true end
local useless = p.setup("useless", {
	p:group("NothingToDo", {
		types = { "StillNothing" },
		priority = 127,
	}),
})
vim.notify = old_notify
assert(not notified, "useless group rendered UI during compilation")
local pending = diagnostic.pending()
assert(#pending == 1, "useless group did not enqueue exactly one diagnostic")
assert(pending[1].severity == diagnostic.severity.HINT, "useless group diagnostic was not HINT")
assert(vim.tbl_contains(pending[1].tags, diagnostic.tag.UNNECESSARY), "useless group diagnostic lost UNNECESSARY tag")
assert(pending[1].message:find("useless", 1, true), "unexpected diagnostic message")
assert(pending[1].source.file:match("highlight_headless%.lua$"), "diagnostic lost its real source")
assert(#useless.actions == 0, "useless group unexpectedly compiled actions")
diagnostic.clear_pending()

print("cf.nvim highlight tests: OK")
