---@meta

---@class CFResolverBackend
---@field lookup_hl? fun(name:string): string?
---@field group_style? fun(name:string): CFHighlightSet?
---@field style_target? fun(style:CFHighlightSet, max_layer:integer, mask:integer): string?
---@field setter? fun(name:string, value:CFHighlightSet|string?, is_link:boolean)

local M = {}

function M.clear_cache() end

---@param backend? CFResolverBackend
function M.setup_backend(backend) end

---Map a Tree-sitter or LSP type token to a semantic DSL token.
---@param source "vim"|"ts"|"lsp"
---@param token string
---@return string? semantic
function M.semantic_type_token(source, token) end

---Map a Tree-sitter or LSP modifier token to a semantic DSL token.
---@param source "vim"|"ts"|"lsp"
---@param token string
---@return string? semantic
function M.semantic_typemod_token(source, token) end

---@param type_name? string
---@param typemod? string
---@param target_type string
---@param filetype? string
---@param targets? CFStyleTargets
---@param clear? CFStyleTargets
---@return string? warning
function M.link(type_name, typemod, target_type, filetype, targets, clear) end

---@param type_name? string
---@param typemod? string
---@param filetype? string
---@param clear? CFStyleTargets
---@return string? warning
function M.clear(type_name, typemod, filetype, clear) end

---@param type_name? string
---@param typemod? string
---@param filetype? string
---@param targets? CFStyleTargets
---@param clear? CFStyleTargets
---@param typemod_style? boolean
---@return string[] names
function M.runtime_style_names(type_name, typemod, filetype, targets, clear, typemod_style) end

---@param type_name? string
---@param typemod? string
---@param target_type string
---@param filetype? string
---@param targets? CFStyleTargets
---@param clear? CFStyleTargets
---@return string[] names
function M.runtime_link_names(type_name, typemod, target_type, filetype, targets, clear) end

---@param type_name? string
---@param typemod? string
---@param filetype? string
---@param clear? CFStyleTargets
---@return string[] names
function M.runtime_clear_names(type_name, typemod, filetype, clear) end

---@param type_name? string
---@param typemods? string|string[]
---@param style CFHighlightSet
---@param filetype? string
---@param targets? CFStyleTargets
---@param clear? CFStyleTargets
---@param typemod_style? boolean
---@return string? warning
function M.resolve(type_name, typemods, style, filetype, targets, clear, typemod_style) end

return M
