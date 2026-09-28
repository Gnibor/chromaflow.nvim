local M = {}

local hl_runtime = require("cf.hl.runtime")
local resolver = require("cf.hl.resolver")

-- One process-wide runtime state. Public module/target/action objects are stable
-- opaque handles into these tables; they never own a second copy of state.
local current_theme
local target_catalog = {}
local runtime_cache = {}
local module_defs = {}
local requested = {}
local module_handles = {}
local action_handles = {}
local target_handles = {}
local scope_handles = {}
local overrides = {}
local sequence = 0
local transitioning = false
local timers = {}
local uv = vim.uv

local ModuleMT = {}
local GroupsMT = {}
local ActionMT = {}
local TargetMT = {}
local ScopeMT = {}

-- Keep implementation metadata out of public handles. Besides making the API
-- intentionally boring, this means arbitrary action/typemod names cannot
-- collide with fields such as `kind`, `scope`, `module` or `name`.
local module_meta = setmetatable({}, { __mode = "k" })
local groups_module = setmetatable({}, { __mode = "k" })
local action_meta = setmetatable({}, { __mode = "k" })
local target_meta = setmetatable({}, { __mode = "k" })
local scope_meta = setmetatable({}, { __mode = "k" })
local invalid_dsl_call_handler

local function invalid_dsl_call(display, line)
	if invalid_dsl_call_handler then
		if invalid_dsl_call_handler(display, line) then
			return nil
		end
	end
	error("cf.fn.runtime: " .. display .. " is not callable", 2)
end

function M._set_invalid_dsl_call_handler(handler)
	assert(
		handler == nil or type(handler) == "function",
		"cf.fn.runtime: invalid DSL call handler must be a function or nil"
	)
	invalid_dsl_call_handler = handler
end

local function validate_runtime_name(name)
	assert(type(name) == "string" and name ~= "", "cf.fn.runtime: module name must be a non-empty string")
	assert(not name:find("/", 1, true) and not name:find("\\", 1, true), "cf.fn.runtime: module name must not contain path separators")
	assert(name ~= "." and name ~= "..", "cf.fn.runtime: invalid module name")
	assert(name:sub(-3) ~= ".cf", "cf.fn.runtime: pass the module name without the .cf suffix")
	return name
end

local function target_key(kind, scope, type_name, typemod)
	return table.concat({
		kind or "",
		scope or "",
		type_name or "",
		typemod or "",
	}, "\0")
end

local function action_key(module_name, action_name)
	return module_name .. "\0" .. action_name
end

local function scope_key(kind, scope)
	return kind .. "\0" .. (scope or "")
end

local function get_hl_setup()
	return require("cf.hl.setup")
end

local function action_info(action)
	local meta = type(action) == "table" and action_meta[action] or nil
	assert(meta, "cf.fn.runtime: action must be r.groups.<name> or r.g.<name>")
	return meta
end

local function target_info(target)
	local meta = type(target) == "table" and target_meta[target] or nil
	assert(meta, "cf.fn.runtime: target must be a ChromaFlow semantic target")
	return meta
end

local function get_action(action)
	local meta = action_info(action)
	local loaded = module_defs[meta.module]
	assert(loaded, "cf.fn.runtime: runtime module '" .. meta.module .. "' is not loaded for the current theme")
	local definition = loaded.definition
	local spec = definition.groups[meta.name]
	assert(spec, "cf.fn.runtime: runtime action '" .. meta.module .. "." .. meta.name .. "' does not exist in the current theme")
	return spec, definition, meta
end

local function get_action_spec(action)
	local spec = get_action(action)
	return spec
end

local function action_target_key(action)
	local kind = action.kind
	if kind == "raw_style" or kind == "raw_link" or kind == "raw_clear" then
		return target_key("raw", nil, action.name, nil)
	end

	local owner_kind = action._cf_owner_kind
	if owner_kind == "language" or owner_kind == "plugin" or owner_kind == "ui" then
		return target_key(owner_kind, action._cf_owner_name, action.type_name, action.typemod)
	end
end

