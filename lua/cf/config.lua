local M = {
	alpha = false,
	theme_path = nil,
	watch = true,
	picker = false,
	autoreload = {
		lsp = false,
		treesitter = false,
	},
	diagnostic = {
		color_trace = false,
		severity_bias = 0,
		severity = {
			hint = false,
			warn = false,
			error = true,
		},
		messages = {
			info = true,
			ok = true,
		},
	},
	lineblend = {
		autostart = true,
		blend = 50,
	},
}

local function has_lsp_autoreload()
	local lsp = vim.lsp
	local semantic_tokens = lsp and lsp.semantic_tokens
	return semantic_tokens ~= nil and type(semantic_tokens.force_refresh) == "function"
end

local function has_treesitter_autoreload()
	local ts = vim.treesitter
	return ts ~= nil
		and type(ts.start) == "function"
		and type(ts.stop) == "function"
		and type(ts.highlighter) == "table"
end


local function copy_bool_policy(dst, src, names, where)
	if src == nil then
		return
	end
	assert(type(src) == "table", where .. " must be a table")
	for i = 1, #names do
		local name = names[i]
		local value = src[name]
		if value ~= nil then
			assert(type(value) == "boolean", where .. "." .. name .. " must be boolean")
			dst[name] = value
		end
	end
end

local function validate_autoreload()
	if M.autoreload.lsp and not has_lsp_autoreload() then
		M.autoreload.lsp = false
	end
	if M.autoreload.treesitter and not has_treesitter_autoreload() then
		M.autoreload.treesitter = false
	end
end

function M.setup(opts)
	opts = opts or {}
	assert(type(opts) == "table", "cf.nvim setup expects a table")

	if opts.alpha ~= nil then
		assert(type(opts.alpha) == "boolean", "cf.nvim setup: alpha must be boolean")
		M.alpha = opts.alpha
	end

	if opts.theme_path ~= nil then
		assert(type(opts.theme_path) == "string" and opts.theme_path ~= "", "cf.nvim setup: theme_path must be a non-empty string")
		M.theme_path = vim.fs.normalize(opts.theme_path)
	end

	if opts.watch ~= nil then
		assert(type(opts.watch) == "boolean", "cf.nvim setup: watch must be boolean")
		M.watch = opts.watch
	end

	if opts.picker ~= nil then
		assert(type(opts.picker) == "boolean", "cf.nvim setup: picker must be boolean")
		M.picker = opts.picker
	end

	if opts.autoreload ~= nil then
		assert(type(opts.autoreload) == "table", "cf.nvim setup: autoreload must be a table")

		if opts.autoreload.lsp ~= nil then
			assert(type(opts.autoreload.lsp) == "boolean", "cf.nvim setup: autoreload.lsp must be boolean")
			M.autoreload.lsp = opts.autoreload.lsp
		end

		if opts.autoreload.treesitter ~= nil then
			assert(
				type(opts.autoreload.treesitter) == "boolean",
				"cf.nvim setup: autoreload.treesitter must be boolean"
			)
			M.autoreload.treesitter = opts.autoreload.treesitter
		end
	end

	validate_autoreload()

	if opts.diagnostic ~= nil then
		assert(type(opts.diagnostic) == "table", "cf.nvim setup: diagnostic must be a table")


		if opts.diagnostic.color_trace ~= nil then
			assert(type(opts.diagnostic.color_trace) == "boolean", "cf.nvim setup: diagnostic.color_trace must be boolean")
			M.diagnostic.color_trace = opts.diagnostic.color_trace
		end

		if opts.diagnostic.severity_bias ~= nil then
			local value = opts.diagnostic.severity_bias
			assert(
				type(value) == "number" and value == math.floor(value),
				"cf.nvim setup: diagnostic.severity_bias must be an integer"
			)
			M.diagnostic.severity_bias = value
		end

		copy_bool_policy(
			M.diagnostic.severity,
			opts.diagnostic.severity,
			{ "hint", "warn", "error" },
			"cf.nvim setup: diagnostic.severity"
		)
		copy_bool_policy(
			M.diagnostic.messages,
			opts.diagnostic.messages,
			{ "info", "ok" },
			"cf.nvim setup: diagnostic.messages"
		)
	end

	if opts.lineblend ~= nil then
		assert(type(opts.lineblend) == "table", "cf.nvim setup: lineblend must be a table")

		if opts.lineblend.autostart ~= nil then
			assert(
				type(opts.lineblend.autostart) == "boolean",
				"cf.nvim setup: lineblend.autostart must be boolean"
			)
			M.lineblend.autostart = opts.lineblend.autostart
		end

		if opts.lineblend.blend ~= nil then
			assert(
				type(opts.lineblend.blend) == "number"
					and opts.lineblend.blend >= 0
					and opts.lineblend.blend <= 100,
				"cf.nvim setup: lineblend.blend must be a number from 0 to 100"
			)
			M.lineblend.blend = opts.lineblend.blend
		end
	end
end

return M
