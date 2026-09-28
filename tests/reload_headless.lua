vim.opt.runtimepath:prepend(vim.fn.getcwd())

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/dark", "p")

local function write(path, data)
	local fd = assert(io.open(path, "wb"))
	fd:write(data)
	fd:close()
end

write(root .. "/.cf-theme", "dark\ndark\n")
write(root .. "/dark/color.cf", [[
return {
	fg = "#aabbcc",
	bg = "#101018",
}
]])
write(root .. "/dark/config.cf", [[return {}]])
write(root .. "/dark/ui.cf", [[
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui
local raw = hl.raw

return u.setup({
	u:group("Normal", { fg = c.fg, bg = c.bg }),
	raw:group("CFReloadProbe", { fg = c.fg, bold = true }),
	raw:group("CFStaleProbe", { fg = c.fg }),
})
]])

local events = {}
vim.api.nvim_create_autocmd("ColorSchemePre", {
	pattern = "dark",
	callback = function(ev)
		events[#events + 1] = "pre:" .. ev.match
	end,
})
vim.api.nvim_create_autocmd("ColorScheme", {
	pattern = "dark",
	callback = function(ev)
		events[#events + 1] = "post:" .. ev.match
	end,
})

-- Give the reload path one active Tree-sitter consumer without depending on a
-- parser being installed in the standalone test image. The refresh code must
-- preserve the parser language rather than deriving it again from filetype.
local ts = vim.treesitter
local active = ts.highlighter.active
local buf = vim.api.nvim_get_current_buf()
local fake_highlighter = {
	tree = {
		lang = function()
			return "lua"
		end,
	},
}
local old_ts_stop = ts.stop
local old_ts_start = ts.start
local ts_stop_count = 0
local ts_start_count = 0
local ts_last_lang
active[buf] = fake_highlighter

ts.stop = function(target)
	ts_stop_count = ts_stop_count + 1
	active[target] = nil
end

ts.start = function(_target, lang)
	ts_start_count = ts_start_count + 1
	ts_last_lang = lang
end

local semantic = vim.lsp.semantic_tokens
local old_force_refresh = semantic.force_refresh
local lsp_refresh_count = 0
semantic.force_refresh = function(target)
	assert(target == nil, "semantic-token reload should refresh all active buffers")
	lsp_refresh_count = lsp_refresh_count + 1
end

local cf = require("cf")
local runtime = require("cf.hl.runtime")
local color = require("cf.color")

cf.setup({
	theme_path = root,
	watch = false,
	autoreload = { lsp = true, treesitter = true },
})

assert(events[1] == "pre:dark" and events[2] == "post:dark", "initial colorscheme lifecycle order is wrong")
assert(vim.g.colors_name == "dark", "selected CF theme was not exposed as colors_name")
assert(ts_stop_count == 1 and ts_start_count == 1, "Tree-sitter was not refreshed after initial apply")
assert(ts_last_lang == "lua", "Tree-sitter parser language was not preserved")
assert(lsp_refresh_count == 1, "LSP semantic tokens were not refreshed after initial apply")

local expected_style = assert(runtime.group_style("CFReloadProbe"), "reload probe style missing")
local expected_fg = color.from_hex("#aabbcc")
assert(expected_style.fg == expected_fg, "reload probe compiled with wrong style")

-- Simulate external/highlighter state drifting away from CF while CF's own
-- direct-style cache still points at the interned style object. A real reload
-- must invalidate materialization state and write the style again.
vim.api.nvim_set_hl(0, "CFReloadProbe", { fg = "#112233" })
local drifted = vim.api.nvim_get_hl(0, { name = "CFReloadProbe", link = false })
assert(drifted.fg == 0x112233, "failed to seed external highlight drift")

-- Also remove one declaration. highlight clear must prevent groups from a
-- previous compile surviving just because the new theme no longer mentions it.
write(root .. "/dark/ui.cf", [[
local hl = require("cf.hl.setup")
local c = hl.colors
local u = hl.ui
local raw = hl.raw

return u.setup({
	u:group("Normal", { fg = c.fg, bg = c.bg }),
	raw:group("CFReloadProbe", { fg = c.fg, bold = true }),
})
]])

active[buf] = fake_highlighter
cf.reload()

assert(events[3] == "pre:dark" and events[4] == "post:dark", "reload colorscheme lifecycle order is wrong")
assert(ts_stop_count == 2 and ts_start_count == 2, "Tree-sitter was not refreshed on reload")
assert(ts_last_lang == "lua", "Tree-sitter language changed during reload")
assert(lsp_refresh_count == 2, "LSP semantic tokens were not refreshed on reload")

local restored = vim.api.nvim_get_hl(0, { name = "CFReloadProbe", link = false })
assert(restored.fg == 0xaabbcc and restored.bold == true, "full reload skipped an unchanged cached style")
assert(runtime.group_style("CFReloadProbe") == expected_style, "session style interning did not survive full reload")
assert(runtime.group_style("CFStaleProbe") == nil, "removed declaration survived in runtime materialization cache")
local stale = vim.api.nvim_get_hl(0, { name = "CFStaleProbe", link = false })
assert(next(stale) == nil, "removed declaration survived Neovim's full highlight reset")

semantic.force_refresh = old_force_refresh
ts.stop = old_ts_stop
ts.start = old_ts_start
active[buf] = nil
vim.fn.delete(root, "rf")

print("cf.nvim reload lifecycle tests: OK")
