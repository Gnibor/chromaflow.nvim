-- ./AppRun --headless -u NONE -i NONE --cmd 'cd cf.nvim' -l tests/picker_mods_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")
local api = vim.api
local theme = require("cf.theme")
local picker = require("cf.picker")
local runtime = require("cf.fn.runtime")
local menu = require("cf.menu")
require("cf.config").setup({ picker = true })
picker.start()

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/dark", "p")
local function write(path, text) vim.fn.writefile(vim.split(text, "\n", { plain = true }), path) end
write(root .. "/.cf-theme", "dark\ndark")
write(root .. "/dark/color.cf", 'return { bg = "#101010", fg = "#aaccee" }')
-- Same filetype, earlier module, but not the owner of the picked variable.
-- A separate "first matching language module" fallback would write here.
write(root .. "/dark/aaa-decoy.cf", [[
local h = require("cf.hl.setup")
return h.language.setup("lua", { h.language:group("number", { fg = "#123456" }) })
]])
write(root .. "/dark/lua.cf", [[
local h = require("cf.hl.setup")
local l = h.language
return l.setup("lua", {
  mods = {
    readonly = { italic = true } -- no trailing comma; preserve this comment
  },
  l:group("variable", {
    fg = h.colors.fg,
    typemods = { readonly = true, static = false, async = { bold = true } },
  }),
})
]])
write(root .. "/dark/generic.cf", [[
local h = require("cf.hl.setup")
return h.language.setup(nil, { h.language:group("variable", { fg = "#ff0000" }) })
]])
write(root .. "/dark/python.cf", [[
local h = require("cf.hl.setup")
return h.language.setup("python", { h.language:group("variable", { fg = "#00ff00" }) })
]])
local compiled = theme.load(root)
vim.bo.filetype = "lua"
local buf = api.nvim_get_current_buf()

local function up(fn, name)
  for i = 1, 100 do
    local key, value = debug.getupvalue(fn, i)
    if key == name then return value end
    if not key then break end
  end
  error("missing upvalue " .. name)
end
local open_pick = up(picker.open, "open_pick")
local open_edit = up(open_pick, "open_edit")
local open_mods = up(open_edit, "open_typemods")
local available = up(open_mods, "session_typemods")

local function entry()
  return { kind = "Type", name = "variable", type_name = "variable", filetype = "lua", bufnr = buf }
end
api.nvim_set_hl(0, "@lsp.typemod.variable.sessionOnly.lua", { italic = true })
api.nvim_set_hl(0, "@lsp.mod.sessionOnly", { italic = true })
api.nvim_set_hl(0, "@lsp.typemod.variable.foreignOnly.python", { italic = true })
api.nvim_set_hl(0, "@lsp.typemod.function.otherType.lua", { italic = true })
api.nvim_set_hl(0, "@lsp.mod.freshMod.lua", { italic = true })
api.nvim_set_hl(0, "@variable.documentation.lua", { italic = true })
api.nvim_set_hl(0, "@lsp.typemod.variable.end.lua", { italic = true })
api.nvim_set_hl(0, "@lsp.mod.end", { italic = true })
api.nvim_set_hl(0, "@variable.lua", { fg = 0xaaccee })
local before = api.nvim_get_hl(0, {})
local found = {}
for _, row in ipairs(available(entry())) do found[row.name] = row end
assert(found.sessiononly and found.documentation, "session-only modifiers missing")
assert(not found.foreignonly and not found.othertype, "foreign type/filetype leaked")
assert(not found.lua, "filetype suffix was treated as a modifier")
assert(not found.madeup, "fabricated modifier")
assert(vim.deep_equal(before, api.nvim_get_hl(0, {})), "discovery materialized highlights")
api.nvim_set_hl(0, "@lsp.typemod.variable.latearrival.lua", { bold = true })
local late = false
for _, row in ipairs(available(entry())) do if row.name == "latearrival" then late = true end end
assert(late, "menu reused a stale session catalogue")

local function key(k) api.nvim_feedkeys(api.nvim_replace_termcodes(k, true, false, true), "mx", false) end
-- CFPick retains the original cursor-derived axes even if no concrete
-- highlight/declaration exists yet. Only Type -> TypeMods scans the catalogue.
local old_tokens, old_inspect = vim.lsp.semantic_tokens.get_at_pos, vim.inspect_pos
vim.inspect_pos = function() return { treesitter = {}, syntax = {} } end
vim.lsp.semantic_tokens.get_at_pos = function()
  return { { type = "variable", modifiers = { cursorOnly = true } } }
end
api.nvim_set_hl(0, "@lsp.typemod.variable.cursoronly.lua", { fg = 0xaaccee })
local picked = picker.open()
assert(vim.deep_equal(picked.items, {
  "Type     variable", "Mod      cursoronly", "TypeMod  variable.cursoronly",
}), "CFPick cursor resolution differs from the original")
menu.close()
vim.lsp.semantic_tokens.get_at_pos, vim.inspect_pos = old_tokens, old_inspect

local parent = entry()
local opened = open_mods(parent, { parent }, 1)
assert(parent.action._cf_owner_name == "lua", "picker chose another scope in the float")
local function select_row(handle, token)
  local chosen
  for i, text in ipairs(handle.items) do
    if text:match("^...([^ ]+)") == token then chosen = i; break end
  end
  assert(chosen, "missing row " .. token .. ": " .. vim.inspect(handle.items))
  for _ = 1, #handle.items do key("k") end
  for _ = 2, chosen do key("j") end
  return chosen
