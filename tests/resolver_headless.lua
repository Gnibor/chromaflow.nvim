vim.opt.runtimepath:prepend(vim.fn.getcwd())

local resolver = require("cf.hl.resolver")
local style = { fg = 0x123456 }
local catalog = {
	["identifier"] = "Identifier",
	["@variable"] = "@variable",
	["@lsp.type.variable"] = "@lsp.type.variable",
	["@variable.readonly"] = "@variable.readonly",
	["@lsp.typemod.variable.readonly"] = "@lsp.typemod.variable.readonly",
}

local calls = {}
local function setup(record, direct, anchor)
	direct = direct or {}
	resolver.setup_backend({
		lookup_hl = function(name) return catalog[name:lower()] end,
		group_style = function(name) return direct[name] end,
		style_target = function(value, max_layer, target_mask)
			if anchor and value == style and anchor.layer <= max_layer then
				local bit = ({ 1, 2, 4 })[anchor.layer]
				if bit and bit.band and false then end -- keep LuaLS quiet about the description below
				if require("bit").band(target_mask, bit) ~= 0 then return anchor.name end
			end
		end,
		setter = record and function(name, value, is_link)
			calls[#calls + 1] = { name, value, is_link }
			direct[name] = is_link and nil or value
		end or function() end,
	})
	return direct
end
setup(true)

local function check(type_name, typemods, expected, ft, targets, clear, explicit)
	for _ = 1, 2 do -- identical contract on cold and warm caches
		local actual = resolver.resolve(type_name, typemods, style, ft, targets, clear, explicit)
		assert(actual == expected, vim.inspect({ actual = actual, expected = expected }))
	end
end

-- Known semantic forms resolve without a fallback status.
check("variable", nil, nil)
check("variable", {}, nil)
check(nil, "readonly", nil)
check(nil, "static", nil)
check("variable", "readonly", nil)

-- Unknown types and type-owned combinations keep literal fallback. Standalone
-- modifiers can always address Neovim's @lsp.mod.<name> form, including custom
-- modifier names advertised by a server.
check("MissingType", nil, "unresolved_literal")
check(nil, "MissingMod", nil)
check("variable", "MissingMod", "unresolved_literal")
check("MissingType", "MissingMod", "unresolved_literal")
check("variable", { "readonly", "MissingMod", "static" }, "unresolved_literal")
check(nil, { "readonly", "MissingMod", "static" }, nil)
check("MissingType", {}, "unresolved_literal", "lua")

-- Explicit typemod styles own concrete TS/LSP combinations. A concrete target
-- that has to be invented is still reported as a literal fallback.
check("variable", "readonly", nil, nil, nil, nil, true)
check("variable", "static", "unresolved_literal", nil, nil, nil, true)
check("MissingType", "MissingMod", "unresolved_literal", nil, nil, nil, true)
check("variable", "MissingMod", "unresolved_literal", nil, nil, nil, true)
-- No TS/LSP target was requested here, so nothing unresolved is materialized.
check("variable", "MissingMod", nil, nil, { vim = true }, nil, true)
check("variable", "MissingMod", nil, nil, {}, { ts = true, lsp = true }, true)

local function check_link(type_name, typemod, target_type, expected)
	for _ = 1, 2 do
		assert(resolver.link(type_name, typemod, target_type) == expected)
	end
end
check_link("variable", nil, "variable", nil)
check_link("variable", nil, "MissingTarget", "unresolved_literal")
check_link("MissingType", nil, "variable", "unresolved_literal")
check_link("MissingType", nil, "MissingTarget", "unresolved_literal")
check_link(nil, "MissingMod", "MissingTarget", "unresolved_literal")
check_link("variable", "MissingMod", "MissingTarget", "unresolved_literal")

assert(resolver.clear("variable", nil) == nil)
assert(resolver.clear("MissingType", nil) == "unresolved_literal")
assert(resolver.clear(nil, "MissingMod") == nil)
assert(resolver.clear("variable", "MissingMod") == "unresolved_literal")
assert(resolver.clear("MissingType", "MissingMod") == "unresolved_literal")

-- The resolver must preserve the source hierarchy. LSP links to Tree-sitter,
-- Tree-sitter links to Vim/syntax; it must never flatten the chain itself.
calls = {}
resolver.clear_cache()
setup(true)
resolver.resolve("variable", nil, style)
assert(#calls == 3, "variable resolve did not materialize the three semantic layers")
assert(calls[1][1] == "Identifier" and calls[1][2] == style and calls[1][3] == false)
assert(calls[2][1] == "@variable" and calls[2][2] == "Identifier" and calls[2][3] == true)
assert(calls[3][1] == "@lsp.type.variable" and calls[3][2] == "@variable" and calls[3][3] == true)

calls = {}
resolver.resolve("variable", nil, style, "lua")
assert(#calls == 3, "filetype resolve did not materialize the three semantic layers")
assert(calls[1][1] == "luaIdentifier" and calls[1][2] == style and calls[1][3] == false)
assert(calls[2][1] == "@variable.lua" and calls[2][2] == "luaIdentifier" and calls[2][3] == true)
assert(calls[3][1] == "@lsp.type.variable.lua" and calls[3][2] == "@variable.lua" and calls[3][3] == true)

-- A custom LSP modifier needs no pre-existing highlight group. Tree-sitter is
-- written only when its standalone capture already exists in the catalog.
calls = {}
resolver.resolve(nil, "functionScope", style, "c", { vim = false, ts = true, lsp = true })
assert(#calls == 1 and calls[1][1] == "@lsp.mod.functionScope.c" and calls[1][2] == style)
assert(vim.deep_equal(
	resolver.runtime_style_names(nil, "functionScope", "c", { vim = false, ts = true, lsp = true }),
	{ "@lsp.mod.functionScope.c" }
))

catalog["@functionscope"] = "@functionScope"
resolver.clear_cache()
setup(true)
calls = {}
resolver.resolve(nil, "functionScope", style, "c", { vim = false, ts = true, lsp = true })
assert(#calls == 2)
assert(calls[1][1] == "@functionScope.c" and calls[1][2] == style and calls[1][3] == false)
assert(calls[2][1] == "@lsp.mod.functionScope.c" and calls[2][2] == "@functionScope.c" and calls[2][3] == true)
catalog["@functionscope"] = nil
resolver.clear_cache()
setup(true)

-- Multiple unknown mods still execute every requested literal action even though
-- the public warning result is intentionally collapsed to one status string.
calls = {}
resolver.resolve("variable", { "MissingMod", "AnotherMod" }, style)
assert(#calls == 2)
assert(calls[1][1] == "MissingMod" and calls[2][1] == "AnotherMod")
assert(calls[1][2] == style and calls[2][2] == style)
assert(calls[1][3] == false and calls[2][3] == false)

-- Target/clear masks remain independent.
calls = {}
resolver.resolve("MissingType", nil, style, "lua", { ts = true }, { vim = true, lsp = true })
assert(#calls == 3)
assert(calls[1][1] == "luaMissingType" and calls[1][2] == nil and calls[1][3] == false)
assert(calls[2][1] == "@lsp.type.MissingType.lua" and calls[2][2] == nil and calls[2][3] == false)
assert(calls[3][1] == "@MissingType.lua" and calls[3][2] == style and calls[3][3] == false)

-- Existing concrete combinations make otherwise unknown typemods resolvable.
catalog["@variable.custom"] = "@variable.custom"
resolver.clear_cache()
check("variable", "custom", nil, nil, { ts = true }, nil, true)
check("variable", "custom", "unresolved_literal", nil, nil, nil, true)
-- The language-specific concrete target does not exist yet, so materializing it
-- is correctly reported as a literal fallback.
check("variable", "custom", "unresolved_literal", "lua", { ts = true }, nil, true)

-- Cache invalidation must observe the new environment.
catalog["missingtype"] = "MissingType"
catalog["missingmod"] = "MissingMod"
resolver.clear_cache()
check("MissingType", nil, nil)
check(nil, "MissingMod", nil)
catalog["missingtype"], catalog["missingmod"] = nil, nil
resolver.clear_cache()
check("MissingType", nil, "unresolved_literal")
check(nil, "MissingMod", nil)

-- Warm resolver calls are deliberately allocation-free for the common nil/string
-- result contract. Disable the recording setter first, then disable JIT allocation
-- elision so accidental temporary tables are visible.
setup(false)
resolver.clear_cache()
jit.off()
jit.flush()
local known_list = { "readonly", "static" }
local missing_list = { "MissingMod", "AnotherMod" }
local probes = {
	function() return resolver.resolve("variable", nil, style) end,
	function() return resolver.resolve("MissingType", nil, style) end,
	function() return resolver.resolve(nil, "MissingMod", style) end,
	function() return resolver.resolve("variable", "MissingMod", style, nil, nil, nil, true) end,
	function() return resolver.resolve("variable", known_list, style) end,
	function() return resolver.resolve("variable", missing_list, style) end,
}
local function allocated_by(probe)
	probe()
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 10000 do probe() end
	local allocated = collectgarbage("count") - before
	collectgarbage("restart")
	return allocated
end
for i, probe in ipairs(probes) do
	local allocated = allocated_by(probe)
	assert(allocated < 1, ("probe %d allocated %.3f KiB on warm calls"):format(i, allocated))
end
jit.on()

print("cf.nvim resolver contract, chain and allocation tests: OK")
