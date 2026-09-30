local M = {}

local color = require("cf.color")
local diagnostic = require("cf.diagnostic")
local pipeline = require("cf.hl.pipeline")
local resolver = require("cf.hl.resolver")
local hl_runtime = require("cf.hl.runtime")

-- Public theme-module environment. `colors` is replaced with the currently
-- resolved palette before any .cf module is executed.
M.colors = {}
M.mix = pipeline.mix
M.opacity = pipeline.opacity
M.brightness = pipeline.brightness
M.lighten = pipeline.lighten
M.darken = pipeline.darken
M.shiftHue = pipeline.shiftHue
M.gamma = pipeline.gamma

local TARGET_KEYS = { "vim", "ts", "lsp" }
local CLEAR_ALL = { vim = true, ts = true, lsp = true }

local current_targets = {
	vim = true,
	ts = true,
	lsp = true,
}
local current_global_clear = {}

local UI_TARGET_DEFAULTS = {
	vim = true,
	ts = false,
	lsp = false,
}

local PLUGIN_TARGET_DEFAULTS = {
	vim = false,
	ts = false,
	lsp = false,
}

-- Session-lifetime style interning. `require("cf.hl.setup")` is cached by Lua,
-- so this table and every interned complete hl_set live until the Neovim Lua
-- state ends (unless somebody explicitly evicts this module from package.loaded).
local style_cache = {}
local style_cache_count = 0

-- Global declaration order is also session-local. Priorities are sorted first;
-- this monotonically increasing sequence makes equal-priority order explicit
-- and stable across all modules in one compiled theme.
local action_sequence = 0

-- Theme-loader source context. Lua tail-call optimization can remove the .cf
-- frame around l/p/u/r.setup(), so the loader-owned file remains the stable
-- anchor. Caller lines come from debug.getinfo(); when picker/ColorTrace needs
-- precise source data, Lua Tree-sitter refines DSL calls to end-exclusive ranges.
local source_stack = {}
local source_range_cache = {}
local source_range_cache_active = false
local error_source_hint
local colortrace_enabled = false
local colortrace_picker_enabled = false
local colortrace_active = false

local GROUP_RESERVED = {
	pipeline = true,
	types = true,
	typemods = true,
	style_targets = true,
	style_targets_clear = true,
	priority = true,
	link = true,
	clear = true,
}

-- nvim_set_hl() fields that fit ChromaFlow's immutable full-style model.
-- `link` is DSL metadata handled explicitly; `update`/`link_global` would break
-- the full replacement/cache semantics and are intentionally not style fields.
local HL_FIELDS = {
	altfont = true,
	bg = true,
	bg_indexed = true,
	blend = true,
	blink = true,
	bold = true,
	conceal = true,
	cterm = true,
	ctermbg = true,
	ctermfg = true,
	default = true,
	dim = true,
	fg = true,
	fg_indexed = true,
	force = true,
	italic = true,
	nocombine = true,
	overline = true,
	reverse = true,
	sp = true,
	standout = true,
	strikethrough = true,
	undercurl = true,
	underdashed = true,
	underdotted = true,
	underdouble = true,
	underline = true,
}

local RANGE_CALLS = {
	group = true,
	link = true,
	setup = true,
}

local function source_file_signature(path)
	local stat = vim.uv.fs_stat(path)
	if not stat then
		return nil
	end
	local mtime = stat.mtime or {}
	return table.concat({
		tostring(stat.size or 0),
		tostring(mtime.sec or 0),
		tostring(mtime.nsec or 0),
	}, ":")
end

local function build_source_ranges(path)
	local signature = source_file_signature(path)
	local cached = source_range_cache[path]
	if cached and cached.signature == signature then
		return cached.ranges
	end

	local fd = io.open(path, "rb")
	if not fd then
		return nil
	end
	local source = fd:read("*a")
	fd:close()

	local ok_parser, parser = pcall(vim.treesitter.get_string_parser, source, "lua")
	if not ok_parser or not parser then
		return nil
	end
	local ok_trees, trees = pcall(parser.parse, parser)
	if not ok_trees or type(trees) ~= "table" or not trees[1] then
		return nil
	end

	local ranges = {
		group = {},
		link = {},
		setup = {},
		pipeline = {},
	}

	local function visit(node)
		if node:type() == "function_call" then
			local name_node = node:field("name")[1]
			local call_node
			if name_node then
				if name_node:type() == "method_index_expression" then
					call_node = name_node:field("method")[1]
				elseif name_node:type() == "dot_index_expression" then
					call_node = name_node:field("field")[1]
				end
			end

			if call_node then
				local name = vim.treesitter.get_node_text(call_node, source)
				if RANGE_CALLS[name] then
					local start_row, start_col, end_row, end_col = node:range()
					local direct_return = false
					local parent = node:parent()
					while parent do
						if parent:type() == "function_call" then break end
						if parent:type() == "return_statement" then
							direct_return = true
							break
						end
						parent = parent:parent()
					end
					ranges[name][#ranges[name] + 1] = {
						line = start_row + 1,
						col = start_col + 1,
						end_line = end_row + 1,
						end_col = end_col + 1,
						direct_return = direct_return,
					}
				end
			end

			if name_node then
				local full_name = vim.treesitter.get_node_text(name_node, source)
				local family, channel = full_name:match("%.([%a_][%w_]*)%.(fg)$")
				if not family then family, channel = full_name:match("%.([%a_][%w_]*)%.(bg)$") end
				if not family then family, channel = full_name:match("%.([%a_][%w_]*)%.(sp)$") end
				if not family then family, channel = full_name:match("%.([%a_][%w_]*)%.(cfg)$") end
				if not family then family, channel = full_name:match("%.([%a_][%w_]*)%.(cbg)$") end
				if family and (family == "mix" or family == "opacity" or family == "brightness" or family == "lighten" or family == "darken" or family == "shiftHue" or family == "gamma") then
					local start_row, start_col, end_row, end_col = node:range()
					local key = family .. "." .. channel
					local list = ranges.pipeline[key]
					if not list then list = {}; ranges.pipeline[key] = list end
					list[#list + 1] = {
						line = start_row + 1,
						col = start_col + 1,
						end_line = end_row + 1,
						end_col = end_col + 1,
					}
				end
			end
		end

		for child in node:iter_children() do
			visit(child)
		end
	end

	visit(trees[1]:root())
	for _, name in ipairs({ "group", "link", "setup" }) do
		table.sort(ranges[name], function(a, b)
			if a.line ~= b.line then return a.line < b.line end
			return a.col < b.col
		end)
	end
	for _, list in pairs(ranges.pipeline) do
		table.sort(list, function(a, b)
			if a.line ~= b.line then return a.line < b.line end
			return a.col < b.col
		end)
	end

	source_range_cache[path] = {
		signature = signature,
		ranges = ranges,
	}
	source_range_cache_active = true
	return ranges
end

local function picker_enabled()
	if colortrace_picker_enabled then
		return true
	end
	if source_range_cache_active then
		source_range_cache = {}
		source_range_cache_active = false
	end
	return false
end

local function source_context_ranges(context)
	if not context.ranges_enabled then
		return nil
	end
	if context.ranges_loaded then
		return context.ranges
	end
	context.ranges_loaded = true
	context.ranges = build_source_ranges(context.file)
	return context.ranges
