vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cf = require("cf")
local color = require("cf.color")
local runtime = require("cf.hl.runtime")
local theme = require("cf.theme")

local root = vim.fs.joinpath(vim.fn.getcwd(), "example", "themes")
cf.setup({ theme_path = root, watch = false })

local compiled = assert(theme.current())
assert(compiled.default == "dark")
assert(compiled.active == "dark")

local normal = assert(runtime.group_style("Normal"), "bundled theme did not style Normal")
assert(normal.bg == color.from_hex("#0f121b"))
assert(normal.fg == color.from_hex("#cfcfcf"))

local fn = assert(runtime.group_style("Function"), "generic syntax module did not style Function")
assert(fn.fg == color.from_hex("#feac33"))

-- The Lua module is allowed to reuse the generic interned style. In that case
-- the resolver deliberately links the language-specific chain instead of
-- duplicating an identical direct style.
local lua_fn = vim.api.nvim_get_hl(0, { name = "luaFunction", link = true })
assert(lua_fn.link == "Function", "Lua Vim syntax form was not materialized")
local lua_ts = vim.api.nvim_get_hl(0, { name = "@function.lua", link = true })
assert(lua_ts.link == "luaFunction", "Lua Tree-sitter form was not materialized")
local lua_lsp = vim.api.nvim_get_hl(0, { name = "@lsp.type.function.lua", link = true })
assert(lua_lsp.link == "@function.lua", "Lua LSP form was not materialized")

local raw_keyword = assert(runtime.group_style("@keyword.function.lua"), "Lua raw capture missing")
assert(raw_keyword.bold == true)

print("cf.nvim bundled dark theme tests: OK")
