local M = {}

--[[
Internal hl_group resolver.

The engine owns the hl_group/style caches and provides the backend. This module
only caches the *results of its own name resolution* so repeated calls do not
rebuild candidate strings or repeat environment lookups.

Style objects are owned by the external cache. This module only reads them and
passes the original reference to the setter; it never mutates or copies them.

Backend contract:
  lookup_hl(name) -> canonical_name|nil
      Case-insensitive lookup in the already-built environment hl_group cache.

  group_style(name) -> style_object|nil
      Returns only a directly materialized cached style object for `name`.
      Linked groups deliberately return nil; link state is not cached here.

  style_target(style, max_layer, target_mask) -> hl_group|nil
      Returns an already-materialized hl_group for exactly this style from an
      enabled layer <= max_layer. Layers: 1=Vim/Nvim, 2=Tree-sitter, 3=LSP.
      target_mask uses bits 1=Vim/Nvim, 2=Tree-sitter, 4=LSP.

  setter(name, value, is_link)
      Executes exactly the operation chosen by the resolver.
      is_link == false, value == nil: clear this hl_group.
      is_link == false, value ~= nil: set the cached style object.
      is_link == true: value is the target hl_group name.
      The setter performs no resolution or policy decisions.
]]

local lookup_hl = function(_)
	return nil
end

local group_style = function(_)
	return nil
end

local style_target = function(_, _)
	return nil
end

local setter = function(_, _, _)
end

-- Resolver-owned caches. They contain no styles and no hl_group catalog, only
-- the result of already performed resolution work.
local type_cache = {}
local mod_cache = {}
local typemod_cache = {}
local literal_cache = {}

-- Filetype variants are derived exclusively from the already-resolved generic
-- hl_group names. They never perform semantic resolution on their own.
local type_ft_cache = {}
local mod_ft_cache = {}
local typemod_ft_cache = {}

-- Unknown types still get a complete literal Vim/TS/LSP chain.
local literal_type_cache = {}
local literal_type_ft_cache = {}

-- Explicit typemod styles own the concrete type+typemod combination.
-- These caches keep those literal TS/LSP names separate from the normal
-- typemod cache, whose fallback semantics are intentionally unchanged.
local literal_typemod_cache = {}
local literal_typemod_ft_cache = {}

local function clear_table(t)
	for k in pairs(t) do
		t[k] = nil
	end
end

function M.clear_cache()
	clear_table(type_cache)
	clear_table(mod_cache)
	clear_table(typemod_cache)
	clear_table(literal_cache)
	clear_table(type_ft_cache)
	clear_table(mod_ft_cache)
	clear_table(typemod_ft_cache)
	clear_table(literal_type_cache)
	clear_table(literal_type_ft_cache)
	clear_table(literal_typemod_cache)
	clear_table(literal_typemod_ft_cache)
end

function M.setup_backend(backend)
	if not backend then
		return
	end

	if backend.lookup_hl then
		lookup_hl = backend.lookup_hl
	end
	if backend.group_style then
		group_style = backend.group_style
	end
	if backend.style_target then
		style_target = backend.style_target
	end
	if backend.setter then
		setter = backend.setter
	end

	-- Cached canonical names belong to the old backend/environment.
	M.clear_cache()
end

-- Only real naming deviations belong here. The environment cache still has to
-- confirm that a candidate hl_group exists.
local TYPE_MAP = {
	class = { ts = "type", ts_writable = false },
	enum = { ts = "type", ts_writable = false },
	interface = { ts = "type", ts_writable = false },
	method = { vim = "Function", vim_writable = false, ts = "function.method" },
	modifier = { ts = "keyword.modifier", ts_writable = false },
	namespace = { ts = "module" },
	parameter = { vim = "Identifier", vim_writable = false, ts = "variable.parameter" },
	regexp = { ts = "string.regexp" },
	struct = { ts = "type", ts_writable = false },
	variable = { vim = "Identifier" },
}

local LSP_TYPE_TOKEN = {
	enummember = "enumMember",
	typeparameter = "typeParameter",
}

local TYPEMOD_MAP = {
	builtin = { ts = "builtin", lsp = "defaultLibrary" },
	defaultlibrary = { ts = "builtin", lsp = "defaultLibrary" },
}

local function unique_mapped_semantic(map, field, token)
	local found
	for semantic, spec in pairs(map) do
		if spec[field] == token then
			if found and found ~= semantic then
				return nil
			end
			found = semantic
		end
	end
	return found
end

-- Convert source-specific tokens back to the semantic spelling used by the DSL.
-- This is naming knowledge only; it does not resolve or materialize highlights.
function M.semantic_type_token(source, token)
	if type(token) ~= "string" or token == "" then
		return nil
	end

	token = token:gsub("^@", "")
	if source == "lsp" then
		token = token:gsub("^lsp%.type%.", "")
		for semantic, lsp_token in pairs(LSP_TYPE_TOKEN) do
			if lsp_token == token then
				return semantic
			end
		end
		return token
	end

	if source == "ts" then
		local mapped = unique_mapped_semantic(TYPE_MAP, "ts", token)
		if mapped then
			return mapped
		end
		return token:match("([^.]+)$") or token
	end

	return token
