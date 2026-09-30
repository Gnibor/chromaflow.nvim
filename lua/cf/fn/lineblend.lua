local M = {}

local ns = vim.api.nvim_create_namespace("LineBlend")


local state = {
	enabled = false,
	installed = false,
	blend = 40,
	last_buf = nil,
	last_win = nil,
	last_row = nil,
	last_line = nil,
	cursorline_bg = nil,
	bg_groups = {},
	fg_groups = {},
	text_runs = {},
	sources = { text = {}, virtual = {} },
}

local DEFAULT_TS_PRIORITY = 100
local DEFAULT_LSP_PRIORITY = 125
local DEFAULT_EXTMARK_PRIORITY = 0
local DEFAULT_SYNTAX_PRIORITY = 0

-- Some virtual-text plugins use a foreground-coloured block glyph as a
-- background surrogate. Only these explicit fill glyphs may have their
-- foreground blended; ordinary virtual-text foregrounds stay untouched.
local FILL_CHARS = {
	["▁"] = true,
	["▂"] = true,
	["▃"] = true,
	["▅"] = true,
	["▆"] = true,
	["▇"] = true,

	["▏"] = true,
	["▎"] = true,
	["▍"] = true,
	["▋"] = true,
	["▊"] = true,
	["▉"] = true,

	["█"] = true,
	["▓"] = true,
	["▒"] = true,
	["░"] = true,

	["▀"] = true,
	["▄"] = true,
	["▌"] = true,
	["▐"] = true,

	["▖"] = true,
	["▗"] = true,
	["▘"] = true,
	["▝"] = true,
	["▚"] = true,
	["▞"] = true,
	["▙"] = true,
	["▛"] = true,
	["▜"] = true,
	["▟"] = true,
}

-- Plain buffer whitespace is left entirely to native CursorLine.
local function normalize_priority(value, fallback)
	if type(value) == "number" then
		return value
	end

	local number = tonumber(value)
	if number ~= nil then
		return number
	end

	return fallback
end

local function item_priority(item, fallback)
	if type(item) ~= "table" then
		return fallback
	end

	if item.priority ~= nil then
		return normalize_priority(item.priority, fallback)
	end

	if type(item.opts) == "table" and item.opts.priority ~= nil then
		return normalize_priority(item.opts.priority, fallback)
	end

	local metadata = item.metadata
	if type(metadata) == "table" then
		if metadata.priority ~= nil then
			return normalize_priority(metadata.priority, fallback)
		end

		if item.id ~= nil and type(metadata[item.id]) == "table" then
			return normalize_priority(metadata[item.id].priority, fallback)
		end
	end

	return fallback
end

local function group_name(value)
	if type(value) == "string" and value ~= "" then
		return value
	end

	if type(value) == "number" then
		local name = vim.fn.synIDattr(value, "name")
		if type(name) == "string" and name ~= "" then
			return name
		end
	end

	return nil
end

local function append_group(entries, name, priority, order, hl_eol)
	name = group_name(name)
	if not name then
		return order
	end

	order = order + 1
	entries[#entries + 1] = {
		name = name,
		priority = priority,
		order = order,
		-- `hl_eol` belongs to an extmark's own hl_group. Keep it on the
		-- exact source entry so a later, higher-priority background can
		-- correctly replace both its colour and its EOL behaviour.
		hl_eol = hl_eol == true,
	}

	return order
end

local function append_group_value(entries, value, priority, order, hl_eol)
	if type(value) == "table" then
		for _, group in ipairs(value) do
			order = append_group(entries, group, priority, order, hl_eol)
		end
		return order
	end

	return append_group(entries, value, priority, order, hl_eol)
end

