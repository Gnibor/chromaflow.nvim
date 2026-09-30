-- Cold editor only. The draft holds DSL operations/source edits, not another
-- persistent highlight cache. Live results belong to cf.fn.runtime.
local M = {}
local api = vim.api
local color = require("cf.color")
local pipeline = require("cf.hl.pipeline")
local runtime = require("cf.fn.runtime")
local setup = require("cf.hl.setup")
local Float = require("cf.fn.float")
local menu = require("cf.menu")
local fields = { "fg", "bg", "sp", "ctermfg", "ctermbg" }
local channels = { "fg", "bg", "sp", "cfg", "cbg" }
local operations = { "mix", "opacity", "brightness", "lighten", "darken", "shiftHue", "gamma" }
local defaults = { 30, 100, 0, 5, 5, 0, 1 }
local namespace = api.nvim_create_namespace("cf.picker.pipeline")
local active
local keywords = {}
for key in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%S+") do keywords[key] = true end

function M.close()
	if active then active.cancel(false) end
end

local function copy(t)
	local out = {}
	for k, v in pairs(t or {}) do out[k] = v end
	return out
end

local function palette_entries(colors)
	local result, visiting = {}, {}
	local function walk(value, path)
		if type(value) == "table" then
			if visiting[value] then return end
			visiting[value] = true
			for key, child in pairs(value) do
				local suffix
				if type(key) == "string" then
					suffix = key:match("^[%a_][%w_]*$") and not keywords[key] and ("." .. key) or ("[" .. string.format("%q", key) .. "]")
				elseif type(key) == "number" then suffix = "[" .. tostring(key) .. "]" end
				if suffix then walk(child, path .. suffix) end
			end
			visiting[value] = nil
		elseif type(value) == "number" or type(value) == "string" then
			local ok, packed = pcall(color.from_hex, value)
			if type(value) == "number" then ok, packed = value >= 0 and value <= 0xffffffff and value % 1 == 0, value end
			if ok then result[#result + 1] = { label = "c" .. path, expr = "c" .. path, value = packed } end
		end
	end
	walk(colors, "")
	table.sort(result, function(a, b) return a.label < b.label end)
	return result
end

local function display(value)
	return value ~= nil and color.to_hex(value) or "unset"
end

local function clone_operation(op)
	assert(type(op) == "table" and operations[op[1]] and channels[op[2]],
		"ChromaFlow: this pipeline contains an unsupported/dynamic operation")
	return { op[1], op[2], op[3], op[4] }
end

function M.open(opts)
	assert(not active, "ChromaFlow: a pipeline editor is already open")
	local theme = require("cf.theme").current()
	local source = require("cf.save")._pipeline_source(opts.edit, opts.spec.pipeline)
	assert(opts.reset or not opts.spec.link, "ChromaFlow: edit the linked style's owner before adding a pipeline")
	local state = runtime._picker_style_state(opts.edit.target)
	local initial = opts.reset and {} or copy(opts.spec)
	initial.pipeline = nil
	local base = setup._build_style(initial, opts.inherited, nil)
	local draft = { fields = {}, steps = {} }
	local palette = palette_entries(theme.colors)
	local by_expr = {}
	for _, item in ipairs(palette) do by_expr[item.expr] = item end
	local original_ops = opts.spec.pipeline or {}
	assert(#original_ops == #source.steps, "ChromaFlow: pipeline source no longer matches compiled operations; reload first")
	if not opts.reset then
		for i, op in ipairs(original_ops) do draft.steps[i] = { original = i, op = clone_operation(op) } end
	end
	if opts.pending then
		assert(source.signature == opts.pending.original.signature, "ChromaFlow: source changed; reload first")
		for field, expr in pairs(opts.pending.fields) do
			local raw = expr:match('^require%("cf.color"%).to_cterm%((.*)%)$') or expr
			draft.fields[field] = assert(by_expr[raw], "ChromaFlow: selected palette entry is no longer available")
		end
		if opts.pending.steps then
			draft.steps = {}
			for i, step in ipairs(opts.pending.steps) do
				local op
				if step.original then op = clone_operation(original_ops[step.original])
				else
					op = pipeline[step.name][step.channel](step.value, step.color_expr and assert(by_expr[step.color_expr]).value)
				end
				if step.value ~= nil then op[3] = step.value end
				if step.color_expr then op[4] = assert(by_expr[step.color_expr]).value end
				draft.steps[i] = { original = step.original, op = op, value = step.value, color_expr = step.color_expr }
			end
		end
	end
	local editor = { row = 0, col = 1, draft = draft, palette = palette }
	local closed, suspended, previewed = false, false, false
	local lineblend = require("cf.fn.lineblend")
	local restore_lineblend = lineblend.is_active()
	local float, columns, starts, traces, working, final, resize_group
	local render, show
	local function valid()
		if require("cf.theme").current() == theme then return true end
		api.nvim_echo({ { "ChromaFlow: theme reloaded; reopen Pipeline", "WarningMsg" } }, false, {})
		return false
	end
	local function delta()
		local result = { fields = {}, original = source }
		for field, item in pairs(draft.fields) do
			result.fields[field] = (field == "ctermfg" or field == "ctermbg") and ('require("cf.color").to_cterm(' .. item.expr .. ')') or item.expr
		end
		local changed = #draft.steps ~= (opts.reset and 0 or #original_ops)
		local steps = {}
		for i, step in ipairs(draft.steps) do
			if step.original ~= i or step.value ~= nil or step.color_expr then changed = true end
			steps[i] = { original = step.original, name = operations[step.op[1]], channel = channels[step.op[2]],
				value = step.original and step.value or step.op[3], color_expr = step.color_expr }
		end
		if changed then result.steps = steps end
		return (changed or next(result.fields)) and result or nil
	end
	local function compute(write)
		working = copy(base)
		for field, item in pairs(draft.fields) do
			working[field] = (field == "ctermfg" or field == "ctermbg") and color.to_cterm(item.value) or item.value
		end
		local ops = {}
		columns = { {}, {}, {}, {}, {} }
		for i, step in ipairs(draft.steps) do
			ops[i] = step.op
			local list = columns[step.op[2]]
			list[#list + 1] = i
		end
		local fg, bg, sp = working.fg, working.bg, working.sp
		local cfg = working.ctermfg and color.from_cterm(working.ctermfg)
		local cbg = working.ctermbg and color.from_cterm(working.ctermbg)
		starts = { fg, bg, sp, cfg or fg, cbg or bg }
		traces = {}
		-- Read the existing compile traces for unchanged operations; edited chains
		-- are traced through the exact same DSL executor, never custom colour math.
		local cached = require("cf.colortrace")._cached(opts.edit.source.file, theme)
		local cached_sources = cached and cached.by_source or {}
		for i, step in ipairs(draft.steps) do
			local trace
			fg, bg, sp, trace, cfg, cbg = pipeline.color_trace_apply(fg, bg, sp, step.op, cfg, cbg)
			traces[i] = trace
			local original = step.original and original_ops[step.original]
			local pos = original and original._cf_source
			if not write and not opts.pending and pos then
				local key = table.concat({ pos.line or 0, pos.col or 0, pos.end_line or 0, pos.end_col or 0 }, ":")
				local record = cached_sources[key]
				if record and record.trace.before == trace.before and record.trace.after == trace.after then traces[i] = record.trace end
			end
		end
		local spec = copy(working)
		spec.pipeline = ops
		final = setup._build_style(spec, nil, nil)
		if write then
			-- Preserve the existing runtime Style edits; only the colour channels
			-- are controlled by this editor.
			local preview = copy(not opts.reset and type(state.current) == "table" and state.current or final)
			for _, field in ipairs(fields) do preview[field] = final[field] end
			runtime._picker_set_style(opts.edit.target, preview)
			previewed = true
		end
	end
	compute(false)
	local function maxrow() return starts[editor.col] ~= nil and (#columns[editor.col] + 1) or 0 end
	local function cleanup(restore)
		if closed then return end
		closed = true
		active = nil
		if resize_group then api.nvim_del_augroup_by_id(resize_group); resize_group = nil end
		if suspended then menu.close() end
		if float then float:close() end
		if restore and previewed and require("cf.theme").current() == theme then runtime._picker_restore_style(opts.edit.target, state) end
		if restore_lineblend then lineblend.activate() end
	end
	function editor.cancel(back)
		cleanup(true)
		if back then opts.on_back() end
	end
	function editor.accept()
		if not valid() then cleanup(false); return end
		local changes = delta()
		opts.on_commit(changes)
		cleanup(changes == nil and not opts.pending)
		opts.on_back()
	end
	local function mutate(fn)
		if not valid() then cleanup(false); return end
		local old = vim.deepcopy(draft)
		local ok, err = pcall(function() fn(); compute(true) end)
		if not ok then
			draft = old; editor.draft = draft
			compute(false)
			api.nvim_echo({ { tostring(err), "ErrorMsg" } }, false, {})
		end
		editor.row = math.min(editor.row, maxrow())
		render()
	end
	local function step_index() return columns[editor.col][editor.row] end
	function editor.adjust(amount)
		local index = step_index()
		if not index then return end
		mutate(function()
			local step = draft.steps[index]
			local opcode = step.op[1]
			local value = step.op[3] + (opcode == 7 and amount / 100 or amount)
			if opcode == 7 then
				value = math.max(0.01, math.min(100, math.floor(value * 100 + 0.5) / 100))
			elseif opcode == 3 then
				value = math.max(-100, math.min(100, value))
			elseif opcode == 6 then
				value = math.max(-180, math.min(180, value))
			elseif opcode == 1 or opcode == 2 or opcode == 4 or opcode == 5 then
				value = math.max(0, math.min(100, value))
			end
			step.op[3], step.value = value, value
			if step.original and original_ops[step.original][3] == value then step.value = nil end
		end)
	end
	function editor.delete()
		local index = step_index()
		if index then mutate(function() table.remove(draft.steps, index) end) end
	end
	local function swatch(name, value)
		if value then
			local rgb = color.to_rgb_hex(value)
			api.nvim_set_hl(namespace, name, { fg = rgb, bg = rgb })
		else
			api.nvim_set_hl(namespace, name, { link = "Comment" })
		end
		return name
	end

	local active_cell_hl = "Visual"
	local function resume()
		if closed then return end
		suspended = false
		if not valid() then cleanup(false); return end
		show()
	end
	local function select_menu(title, items, chosen, palette_mode)
		suspended = true
		float:hide()
		local labels = {}
		for i, item in ipairs(items) do labels[i] = palette_mode and ("██ " .. item.label) or item end
		local handle = menu.open({ title = title, items = labels, on_back = resume, on_cancel = resume,
			on_select = function(_, i) if valid() then chosen(items[i]) end; resume() end,
			render_item = palette_mode and function(i, selected, width)
				return { { col = 0, text = string.rep(" ", width), hl = selected and "Visual" or "NormalFloat" },
					{ col = 1, text = "██", hl = swatch("CFPalette" .. i, items[i].value) },
					{ col = 4, text = items[i].label, hl = selected and "Visual" or "NormalFloat" } }
			end or nil,
		})
		api.nvim_win_set_hl_ns(handle.float:win(), namespace)
	end
	local function choose_color(callback)
		if #palette == 0 then api.nvim_echo({ { "ChromaFlow: active color.cf has no colours", "WarningMsg" } }, false, {}); return end
		select_menu(" Palette: " .. channels[editor.col]:upper() .. " ", palette, callback, true)
	end
	function editor.insert()
		if starts[editor.col] == nil then return end
		-- Insert before the selected operation; at 'new', after this channel's
		-- last operation. Never regroup the interleaved global pipeline.
		local list = columns[editor.col]
		local at = step_index() or (#list > 0 and (list[#list] + 1) or (#draft.steps + 1))
		select_menu(" New manipulation ", operations, function(name)
			local opcode
			for i, value in ipairs(operations) do if value == name then opcode = i end end
			local function add(item)
				mutate(function()
					local op = pipeline[name][channels[editor.col]](defaults[opcode], item and item.value)
					table.insert(draft.steps, at, { op = op, color_expr = item and item.expr })
				end)
			end
			if opcode == 1 then
				-- Defer opening the second selection until the first has resumed.
				vim.schedule(function() if not closed then choose_color(add) end end)
			else add() end
		end)
	end
	function editor.enter()
		if editor.row == 0 then
			choose_color(function(item) mutate(function() draft.fields[fields[editor.col]] = item end) end)
		elseif editor.row == #columns[editor.col] + 1 then editor.insert()
		else
			local index = step_index()
			if index and draft.steps[index].op[1] == 1 then
				choose_color(function(item) mutate(function() draft.steps[index].op[4] = item.value; draft.steps[index].color_expr = item.expr end) end)
			end
		end
	end
	local function fit(text, width)
		return vim.fn.strcharpart(text, 0, math.max(0, width))
	end
	render = function()
		if not float or closed or suspended then return end
		local width = math.max(12, math.min(112, vim.o.columns - 4))
		local height = math.max(7, math.min(18, vim.o.lines - 4))
		local visible = math.max(1, math.min(5, math.floor((width - 6) / 18)))
		local cell = math.floor((width - 6) / visible)
		local first_col = math.max(1, math.min(6 - visible, editor.col - visible + 1))
		local count = height - 6
		local first_row = math.max(1, editor.row - count + 1)
		float:configure({ width = width, height = height, row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
			col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)) })
		local lines = {}
		for i = 1, height do lines[i] = {} end
		for j = first_col, first_col + visible - 1 do
			local x = 6 + (j - first_col) * cell
			local enabled = starts[j] ~= nil
			local normal = enabled and "NormalFloat" or "Comment"
			lines[1][#lines[1] + 1] = { col = x, text = j .. " " .. channels[j]:upper(), hl = normal }
			local field = fields[j]
			local expression = not opts.reset and source.fields[field] or nil
			local raw = expression and (expression:match('^require%("cf.color"%).to_cterm%((.*)%)$') or expression)
			local known = raw and by_expr[raw]
			local label = draft.fields[field] and draft.fields[field].label or (known and known.label) or expression or display(starts[j])
			local origin = not draft.fields[field] and not expression and enabled and "inherited" or ""
			if j >= 4 and working[field] == nil and enabled then origin = j == 4 and "[from FG]" or "[from BG]" end
			local selected = editor.col == j
			local function cell_line(line, row, text, before, after)
				local highlight = selected and editor.row == row and active_cell_hl or normal
				if before ~= nil then
					lines[line][#lines[line] + 1] = { col = x, text = "██", hl = swatch("CFPipeIn" .. line .. "_" .. j, before) }
					lines[line][#lines[line] + 1] = { col = x + 2, text = "██", hl = swatch("CFPipeOut" .. line .. "_" .. j, after) }
					local body = " " .. fit(text, cell - 5)
					local padding = cell - 4 - vim.fn.strdisplaywidth(body)
					if padding > 0 then body = body .. string.rep(" ", padding) end
					lines[line][#lines[line] + 1] = { col = x + 4, text = body, hl = highlight }
				else
					local body = fit(text, cell)
					local padding = cell - vim.fn.strdisplaywidth(body)
					if padding > 0 then body = body .. string.rep(" ", padding) end
					lines[line][#lines[line] + 1] = { col = x, text = body, hl = highlight }
				end
			end
			cell_line(2, 0, label, starts[j], starts[j])
			local origin_hl = selected and editor.row == 0 and active_cell_hl or "Comment"
			local origin_text = fit(origin, cell)
			local origin_padding = cell - vim.fn.strdisplaywidth(origin_text)
			if origin_padding > 0 then origin_text = origin_text .. string.rep(" ", origin_padding) end
			lines[3][#lines[3] + 1] = { col = x, text = origin_text, hl = origin_hl }
			for k = 1, count do
				local row = first_row + k - 1
				local index = columns[j][row]
				local text, before, after = "", nil, nil
				if not enabled then text = ""
				elseif index then
					local op, trace = draft.steps[index].op, traces[index]
					text = operations[op[1]] .. " " .. tostring(op[1] == 7 and math.floor(op[3] * 100 + 0.5) or op[3])
					before, after = trace.before, trace.after
				elseif row == #columns[j] + 1 then text = "new" end
				cell_line(k + 4, row, text, before, after)
			end
		end
		lines[height - 1] = { { col = 0, text = fit("Enter Farbe/Neu · n Einfügen · d Löschen · +/- Wert · Alt +/- 10", width), hl = "Comment" } }
		lines[height] = { { col = 0, text = fit("a Übernehmen · BS Zurück/verwerfen · q/Esc Verwerfen · 1–5 Kanal", width), hl = "Comment" } }
		float:set_lines(1, lines)
		if float:is_open() then api.nvim_win_set_cursor(float:win(), { editor.row == 0 and 2 or (editor.row - first_row + 5), 0 }) end
	end
	show = function()
		if not float then float = Float.new({ relative = "editor", border = "rounded", title = " Pipeline: " .. opts.edit.name .. " ",
			width = 1, height = 1, enter = true, focusable = true, cursor_hl = "NormalFloat" }) end
		render()
		float:open()
		api.nvim_win_set_hl_ns(float:win(), namespace)
		local mapopts = { buffer = float:buf(), nowait = true, silent = true }
		local function map(keys, fn)
			for _, key in ipairs(type(keys) == "table" and keys or { keys }) do
				vim.keymap.set("n", key, function() if not closed and valid() then fn() elseif not closed then cleanup(false) end end, mapopts)
			end
		end
		local function move(dr, dc)
			editor.col = ((editor.col - 1 + dc) % 5) + 1
			editor.row = math.max(0, math.min(maxrow(), editor.row + dr))
			render()
		end
		map({ "j", "<Down>" }, function() move(1, 0) end)
		map({ "k", "<Up>" }, function() move(-1, 0) end)
		map({ "h", "<Left>" }, function() move(0, -1) end)
		map({ "l", "<Right>" }, function() move(0, 1) end)
		for i = 1, 5 do map(tostring(i), function() editor.col = i; editor.row = math.min(editor.row, maxrow()); render() end) end
		map("+", function() editor.adjust(1) end); map("-", function() editor.adjust(-1) end)
		map("<M-+>", function() editor.adjust(10) end); map("<M-->", function() editor.adjust(-10) end)
		map("n", editor.insert); map("d", editor.delete); map("<CR>", editor.enter)
		map("a", editor.accept); map("<BS>", function() editor.cancel(true) end)
		map({ "q", "<Esc>" }, function() editor.cancel(false) end)
		render()
	end
	active = editor
	if restore_lineblend then lineblend.stop() end
	local ok, err = pcall(show)
	if not ok then cleanup(true); error(err) end
	resize_group = api.nvim_create_augroup("cf_picker_pipeline_resize", { clear = true })
	api.nvim_create_autocmd("VimResized", { callback = function() if not closed then render() end end, group = resize_group })
	return editor
end

return M
