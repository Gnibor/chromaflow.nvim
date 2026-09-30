local M = {}

local config = require("cf.config")
local diagnostic = require("cf.diagnostic")
local lineblend = require("cf.fn.lineblend")
local menu = require("cf.menu")
local resolver = require("cf.hl.resolver")
local runtime = require("cf.hl.runtime")
local theme = require("cf.theme")
local usr_cmd = require("cf.usr_cmd")
local watcher = require("cf.watcher")

local api = vim.api
local startup_autocmd


-- Small public utility namespace. Keep heavy subsystems out of the root API,
-- but expose tools that are intentionally usable directly by users/benchmarks.
M.fn = {
	lineblend = lineblend,
}

-- Backend functions close over runtime-owned caches, so this only needs to be
-- wired once for the Neovim session.
resolver.setup_backend(runtime.backend())

local function report_error(err)
	vim.notify("cf.nvim: " .. tostring(err), vim.log.levels.ERROR)
end

local function load_theme()
	if not config.theme_path then
		return nil
	end

	-- One compile/apply cycle owns one pending diagnostic set. Rendering is delayed
	-- until the complete theme operation has finished, keeping diagnostics out of
	-- parser/resolver hot paths. Always flush before propagating a fatal error so
	-- recoverable records produced earlier in the cycle are not lost.
	diagnostic.clear_pending()
	local ok, result = xpcall(function()
		return theme.load(config.theme_path)
	end, debug.traceback)
	diagnostic.flush()
	if not ok then
		error(result, 0)
	end
	return result
end

local function start_watcher(compiled)
	watcher.stop()
	if not config.watch or not config.theme_path or not compiled then
		return
	end

	local ok, err = watcher.start(
		config.theme_path,
		compiled.default,
		compiled.requested_active,
		function(_batch)
			-- A watched edit is the same operation as an explicit reload. Keep one
			-- reload path so theme, watcher and LineBlend refresh policy cannot drift.
			local loaded_ok, result = pcall(M.reload)
			if not loaded_ok then
				report_error(result)
			end
		end,
		function(watch_err, path, scope)
			report_error(("watcher %s error at %s: %s"):format(tostring(scope), tostring(path), tostring(watch_err)))
		end
	)

	if not ok then
		report_error(err)
	end
end

local function load_and_watch()
	local compiled
	if config.theme_path then
		compiled = load_theme()
	end
	start_watcher(compiled)
	return compiled
end

local function apply_lineblend_config()
	if config.lineblend.autostart then
		-- LineBlend owns its own activation/setup refresh. Do not hard-reload its
		-- session caches from ChromaFlow startup.
		lineblend.setup({ blend = config.lineblend.blend })
		return
	end

	-- Keep the configured blend value for a later :LineBlendToggle without
	-- installing/activating LineBlend just to store the option.
	lineblend.set_blend(config.lineblend.blend)
	if lineblend.is_active() then
		lineblend.stop()
	end
end

local function cancel_startup_autocmd()
	if startup_autocmd then
		pcall(api.nvim_del_autocmd, startup_autocmd)
		startup_autocmd = nil
	end
end

local function defer_initial_load_until_vimenter()
	if startup_autocmd then
		return
	end

	startup_autocmd = api.nvim_create_autocmd("VimEnter", {
		once = true,
		callback = function()
			startup_autocmd = nil

			-- Run after every VimEnter callback. Plugins that create their highlight
			-- groups on VimEnter therefore finish before CF compiles/applies the theme.
			vim.schedule(function()
				local ok, err = pcall(load_and_watch)
				if not ok then
					report_error(err)
				end
			end)
		end,
	})
end

function M.set_theme(name, set_default)
	assert(vim.v.vim_did_enter ~= 0, "cf.nvim: set_theme() is only available after VimEnter")
	assert(config.theme_path, "cf.nvim: theme_path is not configured")
	assert(type(name) == "string" and name ~= "", "cf.nvim: theme name must be a non-empty string")
	assert(set_default == nil or type(set_default) == "boolean", "cf.nvim: set_default must be boolean or nil")

	-- Validate before touching the running watcher. A typo must not disable live
	-- reloads just because theme.select() would reject it afterwards.
	local available = theme.available(config.theme_path)
	local found = false
	for i = 1, #available do
		if available[i] == name then
			found = true
			break
		end
	end
	assert(found, "cf.nvim: unknown theme '" .. name .. "'")

	-- Stop before writing .cf-theme so our own selection change cannot come back
	-- through the fs watcher as a second reload 250 ms later.
	watcher.stop()
	local ok, compiled_or_err = xpcall(function()
		theme.select(config.theme_path, name, set_default == true)
		local compiled = load_and_watch()
		lineblend.refresh()
		return compiled
	end, debug.traceback)

	if not ok then
		-- A failed selection/reload must not silently disable live watching. The
		-- last successfully applied theme is still the best available scope.
		start_watcher(theme.current())
		error(compiled_or_err, 0)
	end
	return compiled_or_err
