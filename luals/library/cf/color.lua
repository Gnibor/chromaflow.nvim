---@meta

---@alias CFColor integer|string Packed 0xAARRGGBB integer or #RRGGBB/#RRGGBBAA string.

---@class CFColorAPI
local M = {}

---Convert #RRGGBB or #RRGGBBAA to packed 0xAARRGGBB.
---@param value string
---@return integer color
function M.from_hex(value) end

---Convert packed 0xAARRGGBB to #RRGGBB or #RRGGBBAA.
---@param value integer
---@param force_alpha? boolean
---@return string color
function M.to_hex(value, force_alpha) end

---Render packed 0xAARRGGBB as #RRGGBB, dropping alpha.
---@param value integer
---@return string color
function M.to_rgb_hex(value) end

---Render packed 0xAARRGGBB as #RRGGBBAA.
---@param value integer
---@return string color
function M.to_rgba_hex(value) end

---Nearest xterm-256 cube/grayscale index (16..255) by squared RGB distance.
---Alpha is discarded; composite first with opacity() when needed.
---Avoids customizable ANSI slots 0..15. No terminal settings are changed.
---@param value CFColor
---@return integer index
function M.to_cterm(value) end

---Decode an xterm-256 palette index to opaque ARGB. Slots 0..15 use xterm
---defaults, not a query of the user's customized terminal palette.
---@param index integer Palette index 0..255.
---@return integer color Packed 0xFFRRGGBB.
function M.from_cterm(index) end

---Mix `percent` of `addedColor` into `baseColor`.
---@param percent number
---@param addedColor CFColor
---@param baseColor CFColor
---@return integer color Packed 0xAARRGGBB.
function M.mix(percent, addedColor, baseColor) end

---Apply `percent` opacity to `color` over `background`.
---Returns the opaque pre-composited result first and the alpha-preserving result second.
---@param color CFColor
---@param percent number
---@param background CFColor
---@return integer mixedColor Packed opaque 0xFFRRGGBB for non-alpha output.
---@return integer alphaColor Packed 0xAARRGGBB for alpha-capable output.
function M.opacity(color, percent, background) end

---Adjust brightness with a signed percentage.
---Positive values lighten; negative values darken.
---@param color CFColor
---@param percent number
---@return integer color Packed 0xAARRGGBB.
function M.brightness(color, percent) end

---Lighten a color by a non-negative percentage.
---@param color CFColor
---@param percent number
---@return integer color Packed 0xAARRGGBB.
function M.lighten(color, percent) end

---Darken a color by a non-negative percentage.
---@param color CFColor
---@param percent number
---@return integer color Packed 0xAARRGGBB.
function M.darken(color, percent) end

---Shift hue by `degree` degrees.
---@param color CFColor
---@param degree number
---@return integer color Packed 0xAARRGGBB.
function M.shiftHue(color, degree) end

---Apply gamma correction.
---Values > 1 darken, values < 1 lighten, and 1 leaves the color unchanged.
---@param color CFColor
---@param value number
---@return integer color Packed 0xAARRGGBB.
function M.gamma(color, value) end

return M