end

function M.semantic_typemod_token(source, token)
	if type(token) ~= "string" or token == "" then
		return nil
	end

	token = token:gsub("^@", "")
	if source == "lsp" then
		token = token:gsub("^lsp%.mod%.", "")
		return unique_mapped_semantic(TYPEMOD_MAP, "lsp", token) or token:lower()
	end

	if source == "ts" then
		return unique_mapped_semantic(TYPEMOD_MAP, "ts", token)
			or token:match("([^.]+)$")
			or token
	end

	return token
end

local function known_lsp_modifier(name)
	return name == "abstract"
		or name == "async"
		or name == "declaration"
		or name == "definition"
		or name == "deprecated"
		or name == "documentation"
		or name == "modification"
		or name == "readonly"
		or name == "static"
end

local bit = require("bit")
local band = bit.band

local TARGET_VIM = 1
local TARGET_TS = 2
local TARGET_LSP = 4
local TARGET_ALL = 7

local function resolve_masks(targets, clear)
	local target_mask

	if targets == nil then
		target_mask = TARGET_ALL
	else
		target_mask = 0
		if targets.vim then target_mask = target_mask + TARGET_VIM end
		if targets.ts then target_mask = target_mask + TARGET_TS end
		if targets.lsp then target_mask = target_mask + TARGET_LSP end
	end

	local clear_mask = 0
	if clear ~= nil then
		if clear.vim then clear_mask = clear_mask + TARGET_VIM end
		if clear.ts then clear_mask = clear_mask + TARGET_TS end
		if clear.lsp then clear_mask = clear_mask + TARGET_LSP end
	end

	return target_mask, clear_mask
end

local function layer_bit(layer)
	if layer == 1 then return TARGET_VIM end
	if layer == 2 then return TARGET_TS end
	return TARGET_LSP
end

-- Cache entry layouts are deliberately positional and persistent. No temporary
-- result table is allocated on a cache hit.
--
-- type_cache[type]:
--   1 vim_name|false
--   2 vim_writable
--   3 ts_name|false
--   4 ts_writable
--   5 lsp_type_name|false
--   6 ts_token
--   7 lsp_type_token
--   8 known
--
-- mod_cache[typemod]:
--   1 vim_name|false
--   2 ts_name|false
--   3 lsp_mod_name
--   4 ts_token
--   5 lsp_mod_token
--   6 known (standalone LSP modifiers are always addressable)
--   7 known_lsp_typemod_component (preserves TypeMod fallback rules)
--
-- typemod_cache[type][typemod]:
--   1 ts_typemod_name|false
--   2 lsp_typemod_name|false

local function apply3(n1, w1, n2, w2, n3, w3, style, target_mask, clear_mask)
	-- Clear is intentionally independent from target selection. A theme may
	-- clear a system without setting it again afterwards. Broad fallback groups
	-- marked non-writable are never cleared here because this resolve would not
	-- set them either.
	if band(clear_mask, TARGET_VIM) ~= 0 and n1 and w1 then
		setter(n1, nil, false)
	end
	if band(clear_mask, TARGET_TS) ~= 0 and n2 and w2 then
		setter(n2, nil, false)
	end
	if band(clear_mask, TARGET_LSP) ~= 0 and n3 and w3 then
		setter(n3, nil, false)
	end

	if target_mask == 0 then
		return true
	end

	local use1 = band(target_mask, TARGET_VIM) ~= 0
	local use2 = band(target_mask, TARGET_TS) ~= 0
	local use3 = band(target_mask, TARGET_LSP) ~= 0

	local anchor
	local start = 1

	if use1 and n1 and group_style(n1) == style then
		anchor = n1
		start = 2
	elseif use2 and n2 and group_style(n2) == style then
		anchor = n2
		start = 3
	elseif use3 and n3 and group_style(n3) == style then
		return true
	end

	if not anchor then
		local base
		local base_layer

		if use1 and n1 and w1 then
			base = n1
			base_layer = 1
			start = 2
		elseif use2 and n2 and w2 then
			base = n2
			base_layer = 2
			start = 3
		elseif use3 and n3 and w3 then
			base = n3
			base_layer = 3
			start = 4
		else
			return false
		end

		local target = style_target(style, base_layer, target_mask)

		if target and target ~= base then
			setter(base, target, true)
		else
			setter(base, style, false)
		end

		anchor = base
	end

	if start <= 2 and use2 and n2 then
		if w2 then
			if n2 ~= anchor then
				setter(n2, anchor, true)
			end
			anchor = n2
		elseif group_style(n2) == style then
			anchor = n2
		end
	end

	if start <= 3 and use3 and n3 then
		if w3 then
			if n3 ~= anchor then
				setter(n3, anchor, true)
			end
		elseif group_style(n3) == style then
			anchor = n3
		end
	end

	return true
end