-- One request gets every extmark on the active row. Virtual and normal entries
-- are classified immediately so no later helper asks Neovim for the same row
-- again. Yank never enters either list.
local function collect_row_sources(bufnr, row, line, yank_ns)
	local ok, marks = pcall(
		vim.api.nvim_buf_get_extmarks,
		bufnr,
		-1,
		{ row, 0 },
		{ row, #line },
		{ details = true, hl_name = true }
	)

	if not ok or type(marks) ~= "table" then
		return {}, {}
	end

	local text, virtual = {}, {}
	for order, mark in ipairs(marks) do
		local details = mark[4]
		if type(details) == "table" and details.ns_id ~= ns and details.ns_id ~= yank_ns then
			local priority = normalize_priority(details.priority, DEFAULT_EXTMARK_PRIORITY)
			local end_col = details.end_col
			if details.end_row ~= nil and details.end_row > row then
				end_col = #line
			end
			end_col = type(end_col) == "number" and end_col or #line

			if details.line_hl_group then
				text[#text + 1] = {
					id = mark[1], ns_id = details.ns_id,
					start_col = 0, end_col = #line,
					group = details.line_hl_group, priority = priority,
					hl_eol = details.hl_eol == true, origin = "extmark",
				}
			end
			if details.hl_group then
				text[#text + 1] = {
					id = mark[1], ns_id = details.ns_id,
					start_col = mark[3], end_col = end_col,
					group = details.hl_group, priority = priority,
					hl_eol = details.hl_eol == true, origin = "extmark",
				}
			end
			if type(details.virt_text) == "table" then
				virtual[#virtual + 1] = {
					id = mark[1], ns_id = details.ns_id, anchor_col = mark[3],
					chunks = details.virt_text,
					position = details.virt_text_pos or "eol",
					win_col = details.virt_text_win_col,
					priority = priority, order = order,
				}
			end
		end
	end

	return text, virtual
end

-- Tree-sitter decorations are ephemeral, so they do not appear in the normal
-- extmark query above. Collect their byte ranges once for this row instead of
-- asking inspect_pos() for every buffer character.
local function collect_treesitter_sources(bufnr, row, line)
	local highlighter = vim.treesitter
		and vim.treesitter.highlighter
		and vim.treesitter.highlighter.active[bufnr]
	if not highlighter or not highlighter.tree then
		return {}
	end

	local sources = {}
	local order = 0
	pcall(function()
		highlighter.tree:for_each_tree(function(tstree, tree)
			if not tstree then
				return
			end

			local highlighter_query = highlighter:get_query(tree:lang())
			local query = highlighter_query and highlighter_query:query()
			if not query then
				return
			end

			for capture, node, metadata in query:iter_captures(
				tstree:root(), bufnr, row, row + 1
			) do
				local capture_name = query.captures[capture]
				local hl_id = highlighter_query:get_hl_from_capture(capture)
				if capture_name and capture_name:sub(1, 1) ~= "_" and hl_id ~= 0 then
					local start_row, start_col, end_row, end_col = node:range()
					if start_row <= row and end_row >= row then
						if start_row < row then
							start_col = 0
						end
						if end_row > row then
							end_col = #line
						end

						if end_col > start_col then
							local capture_metadata = type(metadata) == "table"
								and metadata[capture]
							local priority = type(metadata) == "table"
								and (metadata.priority
									or (type(capture_metadata) == "table"
										and capture_metadata.priority))
							order = order + 1
							sources[#sources + 1] = {
								start_col = start_col,
								end_col = end_col,
								group = "@" .. capture_name .. "." .. tree:lang(),
								priority = normalize_priority(priority, DEFAULT_TS_PRIORITY),
								hl_eol = false,
								origin = "treesitter",
								order = order,
							}
						end
					end
				end
			end
		end)
	end)

	return sources
end

local get_hl

-- Vim syntax has no range iterator. synID(..., 1) gives the effective syntax
-- item after transparent groups were resolved; unlike synstack() it is cheap
-- enough to use as the sparse legacy-Syntax probe.
local function syntax_context_at(context, row, col, hl_cache)
	local cached = context.columns[col]
	if cached then
		return cached.groups, cached.has_bg
	end

	local ok, syntax_id = pcall(vim.fn.synID, row + 1, col + 1, 1)
	if not ok or type(syntax_id) ~= "number" or syntax_id == 0 then
		context.columns[col] = { groups = {}, has_bg = false }
		return {}, false
	end

	local info = context.ids[syntax_id]
	if info == nil then
		local resolved_id = vim.fn.synIDtrans(syntax_id)
		local name = vim.fn.synIDattr(resolved_id, "name")
		local hl = name ~= "" and get_hl(name, hl_cache) or nil
		info = {
			name = name ~= "" and name or false,
			has_bg = hl and hl.bg ~= nil or false,
		}
		context.ids[syntax_id] = info
	end

	local groups = info.name and { info.name } or {}
	context.columns[col] = { groups = groups, has_bg = info.has_bg }
	return groups, info.has_bg
end

local function collect_groups(bufnr, row, col, text_sources, syntax_context, empty_eol)

	local entries = {}
	local order = 0

	if syntax_context then
		local syntax_groups = syntax_context_at(
			syntax_context, row, col, syntax_context.hl_cache
		)
		for _, name in ipairs(syntax_groups) do
			order = append_group_value(entries, name, DEFAULT_SYNTAX_PRIORITY, order)
		end
	end

	-- Tree-sitter, LSP semantic tokens and all foreign extmarks are already in
	-- the prepared row list. Fold them in without another Neovim query.
	for _, source in ipairs(text_sources) do
		if
			(source.start_col <= col and source.end_col > col)
			or (
				empty_eol
				and source.hl_eol
				and source.start_col == 0
				and source.end_col == 0
			)
		then
			order = append_group_value(entries, source.group, source.priority,
				order, source.hl_eol)
		end
	end

	table.sort(entries, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.order < b.order
	end)

	-- Keep only the last occurrence of a duplicate group. That occurrence also
	-- represents the highest encountered priority/order for that name.
	local last_index = {}
	for i, entry in ipairs(entries) do
		last_index[entry.name] = i
	end

	local groups = {}
	local signature = {}

	for i, entry in ipairs(entries) do
		if last_index[entry.name] == i then
			groups[#groups + 1] = entry
			signature[#signature + 1] = string.format(
				"%d:%s:%s",
				entry.priority,
				entry.name,
				entry.hl_eol and "eol" or "text"
			)
		end
	end

	local max_priority = DEFAULT_EXTMARK_PRIORITY

	for _, entry in ipairs(entries) do
		if entry.priority > max_priority then
			max_priority = entry.priority
		end
	end

	return groups, table.concat(signature, "|"), max_priority
end

get_hl = function(group, cache)
	local cached = cache[group]
	if cached ~= nil then
		return cached or nil
	end

	local ok, hl = pcall(vim.api.nvim_get_hl, 0, {
		name = group,
		link = false,
		create = false,
	})

	if not ok or type(hl) ~= "table" then
		cache[group] = false
		return nil
	end

	cache[group] = hl
	return hl
end

-- Only ranges which contain a real background can require a normal-text
-- overlay. Foreground-only semantic/tree-sitter sources are still kept in the
-- complete source list: when a BG range is scanned they contribute to that
-- run's final priority, but they never make us decode unrelated text.
local function background_spans(sources, line_len, hl_cache)
	local spans = {}
	for _, source in ipairs(sources) do
		local hl = get_hl(source.group, hl_cache)
		if hl and hl.bg ~= nil then
			local start_col = math.max(0, source.start_col)
			local end_col = math.min(line_len, source.end_col)
			if end_col > start_col then
				spans[#spans + 1] = {
					start_col = start_col,
					end_col = end_col,
				}
			end
		end
	end

	table.sort(spans, function(a, b)
		return a.start_col < b.start_col
	end)

	local merged = {}
	for _, span in ipairs(spans) do
		local previous = merged[#merged]
		if previous and span.start_col <= previous.end_col then
			previous.end_col = math.max(previous.end_col, span.end_col)
		else
			merged[#merged + 1] = span
		end
	end

	return merged
end

local function effective_bg(groups, cache)
	local bg = nil
	local hl_eol = false

	for _, group_entry in ipairs(groups) do
		local group = type(group_entry) == "table"
			and group_entry.name
			or group_entry
		local hl = get_hl(group, cache)
		if hl and hl.bg ~= nil then
			bg = hl.bg
			hl_eol = type(group_entry) == "table"
				and group_entry.hl_eol == true
		end
	end

	return bg, hl_eol
end

local function effective_fg(groups, cache)
	local fg = nil

	for _, group_entry in ipairs(groups) do
		local group = type(group_entry) == "table"
			and group_entry.name
			or group_entry
		local hl = get_hl(group, cache)
		if hl and hl.fg ~= nil then
			fg = hl.fg
		end
	end

	return fg
end

local function cursorline_bg()
	local ok, hl = pcall(vim.api.nvim_get_hl, 0, {
		name = "CursorLine",
		link = false,
		create = false,
	})

	if not ok or type(hl) ~= "table" then
		return nil
	end

	return hl.bg
end

local bit = require("bit")

local function mix_channel(a, b, amount)
	return bit.tobit(a + ((b - a) * amount * 0.01) + 0.5)
	-- return math.floor(a + ((b - a) * amount / 100) + 0.5)
end

local function mix_rgb(base, overlay, amount)
	local br = bit.band(bit.rshift(base, 16), 0xFF)
	local bg = bit.band(bit.rshift(base, 8), 0xFF)
	local bb = bit.band(base, 0xFF)

	local or_ = bit.band(bit.rshift(overlay, 16), 0xFF)
	local og = bit.band(bit.rshift(overlay, 8), 0xFF)
	local ob = bit.band(overlay, 0xFF)

	-- local br = math.floor(base / 0x10000) % 0x100
	-- local bg = math.floor(base / 0x100) % 0x100
	-- local bb = base % 0x100
	--
	-- local or_ = math.floor(overlay / 0x10000) % 0x100
	-- local og = math.floor(overlay / 0x100) % 0x100
	-- local ob = overlay % 0x100

	local r = mix_channel(br, or_, amount)
	local g = mix_channel(bg, og, amount)
	local b = mix_channel(bb, ob, amount)

	return (r * 0x10000) + (g * 0x100) + b
end

local function refresh_bg_groups(new_cursorline_bg)
	state.cursorline_bg = new_cursorline_bg

	if new_cursorline_bg == nil then
		return
	end

	for base_bg, group in pairs(state.bg_groups) do
		vim.api.nvim_set_hl(0, group, {
			bg = mix_rgb(base_bg, new_cursorline_bg, state.blend),
		})
	end

	for base_fg, group in pairs(state.fg_groups) do
		vim.api.nvim_set_hl(0, group, {
			fg = mix_rgb(base_fg, new_cursorline_bg, state.blend),
		})
	end
end

local function mixed_bg_group(base_bg, current_cursorline_bg)
	if state.cursorline_bg ~= current_cursorline_bg then
		refresh_bg_groups(current_cursorline_bg)
	end

	local group = state.bg_groups[base_bg]
	if group then
		return group
	end

	group = string.format("LineBlendBg_%06X", base_bg)
	state.bg_groups[base_bg] = group

	vim.api.nvim_set_hl(0, group, {
		bg = mix_rgb(base_bg, current_cursorline_bg, state.blend),
	})

	return group
end

local function mixed_fg_group(base_fg, current_cursorline_bg)
	if state.cursorline_bg ~= current_cursorline_bg then
		refresh_bg_groups(current_cursorline_bg)
	end

	local group = state.fg_groups[base_fg]
	if group then
		return group
	end

	group = string.format("LineBlendFg_%06X", base_fg)
	state.fg_groups[base_fg] = group

	vim.api.nvim_set_hl(0, group, {
		fg = mix_rgb(base_fg, current_cursorline_bg, state.blend),
	})

	return group
end

local function display_width(value, start_col)
	local ok, width = pcall(vim.fn.strdisplaywidth, value, start_col or 0)
	if ok and type(width) == "number" then
		return width
	end

	return vim.fn.strdisplaywidth(value)
end

-- Parse UTF-8 without relying on the version-dependent vim.str_* signatures.
-- Besides byte columns, keep screen columns: virtual text is rendered in screen
-- cells, while extmark anchors are buffer-byte columns.
local function utf8_chars(line)
	local chars = {}
	local i = 1
	local n = #line
	local screen_col = 0

	while i <= n do
		local b = line:byte(i)
		local len = 1

		if b >= 0xC2 and b <= 0xDF then
			len = 2
		elseif b >= 0xE0 and b <= 0xEF then
			len = 3
		elseif b >= 0xF0 and b <= 0xF4 then
			len = 4
		end

		if i + len - 1 > n then
			len = 1
		else
			for j = i + 1, i + len - 1 do
				local continuation = line:byte(j)
				if continuation < 0x80 or continuation > 0xBF then
					len = 1
					break
				end
			end
		end

		local finish = i + len - 1
		local char_text = line:sub(i, finish)
		local width = display_width(char_text, screen_col)

		chars[#chars + 1] = {
			start_col = i - 1,
			end_col = finish,
			text = char_text,
			whitespace = b == 0x20 or b == 0x09,
			screen_start = screen_col,
			screen_end = screen_col + width,
		}

		screen_col = screen_col + width
		i = finish + 1
	end

	return chars
end

-- A byte-column iterator for normal buffer text. Unlike utf8_chars(), it
-- allocates nothing and is called only inside a background-bearing source
-- span. The full character/screen-cell parser remains virtual-text-only.
local function next_utf8_col(line, col)
	local index = col + 1
	local byte = line:byte(index)
	if byte == nil then
		return #line
	end

	local length = 1
	if byte >= 0xC2 and byte <= 0xDF then
		length = 2
	elseif byte >= 0xE0 and byte <= 0xEF then
		length = 3
	elseif byte >= 0xF0 and byte <= 0xF4 then
		length = 4
	end

	if index + length - 1 > #line then
		return index
	end
	for continuation_index = index + 1, index + length - 1 do
		local continuation = line:byte(continuation_index)
		if continuation == nil or continuation < 0x80 or continuation > 0xBF then
			return index
		end
	end

	return col + length
end

local function syntax_background_spans(line, row, syntax_context)
	local spans = {}
	local col = 0
	local span_start = nil

	while col < #line do
		local next_col = next_utf8_col(line, col)
		local _, has_bg = syntax_context_at(
			syntax_context, row, col, syntax_context.hl_cache
		)

		if has_bg then
			span_start = span_start or col
		elseif span_start ~= nil then
			spans[#spans + 1] = {
				start_col = span_start,
				end_col = col,
			}
			span_start = nil
		end

		col = next_col
	end

	if span_start ~= nil then
		spans[#spans + 1] = {
			start_col = span_start,
			end_col = #line,
		}
	end

	return spans
end

local function merge_byte_spans(first, second)
	local spans = {}
	for _, span in ipairs(first) do
		spans[#spans + 1] = span
	end
	for _, span in ipairs(second) do
		spans[#spans + 1] = span
	end

	table.sort(spans, function(a, b)
		return a.start_col < b.start_col
	end)

	local merged = {}
	for _, span in ipairs(spans) do
		local previous = merged[#merged]
		if previous and span.start_col <= previous.end_col then
			previous.end_col = math.max(previous.end_col, span.end_col)
		else
			merged[#merged + 1] = {
				start_col = span.start_col,
				end_col = span.end_col,
			}
		end
	end

	return merged
end

local function virt_hl_stack(value)
	local stack = {}

	local function add(group)
		group = group_name(group)
		if group then
			stack[#stack + 1] = group
		end
	end

	if type(value) == "table" then
		for _, group in ipairs(value) do
			add(group)
		end
	else
		add(value)
	end

	return stack
end

local function contains_fill_char(text)
	for fill_char in pairs(FILL_CHARS) do
		if text:find(fill_char, 1, true) then
			return true
		end
	end

	return false
end

-- A virtual source is worth the screen-cell path only if at least one of its
-- chunks can actually change under LineBlend: a real BG, or a block-fill glyph
-- whose visible FG needs blending. Keep the original complete chunk list for
-- layout, but record exactly which chunks may be cloned.
local function relevant_virtual_sources(sources, hl_cache)
	local relevant = {}

	for _, source in ipairs(sources) do
		if source.position ~= "inline" then
			local relevant_chunks = {}

			for index, chunk in ipairs(source.chunks) do
				local text = chunk[1]
				if type(text) == "string" and text ~= "" then
					local stack = virt_hl_stack(chunk[2])
					local has_bg = effective_bg(stack, hl_cache) ~= nil
					local is_fill = contains_fill_char(text)
					local has_fill_fg = is_fill
						and effective_fg(stack, hl_cache) ~= nil

					if has_bg or has_fill_fg then
						relevant_chunks[index] = true
					end
				end
			end

			if next(relevant_chunks) ~= nil then
				local prepared = vim.tbl_extend("force", {}, source)
				prepared.relevant_chunks = relevant_chunks
				relevant[#relevant + 1] = prepared
			end
		end
	end

	return relevant
end

local function append_lineblend_hl(original, is_fill, line_bg, hl_cache)
	local stack = virt_hl_stack(original)

	-- Important: no explicit background means "inherit whatever is below".
	-- On the cursor row that is already CursorLine. Falling back to Normal here
	-- would create dark holes for virtual-text spaces (e.g. ITHNormal -> NonText).
	local base_bg = effective_bg(stack, hl_cache)
	local base_fg = nil

	-- A fill glyph such as "█" uses its foreground as the visible cell colour.
	-- Blend that foreground as well, but never touch ordinary virtual-text FG.
	if is_fill then
		base_fg = effective_fg(stack, hl_cache)
	end

	if base_bg ~= nil then
		stack[#stack + 1] = mixed_bg_group(base_bg, line_bg)
	end

	if base_fg ~= nil then
		stack[#stack + 1] = mixed_fg_group(base_fg, line_bg)
	end

	-- nil as the second virt_text chunk item means: no highlight of our own.
	-- With hl_mode="combine", CursorLine can then pass through unchanged.
	if #stack == 0 then
		return nil
	end

	return stack
end

local function virt_text_width(chunks, start_screen)
	local screen = start_screen

	for _, chunk in ipairs(chunks or {}) do
		local chunk_text = chunk[1]
		if type(chunk_text) == "string" and chunk_text ~= "" then
			screen = screen + display_width(chunk_text, screen)
		end
	end

	return screen - start_screen
end

local function append_screen_span(spans, start_col, end_col)
	if end_col <= start_col then
		return
	end

	local previous = spans[#spans]
	if previous and start_col <= previous.end_col then
		previous.end_col = math.max(previous.end_col, end_col)
		return
	end

	spans[#spans + 1] = {
		start_col = start_col,
		end_col = end_col,
	}
end

-- Only these screen cells can need a virtual-text clone. Normal buffer text is
-- left entirely to its native highlight stack and never enters the virt_text
-- pipeline.
local function relevant_screen_spans(chars, line, winid)
	local spans = {}

	for _, char in ipairs(chars) do
		if char.whitespace then
			append_screen_span(spans, char.screen_start, char.screen_end)
		end
	end

	local line_width = display_width(line, 0)
	append_screen_span(
		spans,
		line_width,
		vim.api.nvim_win_get_width(winid) + 8
	)

	return spans
end

local function overlaps_relevant_span(spans, start_col, end_col)
	for _, span in ipairs(spans) do
		if start_col < span.end_col and end_col > span.start_col then
			return true
		end
	end

	return false
end

-- Convert only foreign virtual text that overlaps whitespace or EOL into small
-- units. Normal buffer text never needs a clone, so its virtual overlays are
-- rejected before UTF-8 splitting and highlight work begins.
local function collect_virtual_units(
	line,
	winid,
	sources,
	relevant_spans
)
	local units = {}
	local order = 0
	local block_id = 0
	local line_width = display_width(line, 0)
	local win_width = vim.api.nvim_win_get_width(winid)

	for _, source in ipairs(sources) do
		local col = source.anchor_col
		local details = {
			virt_text = source.chunks,
			virt_text_pos = source.position,
			virt_text_win_col = source.win_col,
			priority = source.priority,
		}
		local pos = details.virt_text_pos or "eol"

			-- Inline virtual text changes layout. Re-emitting it would shift the
			-- line a second time, so it is intentionally left to Neovim.
		if pos ~= "inline" then
				local start_screen
				local total_width = virt_text_width(details.virt_text, 0)

				if type(details.virt_text_win_col) == "number" then
					start_screen = details.virt_text_win_col
				elseif pos == "overlay" then
					start_screen = display_width(
						line:sub(1, math.max(col, 0)),
						0
					)
				elseif pos == "right_align" then
					start_screen = math.max(0, win_width - total_width)
				elseif pos == "eol_right_align" then
					start_screen = math.max(
						line_width,
						win_width - total_width
					)
				else
					start_screen = line_width
				end

				local screen = start_screen
				local priority = source.priority

				for chunk_index, chunk in ipairs(details.virt_text) do
					local chunk_text = chunk[1]
					local chunk_hl = chunk[2]

					if type(chunk_text) == "string" and chunk_text ~= "" then
						local chunk_width = display_width(chunk_text, screen)
						local chunk_end = screen + chunk_width

						if source.relevant_chunks[chunk_index] and overlaps_relevant_span(
							relevant_spans,
							screen,
							chunk_end
						) then
							block_id = block_id + 1
							local chunk_chars = utf8_chars(chunk_text)

							for _, char in ipairs(chunk_chars) do
								local width = display_width(char.text, screen)
								local char_end = screen + width

								if
									width > 0
									and overlaps_relevant_span(
										relevant_spans,
										screen,
										char_end
									)
								then
									order = order + 1
									units[#units + 1] = {
										id = order,
										block_id = block_id,
										text = char.text,
										fill = FILL_CHARS[char.text] == true,
										hl = chunk_hl,
										priority = priority,
										screen_start = screen,
										screen_end = char_end,
										order = source.order,
									}
								end

								screen = char_end
							end
						else
							screen = chunk_end
						end
					end
				end
		end
	end

	return units
end

local function overlaps(a_start, a_end, b_start, b_end)
	return a_start < b_end and a_end > b_start
end

-- Highest priority is what is visible. For equal priorities we use the later
-- unit returned by extmark traversal as the practical tie-breaker.
local function visible_virtual_unit(units, screen_start, screen_end)
	local winner = nil

	for _, unit in ipairs(units) do
		if overlaps(
			unit.screen_start,
			unit.screen_end,
			screen_start,
			screen_end
		) then
			if
				winner == nil
				or unit.priority > winner.priority
				or (
					unit.priority == winner.priority
					and unit.order > winner.order
				)
			then
				winner = unit
			end
		end
	end

	return winner
end

local function clear_last()
	if state.last_buf and vim.api.nvim_buf_is_valid(state.last_buf) then
		vim.api.nvim_buf_clear_namespace(state.last_buf, ns, 0, -1)
	end

	state.last_buf = nil
	state.last_win = nil
	state.last_row = nil
	state.last_line = nil
	state.text_runs = {}
	state.sources = { text = {}, virtual = {} }
end

local function remember_last(winid, bufnr, row, line)
	state.last_win = winid
	state.last_buf = bufnr
	state.last_row = row
	state.last_line = line
end

local function draw_virtual_block(
	bufnr,
	row,
	anchor_col,
	block,
	line_bg,
	hl_cache
)
	local opts = {
		virt_text = {
			{
				block.text,
				append_lineblend_hl(
					block.hl,
					block.fill,
					line_bg,
					hl_cache
				),
			},
		},
		hl_mode = "combine",
		priority = block.priority + 1,
		virt_text_win_col = block.screen_start,
	}

	vim.api.nvim_buf_set_extmark(
		bufnr,
		ns,
		row,
		anchor_col,
		opts
	)
end

local function new_virtual_block(unit)
	return {
		block_id = unit.block_id,
		text = unit.text,
		fill = unit.fill,
		hl = unit.hl,
		priority = unit.priority,
		screen_start = unit.screen_start,
		screen_end = unit.screen_end,
	}
end

local function append_virtual_unit(block, unit)
	if
		block ~= nil
		and block.block_id == unit.block_id
		and block.fill == unit.fill
		and block.screen_end == unit.screen_start
	then
		block.text = block.text .. unit.text
		block.screen_end = unit.screen_end
		return block
	end

	return nil
end

local function draw_whitespace_run(
	bufnr,
	row,
	chars,
	first,
	last,
	virtual_units,
	drawn_units,
	line_bg,
	hl_cache
)
	local block = nil
	local anchor_col = chars[first].start_col

	local function flush()
		if block ~= nil then
			draw_virtual_block(
				bufnr,
				row,
				anchor_col,
				block,
				line_bg,
				hl_cache
			)
			block = nil
		end
	end

	for i = first, last do
		local char = chars[i]

		-- A space occupies one screen cell, but a TAB occupies several.
		-- Parse whitespace in screen cells here, otherwise only one virtual-text
		-- unit inside a whole TAB would be seen and the remaining TAB cells could
		-- keep the wrong background.
		local screen = char.screen_start

		while screen < char.screen_end do
			local unit = visible_virtual_unit(
				virtual_units,
				screen,
				screen + 1
			)

			if unit ~= nil then
				if not drawn_units[unit.id] then
					if append_virtual_unit(block, unit) == nil then
						flush()
						block = new_virtual_block(unit)
					end
					drawn_units[unit.id] = true
				else
					flush()
				end

				screen = math.max(screen + 1, unit.screen_end)
			else
				flush()
				-- No foreign virtual text in this cell: native CursorLine is
				-- already correct, so leave it completely untouched.
				screen = screen + 1
			end
		end

	end

	flush()
end

local function draw_eol(
	bufnr,
	winid,
	row,
	line,
	virtual_units,
	drawn_units,
	line_bg,
	hl_cache
)
	local first = display_width(line, 0)
	local last = vim.api.nvim_win_get_width(winid) + 8
	local col = first
	local block = nil

	local function flush()
		if block ~= nil then
			draw_virtual_block(
				bufnr,
				row,
				#line,
				block,
				line_bg,
				hl_cache
			)
			block = nil
		end
	end

	while col < last do
		local unit = visible_virtual_unit(
			virtual_units,
			col,
			col + 1
		)

		if unit ~= nil then
			if not drawn_units[unit.id] then
				if append_virtual_unit(block, unit) == nil then
					flush()
					block = new_virtual_block(unit)
				end
				drawn_units[unit.id] = true
			else
				flush()
			end

			col = math.max(col + 1, unit.screen_end)
		else
			flush()
			-- Native CursorLine already covers empty screen cells after EOL.
			-- We only need to intervene where foreign virtual text exists.
			col = col + 1
		end
	end

	flush()
end

local function draw_text_spans(
	row,
	line,
	spans,
	line_bg,
	normal_bg,
	hl_cache,
	inspect
)
	local run = nil
	local last_eol_col = nil

	local function flush()
		if run ~= nil then
			state.text_runs[#state.text_runs + 1] = run
			run = nil
		end
	end

	for _, span in ipairs(spans) do
		local col = span.start_col
		while col < span.end_col do
			local next_col = next_utf8_col(line, col)
			if next_col > span.end_col then
				-- Extmarks normally land on character boundaries. If a malformed
				-- source does not, retain its exact byte range rather than decoding
				-- bytes outside the source.
				next_col = span.end_col
			end

			local groups, _, max_priority = inspect(col)
			local bg = effective_bg(groups, hl_cache)
			if bg ~= nil and bg ~= normal_bg then
				local mixed = mixed_bg_group(bg, line_bg)
				local priority = max_priority + 1
				if run
					and run.end_col == col
					and run.hl_group == mixed
					and run.priority == priority
				then
					run.end_col = next_col
				else
					flush()
					run = {
						row = row,
						start_col = col,
						end_col = next_col,
						hl_group = mixed,
						priority = priority,
					}
				end
			else
				flush()
			end

			if next_col == #line then
				last_eol_col = col
			end
			col = next_col
		end
		-- Gaps between source spans are deliberately native CursorLine only.
		flush()
	end

	return last_eol_col
end

-- `hl_eol` only takes effect on a range that actually reaches the next line.
-- The text runs above deliberately stop at their last buffer character, so the
-- EOL part needs its own zero-text, one-line range. Its colour is determined
-- from the final buffer character, where the source still proves that it
-- reaches this line's EOL.
local function queue_eol_run(
	row,
	source_col,
	eol_col,
	line_bg,
	normal_bg,
	hl_cache,
	inspect
)
	-- `end_col` is exclusive, so querying exactly at #line is already outside
	-- a normal highlight range. The final buffer character is the last position
	-- where a source can prove that it reaches this line's EOL.
	local groups, _, max_priority = inspect(source_col)
	local bg, hl_eol = effective_bg(groups, hl_cache)

	if hl_eol and bg ~= nil and bg ~= normal_bg then
		state.text_runs[#state.text_runs + 1] = {
			row = row,
			start_col = eol_col,
			end_row = row + 1,
			hl_group = mixed_bg_group(bg, line_bg),
			priority = max_priority + 1,
			hl_eol = true,
		}
	end
end

local function visual_active()
	local mode = vim.fn.mode(1)
	local first = mode:sub(1, 1)

	return first == "v" or first == "V" or first == "\22"
end

function M.refresh(force)
	if not state.enabled then
		return
	end

	local winid = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local row = vim.api.nvim_win_get_cursor(winid)[1] - 1

	-- Read the line before checking the render cache so text changes invalidate it.
	local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""

	-- CursorMoved/CursorMovedI also fire for horizontal movement. If the
	-- rendered buffer+row did not change, the existing overlay is still valid,
	-- so do not clear it and do not parse the line again.
	if
		not force
		and state.last_buf  == bufnr
		and state.last_row  == row
		and state.last_line == line
	then
		return
	end

	clear_last()

	-- Visual mode owns the focused-row rendering completely.
	-- ModeChanged calls refresh(true), so entering Visual clears LineBlend and
	-- leaving Visual reconstructs the current line even if buf+row are unchanged.
	if visual_active() then
		return
	end

	local line_bg = cursorline_bg()

	if line_bg == nil then
		return
	end

	if state.cursorline_bg ~= line_bg then
		refresh_bg_groups(line_bg)
	end

	local yank_ns = vim.api.nvim_get_namespaces()["nvim.hlyank"]
	local extmark_sources, all_virtual_sources = collect_row_sources(
		bufnr, row, line, yank_ns
	)
	local text_sources = collect_treesitter_sources(bufnr, row, line)
	for _, source in ipairs(extmark_sources) do
		text_sources[#text_sources + 1] = source
	end
	local hl_cache = {}
	local virtual_sources = relevant_virtual_sources(
		all_virtual_sources, hl_cache
	)
	state.sources = { text = text_sources, virtual = virtual_sources }
	local normal = get_hl("Normal", hl_cache)
	local normal_bg = normal and normal.bg or nil
	local use_syntax = vim.bo[bufnr].syntax ~= ""
	local syntax_context = use_syntax and {
		columns = {},
		ids = {},
		hl_cache = hl_cache,
	} or nil
	local text_spans = background_spans(text_sources, #line, hl_cache)
	if syntax_context then
		text_spans = merge_byte_spans(
			text_spans,
			syntax_background_spans(line, row, syntax_context)
		)
	end

	-- Full UTF-8/screen-cell parsing is exclusively for relevant virtual text.
	-- A normal line with no blendable virtual source never constructs characters.
	local chars = nil
	local virtual_units = {}
	local drawn_units = {}
	if #virtual_sources > 0 then
		chars = utf8_chars(line)
		virtual_units = collect_virtual_units(line, winid, virtual_sources,
			relevant_screen_spans(chars, line, winid))
	end

	local inspect_cache = {}

	local function inspect(col, empty_eol)
		local cache_key = empty_eol and "eol" or col
		local cached = inspect_cache[cache_key]
		if cached then
			return cached.groups, cached.signature, cached.max_priority
		end

		local groups, signature, max_priority = collect_groups(
			bufnr,
			row,
			col,
			text_sources,
			syntax_context,
			empty_eol
		)
		inspect_cache[cache_key] = {
			groups = groups,
			signature = signature,
			max_priority = max_priority,
		}
		return groups, signature, max_priority
	end

	if #line == 0 then
		queue_eol_run(
			row,
			0,
			#line,
			line_bg,
			normal_bg,
			hl_cache,
			function(col)
				return inspect(col, true)
			end
		)
		if #virtual_units > 0 then
			draw_eol(bufnr, winid, row, line, virtual_units, drawn_units,
				line_bg, hl_cache)
		end
		remember_last(winid, bufnr, row, line)
		return
	end

	-- Normal text is decoded only inside background-bearing Tree-sitter/extmark
	-- spans. Every other byte is left entirely to native rendering.
	local eol_source_col = draw_text_spans(
		row,
		line,
		text_spans,
		line_bg,
		normal_bg,
		hl_cache,
		inspect
	)

	if eol_source_col ~= nil then
		queue_eol_run(
			row,
			eol_source_col,
			#line,
			line_bg,
			normal_bg,
			hl_cache,
			inspect
		)
	end

	if #virtual_units > 0 then
		-- No virtual source means native CursorLine is already correct for every
		-- whitespace and EOL cell, so neither screen-cell loop may run.
		local i = 1
		while i <= #chars do
			if chars[i].whitespace then
				local j = i + 1
				while j <= #chars and chars[j].whitespace do
					j = j + 1
				end
				draw_whitespace_run(bufnr, row, chars, i, j - 1,
					virtual_units, drawn_units, line_bg, hl_cache)
				i = j
			else
				i = i + 1
			end
		end
		draw_eol(bufnr, winid, row, line, virtual_units, drawn_units,
			line_bg, hl_cache)
	end

	remember_last(winid, bufnr, row, line)
end

function M.set_blend(value)
	value = tonumber(value)

	if not value or value < 0 or value > 100 then
		error("LineBlend expects a number from 0 to 100")
	end

	state.blend = value

	local bg = cursorline_bg()
	if bg ~= nil then
		refresh_bg_groups(bg)
	end

	M.refresh(true)
	vim.cmd("redraw")
end

function M.reload()
	if not state.enabled then
		return
	end

	-- Rebuild generated highlight groups as well as the current render state.
	state.cursorline_bg = nil
	state.bg_groups = {}
	state.fg_groups = {}
	M.refresh(true)
	vim.cmd("redraw")
end

local function install_decoration_provider()
	vim.api.nvim_set_decoration_provider(ns, {
		on_win = function(_, winid, bufnr)
			if
				not state.enabled
				or winid ~= state.last_win
				or bufnr ~= state.last_buf
			then
				return false
			end

			for _, run in ipairs(state.text_runs) do
				local opts = {
					hl_group = run.hl_group,
					priority = run.priority,
					ephemeral = true,
				}

				if run.hl_eol then
					-- Neovim only expands hl_eol for a range that reaches the
					-- following line. This EOL-only run starts at #line, so it
					-- cannot repaint any preceding buffer text.
					opts.end_row = run.end_row
					opts.hl_eol = true
				else
					opts.end_row = run.row
					opts.end_col = run.end_col
				end

				vim.api.nvim_buf_set_extmark(
					bufnr,
					ns,
					run.row,
					run.start_col,
					opts
				)
			end

			return false
		end,
	})
end

function M.activate(opts)
	opts = opts or {}

	if opts.blend ~= nil then
		local value = tonumber(opts.blend)
		assert(
			value and value >= 0 and value <= 100,
			"lineblend.setup(): blend must be 0..100"
		)
		state.blend = value
	end

	state.enabled = true
	if state.installed then
		M.refresh(true)
		return
	end
	state.installed = true

	install_decoration_provider()

	local augroup = vim.api.nvim_create_augroup("LineBlend", {
		clear = true,
	})

	-- Horizontal cursor movement on the same row is the hot path: refresh(false)
	-- returns before clear_last(), nvim_buf_get_lines(), UTF-8 scanning, highlight
	-- inspection, or virtual-text parsing.
	vim.api.nvim_create_autocmd({
		"CursorMoved",
		"CursorMovedI",
	}, {
		group = augroup,
		callback = function()
			if state.enabled then
				M.refresh(false)
			end
		end,
	})

	-- These events can change the rendered result without changing buffer+row.
	vim.api.nvim_create_autocmd({
		"ModeChanged",
		"BufEnter",
		"WinEnter",
		"WinResized",
		"DiagnosticChanged",
		"TextChanged",
		"TextChangedP",
	}, {
		group = augroup,
		callback = function()
			if state.enabled then
				M.refresh(true)
			end
		end,
	})

	-- A typed character changes last_line, so refresh(false) rebuilds precisely
	-- when the active row changed and otherwise preserves the current overlay.
	vim.api.nvim_create_autocmd("TextChangedI", {
		group = augroup,
		callback = function()
			if state.enabled then
				M.refresh(false)
			end
		end,
	})

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = augroup,
		callback = function()
			vim.schedule(function()
				if state.enabled then
					M.refresh(true)
				end
			end)
		end,
	})

	M.refresh(true)
end

-- Keep setup() as an alias for direct callers. ChromaFlow invokes it only when
-- lineblend.autostart is true; later activate() calls reuse the installed provider
-- and autocmds instead of registering them again.
M.setup = M.activate

function M.is_active()
	return state.enabled
end

function M.stop()
	state.enabled = false
	clear_last()
	vim.cmd("redraw")
end

function M.status()
	local runs = {}

	for _, run in ipairs(state.text_runs) do
		runs[#runs + 1] = {
			row = run.row,
			start_col = run.start_col,
			end_col = run.end_col,
			hl_group = run.hl_group,
			priority = run.priority,
		}
	end

	return {
		enabled = state.enabled,
		blend = state.blend,
		last_win = state.last_win,
		last_buf = state.last_buf,
		last_row = state.last_row,
		last_line = state.last_line,
		cursorline_bg = state.cursorline_bg,
		text_runs = runs,
		virtual_sources = vim.deepcopy(state.sources.virtual),
		text_sources = vim.deepcopy(state.sources.text),
	}
end

return M