end

local function take_source_range(context, call_name, line)
	if not context.ranges_enabled or not call_name or not RANGE_CALLS[call_name] then
		return nil
	end

	local ranges = source_context_ranges(context)
	local list = ranges and ranges[call_name]
	if not list or #list == 0 then
		return nil
	end

	if not context.range_used then return nil end
	local used = context.range_used[call_name]
	if not used then
		used = {}
		context.range_used[call_name] = used
	end

	local best
	for i = 1, #list do
		local range = list[i]
		if not used[i] and range.line == line then
			best = i
			break
		end
	end

	if not best then
		for i = 1, #list do
			local range = list[i]
			if not used[i] and range.line <= line and line <= range.end_line then
				best = i
				break
			end
		end
	end

	-- `return l.setup(...)`/`return r.setup(...)` is normally a Lua tail call, so
	-- debug.getinfo() may no longer expose the .cf caller line at all. The module
	-- contract gives us a stronger anchor: use the top-level returned setup call.
	if not best and call_name == "setup" then
		for i = 1, #list do
			if not used[i] and list[i].direct_return then
				best = i
				break
			end
		end
	end

	if not best then
		return nil
	end
	used[best] = true
	return list[best]
end

local function take_pipeline_source(context, key, line)
	if not context or not context.trace_enabled then return nil end
	local ranges = source_context_ranges(context)
	local list = ranges and ranges.pipeline and ranges.pipeline[key]
	if not list then return nil end
	local used = context.pipeline_range_used
	for i = 1, #list do
		local range = list[i]
		if not used[key .. ":" .. i] and range.line == line then
			used[key .. ":" .. i] = true
			return range
		end
	end
	return nil
end

local function source_from_range(file, line, range)
	if not range then
		return {
			file = file,
			line = line,
			col = 1,
		}
	end
	return {
		file = file,
		line = range.line,
		col = range.col,
		end_line = range.end_line,
		end_col = range.end_col,
	}
end

