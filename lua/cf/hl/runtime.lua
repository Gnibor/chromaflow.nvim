local M = {}

local color = require("cf.color")
local config = require("cf.config")

local lower = string.lower
local byte = string.byte
local band = require("bit").band

local TARGET_VIM = 1
local TARGET_TS = 2
local TARGET_LSP = 4

local catalog = {}
local group_styles = {}
local style_layers = setmetatable({}, { __mode = "k" })
local rendered_rgb = setmetatable({}, { __mode = "k" })
local rendered_alpha = setmetatable({}, { __mode = "k" })


-- Standard Vim syntax roots. Config-level global syntax clear is the one place
-- where ChromaFlow intentionally clears outside a concrete module/group scope.
local VIM_SYNTAX = {
	"Comment",
	"Constant", "String", "Character", "Number", "Boolean", "Float",
	"Identifier", "Function",
	"Statement", "Conditional", "Repeat", "Label", "Operator", "Keyword", "Exception",
	"PreProc", "Include", "Define", "Macro", "PreCondit",
	"Type", "StorageClass", "Structure", "Typedef",
	"Special", "SpecialChar", "Tag", "Delimiter", "SpecialComment", "Debug",
	"Underlined", "Ignore", "Error", "Todo",
	"Added", "Changed", "Removed",
}

local function layer(name)
	if byte(name, 1) ~= 64 then -- @
		return 1
	end

	if byte(name, 2) == 108 -- l
		and byte(name, 3) == 115 -- s
		and byte(name, 4) == 112 -- p
		and byte(name, 5) == 46 -- .
	then
		return 3
	end

	return 2
end

local function layer_bit(value)
	if value == 1 then return TARGET_VIM end
	if value == 2 then return TARGET_TS end
	return TARGET_LSP
end

local function remove_style_target(name, style)
	if not style then
		return
	end

	local layers = style_layers[style]
	if not layers then
		return
	end

	local l = layer(name)
	if layers[l] == name then
		layers[l] = nil
	end
end

local function remember_style(name, style)
	group_styles[name] = style
	if not style then
		return
	end

	local layers = style_layers[style]
	if not layers then
		layers = {}
		style_layers[style] = layers
	end
	layers[layer(name)] = name
end

local function render_style(style)
	local cache = config.alpha and rendered_alpha or rendered_rgb
	local rendered = cache[style]
	if rendered then
		return rendered
	end

	rendered = {}
	for key, value in pairs(style) do
		if key == "fg" or key == "bg" or key == "sp" then
			if type(value) == "number" then
				-- Neovim accepts 0xRRGGBB directly. Keep the normal render path numeric
				-- instead of formatting #RRGGBB only for nvim_set_hl() to parse it back.
				rendered[key] = config.alpha and color.to_rgba_hex(value) or band(value, 0xFFFFFF)
			else
				rendered[key] = value
			end
		else
			rendered[key] = value
		end
	end

	cache[style] = rendered
	return rendered
end


function M.invalidate_materialized()
	-- A full colorscheme rebuild may clear/recreate Neovim highlight groups
	-- behind our back. Drop only the runtime materialization index here; the
	-- session-lifetime style interning/render caches remain valid and reusable.
	group_styles = {}
	style_layers = setmetatable({}, { __mode = "k" })
end

function M.refresh_catalog()
	local fresh = {}
	local ok, all = pcall(vim.api.nvim_get_hl, 0, {})
	if ok and type(all) == "table" then
		for name in pairs(all) do
			if type(name) == "string" then
				fresh[lower(name)] = name
			end
		end
	else
		local names = vim.fn.getcompletion("", "highlight")
		for i = 1, #names do
			local name = names[i]
			fresh[lower(name)] = name
		end
	end

	catalog = fresh
	return catalog
end

function M.lookup_hl(name)
	return catalog[lower(name)]
end