local function action_names(action)
	local kind = action.kind
	if kind == "raw_style" or kind == "raw_link" or kind == "raw_clear" then
		return { action.name }
	elseif kind == "resolver_style" then
		return resolver.runtime_style_names(
			action.type_name,
			action.typemod,
			action.filetype,
			action.targets,
			action.clear,
			action.typemod_style
		)
	elseif kind == "resolver_link" then
		return resolver.runtime_link_names(
			action.type_name,
			action.typemod,
			action.target_type,
			action.filetype,
			action.targets,
			action.clear
		)
	elseif kind == "resolver_clear" then
		return resolver.runtime_clear_names(
			action.type_name,
			action.typemod,
			action.filetype,
			action.clear
		)
	end
	return {}
end

local function action_less(a, b)
	if a.priority == b.priority then
		return a.sequence < b.sequence
	end
	return a.priority < b.priority
end

local function resolve_target_entry(meta)
	local actions = {}
	local modules = current_theme and current_theme.modules or {}
	for i = 1, #modules do
		local module = modules[i]
		for n = 1, #module.actions do
			local action = module.actions[n]
			if action_target_key(action) == meta.key then
				actions[#actions + 1] = action
			end
		end
	end
	if #actions == 0 then
		return nil
	end
	table.sort(actions, action_less)

	local names = {}
	local seen = {}
	for i = 1, #actions do
		local resolved = action_names(actions[i])
		for n = 1, #resolved do
			local name = resolved[n]
			if not seen[name] then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end
	if #names == 0 then
		return nil
	end

	-- Runtime is a sparse diff. The normal theme remains untouched in its own
	-- caches; capture only the effective base for this one semantic target when
	-- the user actually modifies it. If every concrete name is already covered
	-- by another runtime diff, fall back to the theme action's original style so
	-- apply() never compounds a previous runtime result.
	local base
	for i = 1, #names do
		local name = names[i]
		if runtime_cache[name] == nil then
			base = hl_runtime.read_effective_style(name)
			if base then
				break
			end
		end
	end
	if not base then
		for i = #actions, 1, -1 do
			local action = actions[i]
			if action.kind == "resolver_style" or action.kind == "raw_style" then
				base = action.style
				break
			elseif action.kind == "resolver_clear" or action.kind == "raw_clear" then
				break
			end
		end
	end

	return {
		names = names,
		base = base,
	}
end

local function install_theme_view(compiled)
	current_theme = compiled
	target_catalog = {}

	local loaded = compiled.runtime_modules or {}
	for name in pairs(requested) do
		module_defs[name] = loaded[name]
	end
end

local function adopt_current_theme()
	if current_theme then
		return current_theme
	end

	local theme = require("cf.theme")
	local compiled, phase = theme._runtime_state()
	if not compiled then
		return nil
	end

	compiled.runtime_modules = compiled.runtime_modules or {}
	for name in pairs(requested) do
		if not compiled.runtime_modules[name] then
			compiled.runtime_modules[name] = theme.load_runtime(compiled, name)
		end
	end

	if phase == "callbacks" then
		M._theme_prepare(compiled)
	else
		M._theme_applied(compiled)
	end
	return compiled
end

local function target_entry(target, allow_missing)
	local meta = target_info(target)
	adopt_current_theme()
	assert(current_theme, "cf.fn.runtime: no theme has been applied yet")
	local entry = target_catalog[meta.key]
	if not entry then
		entry = resolve_target_entry(meta)
		if entry then
			target_catalog[meta.key] = entry
		end
	end
	if not entry and not allow_missing then
		error("cf.fn.runtime: target is not materialized by the current theme", 3)
	end
	return entry, meta
end

local function names_for_override(override)
	local entry = target_entry(override.target, true)
	return entry and entry.names or nil, entry
end

local function sorted_overrides()
	local list = {}
	for _, override in pairs(overrides) do
		list[#list + 1] = override
	end
	table.sort(list, function(a, b)
		return a.sequence < b.sequence
	end)
	return list
end

local function now_ms()
	return uv.hrtime() / 1000000
end

local function make_timing(tick)
	local now = now_ms()
	return {
		frame = 0,
		tick = tick,
		delta = 0,
		elapsed = 0,
		started = now,
		last = now,
	}
end

local function action_tick(action)
	local _, definition, meta = get_action(action)
	return definition.group_ticks and definition.group_ticks[meta.name] or nil
end

local function runtime_build_context(definition, meta, override)
	return {
		module_name = meta.module,
		definition = definition,
		ctx = override.timing,
	}
end

-- Runtime is only a sparse diff over the already-materialized theme. The base
-- caches are never overwritten by runtime writes, so reset is simply removal of
-- the diff plus one direct write of the current semantic base.
local function recompose(affected, fallback_entry)
	if not next(affected) then
		return
	end

	local plan = {}
	local ordered = sorted_overrides()
	local build_style = get_hl_setup()._build_style

	for i = 1, #ordered do
		local override = ordered[i]
		local names, entry = names_for_override(override)
		if names and entry then
			local value
			if override.mode == "clear" then
				value = false
			else
				local spec, definition, meta = get_action(override.action)
				local runtime_context = runtime_build_context(definition, meta, override)
				if override.mode == "replace" then
					value = build_style(spec, nil, runtime_context)
				else
					value = build_style(spec, entry.base, runtime_context)
				end
			end

			for n = 1, #names do
				local name = names[n]
				if affected[name] then
					plan[name] = value
				end
			end
		end
	end

	-- Style computation above does not touch the normal highlight cache. Only the
	-- final sparse diff is written to Neovim after the complete plan succeeded.
	for name in pairs(affected) do
		local value = plan[name]
		if value == nil then
			runtime_cache[name] = nil
			hl_runtime.runtime_write(name, fallback_entry and fallback_entry.base or nil)
		elseif value == false then
			runtime_cache[name] = false
			hl_runtime.runtime_write(name, nil)
		else
			runtime_cache[name] = value
			hl_runtime.runtime_write(name, value)
		end
	end
end

local function affected_for(target)
	local affected = {}
	local entry = target_entry(target, true)
	if entry then
		for i = 1, #entry.names do
			affected[entry.names[i]] = true
		end
	end
	return affected, entry
end

local function stop_timer(key)
	local entry = timers[key]
	if not entry then
		return
	end
	timers[key] = nil
	if entry.handle and not entry.handle:is_closing() then
		entry.handle:stop()
		entry.handle:close()
	end
end

local function stop_all_timers()
	local keys = {}
	for key in pairs(timers) do
		keys[#keys + 1] = key
	end
	for i = 1, #keys do
		stop_timer(keys[i])
	end
end

local function reset_override_timing(override)
	if not override or override.mode == "clear" then
		if override then override.timing = nil end
		return nil
	end
	local tick = action_tick(override.action)
	override.timing = make_timing(tick)
	return tick
end

local function timer_tick(key, override)
	if transitioning or overrides[key] ~= override then
		return
	end
	local timing = override.timing
	if not timing or not timing.tick then
		return
	end

	local now = now_ms()
	timing.frame = timing.frame + 1
	timing.delta = now - timing.last
	timing.elapsed = now - timing.started
	timing.last = now

	local affected, entry = affected_for(override.target)
	local ok, err = pcall(recompose, affected, entry)
	if not ok then
		stop_timer(key)
		vim.schedule(function() error(err, 0) end)
	end
end

local function sync_timer(key, override, restart_timing)
	stop_timer(key)
	if not override or override.mode == "clear" then
		return
	end

	local tick
	if restart_timing or not override.timing then
		tick = reset_override_timing(override)
	else
		tick = override.timing.tick
	end
	if not tick then
		return
	end

	local handle = uv.new_timer()
	local entry = { handle = handle, override = override }
	timers[key] = entry
	handle:start(tick, tick, vim.schedule_wrap(function()
		if timers[key] ~= entry or overrides[key] ~= override then
			return
		end
		timer_tick(key, override)
	end))
end

local function change_override(target, replacement)
	local meta = target_info(target)
	adopt_current_theme()
	assert(current_theme, "cf.fn.runtime: no theme has been applied yet")

	local key = meta.key
	local previous = overrides[key]

	if replacement then
		sequence = sequence + 1
		replacement.sequence = sequence
		replacement.target = target
		reset_override_timing(replacement)
	end
	overrides[key] = replacement

	-- ColorScheme callbacks run against the normal theme base. Only mutate the
	-- sparse override state here; do not resolve/cache concrete targets yet. That
	-- happens once, after the complete callback chain, against the final base.
	if transitioning then
		stop_timer(key)
		return true
	end

	local entry = target_entry(target, false)
	local affected = {}
	for i = 1, #entry.names do
		affected[entry.names[i]] = true
	end

	local ok, err = pcall(recompose, affected, entry)
	if not ok then
		overrides[key] = previous
		error(err, 0)
	end
	sync_timer(key, replacement, false)
	if replacement == nil then
		target_catalog[key] = nil
	end
	return true
end

function M.apply(target, action)
	get_action_spec(action)
	return change_override(target, {
		mode = "apply",
		action = action,
	})
end

function M.replace(target, action)
	get_action_spec(action)
	return change_override(target, {
		mode = "replace",
		action = action,
	})
end

function M.reset(target)
	local meta = target_info(target)
	if not overrides[meta.key] then
		return false
	end
	return change_override(target, nil)
end

function M.clear(target)
	return change_override(target, { mode = "clear" })
end

function GroupsMT:__index(name)
	assert(type(name) == "string" and name ~= "", "cf.fn.runtime: runtime action name must be a non-empty string")
	local module_name = assert(groups_module[self], "cf.fn.runtime: detached groups handle")
	local key = action_key(module_name, name)
	local handle = action_handles[key]
	if not handle then
		handle = setmetatable({}, ActionMT)
		action_meta[handle] = { module = module_name, name = name }
		action_handles[key] = handle
	end
	return handle
end

function ActionMT:__tostring()
	local meta = action_meta[self]
	return meta and ("cf.runtime.action(%s.%s)"):format(meta.module, meta.name) or "cf.runtime.action(?)"
end

function ModuleMT:__index(key)
	if key == "apply" then return M.apply end
	if key == "replace" then return M.replace end
	if key == "reset" then return M.reset end
	if key == "clear" then return M.clear end

	local meta = module_meta[self]
	local loaded = meta and module_defs[meta.name] or nil
	local exports = loaded and loaded.definition and loaded.definition.exports or nil
	if exports then
		return exports[key]
	end
	return nil
end

function ModuleMT:__tostring()
	local meta = module_meta[self]
	return meta and ("cf.runtime(%s)"):format(meta.name) or "cf.runtime(?)"
end

function M._module_handle(name)
	name = validate_runtime_name(name)
	local handle = module_handles[name]
	if not handle then
		local groups = setmetatable({}, GroupsMT)
		handle = setmetatable({ groups = groups, g = groups }, ModuleMT)
		module_meta[handle] = { name = name }
		groups_module[groups] = name
		module_handles[name] = handle
	end
	return handle
end

function M.runtime(name)
	name = validate_runtime_name(name)
	local handle = M._module_handle(name)

	local was_requested = requested[name] == true
	requested[name] = true

	-- Before the first theme apply the stable handle is enough. If a theme already
	-- exists, late runtime activation adopts it lazily; concrete target names are
	-- read from the resolver's existing caches only when an override is applied.
	local ok, err = pcall(function()
		adopt_current_theme()
		if current_theme and not module_defs[name] then
			local loaded = require("cf.theme").load_runtime(current_theme, name)
			module_defs[name] = loaded
			current_theme.runtime_modules = current_theme.runtime_modules or {}
			current_theme.runtime_modules[name] = loaded
		end
	end)
	if not ok then
		if not was_requested then
			requested[name] = nil
		end
		error(err, 0)
	end

	return handle
end

function M.target(kind, scope, type_name, typemod)
	assert(kind == "language" or kind == "plugin" or kind == "ui" or kind == "raw", "cf.fn.runtime: invalid target kind")
	assert(scope == nil or (type(scope) == "string" and scope ~= ""), "cf.fn.runtime: invalid target scope")
	assert(type_name == nil or (type(type_name) == "string" and type_name ~= ""), "cf.fn.runtime: target type/name must be a non-empty string or nil")
	assert(typemod == nil or (type(typemod) == "string" and typemod ~= ""), "cf.fn.runtime: typemod must be a non-empty string or nil")
	assert(type_name ~= nil or typemod ~= nil, "cf.fn.runtime: target needs a type/name or typemod")
	assert(kind ~= "raw" or (type_name ~= nil and typemod == nil), "cf.fn.runtime: raw targets require a name and cannot have typemods")

	local key = target_key(kind, scope, type_name, typemod)
	local handle = target_handles[key]
	if not handle then
		handle = setmetatable({}, TargetMT)
		target_meta[handle] = {
			key = key,
			kind = kind,
			scope = scope,
			type_name = type_name,
			typemod = typemod,
		}
		target_handles[key] = handle
	end
	return handle
end

function TargetMT:__index(typemod)
	-- One more lookup level means an explicit type+typemod target, e.g.
	-- hl.language.lua.variable.readonly. Mod-only targets are internal handles and
	-- do not expose another lookup level.
	local meta = target_meta[self]
	if not meta or meta.type_name == nil or meta.typemod ~= nil then
		return nil
	end
	if type(typemod) ~= "string" or typemod == "" then
		return nil
	end
	return M.target(meta.kind, meta.scope, meta.type_name, typemod)
end

function TargetMT:__call()
	local meta = target_meta[self]
	if not meta then
		error("cf.fn.runtime: detached target is not callable", 2)
	end

	local prefix
	local type_name = meta.type_name
	if meta.kind == "language" then
		prefix = "l." .. tostring(meta.scope) .. (type_name and ("." .. type_name) or "")
	elseif meta.kind == "plugin" then
		prefix = "p." .. tostring(meta.scope) .. (type_name and ("." .. type_name) or "")
	elseif meta.kind == "ui" then
		prefix = "u:" .. tostring(type_name or "")
	else
		prefix = "raw:" .. tostring(type_name or "")
	end
	if meta.typemod then
		prefix = prefix .. "." .. meta.typemod
	end
	local info = debug.getinfo(2, "l")
	return invalid_dsl_call(prefix, info and info.currentline or 1)
end

function TargetMT:__tostring()
	local meta = target_meta[self]
	if not meta then return "cf.runtime.target(?)" end
	local parts = { "cf.runtime.target", meta.kind }
	if meta.scope then parts[#parts + 1] = meta.scope end
	if meta.type_name then parts[#parts + 1] = meta.type_name end
	if meta.typemod then parts[#parts + 1] = meta.typemod end
	return table.concat(parts, ".")
end

function M.scope(kind, scope)
	assert(kind == "language" or kind == "plugin", "cf.fn.runtime: scope kind must be language or plugin")
	assert(type(scope) == "string" and scope ~= "", "cf.fn.runtime: scope must be a non-empty string")
	local key = scope_key(kind, scope)
	local handle = scope_handles[key]
	if not handle then
		handle = setmetatable({}, ScopeMT)
		scope_meta[handle] = { kind = kind, scope = scope }
		scope_handles[key] = handle
	end
	return handle
end

function ScopeMT:__index(type_name)
	if type(type_name) ~= "string" or type_name == "" then
		return nil
	end
	local meta = scope_meta[self]
	if not meta then return nil end
	return M.target(meta.kind, meta.scope, type_name, nil)
end

function ScopeMT:__call()
	local meta = scope_meta[self]
	if not meta then
		error("cf.fn.runtime: detached scope is not callable", 2)
	end
	local prefix = meta.kind == "language" and "l:" or "p:"
	local info = debug.getinfo(2, "l")
	return invalid_dsl_call(prefix .. meta.scope, info and info.currentline or 1)
end

function M._requested_names()
	local out = {}
	for name in pairs(requested) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

-- Compile-time validation keeps missing runtime actions transactional: a theme
-- reload fails before ColorSchemePre/reset if an active apply/replace override
-- refers to an action that the newly selected runtime module no longer defines.
function M._validate_compiled(compiled)
	local loaded = compiled.runtime_modules or {}
	for _, override in pairs(overrides) do
		if override.mode ~= "clear" then
			local meta = action_info(override.action)
			local module = loaded[meta.module]
			assert(module, "cf.fn.runtime: runtime module '" .. meta.module .. "' is not loaded for the compiled theme")
			assert(
				module.definition.groups[meta.name] ~= nil,
				"cf.fn.runtime: runtime action '" .. meta.module .. "." .. meta.name .. "' does not exist in the compiled theme"
			)
		end
	end
	return true
end

-- Called before ColorScheme callbacks. The normal theme has already been
-- materialized at this point. Drop the old sparse diff state; callbacks see the
-- normal theme and runtime calls from them only update override state until the
-- callback chain has completed.
function M._theme_prepare(compiled)
	stop_all_timers()
	install_theme_view(compiled)
	runtime_cache = {}
	transitioning = true
end

-- Called after the normal theme and every ColorScheme callback have completed.
-- Rebuild only targets that actually have a runtime override, then write that
-- sparse diff back on top of the new base.
function M._theme_applied(compiled)
	-- Normal reloads already installed the new view in _theme_prepare(). Late
	-- runtime activation has no prepare phase, so adopt that already-applied theme
	-- exactly once here instead of rebuilding the caches a second time.
	if current_theme ~= compiled then
		install_theme_view(compiled)
		runtime_cache = {}
	end
	transitioning = false

	local affected = {}
	for _, override in pairs(overrides) do
		reset_override_timing(override)
		local names = names_for_override(override)
		if names then
			for i = 1, #names do
				affected[names[i]] = true
			end
		end
	end

	recompose(affected, nil)

	for key, override in pairs(overrides) do
		sync_timer(key, override, false)
	end
end

-- Picker edits are ephemeral runtime previews. They write into the existing
-- sparse runtime cache directly, so a normal theme reload discards them while
-- ordinary runtime action overrides keep their own lifecycle unchanged.
-- Cold picker path: bind an existing session highlight which has no theme
-- declaration yet. Discovery supplies concrete names; the resolver is unchanged.
function M._picker_bind_target(target, names, base)
	local entry, meta = target_entry(target, true)
	if entry then return end
	assert(type(names) == "table" and #names > 0, "cf.fn.runtime: no existing picker targets")
	local copied = {}
	for i, name in ipairs(names) do
		assert(vim.fn.hlexists(name) == 1, "cf.fn.runtime: picker target does not exist")
		copied[i] = name
	end
	target_catalog[meta.key] = { names = copied, base = base }
end

-- Status readers opt out of undo snapshots; editor/save callers keep the
-- existing default. Both paths return the same base/runtime style references.
function M._picker_style_state(target, capture_snapshot)
	local entry = target_entry(target, false)
	local source_style
	local runtime_style
	local has_runtime = false
	local snapshots
	if capture_snapshot ~= false then snapshots = {} end

	for i = 1, #entry.names do
		local name = entry.names[i]
		if snapshots then
			snapshots[name] = {
				highlight = vim.api.nvim_get_hl(0, { name = name, link = true, create = false }),
				runtime = runtime_cache[name],
			}
		end
		if not source_style then
			source_style = hl_runtime.group_style(name)
		end
		local value = runtime_cache[name]
		if value ~= nil and not has_runtime then
			runtime_style = value
			has_runtime = true
		end
	end

	local base = source_style or entry.base
	local current = base
	if has_runtime then
		current = runtime_style
	end
	return {
		base = base,
		runtime = runtime_style,
		has_runtime = has_runtime,
		current = current,
		names = entry.names,
		snapshots = snapshots,
	}
end

-- Restore the exact sparse-runtime state captured by _picker_style_state().
-- This is used by picker previews on cancel/back: an absent runtime diff must
-- become absent again rather than being replaced by a redundant copy of base.
function M._picker_restore_style(target, state)
	assert(type(state) == "table", "cf.fn.runtime: picker style state must be a table")
	local entry = target_entry(target, false)
	local value = state.runtime
	for i = 1, #entry.names do
		local name = entry.names[i]
		local saved = state.snapshots and state.snapshots[name]
		if saved then
			runtime_cache[name] = saved.runtime
			vim.api.nvim_set_hl(0, name, saved.highlight)
		elseif state.has_runtime then
			runtime_cache[name] = value
			hl_runtime.runtime_write(name, value == false and nil or value)
		else
			runtime_cache[name] = nil
			hl_runtime.runtime_write(name, state.base)
		end
	end
	return state.has_runtime and value or state.base
end

function M._picker_set_style(target, style)
	assert(type(style) == "table", "cf.fn.runtime: picker style must be a table")
	local entry = target_entry(target, false)
	-- Reuse the normal immutable style intern cache. The runtime cache then holds
	-- the exact same canonical full-style objects as compiled styles whenever the
	-- values are equal, which keeps the later save diff straightforward.
	local value = get_hl_setup()._build_style(style, nil, nil)
	for i = 1, #entry.names do
		local name = entry.names[i]
		runtime_cache[name] = value
		hl_runtime.runtime_write(name, value)
	end
	return value
end

function M._overlay_size()
	local count = 0
	for _ in pairs(runtime_cache) do
		count = count + 1
	end
	return count
end

function M._current_theme()
	return current_theme
end

return M
