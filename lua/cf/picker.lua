local M = {}

local menu = require("cf.menu")
local resolver = require("cf.hl.resolver")
local theme = require("cf.theme")
local api = vim.api

local reverse_theme
local reverse_types
local reverse_mods
local edit_theme
local style_edits = {}
local rule_edits = {}
local pipeline_edits = {}

local TARGETS_ALL = { vim = true, ts = true, lsp = true }

-- Visual boolean nvim_set_hl style fields. Colour/index/default/force metadata
-- deliberately stays out of the Style menu; those belong to other editors or
-- to ChromaFlow's materialization policy rather than to visual style toggles.
local STYLE_FLAGS = {
	"bold",
	"italic",
	"underline",
	"undercurl",
	"underdouble",
	"underdotted",
	"underdashed",
	"strikethrough",
	"overline",
	"reverse",
	"standout",
	"nocombine",
	"altfont",
	"blink",
	"dim",
	"conceal",
}

local STYLE_FIELDS = { unpack(STYLE_FLAGS) }
STYLE_FIELDS[#STYLE_FIELDS + 1] = "blend"

local function blend_label(value)
	return "blend: " .. (value == nil and "unset" or tostring(value)) .. "  (+/-; Alt: 10)"
end

-- Tree-sitter capture names are hierarchical. Most can be reversed from their
-- dot structure, but a few standard captures do not mean what that structure
-- would suggest to the CF DSL. Keep only those reverse-only exceptions here;
-- the resolver hotpath does not need them.
local TS_REVERSE = {
	types = {
		["variable.parameter"] = "parameter",
		["module"] = "namespace",
		["string.regexp"] = "regexp",
		["number.float"] = "float",
		["function.method"] = "method",
		["keyword.function"] = "function",
		["keyword.operator"] = "operator",
		["keyword.type"] = "type",
		["keyword.modifier"] = "modifier",
	},
	mods = {
		-- Hierarchy components used only inside concrete captures. They must not
		-- become synthetic standalone Mod rows just because a dotted capture was
		-- inspected at the cursor.
		call = { standalone = false },
		member = { standalone = false },
	},
	typemods = {
		-- Full-capture overrides belong here if a future TS capture cannot be
		-- represented by the normal <type-prefix>.<typemod-suffix> heuristic.
	},
}

local function append(items, seen, kind, name, type_name, typemod, origin)
	if type(name) ~= "string" or name == "" then
		return
	end
	local key = kind .. "\0" .. name
	if seen[key] then
		return seen[key]
	end

	if kind == "Type" then
		type_name = name
	elseif kind == "Mod" then
		typemod = name
	end

	items[#items + 1] = {
		kind = kind,
		name = name,
		type_name = type_name,
		typemod = typemod,
		origin = origin,
		label = string.format("%-8s %s", kind, name),
	}
	seen[key] = items[#items]
	return items[#items]
end

local function reverse_key(source, token)
	return source .. "\0" .. token
end

local function remember_reverse(map, source, token, semantic)
	if type(token) ~= "string" or token == "" then
		return
	end
	local key = reverse_key(source, token)
	-- Several semantic aliases may deliberately share one concrete target.
	-- Keep the first semantic name from the compiled theme; primary declarations
	-- are compiled before their aliases.
	if map[key] == nil then
		map[key] = semantic
	end
end

local function remember_type_name(map, semantic, name)
	if name:sub(1, 10) == "@lsp.type." then
		remember_reverse(map, "lsp", name:sub(11), semantic)
	elseif name:sub(1, 1) == "@" and name:sub(1, 5) ~= "@lsp." then
		remember_reverse(map, "ts", name:sub(2), semantic)
	elseif name:sub(1, 1) ~= "@" then
		remember_reverse(map, "vim", name, semantic)
	end
end

local function remember_mod_name(map, semantic, name)
	if name:sub(1, 9) == "@lsp.mod." then
		remember_reverse(map, "lsp", name:sub(10), semantic)
	elseif name:sub(1, 1) == "@" and name:sub(1, 5) ~= "@lsp." then
		remember_reverse(map, "ts", name:sub(2), semantic)
	elseif name:sub(1, 1) ~= "@" then
		remember_reverse(map, "vim", name, semantic)
	end
end

local function rebuild_reverse()
	local current = theme.current()
	if edit_theme ~= current then
		style_edits = {}
		rule_edits = {}
		pipeline_edits = {}
		edit_theme = current
	end
	if reverse_types and reverse_theme == current then
		return
	end

	local types = {}
	local mods = {}

	if current and type(current.modules) == "table" then
		for i = 1, #current.modules do
			local actions = current.modules[i].actions
			if type(actions) == "table" then
				for j = 1, #actions do
					local action = actions[j]
					if type(action.type_name) == "string" then
						types[action.type_name] = true
					end
					if type(action.target_type) == "string" then
						types[action.target_type] = true
					end
					if type(action.typemod) == "string" then
						mods[action.typemod] = true
					end
				end
			end
		end
	end

	local type_map = {}
	local mod_map = {}

	for semantic in pairs(types) do
		local names = resolver.runtime_style_names(semantic, nil, nil, TARGETS_ALL, nil, nil)
		for i = 1, #names do
			remember_type_name(type_map, semantic, names[i])
		end
	end

	for semantic in pairs(mods) do
		local names = resolver.runtime_style_names(nil, semantic, nil, TARGETS_ALL, nil, nil)
		for i = 1, #names do
			remember_mod_name(mod_map, semantic, names[i])
		end
	end

	reverse_theme = current
	reverse_types = type_map
	reverse_mods = mod_map
end

local function reverse_type(source, token)
	rebuild_reverse()
	return reverse_types[reverse_key(source, token)]
end

local function reverse_mod(source, token)
	rebuild_reverse()
	return reverse_mods[reverse_key(source, token)]
end

local function reverse_ts_type(token)
	return TS_REVERSE.types[token] or reverse_type("ts", token)
end

local function reverse_ts_mod(token)
	local rule = TS_REVERSE.mods[token]
	if rule and rule.name then return rule.name end
	return reverse_mod("ts", token) or token
end

local function lower_token(token)
	return type(token) == "string" and token:lower() or nil
end

local function append_lsp(items, seen)
	local tokens = vim.lsp.semantic_tokens.get_at_pos(0) or {}
	if #tokens == 0 then
		return false
	end

	for i = #tokens, 1, -1 do
		local token = tokens[i]
		-- LSP already supplies the semantic axes separately. In particular,
		-- token.type == "modifier" is just a Type named "modifier"; only the
		-- modifiers table represents Mods.
		local type_name = reverse_type("lsp", token.type) or lower_token(token.type)
		local parent = append(items, seen, "Type", type_name, nil, nil, "lsp")

		local mods = {}
		for mod in pairs(token.modifiers or {}) do
			mods[#mods + 1] = mod
		end
		table.sort(mods)

		for j = 1, #mods do
			local mod = reverse_mod("lsp", mods[j]) or lower_token(mods[j])
			local entry = append(items, seen, "Mod", mod, nil, nil, "lsp")
			if entry and not entry.parent then entry.parent = parent end
			append(items, seen, "TypeMod", type_name and mod and (type_name .. "." .. mod) or nil, type_name, mod, "lsp")
		end
	end

	return #items > 0
end

local function split_dots(token)
	local out = {}
	for part in token:gmatch("[^.]+") do
		out[#out + 1] = part
	end
	return out
end

local function join_parts(parts, first, last)
	if first > last then
		return nil
	end
	local value = parts[first]
	for i = first + 1, last do
		value = value .. "." .. parts[i]
	end
	return value
end

-- Resolve one *actual* Tree-sitter capture into one editable CF target.
-- Dot splitting is the default heuristic; exception tables only override cases
-- where TS hierarchy and CF semantics differ. Importantly, decomposition is
-- internal only: @function.call does not invent active @function/@call rows.
local function classify_ts_capture(token)
	if type(token) ~= "string" or token == "" then return nil end
	token = token:gsub("^@", "")

	local type_name = reverse_ts_type(token)
	if type_name then
		return { kind = "Type", name = type_name, type_name = type_name }
	end

	local explicit = TS_REVERSE.typemods[token]
	if explicit then
		local tm_type = explicit.type_name
		local typemod = explicit.typemod
		local name = explicit.name or (tm_type and typemod and (tm_type .. "." .. typemod))
		if name and tm_type and typemod then
			return { kind = "TypeMod", name = name, type_name = tm_type, typemod = typemod }
		end
	end

	local parts = split_dots(token)
	if #parts == 1 then
		local rule = TS_REVERSE.mods[token]
		local mod = reverse_mod("ts", token)
		if mod and (not rule or rule.standalone ~= false) then
			return { kind = "Mod", name = mod, typemod = mod }
		end
		return { kind = "Type", name = token, type_name = token }
	end

	-- Prefer the longest known Type prefix. If none is exceptional/materialized,
	-- the first TS hierarchy component is the ordinary Type by convention.
	local prefix_type
	local prefix_last
	for last = #parts - 1, 1, -1 do
		local candidate = join_parts(parts, 1, last)
		local semantic = reverse_ts_type(candidate)
		if semantic then
			prefix_type, prefix_last = semantic, last
			break
		end
	end
	if not prefix_type then
		prefix_type = reverse_ts_type(parts[1]) or parts[1]
		prefix_last = 1
	end

	local suffix = join_parts(parts, prefix_last + 1, #parts)
	if not suffix then
		return { kind = "Type", name = prefix_type, type_name = prefix_type }
	end
	local typemod = reverse_ts_mod(suffix)
	return {
		kind = "TypeMod",
		name = prefix_type .. "." .. typemod,
		type_name = prefix_type,
		typemod = typemod,
	}
end

local function append_ts_capture(items, seen, token)
	local entry = classify_ts_capture(token)
	if not entry then return end
	append(items, seen, entry.kind, entry.name, entry.type_name, entry.typemod, "ts")
end

local function append_ts(items, seen, inspected)
	if #inspected.treesitter == 0 then
		return false
	end

	for i = #inspected.treesitter, 1, -1 do
		append_ts_capture(items, seen, inspected.treesitter[i].capture)
	end

	return #items > 0
end

local function append_vim(items, seen, inspected)
	for i = #inspected.syntax, 1, -1 do
		local name = inspected.syntax[i].hl_group
		append(items, seen, "Type", reverse_type("vim", name) or name, nil, nil, "vim")
	end
end

local function items_at_cursor()
	local inspected = vim.inspect_pos(0, nil, nil, {
		treesitter = true,
		semantic_tokens = false,
		syntax = true,
		extmarks = false,
	})

	local items = {}
	local seen = {}

	-- LSP and Tree-sitter can describe different semantic axes at the same
	-- cursor position. Collect both; only fall back to Vim syntax when neither
	-- semantic source contributed anything.
	local semantic = append_lsp(items, seen)
	if append_ts(items, seen, inspected) then
		semantic = true
	end
	if semantic then
		return items
	end
	append_vim(items, seen, inspected)

	return items
end


local function action_matches(entry, action)
	local kind = action.kind
	if kind == "raw_style" or kind == "raw_link" or kind == "raw_clear" then
		return entry.kind == "Type" and entry.origin == "vim" and action.name == entry.name
	end
	if kind ~= "resolver_style" and kind ~= "resolver_link" and kind ~= "resolver_clear" then
		return false
	end
	return action.type_name == entry.type_name and action.typemod == entry.typemod
end

local function owner_rank(action, filetype)
	local kind = action._cf_owner_kind
	local scope = action._cf_owner_name
	if kind == "language" then
		if scope == filetype and filetype ~= "" then return 4 end
		if scope == nil then return 3 end
		return 1
	end
	if kind == "plugin" then return 2 end
	if kind == "ui" then return 2 end
	return 0
end

local function better_action(candidate, best, filetype)
	if not best then return true end
	local candidate_rank = owner_rank(candidate, filetype)
	local best_rank = owner_rank(best, filetype)
	if candidate_rank ~= best_rank then
		return candidate_rank > best_rank
	end
	local candidate_priority = candidate.priority or 0
	local best_priority = best.priority or 0
	if candidate_priority ~= best_priority then
		return candidate_priority > best_priority
	end
	return (candidate.sequence or 0) > (best.sequence or 0)
end

-- Resolve the picked semantic axis back to the compiled action that owns it.
-- This remains picker-local/coldpath work. The action already carries its exact
-- source range when picker mode compiled it, so save can later use that source
-- together with the normal style/runtime caches instead of reconstructing DSL.
local function resolve_entry(entry)
	if entry.target ~= nil or entry.unresolved then
		return entry.target
	end

	local current = theme.current()
	local modules = current and current.modules or nil
	local filetype = entry.filetype or vim.bo.filetype
	local best

	if type(modules) == "table" then
		for i = 1, #modules do
			local actions = modules[i].actions
			if type(actions) == "table" then
				for j = 1, #actions do
					local action = actions[j]
					local scope = action._cf_owner_kind == "language" and action._cf_owner_name or nil
					if (scope == nil or scope == filetype) and action_matches(entry, action) and better_action(action, best, filetype) then
						best = action
					end
				end
			end
		end
	end

	if not best then
		entry.unresolved = true
		return nil
	end

	local runtime = require("cf.fn.runtime")
	if best.kind == "raw_style" or best.kind == "raw_link" or best.kind == "raw_clear" then
		entry.target = runtime.target("raw", nil, best.name, nil)
	else
		entry.target = runtime.target(best._cf_owner_kind, best._cf_owner_name, entry.type_name, entry.typemod)
	end
	entry.action = best
	entry.source = best._cf_source
	return entry.target
end

local function copy_style(style)
	local out = {}
	if type(style) == "table" then
		for key, value in pairs(style) do
			out[key] = value
		end
	end
	return out
end

local function same_source(a, b)
	return a and b and a.file == b.file and a.line == b.line and a.col == b.col
end

local function owner_module(entry)
	local current = theme.current()
	if not entry.source then return end
	for _, module in ipairs(current and current.modules or {}) do
		for _, declaration in ipairs(module.declarations or {}) do
			if same_source(declaration.source, entry.source) then return module, declaration end
		end
		if same_source(module.source, entry.source) then return module end
	end
end

local function inherited_type_owner(entry)
	if entry.kind ~= "Type" or not entry.action or entry.action.kind ~= "resolver_link" then return end
	local module, declaration = owner_module(entry)
	if not declaration or declaration.action ~= "group" or declaration.kind == "raw" then return end
	if declaration.name ~= entry.action.target_type then return end
	local types = declaration.spec and declaration.spec.types
	if type(types) ~= "table" then return end
	for i = 1, #types do
		if types[i] == entry.type_name then return module, declaration end
	end
end

local function detached_type_owner(entry)
	if entry._cf_create_type_anchor then
		local module, declaration = owner_module(entry)
		if declaration and declaration.action == "group" and declaration.kind ~= "raw"
			and declaration.name == entry._cf_create_type_anchor
		then
			return module, declaration, false, entry._cf_create_type_inherited == true
		end
		return nil
	end

	local module, declaration = inherited_type_owner(entry)
	if module then return module, declaration, true, true end
end

local function detach_metadata(entry, base)
	local module, declaration, remove_from_types, copy_parent_metadata = detached_type_owner(entry)
	if not module then return nil end
	local inherited = base
	for _, action in ipairs(module.actions or {}) do
		if same_source(action._cf_source, entry.source)
			and action.kind == "resolver_style"
			and action.type_name == declaration.name
			and action.typemod == nil
		then
			inherited = action.style
			break
		end
	end
	return {
		parent = declaration.name,
		child = entry.type_name,
		base = copy_style(inherited),
		remove_from_types = remove_from_types,
		copy_parent_metadata = copy_parent_metadata,
	}
end

local function local_language_modules(filetype)
	local out = {}
	local current = theme.current()
	for _, module in ipairs(current and current.modules or {}) do
		if module.kind == "language" and module.name == filetype then
			out[#out + 1] = module
		end
	end
	return out
end

local function first_group_declaration(module)
	for _, declaration in ipairs(module and module.declarations or {}) do
		if declaration.action == "group" and declaration.kind ~= "raw" then return declaration end
	end
end

local function local_parent(entry, type_name)
	if not type_name then return nil end
	local parent = {
		kind = "Type", name = type_name, type_name = type_name,
		filetype = entry.filetype, bufnr = entry.bufnr,
	}
	if not resolve_entry(parent) then return nil end
	local action = parent.action
	local filetype = entry.filetype or vim.bo.filetype
	if not action or action._cf_owner_kind ~= "language" or action._cf_owner_name ~= filetype then return nil end
	local module, declaration = owner_module(parent)
	if not module then return nil end
	return parent, module, declaration
end

-- Pick the concrete language source that can own a new local semantic entry.
-- Existing semantic parents are authoritative (important when several modules
-- contribute to one filetype); otherwise only a unique language module is safe.
local function local_creation(entry)
	local filetype = entry.filetype or vim.bo.filetype
	if filetype == "" then return nil end

	local parent, module, declaration
	if entry.kind == "Mod" and entry.parent then
		parent, module, declaration = local_parent(entry, entry.parent.type_name)
	elseif entry.kind == "TypeMod" and entry.type_name then
		parent, module, declaration = local_parent(entry, entry.type_name)
	elseif entry.kind == "Type" and entry.action and entry.action.kind == "resolver_link"
		and entry.action._cf_owner_kind == "language" and entry.action._cf_owner_name == nil
	then
		parent, module, declaration = local_parent(entry, entry.action.target_type)
	end

	if not module then
		local modules = local_language_modules(filetype)
		if #modules ~= 1 then return nil end
		module = modules[1]
		declaration = first_group_declaration(module)
	end

	local type_name = entry.kind == "Mod" and nil or entry.type_name
	local candidates = resolver.runtime_style_names(type_name, entry.typemod, filetype, TARGETS_ALL, nil, type_name ~= nil)
	local names = {}
	for i = 1, #candidates do
		if vim.fn.hlexists(candidates[i]) == 1 then names[#names + 1] = candidates[i] end
	end
	if #names == 0 then return nil end

	local source
	local create_type_anchor
	local create_type_inherited = false
	if entry.kind == "Mod" then
		source = module.source
	elseif entry.kind == "TypeMod" then
		source = declaration and declaration.source
	else
		if not declaration then return nil end
		source = declaration.source
		create_type_anchor = declaration.name
		create_type_inherited = parent ~= nil and entry.action ~= nil
			and entry.action.kind == "resolver_link" and entry.action.target_type == declaration.name
	end
	if not source then return nil end

	return {
		module = module,
		source = source,
		names = names,
		type_name = type_name,
		create_type_anchor = create_type_anchor,
		create_type_inherited = create_type_inherited,
	}
end

-- Only enumerate actual hl_group names in this session. In particular, do not
-- use runtime_style_names() as proof of existence: it can return literal names
-- for a future DSL declaration. No catalogue refresh or resolver mutation here.
local function session_typemods(entry)
	rebuild_reverse()
	local catalog = api.nvim_get_hl(0, {})
	local ft = entry.filetype or ""
	local filetypes = {}
	local current = theme.current()
	for _, module in ipairs(current and current.modules or {}) do
		if module.kind == "language" and module.name then filetypes[module.name] = true end
	end
	for _, buf in ipairs(api.nvim_list_bufs()) do
		local value = vim.bo[buf].filetype
		if value ~= "" then filetypes[value] = true end
	end
	for name in pairs(catalog) do
		local scope = name:match("^@lsp%.mod%.[^.]+%.(.+)$")
			or name:match("^@lsp%.typemod%.[^.]+%.[^.]+%.(.+)$")
		if scope then filetypes[scope] = true end
	end
	local rows = {}
	local function add(mod, name, specific)
		if not mod or mod == "" then return end
		local row = rows[mod]
		if not row then row = { name = mod, names = {}, generic = {} }; rows[mod] = row end
		local list = specific and row.names or row.generic
		list[#list + 1] = name
	end
	for name in pairs(catalog) do
		local typ, mod, lang = name:match("^@lsp%.typemod%.([^.]+)%.([^.]+)%.?(.*)$")
		if typ then
			local semantic = reverse_type("lsp", typ) or resolver.semantic_type_token("lsp", typ):lower()
			if entry.type_name == semantic and (lang == "" or lang == ft) then
				add(reverse_mod("lsp", mod) or resolver.semantic_typemod_token("lsp", mod), name, lang ~= "")
			end
		elseif name:sub(1, 1) == "@" and name:sub(1, 5) ~= "@lsp." then
			local capture = name:sub(2)
			local prefix, suffix = capture:match("^(.*)%.([^.]+)$")
			local specific = suffix and filetypes[suffix]
			if not specific or suffix == ft then
				if specific then capture = prefix end
				-- The Type is already selected. Do not reinterpret its children
				-- as cursor Types (keyword.function -> function, for example).
				for dot in capture:gmatch("()%.") do
					local prefix_, mod_ = capture:sub(1, dot - 1), capture:sub(dot + 1)
					if prefix_ == entry.type_name or reverse_type("ts", prefix_) == entry.type_name then
						add(reverse_mod("ts", mod_) or resolver.semantic_typemod_token("ts", mod_), name, specific)
						break
					end
				end
			end
		end
	end
	local result = {}
	for _, row in pairs(rows) do
		-- A filetype-specific entry shadows its generic counterpart within each
		-- source, not across Tree-sitter/LSP. Keep both source families available.
		local families = {}
		for _, name in ipairs(row.names) do families[name:sub(1, 5) == "@lsp." and "lsp" or "ts"] = true end
		for _, name in ipairs(row.generic) do
			if not families[name:sub(1, 5) == "@lsp." and "lsp" or "ts"] then row.names[#row.names + 1] = name end
		end
		table.sort(row.names)
		row.generic = nil
		result[#result + 1] = row
	end
	table.sort(result, function(a, b) return a.name < b.name end)
	return result
end

local function editable_child(parent, mod, type_name, names)
	local child = {
		kind = "TypeMod",
		name = type_name .. "." .. mod,
		type_name = type_name, typemod = mod,
		filetype = parent.filetype, bufnr = parent.bufnr,
	}
	if resolve_entry(child) then return child end
	local module = owner_module(parent)
	if not module or not parent.source then return child end
	local runtime = require("cf.fn.runtime")
	child.target = runtime.target(module.kind, module.name, type_name, mod)
	child.source = parent.source
	child.action = {
		kind = "resolver_style", type_name = type_name, typemod = mod,
		_cf_owner_kind = module.kind, _cf_owner_name = module.name,
		_cf_source = child.source,
	}
	child.unresolved = nil
	local base = require("cf.hl.runtime").read_effective_style(names[1])
	runtime._picker_bind_target(child.target, names, base)
	return child
end

local function style_label(name, value)
	local mark = "[ ] "
	if value == true then
		mark = "[x] "
	elseif value == false then
		mark = "[-] "
	end
	return mark .. name
end

local function next_style_value(value)
	if value == nil then
		return true
	end
	if value == true then
		return false
	end
	return nil
end

local function style_edit_key(entry)
	local action = entry.action
	if not action then return nil end
	if action.kind == "raw_style" or action.kind == "raw_link" or action.kind == "raw_clear" then
		return table.concat({ "raw", "", action.name or "", "" }, "\0")
	end
	return table.concat({
		action._cf_owner_kind or "",
		action._cf_owner_name or "",
		entry.type_name or "",
		entry.typemod or "",
	}, "\0")
end

local function remember_style_edit(entry, target, detach_type)
	local key = style_edit_key(entry)
	if not key then return end
	style_edits[key] = {
		target = target,
		source = entry.source,
		action = entry.action,
		kind = entry.kind,
		name = entry.name,
		type_name = entry.type_name,
		typemod = entry.typemod,
		detach_type = detach_type,
	}
end


function M.start()
	require("cf.colortrace").set_picker(true)
	return M
end

function M.stop()
	local pipeline_editor = package.loaded["cf.picker_pipeline"]
	if pipeline_editor then pipeline_editor.close() end
	local colortrace = package.loaded["cf.colortrace"]
	if colortrace then
		colortrace.set_picker(false)
	end
	reverse_theme = nil
	reverse_types = nil
	reverse_mods = nil
	edit_theme = nil
	style_edits = {}
	rule_edits = {}
	pipeline_edits = {}
	return M
end

-- Internal save handoff. Runtime owns the live sparse values, compiled highlight
-- state owns the immutable base styles, and this picker cache owns only semantic
-- target/source identity. The returned table is read-only to consumers.
function M._style_edits()
	rebuild_reverse()
	return style_edits
end

function M._rule_edits()
	rebuild_reverse()
	return rule_edits
end

function M._pipeline_edits()
	rebuild_reverse()
	return pipeline_edits
end

-- Boolean fields keep their tri-state UI; the save writer also needs numeric blend.
function M._style_flags()
	return STYLE_FLAGS
end

function M._style_fields()
	return STYLE_FIELDS
end

local open_pick
local open_edit

local function bind_local_target(entry, creation)
	local runtime = require("cf.fn.runtime")
	local target = runtime.target(creation.module.kind, creation.module.name, creation.type_name, entry.typemod)
	runtime._picker_bind_target(target, creation.names, require("cf.hl.runtime").read_effective_style(creation.names[1]))
	entry.target, entry.source, entry.unresolved = target, creation.source, nil
	entry._cf_create_type_anchor = creation.create_type_anchor
	entry._cf_create_type_inherited = creation.create_type_inherited
	entry.action = {
		kind = "resolver_style", type_name = creation.type_name, typemod = entry.typemod,
		typemod_style = creation.type_name ~= nil and entry.typemod ~= nil,
		_cf_owner_kind = creation.module.kind, _cf_owner_name = creation.module.name, _cf_source = creation.source,
	}
	return target
end

local function prepare_target(entry)
	if entry._cf_local_creation then
		return bind_local_target(entry, entry._cf_local_creation)
	end

	local target = resolve_entry(entry)
	if target then return target end

	local creation = local_creation(entry)
	if creation then return bind_local_target(entry, creation) end

	local parent
	local type_name
	if entry.kind == "Mod" and entry.parent then
		parent = entry.parent
	elseif entry.kind == "TypeMod" and entry.type_name then
		-- A cursor TypeMod may be perfectly valid even when the selected Type has
		-- no direct TypeMod declaration yet. Use the Type declaration as the
		-- source owner so Style/Pipeline can create the missing typemods entry.
		parent = {
			kind = "Type", name = entry.type_name, type_name = entry.type_name,
			filetype = entry.filetype, bufnr = entry.bufnr,
		}
		type_name = entry.type_name
	end
	if not parent or not resolve_entry(parent) then return nil end

	local module = owner_module(parent)
	if not module or not parent.source then return nil end
	local candidates = resolver.runtime_style_names(type_name, entry.typemod, entry.filetype, TARGETS_ALL, nil, type_name ~= nil)
	local names = {}
	for i = 1, #candidates do
		if vim.fn.hlexists(candidates[i]) == 1 then names[#names + 1] = candidates[i] end
	end
	if #names == 0 then return nil end

	local runtime = require("cf.fn.runtime")
	local source = type_name == nil and module.source or parent.source
	target = runtime.target(module.kind, module.name, type_name, entry.typemod)
	runtime._picker_bind_target(target, names, require("cf.hl.runtime").read_effective_style(names[1]))
	entry.target, entry.source, entry.unresolved = target, source, nil
	entry.action = {
		kind = "resolver_style", type_name = type_name, typemod = entry.typemod,
		typemod_style = type_name ~= nil,
		_cf_owner_kind = module.kind, _cf_owner_name = module.name, _cf_source = source,
	}
	return target
end

local function generic_language_fallback(entry)
	local action = entry.action
	return action and action._cf_owner_kind == "language" and action._cf_owner_name == nil
end

local function source_choice(entry)
	if entry._cf_source_choice then return nil end
	if not resolve_entry(entry) or not generic_language_fallback(entry) then return nil end
	return local_creation(entry)
end

local function clone_entry(entry)
	local copy = {}
	for key, value in pairs(entry) do copy[key] = value end
	return copy
end

local function open_source_choice(entry, entries, selected, creation)
	local filetype = entry.filetype or vim.bo.filetype
	return menu.open({
		title = " Source: " .. entry.name .. " ",
		items = { filetype, "generic" },
		on_back = function()
			if entry.back then entry.back() else open_pick(entries, selected) end
		end,
		on_select = function(_, index)
			local chosen = clone_entry(entry)
			chosen._cf_source_choice = index == 1 and "local" or "generic"
			chosen._cf_local_creation = index == 1 and creation or nil
			chosen._cf_choice_back = function() open_source_choice(entry, entries, selected, creation) end
			open_edit(chosen, entries, selected)
		end,
	})
end

local function open_style(entry, entries, selected)
	local target = prepare_target(entry)
	if not target then
		api.nvim_echo({ { ("ChromaFlow: no editable source for %s %s"):format(entry.kind, entry.name), "WarningMsg" } }, false, {})
		return open_edit(entry, entries, selected)
	end

	local runtime = require("cf.fn.runtime")
	local ok, state = pcall(runtime._picker_style_state, target)
	if not ok then
		api.nvim_echo({ { tostring(state), "ErrorMsg" } }, false, {})
		return open_edit(entry, entries, selected)
	end

	local detach_type = detach_metadata(entry, state.base)
	local current = type(state.current) == "table" and state.current or {}
	if entry.kind == "TypeMod" then
		-- A source TypeMod table starts from its Type's finished style. Match
		-- that semantics when turning a cleared/new combination into a style.
		local parent = { kind = "Type", name = entry.type_name, type_name = entry.type_name,
			filetype = entry.filetype, bufnr = entry.bufnr }
		if resolve_entry(parent) then
			local parent_state = runtime._picker_style_state(parent.target, false)
			local inherited = copy_style(parent_state.current)
			for name, value in pairs(current) do inherited[name] = value end
			current = inherited
		end
	end
	local values = {}
	local items = {}
	for i = 1, #STYLE_FLAGS do
		local name = STYLE_FLAGS[i]
		values[i] = current[name]
		items[i] = style_label(name, values[i])
	end
	local blend_index = #STYLE_FLAGS + 1
	local blend = current.blend
	items[blend_index] = blend_label(blend)

	local function preview()
		local style = copy_style(current)
		for i = 1, #STYLE_FLAGS do
			local name = STYLE_FLAGS[i]
			style[name] = values[i]
		end
		style.blend = blend
		runtime._picker_set_style(target, style)
	end

	local function restore()
		runtime._picker_restore_style(target, state)
	end

	return menu.open({
		title = " Styles: " .. entry.name .. " ",
		items = items,
		on_back = function()
			restore()
			open_edit(entry, entries, selected)
		end,
		on_cancel = restore,
		on_space = function(_, index, current_menu)
			if index == blend_index then
				blend = nil
				current_menu:set_item(index, blend_label(blend))
				preview()
				return
			end
			values[index] = next_style_value(values[index])
			current_menu:set_item(index, style_label(STYLE_FLAGS[index], values[index]))
			preview()
		end,
		on_adjust = function(_, index, current_menu, delta)
			if index ~= blend_index then return end
			blend = math.max(0, math.min(100, (blend or 0) + delta))
			current_menu:set_item(index, blend_label(blend))
			preview()
		end,
		on_select = function()
			remember_style_edit(entry, target, detach_type)
			open_edit(entry, entries, selected)
		end,
	})
end

local function rule_key(source, mod)
	return table.concat({ source.file, source.line, source.col, mod }, "\0")
end

local function open_pipeline(entry, entries, selected)
	local target = prepare_target(entry)
	if not target then
		api.nvim_echo({ { "ChromaFlow: no editable source for " .. entry.name, "WarningMsg" } }, false, {})
		return open_edit(entry, entries, selected)
	end
	local module, declaration = owner_module(entry)
	local spec = declaration and declaration.spec or {}
	local inherited
	local detach_type
	local inherited_module, inherited_declaration = detached_type_owner(entry)
	if inherited_module then
		local state = require("cf.fn.runtime")._picker_style_state(target, false)
		detach_type = detach_metadata(entry, state.base)
		inherited = copy_style(detach_type.base)
		spec = {}
		module, declaration = inherited_module, inherited_declaration
	elseif entry.kind == "Mod" then
		spec = module and module.mods and module.mods[entry.typemod] or {}
	elseif entry.kind == "TypeMod" then
		for _, action in ipairs(module and module.actions or {}) do
			if same_source(action._cf_source, entry.source) and action.kind == "resolver_style" and action.typemod == nil then
				local runtime = require("cf.fn.runtime")
				local parent = runtime.target(action._cf_owner_kind, action._cf_owner_name, action.type_name, nil)
				inherited = runtime._picker_style_state(parent, false).current
				break
			end
		end
		spec = spec.typemods and spec.typemods[entry.typemod] or {}
	end
	if type(spec) ~= "table" then spec = {} end
	local key = style_edit_key(entry)
	local metadata = { target = target, source = entry.source, action = entry.action,
		kind = entry.kind, name = entry.name, type_name = entry.type_name, typemod = entry.typemod,
		detach_type = detach_type }
	local ok, result = pcall(function()
		return require("cf.picker_pipeline").open({
			edit = metadata, spec = spec, inherited = inherited,
			reset = entry.kind == "TypeMod" and rule_edits[rule_key(entry.source, entry.typemod)] ~= nil,
			pending = pipeline_edits[key] and pipeline_edits[key].pipeline_edit,
			on_back = function() open_edit(entry, entries, selected) end,
			on_commit = function(delta)
				metadata.pipeline_edit = delta
				pipeline_edits[key] = delta and metadata or nil
			end,
		})
	end)
	if not ok then
		api.nvim_echo({ { tostring(result), "ErrorMsg" } }, false, {})
		return open_edit(entry, entries, selected)
	end
	return result
end

local function open_typemods(entry, entries, selected, row_selected)
	resolve_entry(entry)
	local _, declaration = owner_module(entry)
	if not declaration or declaration.action ~= "group" or declaration.kind == "raw" then
		api.nvim_echo({ { "ChromaFlow: no semantic group declaration for TypeMods", "WarningMsg" } }, false, {})
		return open_edit(entry, entries, selected)
	end
	local rows = session_typemods(entry)
	if #rows == 0 then
		api.nvim_echo({ { "ChromaFlow: no TypeMods available for this Type in the current session", "WarningMsg" } }, false, {})
		return open_edit(entry, entries, selected)
	end
	-- A Type and its TypeMods can live in separate group declarations.
	-- Use the same resolved child source for labels, edits and persistence.
	for _, row in ipairs(rows) do
		local child = { kind = "TypeMod", name = entry.type_name .. "." .. row.name,
			type_name = entry.type_name, typemod = row.name, filetype = entry.filetype }
		resolve_entry(child)
		local _, child_declaration = owner_module(child)
		row.source = child.source or entry.source
		row.spec = child_declaration and child_declaration.spec or declaration.spec
		row.action = child.action or entry.action
	end
	local function styled(row)
		for _, edit in pairs(pipeline_edits) do
			if edit.type_name == entry.type_name and edit.typemod == row.name and same_source(edit.source, row.source) then return true end
		end
		for _, edit in pairs(style_edits) do
			if edit.type_name == entry.type_name and edit.typemod == row.name and same_source(edit.source, row.source) then
				local state = require("cf.fn.runtime")._picker_style_state(edit.target, false)
				return not vim.deep_equal(state.base, state.current)
			end
		end
		return false
	end
	local function value(row)
		local pending = rule_edits[rule_key(row.source, row.name)]
		if pending then return pending.value end
		return row.spec.typemods and row.spec.typemods[row.name]
	end
	local function label(row)
		local v = value(row)
		local status = "empty"
		for _, edit in pairs(pipeline_edits) do
			if edit.type_name == entry.type_name and edit.typemod == row.name and same_source(edit.source, row.source) then
				return "   " .. row.name .. "  group: Pipeline (edited)"
			end
		end
		if styled(row) then
			return "   " .. row.name .. "  group: Style" .. (type(v) == "table" and v.pipeline and "+Pipeline" or "")
		end
		if v == true then return "=  " .. row.name end
		if v == false then return "x  " .. row.name .. "  excluded" end
		if type(v) == "table" then
			local styled = false
			for k in pairs(v) do
				if k ~= "pipeline" and k ~= "priority" and k ~= "link" then styled = true end
			end
			status = v.link and "group: Link" or (v.pipeline and (styled and "group: Style+Pipeline" or "group: Pipeline") or "group: Style")
		else
			local global = { kind = "Mod", name = row.name, typemod = row.name, filetype = entry.filetype }
			if resolve_entry(global) then status = "global" end
		end
		return "   " .. row.name .. "  " .. status
	end
	local items = {}
	for i, row in ipairs(rows) do items[i] = label(row) end
	return menu.open({
		title = " TypeMods: " .. entry.name .. " ", items = items, selected = row_selected,
		on_back = function() open_edit(entry, entries, selected) end,
		on_mark = function(_, index, current_menu, mark)
			local row = rows[index]
			local new_value
			if styled(row) or value(row) ~= mark then new_value = mark end
			local runtime = require("cf.fn.runtime")
			local parent_style = runtime._picker_style_state(entry.target, false).current
			if new_value == true and type(parent_style) ~= "table" then
				api.nvim_echo({ { "ChromaFlow: '=' requires a styled Type", "WarningMsg" } }, false, {})
				return
			end
			local child = editable_child(entry, row.name, entry.type_name, row.names)
			if not child.target then return end
			-- Removing an explicit combination clears its direct style, allowing
			-- normal TS/LSP fallback and independent Mod highlights to apply.
			runtime._picker_set_style(child.target, new_value == true and parent_style or {})
			style_edits[style_edit_key(child)] = nil
			pipeline_edits[style_edit_key(child)] = nil
			rule_edits[rule_key(row.source, row.name)] = {
				source = row.source, action = row.action, typemod = row.name,
				value = new_value, target = child.target,
			}
			current_menu:set_item(index, label(row))
		end,
		on_select = function(_, index)
			local row = rows[index]
			local child = editable_child(entry, row.name, entry.type_name, row.names)
			child.back = function() open_typemods(entry, entries, selected, index) end
			open_edit(child, entries, selected)
		end,
	})
end

open_edit = function(entry, entries, selected)
	local creation = source_choice(entry)
	if creation then return open_source_choice(entry, entries, selected, creation) end

	local items = { "Pipeline", "Style" }
	if entry.kind == "Type" then
		items[3] = "TypeMods"
	end

	return menu.open({
		title = " Edit: " .. entry.name .. " ",
		items = items,
		on_back = function()
			if entry._cf_choice_back then
				entry._cf_choice_back()
			elseif entry.back then
				entry.back()
			else
				open_pick(entries, selected)
			end
		end,
		on_select = function(action)
			if action == "Style" then
				return open_style(entry, entries, selected)
			elseif action == "Pipeline" then
				return open_pipeline(entry, entries, selected)
			elseif action == "TypeMods" then
				return open_typemods(entry, entries, selected)
			end
			api.nvim_echo({ { ("ChromaFlow: %s %s -> %s"):format(entry.kind, entry.name, action), "Normal" } }, false, {})
		end,
	})
end

open_pick = function(entries, selected)
	local items = {}
	for i = 1, #entries do
		items[i] = entries[i].label
	end

	return menu.open({
		title = " ChromaFlow Pick ",
		items = items,
		selected = selected,
		on_select = function(_, index)
			open_edit(entries[index], entries, index)
		end,
	})
end

function M.open()
	local entries = items_at_cursor()
	local buf = api.nvim_get_current_buf()
	for _, entry in ipairs(entries) do
		entry.bufnr, entry.filetype = buf, vim.bo[buf].filetype
	end
	if #entries == 0 then
		api.nvim_echo({ { "ChromaFlow: no highlight at cursor", "Normal" } }, false, {})
		return nil
	end

	return open_pick(entries, 1)
end

return M
