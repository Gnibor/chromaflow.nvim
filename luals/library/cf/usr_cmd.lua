---@meta

---@class CFUserCommandHandlers
---@field reload? fun(): CFCompiledTheme
---@field save? fun(): integer, integer
---@field set_theme? fun(name:string, set_default?:boolean): CFCompiledTheme
---@field theme_menu? fun(): CFMenu

local M = {}

---Install or replace ChromaFlow user commands.
---@param handlers? CFUserCommandHandlers
function M.setup(handlers) end

return M
