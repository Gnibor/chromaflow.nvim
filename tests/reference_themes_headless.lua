-- From the cf.nvim directory:
-- nvim --headless -u NONE -l tests/reference_themes_headless.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")

local theme = require("cf.theme")
local root = vim.fs.joinpath(vim.fn.getcwd(), "examples", "themes")
local selection_path = vim.fs.joinpath(root, ".cf-theme")
local original_default, original_active = theme.selection(root)

local function restore_selection()
	local fd = assert(io.open(selection_path, "wb"))
	assert(fd:write(original_default .. "\n" .. original_active .. "\n"))
	fd:close()
end

local function ends_with(value, suffix)
	return value:sub(-#suffix) == suffix
end

local function find_file(compiled, source, name)
	for _, file in ipairs(compiled.module_files) do
		if file.source == source and file.name == name then
			return file
		end
	end
end

local ok, err = xpcall(function()
	local available = theme.available(root)
	local expected = { dark = true, fallback = true, palette = true, ["ts-only"] = true }
	for _, name in ipairs(available) do
		expected[name] = nil
	end
	assert(next(expected) == nil, "not all reference themes are discoverable")

	theme.select(root, "fallback")
	local fallback = theme.compile(root)
	assert(fallback.default == original_default and fallback.active == "fallback")
	assert(ends_with(fallback.color_path, "/" .. original_default .. "/color.cf"), "fallback did not inherit default palette")
	assert(ends_with(fallback.config_path, "/" .. original_default .. "/config.cf"), "fallback did not inherit default config")
	assert(find_file(fallback, "active", "lang-lua.cf"), "fallback lua override missing")
	assert(find_file(fallback, "active", "plugin-codemap.cf"), "fallback codemap override missing")
	assert(find_file(fallback, "default", "lang-lua.cf").skipped == true, "default lua identity was not skipped")
	assert(find_file(fallback, "default", "plugin-codemap.cf").skipped == true, "default codemap identity was not skipped")
	assert(find_file(fallback, "default", "core-ui.cf").skipped ~= true, "unrelated UI fallback was skipped")

	theme.select(root, "palette")
	local palette = theme.compile(root)
	assert(palette.active == "palette")
	assert(ends_with(palette.color_path, "/palette/color.cf"), "palette override was not selected")
	assert(ends_with(palette.config_path, "/" .. original_default .. "/config.cf"), "palette theme did not inherit default config")
	for _, file in ipairs(palette.module_files) do
		assert(file.source == "default" and file.skipped ~= true, "palette theme did not use complete module fallback")
	end

	theme.select(root, "ts-only")
	local ts_only = theme.compile(root)
	assert(ts_only.active == "ts-only")
	assert(ends_with(ts_only.color_path, "/" .. original_default .. "/color.cf"), "ts-only did not inherit default palette")
	assert(ends_with(ts_only.config_path, "/ts-only/config.cf"), "ts-only config override was not selected")
	assert(ts_only.config.only_style_target == "ts", "ts-only target boundary missing")
	for _, file in ipairs(ts_only.module_files) do
		assert(file.source == "default" and file.skipped ~= true, "ts-only theme did not use complete module fallback")
	end
end, debug.traceback)

restore_selection()
if not ok then
	error(err, 0)
end

print("Reference themes: selection, reserved fallback, identity fallback and target config OK")
