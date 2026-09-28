local M = {}

local uv = vim.uv
local fs_join = vim.fs.joinpath
local fs_normalize = vim.fs.normalize

local DEBOUNCE_MS = 250
local RUNTIME_DIR = "runtime"

local root_handle
local theme_handles = {}
local runtime_handles = {}
local timer

local theme_path
local default_theme
local active_theme
local on_change
local on_error
local running = false

local pending
local refresh_runtime_handles

local function close_handle(handle)
	if not handle then
		return
	end

	pcall(handle.stop, handle)
	if not handle:is_closing() then
		handle:close()
	end
end

local function close_handles(handles)
	for i = 1, #handles do
		close_handle(handles[i])
	end
	for i = #handles, 1, -1 do
		handles[i] = nil
	end
end

local function report_error(err, path, scope)
	if on_error then
		on_error(err, path, scope)
	end
end

local function flush()
	if not running or not pending then
		return
	end

	-- Hand the whole deduplicated debounce window to the receiver at once.
	-- The table is keyed by path, so queueing repeated fs events for the same
	-- file does not allocate a second event object or require a second index.
	local batch = pending
	pending = nil
	on_change(batch)
end

local function arm_timer()
	if not timer then
		timer = uv.new_timer()
	end

	timer:stop()
	timer:start(DEBOUNCE_MS, 0, vim.schedule_wrap(flush))
end

local function queue(scope, filename, path)
	if not pending then
		pending = {}
	end

	local event = pending[path]
	if event then
		event.scope = scope
		event.filename = filename
	else
		pending[path] = {
			scope = scope,
			filename = filename,
			path = path,
		}
	end

	arm_timer()
end

local function is_cf(filename)
	local len = #filename
	return len > 3 and filename:sub(len - 2) == ".cf"
end

local function runtime_scope(scope)
	if scope == "both" then return "runtime-both" end
	return "runtime-" .. scope
end

