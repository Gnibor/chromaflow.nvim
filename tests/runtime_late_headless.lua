vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")

local theme = require("cf.theme")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/only", "p")
vim.fn.mkdir(root .. "/runtime", "p")

local function write(path, data)
	local fd = assert(io.open(path, "wb"))
	assert(fd:write(data))
	fd:close()
end

write(root .. "/.cf-theme", "only\nonly\n")
write(root .. "/only/color.cf", [[ return { bg = "#101010", fg = "#6080a0" } ]])
write(root .. "/only/core.cf", [[
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui
return u.setup({ u:group("LateRuntimeThing", { fg = c.fg, bg = c.bg }) })
]])
write(root .. "/runtime/actions.cf", [[
local hl = require("cf.hl.setup")
local r = hl.runtime
return r.setup({ r:group("strong", { bold = true }) })
]])

-- Apply a theme before cf.fn.runtime has ever been required.
theme.load(root)
assert(package.loaded["cf.fn.runtime"] == nil, "runtime state loaded too early")

local hl = require("cf.hl.setup")
local r = hl.runtime("actions")
local target = hl.ui.LateRuntimeThing
r.apply(target, r.groups.strong)
local value = vim.api.nvim_get_hl(0, { name = "LateRuntimeThing", link = false, create = false })
assert(value.bold == true and value.fg ~= nil and value.bg ~= nil, "late runtime activation lost captured theme target/base")
r.reset(target)

vim.fn.delete(root, "rf")
print("cf.nvim late runtime tests: OK")
