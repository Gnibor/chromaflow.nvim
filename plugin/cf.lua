if vim.g.loaded_cf_nvim then
	return
end
vim.g.loaded_cf_nvim = true

vim.filetype.add({
	extension = {
		cf = "lua",
	},
})

-- LuaSnip is an optional integration. ChromaFlow never loads LuaSnip itself;
-- snippets are registered only after LuaSnip has already been loaded by the
-- user's own configuration.
local snippets_ready = false
local snippet_retry

local function setup_snippets()
	if snippets_ready then
		return true
	end

	local luasnip = package.loaded["luasnip"]
	if type(luasnip) ~= "table" then
		return false
	end

	require("cf.snippets").setup(luasnip)
	snippets_ready = true
	return true
end

local function retry_snippets()
	if snippet_retry and setup_snippets() then
		pcall(vim.api.nvim_del_autocmd, snippet_retry)
		snippet_retry = nil
	end
end

if not setup_snippets() then
	snippet_retry = vim.api.nvim_create_autocmd("InsertEnter", {
		callback = function()
			vim.schedule(retry_snippets)
		end,
	})

	-- Local plugin files may be sourced before the user's optional completion
	-- plugins are configured. Re-check once after startup; the autocmd remains
	-- as a fallback for genuinely lazy-loaded LuaSnip setups.
	vim.schedule(retry_snippets)
end
