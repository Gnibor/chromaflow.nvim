-- From the cf.nvim directory:
-- /path/to/neovim-portable/AppRun --headless -u NONE -l tests/lsd_demo_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")

local theme = require("cf.theme")
local color = require("cf.color")
local root = vim.fn.getcwd() .. "/examples/themes"

theme.load(root)
dofile(vim.fn.getcwd() .. "/examples/showcase/lsd.lua")

assert(vim.fn.exists(":LSD") == 2, ":LSD demo command was not registered")

local function style(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
end

local before = style("@variable.lua").fg
local function_before = style("@function.lua").fg
vim.cmd("LSD")
local first = style("@variable.lua").fg
local function_first = style("@function.lua").fg
assert(first ~= nil and first ~= before, ":LSD did not apply the first runtime frame")
assert(function_first ~= nil and function_first ~= first, ":LSD types did not start on different colours")

local advanced = vim.wait(500, function()
	return style("@variable.lua").fg ~= first
end, 10)
assert(advanced, ":LSD colourfade did not advance")

vim.cmd("LSD")
local restored = style("@variable.lua").fg
local function_restored = style("@function.lua").fg
assert(restored == before, ":LSD did not restore the theme base")
assert(function_restored == function_before, ":LSD did not restore the function base")

local r = require("cf.hl.setup").runtime("lsd")
assert(r.g == r.groups, "runtime short group namespace alias changed")
assert(color.to_hex(first) ~= nil)

print("cf.nvim LSD demo tests: OK")
