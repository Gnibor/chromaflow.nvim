---@meta

---@class CFMenuOptions
---@field title? string
---@field items string[] Non-empty list of single-line labels.
---@field selected? integer One-based initial selection.
---@field render_item? fun(index:integer, selected:boolean, width:integer): CFFloatSpan[]
---@field on_select? fun(item:string, index:integer)
---@field on_default? fun(item:string, index:integer)
---@field on_back? fun()
---@field on_cancel? fun()
---@field on_space? fun(item:string, index:integer, menu:CFMenu)
---@field on_adjust? fun(item:string, index:integer, menu:CFMenu, delta:integer)
---@field on_mark? fun(item:string, index:integer, menu:CFMenu, value:boolean)

---@class CFMenu
---@field float CFFloat
---@field items string[]
---@field on_select? fun(item:string, index:integer)
---@field on_default? fun(item:string, index:integer)
---@field on_back? fun()
---@field on_cancel? fun()
---@field on_space? fun(item:string, index:integer, menu:CFMenu)
---@field restore_lineblend boolean
---@field set_item fun(self:CFMenu, index:integer, item:string)

local M = {}

---@param opts CFMenuOptions
---@return CFMenu
function M.open(opts) end

---Close the current menu, if one is open.
function M.close() end

return M
