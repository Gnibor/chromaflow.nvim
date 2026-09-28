local M = {}

local bit = require("bit")
local band = bit.band
local bor = bit.bor
local lshift = bit.lshift
local rshift = bit.rshift
local tobit = bit.tobit

local byte = string.byte
local format = string.format
local type = type

local UINT32 = 0x100000000
local ALPHA_SHIFT = 24
local INV_255 = 1 / 255
local INV_100 = 1 / 100

-- LuaJIT BitOp rounds fractional numbers to the nearest integer.
-- Correct the possible upward round to preserve floor semantics without
-- calling math.floor() in a colour hotpath.
local function floor_channel(value)
	local integer = tobit(value)
	if integer > value then
		integer = integer - 1
	end
	if integer < 0 then
		return 0
	end
	if integer > 255 then
		return 255
	end
	return integer
end

local function clamp_percent(percent)
	if percent <= 0 then
		return 0
	end
	if percent >= 100 then
		return 100
	end
	return percent
end

local function unsigned32(value)
	return value < 0 and value + UINT32 or value
end

local function pack_rgba(a, r, g, b)
	return unsigned32(bor(lshift(a, ALPHA_SHIFT), lshift(r, 16), lshift(g, 8), b))
end

local function unpack_rgba(color)
	return
		band(rshift(color, 24), 0xFF),
		band(rshift(color, 16), 0xFF),
		band(rshift(color, 8), 0xFF),
		band(color, 0xFF)
end

local function hex_nibble(value)
	if value >= 48 and value <= 57 then
		return value - 48
	end
	if value >= 65 and value <= 70 then
		return value - 55
	end
	if value >= 97 and value <= 102 then
		return value - 87
	end
	return -1
end

local function hex_byte(hi, lo)
	hi = hex_nibble(hi)
	lo = hex_nibble(lo)
	if hi < 0 or lo < 0 then
		return nil
	end
	return lshift(hi, 4) + lo
end

-- Internal engine boundary: #RRGGBB or #RRGGBBAA -> 0xAARRGGBB.
-- Six-digit RGB input becomes fully opaque RGBA (A=0xFF).
function M.from_hex(value)
	assert(type(value) == "string", "colour must be a hex string")

	local len = #value
	assert((len == 7 or len == 9) and byte(value, 1) == 35, "colour must be #RRGGBB or #RRGGBBAA")

	local r = hex_byte(byte(value, 2), byte(value, 3))
	local g = hex_byte(byte(value, 4), byte(value, 5))
	local b = hex_byte(byte(value, 6), byte(value, 7))
	assert(r and g and b, "invalid hex colour: " .. value)

	if len == 7 then
		return pack_rgba(255, r, g, b)
	end

	local a = hex_byte(byte(value, 8), byte(value, 9))
	assert(a, "invalid hex colour: " .. value)
	return pack_rgba(a, r, g, b)
end

-- Internal engine helper. Internal integers are always 0xAARRGGBB.
-- Without force_alpha, opaque colours are rendered as #RRGGBB; colours with
-- transparency are rendered as #RRGGBBAA.
function M.to_hex(value, force_alpha)
	assert(type(value) == "number", "colour must be a packed RGBA integer")

	local a, r, g, b = unpack_rgba(value)
	if force_alpha or a ~= 255 then
		return format("#%02x%02x%02x%02x", r, g, b, a)
	end

	return format("#%02x%02x%02x", r, g, b)
end

-- Internal render helpers. They deliberately do not guess terminal/GUI support;
-- the caller already knows whether alpha output is enabled.
function M.to_rgb_hex(value)
	assert(type(value) == "number", "colour must be a packed RGBA integer")
	local _, r, g, b = unpack_rgba(value)
	return format("#%02x%02x%02x", r, g, b)
end

function M.to_rgba_hex(value)
	assert(type(value) == "number", "colour must be a packed RGBA integer")
	local a, r, g, b = unpack_rgba(value)
	return format("#%02x%02x%02x%02x", r, g, b, a)
end

-- Public colour functions accept packed 0xAARRGGBB integers or hex strings.
-- Hex is converted once at the boundary; every calculation after this point
-- uses numeric channels only.
local function unpack_color(value)
	if type(value) == "string" then
		value = M.from_hex(value)
	else
		assert(type(value) == "number", "colour must be a packed RGBA integer or hex string")
	end

	local a, r, g, b = unpack_rgba(value)
	return r, g, b, a
end

