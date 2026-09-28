-- nvim --headless -u NONE -l tests/picker_headless.lua

local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local menus = {}
package.loaded["cf.menu"] = {
	open = function(opts)
		local handle = { items = opts.items }
		function handle:set_item(index, item)
			self.items[index] = item
			opts.items[index] = item
		end
		opts._handle = handle
		menus[#menus + 1] = opts
		return handle
	end,
}
package.loaded["cf.hl.resolver"] = {
	runtime_style_names = function()
		return {}
	end,
}
local current_theme
package.loaded["cf.theme"] = {
	current = function()
		return current_theme
	end,
}

local written_style
local write_count = 0
local restored_state
local restore_count = 0
package.loaded["cf.fn.runtime"] = {
	target = function(kind, scope, type_name, typemod)
		return {
			kind = kind,
			scope = scope,
			type_name = type_name,
			typemod = typemod,
		}
	end,
	_picker_style_state = function()
		return {
			base = { fg = 0xFF123456, italic = true, underline = false },
			current = { fg = 0xFF123456, italic = true, underline = false },
			has_runtime = false,
		}
	end,
	_picker_set_style = function(target, style)
		write_count = write_count + 1
		written_style = { target = target, style = style }
		return style
	end,
	_picker_restore_style = function(target, state)
		restore_count = restore_count + 1
		restored_state = { target = target, state = state }
	end,
}

local old_inspect_pos = vim.inspect_pos
local old_get_at_pos = vim.lsp.semantic_tokens.get_at_pos

local function reset()
	for i = #menus, 1, -1 do
		menus[i] = nil
	end
	current_theme = nil
	written_style = nil
	write_count = 0
	restored_state = nil
	restore_count = 0
end

local picker = require("cf.picker")

-- A plain Type gets Pipeline, Style and TypeMods.
vim.lsp.semantic_tokens.get_at_pos = function()
	return {}
end
vim.inspect_pos = function()
	return {
		treesitter = {},
		syntax = { { hl_group = "variable" } },
	}
end

picker.open()
assert(#menus == 1, "picker did not open pick menu")
assert(menus[1].items[1] == "Type     variable", "picker Type label changed")
menus[1].on_select(menus[1].items[1], 1)
assert(#menus == 2, "picker did not open edit menu")
assert(menus[2].title == " Edit: variable ", "Type edit title mismatch")
assert(#menus[2].items == 3, "Type edit menu item count mismatch")
assert(menus[2].items[1] == "Pipeline", "Type edit menu missing Pipeline")
assert(menus[2].items[2] == "Style", "Type edit menu missing Style")
assert(menus[2].items[3] == "TypeMods", "Type edit menu missing TypeMods")
assert(type(menus[2].on_back) == "function", "Type edit menu missing back action")
menus[2].on_back()
assert(#menus == 3, "Type edit back did not reopen pick menu")
assert(menus[3].title == " ChromaFlow Pick ", "Type edit back opened wrong menu")
assert(menus[3].selected == 1, "Type edit back did not restore selection")
assert(menus[3].items[1] == "Type     variable", "Type edit back changed pick entries")

-- A global Mod and a concrete TypeMod only get Pipeline + Style.
reset()
vim.lsp.semantic_tokens.get_at_pos = function()
	return {
		{
			type = "variable",
			modifiers = { readonly = true },
		},
	}
end
vim.inspect_pos = function()
	return { treesitter = {}, syntax = {} }
end

picker.open()
assert(#menus == 1, "LSP picker did not open pick menu")
assert(#menus[1].items == 3, "LSP picker entry count mismatch")
assert(menus[1].items[1] == "Type     variable", "LSP Type label mismatch")
assert(menus[1].items[2] == "Mod      readonly", "LSP Mod label mismatch")
assert(menus[1].items[3] == "TypeMod  variable.readonly", "LSP TypeMod label mismatch")

menus[1].on_select(menus[1].items[2], 2)
assert(#menus == 2, "Mod edit menu missing")
assert(menus[2].title == " Edit: readonly ", "Mod edit title mismatch")
assert(#menus[2].items == 2 and menus[2].items[1] == "Pipeline" and menus[2].items[2] == "Style", "Mod edit menu mismatch")

menus[1].on_select(menus[1].items[3], 3)
assert(#menus == 3, "TypeMod edit menu missing")
assert(menus[3].title == " Edit: variable.readonly ", "TypeMod edit title mismatch")
assert(#menus[3].items == 2 and menus[3].items[1] == "Pipeline" and menus[3].items[2] == "Style", "TypeMod edit menu mismatch")
assert(type(menus[3].on_back) == "function", "TypeMod edit menu missing back action")
menus[3].on_back()
assert(#menus == 4, "TypeMod edit back did not reopen pick menu")
assert(menus[4].selected == 3, "TypeMod edit back did not restore selection")
assert(menus[4].items[3] == "TypeMod  variable.readonly", "TypeMod edit back changed pick entries")

-- Style opens as a tri-state editor. Space writes the preview immediately
-- through the existing runtime sparse diff; <CR> only confirms that preview.
reset()
vim.bo.filetype = "lua"
current_theme = {
	modules = {
		{
			actions = {
				{
					kind = "resolver_style",
					type_name = "variable",
					priority = 0,
					sequence = 1,
					_cf_owner_kind = "language",
					_cf_owner_name = "lua",
					_cf_source = { file = "/tmp/lua.cf", line = 4, col = 2, end_line = 6, end_col = 4 },
				},
			},
		},
	},
}
vim.lsp.semantic_tokens.get_at_pos = function() return {} end
vim.inspect_pos = function()
	return { treesitter = {}, syntax = { { hl_group = "variable" } } }
end

picker.open()
menus[1].on_select(menus[1].items[1], 1)
menus[2].on_select("Style", 2)
assert(#menus == 3, "Style did not open style menu")
assert(menus[3].title == " Styles: variable ", "Style menu title mismatch")
assert(menus[3].items[1] == "[ ] bold", "Style menu unset bold state mismatch")
assert(menus[3].items[2] == "[x] italic", "Style menu true italic state mismatch")
assert(menus[3].items[3] == "[-] underline", "Style menu false underline state mismatch")
assert(type(menus[3].on_space) == "function", "Style menu missing Space toggle")
assert(type(menus[3].on_back) == "function", "Style menu missing back action")

menus[3].on_space(menus[3].items[1], 1, menus[3]._handle)
assert(write_count == 1 and written_style.style.bold == true, "Style Space did not apply live preview")
menus[3].on_space(menus[3].items[2], 2, menus[3]._handle)
menus[3].on_space(menus[3].items[3], 3, menus[3]._handle)
assert(menus[3].items[1] == "[x] bold", "Style nil -> true transition mismatch")
assert(menus[3].items[2] == "[-] italic", "Style true -> false transition mismatch")
assert(menus[3].items[3] == "[ ] underline", "Style false -> nil transition mismatch")
assert(write_count == 3, "Style preview did not write once per toggle")
assert(written_style.target.kind == "language" and written_style.target.scope == "lua", "Style runtime target owner mismatch")
assert(written_style.target.type_name == "variable" and written_style.target.typemod == nil, "Style runtime semantic target mismatch")
assert(written_style.style.fg == 0xFF123456, "Style edit lost non-style fields")
assert(written_style.style.bold == true, "Style edit lost explicit true")
assert(written_style.style.italic == false, "Style edit lost explicit false")
assert(written_style.style.underline == nil, "Style edit lost unset/inherit state")
assert(type(menus[3].on_cancel) == "function", "Style menu missing cancel restore")
menus[3].on_cancel()
assert(restore_count == 1 and restored_state ~= nil, "Style cancel did not restore pre-menu runtime state")
assert(next(picker._style_edits()) == nil, "Cancelled Style preview created save metadata")

-- Reopen and confirm: CR must not rewrite the style a second time; it only marks
-- the already-visible runtime preview as a persistent picker edit candidate.
picker.open()
menus[4].on_select(menus[4].items[1], 1)
menus[5].on_select("Style", 2)
menus[6].on_space(menus[6].items[1], 1, menus[6]._handle)
menus[6].on_space(menus[6].items[2], 2, menus[6]._handle)
menus[6].on_space(menus[6].items[3], 3, menus[6]._handle)
local writes_before_confirm = write_count
menus[6].on_select(menus[6].items[1], 1)
assert(write_count == writes_before_confirm, "Style confirmation rewrote an already-live preview")
assert(restore_count == 1, "Style confirmation restored committed preview")
assert(#menus == 7 and menus[7].title == " Edit: variable ", "Style confirmation did not return to edit menu")
local edits = picker._style_edits()
local edit_count = 0
local edit
for _, value in pairs(edits) do
	edit_count = edit_count + 1
	edit = value
end
assert(edit_count == 1, "Style commit did not create exactly one picker edit-cache entry")
assert(edit.source and edit.source.file == "/tmp/lua.cf", "Style picker cache lost exact source identity")
assert(edit.target == written_style.target, "Style picker cache target differs from runtime target")

current_theme = { modules = {} }
assert(next(picker._style_edits()) == nil, "Style picker cache survived theme replacement")

vim.inspect_pos = old_inspect_pos
vim.lsp.semantic_tokens.get_at_pos = old_get_at_pos

print("cf.nvim picker edit/style-menu tests: OK")
