vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cf = require("cf")
local watcher = require("cf.watcher")

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/good", "p")
vim.fn.mkdir(root .. "/bad", "p")

local function write(path, data)
	local fd = assert(io.open(path, "wb"))
	assert(fd:write(data))
	fd:close()
end

write(root .. "/.cf-theme", "good\ngood\n")
write(root .. "/good/color.cf", "return { fg = '#112233' }\n")
write(root .. "/good/core.cf", [[
local hl = require("cf.hl.setup")
local u = hl.ui
return u.setup({
	u:group("WatcherRecovery", { fg = hl.colors.fg }),
})
]])
write(root .. "/bad/color.cf", "error('broken theme probe')\n")
write(root .. "/bad/core.cf", [[
local hl = require("cf.hl.setup")
local u = hl.ui
return u.setup({
	u:group("WatcherRecovery", { fg = '#445566' }),
})
]])

cf.setup({
	theme_path = root,
	watch = true,
	lineblend = { autostart = false },
})
assert(watcher.is_running(), "watcher did not start")

local ok = pcall(cf.set_theme, "bad", false)
assert(ok == false, "broken theme switch unexpectedly succeeded")
assert(watcher.is_running(), "failed theme switch left watcher stopped")

ok = pcall(cf.set_default_theme, "missing")
assert(ok == false, "missing default theme unexpectedly succeeded")
assert(watcher.is_running(), "failed default-theme change left watcher stopped")

watcher.stop()
vim.fn.delete(root, "rf")
print("cf.nvim theme switch watcher recovery tests: OK")