local CTERM_LEVELS = { [0] = 0, 95, 135, 175, 215, 255 }
-- Conventional xterm defaults only; terminals may customize ANSI slots 0..15.
local CTERM_ANSI = {
	[0] = 0xFF000000, 0xFFCD0000, 0xFF00CD00, 0xFFCDCD00,
	0xFF0000EE, 0xFFCD00CD, 0xFF00CDCD, 0xFFE5E5E5,
	0xFF7F7F7F, 0xFFFF0000, 0xFF00FF00, 0xFFFFFF00,
	0xFF5C5CFF, 0xFFFF00FF, 0xFF00FFFF, 0xFFFFFFFF,
}

local function cterm_level(value)
	if value <= 47 then return 0 end
	if value <= 115 then return 1 end
	if value <= 155 then return 2 end
	if value <= 195 then return 3 end
	if value <= 235 then return 4 end
	return 5
end

-- Nearest xterm-256 cube/grayscale entry by squared RGB distance. Deliberately
-- avoid the customizable ANSI slots. Like to_rgb_hex(), this drops alpha;
-- callers wanting transparency must composite against a background first.
function M.to_cterm(value)
	local r, g, b = unpack_color(value)
	local ri, gi, bi = cterm_level(r), cterm_level(g), cterm_level(b)
	local dr, dg, db = r - CTERM_LEVELS[ri], g - CTERM_LEVELS[gi], b - CTERM_LEVELS[bi]
	local cube_distance = dr * dr + dg * dg + db * db
	local gray = math.floor((r + g + b - 24) / 30 + 0.5)
	if gray < 0 then gray = 0 elseif gray > 23 then gray = 23 end
	local level = 8 + 10 * gray
	dr, dg, db = r - level, g - level, b - level
	if dr * dr + dg * dg + db * db < cube_distance then
		return 232 + gray
	end
	return 16 + 36 * ri + 6 * gi + bi
end

-- Decode an explicit palette index for terminal-only pipeline manipulation.
function M.from_cterm(index)
	assert(type(index) == "number" and index >= 0 and index <= 255 and index % 1 == 0,
		"cterm colour must be an integer palette index from 0 to 255")
	if index < 16 then return CTERM_ANSI[index] end
	if index >= 232 then
		local level = 8 + 10 * (index - 232)
		return pack_rgba(255, level, level, level)
	end
	local cube = index - 16
	return pack_rgba(255, CTERM_LEVELS[math.floor(cube / 36)],
		CTERM_LEVELS[math.floor(cube / 6) % 6], CTERM_LEVELS[cube % 6])
end

local function mix_channels(percent, ar, ag, ab, aa, br, bg, bb, ba)
	local w = clamp_percent(percent) * INV_100
	local iw = 1 - w

	-- Common RGB path: no alpha division at all.
	if aa == 255 and ba == 255 then
		return
			floor_channel(ar * w + br * iw),
			floor_channel(ag * w + bg * iw),
			floor_channel(ab * w + bb * iw),
			255
	end

	local aw = aa * w
	local bw = ba * iw
	local alpha = aw + bw
	if alpha <= 0 then
		return 0, 0, 0, 0
	end

	return
		floor_channel((ar * aw + br * bw) / alpha),
		floor_channel((ag * aw + bg * bw) / alpha),
		floor_channel((ab * aw + bb * bw) / alpha),
		floor_channel(alpha)
end

-- mix(20, added, base): mix 20% of added into base.
function M.mix(percent, added_color, base_color)
	local ar, ag, ab, aa = unpack_color(added_color)
	local br, bg, bb, ba = unpack_color(base_color)
	local r, g, b, a = mix_channels(percent, ar, ag, ab, aa, br, bg, bb, ba)
	return pack_rgba(a, r, g, b)
end

-- opacity(colour, 80, background):
--   return 1: opaque RGBA pre-composited for TUI use (A=0xFF)
--   return 2: original RGB with the requested effective alpha (0xAARRGGBB)
--
-- Existing source alpha is multiplied by the requested opacity. Background
-- alpha participates in the pre-composited RGB result as well.
local function opacity_channels(r, g, b, a, percent, br, bg, bb, ba)
	local opacity = clamp_percent(percent) * INV_100
	local effective_a = a * opacity
	local fa = effective_a * INV_255
	local bga = ba * INV_255
	local inv_fa = 1 - fa
	local out_a = fa + bga * inv_fa

	local mr, mg, mb
	if out_a <= 0 then
		mr, mg, mb = 0, 0, 0
	else
		local bg_weight = bga * inv_fa
		mr = floor_channel((r * fa + br * bg_weight) / out_a)
		mg = floor_channel((g * fa + bg * bg_weight) / out_a)
		mb = floor_channel((b * fa + bb * bg_weight) / out_a)
	end

	return mr, mg, mb, floor_channel(effective_a)