local function apply2(n1, w1, layer1, bit1, n2, w2, bit2, style, target_mask, clear_mask)
	if band(clear_mask, bit1) ~= 0 and n1 and w1 then
		setter(n1, nil, false)
	end
	if band(clear_mask, bit2) ~= 0 and n2 and w2 then
		setter(n2, nil, false)
	end

	local use1 = band(target_mask, bit1) ~= 0
	local use2 = band(target_mask, bit2) ~= 0

	-- This semantic pair has no representation in any requested target. Clear
	-- operations above still ran, which is exactly what the caller asked for.
	if not use1 and not use2 then
		return true
	end

	local anchor

	if use1 and n1 and group_style(n1) == style then
		anchor = n1
	elseif use2 and n2 and group_style(n2) == style then
		return true
	end

	if not anchor then
		local base
		local base_layer

		if use1 and n1 and w1 then
			base = n1
			base_layer = layer1
		elseif use2 and n2 and w2 then
			base = n2
			base_layer = 3
		else
			return false
		end

		local target = style_target(style, base_layer, target_mask)

		if target and target ~= base then
			setter(base, target, true)
		else
			setter(base, style, false)
		end

		anchor = base

		if base == n2 then
			return true
		end
	end

	if use2 and n2 and w2 and n2 ~= anchor then
		setter(n2, anchor, true)
	end

	return true
end

local function hl_layer(name)
	if string.byte(name, 1) ~= 64 then -- @
		return 1
	end

	if string.byte(name, 2) == 108 -- l
		and string.byte(name, 3) == 115 -- s
		and string.byte(name, 4) == 112 -- p
		and string.byte(name, 5) == 46 -- .
	then
		return 3
	end

	return 2
end

local function literal(name, style, target_mask, clear_mask)
	local cached = literal_cache[name]
	local target
	local layer

	if cached then
		target = cached[1]
		layer = cached[2]
	else
		target = lookup_hl(name) or name
		layer = hl_layer(target)
		literal_cache[name] = { target, layer }
	end

	local bit_for_layer = layer_bit(layer)

	if band(clear_mask, bit_for_layer) ~= 0 then
		setter(target, nil, false)
	end

	if band(target_mask, bit_for_layer) ~= 0 and group_style(target) ~= style then
		local existing = style_target(style, layer, target_mask)

		if existing and existing ~= target then
			setter(target, existing, true)
		else
			setter(target, style, false)
		end
	end

	return "unresolved_literal"
end

local function literal_type_entry(type_name)
	local cached = literal_type_cache[type_name]
	if cached then
		return cached
	end

	local vim_name = lookup_hl(type_name) or type_name
	local ts_candidate = "@" .. type_name
	local ts_name = lookup_hl(ts_candidate) or ts_candidate
	local lsp_candidate = "@lsp.type." .. type_name
	local lsp_name = lookup_hl(lsp_candidate) or lsp_candidate

	cached = {
		vim_name,
		true,
		ts_name,
		true,
		lsp_name,
		true,
	}
	literal_type_cache[type_name] = cached
	return cached
end

local function filetype_name(name, filetype, vim_prefix)
	local candidate
	if vim_prefix then
		candidate = filetype .. name
	else
		candidate = name .. "." .. filetype
	end

	-- Existing language-specific groups keep the environment's canonical name.
	-- Missing ones are still valid output targets and are created as written.
	return lookup_hl(candidate) or candidate
end

local function literal_type_ft_entry(type_name, filetype, t)
	local by_type = literal_type_ft_cache[type_name]
	if not by_type then
		by_type = {}
		literal_type_ft_cache[type_name] = by_type
	else
		local cached = by_type[filetype]
		if cached then
			return cached
		end
	end

	local cached = {
		filetype_name(t[1], filetype, true),
		true,
		filetype_name(t[3], filetype, false),
		true,
		filetype_name(t[5], filetype, false),
		true,
	}
	by_type[filetype] = cached
	return cached
end

local function literal_type(type_name, style, filetype, target_mask, clear_mask)
	local t = literal_type_entry(type_name)

	if filetype then
		t = literal_type_ft_entry(type_name, filetype, t)
	end

	apply3(t[1], t[2], t[3], t[4], t[5], t[6], style, target_mask, clear_mask)
	return "unresolved_literal"
end

local function literal_typemod_entry(type_name, typemod, t, q)
	local by_type = literal_typemod_cache[type_name]
	if not by_type then
		by_type = {}
		literal_typemod_cache[type_name] = by_type
	else
		local cached = by_type[typemod]
		if cached then
			return cached
		end
	end

	-- A concrete type+typemod request is authoritative. The base type does
	-- not need to exist as its own hl_group; only the naming tokens matter.
	local ts_candidate = "@" .. t[6] .. "." .. q[4]
	local ts_existing = lookup_hl(ts_candidate)

	local lsp_candidate = "@lsp.typemod." .. t[7] .. "." .. q[5]
	local lsp_existing = lookup_hl(lsp_candidate)

	local cached = {
		ts_existing or ts_candidate,
		lsp_existing or lsp_candidate,
		ts_existing ~= nil,
		lsp_existing ~= nil,
	}
	by_type[typemod] = cached
	return cached
end

