-- Compact LuaLS semantic-token showcase for ChromaFlow theme authors.

-- LSP: keyword.documentation / macro / type
---@alias DemoId integer

-- LSP: keyword.documentation / class.declaration
---@class DemoRecord
-- LSP: keyword.documentation / property.declaration / type
---@field name string
---@field count integer
---@field readonly_name string
---@field extra_field boolean
local DemoRecord = {}
DemoRecord.__index = DemoRecord -- LSP: class / property / class

-- LSP: keyword.documentation / variable.declaration / property
---@enum DemoState
local DemoState = { idle = 0, running = 1 }

-- LSP: keyword.documentation / type.modification
---@generic T
---@param value T
---@return T
-- LSP: function.declaration / parameter.declaration
local function identity(value)
	return value
end

-- LSP: variable.global
DEMO_GLOBAL = 1
-- LSP: variable.declaration
local local_value = 2
-- LSP: keyword.documentation / variable.declaration; no readonly modifier
---@readonly
local readonly_by_convention = 3

-- LSP: keyword.documentation / parameter / type
---@param name string
---@param count DemoId
---@return DemoRecord
-- LSP: method / parameter.declaration; new has no modifier.
function DemoRecord.new(name, count)
	-- LSP: variable.declaration / function.defaultLibrary / property / parameter / class
	local instance = setmetatable({ name = name, count = count, readonly_name = name }, DemoRecord)
	return instance
end

---@param amount integer
---@return integer
-- LSP: method.declaration / parameter.declaration
function DemoRecord:add(amount)
	-- LSP: variable.definition / property; definition is not transferred to count.
	self.count = self.count + amount
	return self.count
end

-- LSP: keyword.documentation / function.declaration; no deprecated modifier
---@deprecated
local function deprecated_function(value)
	return value - 1
end

-- LSP: keyword.documentation / function.declaration; no async modifier
---@async
local function async_function(value)
	return value + 1
end

-- LSP: keyword.documentation / function.declaration; no abstract modifier
---@abstract
local function abstract_function()
end

local record = DemoRecord.new("demo", local_value)
record.extra_field = true

_G.demo_defaultLibrary = ""

-- LSP: function.defaultLibrary / variable.defaultLibrary / property
local loaded = require(_G.demo_defaultLibrary)
-- LSP: variable.declaration / variable.defaultLibrary
local global_table = _G
-- LSP: variable.declaration / variable.global
local editor = vim
-- LSP: variable.global / method; notify has no global modifier.
vim.notify("demo")

-- LSP: variable.declaration / variable.defaultLibrary
local string_table = string
-- LSP: variable.defaultLibrary / method; upper has no defaultLibrary modifier.
local upper = string.upper(record.name)
-- LSP: variable.declaration / variable.defaultLibrary
local table_table = table
-- LSP: variable.defaultLibrary / method; insert has no defaultLibrary modifier.
table.insert({ upper }, record.count)
-- LSP: variable.declaration / variable.defaultLibrary
local math_table = math
-- LSP: variable.defaultLibrary / method; sqrt has no defaultLibrary modifier.
local root = math.sqrt(81)

local quoted = "text\n"
local long = [[long string]]
local number = 0x2A + 1.5e2
local truth, empty = true, nil

for index = 1, 3 do
	if index % 2 == 0 or not empty then
		record:add(index)
	end
end

local result = deprecated_function(async_function(record.count))
abstract_function()
local state = DemoState.running
local generic_value = identity(state)

-- Diagnostics showcase.

local diagnostic_number = "not a number"

-- Warning: type mismatch
---@type integer
local must_be_integer = diagnostic_number

-- Warning: undefined global
demo_missing_global()

-- Hint: unused local
local unused_showcase = 123

-- Warning: missing required argument
record:add()

-- Warning: wrong argument type
record:add("wrong type")

-- Warning: undefined field
local missing_field = record.does_not_exist

-- Error: unresolved goto label
goto demo_missing_label

-- Keep showcase values referenced and diagnostics intentional.
return loaded, global_table, editor, string_table, table_table, math_table,
	quoted, long, number, truth, result, generic_value, readonly_by_convention, root, missing_field, must_be_integer
