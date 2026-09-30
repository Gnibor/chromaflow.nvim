---@meta _

---@class CFConfigDiagnosticPolicy
---@field color_trace boolean
---@field severity_bias integer
---@field severity { hint: boolean, warn: boolean, error: boolean }
---@field messages { info: boolean, ok: boolean }

---@class CFConfig: CFSetupOptions
---@field alpha boolean
---@field theme_path? string
---@field watch boolean
---@field picker boolean
---@field autoreload { lsp: boolean, treesitter: boolean }
---@field diagnostic CFConfigDiagnosticPolicy
---@field lineblend { autostart: boolean, blend: number }
local M = {}

---@param opts? CFSetupOptions
function M.setup(opts) end

return M
