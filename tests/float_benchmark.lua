local benchmark = require("tools.benchmark")
local Float = require("cf.fn.float")

local M = {}

local DEFAULT_COUNT = 100

local function new_float(height)
	return Float.new({
		width = 80,
		height = height or 24,
		relative = "editor",
		row = 1,
		col = 1,
		anchor = "NW",
		border = "none",
		title = "",
		focusable = false,
		zindex = 50,
	})
end

local function one_span(text, hl)
	return {
		{
			col = 0,
			text = text,
			hl = hl,
		},
	}
end

local function three_spans(a, b, c)
	return {
		{
			col = 0,
			text = a,
			hl = "Normal",
		},
		{
			col = 16,
			text = b,
			hl = "Comment",
		},
		{
			col = 32,
			text = c,
			hl = "Special",
		},
	}
end

local function four_spans(prefix)
	return {
		{
			col = 0,
			text = prefix .. "0",
			hl = "Normal",
		},
		{
			col = 12,
			text = prefix .. "1",
			hl = "Comment",
		},
		{
			col = 24,
			text = prefix .. "2",
			hl = "Special",
		},
		{
			col = 36,
			text = prefix .. "3",
			hl = "Constant",
		},
	}
end

local function line_set(prefix, count)
	local lines = {}

	for i = 1, count do
		lines[i] = {
			{
				col = 0,
				text = prefix .. i,
				hl = "Normal",
			},
			{
				col = 20,
				text = tostring(i),
				hl = "Comment",
			},
			{
				col = 32,
				text = "●",
				hl = "Special",
			},
		}
	end

	return lines
end

local function run_case(name, batch, make, count)
	local step, cleanup = make()

	local ok, result = pcall(
		benchmark.bench,
		name,
		step,
		{
			count = count or DEFAULT_COUNT,
			batch = batch,
			warmup = 25,
		}
	)

	cleanup()

	if not ok then
		error(result, 0)
	end

	return result
end

function M.run(opts)
	opts = opts or {}

	local count = opts.count or DEFAULT_COUNT

	benchmark.bench(
		"float baseline",
		function()
		end,
		{
			count = count,
			batch = 10000,
			warmup = 25,
		}
	)

	run_case(
		"float set_line same reference",
		10000,
		function()
			local float = new_float(8)
			local line = one_span("same", "Normal")

			float:set_line(1, line)
			float:open()

			return function()
				float:set_line(1, line)
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float set_line replace 1 span",
		100,
		function()
			local float = new_float(8)
			local a = one_span("alpha", "Normal")
			local b = one_span("bravo", "Comment")
			local use_b = false

			float:set_line(1, a)
			float:open()

			return function()
				use_b = not use_b
				float:set_line(1, use_b and b or a)
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float set_line replace 3 spans",
		50,
		function()
			local float = new_float(8)
			local a = three_spans("alpha", "beta", "gamma")
			local b = three_spans("delta", "epsilon", "zeta")
			local use_b = false

			float:set_line(1, a)
			float:open()

			return function()
				use_b = not use_b
				float:set_line(1, use_b and b or a)
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float set_line grow/shrink 1<->4 spans",
		50,
		function()
			local float = new_float(8)
			local one = one_span("one", "Normal")
			local four = four_spans("span-")
			local expanded = false

			float:set_line(1, one)
			float:open()

			return function()
				expanded = not expanded
				float:set_line(1, expanded and four or one)
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float flush one line / 3 spans",
		50,
		function()
			local float = new_float(8)
			local line = three_spans("alpha", "beta", "gamma")

			float:set_line(1, line)
			float:open()

			return function()
				float:flush(1)
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float set_lines replace 20x3 spans",
		5,
		function()
			local float = new_float(20)
			local a = line_set("a-", 20)
			local b = line_set("b-", 20)
			local use_b = false

			float:set_lines(1, a)
			float:open()

			return function()
				use_b = not use_b
				float:set_lines(1, use_b and b or a)
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float flush all 20x3 spans",
		5,
		function()
			local float = new_float(20)
			local lines = line_set("line-", 20)

			float:set_lines(1, lines)
			float:open()

			return function()
				float:flush()
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float configure unchanged",
		1000,
		function()
			local float = new_float(8)
			local config = {
				width = 80,
				height = 8,
				row = 1,
				col = 1,
			}

			float:open()
			float:configure(config)

			return function()
				float:configure(config)
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float configure changed",
		20,
		function()
			local float = new_float(8)
			local a = {
				row = 1,
				col = 1,
			}
			local b = {
				row = 2,
				col = 2,
			}
			local use_b = false

			float:open()
			float:configure(a)

			return function()
				use_b = not use_b
				float:configure(use_b and b or a)
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float clear_line + set_line / 3 spans",
		20,
		function()
			local float = new_float(8)
			local line = three_spans("alpha", "beta", "gamma")

			float:set_line(1, line)
			float:open()

			return function()
				float:clear_line(1)
				float:set_line(1, line)
			end, function()
				float:close()
			end
		end,
		count
	)

	run_case(
		"float hide + open",
		5,
		function()
			local float = new_float(8)
			local lines = line_set("line-", 8)

			float:set_lines(1, lines)
			float:open()

			return function()
				float:hide()
				float:open()
			end, function()
				float:close()
			end
		end,
		count
	)
end

return M
