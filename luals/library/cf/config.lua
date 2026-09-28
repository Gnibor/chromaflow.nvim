---@meta _

---@class CFConfig: CFSetupOptions
---@field alpha boolean
---@field theme_path? string
---@field watch boolean
---@field autoreload { lsp: boolean, treesitter: boolean }
---@field diagnostic CFDiagnosticPolicy
---@field lineblend { autostart: boolean, blend: number }
local M = {}

---@param opts? CFSetupOptions
function M.setup(opts) end

return M
