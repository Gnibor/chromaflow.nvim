-- Run using the portable AppRun, from cf.nvim. Exercises real floats/mappings,
-- palette selection, sparse preview, source persistence and reload.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")
local api = vim.api
local theme, picker = require("cf.theme"), require("cf.picker")
local runtime, menu = require("cf.fn.runtime"), require("cf.menu")
require("cf.config").setup({ picker = true })
picker.start()
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/dark", "p")
local function write(path, text) vim.fn.writefile(vim.split(text, "\n", { plain = true }), path) end
write(root .. "/.cf-theme", "dark\ndark")
write(root .. "/dark/color.cf", 'return { bg = "#202020", fg = "#aaccee", red = "#cc4422", nested = { accent = "#00ff88" } }')
local path = root .. "/dark/lua.cf"
write(path, [[
local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language
return l.setup("lua", {
 mods = { readonly = { fg = c.fg, pipeline = { hl.darken.fg(10) } } },
 l:group("variable", {
  fg = c.fg, bg = c.bg, italic = true,
  pipeline = {
   hl.darken.bg(5), -- preserve order and comment
   hl.opacity.fg(80),
   hl.gamma.fg(
    1.1 -- preserve function range comment
   ),
  },
  typemods = { static = true, readonly = { pipeline = { hl.lighten.fg(5) } } },
 }),
 l:group("function", {
  fg = c.red, bg = c.bg, italic = true, types = { "method", "macro" },
  pipeline = { hl.darken.fg(12) },
 }),
})
]])
theme.load(root)
vim.bo.filetype = "lua"
vim.o.columns = math.max(120, vim.o.columns)
local old_tokens, old_inspect, old_menu = vim.lsp.semantic_tokens.get_at_pos, vim.inspect_pos, menu.open
local current_menu
menu.open = function(opts) current_menu = opts; return old_menu(opts) end
vim.inspect_pos = function() return { treesitter = {}, syntax = {} } end
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "variable", modifiers = {} } } end
local function key(s) api.nvim_feedkeys(api.nvim_replace_termcodes(s, true, false, true), "mx", false) end
local function title() return api.nvim_win_get_config(0).title end
local function select(label)
 local found
 for i, item in ipairs(current_menu.items) do if item == label then found = i end end
 assert(found, "missing menu item " .. label .. " in " .. vim.inspect(current_menu.items))
 for _ = 1, #current_menu.items do key("k") end
 for _ = 2, found do key("j") end
 key("<CR>")
end
local target = runtime.target("language", "lua", "variable", nil)
local function state() return runtime._picker_style_state(target, false) end
local function open()
 picker.open(); key("<CR><CR>")
 assert(vim.inspect(title()):find("Pipeline: variable", 1, true), "pipeline did not open: " .. vim.inspect(title()))