-- Only directly materialized styles are cached. Link state belongs to Neovim
-- and to the resolver's link decisions; a linked hl_group has no own style.
-- This keeps style_target() from ever treating a link as a style anchor.
function M.group_style(name)
	return group_styles[name]
end

function M.style_target(style, max_layer, mask)
	local layers = style_layers[style]
	if not layers then
		return nil
	end

	for current = max_layer, 1, -1 do
		if band(mask, layer_bit(current)) ~= 0 then
			local name = layers[current]
			if name and group_styles[name] == style then
				return name
			end
		end
	end
end

function M.setter(name, value, is_link)
	local old = group_styles[name]
	remove_style_target(name, old)
	group_styles[name] = nil

	if is_link then
		vim.api.nvim_set_hl(0, name, { link = value })
		catalog[lower(name)] = name
		return
	end

	if value == nil then
		vim.api.nvim_set_hl(0, name, {})
		catalog[lower(name)] = name
		return
	end

	vim.api.nvim_set_hl(0, name, render_style(value))
	catalog[lower(name)] = name
	remember_style(name, value)
end


local function internal_style(value)
	local style = {}
	for key, item in pairs(value) do
		if key == "fg" or key == "bg" or key == "sp" then
			-- nvim_get_hl() exposes opaque RGB as 0xRRGGBB; ChromaFlow keeps
			-- colours internally as unsigned 0xAARRGGBB.
			style[key] = 0xFF000000 + item
		elseif key ~= "link" then
			style[key] = item
		end
	end
	return style
end


-- Runtime overlays never touch the normal materialization caches. The base
-- theme therefore remains the source of truth while runtime is only a sparse
-- visual diff layered on top.
function M.read_effective_style(name)
	assert(type(name) == "string" and name ~= "", "cf.hl.runtime.read_effective_style: name must be a non-empty string")
	local ok, value = pcall(vim.api.nvim_get_hl, 0, {
		name = name,
		link = false,
		create = false,
	})
	if not ok or type(value) ~= "table" or next(value) == nil then
		return nil
	end
	return internal_style(value)
end

function M.runtime_write(name, style)
	assert(type(name) == "string" and name ~= "", "cf.hl.runtime.runtime_write: name must be a non-empty string")
	if style == nil then
		vim.api.nvim_set_hl(0, name, {})
	else
		assert(type(style) == "table", "cf.hl.runtime.runtime_write: style must be a table or nil")
		vim.api.nvim_set_hl(0, name, render_style(style))
	end
	catalog[lower(name)] = name
end

-- Raw operations are deliberately literal. No Vim/TS/LSP layer filtering is
-- performed; the exact supplied name is always the target.
function M.apply_raw(name, style, clear)
	if clear then
		M.setter(name, nil, false)
	end
	if M.group_style(name) == style then
		return true
	end
	M.setter(name, style, false)
	return true
end

function M.apply_raw_link(name, target, clear)
	if clear then
		M.setter(name, nil, false)
	end
	-- Link state is deliberately not cached. Re-materializing an explicit link is
	-- cheap and avoids stale effective-style/link bookkeeping in Lua.
	M.setter(name, target, true)
	return true
end

function M.clear_raw(name)
	M.setter(name, nil, false)
	return true
end

function M.global_clear(clear)
	if not clear then
		return
	end

	if clear.vim then
		for i = 1, #VIM_SYNTAX do
			M.setter(VIM_SYNTAX[i], nil, false)
		end
	end

	if clear.ts or clear.lsp then
		local names = {}
		local count = 0
		for _, name in pairs(catalog) do
			local l = layer(name)
			if (l == 2 and clear.ts) or (l == 3 and clear.lsp) then
				count = count + 1
				names[count] = name
			end
		end

		for i = 1, count do
			M.setter(names[i], nil, false)
		end
	end
end

function M.backend()
	return {
		lookup_hl = M.lookup_hl,
		group_style = M.group_style,
		style_target = M.style_target,
		setter = M.setter,
	}
end

return M
