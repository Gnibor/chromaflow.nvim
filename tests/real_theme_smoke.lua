vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cf = require("cf")
local color = require("cf.color")
local theme = require("cf.theme")

local root = vim.fs.joinpath(vim.fn.getcwd(), "examples", "themes")
cf.setup({ theme_path = root, watch = false })
local compiled = assert(theme.current())
local actions = 0
for i = 1, #compiled.modules do actions = actions + #compiled.modules[i].actions end
assert(#compiled.modules >= 20, "large test theme compiled too few modules")
assert(actions >= 250, "large test theme compiled too few actions: " .. actions)

local function effective(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end
local function rgb(value)
	return tonumber(color.to_rgb_hex(value):sub(2), 16)
end

local normal = effective("Normal")
assert(normal.bg == rgb(compiled.colors.bg) and normal.fg == rgb(compiled.colors.fg), "real theme did not apply Normal")
assert(effective("@function.lua").fg ~= nil, "real theme did not materialize Lua semantic highlights")
assert(effective("@lsp.type.variable.lua").fg ~= nil, "real theme did not materialize Lua LSP highlights")
assert(effective("DiagnosticError").fg ~= nil, "real theme lost builtin diagnostic highlights")

print(("cf.nvim real theme smoke: %d modules / %d actions: OK"):format(#compiled.modules, actions))