local function capture_source(level, call_name)
	local current = source_stack[#source_stack]
	if current then
		-- The loader already owns the normalized file path. Lua supplies the caller
		-- line; Tree-sitter is only used to refine that DSL call to its full range.
		local info = debug.getinfo(level or 2, "l")
		local line = info and info.currentline > 0 and info.currentline or 1
		return source_from_range(current.file, line, take_source_range(current, call_name, line))
	end

	-- Direct low-level use outside the theme loader has no source context. Keep the
	-- start-only fallback, but refine it too when a Lua parser is available.
	local info = debug.getinfo(level or 2, "Sl")
	if info and type(info.source) == "string" and info.source:sub(1, 1) == "@" then
		local file = vim.fs.normalize(info.source:sub(2))
		local line = info.currentline > 0 and info.currentline or 1
		local ranges_enabled = picker_enabled()
		local context = {
			file = file,
			ranges_enabled = ranges_enabled,
			range_used = ranges_enabled and {} or nil,
		}
		return source_from_range(file, line, take_source_range(context, call_name, line))
	end
	return nil
end

local function trace_channel_api(family, api)
	local out = {}
	for _, channel in ipairs({ "fg", "bg", "sp", "cfg", "cbg" }) do
		local builder = api[channel]
		local key = family .. "." .. channel
		out[channel] = function(...)
			local operation = builder(...)
			local current = source_stack[#source_stack]
			if current and current.trace_enabled then
				local info = debug.getinfo(2, "l")
				local line = info and info.currentline > 0 and info.currentline or 1
				operation._cf_source = source_from_range(current.file, line, take_pipeline_source(current, key, line))
				operation._cf_color_trace = current.color_trace_visible or nil
			end
			return operation
		end
	end
	return out
end

function M._colortrace_mode(color_trace_enabled_, picker_enabled_)
	colortrace_enabled = color_trace_enabled_ == true
	colortrace_picker_enabled = picker_enabled_ == true
	if not colortrace_picker_enabled and source_range_cache_active then
		source_range_cache = {}
		source_range_cache_active = false
	end
	colortrace_active = colortrace_enabled or colortrace_picker_enabled
	if colortrace_active then
		M.mix = trace_channel_api("mix", pipeline.mix)
		M.opacity = trace_channel_api("opacity", pipeline.opacity)
		M.brightness = trace_channel_api("brightness", pipeline.brightness)
		M.lighten = trace_channel_api("lighten", pipeline.lighten)
		M.darken = trace_channel_api("darken", pipeline.darken)
		M.shiftHue = trace_channel_api("shiftHue", pipeline.shiftHue)
		M.gamma = trace_channel_api("gamma", pipeline.gamma)
	else
		M.mix = pipeline.mix
		M.opacity = pipeline.opacity
		M.brightness = pipeline.brightness
		M.lighten = pipeline.lighten
		M.darken = pipeline.darken
		M.shiftHue = pipeline.shiftHue
		M.gamma = pipeline.gamma
	end
end

local function refine_source_col(source)
	if not source or source.line < 1 then
		return source
	end
	-- A successful Tree-sitter match already has the exact call column and range.
	if source.end_line ~= nil and source.end_col ~= nil then
		return source
	end
	local fd = io.open(source.file, "rb")
	if not fd then
		return source
	end
	local line
	for _ = 1, source.line do
		line = fd:read("*l")
		if line == nil then
			break
		end
	end
	fd:close()
	if line then
		local first = line:find("%S")
		if first then
			return {
				file = source.file,
				line = source.line,
				col = first,
				end_line = source.end_line,
				end_col = source.end_col,
			}
		end
	end
	return source
end

local function hint_unnecessary(message, source, context)
	if not diagnostic._enabled("hint") then
		return
	end
	if not source then
		-- This should only happen for direct low-level API use outside a .cf chunk.
		-- Keep a quiet fallback instead of fabricating a source location.
		vim.notify("cf.nvim: " .. message, vim.log.levels.INFO)
		return
	end
	diagnostic.report("hint", {
		message = message,
		source = refine_source_col(source),
		context = context,
		tags = { diagnostic.tag.UNNECESSARY },
	})
end

local function report_invalid_dsl_call(display, line)
	local current = source_stack[#source_stack]
	if not current then
		return false
	end
	if not diagnostic._enabled("hint") then
		return true
	end

	diagnostic.report("hint", {
		message = "cf.hl.setup: unknown DSL call " .. display .. "(...); ignored",
		source = refine_source_col({
			file = current.file,
			line = type(line) == "number" and line > 0 and line or 1,
			col = 1,
		}),
		context = { kind = "dsl", name = display },
	})
	return true
end

require("cf.fn.runtime")._set_invalid_dsl_call_handler(report_invalid_dsl_call)

local function validate_targets(value, where)
	if value == nil then
		return
	end
	assert(type(value) == "table", where .. " must be a table")
	for i = 1, 3 do
		local key = TARGET_KEYS[i]
		local v = value[key]
		assert(v == nil or type(v) == "boolean", where .. "." .. key .. " must be boolean or nil")
	end
end

local function targets_with_defaults(defaults, overrides)
	local out = {}
	for i = 1, 3 do
		local key = TARGET_KEYS[i]
		local value = overrides and overrides[key]
		out[key] = value ~= nil and value or defaults[key]
	end
	return out
end

local function validate_priority(value, where, inherited)
	if value == nil then
		return inherited or 0
	end
	assert(type(value) == "number" and value == value, where .. " must be a number")
	return value
end

local function validate_name(value, where)
	assert(type(value) == "string" and value ~= "", where .. " must be a non-empty string")
	return value
end

local function copy_clear(a, b)
	if not a and not b then
		return nil
	end
	return {
		vim = (a and a.vim == true) or (b and b.vim == true) or nil,
		ts = (a and a.ts == true) or (b and b.ts == true) or nil,
		lsp = (a and a.lsp == true) or (b and b.lsp == true) or nil,
	}
end

local function effective_targets(module_targets, group_targets)
	local out = {}
	for i = 1, 3 do
		local key = TARGET_KEYS[i]
		if current_targets[key] == false then
			out[key] = false
		elseif group_targets and group_targets[key] ~= nil then
			out[key] = group_targets[key]
		elseif module_targets and module_targets[key] ~= nil then
			out[key] = module_targets[key]
		else
			out[key] = current_targets[key]
		end
	end
	return out
end

local function normalize_palette_table(t, seen)
	seen = seen or {}
	if seen[t] then
		return
	end
	seen[t] = true

	for key, value in pairs(t) do
		if type(value) == "string" then
			local len = #value
			if (len == 7 or len == 9) and value:byte(1) == 35 then -- #
				t[key] = color.from_hex(value)
			end
		elseif type(value) == "table" then
			normalize_palette_table(value, seen)
		end
	end
end

local function sig_value(value, seen)
	local t = type(value)
	if t == "nil" then return "z" end
	if t == "boolean" then return value and "b1" or "b0" end
	if t == "number" then return "n" .. string.format("%.17g", value) end
	if t == "string" then return "s" .. #value .. ":" .. value end
	if t ~= "table" then
		error("cf.hl.setup: unsupported hl_set value type " .. t, 4)
	end

	seen = seen or {}
	if seen[value] then
		error("cf.hl.setup: cyclic table inside hl_set", 4)
	end
	seen[value] = true

	local parts = {}
	for key, item in pairs(value) do
		local ks = sig_value(key, seen)
		local vs = sig_value(item, seen)
		parts[#parts + 1] = ks .. "=" .. vs
	end
	table.sort(parts)
	seen[value] = nil
	return "t{" .. table.concat(parts, ";") .. "}"
end

local function intern_style(style)
	local key = sig_value(style)
	local cached = style_cache[key]
	if cached then
		return cached
	end
	style_cache[key] = style
	style_cache_count = style_cache_count + 1
	return style
end

local function normalize_style_color(value)
	if type(value) == "string" then
		local len = #value
		if (len == 7 or len == 9) and value:byte(1) == 35 then
			return color.from_hex(value)
		end
	end
	return value
end

local function has_style_fields(spec)
	for key in pairs(spec) do
		if not GROUP_RESERVED[key] then
			return true
		end
	end
	return false
end

local runtime_func_meta = setmetatable({}, { __mode = "k" })
local RuntimeFuncMT = {}

local function runtime_func_operation(module_name, name, tick)
	local operation = setmetatable({}, RuntimeFuncMT)
	runtime_func_meta[operation] = {
		module = module_name,
		name = name,
		tick = tick,
	}
	return operation
end

function RuntimeFuncMT:__index(key)
	if type(key) ~= "number" then
		return nil
	end
	assert(key == key and key >= 1 and key % 1 == 0, "cf.hl.setup: runtime func tick must be a positive integer in milliseconds")
	local meta = assert(runtime_func_meta[self], "cf.hl.setup: detached runtime func operation")
	return runtime_func_operation(meta.module, meta.name, key)
end

function RuntimeFuncMT:__tostring()
	local meta = runtime_func_meta[self]
	if not meta then
		return "cf.runtime.func(?)"
	end
	local suffix = meta.tick and ("[%d]"):format(meta.tick) or ""
	return ("cf.runtime.func(%s.%s)%s"):format(meta.module, meta.name, suffix)
end

local function normalize_complete_style(value, where, reuse)
	assert(type(value) == "table", where .. " must return a style table or nil")
	local out = reuse and value or {}
	for key, item in pairs(value) do
		assert(HL_FIELDS[key] == true, where .. " returned unknown nvim_set_hl style field '" .. tostring(key) .. "'")
		if key == "fg" or key == "bg" or key == "sp" then
			out[key] = normalize_style_color(item)
		elseif not reuse then
			out[key] = item
		end
	end
	return out
end

local function runtime_func_context(base, tick)
	base = base or {}
	return {
		frame = base.frame or 0,
		tick = tick,
		delta = base.delta or 0,
		elapsed = base.elapsed or 0,
	}
end

local function commit_cterm(style, cfg, cbg, cfg_changed, cbg_changed)
	if cfg_changed then style.ctermfg = color.to_cterm(cfg) end
	if cbg_changed then style.ctermbg = color.to_cterm(cbg) end
end

local function apply_style_pipeline(style, operations, runtime_context, source)
	if operations == nil then
		return style, false
	end
	assert(type(operations) == "table", "cf.hl.pipeline: pipeline must be a table")

	local dynamic = false
	local single = {}
	local colortrace = colortrace_active and package.loaded["cf.colortrace"] or nil
	local cfg, cbg
	local cfg_loaded, cbg_loaded = false, false
	local cfg_changed, cbg_changed = false, false
	for i = 1, #operations do
		local operation = operations[i]
		local func_meta = type(operation) == "table" and runtime_func_meta[operation] or nil
		if func_meta then
			-- User callbacks see real cterm indices, never our ARGB working values.
			if cfg_changed or cbg_changed then
				commit_cterm(style, cfg, cbg, cfg_changed, cbg_changed)
				cfg, cbg = nil, nil
				cfg_loaded, cbg_loaded = false, false
				cfg_changed, cbg_changed = false, false
			end
			dynamic = true
			assert(runtime_context ~= nil, "cf.hl.setup: runtime functions are only valid in runtime actions")
			assert(
				runtime_context.module_name == func_meta.module,
				"cf.hl.setup: runtime function belongs to a different runtime module"
			)
			local definition = runtime_context.definition
			local fn = definition and definition.exports and definition.exports[func_meta.name]
			assert(type(fn) == "function", "cf.hl.setup: runtime function '" .. func_meta.name .. "' is not defined")

			local result = fn(style, runtime_func_context(runtime_context.ctx, func_meta.tick))
			if result ~= nil then
				style = normalize_complete_style(result, "cf.hl.setup: runtime function '" .. func_meta.name .. "'", false)
			else
				style = normalize_complete_style(style, "cf.hl.setup: runtime function '" .. func_meta.name .. "'", true)
			end
		else
			assert(type(operation) == "table", "cf.hl.pipeline: pipeline entries must be operations")
			local channel = operation[2]
			if channel == 4 then -- cfg
				if not cfg_loaded then
					if style.ctermfg ~= nil then cfg = color.from_cterm(style.ctermfg) end
					cfg_loaded = true
				end
				cfg_changed = true
			elseif channel == 5 then -- cbg
				cbg_changed = true
			end
			-- Decode a terminal background only when it is manipulated or actually
			-- used as the backdrop of opacity.cfg (opcode 2).
			if (channel == 5 or (channel == 4 and operation[1] == 2)) and not cbg_loaded then
				if style.ctermbg ~= nil then cbg = color.from_cterm(style.ctermbg) end
				cbg_loaded = true
			end
			local trace_source = colortrace and operation._cf_source or nil
			if trace_source then
				local trace
				style.fg, style.bg, style.sp, trace, cfg, cbg = pipeline.color_trace_apply(
					style.fg, style.bg, style.sp, operation, cfg, cbg)
				colortrace._record(source, trace_source, trace, i, operation._cf_color_trace == true)
			else
				single[1] = operation
				style.fg, style.bg, style.sp, cfg, cbg = pipeline.apply(
					style.fg, style.bg, style.sp, single, cfg, cbg)
			end
		end
	end
	single[1] = nil
	if cfg_changed or cbg_changed then commit_cterm(style, cfg, cbg, cfg_changed, cbg_changed) end
	return style, dynamic
end

local function build_style(spec, base, runtime_context, source)
	assert(type(spec) == "table", "cf.hl.setup: group/style definition must be a table")

	local style = {}
	if base then
		for key, value in pairs(base) do
			style[key] = value
		end
	end

	for key, value in pairs(spec) do
		if not GROUP_RESERVED[key] then
			assert(HL_FIELDS[key] == true, "cf.hl.setup: unknown nvim_set_hl style field '" .. tostring(key) .. "'")
			if key == "fg" or key == "bg" or key == "sp" then
				style[key] = normalize_style_color(value)
			else
				style[key] = value
			end
		end
	end

	local dynamic
	style, dynamic = apply_style_pipeline(style, spec.pipeline, runtime_context, source)

	-- Runtime functions may intentionally create a different style every tick.
	-- Do not pin those transient styles in the session-lifetime intern cache.
	if dynamic then
		return style
	end
	return intern_style(style)
end

local function collect_types(primary, extra)
	validate_name(primary, "cf.hl.setup: group name")
	local names = { primary }
	local seen = { [primary] = true }
	if extra ~= nil then
		assert(type(extra) == "table", "cf.hl.setup: types must be an array")
		for i = 1, #extra do
			local name = extra[i]
			validate_name(name, "cf.hl.setup: types entry")
			if not seen[name] then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end
	return names
end

local function add_action(actions, priority, kind, data)
	action_sequence = action_sequence + 1
	data.priority = priority
	data.sequence = action_sequence
	data.kind = kind
	-- Picker-only source ownership is attached while the exact declaration range
	-- is already known. Normal compiles keep actions unchanged and pay no extra
	-- metadata cost.
	if colortrace_picker_enabled then
		data._cf_source = error_source_hint
	end
	actions[#actions + 1] = data
	return data
end

local function run_action(action)
	local kind = action.kind
	if kind == "resolver_style" then
		local warning = resolver.resolve(
			action.type_name,
			action.typemod,
			action.style,
			action.filetype,
			action.targets,
			action.clear,
			action.typemod_style
		)
		if warning == "unresolved_literal" and action._cf_type_hint_source then
			hint_unnecessary(
				'type "' .. action.type_name .. '" uses literal fallback',
				action._cf_type_hint_source,
				{ kind = "type", name = action.type_name }
			)
		end
	elseif kind == "resolver_link" then
		resolver.link(
			action.type_name,
			action.typemod,
			action.target_type,
			action.filetype,
			action.targets,
			action.clear
		)
	elseif kind == "resolver_clear" then
		resolver.clear(action.type_name, action.typemod, action.filetype, action.clear)
	elseif kind == "raw_style" then
		hl_runtime.apply_raw(action.name, action.style, action.clear)
	elseif kind == "raw_link" then
		hl_runtime.apply_raw_link(action.name, action.target, action.clear)
	elseif kind == "raw_clear" then
		hl_runtime.clear_raw(action.name)
	else
		error("cf.hl.setup: unknown compiled action kind " .. tostring(kind), 2)
	end
end

local function action_less(a, b)
	if a.priority == b.priority then
		return a.sequence < b.sequence
	end
	return a.priority < b.priority
end

local function apply_actions(actions)
	if #actions == 0 then
		return
	end
	table.sort(actions, action_less)
	for i = 1, #actions do
		run_action(actions[i])
	end
end

local language_api = {}
local plugin_api = {}
local ui_api = {}
local raw_api = {}
local runtime_api = {}
local runtime_definition_stack = {}
local runtime_definition_meta = setmetatable({}, { __mode = "k" })
local RuntimeDefinitionMT = {}

local RUNTIME_RESERVED_EXPORTS = {
	group = true,
	func = true,
	setup = true,
	groups = true,
	g = true,
	apply = true,
	replace = true,
	reset = true,
	clear = true,
}

local function runtime_declaration(name, spec)
	validate_name(name, "cf.hl.setup: runtime group name")
	assert(type(spec) == "table", "cf.hl.setup: runtime group definition must be a table")

	local useful = false
	for key in pairs(spec) do
		if key == "pipeline" then
			assert(type(spec.pipeline) == "table", "cf.hl.setup: runtime group pipeline must be a table")
			useful = true
		else
			assert(HL_FIELDS[key] == true, "cf.hl.setup: runtime group does not support field '" .. tostring(key) .. "'")
			useful = true
		end
	end
	assert(useful, "cf.hl.setup: runtime group must contain a style field or pipeline")

	return {
		_cf_runtime_declaration = true,
		name = name,
		spec = spec,
		source = capture_source(3, "group"),
	}
end

local function definition_info(proxy)
	return assert(runtime_definition_meta[proxy], "cf.hl.setup: detached runtime module definition")
end

local function runtime_group_tick(module_name, group_name, spec, exports)
	local tick
	local operations = spec.pipeline
	if operations == nil then
		return nil
	end

	for i = 1, #operations do
		local operation = operations[i]
		local meta = type(operation) == "table" and runtime_func_meta[operation] or nil
		if meta then
			assert(meta.module == module_name, "cf.hl.setup: runtime group '" .. group_name .. "' uses a function from another runtime module")
			assert(type(exports[meta.name]) == "function", "cf.hl.setup: runtime function '" .. meta.name .. "' is not defined on r")
			if meta.tick ~= nil then
				if tick == nil then
					tick = meta.tick
				else
					assert(tick == meta.tick, "cf.hl.setup: runtime group '" .. group_name .. "' cannot use different func tick intervals")
				end
			end
		end
	end
	return tick
end

local function runtime_definition_group(proxy, name, spec)
	definition_info(proxy)
	return runtime_declaration(name, spec)
end

local function runtime_definition_func(proxy, name)
	local meta = definition_info(proxy)
	validate_name(name, "cf.hl.setup: runtime function name")
	return runtime_func_operation(meta.name, name, nil)
end

local function runtime_definition_setup(proxy, spec)
	local meta = definition_info(proxy)
	local source = capture_source(3, "setup")
	assert(type(spec) == "table", "cf.hl.setup: runtime setup expects a declaration array")
	assert(not meta.setup_called, "cf.hl.setup: runtime setup may only be called once per runtime module load")

	local groups = {}
	local group_ticks = {}
	local group_sources = {}
	for i = 1, #spec do
		local item = spec[i]
		assert(
			type(item) == "table" and item._cf_runtime_declaration == true,
			"cf.hl.setup: runtime setup entries must be r:group() declarations"
		)
		assert(groups[item.name] == nil, "cf.hl.setup: duplicate runtime group '" .. item.name .. "'")
		groups[item.name] = item.spec
		group_ticks[item.name] = runtime_group_tick(meta.name, item.name, item.spec, meta.exports)
		group_sources[item.name] = item.source
	end

	meta.setup_called = true
	local definition = {
		_cf_runtime_module = true,
		name = meta.name,
		groups = groups,
		group_ticks = group_ticks,
		group_sources = group_sources,
		declarations = spec,
		source = source,
		exports = meta.exports,
	}
	meta.definition = definition
	return definition
end

function RuntimeDefinitionMT:__index(key)
	local meta = definition_info(self)
	if key == "group" then
		return runtime_definition_group
	elseif key == "func" then
		return runtime_definition_func
	elseif key == "setup" then
		return function(spec) return runtime_definition_setup(self, spec) end
	elseif key == "groups" or key == "g" then
		return require("cf.fn.runtime")._module_handle(meta.name).groups
	elseif key == "apply" then
		return require("cf.fn.runtime").apply
	elseif key == "replace" then
		return require("cf.fn.runtime").replace
	elseif key == "reset" then
		return require("cf.fn.runtime").reset
	elseif key == "clear" then
		return require("cf.fn.runtime").clear
	end
	return meta.exports[key]
end

function RuntimeDefinitionMT:__newindex(key, value)
	local meta = definition_info(self)
	assert(not RUNTIME_RESERVED_EXPORTS[key], "cf.hl.setup: runtime export name '" .. tostring(key) .. "' is reserved")
	meta.exports[key] = value
end

function RuntimeDefinitionMT:__call(name)
	return require("cf.fn.runtime").runtime(name)
end

function RuntimeDefinitionMT:__tostring()
	local meta = runtime_definition_meta[self]
	return meta and ("cf.runtime.definition(%s)"):format(meta.name) or "cf.runtime.definition(?)"
end

local function new_runtime_definition(name)
	local proxy = setmetatable({}, RuntimeDefinitionMT)
	runtime_definition_meta[proxy] = {
		name = name,
		exports = {},
		setup_called = false,
	}
	return proxy
end

setmetatable(runtime_api, {
	__call = function(_, name)
		return require("cf.fn.runtime").runtime(name)
	end,
})

-- Theme fallback is resolved by semantic module identity, not by filename.
-- During the active pass identities are only collected; they never suppress
-- another active module. The finished active registry becomes read-only input
-- for the fallback pass, and fallback modules never extend it.
local compile_phase
local active_registry

local function declaration(kind, action, name, target, spec)
	return {
		_cf_declaration = true,
		kind = kind,
		action = action,
		name = name,
		target = target,
		spec = spec,
		source = capture_source(3, action),
	}
end

function language_api:group(name, spec)
	return declaration("language", "group", name, nil, spec)
end

function language_api:link(source, target)
	return declaration("language", "link", source, target, nil)
end

function plugin_api:group(name, spec)
	return declaration("plugin", "group", name, nil, spec)
end

function plugin_api:link(source, target)
	return declaration("plugin", "link", source, target, nil)
end

function ui_api:group(name, spec)
	return declaration("ui", "group", name, nil, spec)
end

function ui_api:link(source, target)
	return declaration("ui", "link", source, target, nil)
end

function raw_api:group(name, spec)
	return declaration("raw", "group", name, nil, spec)
end

function raw_api:link(source, target)
	return declaration("raw", "link", source, target, nil)
end

local function module_declarations(spec, kind)
	local declarations = {}
	local last = 0
	for key in pairs(spec) do
		if type(key) == "number" and key >= 1 and key % 1 == 0 and key > last then
			last = key
		end
	end

	for i = 1, last do
		local item = spec[i]
		if item ~= nil then
			assert(
				type(item) == "table" and item._cf_declaration == true,
				"cf.hl.setup: module array entries must be group()/link() declarations"
			)
			assert(
				item.kind == kind or item.kind == "raw",
				"cf.hl.setup: declaration kind does not match module kind"
			)
			declarations[#declarations + 1] = item
		end
	end
	return declarations
end

local function registry_has(kind, name)
	if compile_phase ~= "fallback" or not active_registry then
		return false
	end

	if kind == "ui" then
		return active_registry.ui == true
	elseif kind == "plugin" then
		return active_registry.plugins[name] == true
	elseif kind == "language" then
		if name == nil then
			return active_registry.global_language == true
		end
		return active_registry.languages[name] == true
	end

	return false
end

local function registry_add(kind, name)
	if compile_phase ~= "active" or not active_registry then
		return
	end

	if kind == "ui" then
		active_registry.ui = true
	elseif kind == "plugin" then
		active_registry.plugins[name] = true
	elseif kind == "language" then
		if name == nil then
			active_registry.global_language = true
		else
			active_registry.languages[name] = true
		end
	end
end

local function skipped_module(kind, name)
	return {
		_cf_module = true,
		_cf_skip = true,
		kind = kind,
		name = name,
		actions = {},
		apply = function() end,
	}
end

local function validate_group_common(spec, where, allow_targets, allow_raw_clear)
	assert(type(spec) == "table", where .. " definition must be a table")
	validate_priority(spec.priority, where .. ".priority", 0)

	if allow_targets then
		validate_targets(spec.style_targets, where .. ".style_targets")
		validate_targets(spec.style_targets_clear, where .. ".style_targets_clear")
		assert(spec.clear == nil, where .. ".clear is only valid for raw:group()")
	else
		assert(spec.style_targets == nil, where .. " does not support style_targets")
		assert(spec.style_targets_clear == nil, where .. " does not support style_targets_clear; use clear=true")
		if spec.clear ~= nil then
			assert(allow_raw_clear and type(spec.clear) == "boolean", where .. ".clear must be boolean")
		end
	end

	if spec.link ~= nil then
		validate_name(spec.link, where .. ".link")
	end
end

local function base_action(spec, where, source)
	local has_style = has_style_fields(spec)
	local has_pipeline = spec.pipeline ~= nil
	local link = spec.link

	if link ~= nil then
		assert(not has_style and not has_pipeline, where .. " cannot combine link with style fields or pipeline")
		return "link", nil
	end

	if has_style then
		return "style", build_style(spec, nil, nil, source)
	end

	if has_pipeline then
		-- A base group has no inherited fg/bg/sp for a pipeline-only definition.
		-- Let the pipeline raise its precise missing-channel error if somebody
		-- nevertheless supplied an operation.
		return "style", build_style(spec, nil, nil, source)
	end

	return nil, nil
end

local function typemod_entry(value, base_style, inherited_priority, where, source)
	if value == true then
		assert(base_style ~= nil, where .. "=true requires the group to have a style")
		return "style", base_style, inherited_priority, false
	end
	if value == false then
		return "clear", nil, inherited_priority
	end

	assert(type(value) == "table", where .. " must be true, false or a table")
	local priority = validate_priority(value.priority, where .. ".priority", inherited_priority)
	assert(value.types == nil, where .. " cannot contain types")
	assert(value.typemods == nil, where .. " cannot contain typemods")
	assert(value.style_targets == nil, where .. " cannot contain style_targets")
	assert(value.style_targets_clear == nil, where .. " cannot contain style_targets_clear")
	assert(value.clear == nil, where .. " cannot contain clear; use false to remove the typemod")

	local has_style = has_style_fields(value)
	local has_pipeline = value.pipeline ~= nil
	if value.link ~= nil then
		validate_name(value.link, where .. ".link")
		assert(not has_style and not has_pipeline, where .. " cannot combine link with style fields or pipeline")
		return "link", value.link, priority
	end

	if has_style or has_pipeline then
		return "style", build_style(value, base_style, nil, source), priority, true
	end

	if diagnostic._enabled("hint") then
		hint_unnecessary(where .. " is useless: it contains no style, pipeline, link or false clear", source)
	end
	return nil, nil, priority
end

local function has_typemod_actions(typemods)
	if typemods == nil then
		return false
	end
	assert(type(typemods) == "table", "cf.hl.setup: typemods must be a table")
	return next(typemods) ~= nil
end

local function compile_scope_safe(actions, declaration_, compiler, ...)
	-- Theme module setup() is already protected by cf.theme.execute(). Give each
	-- independently compiled scope the same failure boundary so one invalid part
	-- does not abort otherwise valid sibling work. Direct low-level use outside a
	-- loaded .cf file keeps the existing assert contract.
	if #source_stack == 0 then
		return compiler(actions, declaration_, ...)
	end

	local action_count = #actions
	local ok, err = pcall(compiler, actions, declaration_, ...)
	if ok then
		return true
	end

	-- Roll back only the scope owned by this call. Group callers therefore drop a
	-- broken group, while nested typemod callers can preserve the valid group base
	-- and sibling typemods around one broken entry.
	for i = #actions, action_count + 1, -1 do
		actions[i] = nil
	end

	if diagnostic._enabled("error") then
		local record, report_err = diagnostic.report("error", {
			message = tostring(err):match("([^\n]+)") or tostring(err),
			source = refine_source_col(declaration_.source),
		})
		if not record then
			vim.notify(tostring(report_err), vim.log.levels.ERROR)
		end
	end
	return false
end

local function compile_raw_typemod(actions, declaration_, name, value, style, priority, where, clear)
	validate_name(name, where .. ".typemods key")
	local qmode, payload, qpriority = typemod_entry(
		value,
		style,
		priority,
		where .. ".typemods[" .. name .. "]",
		declaration_.source
	)
	if qmode == "style" then
		add_action(actions, qpriority, "raw_style", {
			name = name,
			style = payload,
			clear = clear,
		})
	elseif qmode == "link" then
		assert(payload ~= name, where .. ".typemods cannot self-link " .. name)
		add_action(actions, qpriority, "raw_link", {
			name = name,
			target = payload,
			clear = clear,
		})
	elseif qmode == "clear" then
		add_action(actions, qpriority, "raw_clear", { name = name })
	end
end

local function compile_raw_group(actions, declaration_)
	local where = "cf.hl.setup: raw:group(" .. tostring(declaration_.name) .. ")"
	local spec = declaration_.spec
	validate_name(declaration_.name, where .. " name")
	validate_group_common(spec, where, false, true)

	local names = collect_types(declaration_.name, spec.types)
	local priority = validate_priority(spec.priority, where .. ".priority", 0)
	local mode, style = base_action(spec, where, declaration_.source)
	local typemods_present = has_typemod_actions(spec.typemods)

	if not mode and not typemods_present then
		if diagnostic._enabled("hint") then
			hint_unnecessary(where .. " is useless: group() has no style, link or typemod action", declaration_.source)
		end
		return
	end

	local clear = spec.clear == true
	if mode == "style" then
		add_action(actions, priority, "raw_style", {
			name = names[1],
			style = style,
			clear = clear,
		})
	elseif mode == "link" then
		assert(spec.link ~= names[1], where .. " cannot link a group to itself")
		add_action(actions, priority, "raw_link", {
			name = names[1],
			target = spec.link,
			clear = clear,
		})
	end

	-- `types` always hang off the primary group instead of duplicating the
	-- style or external link. This keeps one explicit anchor per group().
	if mode then
		for i = 2, #names do
			add_action(actions, priority, "raw_link", {
				name = names[i],
				target = names[1],
				clear = clear,
			})
		end
	end

	if spec.typemods then
		for name, value in pairs(spec.typemods) do
			compile_scope_safe(actions, declaration_, compile_raw_typemod, name, value, style, priority, where, clear)
		end
	end
end

local function compile_resolved_typemod(actions, declaration_, typemod, value, names, style, priority, where, filetype, targets, clear)
	validate_name(typemod, where .. ".typemods key")
	local qmode, payload, qpriority, typemod_style = typemod_entry(
		value,
		style,
		priority,
		where .. ".typemods[" .. typemod .. "]",
		declaration_.source
	)

	for i = 1, #names do
		local type_name = names[i]
		if qmode == "style" then
			add_action(actions, qpriority, "resolver_style", {
				type_name = type_name,
				typemod = typemod,
				typemod_style = typemod_style,
				style = payload,
				filetype = filetype,
				targets = targets,
				clear = clear,
			})
		elseif qmode == "link" then
			add_action(actions, qpriority, "resolver_link", {
				type_name = type_name,
				typemod = typemod,
				target_type = payload,
				filetype = filetype,
				targets = targets,
				clear = clear,
			})
		elseif qmode == "clear" then
			add_action(actions, qpriority, "resolver_clear", {
				type_name = type_name,
				typemod = typemod,
				filetype = filetype,
				clear = CLEAR_ALL,
			})
		end
	end
end

local function compile_resolved_group(actions, declaration_, filetype, module_targets, module_clear, prefix, plugin_needs_group_targets)
	local where = "cf.hl.setup: " .. prefix .. ":group(" .. tostring(declaration_.name) .. ")"
	local spec = declaration_.spec
	validate_name(declaration_.name, where .. " name")
	validate_group_common(spec, where, true, false)

	local names = collect_types(declaration_.name, spec.types)
	local priority = validate_priority(spec.priority, where .. ".priority", 0)
	local targets = effective_targets(module_targets, spec.style_targets)
	local clear = copy_clear(module_clear, spec.style_targets_clear)
	local mode, style = base_action(spec, where, declaration_.source)
	local typemods_present = has_typemod_actions(spec.typemods)

	if not mode and not typemods_present then
		if diagnostic._enabled("hint") then
			hint_unnecessary(where .. " is useless: group() has no style, link or typemod action", declaration_.source)
		end
		return
	end

	if plugin_needs_group_targets then
		assert(spec.style_targets ~= nil, where .. " requires style_targets when p.setup() has no module style_targets")
	end

	if mode == "style" then
		local action = add_action(actions, priority, "resolver_style", {
			type_name = names[1],
			style = style,
			filetype = filetype,
			targets = targets,
			clear = clear,
		})
		if diagnostic._enabled("hint") then
			action._cf_type_hint_source = declaration_.source
		end
	elseif mode == "link" then
		assert(spec.link ~= names[1], where .. " cannot link a group to itself")
		add_action(actions, priority, "resolver_link", {
			type_name = names[1],
			target_type = spec.link,
			filetype = filetype,
			targets = targets,
			clear = clear,
		})
	end

	-- Additional semantic types link to the primary semantic type. The
	-- primary alone owns the style/external link anchor.
	if mode then
		for i = 2, #names do
			add_action(actions, priority, "resolver_link", {
				type_name = names[i],
				target_type = names[1],
				filetype = filetype,
				targets = targets,
				clear = clear,
			})
		end
	end

	if spec.typemods then
		for typemod, value in pairs(spec.typemods) do
			compile_scope_safe(
				actions, declaration_, compile_resolved_typemod,
				typemod, value, names, style, priority, where, filetype, targets, clear
			)
		end
	end
end

local function compile_module_mods(actions, mods, filetype, module_targets, module_clear, where, source)
	if mods == nil then
		return
	end
	assert(type(mods) == "table", where .. " mods must be a table")
	local targets = effective_targets(module_targets, nil)
	local clear = copy_clear(module_clear, nil)

	for typemod, value in pairs(mods) do
		validate_name(typemod, where .. " mod name")
		if value == false then
			add_action(actions, 0, "resolver_clear", {
				typemod = typemod,
				filetype = filetype,
				clear = CLEAR_ALL,
			})
		else
			assert(type(value) == "table", where .. " mod '" .. typemod .. "' must be false or a style table")
			local priority = validate_priority(value.priority, where .. ".mods[" .. typemod .. "].priority", 0)
			assert(value.types == nil and value.typemods == nil, where .. " module mod cannot contain types/typemods")
			assert(value.style_targets == nil and value.style_targets_clear == nil, where .. " module mod cannot override targets")
			assert(value.clear == nil, where .. " module mod uses false for explicit removal")
			local has_style = has_style_fields(value)
			local has_pipeline = value.pipeline ~= nil
			if value.link ~= nil then
				validate_name(value.link, where .. ".mods[" .. typemod .. "].link")
				assert(not has_style and not has_pipeline, where .. " module mod cannot combine link with style/pipeline")
				add_action(actions, priority, "resolver_link", {
					typemod = typemod,
					target_type = value.link,
					filetype = filetype,
					targets = targets,
					clear = clear,
				})
			elseif has_style or has_pipeline then
				add_action(actions, priority, "resolver_style", {
					typemod = typemod,
					style = build_style(value, nil, nil, source),
					filetype = filetype,
					targets = targets,
					clear = clear,
				})
			else
				if diagnostic._enabled("hint") then
					hint_unnecessary(where .. ".mods[" .. typemod .. "] is useless", source)
				end
			end
		end
	end
end

local function bind_action_owner(actions, kind, name)
	for i = 1, #actions do
		actions[i]._cf_owner_kind = kind
		actions[i]._cf_owner_name = name
	end
end

local function compile_language_module(language, spec, source)
	assert(language == nil or (type(language) == "string" and language ~= ""), "cf.hl.setup: language must be a non-empty string or nil")
	assert(type(spec) == "table", "cf.hl.setup: language setup expects a table")
	validate_targets(spec.style_targets, "cf.hl.setup: module style_targets")
	validate_targets(spec.style_targets_clear, "cf.hl.setup: module style_targets_clear")

	local declarations = module_declarations(spec, "language")
	local actions = {}

	compile_module_mods(actions, spec.mods, language, spec.style_targets, spec.style_targets_clear, "cf.hl.setup: language module", source)

	for i = 1, #declarations do
		local declaration_ = declarations[i]
		error_source_hint = declaration_.source
		if declaration_.kind == "raw" then
			if declaration_.action == "group" then
				compile_scope_safe(actions, declaration_, compile_raw_group)
			else
				validate_name(declaration_.name, "cf.hl.setup: raw:link source")
				validate_name(declaration_.target, "cf.hl.setup: raw:link target")
				assert(declaration_.name ~= declaration_.target, "cf.hl.setup: raw:link cannot self-link")
				add_action(actions, 0, "raw_link", {
					name = declaration_.name,
					target = declaration_.target,
					clear = false,
				})
			end
		elseif declaration_.action == "group" then
			compile_scope_safe(
				actions, declaration_, compile_resolved_group,
				language, spec.style_targets, spec.style_targets_clear, "l", false
			)
		else
			validate_name(declaration_.name, "cf.hl.setup: l:link source")
			validate_name(declaration_.target, "cf.hl.setup: l:link target")
			assert(declaration_.name ~= declaration_.target, "cf.hl.setup: l:link cannot self-link")
			add_action(actions, 0, "resolver_link", {
				type_name = declaration_.name,
				target_type = declaration_.target,
				filetype = language,
				targets = effective_targets(spec.style_targets, nil),
				clear = copy_clear(spec.style_targets_clear, nil),
			})
		end
		error_source_hint = source
	end

	bind_action_owner(actions, "language", language)

	local module = {
		_cf_module = true,
		kind = "language",
		name = language,
		actions = actions,
		declarations = declarations,
		mods = colortrace_picker_enabled and spec.mods or nil,
		source = source,
	}

	function module:apply()
		apply_actions(self.actions)
	end

	return module
end

local function compile_resolved_module(kind, name, spec, source)
	assert(type(spec) == "table", "cf.hl.setup: " .. kind .. " setup expects a table")
	validate_targets(spec.style_targets, "cf.hl.setup: module style_targets")
	validate_targets(spec.style_targets_clear, "cf.hl.setup: module style_targets_clear")

	local explicit_module_targets = spec.style_targets ~= nil
	local module_targets
	if kind == "ui" then
		module_targets = targets_with_defaults(UI_TARGET_DEFAULTS, spec.style_targets)
	else
		module_targets = targets_with_defaults(PLUGIN_TARGET_DEFAULTS, spec.style_targets)
	end

	local declarations = module_declarations(spec, kind)
	local actions = {}

	-- Plugin/UI setup names are not filetypes. Their declarations still use the
	-- normal resolver; style_targets select which Vim/TS/LSP forms are writable.
	if kind == "plugin" and spec.mods and next(spec.mods) ~= nil then
		assert(explicit_module_targets, "cf.hl.setup: plugin module mods require module style_targets")
	end
	compile_module_mods(actions, spec.mods, nil, module_targets, spec.style_targets_clear, "cf.hl.setup: " .. kind .. " module", source)

	local prefix = kind == "plugin" and "p" or "u"
	for i = 1, #declarations do
		local declaration_ = declarations[i]
		error_source_hint = declaration_.source
		if declaration_.kind == "raw" then
			if declaration_.action == "group" then
				compile_scope_safe(actions, declaration_, compile_raw_group)
			else
				validate_name(declaration_.name, "cf.hl.setup: raw:link source")
				validate_name(declaration_.target, "cf.hl.setup: raw:link target")
				assert(declaration_.name ~= declaration_.target, "cf.hl.setup: raw:link cannot self-link")
				add_action(actions, 0, "raw_link", {
					name = declaration_.name,
					target = declaration_.target,
					clear = false,
				})
			end
		elseif declaration_.action == "group" then
			compile_scope_safe(
				actions, declaration_, compile_resolved_group,
				nil, module_targets, spec.style_targets_clear, prefix, kind == "plugin" and not explicit_module_targets
			)
		else
			if kind == "plugin" then
				assert(explicit_module_targets, "cf.hl.setup: p:link() requires module style_targets")
			end
			validate_name(declaration_.name, "cf.hl.setup: " .. prefix .. ":link source")
			validate_name(declaration_.target, "cf.hl.setup: " .. prefix .. ":link target")
			assert(declaration_.name ~= declaration_.target, "cf.hl.setup: " .. prefix .. ":link cannot self-link")
			add_action(actions, 0, "resolver_link", {
				type_name = declaration_.name,
				target_type = declaration_.target,
				targets = effective_targets(module_targets, nil),
				clear = copy_clear(spec.style_targets_clear, nil),
			})
		end
		error_source_hint = source
	end

	bind_action_owner(actions, kind, name)

	local module = {
		_cf_module = true,
		kind = kind,
		name = name,
		actions = actions,
		declarations = declarations,
		mods = colortrace_picker_enabled and spec.mods or nil,
		source = source,
	}

	function module:apply()
		apply_actions(self.actions)
	end

	return module
end

function language_api.setup(language, spec)
	if registry_has("language", language) then
		return skipped_module("language", language)
	end

	local source = capture_source(3, "setup")
	error_source_hint = source
	local module = compile_language_module(language, spec, source)
	error_source_hint = nil
	registry_add("language", language)
	return module
end

function plugin_api.setup(name, spec)
	if registry_has("plugin", name) then
		return skipped_module("plugin", name)
	end

	local source = capture_source(3, "setup")
	error_source_hint = source
	assert(type(name) == "string" and name ~= "", "cf.hl.setup: plugin name must be a non-empty string")
	local module = compile_resolved_module("plugin", name, spec, source)
	error_source_hint = nil
	registry_add("plugin", name)
	return module
end

function ui_api.setup(spec)
	if registry_has("ui") then
		return skipped_module("ui", nil)
	end

	local source = capture_source(3, "setup")
	error_source_hint = source
	local module = compile_resolved_module("ui", nil, spec, source)
	error_source_hint = nil
	registry_add("ui", nil)
	return module
end

setmetatable(language_api, {
	__index = function(_, language)
		if type(language) ~= "string" or language == "" then return nil end
		return require("cf.fn.runtime").scope("language", language)
	end,
})

setmetatable(plugin_api, {
	__index = function(_, plugin)
		if type(plugin) ~= "string" or plugin == "" then return nil end
		return require("cf.fn.runtime").scope("plugin", plugin)
	end,
})

setmetatable(ui_api, {
	__index = function(_, name)
		if type(name) ~= "string" or name == "" then return nil end
		return require("cf.fn.runtime").target("ui", nil, name, nil)
	end,
})

setmetatable(raw_api, {
	__index = function(_, name)
		if type(name) ~= "string" or name == "" then return nil end
		return require("cf.fn.runtime").target("raw", nil, name, nil)
	end,
})

M.language = language_api
M.plugin = plugin_api
M.ui = ui_api
M.raw = raw_api
M.runtime = runtime_api

function M._source_begin(path)
	assert(type(path) == "string" and path ~= "", "cf.hl.setup: source path must be a non-empty string")
	local normalized = vim.fs.normalize(path)
	local picker = picker_enabled()
	local trace_enabled = false
	local color_trace_visible = false
	local colortrace = colortrace_active and package.loaded["cf.colortrace"] or nil
	if colortrace then
		trace_enabled, color_trace_visible = colortrace._source_mode(normalized)
		colortrace._source_begin(normalized)
	end
	local ranges_enabled = picker or trace_enabled
	source_stack[#source_stack + 1] = {
		file = normalized,
		ranges_enabled = ranges_enabled,
		range_used = picker and {} or nil,
		pipeline_range_used = trace_enabled and {} or nil,
		trace_enabled = trace_enabled,
		color_trace_visible = color_trace_visible,
		ranges_loaded = false,
	}
	return #source_stack
end

function M._source_end(token)
	assert(token == #source_stack, "cf.hl.setup: unbalanced source context")
	source_stack[#source_stack] = nil
end

function M._error_source_clear()
	error_source_hint = nil
end

function M._error_source_take()
	local source = error_source_hint
	error_source_hint = nil
	return source
end

-- Internal compile boundary used by the theme loader. It mutates the palette
-- in place so every module sees one shared table reference with packed integer
-- colours, then installs the hard config-level target boundary.
function M._begin(colors, theme_config)
	assert(type(colors) == "table", "cf.hl.setup: colors must be a table")
	theme_config = theme_config or {}
	assert(type(theme_config) == "table", "cf.hl.setup: config.cf must return a table")

	normalize_palette_table(colors)
	M.colors = colors
	pipeline.set_background(colors.bg)

	validate_targets(theme_config.style_targets, "cf.hl.setup: config style_targets")
	validate_targets(theme_config.style_targets_clear, "cf.hl.setup: config style_targets_clear")

	local configured = theme_config.style_targets
	current_targets = {
		vim = configured == nil or configured.vim ~= false,
		ts = configured == nil or configured.ts ~= false,
		lsp = configured == nil or configured.lsp ~= false,
	}

	current_global_clear = copy_clear(theme_config.style_targets_clear, nil) or {}

	local only = theme_config.only_style_target
	if only ~= nil then
		assert(only == "vim" or only == "ts" or only == "lsp", "cf.hl.setup: only_style_target must be 'vim', 'ts', 'lsp' or nil")
		for i = 1, 3 do
			local key = TARGET_KEYS[i]
			if key ~= only then
				current_targets[key] = false
				current_global_clear[key] = true
			end
		end
	end

	return M
end

function M._runtime_begin(name)
	validate_name(name, "cf.hl.setup: runtime module name")
	local proxy = new_runtime_definition(name)
	local token = { previous = M.runtime, proxy = proxy }
	runtime_definition_stack[#runtime_definition_stack + 1] = token
	M.runtime = proxy
	return token
end

function M._runtime_end(token)
	local current = runtime_definition_stack[#runtime_definition_stack]
	assert(current == token and M.runtime == token.proxy, "cf.hl.setup: unbalanced runtime module load")
	runtime_definition_stack[#runtime_definition_stack] = nil
	M.runtime = token.previous
	return true
end

function M._global_clear()
	return current_global_clear
end

-- Theme.apply uses one global stable priority pass. module:apply() remains
-- useful for standalone tests and direct low-level use.
function M._apply_modules(modules)
	local actions = {}
	for i = 1, #modules do
		local module = modules[i]
		for n = 1, #module.actions do
			actions[#actions + 1] = module.actions[n]
		end
	end
	apply_actions(actions)
end

-- Internal theme-loader pass control. Active modules are always compiled and
-- only collected here. The registry becomes a fallback filter after the full
-- active pass succeeds.
function M._active_begin()
	compile_phase = "active"
	active_registry = {
		languages = {},
		plugins = {},
		global_language = false,
		ui = false,
	}
end

function M._fallback_begin()
	assert(compile_phase == "active" and active_registry, "cf.hl.setup: fallback pass started without active pass")
	compile_phase = "fallback"
end

function M._compile_end()
	compile_phase = nil
	active_registry = nil
end

function M._build_style(spec, base, runtime_context)
	return build_style(spec, base, runtime_context, nil)
end

function M._style_cache_size()
	return style_cache_count
end

return M
