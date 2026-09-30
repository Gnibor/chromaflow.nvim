local M = {}

local api = vim.api
local diag_ns = api.nvim_create_namespace("cf.nvim.diagnostic")
local float_ns = api.nvim_create_namespace("cf.nvim.diagnostic.float")
local span_groups = {}

-- Diagnostics deliberately use a sparse internal scale. The public severities
-- are HINT/WARN/ERROR; the gaps give severity_bias room to move an effective
-- severity without changing the producer's base severity.
M.severity = {
	HINT = 64,
	WARN = 128,
	ERROR = 192,
	MIN = 0,
	MAX = 255,
}

M.tag = {
	DEPRECATED = "deprecated",
	UNNECESSARY = "unnecessary",
}

-- INFO/OK are user-message kinds, not diagnostic severities.
M.message = {
	INFO = "info",
	OK = "ok",
}

M.form = {
	DIAGNOSTIC = "diagnostic",
	MESSAGE = "message",
	ASSERT = "assert",
}

local severity_by_name = {
	hint = M.severity.HINT,
	warn = M.severity.WARN,
	warning = M.severity.WARN,
	error = M.severity.ERROR,
}

local policy = {
	severity_bias = 0,
	severity = {
		hint = true,
		warn = true,
		error = true,
	},
	messages = {
		info = true,
		ok = true,
	},
}

local pending = {}
local history = {}
local next_id = 0
local rendered_buffers = {}

local function fail(message)
	return nil, "cf.diagnostic: " .. message
end

local function is_integer(value)
	return type(value) == "number" and value == math.floor(value)
end

local function copy_table(value)
	local out = {}
	for key, item in pairs(value) do
		out[key] = item
	end
	return out
end

local function copy_list(value)
	local out = {}
	for i = 1, #value do
		out[i] = value[i]
	end
	return out
end

local function normalize_source(source)
	if type(source) ~= "table" then
		return fail("source must be a table")
	end
	if type(source.file) ~= "string" or source.file == "" then
		return fail("source.file must be a non-empty string")
	end
	if not is_integer(source.line) or source.line < 1 then
		return fail("source.line must be a 1-based integer")
	end
	if not is_integer(source.col) or source.col < 1 then
		return fail("source.col must be a 1-based integer")
	end

	local end_line = source.end_line
	local end_col = source.end_col
	if (end_line == nil) ~= (end_col == nil) then
		return fail("source.end_line and source.end_col must be provided together")
	end
	if end_line ~= nil then
		if not is_integer(end_line) or end_line < 1 then
			return fail("source.end_line must be a 1-based integer or nil")
		end
		if not is_integer(end_col) or end_col < 1 then
			return fail("source.end_col must be a 1-based integer or nil")
		end
		if end_line < source.line or (end_line == source.line and end_col < source.col) then
			return fail("source end position must not precede the start position")
		end
	end

	return {
		file = vim.fs.normalize(source.file),
		line = source.line,
		col = source.col,
		end_line = end_line,
		end_col = end_col,
	}
end

local function normalize_context(context)
	if context == nil then
		return nil
	end
	if type(context) ~= "table" then
		return fail("context must be a table or nil")
	end
	if context.kind ~= nil and (type(context.kind) ~= "string" or context.kind == "") then
		return fail("context.kind must be a non-empty string or nil")
	end
	if context.name ~= nil and (type(context.name) ~= "string" or context.name == "") then
		return fail("context.name must be a non-empty string or nil")
	end

	return {
		kind = context.kind,
		name = context.name,
	}
end

