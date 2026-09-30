vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cf = require("cf")
local color = require("cf.color")
local theme = require("cf.theme")

local root = vim.fs.joinpath(vim.fn.getcwd(), "examples", "themes")
cf.setup({ theme_path = root, watch = false })

local compiled = assert(theme.current())
assert(compiled.default == "dark")
assert(compiled.active == "dark")
local c = compiled.colors

local function effective(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end

local function direct(name)
	return vim.api.nvim_get_hl(0, { name = name, link = true, create = false })
end

local function rgb(value)
	if type(value) == "string" then return tonumber(value:sub(2), 16) end
	return tonumber(color.to_rgb_hex(value):sub(2), 16)
end

local normal = effective("Normal")
assert(normal.bg == rgb("#0f121b"))
assert(normal.fg == rgb("#cfcfcf"))

local generic_function = color.darken(c.func, 3)
assert(effective("Function").fg == rgb(generic_function), "generic Function style drifted")

-- Lua intentionally overrides the generic function pipeline. The resolver still
-- keeps the semantic source chain LSP -> Tree-sitter -> Vim syntax intact.
local lua_function = color.brightness(color.shiftHue(c.func, -5), 20)
assert(effective("luaFunction").fg == rgb(lua_function), "Lua function pipeline was not applied")
assert(direct("@function.lua").link == "luaFunction", "Lua Tree-sitter form did not link to Vim syntax")
assert(direct("@lsp.type.function.lua").link == "@function.lua", "Lua LSP form did not link to Tree-sitter")

local keyword_function = effective("@keyword.function.lua")
assert(keyword_function.bold == true, "Lua keyword.function capture lost its bold style")

print("cf.nvim bundled dark theme tests: OK")