end

function M.set_default_theme(name)
	assert(vim.v.vim_did_enter ~= 0, "cf.nvim: set_default_theme() is only available after VimEnter")
	assert(config.theme_path, "cf.nvim: theme_path is not configured")
	assert(type(name) == "string" and name ~= "", "cf.nvim: theme name must be a non-empty string")

	-- Stop before writing .cf-theme so our own default-only change cannot come
	-- back through the fs watcher as a second reload 250 ms later.
	watcher.stop()
	local ok, default_or_err, active_name = xpcall(function()
		local default_name, selected_active = theme.set_default(config.theme_path, name)
		load_and_watch()
		return default_name, selected_active
	end, debug.traceback)

	if not ok then
		-- Keep the previous successful watcher scope alive if changing the
		-- default or the following reload fails.
		start_watcher(theme.current())
		error(default_or_err, 0)
	end
	return default_or_err, active_name
end

function M.theme_menu()
	assert(vim.v.vim_did_enter ~= 0, "cf.nvim: theme_menu() is only available after VimEnter")
	assert(config.theme_path, "cf.nvim: theme_path is not configured")

	local available = theme.available(config.theme_path)
	assert(#available > 0, "cf.nvim: no themes available")
	local _, active = theme.selection(config.theme_path)
	local selected = 1
	for i = 1, #available do
		if available[i] == active then
			selected = i
			break
		end
	end

	return menu.open({
		title = " ChromaFlow Themes ",
		items = available,
		selected = selected,
		on_select = function(name)
			M.set_theme(name, false)
		end,
		on_default = function(name)
			M.set_default_theme(name)
		end,
	})
end

function M.setup(opts)
	config.setup(opts)
	local diagnostic_ok, diagnostic_err = diagnostic.configure(config.diagnostic)
	assert(diagnostic_ok, diagnostic_err)

	local picker = package.loaded["cf.picker"]
	if config.picker then
		require("cf.picker").start()
	elseif picker then
		picker.stop()
	end

	local colortrace = package.loaded["cf.colortrace"]
	if config.diagnostic.color_trace then
		require("cf.colortrace").set_enabled(true)
	elseif colortrace then
		colortrace.set_enabled(false)
	end

	local colortrace_view = package.loaded["cf.colortrace_view"]
	if config.diagnostic.color_trace then
		require("cf.colortrace_view").start()
	elseif colortrace_view then
		colortrace_view.stop()
	end

	usr_cmd.setup({
		reload = M.reload,
		save = M.save,
		set_theme = M.set_theme,
		theme_menu = M.theme_menu,
	})
	apply_lineblend_config()

	if vim.v.vim_did_enter == 0 then
		-- No theme compile/apply before VimEnter. Keep setup cheap during startup
		-- and let the final configured state win if setup() is called again.
		watcher.stop()
		defer_initial_load_until_vimenter()
		return M
	end

	cancel_startup_autocmd()
	load_and_watch()
	return M
end

function M.save()
	assert(vim.v.vim_did_enter ~= 0, "cf.nvim: save() is only available after VimEnter")
	assert(config.picker, "cf.nvim: save() requires picker=true")
	assert(config.theme_path, "cf.nvim: theme_path is not configured")

	-- Build and validate the complete write plan before touching the watcher or
	-- filesystem. A bad/unsupported edit therefore cannot leave half a save.
	local save = require("cf.save")
	local plan = save.plan()
	if #plan.files == 0 then
		return 0, 0
	end

	-- Just like theme selection, do not let our own writes return through the
	-- fs watcher as a delayed second reload.
	watcher.stop()
	local ok, count_or_err, files = xpcall(function()
		save.write(plan)
		local compiled = load_and_watch()
		lineblend.refresh()
		return plan.count, #plan.files, compiled
	end, debug.traceback)

	if not ok then
		-- Keep live watching useful even if the post-write reload fails. The old
		-- compiled theme is still the best available watcher scope at that point.
		start_watcher(theme.current())
		error(count_or_err, 0)
	end

	return count_or_err, files
end

function M.reload()
	assert(vim.v.vim_did_enter ~= 0, "cf.nvim: reload() is only available after VimEnter")
	assert(config.theme_path, "cf.nvim: theme_path is not configured")

	local compiled = load_theme()
	if watcher.is_running() then
		watcher.set_themes(compiled.default, compiled.requested_active)
	end

	-- CF never hard-reloads LineBlend. Its generated-group/session caches belong
	-- to the Neovim session; a normal cached refresh is sufficient here. Passing
	-- nil is intentional: unlike some languages, Lua treats numeric 0 as true.
	lineblend.refresh()

	return compiled
end

function M.stop_watcher()
	watcher.stop()
end

return M
