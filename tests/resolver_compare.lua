-- Differential regression test against a saved resolver before the change:
-- CF_RESOLVER_REFERENCE=/path/to/original/resolver.lua nvim --headless -u NONE -l tests/resolver_compare.lua
local reference = assert(vim.env.CF_RESOLVER_REFERENCE, "set CF_RESOLVER_REFERENCE to the original resolver.lua")
local before = dofile(reference)
local after = dofile("lua/cf/hl/resolver.lua")
local band = require("bit").band
local style = { fg = 0x123456 }
local other_style = { fg = 0x654321 }
local cases = 0

local function layer(name)
	return name:sub(1, 5) == "@lsp." and 3 or name:sub(1, 1) == "@" and 2 or 1
end

local function backend(catalog, anchor_layer)
	local operations, direct = {}, {}
	local anchor = ({ "Anchor", "@anchor", "@lsp.type.anchor" })[anchor_layer]
	if anchor then direct[anchor] = style end
	return {
		lookup_hl = function(name) return catalog[name:lower()] end,
		group_style = function(name) return direct[name] end,
		style_target = function(value, max_layer, mask)
			if value == style and anchor and anchor_layer <= max_layer and band(mask, 2 ^ (anchor_layer - 1)) ~= 0 then
				return anchor
			end
		end,
		setter = function(name, value, is_link)
			operations[#operations + 1] = { name, value, is_link }
			direct[name] = not is_link and value or nil
		end,
	}, operations
end

local names = {
	"Function", "Identifier", "Type", "@function", "@variable", "@type", "@function.method",
	"@lsp.type.function", "@lsp.type.variable", "@lsp.type.method", "@lsp.type.enumMember",
	"@lsp.mod.readonly", "@lsp.mod.defaultLibrary", "@variable.readonly", "@function.builtin",
	"@lsp.typemod.variable.readonly", "@lsp.typemod.function.defaultLibrary",
	"luaFunction", "@function.lua", "@variable.readonly.lua", "@lsp.typemod.variable.readonly.lua",
}
local masks = { false }
for value = 0, 7 do
	masks[#masks + 1] = { vim = band(value, 1) ~= 0, ts = band(value, 2) ~= 0, lsp = band(value, 4) ~= 0 }
end
local mods = { false, "readonly", "builtin", "MissingMod", {}, { "readonly", "static" },
	{ "MissingMod", "readonly", "AnotherMod" }, { "MissingMod", "MissingMod" } }

for catalog_kind = 1, 3 do
	local catalog = {}
	for i, name in ipairs(names) do
		if catalog_kind == 1 or (catalog_kind == 2 and i % 2 == 0) then catalog[name:lower()] = name end
	end
	for anchor_layer = 0, 3 do
		local old_backend, old_ops = backend(catalog, anchor_layer)
		local new_backend, new_ops = backend(catalog, anchor_layer)
		before.setup_backend(old_backend)
		after.setup_backend(new_backend)
		local function compare(method, ...)
			cases = cases + 1
			if cases % 17 == 0 then before.clear_cache(); after.clear_cache() end
			for i = #old_ops, 1, -1 do old_ops[i] = nil end
			for i = #new_ops, 1, -1 do new_ops[i] = nil end
			local old_hint = before[method](...)
			local new_hint = after[method](...)
			assert((old_hint ~= nil) == (new_hint ~= nil), method .. ": changed hint presence at case " .. cases)
			assert(#old_ops == #new_ops, method .. ": changed setter count at case " .. cases)
			for i = 1, #old_ops do
				for field = 1, 3 do
					assert(old_ops[i][field] == new_ops[i][field], method .. ": changed setter name/value/identity/order at case " .. cases)
				end
			end
		end
		for _, type_name in ipairs({ false, "function", "variable", "method", "class", "enummember", "MissingType" }) do
			for _, modifier in ipairs(mods) do
				if type_name or (modifier and (type(modifier) == "string" or #modifier > 0)) then
					for _, ft in ipairs({ false, "lua" }) do
						for _, targets in ipairs(masks) do
							for _, clear in ipairs(masks) do
								for _, explicit in ipairs({ false, true }) do
									compare("resolve", type_name or nil, modifier or nil, style, ft or nil, targets or nil, clear or nil, explicit)
									-- Repeat with another style to exercise setter and link transitions.
									compare("resolve", type_name or nil, modifier or nil, other_style, ft or nil, targets or nil, clear or nil, explicit)
								end
								if type(modifier) ~= "table" then
									compare("link", type_name or nil, modifier or nil, "MissingTarget", ft or nil, targets or nil, clear or nil)
									compare("clear", type_name or nil, modifier or nil, ft or nil, clear or nil)
									local args = { type_name or nil, modifier or nil, ft or nil, targets or nil, clear or nil, true }
									assert(vim.deep_equal(before.runtime_style_names(unpack(args, 1, 6)), after.runtime_style_names(unpack(args, 1, 6))))
								end
							end
						end
					end
				end
			end
		end
	end
end
print(("cf.nvim resolver differential tests: %d calls with identical setter operations and hint presence: OK"):format(cases))
