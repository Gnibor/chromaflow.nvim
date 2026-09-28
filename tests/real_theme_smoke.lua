vim.opt.runtimepath:prepend(vim.fn.getcwd())
local theme = require('cf.theme')
local runtime = require('cf.hl.runtime')
local color = require('cf.color')
local root = vim.fs.joinpath(vim.fn.getcwd(), 'example', 'themes')
local compiled = theme.load(root)
local actions = 0
for i = 1, #compiled.modules do
  actions = actions + #compiled.modules[i].actions
end
assert(#compiled.modules >= 20, 'large test theme compiled too few modules')
assert(actions >= 250, 'large test theme compiled too few actions: ' .. actions)
local normal = assert(runtime.group_style('Normal'))
assert(normal.bg == color.from_hex('#0f121b'))
assert(vim.api.nvim_get_hl(0, {name='ITHActive', link=true}).fg ~= nil)
assert(vim.api.nvim_get_hl(0, {name='RenderMarkdownCode', link=true}).bg ~= nil)
assert(vim.api.nvim_get_hl(0, {name='DiagnosticError', link=true}).fg ~= nil)
print(('cf.nvim real theme smoke: %d modules / %d actions: OK'):format(#compiled.modules, actions))
