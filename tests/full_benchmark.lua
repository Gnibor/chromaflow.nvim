-- Full ChromaFlow white-box benchmark.
-- Defaults: 100 samples x 10 calls for every measured command.
-- Uses tests/benchmark.lua when it sits next to this file, otherwise falls back
-- to tools.benchmark. Private upvalues are intentionally measured because this
-- suite is meant to decompose the current implementation, not define public API.
--
-- Run from Neovim:
--   :lua dofile(vim.api.nvim_get_runtime_file("tests/full_benchmark.lua", false)[1]).run()

local function load_benchmark()
	local source = debug.getinfo(1, "S").source
	if type(source) == "string" and source:sub(1, 1) == "@" then
		local here = vim.fs.dirname(vim.fs.normalize(source:sub(2)))
		local sibling = vim.fs.joinpath(here, "benchmark.lua")
		local chunk = loadfile(sibling)
		if chunk then
			return chunk()
		end
	end
	return require("tools.benchmark")
end

local benchmark = load_benchmark()
local cf = require("cf")
local config = require("cf.config")
local colortrace = require("cf.colortrace")
local diagnostic = require("cf.diagnostic")
local Float = require("cf.fn.float")
local lineblend = require("cf.fn.lineblend")
local runtime_state = require("cf.fn.runtime")
local hl = require("cf.hl.setup")
local resolver = require("cf.hl.resolver")
local runtime = require("cf.hl.runtime")
local theme = require("cf.theme")
local watcher = require("cf.watcher")

local M = {}
local unpack_args = table.unpack or rawget(_G, "unpack")

local function pack(...)
	return { n = select("#", ...), ... }
end

local function upvalue(fn, wanted)
	for i = 1, 200 do
		local name, value = debug.getupvalue(fn, i)
		if not name then
			break
		end
		if name == wanted then
			return value, i
		end
	end
	error("full_benchmark: missing upvalue '" .. wanted .. "'", 2)
end

local function benchmark_opts(opts, extra)
	local out = {
		count = opts.count or 100,
		batch = opts.batch or 10,
		warmup = opts.warmup == nil and 25 or opts.warmup,
	}
	if extra then
		for key, value in pairs(extra) do
			out[key] = value
		end
	end
	return out
end

local function bench(opts, name, fn, extra)
	return benchmark.bench(name, fn, benchmark_opts(opts, extra))
end

