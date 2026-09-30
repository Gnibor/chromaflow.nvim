---@meta

---@class CFWatchChange
---@field scope string
---@field filename? string
---@field path string

local M = {}

---Start watching a theme root and its selected theme/runtime directories.
---@param path string
---@param default_name string
---@param active_name string
---@param callback fun(batch:table<string, CFWatchChange>) Changes keyed by full path after debounce.
---@param error_callback? fun(error:string, path?:string, scope?:string)
---@return boolean? ok
---@return string? error
function M.start(path, default_name, active_name, callback, error_callback) end

---Update the watched theme directories after a selection change.
---@param default_name string
---@param active_name string
---@return boolean changed
function M.set_themes(default_name, active_name) end

function M.stop() end

---@return boolean
function M.is_running() end

return M
