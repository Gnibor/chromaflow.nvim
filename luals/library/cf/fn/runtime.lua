---@meta

---@class CFFunctionRuntimeAPI
local M = {}

---@param name string Logical runtime module name without `.cf`.
---@return CFRuntimeModule
function M.runtime(name) end

---@param target CFRuntimeTarget
---@param action CFRuntimeAction
---@return boolean
function M.apply(target, action) end

---@param target CFRuntimeTarget
---@param action CFRuntimeAction
---@return boolean
function M.replace(target, action) end

---@param target CFRuntimeTarget
---@return boolean
function M.reset(target) end

---@param target CFRuntimeTarget
---@return boolean
function M.clear(target) end

---Create a stable semantic target handle directly. Theme modules usually obtain
---the same handles through hl.language, hl.plugin, hl.ui, or hl.raw.
---@param kind "language"|"plugin"|"ui"|"raw"
---@param scope? string Language/filetype or plugin identity; nil for ui/raw/global language.
---@param type_name string Semantic type or literal raw highlight group.
---@param typemod? string
---@return CFRuntimeTarget
function M.target(kind, scope, type_name, typemod) end

---Create a dynamic language or plugin scope whose properties are target handles.
---@param kind "language"|"plugin"
---@param scope string
---@return CFRuntimeLanguageScope|CFRuntimePluginScope
function M.scope(kind, scope) end

return M
