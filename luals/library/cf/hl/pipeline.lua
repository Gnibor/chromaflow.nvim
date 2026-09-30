---@meta

---Pipeline builders operate on fg/bg/sp or the independent cfg/cbg channels.
---@class CFPipelineAPI
---@field mix CFMixPipelineAPI
---@field opacity CFUnaryPipelineAPI
---@field brightness CFUnaryPipelineAPI
---@field lighten CFUnaryPipelineAPI
---@field darken CFUnaryPipelineAPI
---@field shiftHue CFUnaryPipelineAPI
---@field gamma CFUnaryPipelineAPI
local M = {}

---@class CFPipelineTrace
---@field name "mix"|"opacity"|"brightness"|"lighten"|"darken"|"shiftHue"|"gamma"
---@field channel "fg"|"bg"|"sp"|"cfg"|"cbg"
---@field before CFColor
---@field a number
---@field b? CFColor
---@field backdrop? CFColor
---@field after integer

---Set the fallback backdrop used by opacity operations. Theme compilation uses colors.bg.
---@param value? CFColor Packed 0xAARRGGBB color or supported hex string.
function M.set_background(value) end

---Apply one operation and return its trace for ColorTrace consumers.
---@param fg CFColor|nil
---@param bg CFColor|nil
---@param sp CFColor|nil
---@param operation CFPipelineOperation
---@param cfg? CFColor
---@param cbg? CFColor
---@return CFColor? fg
---@return CFColor? bg
---@return CFColor? sp
---@return CFPipelineTrace trace
---@return CFColor? cfg
---@return CFColor? cbg
function M.color_trace_apply(fg, bg, sp, operation, cfg, cbg) end

---Apply operations in array order to packed colors. A missing channel is valid only
---if no operation addresses it; opacity also needs a background color.
---@param fg? CFColor
---@param bg? CFColor
---@param sp? CFColor
---@param operations? CFPipelineOperation[]
---@param cfg? CFColor Terminal foreground working color (ARGB/hex, not a palette index); falls back to fg.
---@param cbg? CFColor Terminal background working color (ARGB/hex, not a palette index); falls back to bg.
---@return CFColor? fg Unchanged inputs retain their original representation.
---@return CFColor? bg
---@return CFColor? sp
---@return CFColor? cfg
---@return CFColor? cbg
function M.apply(fg, bg, sp, operations, cfg, cbg) end

return M
