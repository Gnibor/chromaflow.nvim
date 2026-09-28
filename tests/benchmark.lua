local M = {}

local unpack_args = table.unpack or rawget(_G, "unpack")

local session = {
	active = false,
	results = {},
	started_at = nil,
}

-- ============================================================================
-- Time / statistics
-- ============================================================================

local function now()
	return vim.uv.hrtime()
end

local function percentile(sorted, p)
	if #sorted == 0 then
		return 0
	end

	local index = math.ceil(#sorted * p)
	index = math.max(1, math.min(index, #sorted))

	return sorted[index]
end

local function stats(times)
	local sorted = vim.deepcopy(times)
	table.sort(sorted)

	local sum = 0

	for _, value in ipairs(sorted) do
		sum = sum + value
	end

	return {
		count = #sorted,
		min = sorted[1] or 0,
		avg = #sorted > 0 and sum / #sorted or 0,
		p50 = percentile(sorted, 0.50),
		p90 = percentile(sorted, 0.90),
		p95 = percentile(sorted, 0.95),
		p99 = percentile(sorted, 0.99),
		max = sorted[#sorted] or 0,
	}
end

-- `batch` keeps timer boundaries out of microbenchmarks: one sample measures
-- several real calls and stores their average duration. `count` remains the
-- number of statistical samples, so percentiles stay meaningful.
local function measure(count, batch, fn)
	local times = {}

	for i = 1, count do
		local start = now()

		for _ = 1, batch do
			fn()
		end

		times[i] = (now() - start) / (1000 * batch)
	end

	return stats(times)
end

-- ============================================================================
-- Output
-- ============================================================================

local function format_time(value)
	if value < 1000 then
		return string.format("%.3f µs", value)

	elseif value < 1000000 then
		return string.format("%.3f ms", value / 1000)

	else
		return string.format("%.3f s", value / 1000000)
	end
end

local function format_result(result)
	local count = result.batch > 1
		and string.format("%d samples × %d calls", result.count, result.batch)
		or tostring(result.count)

	return string.format(
		"%s\n"
			.. "  count : %s\n"
			.. "  min   : %s\n"
			.. "  avg   : %s\n"
			.. "  p50   : %s\n"
			.. "  p90   : %s\n"
			.. "  p95   : %s\n"
			.. "  p99   : %s\n"
			.. "  max   : %s",
		result.name,
		count,
		format_time(result.min),
		format_time(result.avg),
		format_time(result.p50),
		format_time(result.p90),
		format_time(result.p95),
		format_time(result.p99),
		format_time(result.max)
	)
end

function M.format(result)
	if result[1] ~= nil then
		local output = {}

		for _, item in ipairs(result) do
			output[#output + 1] = format_result(item)
		end

		return table.concat(output, "\n\n")
	end

	return format_result(result)
end

function M.print(result)
	print(M.format(result))
end

-- ============================================================================
-- Scratch buffer
-- ============================================================================

local function open_scratch(results)
	local lines = {
		"Module Benchmark",
		"================",
		"",
	}

	for index, result in ipairs(results) do
		local text = format_result(result)

		for line in text:gmatch("[^\n]+") do
			lines[#lines + 1] = line
		end

		if index < #results then
			lines[#lines + 1] = ""
		end
	end

	local buf = vim.api.nvim_create_buf(false, true)

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true
	vim.bo[buf].filetype = "benchmark"

	vim.api.nvim_buf_set_name(
		buf,
		"ModuleBenchmark://results"
	)

	vim.api.nvim_buf_set_lines(
		buf,
		0,
		-1,
		false,
		lines
	)

	vim.bo[buf].modifiable = false

	vim.cmd("new")

	vim.api.nvim_win_set_buf(
		0,
		buf
	)

	vim.bo[buf].modifiable = false
end

-- ============================================================================
-- Session
-- ============================================================================

function M.start()
	session.active = true
	session.results = {}
	session.started_at = now()

	vim.notify(
		"ModuleBenchmark session started",
		vim.log.levels.INFO
	)
end

function M.stop()
	if not session.active then
		vim.notify(
			"No ModuleBenchmark session active",
			vim.log.levels.WARN
		)

		return
	end

	session.active = false

	local results = session.results

	session.results = {}
	session.started_at = nil

	if #results == 0 then
		vim.notify(
			"ModuleBenchmark session contained no results",
			vim.log.levels.INFO
		)

		return
	end

	open_scratch(results)
end

function M.is_active()
	return session.active
end

local function output_results(results)
	if session.active then
		for _, result in ipairs(results) do
			session.results[#session.results + 1] = result
		end

		vim.notify(
			string.format(
				"Cached %d benchmark result%s",
				#results,
				#results == 1 and "" or "s"
			),
			vim.log.levels.INFO
		)

		return
	end

	M.print(results)
end

-- ============================================================================
-- Benchmark core
-- ============================================================================

local function prepare(opts)
	if opts.collect_gc ~= false then
		collectgarbage("collect")
	end

	if opts.setup then
		opts.setup()
	end
end

local function finish(opts)
	if opts.teardown then
		opts.teardown()
	end
end

function M.run(name, fn, opts)
	assert(
		type(fn) == "function",
		"benchmark.run(): fn must be a function"
	)

	opts = opts or {}

	local count = opts.count or 1000
	local warmup = opts.warmup or 25
	local batch = opts.batch or 1

	assert(
		type(count) == "number"
			and count > 0
			and count % 1 == 0,
		"benchmark.run(): count must be a positive integer"
	)

	assert(
		type(batch) == "number"
			and batch > 0
			and batch % 1 == 0,
		"benchmark.run(): batch must be a positive integer"
	)

	assert(
		type(warmup) == "number"
			and warmup >= 0
			and warmup % 1 == 0,
		"benchmark.run(): warmup must be a non-negative integer"
	)

	prepare(opts)

	for _ = 1, warmup do
		fn()
	end

	if opts.before then
		opts.before()
	end

	local result = measure(count, batch, fn)

	result.name = name or "benchmark"
	result.batch = batch

	if opts.after then
		opts.after()
	end

	finish(opts)

	return result
end

function M.bench(name, fn, opts)
	local result = M.run(name, fn, opts)

	output_results({ result })

	return result
end

function M.compare(tests, opts)
	assert(
		type(tests) == "table",
		"benchmark.compare(): tests must be a table"
	)

	local results = {}

	for index, test in ipairs(tests) do
		assert(
			type(test) == "table"
				and type(test.fn) == "function",
			"benchmark.compare(): each test needs fn"
		)

		local test_opts = vim.tbl_extend(
			"force",
			opts or {},
			test.opts or {}
		)

		results[#results + 1] = M.run(
			test.name or ("test_" .. index),
			test.fn,
			test_opts
		)
	end

	return results
end

function M.baseline(opts)
	return M.run(
		"baseline",
		function()
		end,
		opts
	)
end

-- ============================================================================
-- Argument handling
-- ============================================================================

local function pack(...)
	return {
		n = select("#", ...),
		...
	}
end

local function strip_quotes(value)
	return value
		:gsub('^["\']', "")
		:gsub('["\']$', "")
end

local function split_command(value)
	local result = {}
	local current = {}

	local depth = 0
	local quote = nil
	local escaped = false

	local function flush()
		if #current == 0 then
			return
		end

		result[#result + 1] = table.concat(current)
		current = {}
	end

	for i = 1, #value do
		local char = value:sub(i, i)

		if quote ~= nil then
			current[#current + 1] = char

			if escaped then
				escaped = false

			elseif char == "\\" then
				escaped = true

			elseif char == quote then
				quote = nil
			end

		else
			if char == '"' or char == "'" then
				quote = char
				current[#current + 1] = char

			elseif char == "("
				or char == "["
				or char == "{"
			then
				depth = depth + 1
				current[#current + 1] = char

			elseif char == ")"
				or char == "]"
				or char == "}"
			then
				depth = depth - 1
				current[#current + 1] = char

			elseif char:match("%s") and depth == 0 then
				flush()

			else
				current[#current + 1] = char
			end
		end
	end

	flush()

	return result
end

local function parse_call(value)
	local name, args = value:match(
		"^([%a_][%w_]*)%s*%((.*)%)$"
	)

	if name then
		return name, args
	end

	name = value:match(
		"^([%a_][%w_]*)$"
	)

	if name then
		return name, ""
	end

	return nil, nil
end

local function evaluate_args(value)
	if value == "" then
		return {
			n = 0,
		}
	end

	local loader, err = load(
		"return function() return "
			.. value
			.. " end"
	)

	if not loader then
		return nil, err
	end

	local ok, evaluator = pcall(loader)

	if not ok then
		return nil, evaluator
	end

	local args

	ok, args = pcall(function()
		return pack(evaluator())
	end)

	if not ok then
		return nil, args
	end

	return args
end

local function bind(fn, args)
	if args.n == 0 then
		return fn
	end

	local a = args[1]
	if args.n == 1 then
		return function()
			return fn(a)
		end
	end

	local b = args[2]
	if args.n == 2 then
		return function()
			return fn(a, b)
		end
	end

	local c = args[3]
	if args.n == 3 then
		return function()
			return fn(a, b, c)
		end
	end

	local d = args[4]
	if args.n == 4 then
		return function()
			return fn(a, b, c, d)
		end
	end

	-- Keep the LuaJIT 5.1-compatible fallback for uncommon wide calls.
	return function()
		return fn(
			unpack_args(
				args,
				1,
				args.n
			)
		)
	end
end

-- ============================================================================
-- Direct module call
-- ============================================================================

function M.call(
	name,
	module_name,
	function_name,
	opts,
	...
)
	assert(
		type(module_name) == "string",
		"benchmark.call(): module_name must be a string"
	)

	assert(
		type(function_name) == "string",
		"benchmark.call(): function_name must be a string"
	)

	local module = require(module_name)
	local fn = module[function_name]

	assert(
		type(fn) == "function",
		string.format(
			"benchmark.call(): %s.%s is not a function",
			module_name,
			function_name
		)
	)

	local args = pack(...)

	return M.run(
		name or (
			module_name
			.. "."
			.. function_name
		),
		bind(fn, args),
		opts
	)
end

-- ============================================================================
-- :ModuleBenchmark
-- ============================================================================

local function command_benchmark(parts, opts)
	if #parts < 3 then
		vim.notify(
			"Usage: :ModuleBenchmark <count> [batch=<n>] <module> <function(args...)> [...]",
			vim.log.levels.ERROR
		)

		return
	end

	local count = tonumber(
		table.remove(parts, 1)
	)

	if not count
		or count < 1
		or count % 1 ~= 0
	then
		vim.notify(
			"ModuleBenchmark: count must be a positive integer",
			vim.log.levels.ERROR
		)

		return
	end

	local batch = 1

	if parts[1] and parts[1]:match("^batch=") then
		local raw = parts[1]:match("^batch=(.*)$")
		local value = tonumber(raw)

		if
			not value
			or value < 1
			or value % 1 ~= 0
		then
			vim.notify(
				"ModuleBenchmark: batch must be a positive integer",
				vim.log.levels.ERROR
			)
			return
		end

		batch = value
		table.remove(parts, 1)
	end

	local module_name = strip_quotes(
		table.remove(parts, 1)
	)

	local ok, module = pcall(
		require,
		module_name
	)

	if not ok then
		vim.notify(
			"Could not load module: "
				.. module_name
				.. "\n"
				.. tostring(module),
			vim.log.levels.ERROR
		)

		return
	end

	local tests = {}

	for _, call in ipairs(parts) do
		local function_name, raw_args =
			parse_call(call)

		if not function_name then
			vim.notify(
				"Invalid function call: "
					.. call,
				vim.log.levels.WARN
			)

		else
			local fn = module[function_name]

			if type(fn) ~= "function" then
				vim.notify(
					string.format(
						"%s.%s is not a function",
						module_name,
						function_name
					),
					vim.log.levels.WARN
				)

			else
				local args, arg_error =
					evaluate_args(raw_args)

				if not args then
					vim.notify(
						string.format(
							"Invalid arguments for %s.%s:\n%s",
							module_name,
							function_name,
							tostring(arg_error)
						),
						vim.log.levels.ERROR
					)

				else
					tests[#tests + 1] = {
						name =
							module_name
							.. "."
							.. call,

						fn = bind(
							fn,
							args
						),
					}
				end
			end
		end
	end

	if #tests == 0 then
		return
	end

	local run_opts = vim.tbl_extend("force", {}, opts, {
		count = count,
		batch = batch,
		warmup = math.min(opts.warmup or 25, count),
	})
	local results = M.compare(tests, run_opts)

	output_results(results)
end

function M.setup(opts)
	opts = opts or {}

	vim.api.nvim_create_user_command(
		"ModuleBenchmark",
		function(cmd)
			local parts = split_command(
				cmd.args
			)

			if #parts == 1 then
				local action =
					parts[1]:lower()

				if action == "start" then
					M.start()
					return
				end

				if action == "stop" then
					M.stop()
					return
				end
			end

			command_benchmark(
				parts,
				opts
			)
		end,
		{
			nargs = "+",
			desc = "Benchmark Lua module functions",
		}
	)
end

return M