local function literal_typemod_ft_entry(type_name, typemod, filetype, tm)
	local by_type = literal_typemod_ft_cache[type_name]
	if not by_type then
		by_type = {}
		literal_typemod_ft_cache[type_name] = by_type
	end

	local by_typemod = by_type[typemod]
	if not by_typemod then
		by_typemod = {}
		by_type[typemod] = by_typemod
	else
		local cached = by_typemod[filetype]
		if cached then
			return cached
		end
	end

	local ts_candidate = tm[1] .. "." .. filetype
	local ts_existing = lookup_hl(ts_candidate)
	local lsp_candidate = tm[2] .. "." .. filetype
	local lsp_existing = lookup_hl(lsp_candidate)

	local cached = {
		ts_existing or ts_candidate,
		lsp_existing or lsp_candidate,
		ts_existing ~= nil,
		lsp_existing ~= nil,
	}
	by_typemod[filetype] = cached
	return cached
end


local function type_entry(type_name)
	local cached = type_cache[type_name]
	if cached then
		return cached
	end

	local map = TYPE_MAP[type_name]

	local vim_candidate = map and map.vim or type_name
	local vim_name = lookup_hl(vim_candidate)
	local vim_writable = map == nil or map.vim_writable ~= false

	local ts_token = map and map.ts or type_name
	local ts_name = lookup_hl("@" .. ts_token)
	local ts_writable = map == nil or map.ts_writable ~= false

	local lsp_token = LSP_TYPE_TOKEN[type_name] or type_name
	local lsp_name = lookup_hl("@lsp.type." .. lsp_token)

	cached = {
		vim_name or false,
		vim_writable,
		ts_name or false,
		ts_writable,
		lsp_name or false,
		ts_token,
		lsp_token,
		vim_name ~= nil or ts_name ~= nil or lsp_name ~= nil,
	}
	type_cache[type_name] = cached
	return cached
end

local function mod_entry(typemod)
	local cached = mod_cache[typemod]
	if cached then
		return cached
	end

	local map = TYPEMOD_MAP[typemod]
	local ts_token = map and map.ts or typemod
	local lsp_token = map and map.lsp or typemod

	local vim_name = lookup_hl(typemod)
	local ts_name = lookup_hl("@" .. ts_token)

	local lsp_candidate = "@lsp.mod." .. lsp_token
	local lsp_existing = lookup_hl(lsp_candidate)
	-- Servers may advertise custom semantic-token modifiers. Neovim names
	-- their standalone groups @lsp.mod.<token> even before a highlight exists.
	local lsp_name = lsp_existing or lsp_candidate
	local lsp_typemod_known = lsp_existing ~= nil or map ~= nil or known_lsp_modifier(typemod)

	cached = {
		vim_name or false,
		ts_name or false,
		lsp_name or false,
		ts_token,
		lsp_token,
		true,
		lsp_typemod_known,
	}
	mod_cache[typemod] = cached
	return cached
end

local function resolve_literal_typemod(
	type_name,
	typemod,
	style,
	t,
	filetype,
	target_mask,
	clear_mask
)
	local q = mod_entry(typemod)
	local tm = literal_typemod_entry(type_name, typemod, t, q)
	if filetype then
		tm = literal_typemod_ft_entry(type_name, typemod, filetype, tm)
	end

	local applied = apply2(
		tm[1], true, 2, TARGET_TS,
		tm[2], true, TARGET_LSP,
		style, target_mask, clear_mask
	)

	-- Existing concrete combinations are normal resolution. Only a requested
	-- target that had to be materialized is an unresolved-literal warning.
	local unresolved = not applied
		or (band(target_mask, TARGET_TS) ~= 0 and not tm[3])
		or (band(target_mask, TARGET_LSP) ~= 0 and not tm[4])

	return unresolved and "unresolved_literal" or nil
end

local function typemod_entry(type_name, typemod, t, q)
	local by_type = typemod_cache[type_name]
	if not by_type then
		by_type = {}
		typemod_cache[type_name] = by_type
	else
		local cached = by_type[typemod]
		if cached then
			return cached
		end
	end

	local ts_typemod
	local ts_name = t[3]
	if ts_name then
		-- Concrete Tree-sitter combinations are never invented.
		ts_typemod = lookup_hl(ts_name .. "." .. q[4])
	end

	local lsp_typemod
	if t[5] and q[7] then
		-- Once both LSP components are real, typemod spelling is deterministic.
		local candidate = "@lsp.typemod." .. t[7] .. "." .. q[5]
		lsp_typemod = lookup_hl(candidate) or candidate
	end

	local cached = {
		ts_typemod or false,
		lsp_typemod or false,
	}
	by_type[typemod] = cached
	return cached
end

local function type_ft_entry(type_name, filetype, t)
	local by_type = type_ft_cache[type_name]
	if not by_type then
		by_type = {}
		type_ft_cache[type_name] = by_type
	else
		local cached = by_type[filetype]
		if cached then
			return cached
		end
	end

	local vim_name = t[1] and filetype_name(t[1], filetype, true) or false
	local ts_name = t[3] and filetype_name(t[3], filetype, false) or false
	local lsp_name = t[5] and filetype_name(t[5], filetype, false) or false

	local cached = {
		vim_name,
		t[2],
		ts_name,
		t[4],
		lsp_name,
		true,
	}
	by_type[filetype] = cached
	return cached
end

