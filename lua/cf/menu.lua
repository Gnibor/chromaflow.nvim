local M = {}

local Float = require("cf.fn.float")
local lineblend = require("cf.fn.lineblend")
local api = vim.api

local current

local function close(menu)
	if current == menu then
		current = nil
	end
	menu.float:close()
	if menu.restore_lineblend then
		lineblend.activate()
	end
end

function M.open(opts)
	assert(type(opts) == "table", "cf.menu.open: opts must be a table")
	assert(type(opts.items) == "table" and #opts.items > 0, "cf.menu.open: items must be a non-empty array")
	assert(opts.on_select == nil or type(opts.on_select) == "function", "cf.menu.open: on_select must be a function or nil")
	assert(opts.on_default == nil or type(opts.on_default) == "function", "cf.menu.open: on_default must be a function or nil")
	assert(opts.on_back == nil or type(opts.on_back) == "function", "cf.menu.open: on_back must be a function or nil")
	assert(opts.on_cancel == nil or type(opts.on_cancel) == "function", "cf.menu.open: on_cancel must be a function or nil")
	assert(opts.on_space == nil or type(opts.on_space) == "function", "cf.menu.open: on_space must be a function or nil")
	assert(opts.on_adjust == nil or type(opts.on_adjust) == "function", "cf.menu.open: on_adjust must be a function or nil")
	assert(opts.on_mark == nil or type(opts.on_mark) == "function", "cf.menu.open: on_mark must be a function or nil")

	if current then
		close(current)
	end

	local width = 1
	for i = 1, #opts.items do
		local item = opts.items[i]
		assert(type(item) == "string" and not item:find("\n", 1, true), "cf.menu.open: items must be single-line strings")
		width = math.max(width, vim.fn.strdisplaywidth(item))
	end

	width = math.min(width + 2, math.max(1, vim.o.columns - 4))
	local height = math.min(#opts.items, 11, math.max(1, vim.o.lines - 4))
	local row = math.max(0, math.floor((vim.o.lines - height - 2) / 2))
	local col = math.max(0, math.floor((vim.o.columns - width - 2) / 2))

	local function menu_line(index, selected)
		if opts.render_item then return opts.render_item(index, selected, width) end
		local text = " " .. opts.items[index]
		local padding = width - vim.fn.strdisplaywidth(text)
		if padding > 0 then
			text = text .. string.rep(" ", padding)
		end
		return { { col = 0, text = text, hl = selected and "Visual" or "NormalFloat" } }
	end

	local restore_lineblend = lineblend.is_active()
	if restore_lineblend then
		lineblend.stop()
	end

	local menu = {
		float = Float.new({
			width = width,
			height = height,
			relative = "editor",
			row = row,
			col = col,
			border = "rounded",
			title = opts.title or "",
			focusable = true,
			enter = true,
			cursor_hl = "Visual",
		}),
		items = opts.items,
		on_select = opts.on_select,
		on_default = opts.on_default,
		on_back = opts.on_back,
		on_cancel = opts.on_cancel,
		on_space = opts.on_space,
		restore_lineblend = restore_lineblend,
	}
	current = menu

	local selected = opts.selected or 1
	selected = math.max(1, math.min(#opts.items, selected))
	local first = 1

	local function render()
		local max_first = math.max(1, #menu.items - height + 1)
		first = math.max(1, math.min(max_first, selected - math.floor(height / 2)))
		local lines = {}
		for row_index = 1, height do
			local item_index = first + row_index - 1
			if item_index > #menu.items then break end
			lines[row_index] = menu_line(item_index, item_index == selected)
		end
		menu.float:set_lines(1, lines)
		if menu.float:is_open() then
			api.nvim_win_set_cursor(menu.float:win(), { selected - first + 1, 0 })
		end
	end

	function menu:set_item(index, item)
		assert(type(index) == "number" and index >= 1 and index <= #self.items, "cf.menu: item index out of range")
		assert(type(item) == "string" and not item:find("\n", 1, true), "cf.menu: item must be a single-line string")
		self.items[index] = item
		render()
	end

	render()
	menu.float:open()

	local buf = menu.float:buf()
	local win = menu.float:win()
	api.nvim_set_option_value("cursorline", false, { win = win })
	api.nvim_set_option_value("winhighlight", "Normal:NormalFloat,FloatBorder:FloatBorder", { win = win })
	api.nvim_win_set_cursor(win, { selected - first + 1, 0 })

	local moving = false
	local function move(delta)
		if current ~= menu or not menu.float:is_open() then return end
		local next_index = math.max(1, math.min(#menu.items, selected + delta))
		if next_index == selected then return end
		selected = next_index
		moving = true
		render()
		moving = false
	end

	api.nvim_create_autocmd("CursorMoved", {
		buffer = buf,
		callback = function()
			if moving or current ~= menu or not menu.float:is_open() then return end
			local row_index = api.nvim_win_get_cursor(menu.float:win())[1]
			local index = first + row_index - 1
			if index < 1 or index > #menu.items or index == selected then return end
			selected = index
		render()
		end,
	})

	local map_opts = { buffer = buf, nowait = true, silent = true }
	if opts.on_mark then
		local function mark(value)
			if current ~= menu or not menu.float:is_open() then return end
			opts.on_mark(menu.items[selected], selected, menu, value)
		end
		vim.keymap.set("n", "=", function() mark(true) end, map_opts)
		vim.keymap.set("n", "x", function() mark(false) end, map_opts)
	end
	local function cancel()
		if current ~= menu or not menu.float:is_open() then return end
		close(menu)
		if menu.on_cancel then
			menu.on_cancel()
		end
	end

	vim.keymap.set("n", "<Esc>", cancel, map_opts)
	vim.keymap.set("n", "q", cancel, map_opts)
	vim.keymap.set("n", "<BS>", function()
		if current ~= menu or not menu.float:is_open() then return end
		close(menu)
		if menu.on_back then
			menu.on_back()
		end
	end, map_opts)
	vim.keymap.set("n", "j", function() move(1) end, map_opts)
	vim.keymap.set("n", "<Down>", function() move(1) end, map_opts)
	vim.keymap.set("n", "k", function() move(-1) end, map_opts)
	vim.keymap.set("n", "<Up>", function() move(-1) end, map_opts)
	vim.keymap.set("n", "<Space>", function()
		if current ~= menu or not menu.float:is_open() or not menu.on_space then return end
		menu.on_space(menu.items[selected], selected, menu)
	end, map_opts)
	if opts.on_adjust then
		local function adjust(delta)
			if current ~= menu or not menu.float:is_open() then return end
			opts.on_adjust(menu.items[selected], selected, menu, delta)
		end
		vim.keymap.set("n", "-", function() adjust(-1) end, map_opts)
		vim.keymap.set("n", "+", function() adjust(1) end, map_opts)
		vim.keymap.set("n", "<M-->", function() adjust(-10) end, map_opts)
		vim.keymap.set("n", "<M-+>", function() adjust(10) end, map_opts)
	end
	vim.keymap.set("n", "<M-CR>", function()
		if current ~= menu or not menu.float:is_open() then return end
		if menu.on_default then
			menu.on_default(menu.items[selected], selected)
		end
	end, map_opts)
	vim.keymap.set("n", "<CR>", function()
		if current ~= menu or not menu.float:is_open() then return end
		local item = menu.items[selected]
		local index = selected
		close(menu)
		if menu.on_select then
			menu.on_select(item, index)
		end
	end, map_opts)

	return menu
end

function M.close()
	if current then
		close(current)
	end
end

return M
