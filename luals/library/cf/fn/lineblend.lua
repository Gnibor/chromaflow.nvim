---@meta

---@class CFLineBlendActivateOptions
---@field blend? number|string Blend amount from 0..100; numeric strings are accepted.

---@class CFLineBlendTextRun
---@field row integer
---@field start_col integer
---@field end_col? integer
---@field hl_group string
---@field priority number

---@class CFLineBlendStatus
---@field enabled boolean
---@field blend number
---@field last_win? integer
---@field last_buf? integer
---@field last_row? integer
---@field last_line? string
---@field cursorline_bg? integer
---@field text_runs CFLineBlendTextRun[]
---@field virtual_sources table[]
---@field text_sources table[]

---@class CFLineBlendAPI
local M = {}

---Activate/install LineBlend. Repeated calls do not re-register providers/autocmds.
---@param opts? CFLineBlendActivateOptions
function M.activate(opts) end

---Alias of activate(), retained as the direct helper setup API.
---@param opts? CFLineBlendActivateOptions
function M.setup(opts) end

---Refresh the current cursor row. Nil/false keeps the session render-cache fast path;
---true bypasses only the last-line cache check.
---@param force? boolean
function M.refresh(force) end

---Set the blend amount and refresh generated groups/current rendering.
---@param value number|string Number from 0..100.
function M.set_blend(value) end

---Hard reload LineBlend's generated highlight-group/session caches.
function M.reload() end

---@return boolean
function M.is_active() end

---Disable LineBlend and clear its current overlay.
function M.stop() end

---@return CFLineBlendStatus
function M.status() end

return M
