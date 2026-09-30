local M = {}

local color = require("cf.color")
local config = require("cf.config")

local OP_MIX = 1
local OP_OPACITY = 2
local OP_BRIGHTNESS = 3
local OP_LIGHTEN = 4
local OP_DARKEN = 5
local OP_SHIFT_HUE = 6
local OP_GAMMA = 7

local CH_FG = 1
local CH_BG = 2
local CH_SP = 3
local CH_CFG = 4
local CH_CBG = 5

local base_background

local function op1(opcode, channel, value)
	return { opcode, channel, value }
end

local function op2(opcode, channel, value1, value2)
	return { opcode, channel, value1, value2 }
end

local function channel_api(opcode, two_args)
	if two_args then
		return {
			fg = function(a, b) return op2(opcode, CH_FG, a, b) end,
			bg = function(a, b) return op2(opcode, CH_BG, a, b) end,
			sp = function(a, b) return op2(opcode, CH_SP, a, b) end,
			cfg = function(a, b) return op2(opcode, CH_CFG, a, b) end,
			cbg = function(a, b) return op2(opcode, CH_CBG, a, b) end,
		}
	end

	return {
		fg = function(value) return op1(opcode, CH_FG, value) end,
		bg = function(value) return op1(opcode, CH_BG, value) end,
		sp = function(value) return op1(opcode, CH_SP, value) end,
		cfg = function(value) return op1(opcode, CH_CFG, value) end,
		cbg = function(value) return op1(opcode, CH_CBG, value) end,
	}
end

M.mix = channel_api(OP_MIX, true)
M.opacity = channel_api(OP_OPACITY, false)
M.brightness = channel_api(OP_BRIGHTNESS, false)
M.lighten = channel_api(OP_LIGHTEN, false)
M.darken = channel_api(OP_DARKEN, false)
M.shiftHue = channel_api(OP_SHIFT_HUE, false)
M.gamma = channel_api(OP_GAMMA, false)

function M.set_background(value)
	base_background = value
end

local function channel_name(channel)
	if channel == CH_FG then return "fg" end
	if channel == CH_BG then return "bg" end
	if channel == CH_CFG then return "cfg" end
	if channel == CH_CBG then return "cbg" end
	return "sp"
end

local function apply_one(value, opcode, a, b, backdrop, cterm)
	if opcode == OP_MIX then
		return color.mix(a, b, value)
	elseif opcode == OP_OPACITY then
		assert(backdrop ~= nil, "cf.hl.pipeline: opacity requires a background color")
		local opaque, alpha = color.opacity(value, a, backdrop)
		return not cterm and config.alpha and alpha or opaque
	elseif opcode == OP_BRIGHTNESS then
		return color.brightness(value, a)
	elseif opcode == OP_LIGHTEN then
		return color.lighten(value, a)
	elseif opcode == OP_DARKEN then
		return color.darken(value, a)
	elseif opcode == OP_SHIFT_HUE then
		return color.shiftHue(value, a)
	elseif opcode == OP_GAMMA then
		return color.gamma(value, a)
	end

	error("cf.hl.pipeline: unknown pipeline opcode", 3)
end

function M.color_trace_apply(fg, bg, sp, operation, cfg, cbg)
	assert(type(operation) == "table", "cf.hl.pipeline: pipeline entry must be an operation")

	local opcode = operation[1]
	local channel = operation[2]
	local value
	local backdrop

	if channel == CH_FG then
		value = fg
		backdrop = bg or base_background
	elseif channel == CH_BG then
		value = bg
		backdrop = base_background
	elseif channel == CH_SP then
		value = sp
		backdrop = bg or base_background
	elseif channel == CH_CFG then
		value = cfg or fg
		backdrop = cbg or bg or base_background
	elseif channel == CH_CBG then
		value = cbg or bg
		backdrop = base_background
	else
		error("cf.hl.pipeline: invalid channel", 2)
	end

	assert(value ~= nil, "cf.hl.pipeline: " .. channel_name(channel) .. " has no color to manipulate")
	local result = apply_one(value, opcode, operation[3], operation[4], backdrop, channel >= CH_CFG)

	if channel == CH_FG then
		fg = result
	elseif channel == CH_BG then
		bg = result
	elseif channel == CH_SP then
		sp = result
	elseif channel == CH_CFG then
		cfg = result
	else
		cbg = result
	end

	local name
	if opcode == OP_MIX then name = "mix"
	elseif opcode == OP_OPACITY then name = "opacity"
	elseif opcode == OP_BRIGHTNESS then name = "brightness"
	elseif opcode == OP_LIGHTEN then name = "lighten"
	elseif opcode == OP_DARKEN then name = "darken"
	elseif opcode == OP_SHIFT_HUE then name = "shiftHue"
	elseif opcode == OP_GAMMA then name = "gamma"
	else error("cf.hl.pipeline: unknown pipeline opcode", 2) end

	return fg, bg, sp, {
		name = name,
		channel = channel_name(channel),
		before = value,
		a = operation[3],
		b = operation[4],
		backdrop = backdrop,
		after = result,
	}, cfg, cbg
end

-- All five channels remain ARGB working colours here. The style boundary
-- decodes cterm indices and quantizes results once, after the pipeline.
function M.apply(fg, bg, sp, operations, cfg, cbg)
	if operations == nil then
		return fg, bg, sp, cfg, cbg
	end

	assert(type(operations) == "table", "cf.hl.pipeline: pipeline must be a table")

	for i = 1, #operations do
		local operation = operations[i]
		assert(type(operation) == "table", "cf.hl.pipeline: pipeline entries must be operations")

		local opcode = operation[1]
		local channel = operation[2]
		local value
		local backdrop

		if channel == CH_FG then
			value = fg
			backdrop = bg or base_background
		elseif channel == CH_BG then
			value = bg
			backdrop = base_background
		elseif channel == CH_SP then
			value = sp
			backdrop = bg or base_background
		elseif channel == CH_CFG then
			value = cfg or fg
			backdrop = cbg or bg or base_background
		elseif channel == CH_CBG then
			value = cbg or bg
			backdrop = base_background
		else
			error("cf.hl.pipeline: invalid channel", 2)
		end

		assert(value ~= nil, "cf.hl.pipeline: " .. channel_name(channel) .. " has no color to manipulate")
		value = apply_one(value, opcode, operation[3], operation[4], backdrop, channel >= CH_CFG)

		if channel == CH_FG then
			fg = value
		elseif channel == CH_BG then
			bg = value
		elseif channel == CH_SP then
			sp = value
		elseif channel == CH_CFG then
			cfg = value
		else
			cbg = value
		end
	end

	return fg, bg, sp, cfg, cbg
end

return M