end
local i = select_row(opened, "sessiononly")
key("=")
assert(opened.items[i]:sub(1,1) == "=", "same-as-type marker missing")
assert(api.nvim_get_hl(0, { name = "@lsp.typemod.variable.sessionOnly.lua", link = false }).fg == 0xaaccee,
  "same-as-type preview not applied")
key("x")
assert(opened.items[i]:sub(1,1) == "x", "exclude marker missing")
key("x")
assert(opened.items[i]:sub(1,1) == " ", "exclude did not toggle off")
key("=")
select_row(opened, "end")
key("x")
select_row(opened, "readonly")
key("=") -- existing true -> unset
key("<BS>")
menu.close()
local save = require("cf.save")
local plan = save.plan()
assert(plan.count == 3, "rule save lost edits")
save.write(plan)
local text = table.concat(vim.fn.readfile(root .. "/dark/lua.cf"), "\n")
assert(text:find("sessiononly = true",1,true), "new TypeMod rule not saved")
assert(text:find('["end"] = false',1,true), "keyword TypeMod not quoted")
assert(not text:find("readonly = true",1,true), "removed rule remains in source")
compiled = theme.load(root)

-- Convert an excluded TypeMod into its own style. Preview and saved result
-- must both inherit the finished Type, not leave a colourless temporary style.
parent = entry()
opened = open_mods(parent, { parent }, 1)
select_row(opened, "static")
key("<CR>") -- existing TypeMod Edit menu
key("j")
key("<CR>") -- Style
key("<Space>") -- bold
assert(api.nvim_get_hl(0, { name = "@lsp.typemod.variable.static.lua", link = false }).fg == 0xaaccee,
  "TypeMod style preview lost parent colour")
key("<CR>")
key("<BS>") -- TypeMods
menu.close()
plan = save.plan()
save.write(plan)
theme.load(root)
assert(api.nvim_get_hl(0, { name = "@lsp.typemod.variable.static.lua", link = false }).bold == true,
  "TypeMod=false to style did not survive reload")

-- Existing Mod -> Style uses the original action/source path. No second
-- session discovery, synthetic Mod target or module-selection fallback.
vim.inspect_pos = function() return { treesitter = {}, syntax = {} } end
vim.lsp.semantic_tokens.get_at_pos = function()
  return { { type = "variable", modifiers = { readonly = true } } }
end
picked = picker.open()
assert(picked.items[2] == "Mod      readonly", "cursor Mod missing")
key("j")
key("<CR>")
key("j")
key("<CR>")
key("<Space>")
key("<CR>")
menu.close()
save.write(save.plan())
text = table.concat(vim.fn.readfile(root .. "/dark/lua.cf"), "\n")
assert(text:find("preserve this comment", 1, true), "Mod edit lost source comment")
theme.load(root)
assert(runtime._picker_style_state(runtime.target("language", "lua", nil, "readonly")).current.bold == true,
  "existing Mod style did not survive reload")
assert(not table.concat(vim.fn.readfile(root .. "/dark/aaa-decoy.cf"), "\n"):find("bold", 1, true),
  "Style wrote to a different module")
-- A new module Mod inherits the picked Type's source owner, not the first
-- matching language module (aaa-decoy.cf has the same language).
api.nvim_set_hl(0, "@lsp.mod.declaration.lua", {})
vim.lsp.semantic_tokens.get_at_pos = function()
  return { { type = "variable", modifiers = { declaration = true } } }
end
picker.open()
key("j<CR>j<CR><Space><CR>")
menu.close()
plan = save.plan()
assert(plan.count > 0, "new declaration Mod did not open Style")
save.write(plan)
text = table.concat(vim.fn.readfile(root .. "/dark/lua.cf"), "\n")
assert(text:find("declaration = { bold = true }", 1, true), "new Mod not written to picked Type module")
assert(not table.concat(vim.fn.readfile(root .. "/dark/aaa-decoy.cf"), "\n"):find("declaration", 1, true),
  "new Mod used another module")
theme.load(root)
assert(runtime._picker_style_state(runtime.target("language", "lua", nil, "declaration")).current.bold == true,
  "new declaration Mod did not survive reload")

-- Direct cursor selection must be just as editable as Type -> TypeMods. This
-- combination exists in the live semantic token stream but not in source yet.
vim.lsp.semantic_tokens.get_at_pos = function()
  return { { type = "variable", modifiers = { cursorOnly = true } } }
end
api.nvim_set_hl(0, "@lsp.typemod.variable.cursoronly.lua", { fg = 0xaaccee })
picker.open()
key("jj<CR>j<CR><Space><CR>")
menu.close()
plan = save.plan()
assert(plan.count > 0, "cursor-only TypeMod did not produce a save edit")
save.write(plan)
text = table.concat(vim.fn.readfile(root .. "/dark/lua.cf"), "\n")
assert(text:find("cursoronly = { bold = true }", 1, true), "missing cursor TypeMod source was not created")
theme.load(root)
assert(runtime._picker_style_state(runtime.target("language", "lua", "variable", "cursoronly")).current.bold == true,
  "created cursor TypeMod style did not survive reload")
vim.lsp.semantic_tokens.get_at_pos, vim.inspect_pos = old_tokens, old_inspect
menu.close()
picker.stop()
vim.fn.delete(root, "rf")
print("cf.nvim session Mod/TypeMod menu tests: OK")
