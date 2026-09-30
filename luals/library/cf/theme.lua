---@meta


---@class CFCompiledRuntimeModule
---@field name string
---@field path string
---@field source "active"|"root"|"default"
---@field definition CFRuntimeModuleDefinition

---@class CFThemeAPI
local M = {}

---@param root string
---@return CFCompiledTheme
function M.compile(root) end

---@param compiled CFCompiledTheme
---@return CFCompiledTheme
function M.apply(compiled) end

---@param root string
---@return CFCompiledTheme
function M.load(root) end

---@param compiled CFCompiledTheme
---@param name string Logical module name without `.cf`.
---@return CFCompiledRuntimeModule
function M.load_runtime(compiled, name) end

---@return CFCompiledTheme?
function M.current() end

---Read the two `.cf-theme` entries.
---@param root string
---@return string default_name
---@return string active_name
function M.selection(root) end

---List valid theme directories below the root.
---@param root string
---@return string[]
function M.available(root) end

---Write a new default theme while preserving the selected active theme.
---This changes selection only; use cf.set_default_theme() to reload and update the watcher.
---@param root string
---@param default_name string
---@return string default_name
---@return string active_name
function M.set_default(root, default_name) end

---Write the active theme into `.cf-theme`. When set_default is true, both lines
---are changed to the selected theme. This function only changes selection; it
---does not compile/apply. Prefer cf.set_theme() for normal user-facing changes.
---@param root string
---@param active_name string
---@param set_default? boolean
---@return string default_name
---@return string active_name
function M.select(root, active_name, set_default) end

---Re-execute one file from the current theme to collect on-view diagnostics.
---The rebuilt module is not applied to the active theme.
---@param path string
---@return boolean found_and_loaded
function M.color_trace_file(path) end

return M
