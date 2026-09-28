-- Open this file with LuaLS attached and inspect the actual semantic tokens.
-- Builtin functions stay warm; variables, properties and types retain their
-- own colour families even when they share a modifier such as readonly.

---@class Reading
---@field value number
---@field unit string
local Reading = {}
Reading.__index = Reading

---@param value number
---@return Reading
function Reading.new(value)
	return setmetatable({ value = value, unit = "mV" }, Reading)
end

---@param factor number
---@return number
function Reading:scaled(factor)
	local result = self.value * factor
	return math.floor(result)
end

---@deprecated Use Reading:scaled instead.
function Reading:legacy_value()
	return self.value
end

local sample = Reading.new(12.5)
local message = string.format("Reading: %.1f %s\n", sample:scaled(2), sample.unit)
print(message)
print(sample:legacy_value())

return Reading