end

function M.opacity(color, percent, background)
	local r, g, b, a = unpack_color(color)
	local br, bg, bb, ba = unpack_color(background)
	local mr, mg, mb, result_a = opacity_channels(r, g, b, a, percent, br, bg, bb, ba)
	return pack_rgba(255, mr, mg, mb), pack_rgba(result_a, r, g, b)
end

local function brightness_channel(value, percent)
	local factor = percent * INV_100
	local result
	if factor > 0 then
		result = value + (255 - value) * factor
	else
		result = value + value * factor
	end
	return floor_channel(result)
end

local function brightness_channels(r, g, b, percent)
	return
		brightness_channel(r, percent),
		brightness_channel(g, percent),
		brightness_channel(b, percent)
end

function M.brightness(color, percent)
	assert(type(percent) == "number", "brightness() expects a signed percentage")
	local r, g, b, a = unpack_color(color)
	r, g, b = brightness_channels(r, g, b, percent)
	return pack_rgba(a, r, g, b)
end

function M.lighten(color, percent)
	assert(type(percent) == "number" and percent >= 0, "lighten() expects a percentage >= 0")
	local r, g, b, a = unpack_color(color)
	r, g, b = brightness_channels(r, g, b, percent)
	return pack_rgba(a, r, g, b)
end

function M.darken(color, percent)
	assert(type(percent) == "number" and percent >= 0, "darken() expects a percentage >= 0")
	local r, g, b, a = unpack_color(color)
	r, g, b = brightness_channels(r, g, b, -percent)
	return pack_rgba(a, r, g, b)
end

local function rgb_to_hsl(r, g, b)
	local rf = r * INV_255
	local gf = g * INV_255
	local bf = b * INV_255

	local max = rf
	if gf > max then max = gf end
	if bf > max then max = bf end

	local min = rf
	if gf < min then min = gf end
	if bf < min then min = bf end

	local l = (max + min) * 0.5
	if max == min then
		return 0, 0, l
	end

	local d = max - min
	local s
	if l > 0.5 then
		s = d / (2 - max - min)
	else
		s = d / (max + min)
	end

	local h
	if max == rf then
		h = (gf - bf) / d
		if gf < bf then h = h + 6 end
	elseif max == gf then
		h = (bf - rf) / d + 2
	else
		h = (rf - gf) / d + 4
	end

	return h * 60, s, l
end

local function hsl_component(h, s, l, n)
	local k = (n + h / 30) % 12
	local a
	if l < 0.5 then
		a = s * l
	else
		a = s * (1 - l)
	end

	local x = k - 3
	local y = 9 - k
	local m = x
	if y < m then m = y end
	if 1 < m then m = 1 end
	if m < -1 then m = -1 end

	return floor_channel((l - a * m) * 255)
end

local function shift_hue_channels(r, g, b, degree)
	local h, s, l = rgb_to_hsl(r, g, b)
	h = (h + degree) % 360
	return
		hsl_component(h, s, l, 0),
		hsl_component(h, s, l, 8),
		hsl_component(h, s, l, 4)
end

function M.shiftHue(color, degree)
	assert(type(degree) == "number", "shiftHue() expects degrees")
	local r, g, b, a = unpack_color(color)
	r, g, b = shift_hue_channels(r, g, b, degree)
	return pack_rgba(a, r, g, b)
end

local function gamma_channel(value, gamma_value)
	if value <= 0 then return 0 end
	if value >= 255 then return 255 end
	return floor_channel(((value * INV_255) ^ gamma_value) * 255)
end

local function gamma_channels(r, g, b, gamma_value)
	return
		gamma_channel(r, gamma_value),
		gamma_channel(g, gamma_value),
		gamma_channel(b, gamma_value)
end

-- gamma > 1 darkens, gamma < 1 lightens, gamma == 1 is unchanged.
function M.gamma(color, gamma_value)
	assert(type(gamma_value) == "number" and gamma_value > 0, "gamma() expects a value > 0")
	local r, g, b, a = unpack_color(color)
	r, g, b = gamma_channels(r, g, b, gamma_value)
	return pack_rgba(a, r, g, b)
end

return M
