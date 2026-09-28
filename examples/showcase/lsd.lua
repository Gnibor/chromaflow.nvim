-- Runtime Lua integration demo.
-- Source this file once (the portable dev config does that for the bundled
-- showcase) and :LSD toggles a colour-wave over the Lua semantic types.
local hl = require("cf.hl.setup")
local r = hl.runtime("lsd")
local lua = hl.language.lua

local types = {
	"comment",
	"string",
	"number",
	"boolean",
	"constant",
	"variable",
	"parameter",
	"property",
	"function",
	"method",
	"type",
	"class",
	"struct",
	"enum",
	"interface",
	"typeparameter",
	"enummember",
	"namespace",
	"keyword",
	"modifier",
	"operator",
	"constructor",
}

local enabled = false

local function set_enabled(value)
	for i = 1, #types do
		local target = lua[types[i]]
		if value then
			r.apply(target, r.g[("colorfade_%02d"):format(i)])
		else
			r.reset(target)
		end
	end
	enabled = value
end

pcall(vim.api.nvim_del_user_command, "LSD")
vim.api.nvim_create_user_command("LSD", function()
	set_enabled(not enabled)
end, {
	nargs = 0,
	desc = "Toggle the ChromaFlow runtime colour-wave demo",
})
