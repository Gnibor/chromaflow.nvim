local M = {}

local api = vim.api
local color = require("cf.color")
local diagnostic = require("cf.diagnostic")

local color_trace_enabled = false
local picker_enabled = false

-- Picker traces are transactional: compilation builds a staging cache and only
-- the compiled theme that becomes current is allowed to replace the active one.
local cache = {}
local cache_theme
local staging
local pending_cache
local pending_theme
local reuse_stack = {}

local function normalize(path)
	return vim.fs.normalize(path)
end

local function current_tab_buffer(path)
	local normalized = normalize(path)
	local tabpage = api.nvim_get_current_tabpage()
	for _, winid in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
		if api.nvim_win_is_valid(winid) then
			local bufnr = api.nvim_win_get_buf(winid)
			local name = api.nvim_buf_get_name(bufnr)
			if name ~= "" and normalize(name) == normalized then
				return bufnr
			end
		end
	end
	return nil
end

local function sync_setup()
	local hl = package.loaded["cf.hl.setup"]
	if not hl and (color_trace_enabled or picker_enabled) then
		hl = require("cf.hl.setup")
	end
	if hl and type(hl._colortrace_mode) == "function" then
		hl._colortrace_mode(color_trace_enabled, picker_enabled)
	end
end

local function source_key(source)
	return table.concat({
		tostring(source.line or 0),
		tostring(source.col or 0),
		tostring(source.end_line or 0),
		tostring(source.end_col or 0),
	}, ":")
end

local function ensure_file(target, path)
	path = normalize(path)
	local entry = target[path]
	if entry then
		return entry
	end
	entry = {
		file = path,
		records = {},
		by_source = {},
	}
	target[path] = entry
	return entry
end

local function report(source, trace, code)
	if not source then
		return
	end

	local parts = {}
	local spans = {}
	local length = 0

	local function append(text)
		text = tostring(text)
		parts[#parts + 1] = text
		length = length + #text
	end

	local function append_color(value)
		local packed = type(value) == "string" and color.from_hex(value) or value
		local hex = color.to_hex(packed)
		local start_col = length
		append(hex)
		spans[#spans + 1] = {
			start_col = start_col,
			end_col = length,
			color = color.to_rgb_hex(packed),
		}
	end

	append(trace.name)
	append(".")
	append(trace.channel)
	append(": input ")
	append_color(trace.before)

	if trace.name == "mix" then
		append(" + ")
		append(trace.a)
		append("% mix ")
		append_color(trace.b)
	elseif trace.name == "opacity" then
		append(" over ")
		append_color(trace.backdrop)
		append(" at ")
		append(trace.a)
		append("%")
	elseif trace.name == "shiftHue" then
		append(" by ")
		append(trace.a)
		append("°")
	elseif trace.name == "gamma" then
		append(" gamma ")
		append(trace.a)
	else
		append(" by ")
		append(trace.a)
		append("%")
	end

	append(" -> result ")
	append_color(trace.after)

	diagnostic._trace_info({
		message = table.concat(parts),
		source = source,
		code = code,
		data = { spans = spans },
	})
end

function M.set_enabled(enabled)
	enabled = enabled == true
	if color_trace_enabled == enabled then
		return
	end
	color_trace_enabled = enabled
	sync_setup()
end

function M.set_picker(enabled)
	enabled = enabled == true
	if picker_enabled == enabled then
		return
	end
	picker_enabled = enabled
	if enabled then
		cache = {}
		cache_theme = nil
	else
		cache = {}
		cache_theme = nil
		staging = nil
		pending_cache = nil
		pending_theme = nil
	end
	sync_setup()
end

function M.color_trace_enabled()
	return color_trace_enabled
end

function M.picker_enabled()
	return picker_enabled
end

-- Called once per source execution by cf.hl.setup. Picker mode traces every
-- source; live ColorTrace traces only sources visible in the active tabpage.
-- During an on-view replay of a picker-cached file, colour tracing is suppressed
-- and the cached source trace is emitted after the module has been re-executed.
function M._source_mode(path)
	local normalized = normalize(path)
	local reuse = reuse_stack[#reuse_stack]
	if reuse and reuse == normalized then
		return false, false
	end

	local color_trace_visible = color_trace_enabled and current_tab_buffer(normalized) ~= nil
	return picker_enabled or color_trace_visible, color_trace_visible
end

function M._source_begin(path)
	if not picker_enabled then
		return
	end
	local target = staging or cache
	ensure_file(target, path)
end

function M._record(owner_source, source, trace, pipeline_index, emit_color_trace)
	if picker_enabled then
		local target = staging or cache
		local entry = ensure_file(target, source.file)
		local key = source_key(source)
		local record = entry.by_source[key]
		if record then
			record.owner = owner_source
			record.source = source
			record.trace = trace
			record.pipeline_index = pipeline_index
		else
			record = {
				index = #entry.records + 1,
				owner = owner_source,
				source = source,
				trace = trace,
				pipeline_index = pipeline_index,
			}
			entry.records[#entry.records + 1] = record
			entry.by_source[key] = record
		end
	end

	if emit_color_trace == true and color_trace_enabled then
		report(source, trace, pipeline_index)
	end
end

function M._compile_begin()
	if picker_enabled then
		staging = {}
	else
		staging = nil
	end
	pending_cache = nil
	pending_theme = nil
end

function M._compile_finish(compiled)
	if picker_enabled and staging then
		pending_cache = staging
		pending_theme = compiled
	end
	staging = nil
end

function M._compile_abort()
	staging = nil
	pending_cache = nil
	pending_theme = nil
end

function M._activate(compiled)
	if not picker_enabled then
		return
	end
	if pending_theme == compiled and pending_cache then
		cache = pending_cache
		cache_theme = compiled
		pending_cache = nil
		pending_theme = nil
	elseif cache_theme ~= compiled then
		cache = {}
		cache_theme = compiled
	end
end

function M._reuse_begin(path, compiled)
	if not picker_enabled or cache_theme ~= compiled then
		return nil
	end
	local normalized = normalize(path)
	if cache[normalized] == nil then
		return nil
	end
	reuse_stack[#reuse_stack + 1] = normalized
	return #reuse_stack
end

function M._reuse_end(token)
	assert(token == #reuse_stack, "cf.colortrace: unbalanced cached-trace reuse")
	reuse_stack[#reuse_stack] = nil
end

-- Return nil when there is no valid picker cache for this file/theme. Zero is a
-- valid result: the source was cached but contains no colour operations.
function M.emit_file(path, compiled)
	if not color_trace_enabled or cache_theme ~= compiled then
		return nil
	end
	local entry = cache[normalize(path)]
	if not entry then
		return nil
	end
	for i = 1, #entry.records do
		local record = entry.records[i]
		report(record.source, record.trace, record.pipeline_index)
	end
	return #entry.records
end

-- Internal picker/ColorTrace read API. The returned object is the active
-- immutable source snapshot for the current compiled theme; consumers must not
-- mutate it.
function M._cached(path, compiled)
	if cache_theme ~= compiled then
		return nil
	end
	return cache[normalize(path)]
end

return M
