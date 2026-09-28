local M = {}

local config = require("cf.config")
local lineblend = require("cf.fn.lineblend")
local theme = require("cf.theme")
local hl = require("cf.hl.setup")
local api = vim.api

local function replace_command(name, callback, opts)
	pcall(api.nvim_del_user_command, name)
	api.nvim_create_user_command(name, callback, opts)
end

local function starts_with(value, prefix)
	return value:sub(1, #prefix) == prefix
end

local function theme_completion(arglead, cmdline)
	-- Command name + first argument means we are completing the theme name.
	-- Once a complete first argument and following space exist, only the optional
	-- literal flag is valid.
	local before_cursor = cmdline
	local first = before_cursor:match("^%s*CFTheme%s+(%S+)")
	local after_first = first and before_cursor:match("^%s*CFTheme%s+%S+%s+") ~= nil

	if after_first then
		return starts_with("default=true", arglead) and { "default=true" } or {}
	end

	if not config.theme_path then
		return {}
	end

	local ok, names = pcall(theme.available, config.theme_path)
	if not ok then
		return {}
	end

	local out = {}
	for i = 1, #names do
		if starts_with(names[i], arglead) then
			out[#out + 1] = names[i]
		end
	end
	return out
end

function M.setup(handlers)
	handlers = handlers or {}
	assert(type(handlers) == "table", "cf.usr_cmd.setup: handlers must be a table")

	replace_command("CFReload", function()
		assert(type(handlers.reload) == "function", "cf.nvim: CFReload is not wired")
		handlers.reload()
	end, {
		nargs = 0,
		desc = "Reload the active ChromaFlow theme",
	})

	if config.picker then
		replace_command("CFPick", function()
			require("cf.picker").open()
		end, {
			nargs = 0,
			desc = "Open ChromaFlow highlight picker at cursor",
		})

		replace_command("CFSave", function()
			assert(type(handlers.save) == "function", "cf.nvim: CFSave is not wired")
			local count, files = handlers.save()
			if count == 0 then
				api.nvim_echo({ { "ChromaFlow: nothing to save", "Normal" } }, false, {})
			else
				api.nvim_echo({ { ("ChromaFlow: saved %d edit%s in %d file%s"):format(
					count, count == 1 and "" or "s", files, files == 1 and "" or "s"
				), "MoreMsg" } }, false, {})
			end
		end, {
			nargs = 0,
			desc = "Persist confirmed ChromaFlow picker edits",
		})
	else
		pcall(api.nvim_del_user_command, "CFPick")
		pcall(api.nvim_del_user_command, "CFSave")
	end

	replace_command("CFTheme", function(opts)
		local args = opts.fargs
		if #args == 0 then
			assert(type(handlers.theme_menu) == "function", "cf.nvim: CFTheme menu is not wired")
			handlers.theme_menu()
			return
		end

		assert(type(handlers.set_theme) == "function", "cf.nvim: CFTheme is not wired")
		assert(#args == 1 or #args == 2, "usage: :CFTheme [<theme-name> [default=true]]")

		local set_default = false
		if args[2] ~= nil then
			assert(args[2] == "default=true", "usage: :CFTheme [<theme-name> [default=true]]")
			set_default = true
		end

		handlers.set_theme(args[1], set_default)
	end, {
		nargs = "*",
		complete = theme_completion,
		desc = "Open the theme menu or select a ChromaFlow theme",
	})

	replace_command("LineBlendToggle", function()
		if lineblend.is_active() then
			lineblend.stop()
		else
			lineblend.activate()
		end
	end, {
		nargs = 0,
		desc = "Toggle LineBlend",
	})

	replace_command("LineBlend", function(opts)
		lineblend.set_blend(opts.args)
	end, {
		nargs = 1,
		desc = "Set LineBlend amount (0..100)",
	})

	replace_command("LineBlendReload", function()
		lineblend.reload()
	end, {
		nargs = 0,
		desc = "Hard-reload LineBlend highlight state",
	})


	local function split_dot(value)
		local out = {}
		for part in value:gmatch("[^.]+") do
			out[#out + 1] = part
		end
		return out
	end

	local function runtime_action(value)
		local parts = split_dot(value)

		assert(
			#parts == 3 and parts[1] == "r",
			"runtime action must be: r.<module>.<action>"
		)

		local r = hl.runtime(parts[2])
		return r, r.groups[parts[3]]
	end

	local function runtime_target(value)
		local parts = split_dot(value)
		local prefix = table.remove(parts, 1)

		local target

		if prefix == "l" then
			assert(#parts >= 2, "language target must be: l.<language>.<type>[.<typemod>]")
			target = hl.language
		elseif prefix == "p" then
			assert(#parts >= 2, "plugin target must be: p.<plugin>.<type>[.<typemod>]")
			target = hl.plugin
		elseif prefix == "u" then
			assert(#parts >= 1, "ui target must be: u.<type>[.<typemod>]")
			target = hl.ui
		else
			error("target must start with l., p. or u.")
		end

		for _, part in ipairs(parts) do
			target = target[part]
			assert(target ~= nil, "invalid runtime target: " .. value)
		end

		return target
	end

	local function command(name, callback, nargs)
		pcall(vim.api.nvim_del_user_command, name)

		vim.api.nvim_create_user_command(name, callback, {
			nargs = nargs,
		})
	end

	command("CFApply", function(opts)
		if #opts.fargs ~= 2 then
			error("CFApply expects: <r.module.action> <p|l|u.target>")
		end

		local r, action = runtime_action(opts.fargs[1])
		local target = runtime_target(opts.fargs[2])

		r.apply(target, action)
	end, "+")

	command("CFReplace", function(opts)
		if #opts.fargs ~= 2 then
			error("CFReplace expects: <r.module.action> <p|l|u.target>")
		end

		local r, action = runtime_action(opts.fargs[1])
		local target = runtime_target(opts.fargs[2])

		r.replace(target, action)
	end, "+")

	command("CFReset", function(opts)
		local target = runtime_target(opts.fargs[1])

		-- apply/replace/reset/clear all operate on the one global runtime state.
		-- Any runtime module handle exposes the same operation, so use the
		-- underlying runtime function directly here.
		require("cf.fn.runtime").reset(target)
	end, 1)

	command("CFClear", function(opts)
		local target = runtime_target(opts.fargs[1])

		require("cf.fn.runtime").clear(target)
	end, 1)
end

return M
