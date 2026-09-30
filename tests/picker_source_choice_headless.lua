-- ./AppRun --headless -u NONE -i NONE --cmd 'cd cf.nvim' -l tests/picker_source_choice_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")
local api = vim.api
local theme = require("cf.theme")
local picker = require("cf.picker")
local menu = require("cf.menu")
local save = require("cf.save")
require("cf.config").setup({ picker = true })
picker.start()

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/dark", "p")
local function write(path, text)
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
end
local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end
local function key(s)
  api.nvim_feedkeys(api.nvim_replace_termcodes(s, true, false, true), "mx", false)
end
local function up(fn, name)
  for i = 1, 100 do
    local key_, value = debug.getupvalue(fn, i)
    if key_ == name then return value end
    if not key_ then break end
  end
  error("missing upvalue " .. name)
end

write(root .. "/.cf-theme", "dark\ndark")
write(root .. "/dark/color.cf", 'return { fg = "#aaccee" }')
local generic_path = root .. "/dark/generic.cf"
local lua_path = root .. "/dark/lang-lua.cf"
write(generic_path, [[
local h = require("cf.hl.setup")
local l = h.language
return l.setup(nil, {
  l:group("function", { fg = "#884422", types = { "method" } }),
})
]])
local lua_initial = [[
local h = require("cf.hl.setup")
local l = h.language
return l.setup("lua", {
  l:group("function", { fg = "#2288cc", types = { "method" } }),
})
]]
local lua_without_method = [[
local h = require("cf.hl.setup")
local l = h.language
return l.setup("lua", {
  l:group("function", { fg = "#2288cc" }),
})
]]
write(lua_path, lua_initial)
theme.load(root)
vim.bo.filetype = "lua"
vim.inspect_pos = function() return { treesitter = {}, syntax = {} } end
vim.lsp.semantic_tokens.get_at_pos = function()
  return { { type = "method", modifiers = {} } }
end

local open_pick = up(picker.open, "open_pick")
local open_edit = up(open_pick, "open_edit")
local items_at_cursor = up(picker.open, "items_at_cursor")

-- First edit uses the existing Lua inheritance and therefore needs no source choice.
local entry = items_at_cursor()[1]
local edit = open_edit(entry, { entry }, 1)
assert(edit.items[1] == "Pipeline" and edit.items[2] == "Style", "existing local Type unexpectedly asked for source")
key("j<CR><Space><CR>")
menu.close()
save.write(save.plan())
assert(read(lua_path):find('l:group("method"', 1, true), "initial local method was not detached into Lua")
theme.load(root)

-- Delete that detached Type by hand in the same session. Generic still resolves
-- the visible style, but both Lua and generic are now valid write destinations.
write(lua_path, lua_without_method)
theme.load(root)
entry = items_at_cursor()[1]
local choose = open_edit(entry, { entry }, 1)
assert(vim.deep_equal(choose.items, { "lua", "generic" }), "missing Lua/generic source choice")

-- Choosing Lua recreates a local group and leaves generic untouched.
key("<CR>")
key("j<CR><Space><CR>")
menu.close()
local plan = save.plan()
local local_file, generic_file
for _, file in ipairs(plan.files) do
  if file.path == lua_path then local_file = file end
  if file.path == generic_path then generic_file = file end
end
assert(local_file and local_file.content:find('l:group("method"', 1, true), "Lua choice did not create local method")
assert(not generic_file, "Lua choice also modified generic")
save.write(plan)

-- Return to the ambiguous state and choose generic this time.
write(lua_path, lua_without_method)
theme.load(root)
entry = items_at_cursor()[1]
choose = open_edit(entry, { entry }, 1)
assert(vim.deep_equal(choose.items, { "lua", "generic" }), "source choice disappeared after reload")
key("j<CR>") -- generic
key("j<CR><Space><CR>")
menu.close()
plan = save.plan()
local_file, generic_file = nil, nil
for _, file in ipairs(plan.files) do
  if file.path == lua_path then local_file = file end
  if file.path == generic_path then generic_file = file end
end
assert(generic_file, "generic choice did not edit generic source")
assert(not local_file, "generic choice unexpectedly created a Lua group")

-- With no language module there is no pointless source question: generic is
-- the only owner and opens the normal Edit menu directly.
vim.bo.filetype = "python"
entry = { kind = "Type", name = "method", type_name = "method", filetype = "python", bufnr = api.nvim_get_current_buf() }
edit = open_edit(entry, { entry }, 1)
assert(edit.items[1] == "Pipeline" and edit.items[2] == "Style", "generic-only Type asked for a language source")
menu.close()

-- With a language module but no generic/local declaration there is no fallback
-- to choose. A cursor-materialized Type is created directly in the language module.
vim.bo.filetype = "lua"
write(generic_path, [[
local h = require("cf.hl.setup")
local l = h.language
return l.setup(nil, {
  l:group("variable", { fg = "#884422" }),
})
]])
write(lua_path, lua_without_method)
theme.load(root)
api.nvim_set_hl(0, "@lsp.type.method.lua", { fg = 0x2288cc })
entry = items_at_cursor()[1]
edit = open_edit(entry, { entry }, 1)
assert(edit.items[1] == "Pipeline" and edit.items[2] == "Style", "missing Type incorrectly asked for generic fallback")
key("j<CR><Space><CR>")
menu.close()
plan = save.plan()
local_file, generic_file = nil, nil
for _, file in ipairs(plan.files) do
  if file.path == lua_path then local_file = file end
  if file.path == generic_path then generic_file = file end
end
assert(local_file and local_file.content:find('l:group("method"', 1, true), "missing Type was not created in Lua")
assert(not generic_file, "missing Type invented a generic fallback write")

picker.stop()
vim.fn.delete(root, "rf")
print("cf.nvim picker source choice tests: OK")