local function flatten_actions(modules)
	local out = {}
	for i = 1, #modules do
		local actions = modules[i].actions
		for n = 1, #actions do
			out[#out + 1] = actions[n]
		end
	end
	return out
end

local function capture_dsl(root)
	local language_setup = hl.language.setup
	local plugin_setup = hl.plugin.setup
	local ui_setup = hl.ui.setup

	local compile_language = upvalue(language_setup, "compile_language_module")
	local compile_resolved = upvalue(plugin_setup, "compile_resolved_module")
	local compile_group = upvalue(compile_language, "compile_resolved_group")
	local compile_module_mods = upvalue(compile_language, "compile_module_mods")
	local module_declarations = upvalue(compile_language, "module_declarations")
	local bind_action_owner = upvalue(compile_language, "bind_action_owner")
	local base_action = upvalue(compile_group, "base_action")
	local build_style = upvalue(base_action, "build_style")
	local intern_style = upvalue(build_style, "intern_style")

	local captured = {
		language = {},
		resolved = {},
		groups = {},
		module_mods = {},
		build_styles = {},
		intern_styles = {},
	}

	local function interpreter_pass(fn)
		local jit_was_on = jit ~= nil and jit.status()
		if jit_was_on then
			jit.off()
			jit.flush()
		end
		local ok, result = xpcall(fn, debug.traceback)
		if jit_was_on then
			jit.on()
		end
		if not ok then
			error(result, 0)
		end
		return result
	end

	local function patched_pass(owner, wanted, factory)
		return interpreter_pass(function()
			local old, index = upvalue(owner, wanted)
			debug.setupvalue(owner, index, factory(old))
			local ok, result = xpcall(function()
				return theme.compile(root)
			end, debug.traceback)
			debug.setupvalue(owner, index, old)
			if not ok then
				error(result, 0)
			end
			return result
		end)
	end

	-- Capture the real setup specs once. No internal instrumentation is active in
	-- this pass, so the resulting compiled theme is also the clean seed object.
	captured.compiled = interpreter_pass(function()
		hl.language.setup = function(language, spec)
			local module = language_setup(language, spec)
			if module and module._cf_skip ~= true then
				captured.language[#captured.language + 1] = {
					language = language,
					spec = spec,
					source = module.source,
				}
			end
			return module
		end

		hl.plugin.setup = function(name, spec)
			local module = plugin_setup(name, spec)
			if module and module._cf_skip ~= true then
				captured.resolved[#captured.resolved + 1] = {
					kind = "plugin",
					name = name,
					spec = spec,
					source = module.source,
				}
			end
			return module
		end

		hl.ui.setup = function(spec)
			local module = ui_setup(spec)
			if module and module._cf_skip ~= true then
				captured.resolved[#captured.resolved + 1] = {
					kind = "ui",
					name = nil,
					spec = spec,
					source = module.source,
				}
			end
			return module
		end

		local ok, result = xpcall(function()
			return theme.compile(root)
		end, debug.traceback)

		hl.language.setup = language_setup
		hl.plugin.setup = plugin_setup
		hl.ui.setup = ui_setup

		if not ok then
			error(result, 0)
		end
		return result
	end)

	local action_buckets = {}
	local bucket_count = 0
	local function bucket(actions)
		local value = action_buckets[actions]
		if not value then
			bucket_count = bucket_count + 1
			value = bucket_count
			action_buckets[actions] = value
		end
		return value
	end

	-- These compiler upvalues are shared by language/plugin/ui compiler closures,
	-- so one patch observes every call without double-wrapping anything.
	patched_pass(compile_language, "compile_resolved_group", function(old)
		return function(actions, ...)
			captured.groups[#captured.groups + 1] = {
				bucket = bucket(actions),
				args = pack(...),
			}
			return old(actions, ...)
		end
	end)

	patched_pass(compile_language, "compile_module_mods", function(old)
		return function(actions, ...)
			captured.module_mods[#captured.module_mods + 1] = pack(...)
			return old(actions, ...)
		end
	end)

	-- build_style is likewise a shared upvalue of all style-producing helpers.
	patched_pass(base_action, "build_style", function(old)
		return function(...)
			captured.build_styles[#captured.build_styles + 1] = pack(...)
			return old(...)
		end
	end)

	patched_pass(build_style, "intern_style", function(old)
		return function(style)
			captured.intern_styles[#captured.intern_styles + 1] = style
			return old(style)
		end
	end)

	captured.bucket_count = bucket_count
	captured.compile_language = compile_language
	captured.compile_resolved = compile_resolved
	captured.compile_group = compile_group
	captured.compile_module_mods = compile_module_mods
	captured.module_declarations = module_declarations
	captured.bind_action_owner = bind_action_owner
	captured.build_style = build_style
	captured.intern_style = intern_style
	return captured
end

local function one_span(text, hl_group)
	return {
		{ col = 0, text = text, hl = hl_group },
	}
end

local function three_spans(prefix)
	return {
		{ col = 0, text = prefix .. "-a", hl = "Normal" },
		{ col = 16, text = prefix .. "-b", hl = "Comment" },
		{ col = 32, text = prefix .. "-c", hl = "Special" },
	}
end

local function float_lines(prefix, count)
	local lines = {}
	for i = 1, count do
		lines[i] = {
			{ col = 0, text = prefix .. i, hl = "Normal" },
			{ col = 20, text = tostring(i), hl = "Comment" },
			{ col = 32, text = "●", hl = "Special" },
		}
	end
	return lines
end

function M.run(opts)
	opts = opts or {}
	runtime_state = require("cf.fn.runtime")
	local root = config.theme_path
	assert(type(root) == "string" and root ~= "", "full_benchmark: cf.config.theme_path is not configured")

	local load_theme = upvalue(cf.reload, "load_theme")
	local theme_names = upvalue(theme.compile, "theme_names")
	local valid_theme_dir = upvalue(theme.compile, "valid_theme_dir")
	local resolve_reserved = upvalue(theme.compile, "resolve_reserved")
	local module_files = upvalue(theme.compile, "module_files")
	local execute = upvalue(theme.compile, "execute")
	local list_cf = upvalue(module_files, "list_cf")

	local colorscheme_event = upvalue(theme.apply, "colorscheme_event")
	local reset_highlights = upvalue(theme.apply, "reset_highlights")
	local refresh_consumers = upvalue(theme.apply, "refresh_consumers")
	local refresh_treesitter = upvalue(refresh_consumers, "refresh_treesitter")
	local refresh_lsp_semantic_tokens = upvalue(refresh_consumers, "refresh_lsp_semantic_tokens")

	local function refresh_consumers_no_redraw()
		if config.autoreload.treesitter then
			refresh_treesitter()
		end
		if config.autoreload.lsp then
			refresh_lsp_semantic_tokens()
		end
	end

	local seed = theme.compile(root)
	theme.apply(seed)

	local picker_target
	local picker_style
	for i = 1, #seed.modules do
		local actions = seed.modules[i].actions
		for n = 1, #actions do
			local action = actions[n]
			if action.kind == "resolver_style" and action._cf_owner_kind then
				local target = runtime_state.target(
					action._cf_owner_kind,
					action._cf_owner_name,
					action.type_name,
					action.typemod
				)
				local ok, state = pcall(runtime_state._picker_style_state, target)
				if ok and state and type(state.current) == "table" then
					picker_target = target
					picker_style = {}
					for key, value in pairs(state.current) do picker_style[key] = value end
					break
				end
			end
		end
		if picker_target then break end
	end

	local default_name, requested_active = theme.selection(root)
	local default_dir = vim.fs.joinpath(root, default_name)
	local active_name = requested_active
	local active_dir = vim.fs.joinpath(root, active_name)
	if not valid_theme_dir(active_dir) then
		active_name = default_name
		active_dir = default_dir
	end

	local color_path = assert(resolve_reserved(root, default_dir, active_dir, "color.cf"))
	local config_path = resolve_reserved(root, default_dir, active_dir, "config.cf")
	local active_files = module_files(active_dir, "active")
	local fallback_files = active_dir ~= default_dir and module_files(default_dir, "default") or {}
	local all_module_files = {}
	for i = 1, #active_files do all_module_files[#all_module_files + 1] = active_files[i] end
	for i = 1, #fallback_files do all_module_files[#all_module_files + 1] = fallback_files[i] end

	local preloaded_active = {}
	for i = 1, #active_files do
		preloaded_active[i] = {
			file = active_files[i],
			chunk = assert(loadfile(active_files[i].path)),
		}
	end
	local preloaded_fallback = {}
	for i = 1, #fallback_files do
		preloaded_fallback[i] = {
			file = fallback_files[i],
			chunk = assert(loadfile(fallback_files[i].path)),
		}
	end

	local dsl = capture_dsl(root)
	seed = dsl.compiled
	theme.apply(seed)

	local apply_actions = upvalue(hl._apply_modules, "apply_actions")
	local run_action = upvalue(apply_actions, "run_action")
	local action_less = upvalue(apply_actions, "action_less")
	local sorted_actions = flatten_actions(seed.modules)
	table.sort(sorted_actions, action_less)

	local actions_by_kind = {}
	for i = 1, #sorted_actions do
		local action = sorted_actions[i]
		local list = actions_by_kind[action.kind]
		if not list then
			list = {}
			actions_by_kind[action.kind] = list
		end
		list[#list + 1] = action
	end

	local runtime_names = {}
	for name in pairs(seed.runtime_modules or {}) do
		runtime_names[#runtime_names + 1] = name
	end
	table.sort(runtime_names)

	local function execute_preloaded(item)
		local token = hl._source_begin(item.file.path)
		hl._error_source_clear()
		local ok, result = pcall(item.chunk)
		if ok then
			hl._error_source_clear()
		end
		hl._source_end(token)
		if not ok then
			error(result, 0)
		end
		return result
	end

	local function replay_chunks()
		hl._active_begin()
		local ok, err = xpcall(function()
			for i = 1, #preloaded_active do
				execute_preloaded(preloaded_active[i])
			end
			if #preloaded_fallback > 0 then
				hl._fallback_begin()
				for i = 1, #preloaded_fallback do
					execute_preloaded(preloaded_fallback[i])
				end
			end
		end, debug.traceback)
		hl._compile_end()
		if not ok then
			error(err, 0)
		end
	end

	local function replay_setup_calls()
		hl._active_begin()
		local ok, err = xpcall(function()
			for i = 1, #dsl.language do
				local call = dsl.language[i]
				hl.language.setup(call.language, call.spec)
			end
			for i = 1, #dsl.resolved do
				local call = dsl.resolved[i]
				if call.kind == "plugin" then
					hl.plugin.setup(call.name, call.spec)
				else
					hl.ui.setup(call.spec)
				end
			end
		end, debug.traceback)
		hl._compile_end()
		if not ok then
			error(err, 0)
		end
	end

	local function replay_language_compilers()
		for i = 1, #dsl.language do
			local call = dsl.language[i]
			dsl.compile_language(call.language, call.spec, call.source)
		end
	end

	local function replay_resolved_compilers()
		for i = 1, #dsl.resolved do
			local call = dsl.resolved[i]
			dsl.compile_resolved(call.kind, call.name, call.spec, call.source)
		end
	end

	local function replay_module_declarations()
		for i = 1, #dsl.language do
			dsl.module_declarations(dsl.language[i].spec, "language")
		end
		for i = 1, #dsl.resolved do
			local call = dsl.resolved[i]
			dsl.module_declarations(call.spec, call.kind)
		end
	end

	local function replay_module_mods()
		for i = 1, #dsl.module_mods do
			local args = dsl.module_mods[i]
			dsl.compile_module_mods({}, unpack_args(args, 1, args.n))
		end
	end

	local function replay_groups()
		local buckets = {}
		for i = 1, dsl.bucket_count do buckets[i] = {} end
		for i = 1, #dsl.groups do
			local call = dsl.groups[i]
			dsl.compile_group(buckets[call.bucket], unpack_args(call.args, 1, call.args.n))
		end
	end

	local function replay_build_styles()
		for i = 1, #dsl.build_styles do
			local args = dsl.build_styles[i]
			dsl.build_style(unpack_args(args, 1, args.n))
		end
	end

	local function replay_intern_styles()
		for i = 1, #dsl.intern_styles do
			dsl.intern_style(dsl.intern_styles[i])
		end
	end

	local function replay_bind_owner()
		for i = 1, #seed.modules do
			local module = seed.modules[i]
			dsl.bind_action_owner(module.actions, module.kind, module.name)
		end
	end

	local own_session = opts.session ~= false and not benchmark.is_active()
	if own_session then
		benchmark.start()
	end

	local ok, err = xpcall(function()
		bench(opts, "00 baseline | empty Lua call", function() end)

		bench(opts, "01 end-to-end | cf.reload()", function()
			cf.reload()
		end)
		bench(opts, "01 end-to-end | load_theme() [diagnostic + theme.load]", function()
			load_theme()
		end)
		bench(opts, "01 end-to-end | theme.load()", function()
			theme.load(root)
		end)
		bench(opts, "01 end-to-end | theme.compile()", function()
			theme.compile(root)
		end)
		bench(opts, "01 end-to-end | theme.apply(precompiled)", function()
			theme.apply(seed)
		end)

		bench(opts, "02 compile/fs | theme.selection()", function()
			theme.selection(root)
		end)
		bench(opts, "02 compile/fs | theme.available()", function()
			theme.available(root)
		end)
		bench(opts, "02 compile/fs | theme_names()", function()
			theme_names(root)
		end)
		bench(opts, "02 compile/fs | list_cf(active) [" .. #active_files .. " files]", function()
			list_cf(active_dir)
		end)
		bench(opts, "02 compile/fs | valid_theme_dir(default)", function()
			valid_theme_dir(default_dir)
		end)
		bench(opts, "02 compile/fs | valid_theme_dir(active)", function()
			valid_theme_dir(active_dir)
		end)
		bench(opts, "02 compile/fs | resolve_reserved(color+config)", function()
			resolve_reserved(root, default_dir, active_dir, "color.cf")
			resolve_reserved(root, default_dir, active_dir, "config.cf")
		end)
		bench(opts, "02 compile/fs | module_files(active+fallback) [" .. #all_module_files .. " files]", function()
			module_files(active_dir, "active")
			if active_dir ~= default_dir then
				module_files(default_dir, "default")
			end
		end)
		bench(opts, "02 compile/load | loadfile(color+config)", function()
			assert(loadfile(color_path))
			if config_path then assert(loadfile(config_path)) end
		end)
		bench(opts, "02 compile/load | execute(color+config)", function()
			execute(color_path, "color.cf")
			if config_path then execute(config_path, "config.cf") end
		end)
		bench(opts, "02 compile/load | loadfile(all modules) [" .. #all_module_files .. " files]", function()
			for i = 1, #all_module_files do
				assert(loadfile(all_module_files[i].path))
			end
		end)
		bench(opts, "02 compile/load | execute preloaded module chunks [" .. #all_module_files .. " files]", replay_chunks)
		bench(opts, "02 compile/setup | hl._begin(colors, config)", function()
			hl._begin(seed.colors, seed.config)
		end)

		bench(opts, "03 DSL | setup() replay all [" .. (#dsl.language + #dsl.resolved) .. " calls]", replay_setup_calls)
		bench(opts, "03 DSL | compile_language_module all [" .. #dsl.language .. " calls]", replay_language_compilers)
		bench(opts, "03 DSL | compile_resolved_module all [" .. #dsl.resolved .. " calls]", replay_resolved_compilers)
		bench(opts, "03 DSL | module_declarations all [" .. (#dsl.language + #dsl.resolved) .. " calls]", replay_module_declarations)
		bench(opts, "03 DSL | compile_module_mods all [" .. #dsl.module_mods .. " calls]", replay_module_mods)
		bench(opts, "03 DSL | compile_resolved_group all [" .. #dsl.groups .. " calls]", replay_groups)
		bench(opts, "03 DSL | build_style all [" .. #dsl.build_styles .. " calls]", replay_build_styles)
		bench(opts, "03 DSL | intern_style all [" .. #dsl.intern_styles .. " calls]", replay_intern_styles)
		bench(opts, "03 DSL | bind_action_owner all [" .. #seed.modules .. " modules]", replay_bind_owner)

		bench(opts, "04 apply | ColorSchemePre autocmd", function()
			colorscheme_event("ColorSchemePre", seed.active)
		end)
		bench(opts, "04 apply | reset_highlights() [steady repeated]", reset_highlights, {
			teardown = function() theme.apply(seed) end,
		})
		bench(opts, "04 apply | refresh_catalog()", function()
			runtime.refresh_catalog()
		end)
		bench(opts, "04 apply | resolver.clear_cache()", function()
			resolver.clear_cache()
		end)
		bench(opts, "04 apply | runtime.global_clear()", function()
			runtime.global_clear(hl._global_clear())
		end)
		bench(opts, "04 apply | flatten + sort actions [" .. #sorted_actions .. " actions]", function()
			local actions = flatten_actions(seed.modules)
			table.sort(actions, action_less)
		end)
		bench(opts, "04 apply | run_action all [" .. #sorted_actions .. " actions]", function()
			for i = 1, #sorted_actions do
				run_action(sorted_actions[i])
			end
		end)
		bench(opts, "04 apply | resolver.clear_cache + _apply_modules [" .. #sorted_actions .. " actions]", function()
			resolver.clear_cache()
			hl._apply_modules(seed.modules)
		end)
		bench(opts, "04 apply | _apply_modules cached [" .. #sorted_actions .. " actions]", function()
			hl._apply_modules(seed.modules)
		end)

		local action_order = { "resolver_style", "resolver_link", "resolver_clear", "raw_style", "raw_link", "raw_clear" }
		for i = 1, #action_order do
			local kind = action_order[i]
			local actions = actions_by_kind[kind]
			if actions and #actions > 0 then
				bench(opts, "04 apply/action | " .. kind .. " [" .. #actions .. " actions]", function()
					for n = 1, #actions do
						run_action(actions[n])
					end
				end)
			end
		end

		if runtime_state then
			bench(opts, "04 apply | runtime _theme_prepare()", function()
				runtime_state._theme_prepare(seed)
			end)
		end
		bench(opts, "04 apply | ColorScheme autocmd", function()
			colorscheme_event("ColorScheme", seed.active)
		end)
		if runtime_state then
			bench(opts, "04 apply | runtime _theme_applied()", function()
				runtime_state._theme_applied(seed)
			end)
		end
		bench(opts, "04 apply | refresh_consumers() no redraw", refresh_consumers_no_redraw)
		bench(opts, "04 apply/consumer | treesitter only", refresh_treesitter)
		bench(opts, "04 apply/consumer | lsp semantic tokens only", refresh_lsp_semantic_tokens)
		bench(opts, "04 apply/consumer | redraw! only", function()
			vim.cmd("redraw!")
		end)
		bench(opts, "04 apply/consumer | treesitter + lsp + redraw!", function()
			refresh_treesitter()
			refresh_lsp_semantic_tokens()
			vim.cmd("redraw!")
		end)
		bench(opts, "04 apply | refresh_consumers() [configured]", refresh_consumers)

		if #runtime_names > 0 then
			bench(opts, "05 runtime | theme.load_runtime all [" .. #runtime_names .. " modules]", function()
				for i = 1, #runtime_names do
					theme.load_runtime(seed, runtime_names[i])
				end
			end)
		end
		if picker_target and picker_style then
			bench(opts, "05 runtime | picker style state", function()
				runtime_state._picker_style_state(picker_target)
			end)
			bench(opts, "05 runtime | picker style write", function()
				runtime_state._picker_set_style(picker_target, picker_style)
			end, {
				teardown = function() theme.apply(seed) end,
			})
		end
		bench(opts, "05 runtime | lineblend.refresh() [current state]", function()
			lineblend.refresh()
		end)
		bench(opts, "05 runtime | lineblend.reload() [current state]", function()
			lineblend.reload()
		end)
		bench(opts, "05 runtime | watcher.is_running()", function()
			watcher.is_running()
		end)
		if watcher.is_running() then
			bench(opts, "05 runtime | watcher.set_themes()", function()
				watcher.set_themes(seed.default, seed.requested_active)
			end)
		end

		bench(opts, "06 diagnostic | _enabled(error+hint)", function()
			diagnostic._enabled("error")
			diagnostic._enabled("hint")
		end)
		bench(opts, "06 diagnostic | clear_pending()", function()
			diagnostic.clear_pending()
		end)
		bench(opts, "06 diagnostic | flush() empty", function()
			diagnostic.clear_pending()
			diagnostic.flush()
		end)

		local trace_file = seed.module_files and seed.module_files[1]
		if trace_file then
			local trace_path = trace_file.path
			bench(opts, "06 colortrace | _source_mode(current flags)", function()
				colortrace._source_mode(trace_path)
			end)

			if colortrace.picker_enabled() then
				local cached = colortrace._cached(trace_path, seed)
				if cached then
					bench(opts, "06 colortrace | _cached(file)", function()
						colortrace._cached(trace_path, seed)
					end)
					bench(opts, "06 colortrace | scan cached records [" .. #cached.records .. "]", function()
						local records = cached.records
						for i = 1, #records do
							local record = records[i]
							local _ = record.trace
						end
					end)
				end
			end
		end

		local float = Float.new({
			width = 80,
			height = 20,
			relative = "editor",
			row = 1,
			col = 1,
			border = "none",
			focusable = false,
		})
		local same = one_span("same", "Normal")
		float:set_line(1, same)
		float:open()
		bench(opts, "07 float | set_line same reference", function()
			float:set_line(1, same)
		end)

		local a3 = three_spans("alpha")
		local b3 = three_spans("bravo")
		local toggle3 = false
		bench(opts, "07 float | replace 3 spans", function()
			toggle3 = not toggle3
			float:set_line(1, toggle3 and a3 or b3)
		end)

		local lines_a = float_lines("a-", 20)
		local lines_b = float_lines("b-", 20)
		local toggle_lines = false
		float:set_lines(1, lines_a)
		bench(opts, "07 float | set_lines 20x3 spans", function()
			toggle_lines = not toggle_lines
			float:set_lines(1, toggle_lines and lines_a or lines_b)
		end)
		bench(opts, "07 float | flush all 20x3 spans", function()
			float:flush()
		end)
		bench(opts, "07 float | hide + open", function()
			float:hide()
			float:open()
		end)
		float:close()
	end, debug.traceback)

	pcall(theme.apply, seed)

	if own_session then
		benchmark.stop()
	end

	if not ok then
		error(err, 0)
	end

	return true
end

return M