end
local function text()
 local out = {}
 for _, marks in pairs(api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
  for _, span in ipairs(marks[4].virt_text or {}) do out[#out + 1] = span[1] end
 end
 return table.concat(out, " ")
end
local original = state().current
open()
local pipeline_ns = assert(api.nvim_get_namespaces()["cf.picker.pipeline"], "pipeline highlight namespace missing")
local marked = false
for _, mark in ipairs(api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
 for _, span in ipairs(mark[4].virt_text or {}) do
  if span[2] == "Visual" then marked = true end
 end
end
assert(marked, "pipeline active cell does not use the same Visual marking as other menus")
assert(vim.o.guicursor:find("a:NormalFloat", 1, true), "pipeline cursor is visible instead of blending into NormalFloat")
local base_swatch = api.nvim_get_hl(pipeline_ns, { name = "CFPipeIn2_1", link = false, create = false })
assert(base_swatch.fg ~= nil and base_swatch.bg == base_swatch.fg, "Base colour swatch is not visible")
-- Pipeline cells must not paint a blank background span over their own label/swatch.
for row = 0, 2 do
 local ranges = {}
 for _, mark in ipairs(api.nvim_buf_get_extmarks(0, -1, { row, 0 }, { row, -1 }, { details = true })) do
  local col = mark[4].virt_text_win_col
  local vt = mark[4].virt_text
  if col and vt and vt[1] and vt[1][1] ~= "" then
   local last = col + vim.fn.strdisplaywidth(vt[1][1])
   ranges[#ranges + 1] = { col, last, vt[1][1] }
  end
 end
 table.sort(ranges, function(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end)
 for i = 2, #ranges do
  assert(ranges[i][1] >= ranges[i - 1][2], "pipeline render has overlapping spans: " .. vim.inspect({ ranges[i - 1], ranges[i] }))
 end
end
assert(text():find("c.fg", 1, true) and text():find("c.bg", 1, true), "pipeline colours are not rendered")
assert(not text():find("Base", 1, true), "pipeline still renders the redundant Base label")

-- Swatches are two cells each: input + output = four visible colour cells.
local swatch_spans = {}
for _, mark in ipairs(api.nvim_buf_get_extmarks(0, -1, { 1, 0 }, { 1, -1 }, { details = true })) do
 local vt = mark[4].virt_text
 if vt and vt[1] and (vt[1][1] == "██") then swatch_spans[#swatch_spans + 1] = vt[1][1] end
end
assert(#swatch_spans >= 2, "Base input/output swatches are not rendered as two cells each")
local dot_placeholder = false
for _, mark in ipairs(api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
 local vt = mark[4].virt_text
 if vt and vt[1] and vt[1][1] == "·" then dot_placeholder = true end
end
assert(not dot_placeholder, "inactive pipeline cells still render dot placeholders")
assert(text():find("unset", 1, true) and text():find("[from FG]", 1, true), "unset/fallback UI missing")
assert(not state().has_runtime, "opening editor changed runtime")
key("3<CR>") -- unset SP base: active palette only
assert(#current_menu.items == 4, "palette did not flatten exactly the active colours")
select("██ c.nested.accent")
assert(state().current.sp == 0xff00ff88, "SP palette did not activate channel")
key("q")
assert(not state().has_runtime and state().current == original, "cancel failed to restore exact state")

-- Existing interleaved operations: change one parameter and cancel.
open(); key("j+")
assert(state().has_runtime, "parameter change had no preview")
key("<BS>")
assert(current_menu.title == " Edit: variable ", "Back did not return to Edit")
assert(not state().has_runtime, "Back did not discard preview")
menu.close()

-- Base selection, gamma hundredths, a new cterm pipeline and unset SP.
open(); key("<CR>"); select("██ c.red")
key("jj+") -- gamma 1.10 -> 1.11
key("3<CR>"); select("██ c.nested.accent")
key("4<CR>"); select("██ c.fg")
key("jn"); select("brightness")
key("<M-->")
key("a")
local preview = state().current
assert(preview.sp == 0xff00ff88 and preview.ctermfg ~= nil, "five-channel preview failed")
assert(preview.italic == true, "pipeline preview lost Style")
local save = require("cf.save")
local plan = save.plan()
assert(plan.count == 1, "pipeline edit missing from CFSave")
assert(loadstring(plan.files[1].content), "pipeline generated invalid Lua")
local first_pipeline_line = plan.files[1].content:match("pipeline = {\n([^\n]+)")
assert(first_pipeline_line and first_pipeline_line:match("^   [^ ]"), "pipeline steps lost one indentation level: " .. vim.inspect(first_pipeline_line))
assert(plan.files[1].content:find("\n  },", 1, true), "pipeline closing brace is not aligned with its field")
assert(plan.files[1].content:find("preserve order and comment", 1, true), "pipeline lost comment")
assert(plan.files[1].content:find("1.11 -- preserve function range comment", 1, true), "gamma did not preserve traced function text")
assert(plan.files[1].content:find("to_cterm", 1, true), "cterm base not serialized as conversion")
save.write(plan)
theme.load(root)
local traced_cfg = false
for _, record in ipairs(require("cf.colortrace")._cached(path, theme.current()).records) do
 if record.trace.name == "brightness" and record.trace.channel == "cfg" then traced_cfg = true end
end
assert(traced_cfg, "new persisted operations bypassed the shared Colortrace path")
for _, field in ipairs({ "fg", "bg", "sp", "ctermfg", "ctermbg", "italic" }) do
 assert(state().current[field] == preview[field], "save/reload differs from preview for " .. field)
end

-- Reopening/confirming without any changes does not write inherited bases.
menu.close(); open(); key("a"); menu.close()
assert(save.plan().count == 0, "unchanged pipeline planned a write")

-- A TypeMod=true starts at the finished parent colour, with no own pipeline.
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "variable", modifiers = { static = true } } } end
picker.open(); select("TypeMod  variable.static"); select("Pipeline")
assert(text():find("inherited", 1, true), "TypeMod inheritance marker missing")
key("jn"); select("darken"); key("a"); menu.close()
local tm = runtime.target("language", "lua", "variable", "static")
local tm_preview = runtime._picker_style_state(tm, false).current
plan = save.plan(); save.write(plan)
local saved = table.concat(vim.fn.readfile(path), "\n")
assert(saved:find("static = { pipeline", 1, true), "TypeMod inheritance was baked into an explicit base")
theme.load(root)
assert(runtime._picker_style_state(tm, false).current.fg == tm_preview.fg, "TypeMod inherited pipeline drift after reload")

-- Existing Mod pipelines use the original module spec, not the finished style
-- as input (which would apply the old operation twice).
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "variable", modifiers = { readonly = true } } } end
picker.open(); select("Mod      readonly"); select("Pipeline"); key("j+a"); menu.close()
local mod = runtime.target("language", "lua", nil, "readonly")
local mod_preview = runtime._picker_style_state(mod, false).current
save.write(save.plan()); theme.load(root)
assert(runtime._picker_style_state(mod, false).current.fg == mod_preview.fg, "Mod preview compounded its pipeline")

-- Insert mix before an existing FG operation, edit its palette reference,
-- remove another operation, and keep unrelated BG/CFG order intact.
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "variable", modifiers = {} } } end
open(); key("jn"); select("mix")
assert(vim.wait(200, function() return current_menu.title:find("Palette", 1, true) ~= nil end), "mix palette did not open")
select("██ c.nested.accent")
key("+")
key("<CR>"); select("██ c.red")
key("jd") -- remove old opacity, preserve gamma and BG/CFG operations
key("a"); menu.close()
preview = state().current
plan = save.plan()
local output = plan.files[1].content
local bg_at = assert(output:find("hl.darken.bg(5)", 1, true))
local mix_at = assert(output:find('.mix.fg(31, c.red)', 1, true))
local gamma_at = assert(output:find("hl.gamma.fg(", 1, true))
assert(bg_at < mix_at and mix_at < gamma_at, "UI columns reordered the global pipeline")
assert(not output:find("hl.opacity.fg", 1, true), "operation deletion was not saved")
save.write(plan); theme.load(root)
assert(state().current.fg == preview.fg, "mix/delete save differs from preview")

-- Reopen a committed but unsaved draft, adjust again, then save it together
-- with a Style edit from the same declaration.
open(); key("j+a"); menu.close()
open(); key("j+a"); menu.close()
picker.open(); key("<CR>"); select("Style"); key("<Space><CR>"); menu.close()
preview = state().current
save.write(save.plan()); theme.load(root)
assert(state().current.fg == preview.fg and state().current.bold == true, "Style/Pipeline joint save lost edits")

-- A Mod with no source rule yet receives its own palette base/pipeline.
api.nvim_set_hl(0, "@lsp.mod.declaration.lua", {})
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "variable", modifiers = { declaration = true } } } end
picker.open(); select("Mod      declaration"); select("Pipeline")
key("<CR>"); select("██ c.red")
key("jn"); select("lighten"); key("a"); menu.close()
local newmod = runtime.target("language", "lua", nil, "declaration")
local new_preview = runtime._picker_style_state(newmod, false).current
save.write(save.plan()); theme.load(root)
assert(runtime._picker_style_state(newmod, false).current.fg == new_preview.fg, "new Mod pipeline did not persist")

-- Pending '=' removes the old own pipeline. Editing afterwards must not
-- resurrect it, nor lose the inherited parent flags during preview/save.
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "variable", modifiers = {} } } end
picker.open(); key("<CR>"); select("TypeMods")
local readonly_row
for i, label in ipairs(current_menu.items) do if label:match("^...readonly%s") then readonly_row = i end end
assert(readonly_row)
for _ = 2, readonly_row do key("j") end
key("=<CR>"); select("Pipeline")
assert(not text():find("lighten 5", 1, true), "pending '=' kept old TypeMod pipeline")
key("jn"); select("darken"); key("a"); menu.close()
local qualified = runtime.target("language", "lua", "variable", "readonly")
local qualified_preview = runtime._picker_style_state(qualified, false).current
save.write(save.plan()); theme.load(root)
local qualified_saved = runtime._picker_style_state(qualified, false).current
assert(qualified_saved.fg == qualified_preview.fg and qualified_saved.italic == qualified_preview.italic,
 "pending rule followed by pipeline differed after reload")

