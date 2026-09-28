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
local function setup(record)
	resolver.setup_backend({
		lookup_hl = function(name) return catalog[name:lower()] end,
		group_style = function() return nil end,
		style_target = function() return nil end,
		setter = record and function(name, value, is_link)
			calls[#calls + 1] = { name, value, is_link }
		end or function() end,
	})
end
setup(true)

local function check(type_name, mods, expected, ft, targets, clear, explicit)
	for _ = 1, 2 do -- same result on cold and warm caches
		local actual = resolver.resolve(type_name, mods, style, ft, targets, clear, explicit)
		assert(vim.deep_equal(actual, expected), vim.inspect({ actual = actual, expected = expected }))
	end
end

check("variable", nil, nil)
check("variable", {}, nil)
check(nil, "readonly", nil)
check("variable", { "readonly", "static" }, nil)
check("MissingType", nil, "type: MissingType")
check(nil, "MissingType", "typemod: MissingType")
check("MissingType", {}, "type: MissingType", "lua")
check(nil, "MissingMod", "typemod: MissingMod")
check("variable", "MissingMod", "typemod: MissingMod")
check("MissingType", "MissingMod", "type: MissingType")
check("MissingType", { "MissingMod", "AnotherMod" }, "type: MissingType")
check(nil, { "readonly", "MissingMod", "static" }, "typemod: MissingMod")
check("variable", { "readonly", "MissingMod", "static" }, "typemod: MissingMod")
local two = { "typemod: MissingMod", "typemod: AnotherMod" }
check(nil, { "MissingMod", "readonly", "AnotherMod" }, two)
check("variable", { "MissingMod", "readonly", "AnotherMod" }, two, "lua")
check(nil, { "MissingMod", "MissingMod" }, "typemod: MissingMod")
check("variable", { "MissingMod", "AnotherMod", "MissingMod", "ThirdMod", "AnotherMod" }, {
	"typemod: MissingMod", "typemod: AnotherMod", "typemod: ThirdMod",
})

-- Explicit combinations report their owner even if the free modifier exists.
check("variable", "readonly", nil, nil, nil, nil, true)
check("variable", "static", "typemod: variable.static", nil, nil, nil, true)
check("MissingType", "MissingMod", "typemod: MissingType.MissingMod", nil, nil, nil, true)
check("variable", "readonly", "typemod: variable.readonly", "lua", nil, nil, true)
check("variable", "MissingMod", nil, nil, { vim = true }, nil, true)
check("variable", "MissingMod", nil, nil, {}, { ts = true, lsp = true }, true)

local function check_link(type_name, modifier, target_type, expected)
	for _ = 1, 2 do
		local actual = resolver.link(type_name, modifier, target_type)
		assert(vim.deep_equal(actual, expected), vim.inspect({ actual = actual, expected = expected }))
	end
end
check_link("variable", nil, "variable", nil)
check_link("variable", nil, "MissingTarget", "type: MissingTarget")
check_link("MissingType", nil, "variable", "type: MissingType")
check_link("MissingType", nil, "MissingTarget", { "type: MissingType", "type: MissingTarget" })
check_link("MissingType", nil, "MissingType", "type: MissingType")
check_link(nil, "MissingMod", "MissingTarget", { "typemod: MissingMod", "type: MissingTarget" })
check_link("variable", "MissingMod", "MissingTarget", { "typemod: MissingMod", "type: MissingTarget" })
assert(resolver.clear("variable", nil) == nil)
assert(resolver.clear("MissingType", nil) == "type: MissingType")
assert(resolver.clear(nil, "MissingMod") == "typemod: MissingMod")
assert(resolver.clear("variable", "MissingMod") == "typemod: MissingMod")
assert(resolver.clear("MissingType", "MissingMod") == "type: MissingType")

-- Only a selected missing target causes an explicit-combination hint.
catalog["@variable.static"] = "@variable.static"
resolver.clear_cache()
check("variable", "static", nil, nil, { ts = true }, nil, true)
check("variable", "static", "typemod: variable.static", nil, { lsp = true }, nil, true)
catalog["@lsp.typemod.variable.static"] = "@lsp.typemod.variable.static"
resolver.clear_cache()
check("variable", "static", nil, nil, nil, nil, true)

-- Lists belong to the caller: mutating a returned list cannot poison caches.
local mods = { "MissingMod", "AnotherMod" }
local first = resolver.resolve("variable", mods, style)
first[1] = "changed by caller"
local second = resolver.resolve("variable", mods, style)
assert(first ~= second and vim.deep_equal(second, two))

-- Hint aggregation must preserve every setter call, its order and style identity.
calls = {}
resolver.resolve("variable", mods, style)
assert(#calls == 2)
assert(calls[1][1] == "MissingMod" and calls[2][1] == "AnotherMod")
assert(calls[1][2] == style and calls[2][2] == style)
assert(calls[1][3] == false and calls[2][3] == false)
calls = {}
resolver.resolve("MissingType", nil, style, "lua", { ts = true }, { vim = true, lsp = true })
assert(#calls == 3)
assert(calls[1][1] == "luaMissingType" and calls[1][2] == nil and calls[1][3] == false)
assert(calls[2][1] == "@lsp.type.MissingType.lua" and calls[2][2] == nil and calls[2][3] == false)
assert(calls[3][1] == "@MissingType.lua" and calls[3][2] == style and calls[3][3] == false)

-- Invalidation must discard old literal hints when the environment changes.
catalog["missingtype"] = "MissingType"
catalog["missingmod"] = "MissingMod"
resolver.clear_cache()
check("MissingType", nil, nil)
check(nil, "MissingMod", nil)
catalog["missingtype"], catalog["missingmod"] = nil, nil
setup(false)
check("MissingType", nil, "type: MissingType")
check(nil, "MissingMod", "typemod: MissingMod")

-- Disable JIT allocation elision and GC: a temporary table would accumulate
-- even if discarded before return. Inputs and resolver caches are prebuilt.
jit.off()
jit.flush()
local probes = {
	function() return resolver.resolve("variable", nil, style) end,
	function() return resolver.resolve("MissingType", nil, style) end,
	function() return resolver.resolve(nil, "MissingMod", style) end,
	function() return resolver.resolve("variable", "MissingMod", style, nil, nil, nil, true) end,
}
for _, owner in ipairs({ false, "variable", "MissingType" }) do
	for _, list in ipairs({ { "readonly", "static" }, { "MissingMod" }, { "readonly", "MissingMod" }, { "MissingMod", "MissingMod" } }) do
		probes[#probes + 1] = function() return resolver.resolve(owner or nil, list, style) end
	end
end
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
	assert(allocated < 1, ("probe %d allocated %.3f KiB on warm zero/single-hint calls"):format(i, allocated))
end
local expected = allocated_by(function() return { two[1], two[2] } end)
local actual = allocated_by(function() return resolver.resolve("variable", mods, style) end)
assert(math.abs(actual - expected) < 1, "multiple hints must allocate exactly one result table per call")
jit.on()
print("cf.nvim resolver hints and allocation tests: OK")
