---@meta

---@class CFLuaSnipInstance
---@field snippet fun(...): any
---@field text_node fun(...): any
---@field insert_node fun(...): any
---@field add_snippets fun(filetype:string, snippets:table[])

local M = {}

---Register ChromaFlow snippets with a LuaSnip instance once.
---@param ls CFLuaSnipInstance
function M.setup(ls) end

return M