-- A Type supplied only through another group's `types` keeps its own semantic
-- identity. The parent's finished result is only the inherited colour row; the
-- parent pipeline is not exposed as the child's pipeline. Editing detaches the
-- Type into its own group and removes only that name from the parent `types`.
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "method", modifiers = {} } } end
local method = runtime.target("language", "lua", "method", nil)
local method_base = runtime._picker_style_state(method, false).base
picker.open(); key("<CR><CR>")
assert(vim.inspect(title()):find("Pipeline: method", 1, true), "inherited method was redirected to its parent")
assert(text():find("inherited", 1, true), "inherited Type colour row has no origin marker")
assert(text():find(require("cf.color").to_hex(method_base.fg), 1, true), "inherited Type did not use the parent's finished colour")
assert(not text():find("darken 12", 1, true), "parent pipeline leaked into inherited child pipeline")
key("jn"); select("lighten"); key("a"); menu.close()
local method_preview = runtime._picker_style_state(method, false).current
plan = save.plan()
local detached = plan.files[1].content
assert(detached:find('l:group("method"', 1, true), "pipeline edit did not create an own method group")
assert(detached:match('types%s*=%s*{%s*"macro"%s*}'), "method was not removed from parent types without disturbing siblings")
assert(detached:find("hl.darken.fg(12)", 1, true), "detaching method modified the parent pipeline")
assert(detached:find("hl.lighten.fg(5)", 1, true), "detached method pipeline was not serialized")
save.write(plan); theme.load(root)
assert(runtime._picker_style_state(method, false).current.fg == method_preview.fg, "detached method pipeline differs after reload")

