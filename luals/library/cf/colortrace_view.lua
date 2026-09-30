---@meta

---@class CFColorTraceViewAPI
local M = {}

---Install ColorTrace buffer mappings and on-view diagnostic seeding.
---@return CFColorTraceViewAPI
function M.start() end

---Remove ColorTrace mappings and autocmds.
---@return CFColorTraceViewAPI
function M.stop() end

---@return boolean
function M.is_active() end

---Seed diagnostics for a visible .cf buffer. Internal test/benchmark hook.
---@param bufnr integer
---@return boolean seeded
function M._seed(bufnr) end

return M