local function mod_ft_entry(typemod, filetype, q)
	local by_typemod = mod_ft_cache[typemod]
	if not by_typemod then
		by_typemod = {}
		mod_ft_cache[typemod] = by_typemod
	else
		local cached = by_typemod[filetype]
		if cached then
			return cached
		end
	end

	local vim_name = q[1] and filetype_name(q[1], filetype, true) or false
	local ts_name = q[2] and filetype_name(q[2], filetype, false) or false
	local lsp_name = q[3] and filetype_name(q[3], filetype, false) or false

	local cached = {
		vim_name,
		true,
		ts_name,
		true,
		lsp_name,
		true,
	}
	by_typemod[filetype] = cached
	return cached
end

local function typemod_ft_entry(type_name, typemod, filetype, tm)
	local by_type = typemod_ft_cache[type_name]
	if not by_type then
		by_type = {}
		typemod_ft_cache[type_name] = by_type
	end

	local by_typemod = by_type[typemod]
	if not by_typemod then
		by_typemod = {}
		by_type[typemod] = by_typemod
	else
		local cached = by_typemod[filetype]
		if cached then
			return cached
		end
	end

	local ts_name = tm[1] and filetype_name(tm[1], filetype, false) or false
	local lsp_name = tm[2] and filetype_name(tm[2], filetype, false) or false

	local cached = {
		ts_name,
		lsp_name,
	}
	by_typemod[filetype] = cached
	return cached
end

local function resolve_type(type_name, style, filetype, target_mask, clear_mask)
	local t = type_entry(type_name)

	if not t[8] then
		return literal_type(type_name, style, filetype, target_mask, clear_mask)
	end

	if filetype then
		local ft = type_ft_entry(type_name, filetype, t)
		apply3(ft[1], ft[2], ft[3], ft[4], ft[5], ft[6], style, target_mask, clear_mask)
		return nil
	end

	if apply3(t[1], t[2], t[3], t[4], t[5], true, style, target_mask, clear_mask) then
		return nil
	end

	return literal_type(type_name, style, nil, target_mask, clear_mask)
end

local function resolve_mod(typemod, style, filetype, target_mask, clear_mask)
	local q = mod_entry(typemod)

	if q[6] then
		if filetype then
			local ft = mod_ft_entry(typemod, filetype, q)
			apply3(ft[1], ft[2], ft[3], ft[4], ft[5], ft[6], style, target_mask, clear_mask)
			return nil
		end

		if apply3(q[1], true, q[2], true, q[3], true, style, target_mask, clear_mask) then
			return nil
		end
	end

	return literal(typemod, style, target_mask, clear_mask)
end

local function resolve_typemod_cached(
	type_name,
	typemod,
	style,
	t,
	filetype,
	target_mask,
	clear_mask,
	typemod_style
)
	if typemod_style then
		return resolve_literal_typemod(
			type_name, typemod, style, t, filetype, target_mask, clear_mask
		)
	end

	if not t[8] then
		return literal_type(type_name, style, filetype, target_mask, clear_mask)
	end

	local q = mod_entry(typemod)
	local tm = typemod_entry(type_name, typemod, t, q)
	local ts_typemod = tm[1]
	local lsp_typemod = tm[2]

	if ts_typemod or lsp_typemod then
		if filetype then
			local ft = typemod_ft_entry(type_name, typemod, filetype, tm)
			apply2(
				ft[1], true, 2, TARGET_TS,
				ft[2], true, TARGET_LSP,
				style, target_mask, clear_mask
			)
			return nil
		end

		if apply2(
			ts_typemod, true, 2, TARGET_TS,
			lsp_typemod, true, TARGET_LSP,
			style, target_mask, clear_mask
		) then
			return nil
		end
	end

	return literal(typemod, style, target_mask, clear_mask)
end

local function resolve_typemod(
	type_name,
	typemod,
	style,
	filetype,
	target_mask,
	clear_mask,
	typemod_style
)
	return resolve_typemod_cached(
		type_name,
		typemod,
		style,
		type_entry(type_name),
		filetype,
		target_mask,
		clear_mask,
		typemod_style
	)
end


-- Return the concrete semantic source chain without applying a style. The
-- layouts mirror apply3(): name,writable pairs for Vim/TS/LSP. When the
-- existing resolver would fall back to one literal name, `literal_name` is
-- returned instead so link/clear semantics stay consistent with resolve().
local function type_nodes(type_name, filetype)
	local t = type_entry(type_name)
	if not t[8] then
		local lt = literal_type_entry(type_name)
		if filetype then
			lt = literal_type_ft_entry(type_name, filetype, lt)
		end
		return { lt[1], lt[2], lt[3], lt[4], lt[5], lt[6] }, nil, true
	end

	if filetype then
		local ft = type_ft_entry(type_name, filetype, t)
		return { ft[1], ft[2], ft[3], ft[4], ft[5], ft[6] }, nil, false
	end

	return { t[1], t[2], t[3], t[4], t[5], true }, nil, false
end

local function mod_nodes(typemod, filetype)
	local q = mod_entry(typemod)
	if not q[6] then
		return nil, lookup_hl(typemod) or typemod, true
	end

	if filetype then
		local ft = mod_ft_entry(typemod, filetype, q)
		return { ft[1], ft[2], ft[3], ft[4], ft[5], ft[6] }, nil, false
	end

	return { q[1], true, q[2], true, q[3], true }, nil, false