-- fs_event is deliberately not recursive. Theme directories watch normal .cf
-- files and only the runtime child directory name; runtime/*.cf has a dedicated
-- handle so adding runtime support does not change the old module watch policy.
local function watch_directory(path, scope, watch_runtime_child)
	local stat = uv.fs_stat(path)
	if not stat or stat.type ~= "directory" then
		return nil
	end

	local handle = uv.new_fs_event()
	if not handle then
		return nil, "failed to create fs_event handle"
	end

	local ok, err = handle:start(path, {}, function(watch_err, filename, events)
		if watch_err then
			vim.schedule(function()
				report_error(watch_err, path, scope)
			end)
			return
		end

		if filename == nil then
			queue(scope, nil, path)
			return
		end

		if is_cf(filename) then
			queue(scope, filename, fs_join(path, filename))
			return
		end

		if watch_runtime_child and filename == RUNTIME_DIR and events and events.rename then
			vim.schedule(function()
				if not running then
					return
				end
				refresh_runtime_handles()
				queue(runtime_scope(scope), nil, fs_join(path, RUNTIME_DIR))
			end)
		end
	end)

	if not ok then
		close_handle(handle)
		return nil, err or "failed to start fs_event"
	end

	return handle
end

local function add_watch(handles, path, scope, watch_runtime_child)
	local handle, err = watch_directory(path, scope, watch_runtime_child)
	if handle then
		handles[#handles + 1] = handle
	elseif err then
		report_error(err, path, scope)
	end
end

local function refresh_theme_handles()
	close_handles(theme_handles)

	local active_path = fs_join(theme_path, active_theme)
	local default_path = fs_join(theme_path, default_theme)

	if active_path == default_path then
		add_watch(theme_handles, active_path, "both", true)
		return
	end

	add_watch(theme_handles, active_path, "active", true)
	add_watch(theme_handles, default_path, "default", true)
end

refresh_runtime_handles = function()
	close_handles(runtime_handles)

	-- Shared root runtime modules sit between active and default in the exact same
	-- fallback position as root color.cf/config.cf.
	add_watch(runtime_handles, fs_join(theme_path, RUNTIME_DIR), "runtime-root", false)

	local active_path = fs_join(theme_path, active_theme, RUNTIME_DIR)
	local default_path = fs_join(theme_path, default_theme, RUNTIME_DIR)
	if active_path == default_path then
		add_watch(runtime_handles, active_path, "runtime-both", false)
		return
	end

	add_watch(runtime_handles, active_path, "runtime-active", false)
	add_watch(runtime_handles, default_path, "runtime-default", false)
end

local function root_scope_for(filename)
	if active_theme == default_theme and filename == active_theme then
		return "both"
	end

	if filename == active_theme then
		return "active"
	end

	if filename == default_theme then
		return "default"
	end
end

local function watch_root()
	local handle = uv.new_fs_event()
	if not handle then
		return nil, "failed to create root fs_event handle"
	end

	local ok, err = handle:start(theme_path, {}, function(watch_err, filename, events)
		if watch_err then
			vim.schedule(function()
				report_error(watch_err, theme_path, "root")
			end)
			return
		end

		if filename == nil then
			queue("root", nil, theme_path)
			return
		end

		if filename == ".cf-theme" or filename == "color.cf" or filename == "config.cf" then
			queue("root", filename, fs_join(theme_path, filename))
			return
		end

		if filename == RUNTIME_DIR and events and events.rename then
			vim.schedule(function()
				if not running then
					return
				end
				refresh_runtime_handles()
				queue("runtime-root", nil, fs_join(theme_path, RUNTIME_DIR))
			end)
			return
		end

		-- The root watch is not used for theme contents. It only repairs the
		-- directory watches if an active/default theme directory is replaced.
		local scope = root_scope_for(filename)
		if scope and events and events.rename then
			vim.schedule(function()
				if not running then
					return
				end
				refresh_theme_handles()
				refresh_runtime_handles()
				queue(scope, nil, fs_join(theme_path, filename))
			end)
		end
	end)

	if not ok then
		close_handle(handle)
		return nil, err or "failed to start root fs_event"
	end

	return handle
end

function M.start(path, default_name, active_name, callback, error_callback)
	assert(type(path) == "string" and path ~= "", "cf.watcher.start: theme_path must be a string")
	assert(type(default_name) == "string" and default_name ~= "", "cf.watcher.start: default theme must be a string")
	assert(type(active_name) == "string" and active_name ~= "", "cf.watcher.start: active theme must be a string")
	assert(type(callback) == "function", "cf.watcher.start: callback must be a function")
	assert(error_callback == nil or type(error_callback) == "function", "cf.watcher.start: error callback must be a function")

	M.stop()

	theme_path = fs_normalize(path)
	default_theme = default_name
	active_theme = active_name
	on_change = callback
	on_error = error_callback

	local stat = uv.fs_stat(theme_path)
	if not stat or stat.type ~= "directory" then
		return nil, "theme_path is not a directory: " .. theme_path
	end

	local handle, err = watch_root()
	if not handle then
		return nil, err
	end

	root_handle = handle
	running = true
	refresh_theme_handles()
	refresh_runtime_handles()

	return true
end

function M.set_themes(default_name, active_name)
	assert(running, "cf.watcher.set_themes: watcher is not running")
	assert(type(default_name) == "string" and default_name ~= "", "cf.watcher.set_themes: default theme must be a string")
	assert(type(active_name) == "string" and active_name ~= "", "cf.watcher.set_themes: active theme must be a string")

	if default_name == default_theme and active_name == active_theme then
		return false
	end

	default_theme = default_name
	active_theme = active_name
	refresh_theme_handles()
	refresh_runtime_handles()
	return true
end

function M.stop()
	running = false

	close_handles(theme_handles)
	close_handles(runtime_handles)
	close_handle(root_handle)
	root_handle = nil

	if timer then
		timer:stop()
		if not timer:is_closing() then
			timer:close()
		end
		timer = nil
	end

	pending = nil
	theme_path = nil
	default_theme = nil
	active_theme = nil
	on_change = nil
	on_error = nil
end

function M.is_running()
	return running
end

return M
