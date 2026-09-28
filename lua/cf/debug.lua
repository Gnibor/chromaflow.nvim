local M = {}

local api = vim.api
local diagnostic = require("cf.diagnostic")
local theme = require("cf.theme")
local colortrace = require("cf.colortrace")

local started = false
local group
local mapped = {}
local seeded_theme = {}

local function is_cf_buffer(bufnr)
	if not api.nvim_buf_is_valid(bufnr) or not api.nvim_buf_is_loaded(bufnr) then
		return false
	end
	local name = api.nvim_buf_get_name(bufnr)
	return name ~= "" and name:sub(-3) == ".cf"
end

local function map_buffer(bufnr)
	if mapped[bufnr] or not is_cf_buffer(bufnr) then
		return
	end
	vim.keymap.set("n", "H", diagnostic.open_float, {
		buffer = bufnr,
		silent = true,
		desc = "ChromaFlow debug diagnostic",
	})
	mapped[bufnr] = true
end

local function seed_buffer(bufnr)
	if not started or not is_cf_buffer(bufnr) then
		return false
	end
	if vim.fn.bufwinid(bufnr) == -1 then
		return false
	end

	local compiled = theme.current()
	if not compiled or seeded_theme[bufnr] == compiled then
		return false
	end

	local path = api.nvim_buf_get_name(bufnr)
	diagnostic.clear_pending()

	-- Re-execute the module so non-colour authoring diagnostics are refreshed too.
	-- When picker owns a valid source trace, suppress only the expensive colour
	-- retrace and emit that immutable cached trace after the module replay.
	local reuse_token = colortrace._reuse_begin(path, compiled)
	local ok, result = xpcall(function()
		return theme.debug_file(path)
	end, debug.traceback)
	if reuse_token then
		colortrace._reuse_end(reuse_token)
	end
	if not ok then
		diagnostic.clear_pending()
		error(result, 0)
	end

	if result then
		if reuse_token then
			colortrace.emit_file(path, compiled)
		end
		diagnostic.flush_buffer(bufnr)
		seeded_theme[bufnr] = compiled
		return true
	end

	diagnostic.clear_pending()
	return false
end

local function schedule_seed(bufnr)
	vim.schedule(function()
		if not started then return end
		seed_buffer(bufnr)
	end)
end

function M.start()
	colortrace.set_debug(true)
	if started then
		return M
	end
	started = true

	group = api.nvim_create_augroup("cf.nvim.debug", { clear = true })
	api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
		group = group,
		pattern = "*.cf",
		callback = function(args)
			map_buffer(args.buf)
		end,
	})
	api.nvim_create_autocmd("BufWinEnter", {
		group = group,
		pattern = "*.cf",
		callback = function(args)
			map_buffer(args.buf)
			schedule_seed(args.buf)
		end,
	})
	api.nvim_create_autocmd("BufWipeout", {
		group = group,
		pattern = "*.cf",
		callback = function(args)
			mapped[args.buf] = nil
			seeded_theme[args.buf] = nil
		end,
	})
	api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = function()
			-- Do not retain compiled-theme tables across reloads. A buffer is seeded
			-- again only if it later re-enters a window and needs on-view diagnostics.
			seeded_theme = {}
		end,
	})

	for _, bufnr in ipairs(api.nvim_list_bufs()) do
		map_buffer(bufnr)
	end
	return M
end

function M.stop()
	colortrace.set_debug(false)
	if not started then
		return M
	end
	started = false

	if group then
		pcall(api.nvim_del_augroup_by_id, group)
		group = nil
	end
	for bufnr in pairs(mapped) do
		if api.nvim_buf_is_valid(bufnr) then
			pcall(vim.keymap.del, "n", "H", { buffer = bufnr })
		end
	end
	mapped = {}
	seeded_theme = {}
	return M
end

function M.is_active()
	return started
end

-- Internal test/benchmark hook; production uses BufWinEnter.
M._seed = seed_buffer

return M