end

local function typemod_nodes(type_name, typemod, filetype)
	local t = type_entry(type_name)
	if not t[8] then
		-- Keep the exact fallback behavior of resolve_typemod_cached().
		return type_nodes(type_name, filetype)
	end

	local q = mod_entry(typemod)
	local tm = typemod_entry(type_name, typemod, t, q)
	if tm[1] or tm[2] then
		if filetype then
			local ft = typemod_ft_entry(type_name, typemod, filetype, tm)
			return { false, false, ft[1], true, ft[2], true }, nil, false
		end
		return { false, false, tm[1], true, tm[2], true }, nil, false
	end

	return nil, lookup_hl(typemod) or typemod, true
end

local function semantic_nodes(type_name, typemod, filetype)
	if typemod ~= nil then
		if type_name ~= nil then
			return typemod_nodes(type_name, typemod, filetype)
		end
		return mod_nodes(typemod, filetype)
	end
	return type_nodes(type_name, filetype)
end

local function pick_target(nodes, max_layer)
	if not nodes then
		return nil
	end
	for layer = max_layer, 1, -1 do
		local name = nodes[(layer - 1) * 2 + 1]
		if name then
			return name
		end
	end
	return nil
end

local function apply_semantic_clear(nodes, literal_name, clear_mask)
	if literal_name then
		local layer = hl_layer(literal_name)
		if band(clear_mask, layer_bit(layer)) ~= 0 then
			setter(literal_name, nil, false)
		end
		return
	end

	for layer = 1, 3 do
		local i = (layer - 1) * 2 + 1
		local name = nodes[i]
		local writable = nodes[i + 1]
		if name and writable and band(clear_mask, layer_bit(layer)) ~= 0 then
			setter(name, nil, false)
		end
	end
end

-- Explicit semantic link. Source and target are both resolved semantically.
-- The selected target systems decide which source layers are materialized;
-- clear remains independent and still respects source ownership/writable.
-- The target type itself is not styled here: every source layer links to the
-- best available representation of the target at the same or lower layer.
function M.link(type_name, typemod, target_type, filetype, targets, clear)
	if type_name ~= nil and type(type_name) ~= "string" then
		error("hl.resolver: link source type must be string or nil", 2)
	end
	if typemod ~= nil and type(typemod) ~= "string" then
		error("hl.resolver: link source typemod must be string or nil", 2)
	end
	if type(target_type) ~= "string" or target_type == "" then
		error("hl.resolver: link target type must be a non-empty string", 2)
	end
	if type_name == nil and typemod == nil then
		error("hl.resolver: link source type and typemod cannot both be nil", 2)
	end
	if filetype ~= nil and type(filetype) ~= "string" then
		error("hl.resolver: filetype must be string or nil", 2)
	end
	if targets ~= nil and type(targets) ~= "table" then
		error("hl.resolver: targets must be table or nil", 2)
	end
	if clear ~= nil and type(clear) ~= "table" then
		error("hl.resolver: clear must be table or nil", 2)
	end

	local target_mask, clear_mask = resolve_masks(targets, clear)
	local source_nodes, source_literal, source_warning = semantic_nodes(type_name, typemod, filetype)
	local target_nodes, target_literal, target_warning = type_nodes(target_type, filetype)

	if source_literal then
		local source_layer = hl_layer(source_literal)
		local source_bit = layer_bit(source_layer)
		local target = target_literal or pick_target(target_nodes, source_layer)

		if band(clear_mask, source_bit) ~= 0 and source_literal ~= target then
			setter(source_literal, nil, false)
		end
		if band(target_mask, source_bit) ~= 0 and target and source_literal ~= target then
			setter(source_literal, target, true)
		end
	else
		for layer = 1, 3 do
			local i = (layer - 1) * 2 + 1
			local source = source_nodes[i]
			local writable = source_nodes[i + 1]
			if source and writable then
				local bit_for_layer = layer_bit(layer)
				local target = target_literal or pick_target(target_nodes, layer)
				if band(clear_mask, bit_for_layer) ~= 0 and source ~= target then
					setter(source, nil, false)
				end
				if band(target_mask, bit_for_layer) ~= 0 and target and source ~= target then
					setter(source, target, true)
				end
			end
		end
	end

	if source_warning or target_warning then
		return "unresolved_literal"
	end
	return nil
end

-- Explicit semantic removal used by typemod=false. Unlike resolve(), no
-- cached style object is required because there is intentionally no set step.
function M.clear(type_name, typemod, filetype, clear)
	if type_name ~= nil and type(type_name) ~= "string" then
		error("hl.resolver: clear type must be string or nil", 2)
	end
	if typemod ~= nil and type(typemod) ~= "string" then
		error("hl.resolver: clear typemod must be string or nil", 2)
	end
	if type_name == nil and typemod == nil then
		error("hl.resolver: clear type and typemod cannot both be nil", 2)
	end
	if filetype ~= nil and type(filetype) ~= "string" then
		error("hl.resolver: filetype must be string or nil", 2)
	end
	if clear ~= nil and type(clear) ~= "table" then
		error("hl.resolver: clear mask must be table or nil", 2)
	end

	local _, clear_mask = resolve_masks(nil, clear or {
		vim = true,
		ts = true,
		lsp = true,
	})
	local nodes, literal_name, warning = semantic_nodes(type_name, typemod, filetype)
	apply_semantic_clear(nodes, literal_name, clear_mask)
	return warning and "unresolved_literal" or nil
