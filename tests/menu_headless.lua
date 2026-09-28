-- From the cf.nvim directory:
-- nvim --headless -u NONE -l tests/menu_headless.lua
local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local spaces = 0
local backs = 0
local cancels = 0
local adjustments = {}
local opened = require("cf.menu").open({
	title = " Test ",
	items = { "[ ] one", "[ ] two" },
	on_space = function(_, index, current)
		spaces = spaces + 1
		current:set_item(index, "[x] one")
	end,
	on_back = function()
		backs = backs + 1
	end,
	on_adjust = function(_, index, current, delta)
		assert(index == 1 and current.items[1], "adjust lost selected item")
		adjustments[#adjustments + 1] = delta
	end,
})

for _, key in ipairs({ "-", "+", "<M-->", "<M-+>" }) do
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "mx", false)
end
assert(vim.deep_equal(adjustments, { -1, 1, -10, 10 }), "numeric adjustment mappings failed")

local space = vim.api.nvim_replace_termcodes("<Space>", true, false, true)
vim.api.nvim_feedkeys(space, "mx", false)
vim.wait(100, function() return spaces == 1 end)
assert(spaces == 1, "<Space> did not call menu on_space")
assert(opened.items[1] == "[x] one", "menu set_item did not update the item")

local back = vim.api.nvim_replace_termcodes("<BS>", true, false, true)
vim.api.nvim_feedkeys(back, "mx", false)
vim.wait(100, function() return backs == 1 end)
assert(backs == 1, "<BS> did not call menu on_back")

require("cf.menu").open({
	title = " Cancel ",
	items = { "one" },
	on_cancel = function()
		cancels = cancels + 1
	end,
})
local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
vim.api.nvim_feedkeys(esc, "mx", false)
vim.wait(100, function() return cancels == 1 end)
assert(cancels == 1, "<Esc> did not call menu on_cancel")

print("cf.nvim menu Space/back/cancel tests: OK")
