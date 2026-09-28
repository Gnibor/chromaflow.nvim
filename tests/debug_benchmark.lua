-- ChromaFlow debug-on-view benchmark.
-- Decomposes the one-file debug seed path without changing production APIs.
-- Defaults: 100 samples x 10 calls.
--
-- Run from Neovim:
--   :lua dofile(vim.api.nvim_get_runtime_file("tests/debug_benchmark.lua", false)[1]).run()
-- Optional:
--   :lua dofile(vim.api.nvim_get_runtime_file("tests/debug_benchmark.lua", false)[1]).run({ count = 100, batch = 10 })

local function load_benchmark()
	local source = debug.getinfo(1, "S").source
	if type(source) == "string" and source:sub(1, 1) == "@" then
		local here = vim.fs.dirname(vim.fs.normalize(source:sub(2)))
		local sibling = vim.fs.joinpath(here, "benchmark.lua")
		local chunk = loadfile(sibling)
		if chunk then return chunk() end
	end
	return require("tools.benchmark")
end

local benchmark = load_benchmark()
local diagnostic = require("cf.diagnostic")
local colortrace = require("cf.colortrace")
local hl = require("cf.hl.setup")
local theme = require("cf.theme")

local M = {}

local function opts(base, extra)
	local out = {
		count = base.count or 100,
		batch = base.batch or 10,
		warmup = base.warmup == nil and 25 or base.warmup,
	}
	if extra then
		for k, v in pairs(extra) do out[k] = v end
	end
	return out
end

local function bench(base, name, fn, extra)
	return benchmark.bench(name, fn, opts(base, extra))
end

local function find_upvalue(root, wanted)
	local seen = {}
	local function walk(fn)
		if type(fn) ~= "function" or seen[fn] then return nil end
		seen[fn] = true
		for i = 1, 200 do
			local name, value = debug.getupvalue(fn, i)
			if not name then break end
			if name == wanted then return value, fn, i end
			if type(value) == "function" then
				local found, owner, index = walk(value)
				if found ~= nil then return found, owner, index end
			end
		end
		return nil
	end
	local value, owner, index = walk(root)
	if value == nil then error("debug_benchmark: missing upvalue '" .. wanted .. "'", 2) end
	return value, owner, index
end

local function normalize(path)
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function pick_module()
	local current = theme.current()
	assert(current and type(current.module_files) == "table", "debug_benchmark: load a ChromaFlow theme first")
	local current_path = normalize(vim.api.nvim_buf_get_name(0))
	for i = 1, #current.module_files do
		if normalize(current.module_files[i].path) == current_path then
			return current.module_files[i]
		end
	end
	return current.module_files[1]
end

function M.run(user_opts)
	user_opts = user_opts or {}
	local file = pick_module()
	assert(file, "debug_benchmark: current theme has no module files")

	local old_buf = vim.api.nvim_get_current_buf()
	local old_policy = diagnostic.policy()
	local path = normalize(file.path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	vim.api.nvim_win_set_buf(0, buf)

	local execute = find_upvalue(theme.debug_file, "execute")

	-- build_source_ranges is not captured by _source_begin. It lives behind the
	-- debug pipeline wrappers: fg/bg/sp -> take_pipeline_source ->
	-- source_context_ranges -> build_source_ranges. Enable those wrappers only
	-- long enough to obtain the real closure, then restore the configured state.
	colortrace.set_debug(true)
	local debug_mix_fg = assert(hl.mix and hl.mix.fg, "debug_benchmark: missing debug mix.fg wrapper")
	local build_source_ranges = find_upvalue(debug_mix_fg, "build_source_ranges")
	local source_file_signature = find_upvalue(build_source_ranges, "source_file_signature")
	local source_range_cache = find_upvalue(build_source_ranges, "source_range_cache")
	colortrace.set_debug(old_policy.debug == true)

	local function clear_range_cache()
		source_range_cache[path] = nil
	end

	local function raw_execute()
		local _, err = execute(path, file.name, true)
		assert(not err, err)
	end

	benchmark.start()

	local ok, err = xpcall(function()
		bench(user_opts, "00 source | fs signature", function()
			source_file_signature(path)
		end)

		-- Cached lookup is the steady-state cost after the first source parse.
		build_source_ranges(path)
		bench(user_opts, "01 source ranges | cached", function()
			build_source_ranges(path)
		end)

		-- Force only the source-range cache cold. This includes fs signature,
		-- reading the one .cf file, Tree-sitter parse and range collection.
		bench(user_opts, "01 source ranges | cold read + parse + collect", function()
			clear_range_cache()
			build_source_ranges(path)
		end, { warmup = 5 })

		-- Baseline for executing exactly this module without debug instrumentation.
		diagnostic.configure(vim.tbl_extend("force", old_policy, { debug = false }))
		colortrace.set_debug(false)
		bench(user_opts, "02 execute one module | debug OFF", function()
			diagnostic.clear_pending()
			raw_execute()
		end)

		-- Debug ON with a warm source-range cache isolates operation source capture,
		-- per-operation debug_apply/trace construction and diagnostic production.
		diagnostic.configure(vim.tbl_extend("force", old_policy, { debug = true }))
		colortrace.set_debug(true)
		build_source_ranges(path)
		bench(user_opts, "03 execute one module | debug ON ranges warm", function()
			diagnostic.clear_pending()
			raw_execute()
		end)

		-- Same path with the range cache deliberately cold on every call.
		bench(user_opts, "03 execute one module | debug ON ranges cold", function()
			diagnostic.clear_pending()
			clear_range_cache()
			raw_execute()
		end, { warmup = 5 })

		bench(user_opts, "04 theme.debug_file | producer only", function()
			diagnostic.clear_pending()
			theme.debug_file(path)
		end)

		bench(user_opts, "04 theme.debug_file | producer + flush_buffer", function()
			diagnostic.clear_pending()
			theme.debug_file(path)
			diagnostic.flush_buffer(buf)
		end)

		-- Seed once, then measure only the real diagnostic publication cost.
		diagnostic.clear_pending()
		theme.debug_file(path)
		bench(user_opts, "05 diagnostic | flush_buffer seeded", function()
			diagnostic.flush_buffer(buf)
		end)
	end, debug.traceback)

	diagnostic.clear_pending()
	diagnostic.clear_rendered(buf)
	diagnostic.configure(old_policy)
	colortrace.set_debug(old_policy.debug == true)
	vim.api.nvim_win_set_buf(0, old_buf)

	if not ok then
		-- Do not leave a benchmark session armed after a failed probe. stop() also
		-- exposes whatever completed before the failure in the normal result buffer.
		benchmark.stop()
		error(err, 0)
	end

	benchmark.stop()
end

return M
