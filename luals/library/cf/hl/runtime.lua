---@meta

local M = {}

---Drop materialized style indexes after a full colorscheme reset.
function M.invalidate_materialized() end

---@return table<string, string> catalog Lowercase names mapped to canonical highlight names.
function M.refresh_catalog() end

---@param name string
---@return string? canonical_name
function M.lookup_hl(name) end

---@param name string
---@return CFHighlightSet? style
function M.group_style(name) end

---@param style CFHighlightSet
---@param max_layer integer
---@param mask integer
---@return string? name
function M.style_target(style, max_layer, mask) end

---@param name string
---@param value CFHighlightSet|string? Style table, link target, or nil to clear.
---@param is_link boolean
function M.setter(name, value, is_link) end

---@param name string
---@return CFHighlightSet? style
function M.read_effective_style(name) end

---@param name string
---@param style? CFHighlightSet
function M.runtime_write(name, style) end

---@param name string
---@param style CFHighlightSet
---@param clear? boolean
---@return boolean
function M.apply_raw(name, style, clear) end

---@param name string
---@param target string
---@param clear? boolean
---@return boolean
function M.apply_raw_link(name, target, clear) end

---@param name string
---@return boolean
function M.clear_raw(name) end

---@param clear? CFStyleTargets
function M.global_clear(clear) end

---@return CFResolverBackend
function M.backend() end

return M