-- Style editing follows the same inheritance rule. It freezes the finished
-- parent style into a new child group instead of rewriting the parent's group.
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "macro", modifiers = {} } } end
local macro = runtime.target("language", "lua", "macro", nil)
local macro_before = runtime._picker_style_state(macro, false).current
picker.open(); key("<CR>"); select("Style"); key("<Space><CR>"); menu.close()
local macro_preview = runtime._picker_style_state(macro, false).current
plan = save.plan(); detached = plan.files[1].content
assert(detached:find('l:group("macro"', 1, true), "Style edit did not detach inherited macro")
assert(not detached:find('types = { "macro" }', 1, true), "last inherited Type was not removed from parent types")
save.write(plan); theme.load(root)
local macro_saved = runtime._picker_style_state(macro, false).current
assert(macro_saved.fg == macro_before.fg and macro_saved.bold == macro_preview.bold, "detached Style lost inherited colour or edit")

-- File changes after opening are detected before overwriting external edits.
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "variable", modifiers = {} } } end
open(); key("j+a"); menu.close()
local unchanged = table.concat(vim.fn.readfile(path), "\n")
write(path, unchanged .. "\n-- external change")
assert(not pcall(save.plan), "save overwrote a changed pipeline source")
assert(table.concat(vim.fn.readfile(path), "\n"):find("external change", 1, true))
theme.load(root)

-- A reload invalidates an open transaction instead of restoring stale colours.
vim.lsp.semantic_tokens.get_at_pos = function() return { { type = "variable", modifiers = {} } } end
open(); key("j+"); theme.load(root); key("q")
assert(not state().has_runtime, "old pipeline transaction survived reload")
menu.close()
menu.open, vim.inspect_pos, vim.lsp.semantic_tokens.get_at_pos = old_menu, old_inspect, old_tokens
picker.stop()
vim.fn.delete(root, "rf")
print("cf.nvim five-channel pipeline picker tests: OK")