end


-- Runtime target inspection uses the resolver's already-built name caches but
-- never calls setter() and never performs a second materialization pass. It is
-- deliberately lazy: normal theme reloads pay nothing unless a runtime target
-- is actually modified.
local function runtime_add_name(out, seen, name)
	if name and not seen[name] then
		seen[name] = true
		out[#out + 1] = name
	end
end

local function runtime_collect3(nodes, target_mask, clear_mask, out, seen)
	local writable_target = false
	for layer = 1, 3 do
		local i = (layer - 1) * 2 + 1
		local name = nodes[i]
		local writable = nodes[i + 1]
		local bit_for_layer = layer_bit(layer)
		if name and writable and band(clear_mask, bit_for_layer) ~= 0 then
			runtime_add_name(out, seen, name)
		end
		if name and writable and band(target_mask, bit_for_layer) ~= 0 then
			writable_target = true
			runtime_add_name(out, seen, name)
		end
	end
	return target_mask == 0 or writable_target
end

local function runtime_collect2(n1, w1, bit1, n2, w2, bit2, target_mask, clear_mask, out, seen)
	if n1 and w1 and band(clear_mask, bit1) ~= 0 then
		runtime_add_name(out, seen, n1)
	end
	if n2 and w2 and band(clear_mask, bit2) ~= 0 then
		runtime_add_name(out, seen, n2)
	end

	local selected = band(target_mask, bit1 + bit2)
	if selected == 0 then
		return true
	end

	local writable_target = false
	if n1 and w1 and band(target_mask, bit1) ~= 0 then
		writable_target = true
		runtime_add_name(out, seen, n1)
	end
	if n2 and w2 and band(target_mask, bit2) ~= 0 then
		writable_target = true
		runtime_add_name(out, seen, n2)
	end
	return writable_target
end

local function runtime_collect_literal(name, target_mask, clear_mask, out, seen)
	local bit_for_layer = layer_bit(hl_layer(name))
	if band(target_mask, bit_for_layer) ~= 0 or band(clear_mask, bit_for_layer) ~= 0 then
		runtime_add_name(out, seen, name)
	end
end

local function runtime_literal_type_names(type_name, filetype, target_mask, clear_mask, out, seen)
	local t = literal_type_entry(type_name)
	if filetype then
		t = literal_type_ft_entry(type_name, filetype, t)
	end
	runtime_collect3({ t[1], t[2], t[3], t[4], t[5], t[6] }, target_mask, clear_mask, out, seen)
end

function M.runtime_style_names(type_name, typemod, filetype, targets, clear, typemod_style)
	local target_mask, clear_mask = resolve_masks(targets, clear)
	local out, seen = {}, {}

	if typemod == nil then
		local t = type_entry(type_name)
		if not t[8] then
			runtime_literal_type_names(type_name, filetype, target_mask, clear_mask, out, seen)
			return out
		end

		local nodes
		if filetype then
			local ft = type_ft_entry(type_name, filetype, t)
			nodes = { ft[1], ft[2], ft[3], ft[4], ft[5], ft[6] }
		else
			nodes = { t[1], t[2], t[3], t[4], t[5], true }
		end
		if not runtime_collect3(nodes, target_mask, clear_mask, out, seen) then
			runtime_literal_type_names(type_name, filetype, target_mask, clear_mask, out, seen)
		end
		return out
	end

	if type_name == nil then
		local q = mod_entry(typemod)
		if not q[6] then
			runtime_collect_literal(lookup_hl(typemod) or typemod, target_mask, clear_mask, out, seen)
			return out
		end

		local nodes
		if filetype then
			local ft = mod_ft_entry(typemod, filetype, q)
			nodes = { ft[1], ft[2], ft[3], ft[4], ft[5], ft[6] }
		else
			nodes = { q[1], true, q[2], true, q[3], true }
		end
		if not runtime_collect3(nodes, target_mask, clear_mask, out, seen) then
			runtime_collect_literal(lookup_hl(typemod) or typemod, target_mask, clear_mask, out, seen)
		end
		return out
	end

	local t = type_entry(type_name)
	if typemod_style then
		local q = mod_entry(typemod)
		local tm = literal_typemod_entry(type_name, typemod, t, q)
		if filetype then
			tm = literal_typemod_ft_entry(type_name, typemod, filetype, tm)
		end
		runtime_collect2(
			tm[1], true, TARGET_TS,
			tm[2], true, TARGET_LSP,
			target_mask, clear_mask, out, seen
		)
		return out
	end

	if not t[8] then
		runtime_literal_type_names(type_name, filetype, target_mask, clear_mask, out, seen)
		return out
	end

	local q = mod_entry(typemod)
	local tm = typemod_entry(type_name, typemod, t, q)
	if tm[1] or tm[2] then
		local n1, n2 = tm[1], tm[2]
		if filetype then
			local ft = typemod_ft_entry(type_name, typemod, filetype, tm)
			n1, n2 = ft[1], ft[2]
		end
		if runtime_collect2(
			n1, true, TARGET_TS,
			n2, true, TARGET_LSP,
			target_mask, clear_mask, out, seen
		) then
			return out
		end
	end

	runtime_collect_literal(lookup_hl(typemod) or typemod, target_mask, clear_mask, out, seen)
	return out
end

function M.runtime_link_names(type_name, typemod, target_type, filetype, targets, clear)
	local target_mask, clear_mask = resolve_masks(targets, clear)
	local out, seen = {}, {}
	local source_nodes, source_literal = semantic_nodes(type_name, typemod, filetype)
	local target_nodes, target_literal = type_nodes(target_type, filetype)

	if source_literal then
		local source_layer = hl_layer(source_literal)
		local source_bit = layer_bit(source_layer)
		local target = target_literal or pick_target(target_nodes, source_layer)
		if source_literal ~= target then
			if band(clear_mask, source_bit) ~= 0 then
				runtime_add_name(out, seen, source_literal)
			end
			if band(target_mask, source_bit) ~= 0 and target then
				runtime_add_name(out, seen, source_literal)
			end
		end
		return out
	end

	for layer = 1, 3 do
		local i = (layer - 1) * 2 + 1
		local source = source_nodes[i]
		local writable = source_nodes[i + 1]
		if source and writable then
			local bit_for_layer = layer_bit(layer)
			local target = target_literal or pick_target(target_nodes, layer)
			if source ~= target then
				if band(clear_mask, bit_for_layer) ~= 0 then
					runtime_add_name(out, seen, source)
				end
				if band(target_mask, bit_for_layer) ~= 0 and target then
					runtime_add_name(out, seen, source)
				end
			end
		end
	end
	return out
end

function M.runtime_clear_names(type_name, typemod, filetype, clear)
	local _, clear_mask = resolve_masks(nil, clear or {
		vim = true,
		ts = true,
		lsp = true,
	})
	local out, seen = {}, {}
	local nodes, literal_name = semantic_nodes(type_name, typemod, filetype)
	if literal_name then
		runtime_collect_literal(literal_name, 0, clear_mask, out, seen)
		return out
	end
	for layer = 1, 3 do
		local i = (layer - 1) * 2 + 1
		local name = nodes[i]
		local writable = nodes[i + 1]
		if name and writable and band(clear_mask, layer_bit(layer)) ~= 0 then
			runtime_add_name(out, seen, name)
		end
	end
	return out
end

-- targets / clear:
--   nil targets -> Vim + Tree-sitter + LSP
--   table       -> only truthy entries are materialized
--   clear       -> independent from targets; truthy entries are cleared first
--   typemod_style == true -> style belongs to this single type+typemod
--                              combination; false/nil uses normal fallback resolution
--
-- Example:
--   targets = { vim = true }
--   clear   = { ts = true, lsp = true }
-- clears TS/LSP for the resolved semantic group, then materializes Vim only.
function M.resolve(type_name, typemods, style, filetype, targets, clear, typemod_style)
	if type(style) ~= "table" then
		error("hl.resolver: style must be the cached style object", 2)
	end

	if type_name ~= nil and type(type_name) ~= "string" then
		error("hl.resolver: type must be string or nil", 2)
	end

	if filetype ~= nil and type(filetype) ~= "string" then
		error("hl.resolver: filetype must be string or nil", 2)
	end

	if targets ~= nil and type(targets) ~= "table" then
		error("hl.resolver: targets must be table or nil", 2)
	end

	if clear ~= nil and type(clear) ~= "table" then
		error("hl.resolver: clear must be table or nil", 2)
	end

	if typemod_style ~= nil and type(typemod_style) ~= "boolean" then
		error("hl.resolver: typemod_style must be boolean or nil", 2)
	end

	local target_mask, clear_mask = resolve_masks(targets, clear)

	if typemods == nil then
		if type_name == nil then
			error("hl.resolver: type and typemod cannot both be nil", 2)
		end
		return resolve_type(type_name, style, filetype, target_mask, clear_mask)
	end

	local qtype = type(typemods)
	if qtype == "string" then
		if type_name then
			return resolve_typemod(
				type_name, typemods, style, filetype, target_mask, clear_mask, typemod_style
			)
		end
		return resolve_mod(typemods, style, filetype, target_mask, clear_mask)
	end

	if qtype ~= "table" then
		error("hl.resolver: typemods must be string, table or nil", 2)
	end

	local count = #typemods
	if count == 0 then
		if type_name == nil then
			error("hl.resolver: type and typemod cannot both be nil", 2)
		end
		return resolve_type(type_name, style, filetype, target_mask, clear_mask)
	end

	local warning

	if type_name then
		-- One type-cache lookup for the complete typemod list.
		local t = type_entry(type_name)

		for i = 1, count do
			local current = resolve_typemod_cached(
				type_name, typemods[i], style, t, filetype, target_mask, clear_mask, nil
			)
			if current then
				warning = current
			end
		end
	else
		for i = 1, count do
			local current = resolve_mod(
				typemods[i], style, filetype, target_mask, clear_mask
			)
			if current then
				warning = current
			end
		end
	end

	return warning
end

return M