local function normalize_tags(tags)
	if tags == nil then
		return {}
	end
	if type(tags) ~= "table" then
		return fail("tags must be a list or nil")
	end

	local out = {}
	local seen = {}
	for i = 1, #tags do
		local tag = tags[i]
		if type(tag) ~= "string" or tag == "" then
			return fail("tags must contain non-empty strings")
		end
		if not seen[tag] then
			seen[tag] = true
			out[#out + 1] = tag
		end
	end
	return out
end

local function normalize_severity(value)
	if type(value) == "string" then
		local result = severity_by_name[value:lower()]
		if not result then
			return fail("unknown diagnostic severity '" .. value .. "'")
		end
		return result
	end

	if not is_integer(value) then
		return fail("diagnostic severity must be HINT/WARN/ERROR or an integer")
	end
	if value < M.severity.MIN or value > M.severity.MAX then
		return fail("diagnostic severity must be between 0 and 255")
	end
	return value
end

local function normalize_message_kind(value)
	if type(value) ~= "string" then
		return fail("message kind must be 'info' or 'ok'")
	end
	value = value:lower()
	if value ~= M.message.INFO and value ~= M.message.OK then
		return fail("message kind must be 'info' or 'ok'")
	end
	return value
end

local function normalize_common(data)
	if type(data) ~= "table" then
		return fail("record data must be a table")
	end
	if type(data.message) ~= "string" or data.message == "" then
		return fail("message must be a non-empty string")
	end

	local source, source_err = normalize_source(data.source)
	if not source then
		return nil, source_err
	end

	local context, context_err = normalize_context(data.context)
	if context_err then
		return nil, context_err
	end

	local tags, tags_err = normalize_tags(data.tags)
	if not tags then
		return nil, tags_err
	end

	local code = data.code
	if code ~= nil and type(code) ~= "string" and not is_integer(code) then
		return fail("code must be a string, integer or nil")
	end

	return {
		message = data.message,
		source = source,
		context = context,
		tags = tags,
		code = code,
		data = data.data,
	}
end

local function push(record)
	next_id = next_id + 1
	record.id = next_id
	record.time_ns = vim.uv.hrtime()

	pending[#pending + 1] = record
	history[#history + 1] = record
	return record
end

-- Configure the central diagnostic manager. cf.setup forwards its
-- `diagnostic = {}` block here; producers still only enqueue records.
function M.configure(opts)
	if opts == nil then
		return true
	end
	if type(opts) ~= "table" then
		return false, "cf.diagnostic: configure expects a table"
	end

	local next_policy = {
		severity_bias = policy.severity_bias,
		severity = copy_table(policy.severity),
		messages = copy_table(policy.messages),
	}

	if opts.severity_bias ~= nil then
		if not is_integer(opts.severity_bias) then
			return false, "cf.diagnostic: severity_bias must be an integer"
		end
		next_policy.severity_bias = opts.severity_bias
	end

	if opts.severity ~= nil then
		if type(opts.severity) ~= "table" then
			return false, "cf.diagnostic: severity must be a table"
		end
		for _, name in ipairs({ "hint", "warn", "error" }) do
			local value = opts.severity[name]
			if value ~= nil then
				if type(value) ~= "boolean" then
					return false, "cf.diagnostic: severity." .. name .. " must be boolean"
				end
				next_policy.severity[name] = value
			end
		end
	end

	if opts.messages ~= nil then
		if type(opts.messages) ~= "table" then
			return false, "cf.diagnostic: messages must be a table"
		end
		for _, name in ipairs({ "info", "ok" }) do
			local value = opts.messages[name]
			if value ~= nil then
				if type(value) ~= "boolean" then
					return false, "cf.diagnostic: messages." .. name .. " must be boolean"
				end
				next_policy.messages[name] = value
			end
		end
	end

	policy = next_policy
	return true
end

local function contrast_foreground(hex)
	local packed = tonumber(hex:sub(2, 7), 16)
	if not packed then
		return "#ffffff"
	end
	local red = math.floor(packed / 0x10000) % 0x100
	local green = math.floor(packed / 0x100) % 0x100
	local blue = packed % 0x100
	local luminance = (red * 299 + green * 587 + blue * 114) / 1000
	return luminance > 140 and "#000000" or "#ffffff"
end

local function span_group(hex)
	local key = hex:upper()
	local group = span_groups[key]
	if not group then
		group = "CFDiagnosticSpan_" .. hex:sub(2):upper()
		span_groups[key] = group
	end
	-- :hi clear during a theme reload removes custom definitions. Reapply the
	-- tiny swatch definition only when a diagnostic float actually needs it.
	api.nvim_set_hl(0, group, {
		fg = contrast_foreground(hex),
		bg = hex,
	})
	return group
end

local function decorate_float(float_buf, records)
	if not float_buf or not api.nvim_buf_is_valid(float_buf) then
		return
	end
	api.nvim_buf_clear_namespace(float_buf, float_ns, 0, -1)
	local lines = api.nvim_buf_get_lines(float_buf, 0, -1, false)
	local used = {}
	for i = 1, #records do
		local record = records[i]
		local spans = record.data and record.data.spans
		if spans and spans[1] then
			for row = 1, #lines do
				local from = used[row] or 1
				local first = lines[row]:find(record.message, from, true)
				if first then
					used[row] = first + #record.message
					local message_col = first - 1
					for n = 1, #spans do
						local span = spans[n]
						if type(span.color) == "string" then
							api.nvim_buf_set_extmark(float_buf, float_ns, row - 1, message_col + span.start_col, {
								end_col = message_col + span.end_col,
								hl_group = span_group(span.color),
								priority = 10000,
							})
						end
					end
					break
				end
			end
		end
	end
end

function M.open_float()
	local bufnr = api.nvim_get_current_buf()
	local row = api.nvim_win_get_cursor(0)[1] - 1
	local diagnostics = vim.diagnostic.get(bufnr, { namespace = diag_ns, lnum = row })
	if diagnostics[1] == nil then
		return
	end

	local records = {}
	for i = 1, #diagnostics do
		local record = diagnostics[i].user_data and diagnostics[i].user_data.cf
		if record then
			records[#records + 1] = record
		end
	end

	local float_buf = vim.diagnostic.open_float({
		bufnr = bufnr,
		namespace = diag_ns,
		scope = "line",
		source = "if_many",
		focusable = true,
	})
	if not float_buf then
		return
	end

	-- diagnostic.open_float() may refresh a reused float buffer after returning.
	-- Decorate only after Neovim has finished writing the diagnostic lines.
	vim.schedule(function()
		decorate_float(float_buf, records)
	end)
end

function M.policy()
	return {
		severity_bias = policy.severity_bias,
		severity = copy_table(policy.severity),
		messages = copy_table(policy.messages),
	}
end

function M.classify(value)
	local severity, err = normalize_severity(value)
	if not severity then
		return nil, err
	end

	if severity < 96 then
		return "hint"
	end
	if severity < 160 then
		return "warn"
	end
	return "error"
end


function M._enabled(severity)
	local normalized = severity
	if type(normalized) == "string" then
		normalized = severity_by_name[normalized:lower()]
	end
	if not is_integer(normalized) or normalized < M.severity.MIN or normalized > M.severity.MAX then
		return false
	end

	local effective = normalized + policy.severity_bias
	if effective < M.severity.MIN then
		effective = M.severity.MIN
	elseif effective > M.severity.MAX then
		effective = M.severity.MAX
	end

	local class
	if effective < 96 then
		class = "hint"
	elseif effective < 160 then
		class = "warn"
	else
		class = "error"
	end
	return policy.severity[class] == true
end

function M.effective_severity(value)
	local severity, err = normalize_severity(value)
	if not severity then
		return nil, err
	end
	local effective = severity + policy.severity_bias
	if effective < M.severity.MIN then
		effective = M.severity.MIN
	elseif effective > M.severity.MAX then
		effective = M.severity.MAX
	end
	return effective
end

-- Report a Theme/DSL diagnostic. This only records data; it never throws,
-- aborts the caller, opens UI or changes control flow.
function M.report(severity, data)
	local normalized_severity, severity_err = normalize_severity(severity)
	if not normalized_severity then
		return nil, severity_err
	end
	local common, common_err = normalize_common(data)
	if not common then
		return nil, common_err
	end

	common.form = M.form.DIAGNOSTIC
	common.severity = normalized_severity
	return push(common)
end

-- INFO/OK are explicit user messages and intentionally do not participate in
-- diagnostic severity or severity_bias.
local function push_message(kind, data, policy_controlled)
	local normalized_kind, kind_err = normalize_message_kind(kind)
	if not normalized_kind then
		return nil, kind_err
	end
	local common, common_err = normalize_common(data)
	if not common then
		return nil, common_err
	end

	common.form = M.form.MESSAGE
	common.kind = normalized_kind
	common.message_policy = policy_controlled ~= false
	return push(common)
end

function M.user_message(kind, data)
	return push_message(kind, data, true)
end

function M.info(data)
	return M.user_message(M.message.INFO, data)
end

-- ColorTrace owns its visibility through diagnostic.color_trace. Keep its INFO
-- records independent from the normal diagnostic.messages.info user-message gate.
function M._trace_info(data)
	return push_message(M.message.INFO, data, false)
end

function M.ok(data)
	return M.user_message(M.message.OK, data)
end

-- ASSERT is a rendering fallback, not a fourth severity and not a producer
-- category. Keep assertion() as a compatibility helper: callers may enqueue an
-- ERROR diagnostic, but flush() still decides whether it is shown in-buffer or
-- through the ASSERT fallback according to the active tabpage.
function M.assertion(data)
	if type(data) ~= "table" then
		return fail("assertion data must be a table")
	end
	return M.report(data.severity or M.severity.ERROR, data)
end

local function is_visible(record)
	if record.form == M.form.DIAGNOSTIC then
		local effective = M.effective_severity(record.severity)
		local class = M.classify(effective)
		return policy.severity[class] == true
	end

	if record.form == M.form.MESSAGE then
		return record.message_policy == false or policy.messages[record.kind] == true
	end

	return false
end

function M.visible(record)
	if type(record) ~= "table" or record.form == nil then
		return false
	end
	return is_visible(record)
end

local function context_prefix(context)
	if not context then
		return nil
	end
	if context.kind and context.name then
		return context.kind .. " " .. context.name
	end
	return context.kind or context.name
end

function M.format(record)
	if type(record) ~= "table" or type(record.message) ~= "string" or type(record.source) ~= "table" then
		return nil, "cf.diagnostic: invalid record"
	end

	local prefix = context_prefix(record.context)
	local message = record.message
	if prefix then
		message = prefix .. ": " .. message
	end

	return message
		.. "\n"
		.. record.source.file
		.. ":"
		.. record.source.line
		.. ":"
		.. record.source.col
end

local function current_tab_buffer(file)
	local normalized = vim.fs.normalize(file)
	local tabpage = api.nvim_get_current_tabpage()
	for _, winid in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
		if api.nvim_win_is_valid(winid) then
			local bufnr = api.nvim_win_get_buf(winid)
			if api.nvim_buf_is_valid(bufnr) then
				local name = api.nvim_buf_get_name(bufnr)
				if name ~= "" and vim.fs.normalize(name) == normalized then
					return bufnr
				end
			end
		end
	end
	return nil
end

-- ASSERT is chosen only at render time. A file visible in another tabpage does
-- not count: diagnostics must stay visible in the user's current work context.
function M.output_form(record)
	if type(record) ~= "table" or record.form == nil then
		return nil
	end
	if record.form == M.form.MESSAGE then
		return M.form.MESSAGE
	end
	if record.form ~= M.form.DIAGNOSTIC then
		return nil
	end
	if current_tab_buffer(record.source.file) then
		return M.form.DIAGNOSTIC
	end
	return M.form.ASSERT
end

local function vim_severity(record)
	local effective = M.effective_severity(record.severity)
	local class = M.classify(effective)
	if class == "error" then
		return vim.diagnostic.severity.ERROR
	end
	if class == "warn" then
		return vim.diagnostic.severity.WARN
	end
	return vim.diagnostic.severity.HINT
end


local function buffer_item(record)
	local severity = vim.diagnostic.severity.INFO
	if record.form == M.form.DIAGNOSTIC then
		severity = vim_severity(record)
	end
	return {
		lnum = record.source.line - 1,
		col = record.source.col - 1,
		end_lnum = record.source.end_line and (record.source.end_line - 1) or nil,
		end_col = record.source.end_col and (record.source.end_col - 1) or nil,
		message = record.message,
		severity = severity,
		source = context_prefix(record.context) or "cf.nvim",
		code = record.code or record.id,
		user_data = { cf = record },
	}
end
local function notify_level(record)
	if record.form == M.form.DIAGNOSTIC then
		local class = M.classify(M.effective_severity(record.severity))
		if class == "error" then
			return vim.log.levels.ERROR
		end
		if class == "warn" then
			return vim.log.levels.WARN
		end
		return vim.log.levels.INFO
	end
	return vim.log.levels.INFO
end

local function clear_table(value)
	for key in pairs(value) do
		value[key] = nil
	end
end

-- Rendering is explicit. Producers only enqueue records; flush() chooses
-- in-buffer diagnostics or the ASSERT fallback from the active tabpage.
function M.flush()
	-- Clear only buffers where this manager actually rendered diagnostics before.
	-- The overwhelmingly common clean reload therefore avoids touching Neovim's
	-- diagnostic subsystem at all.
	if next(rendered_buffers) ~= nil then
		for bufnr in pairs(rendered_buffers) do
			if api.nvim_buf_is_valid(bufnr) then
				vim.diagnostic.reset(diag_ns, bufnr)
			end
		end
		clear_table(rendered_buffers)
	end

	if pending[1] == nil then
		return 0
	end

	local by_buf = {}
	local assert_messages = {}
	local assert_level = vim.log.levels.INFO
	local rendered = 0

	for i = 1, #pending do
		local record = pending[i]
		if is_visible(record) then
			local bufnr = current_tab_buffer(record.source.file)
			if bufnr then
				local list = by_buf[bufnr]
				if not list then
					list = {}
					by_buf[bufnr] = list
				end
				list[#list + 1] = buffer_item(record)
				rendered = rendered + 1
			elseif record.form == M.form.DIAGNOSTIC then
				assert_messages[#assert_messages + 1] = M.format(record)
				local level = notify_level(record)
				if level > assert_level then
					assert_level = level
				end
				rendered = rendered + 1
			else
				local text = M.format(record)
				vim.notify(text, notify_level(record), { title = "ChromaFlow" })
				rendered = rendered + 1
			end
		end
	end

	for bufnr, list in pairs(by_buf) do
		vim.diagnostic.set(diag_ns, bufnr, list)
		rendered_buffers[bufnr] = true
	end

	if assert_messages[1] ~= nil then
		vim.notify(table.concat(assert_messages, "\n\n"), assert_level, { title = "ChromaFlow" })
	end

	clear_table(pending)
	return rendered
end

-- Flush only records belonging to one visible source buffer. The ColorTrace
-- on-view seed path uses this so opening one .cf file does not reset diagnostics
-- already rendered for other visible theme files.
function M.flush_buffer(bufnr)
	assert(type(bufnr) == "number" and api.nvim_buf_is_valid(bufnr), "cf.diagnostic.flush_buffer: invalid buffer")
	local name = vim.fs.normalize(api.nvim_buf_get_name(bufnr))
	if name == "" then return 0 end

	if rendered_buffers[bufnr] then
		vim.diagnostic.reset(diag_ns, bufnr)
		rendered_buffers[bufnr] = nil
	end

	local list = {}
	local keep = {}
	local rendered = 0
	for i = 1, #pending do
		local record = pending[i]
		if vim.fs.normalize(record.source.file) == name then
			if is_visible(record) then
				list[#list + 1] = buffer_item(record)
				rendered = rendered + 1
			end
		else
			keep[#keep + 1] = record
		end
	end
	pending = keep

	if list[1] ~= nil then
		vim.diagnostic.set(diag_ns, bufnr, list)
		rendered_buffers[bufnr] = true
	end
	return rendered
end

function M.pending()
	return copy_list(pending)
end

function M.history()
	return copy_list(history)
end

function M.clear_pending()
	if pending[1] ~= nil then
		clear_table(pending)
	end
end

function M.clear_history()
	if history[1] ~= nil then
		clear_table(history)
	end
end

function M.clear_rendered(bufnr)
	if bufnr ~= nil then
		if type(bufnr) ~= "number" then
			return false, "cf.diagnostic: bufnr must be a number or nil"
		end
		vim.diagnostic.reset(diag_ns, bufnr)
		rendered_buffers[bufnr] = nil
		return true
	end
	for rendered_buf in pairs(rendered_buffers) do
		if api.nvim_buf_is_valid(rendered_buf) then
			vim.diagnostic.reset(diag_ns, rendered_buf)
		end
	end
	clear_table(rendered_buffers)
	return true
end

function M.clear()
	clear_table(pending)
	clear_table(history)
	M.clear_rendered()
end

return M
