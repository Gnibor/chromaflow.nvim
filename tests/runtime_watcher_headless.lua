vim.opt.runtimepath:prepend(vim.fn.getcwd())

local watcher = require("cf.watcher")
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/default", "p")
vim.fn.mkdir(root .. "/active", "p")
vim.fn.mkdir(root .. "/runtime", "p")
vim.fn.mkdir(root .. "/active/runtime", "p")
vim.fn.mkdir(root .. "/default/runtime", "p")

local function write(path, data)
	local fd = assert(io.open(path, "wb"))
	assert(fd:write(data))
	fd:close()
end

local batches = {}
assert(watcher.start(root, "default", "active", function(batch)
	batches[#batches + 1] = batch
end, function(err)
	error(err)
end))

local function wait_for(path)
	local ok = vim.wait(2000, function()
		for i = 1, #batches do
			if batches[i][path] then
				return true
			end
		end
		return false
	end, 20)
	assert(ok, "watcher did not report runtime file: " .. path)
end

local root_file = root .. "/runtime/root-action.cf"
write(root_file, "return {}\n")
wait_for(root_file)

local active_file = root .. "/active/runtime/active-action.cf"
write(active_file, "return {}\n")
wait_for(active_file)

local default_file = root .. "/default/runtime/default-action.cf"
write(default_file, "return {}\n")
wait_for(default_file)

-- A runtime directory that appears after watcher startup must get its own
-- non-recursive fs_event handle without restarting the whole watcher.
vim.fn.delete(root .. "/active/runtime", "rf")
vim.wait(350)
vim.fn.mkdir(root .. "/active/runtime", "p")
vim.wait(350)
batches = {}
local recreated = root .. "/active/runtime/recreated.cf"
write(recreated, "return {}\n")
wait_for(recreated)

watcher.stop()
vim.fn.delete(root, "rf")
print("cf.nvim runtime watcher tests: OK")
