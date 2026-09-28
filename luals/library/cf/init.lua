---@meta

---@class CFLineBlendSetupOptions
---@field autostart? boolean Start LineBlend during cf.setup(). Default true.
---@field blend? number Blend amount from 0..100. Default 50.

---@class CFAutoreloadSetupOptions
---@field lsp? boolean Refresh LSP semantic tokens after theme apply/reload. Default false; when enabled, setup keeps it true only if this Neovim supports the required API.
---@field treesitter? boolean Restart active Tree-sitter highlighters after theme apply/reload. Default false; when enabled, setup keeps it true only if this Neovim supports the required API.


---@class CFDiagnosticSeveritySetupOptions
---@field hint? boolean Show HINT diagnostics.
---@field warn? boolean Show WARN diagnostics.
---@field error? boolean Show ERROR diagnostics.

---@class CFDiagnosticMessageSetupOptions
---@field info? boolean Show INFO user messages.
---@field ok? boolean Show OK user messages.

---@class CFDiagnosticSetupOptions
---@field debug? boolean Show debug-only records and bypass the normal diagnostic/message visibility filters.
---@field severity_bias? integer Global diagnostic severity shift inside the internal 0..255 range.
---@field severity? CFDiagnosticSeveritySetupOptions Visibility filters for HINT/WARN/ERROR diagnostics.
---@field messages? CFDiagnosticMessageSetupOptions Visibility filters for INFO/OK user messages.

---@class CFSetupOptions
---@field alpha? boolean Use alpha-capable output paths where cf.nvim supports both alpha and pre-composited output.
---@field theme_path? string Theme root containing `.cf-theme`, theme folders, and optional root color/config fallbacks.
---@field watch? boolean Watch the active/default theme files and reload after the 250 ms debounce window. Default true.
---@field picker? boolean Enable picker source tracking and :CFPick. Default false.
---@field autoreload? CFAutoreloadSetupOptions Consumer refresh policy after applying a theme.
---@field diagnostic? CFDiagnosticSetupOptions Diagnostic/debug visibility policy.
---@field lineblend? CFLineBlendSetupOptions LineBlend lifecycle/configuration.

---@class CFCompiledThemeFile
---@field name string
---@field path string
---@field source "active"|"default"
---@field skipped? boolean
---@field failed? boolean Module failed validation/execution and was skipped locally.
---@field ignored? boolean File returned no theme module and was skipped with a HINT.

---@class CFCompiledModule
---@field kind "language"|"plugin"|"ui"
---@field name? string
---@field actions table[]
---@field apply fun(self:CFCompiledModule)

---@class CFCompiledTheme
---@field root string
---@field default string Default/fallback theme folder from `.cf-theme`.
---@field active string Actual active theme folder after invalid-active fallback.
---@field requested_active string Theme folder requested by `.cf-theme`.
---@field colors table<string, any> Normalized palette shared by all compiled modules.
---@field config CFThemeConfig Theme-level config.cf result.
---@field color_path string
---@field config_path? string
---@field module_files CFCompiledThemeFile[]
---@field modules CFCompiledModule[]
---@field runtime_modules table<string, CFCompiledRuntimeModule> Requested runtime modules resolved for this compile.

---@class CFFunctionNamespace
---@field lineblend CFLineBlendAPI

---@class CF
---@field fn CFFunctionNamespace Public utility/tool namespace.
local M = {}

---Configure ChromaFlow and load/watch the selected theme at the appropriate startup boundary.
---Calling setup again updates the configured state; before VimEnter the final setup state wins.
---@param opts? CFSetupOptions
---@return CF
function M.setup(opts) end

---Compile and fully re-apply the currently selected theme.
---@return CFCompiledTheme compiledTheme
function M.reload() end

---Persist a new active theme selection and apply it once. The watcher is stopped
---before `.cf-theme` is written so this operation cannot self-trigger a second reload.
---When `set_default` is true, the selected theme becomes both default and active.
---@param name string
---@param set_default? boolean
---@return CFCompiledTheme compiledTheme
function M.set_theme(name, set_default) end

function M.stop_watcher() end

return M
