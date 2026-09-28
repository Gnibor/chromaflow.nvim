-- Run as an init file so cf.setup() executes before VimEnter:
--   nvim --headless -u tests/vimenter_headless.vim

vim.opt.runtimepath:prepend(vim.fn.getcwd())

assert(vim.v.vim_did_enter == 0, "test must start before VimEnter")

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
write(root .. "/dark/plugin-late.cf", [[
local hl = require("cf.hl.setup")
local c = hl.colors
local p = hl.plugin

return p.setup("late-plugin", {
	style_targets = { vim = true, ts = false, lsp = false },
	p:group("LatePluginGroup", { fg = c.fg }),
})
]])

local cf = require("cf")
local theme = require("cf.theme")

cf.setup({ theme_path = root, watch = false })
assert(theme.current() == nil, "cf.setup() compiled/applied before VimEnter")

-- Simulate a plugin that creates its highlight groups on VimEnter. CF registered
-- its own VimEnter callback earlier, but its actual load is scheduled until the
-- event has fully finished, so this group must exist before resolver/apply runs.
vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		vim.api.nvim_set_hl(0, "LatePluginGroup", { fg = "#112233" })
		assert(theme.current() == nil, "CF applied inside VimEnter before later callbacks finished")

		vim.schedule(function()
			local compiled = assert(theme.current(), "CF did not apply after VimEnter")
			assert(compiled.active == "dark", "wrong theme applied")

			local value = vim.api.nvim_get_hl(0, { name = "LatePluginGroup", link = false })
			assert(value.fg == 0xaabbcc, "CF did not style the VimEnter-created plugin group")

			vim.fn.delete(root, "rf")
			print("cf.nvim VimEnter lifecycle tests: OK")
			vim.cmd("qa!")
		end)
	end,
})
