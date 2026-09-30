local M = {}

local uv = vim.uv
local api = vim.api
local join = vim.fs.joinpath
local normalize = vim.fs.normalize

local config = require("cf.config")
local diagnostic = require("cf.diagnostic")
local hl = require("cf.hl.setup")
local resolver = require("cf.hl.resolver")
local runtime = require("cf.hl.runtime")

local RESERVED = {
	["color.cf"] = true,
	["config.cf"] = true,
}

local RUNTIME_DIR = "runtime"

local current
local runtime_phase = "idle"

local function is_file(path)
	local stat = uv.fs_stat(path)
	return stat and stat.type == "file"
end

local function is_dir(path)
	local stat = uv.fs_stat(path)
	return stat and stat.type == "directory"
end

local function read_file(path)
	local fd, err = io.open(path, "rb")
	if not fd then
		return nil, err
	end
	local data = fd:read("*a")
	fd:close()
	return data
end

local function write_file(path, data)
	local fd, err = io.open(path, "wb")
	if not fd then
		return nil, err
	end
	local ok, write_err = fd:write(data)
	fd:close()
	if not ok then
		return nil, write_err
	end
	return true
end

local function theme_names(root)
	local path = join(root, ".cf-theme")
	local data, err = read_file(path)
	if not data then
		error("cf.theme: cannot read " .. path .. ": " .. tostring(err), 3)
	end

	local lines = {}
	for line in (data .. "\n"):gmatch("([^\n]*)\n") do
		line = line:gsub("\r$", "")
		if line ~= "" then
			lines[#lines + 1] = line
		end
	end

	assert(#lines == 2, "cf.theme: .cf-theme must contain exactly two non-empty lines: default theme, active theme")
	return lines[1], lines[2]
end

local function list_cf(dir)
	local out = {}
	if not is_dir(dir) then
		return out
	end

	local scan = uv.fs_scandir(dir)
	if not scan then
		return out
	end

	while true do
		local name, kind = uv.fs_scandir_next(scan)
		if not name then
			break
		end
		if kind == "file" and name:sub(-3) == ".cf" then
			out[#out + 1] = name
		end
	end
	table.sort(out)
	return out
end

local function valid_theme_dir(path)
	if not is_dir(path) then
		return false
	end
	return #list_cf(path) > 0
end

function M.selection(root)
	assert(type(root) == "string" and root ~= "", "cf.theme.selection: theme_path must be a non-empty string")
	root = normalize(root)
	assert(is_dir(root), "cf.theme: theme_path is not a directory: " .. root)
	return theme_names(root)
end

function M.available(root)
	assert(type(root) == "string" and root ~= "", "cf.theme.available: theme_path must be a non-empty string")
	root = normalize(root)
	assert(is_dir(root), "cf.theme: theme_path is not a directory: " .. root)

	local out = {}
	local scan = uv.fs_scandir(root)
	if not scan then
		return out
	end

	while true do
		local name, kind = uv.fs_scandir_next(scan)
		if not name then
			break
		end
		if kind == "directory" and name ~= RUNTIME_DIR and valid_theme_dir(join(root, name)) then
			out[#out + 1] = name
		end
	end

	table.sort(out)
	return out
end

function M.set_default(root, default_name)
	assert(type(root) == "string" and root ~= "", "cf.theme.set_default: theme_path must be a non-empty string")
	assert(type(default_name) == "string" and default_name ~= "", "cf.theme.set_default: theme name must be a non-empty string")
	assert(default_name ~= RUNTIME_DIR, "cf.theme.set_default: 'runtime' is reserved for shared runtime modules")

	root = normalize(root)
	assert(is_dir(root), "cf.theme: theme_path is not a directory: " .. root)
	assert(valid_theme_dir(join(root, default_name)), "cf.theme: theme is missing or contains no .cf files: " .. default_name)

	local _, active_name = theme_names(root)
	local path = join(root, ".cf-theme")
	local ok, err = write_file(path, default_name .. "\n" .. active_name .. "\n")
	if not ok then
		error("cf.theme: cannot write " .. path .. ": " .. tostring(err), 2)
	end

	return default_name, active_name
end

function M.select(root, active_name, set_default)
	assert(type(root) == "string" and root ~= "", "cf.theme.select: theme_path must be a non-empty string")
	assert(type(active_name) == "string" and active_name ~= "", "cf.theme.select: theme name must be a non-empty string")
	assert(active_name ~= RUNTIME_DIR, "cf.theme.select: 'runtime' is reserved for shared runtime modules")
	assert(set_default == nil or type(set_default) == "boolean", "cf.theme.select: set_default must be boolean or nil")

	root = normalize(root)
	assert(is_dir(root), "cf.theme: theme_path is not a directory: " .. root)
	assert(valid_theme_dir(join(root, active_name)), "cf.theme: theme is missing or contains no .cf files: " .. active_name)

	local default_name = theme_names(root)
	if set_default then
		default_name = active_name
	end
	assert(valid_theme_dir(join(root, default_name)), "cf.theme: default theme is missing or contains no .cf files: " .. default_name)

	local path = join(root, ".cf-theme")
	local ok, err = write_file(path, default_name .. "\n" .. active_name .. "\n")
	if not ok then
		error("cf.theme: cannot write " .. path .. ": " .. tostring(err), 2)
	end

	return default_name, active_name
end

local function execute(path, label, recover)
	local source_token = hl._source_begin(path)
	hl._error_source_clear()
	local chunk, err = loadfile(path)
	if not chunk then
		hl._error_source_clear()
		hl._source_end(source_token)
		local message = "cf.theme: failed to load " .. label .. " (" .. path .. "): " .. tostring(err)
		if recover then
			return nil, message, nil
		end
		error(message, 3)
	end

	local ok, result = pcall(chunk)
	local source_hint = ok and nil or hl._error_source_take()
	if ok then
		hl._error_source_clear()
	end
	hl._source_end(source_token)
	if not ok then
		local message = "cf.theme: failed to execute " .. label .. " (" .. path .. "): " .. tostring(result)
		if recover then
			return nil, message, source_hint
		end
		error(message, 3)
	end
	return result
end

local function source_at_line(path, line)
	local normalized = normalize(path)
	local col = 1
	local data = read_file(normalized)
	if data then
		local current = 0
		for text in (data .. "\n"):gmatch("([^\n]*)\n") do
			current = current + 1
			if current == line then
				col = text:find("%S") or 1
				break
			end
		end
	end
	return { file = normalized, line = line, col = col }
end

local function source_position(path, message)
	local normalized = normalize(path)
	local escaped = normalized:gsub("(%W)", "%%%1")
	local line = tonumber(tostring(message):match(escaped .. ":(%d+):")) or 1
	return source_at_line(normalized, line)
end

local function first_message_line(message)
	return tostring(message):match("([^\n]+)") or tostring(message)
end

local function report_module_diagnostic(severity, file, message, source_hint)
	if not diagnostic._enabled(severity) then
		return
	end
	local source = source_hint
	if source then
		local refined = source_at_line(source.file, source.line)
		if source.end_line ~= nil and source.end_col ~= nil then
			refined.col = source.col
			refined.end_line = source.end_line
			refined.end_col = source.end_col
		end
		source = refined
	else
		source = source_position(file.path, message)
	end
	local record, report_err = diagnostic.report(severity, {
		message = first_message_line(message),
		source = source,
		context = { kind = "theme", name = file.name },
	})
	if not record then
		vim.notify(tostring(report_err), vim.log.levels.ERROR)
	end
end

local function first_existing(paths)
	for i = 1, #paths do
		if is_file(paths[i]) then
			return paths[i]
		end
	end
end

local function resolve_reserved(root, default_dir, active_dir, name)
	return first_existing({
		join(active_dir, name),
		join(root, name),
		join(default_dir, name),
	})
end

local function validate_runtime_name(name)
	assert(type(name) == "string" and name ~= "", "cf.theme.load_runtime: module name must be a non-empty string")
	assert(not name:find("/", 1, true) and not name:find("\\", 1, true), "cf.theme.load_runtime: module name must not contain path separators")
	assert(name ~= "." and name ~= "..", "cf.theme.load_runtime: invalid module name")
	assert(name:sub(-3) ~= ".cf", "cf.theme.load_runtime: pass the module name without the .cf suffix")
	return name
end

local function runtime_candidate(root, active_dir, default_dir, name)
	local filename = name .. ".cf"
	local candidates = {
		{ path = join(active_dir, RUNTIME_DIR, filename), source = "active" },
		{ path = join(root, RUNTIME_DIR, filename), source = "root" },
		{ path = join(default_dir, RUNTIME_DIR, filename), source = "default" },
	}

	local seen = {}
	for i = 1, #candidates do
		local item = candidates[i]
		if not seen[item.path] then
			seen[item.path] = true
			if is_file(item.path) then
				return item
			end
		end
	end
end

local function module_files(dir, source)
	local files = list_cf(dir)
	local out = {}
	for i = 1, #files do
		local name = files[i]
		if not RESERVED[name] then
			out[#out + 1] = {
				name = name,
				path = join(dir, name),
				source = source,
			}
		end
	end
	return out
end


local function colorscheme_event(event, name)
	api.nvim_exec_autocmds(event, {
		pattern = name,
		modeline = false,
	})
end

local function reset_highlights()
	-- Match the destructive part of a normal colorscheme reload. This removes
	-- stale groups from the previous compile before ChromaFlow materializes the
	-- new result. syntax reset only resets highlight colours, not syntax items.
	vim.cmd("highlight clear")
	if vim.g.syntax_on == 1 then
		vim.cmd("syntax reset")
	end

	-- Neovim just changed highlight state behind the runtime cache. Keep the
	-- session style interning cache, but forget every materialized group/style
	-- association so the new theme is fully written again.
	runtime.invalidate_materialized()
end

local function refresh_treesitter()
	local ts = vim.treesitter
	local highlighter = ts and ts.highlighter
	local active = highlighter and highlighter.active
	if type(active) ~= "table" then
		return
	end

	-- Preserve the language actually used by each active highlighter. Filetype
	-- and parser language are not guaranteed to be identical. Collect first,
	-- because stop() mutates highlighter.active.
	local pending = {}
	local count = 0
	for buf, value in pairs(active) do
		if type(buf) == "number" and api.nvim_buf_is_valid(buf) and api.nvim_buf_is_loaded(buf) then
			local lang
			local tree = value and value.tree
			if tree and type(tree.lang) == "function" then
				local ok, resolved = pcall(tree.lang, tree)
				if ok then
					lang = resolved
				end
			end

			count = count + 1
			pending[count] = { buf, lang }
		end
	end

	for i = 1, count do
		pcall(ts.stop, pending[i][1])
	end
	for i = 1, count do
		pcall(ts.start, pending[i][1], pending[i][2])
	end
end

local function refresh_lsp_semantic_tokens()
	local lsp = vim.lsp
	local semantic_tokens = lsp and lsp.semantic_tokens
	if semantic_tokens and type(semantic_tokens.force_refresh) == "function" then
		pcall(semantic_tokens.force_refresh, nil)
	end
end

local function refresh_consumers()
	-- The final CF hl_group state already exists at this point. Rebuild enabled
	-- consumers afterwards so their extmarks/tokens are based on that fresh state.
	if config.autoreload.treesitter then
		refresh_treesitter()
	end
	if config.autoreload.lsp then
		refresh_lsp_semantic_tokens()
	end
	vim.cmd("redraw!")
end

local function compile_theme(root)
	local default_name, active_name = theme_names(root)
	assert(default_name ~= RUNTIME_DIR, "cf.theme: 'runtime' cannot be the default theme name")
	assert(active_name ~= RUNTIME_DIR, "cf.theme: 'runtime' cannot be the active theme name")
	local default_dir = join(root, default_name)
	assert(valid_theme_dir(default_dir), "cf.theme: default theme is missing or contains no .cf files: " .. default_name)

	local requested_active = active_name
	local active_dir = join(root, active_name)
	if not valid_theme_dir(active_dir) then
		active_name = default_name
		active_dir = default_dir
	end

	local color_path = resolve_reserved(root, default_dir, active_dir, "color.cf")
	assert(color_path, "cf.theme: no color.cf found in active/root/default fallback chain")
	local colors = execute(color_path, "color.cf")
	assert(type(colors) == "table", "cf.theme: color.cf must return a table")

	local config_path = resolve_reserved(root, default_dir, active_dir, "config.cf")
	local theme_config = {}
	if config_path then
		theme_config = execute(config_path, "config.cf")
		assert(type(theme_config) == "table", "cf.theme: config.cf must return a table")
	end

	-- Install the resolved palette/config before executing any module. Every
	-- module then receives the exact same `hl.colors` table reference.
	hl._begin(colors, theme_config)

	local active_files = module_files(active_dir, "active")
	local fallback_files = active_dir ~= default_dir and module_files(default_dir, "default") or {}
	local compiled_files = {}
	local modules = {}

	local function compile_file(file)
		local module, module_err, source_hint = execute(file.path, file.name, true)
		compiled_files[#compiled_files + 1] = file

		if module_err then
			file.failed = true
			report_module_diagnostic("error", file, module_err, source_hint)
			return false
		end
		if type(module) ~= "table" or module._cf_module ~= true or type(module.apply) ~= "function" then
			file.ignored = true
			report_module_diagnostic(
				"hint",
				file,
				"cf.theme: " .. file.name
					.. " is not a theme module; expected l.setup(...), p.setup(...) or u.setup(...)"
			)
			return false
		end

		file.skipped = module._cf_skip == true
		if not file.skipped then
			modules[#modules + 1] = module
		end
		return true
	end

	hl._active_begin()
	local ok, err = pcall(function()
		-- Every active module is compiled. Duplicate language/plugin identities
		-- are intentionally allowed here; the registry is only collected.
		for i = 1, #active_files do
			compile_file(active_files[i])
		end

		if #fallback_files > 0 then
			-- Only now does the completed active registry become a skip filter.
			-- Fallback modules never extend it, so multiple default modules for an
			-- uncovered language/plugin/UI scope are all allowed to compile.
			hl._fallback_begin()
			for i = 1, #fallback_files do
				compile_file(fallback_files[i])
			end
		end
	end)
	hl._compile_end()
	if not ok then
		error(err, 0)
	end

	local compiled = {
		root = root,
		default = default_name,
		active = active_name,
		requested_active = requested_active,
		colors = colors,
		config = theme_config,
		color_path = color_path,
		config_path = config_path,
		module_files = compiled_files,
		modules = modules,
		runtime_modules = {},
	}

	-- Runtime modules are opt-in. Only a previously requested logical module name
	-- is resolved here, while compilation is still fully transactional and before
	-- the destructive colorscheme apply begins.
	local runtime_state = package.loaded["cf.fn.runtime"]
	if runtime_state then
		local names = runtime_state._requested_names()
		for i = 1, #names do
			local name = names[i]
			compiled.runtime_modules[name] = M.load_runtime(compiled, name)
		end
		runtime_state._validate_compiled(compiled)
	end

	return compiled
end

function M.compile(root)
	assert(type(root) == "string" and root ~= "", "cf.theme.compile: theme_path must be a non-empty string")
	root = normalize(root)
	assert(is_dir(root), "cf.theme: theme_path is not a directory: " .. root)

	local colortrace = package.loaded["cf.colortrace"]
	if not colortrace then
		return compile_theme(root)
	end

	colortrace._compile_begin()
	local ok, compiled_or_err = pcall(compile_theme, root)
	if not ok then
		colortrace._compile_abort()
		error(compiled_or_err, 0)
	end
	colortrace._compile_finish(compiled_or_err)
	return compiled_or_err
end

function M.load_runtime(compiled, name)
	assert(type(compiled) == "table" and type(compiled.root) == "string", "cf.theme.load_runtime: invalid compiled theme")
	name = validate_runtime_name(name)

	local active_dir = join(compiled.root, compiled.active)
	local default_dir = join(compiled.root, compiled.default)
	local candidate = runtime_candidate(compiled.root, active_dir, default_dir, name)
	assert(candidate, "cf.theme: no runtime module '" .. name .. "' found in active/root/default fallback chain")

	local token = hl._runtime_begin(name)
	local ok, definition = pcall(execute, candidate.path, RUNTIME_DIR .. "/" .. name .. ".cf")
	local end_ok, end_err = pcall(hl._runtime_end, token)
	if not end_ok then
		error(end_err, 0)
	end
	if not ok then
		error(definition, 0)
	end
	assert(
		type(definition) == "table" and definition._cf_runtime_module == true and type(definition.groups) == "table",
		"cf.theme: runtime/" .. name .. ".cf must return hl.runtime.setup({...})"
	)

	return {
		name = name,
		path = candidate.path,
		source = candidate.source,
		definition = definition,
	}
end

function M.apply(compiled)
	assert(type(compiled) == "table" and type(compiled.modules) == "table", "cf.theme.apply: invalid compiled theme")

	-- Compilation/validation is already complete before anything visible changes.
	-- From here on this is a real colorscheme rebuild, not only a CF cache reload.
	colorscheme_event("ColorSchemePre", compiled.active)
	reset_highlights()

	-- Rebuild resolver knowledge after Neovim's destructive reset, then write the
	-- complete new CF result. Config-global clears intentionally happen before
	-- module/group actions.
	runtime.refresh_catalog()
	resolver.clear_cache()
	runtime.global_clear(hl._global_clear())

	-- Normal theme materialization stays on the original fast path. Runtime target
	-- discovery is lazy and only happens for semantic targets that are actually
	-- modified at runtime.
	hl._apply_modules(compiled.modules)

	-- Expose the actual selected theme before ColorScheme callbacks run. Runtime
	-- callbacks deliberately operate on the new target catalog but defer visible
	-- runtime writes until the full normal ColorScheme callback chain is complete.
	current = compiled
	local colortrace = package.loaded["cf.colortrace"]
	if colortrace then
		colortrace._activate(compiled)
	end
	vim.g.colors_name = compiled.active
	runtime_phase = "callbacks"
	local runtime_state = package.loaded["cf.fn.runtime"]
	if runtime_state then
		runtime_state._theme_prepare(compiled)
	end
	local callbacks_ok, callbacks_err = pcall(colorscheme_event, "ColorScheme", compiled.active)
	runtime_phase = "idle"
	if not callbacks_ok then
		error(callbacks_err, 0)
	end

	-- Runtime is one post-theme layer. Its base is the final normal theme state,
	-- including ColorScheme callbacks; active apply/replace/clear operations are
	-- then replayed against that new base without re-running resolver semantics.
	-- Re-read package.loaded because the first runtime user may have appeared from
	-- a ColorScheme callback itself.
	runtime_state = package.loaded["cf.fn.runtime"]
	if runtime_state then
		runtime_state._theme_applied(compiled)
	end

	-- Tree-sitter and LSP semantic-token consumers are refreshed only after the
	-- final highlight groups (including runtime overrides) are in place.
	refresh_consumers()

	return compiled
end

function M.load(root)
	return M.apply(M.compile(root))
end

-- Re-execute exactly one module from the currently applied theme. Outside the
-- active/fallback compile phase this only rebuilds that module, which is enough
-- for on-view diagnostics/ColorTrace; it does not apply highlight actions or
-- touch the active-module registry.
function M.color_trace_file(path)
	if not current or type(current.module_files) ~= "table" then return false end
	local normalized = normalize(path)
	for i = 1, #current.module_files do
		local file = current.module_files[i]
		if normalize(file.path) == normalized then
			local _, err, source_hint = execute(file.path, file.name, true)
			if err then
				report_module_diagnostic("error", file, err, source_hint)
				return false
			end
			return true
		end
	end
	return false
end

function M.current()
	return current
end

-- Internal late-binding hook for cf.fn.runtime. Runtime target discovery is
-- intentionally lazy, so only the current compiled theme and phase are needed.
function M._runtime_state()
	return current, runtime_phase
end

return M
