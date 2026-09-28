-- Full ChromaFlow benchmark and report.
--
-- The measurement engine is tests/benchmark.lua. This file only defines what
-- to measure, chooses a sensible sample/batch profile for each class of work,
-- and turns the raw statistics into an interpretable report.
--
-- Normal use from this file:
--   local b = dofile(vim.api.nvim_get_runtime_file("tests/full_benchmark.lua", false)[1])
--   b.start()                     -- bundled examples/themes
--   b.start("/path/to/themes")    -- another theme root
--
-- start() performs the minimal user setup itself: cf.setup({ theme_path = ... }).
-- No existing ChromaFlow setup is required for a fresh Neovim session.

local function source_dir()
	local source = debug.getinfo(1, "S").source
	assert(type(source) == "string" and source:sub(1, 1) == "@", "full_benchmark: source path is unavailable")
	return vim.fs.dirname(vim.fs.normalize(source:sub(2)))
end

local HERE = source_dir()
local PLUGIN_ROOT = vim.fs.dirname(HERE)
local DEFAULT_THEME_ROOT = vim.fs.joinpath(PLUGIN_ROOT, "examples", "themes")

local function load_benchmark()
	local sibling = vim.fs.joinpath(HERE, "benchmark.lua")
	local chunk = loadfile(sibling)
	if chunk then
		return chunk()
	end
	return require("tools.benchmark")
end

local benchmark = load_benchmark()
local cf = require("cf")
local color = require("cf.color")
local bxor = require("bit").bxor
local config = require("cf.config")
local colortrace = require("cf.colortrace")
local diagnostic = require("cf.diagnostic")
local Float = require("cf.fn.float")
local lineblend = require("cf.fn.lineblend")
local runtime_state = require("cf.fn.runtime")
local hl = require("cf.hl.setup")
local pipeline = require("cf.hl.pipeline")
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

local PROFILES = {
	-- Expensive, user-visible operations. Batch=1 preserves real call shape.
	end_to_end = { count = 100, batch = 1, warmup = 10 },
	heavy = { count = 100, batch = 1, warmup = 15 },
	-- Filesystem/API sized work. A small batch smooths timer boundaries without
	-- turning each sample into a large synthetic workload.
	medium = { count = 100, batch = 5, warmup = 20 },
	-- Low-microsecond internals.
	micro = { count = 100, batch = 100, warmup = 25 },
	-- Sub-microsecond/session-cache paths.
	tiny = { count = 100, batch = 1000, warmup = 25 },
	-- Pure colour/math primitives where timer cost otherwise dominates.
	nano = { count = 100, batch = 10000, warmup = 25 },
	-- Editor consumer/redraw work should never be multiplied into a huge batch.
	external = { count = 100, batch = 1, warmup = 8 },
}

local active_results
local seen_progress_sections

local function contains(value, needle)
	return value:find(needle, 1, true) ~= nil
end

local function section_for(name)
	if contains(name, "empty Lua call") then return "baseline" end
	if contains(name, "end-to-end") then return "user" end
	if contains(name, "compile/fs") or contains(name, "compile/load") or contains(name, "compile/setup") then
		return "theme"
	end
	if contains(name, "DSL |") then return "dsl" end
	if contains(name, "_apply_modules") then return "apply" end
	if contains(name, "resolver |") or contains(name, "resolver.clear_cache") then return "resolver" end
	if contains(name, "color |") or contains(name, "pipeline |") then return "color" end
	if contains(name, "apply/consumer") or contains(name, "refresh_consumers") then return "consumer" end
	if contains(name, "04 apply") then return "apply" end
	if contains(name, "runtime |") or contains(name, "lineblend") or contains(name, "watcher")
		or contains(name, "refresh_catalog") or contains(name, "runtime.global_clear") then
		return "runtime"
	end
	if contains(name, "diagnostic |") or contains(name, "colortrace |") then return "diagnostic" end
	if contains(name, "float |") then return "float" end
	return "misc"
end

local SECTION_INFO = {
	baseline = {
		title = "Measurement baseline",
		description = "Timer/closure floor for the same benchmark engine. Use it only to judge very small measurements; it is not subtracted from results.",
	},
	user = {
		title = "User-facing end-to-end",
		description = "The operations a user actually feels: reload, complete load, compile and apply. These are the first numbers to compare between machines or releases.",
	},
	theme = {
		title = "Theme discovery and source loading",
		description = "Filesystem discovery, reserved files, Lua chunk loading/execution and the initial compiler setup. This decomposes the front half of theme.compile().",
	},
	dsl = {
		title = "DSL compiler",
		description = "Replays captured real declarations from the selected theme through the actual internal compiler functions. Aggregate probes report a per-item cost where possible.",
	},
	resolver = {
		title = "Highlight resolver",
		description = "Hot cached resolver shapes plus one deliberately cold cache-rebuild path. The variants show the cost of type, modifier, TypeMod, filetype, literal and target filtering.",
	},
	color = {
		title = "Colour engine and pipeline",
		description = "Packed-RGBA conversion/manipulation and prebuilt pipeline execution. Pure operations use large batches because they are near the timer floor.",
	},
	apply = {
		title = "Highlight apply",
		description = "Action flatten/sort, resolver/raw actions and theme apply bookkeeping. This is the back half of a compiled theme load before editor consumers redraw.",
	},
	consumer = {
		title = "Editor consumers and redraw",
		description = "Tree-sitter/LSP refresh hooks and Neovim redraw. These are intentionally low-batch because they are external editor work, not a tight Lua hot loop.",
	},
	runtime = {
		title = "Runtime, picker, LineBlend and watcher",
		description = "Session-state helpers and optional runtime/UI integration. This section makes the cost of sparse runtime state and surrounding services visible separately from core compile/apply.",
	},
	diagnostic = {
		title = "Diagnostics and source tracing",
		description = "Diagnostic gates/queues and picker/debug source tracing in the currently active feature configuration.",
	},
	float = {
		title = "Float renderer",
		description = "The reusable float diff renderer used by ChromaFlow UI. Same-reference, span replacement, bulk line updates and window open/hide are measured separately.",
	},
	misc = {
		title = "Other",
		description = "Additional internal probes that do not fit another category.",
	},
}

local SECTION_ORDER = {
	"baseline", "user", "theme", "dsl", "resolver", "color", "apply",
	"consumer", "runtime", "diagnostic", "float", "misc",
}

local function profile_for(name)
	if contains(name, "baseline") or contains(name, "color |") then
		return PROFILES.nano
	end
	if contains(name, "pipeline |") then
		return PROFILES.tiny
	end
	if contains(name, "end-to-end") then
		return PROFILES.end_to_end
	end
	if contains(name, "redraw") or contains(name, "treesitter") or contains(name, "lsp semantic")
		or contains(name, "hide + open") then
		return PROFILES.external
	end
	if contains(name, "resolver | cold") then
		return PROFILES.micro
	end
	if contains(name, "resolver |") or contains(name, "resolver.clear_cache()") or contains(name, "diagnostic |") or contains(name, "colortrace |")
		or contains(name, "picker style") or contains(name, "watcher.is_running") then
		return PROFILES.tiny
	end
	if contains(name, "execute preloaded module chunks") or contains(name, "loadfile(all modules)")
		or contains(name, "DSL | setup()") or contains(name, "compile_language_module all")
		or contains(name, "compile_resolved_module all") or contains(name, "compile_resolved_group all")
		or contains(name, "build_style all") or contains(name, "intern_style all")
		or contains(name, "run_action all") or contains(name, "_apply_modules")
		or contains(name, "theme.load_runtime all") or contains(name, "lineblend.reload") then
		return PROFILES.heavy
	end
	if contains(name, "float |") then
		return PROFILES.micro
	end
	if contains(name, "compile/fs") or contains(name, "compile/load") or contains(name, "compile/setup")
		or contains(name, "04 apply") or contains(name, "runtime |") or contains(name, "lineblend")
		or contains(name, "watcher") then
		return PROFILES.medium
	end
	return PROFILES.medium
end

local function benchmark_opts(opts, name, extra)
	local profile = profile_for(name)
	local out = {
		count = opts.count or profile.count,
		batch = opts.batch or profile.batch,
		warmup = opts.warmup == nil and profile.warmup or opts.warmup,
	}
	if extra then
		for key, value in pairs(extra) do
			out[key] = value
		end
	end
	return out
end

local function bench(opts, name, fn, extra)
	local run_opts = benchmark_opts(opts, name, extra)
	local section = section_for(name)
	if not seen_progress_sections[section] then
		seen_progress_sections[section] = true
		local info = SECTION_INFO[section]
		vim.api.nvim_echo({ { "ChromaFlow benchmark: " .. (info and info.title or section), "ModeMsg" } }, false, {})
	end
	local result = benchmark.run(name, fn, run_opts)
	result.warmup = run_opts.warmup
	result.section = section
	if active_results then
		active_results[#active_results + 1] = result
	end
	return result
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


local function format_time(value)
	if value < 1000 then
		return string.format("%.3f µs", value)
	elseif value < 1000000 then
		return string.format("%.3f ms", value / 1000)
	end
	return string.format("%.3f s", value / 1000000)
end

local function format_count(result)
	if result.batch > 1 then
		return string.format("%d samples × %d calls", result.count, result.batch)
	end
	return string.format("%d samples × 1 call", result.count)
end

local function tail_label(result)
	if result.avg <= 0 then return "n/a" end
	if result.avg < 0.01 then return "timer-floor dominated" end
	local ratio = result.p99 / result.avg
	local label
	if ratio <= 1.25 then label = "very tight"
	elseif ratio <= 1.75 then label = "tight"
	elseif ratio <= 3 then label = "visible tails"
	else label = "wide tails" end
	return string.format("%.2f× avg (%s)", ratio, label)
end

local function item_count(name)
	local value, unit = name:match("%[(%d+) ([^%]]+)%]")
	value = tonumber(value)
	if not value or value <= 0 then return nil end
	return value, unit
end

local function clean_name(name)
	return (name:gsub("^%d+ [^|]+ | ", ""))
end

local function explanation(name)
	if contains(name, "empty Lua call") then
		return "Measures the benchmark loop with an empty Lua closure.",
			"Reference floor for sub-microsecond probes; it is not subtracted from any result."
	elseif contains(name, "cf.reload()") then
		return "Calls the public cf.reload() path on the selected theme.",
			"Closest single number to the cost a user pays for a normal ChromaFlow reload: diagnostic cycle, theme load/apply, watcher scope update when active, and cached LineBlend refresh."
	elseif contains(name, "load_theme()") then
		return "Calls the internal reload helper around theme.load(), including diagnostic clear/flush.",
			"Shows ChromaFlow's theme work before watcher/LineBlend post-work from cf.reload()."
	elseif contains(name, "theme.load()") then
		return "Compiles the theme and immediately applies the compiled result.",
			"Core load cost without the public reload wrapper."
	elseif contains(name, "theme.compile()") then
		return "Discovers theme files, executes the DSL and produces the compiled theme object.",
			"Front half of a reload; no Neovim highlight application is included."
	elseif contains(name, "theme.apply(precompiled)") then
		return "Applies an already compiled theme object.",
			"Back half of a reload: highlight reset/apply, runtime bookkeeping, events and configured consumers."
	elseif contains(name, "theme.selection()") then
		return "Reads and resolves the .cf-theme default/active selection.", "Theme-selection filesystem overhead."
	elseif contains(name, "theme.available()") then
		return "Scans the theme root for valid selectable themes.", "Cost of populating the theme list/menu, not a per-highlight hot path."
	elseif contains(name, "theme_names()") then
		return "Enumerates candidate theme directory names used by the compiler.", "Low-level directory-name discovery cost."
	elseif contains(name, "list_cf(active)") then
		return "Lists .cf modules in the active theme directory.", "Filesystem cost of discovering active theme modules."
	elseif contains(name, "valid_theme_dir") then
		return "Validates a candidate theme directory.", "Selection/fallback validation cost."
	elseif contains(name, "resolve_reserved") then
		return "Resolves color.cf and config.cf across active/default fallback rules.", "Reserved-file lookup cost for one compile."
	elseif contains(name, "module_files(active+fallback)") then
		return "Builds active/default module file lists with fallback scope metadata.", "Module-discovery cost before source execution."
	elseif contains(name, "loadfile(color+config)") then
		return "Compiles reserved color/config Lua chunks with loadfile(), without executing them.", "Lua parser/loader cost for reserved files."
	elseif contains(name, "execute(color+config)") then
		return "Loads and executes color.cf/config.cf through ChromaFlow's source wrapper.", "Reserved source execution plus ChromaFlow source bookkeeping."
	elseif contains(name, "loadfile(all modules)") then
		return "Runs loadfile() for every active/fallback theme module.", "Lua parse/load cost for the complete module set, excluding module execution."
	elseif contains(name, "execute preloaded module chunks") then
		return "Executes already-loaded real module chunks through active/fallback compiler phases.", "DSL execution cost with filesystem parsing removed."
	elseif contains(name, "hl._begin") then
		return "Initializes the highlight compiler with the already loaded colours and theme config.", "Fixed compiler setup cost per compile."
	elseif contains(name, "DSL | setup() replay all") then
		return "Replays every captured language/plugin/ui setup call from the real theme.", "Aggregate public DSL setup/compiler cost for this exact theme."
	elseif contains(name, "compile_language_module all") then
		return "Calls the internal language-module compiler for every captured language declaration.", "Language-specific DSL compile contribution."
	elseif contains(name, "compile_resolved_module all") then
		return "Calls the plugin/ui resolved-module compiler for every captured declaration.", "Plugin/UI DSL compile contribution."
	elseif contains(name, "module_declarations all") then
		return "Extracts declaration tables from every module spec.", "Cost of turning user DSL tables into compiler declaration streams."
	elseif contains(name, "compile_module_mods all") then
		return "Replays per-module modifier compilation.", "Modifier declaration overhead across the selected theme."
	elseif contains(name, "compile_resolved_group all") then
		return "Replays every captured resolved highlight group compiler call.", "One of the main inner DSL compilation loops; per-item cost is useful here."
	elseif contains(name, "build_style all") then
		return "Builds every captured style object from the real theme.", "Style normalization/pipeline/cache lookup contribution during DSL compilation."
	elseif contains(name, "intern_style all") then
		return "Interns every captured normalized style into the session style cache.", "Style deduplication/cache contribution."
	elseif contains(name, "bind_action_owner all") then
		return "Binds compiled actions to their language/plugin/ui owners.", "Runtime/picker ownership metadata cost per compiled module."
	elseif contains(name, "resolver | cold") then
		return "Clears resolver caches and resolves a type on every measured call.", "Deliberately cold resolver rebuild cost; compare with the hot resolver variants below."
	elseif contains(name, "resolver | type + 2 modifiers") then
		return "Resolves one type with two modifiers using a cached style object.", "Hot multi-modifier resolver cost."
	elseif contains(name, "resolver | explicit TypeMod") then
		return "Resolves a style owned by one explicit type+modifier combination.", "Hot TypeMod-style path, distinct from a free modifier."
	elseif contains(name, "resolver | type + modifier") then
		return "Resolves one type+modifier combination using a cached style object.", "Common hot semantic-token TypeMod path."
	elseif contains(name, "resolver | modifier only") then
		return "Resolves a modifier without an owning type.", "Hot free-modifier path."
	elseif contains(name, "resolver | type + filetype") then
		return "Resolves a type with filetype-specific semantic context.", "Hot filetype-qualified resolver path."
	elseif contains(name, "resolver | literal") then
		return "Resolves an unknown/literal highlight name instead of a normal semantic type.", "Literal escape-path cost for names outside the standard semantic chain."
	elseif contains(name, "resolver | target=") then
		return "Resolves a type while materializing only one target mask.", "Fast target-filtered resolver path after session caches are warm."
	elseif contains(name, "resolver | type only") then
		return "Resolves a normal semantic type using a cached style object.", "Baseline hot type resolver path."
	elseif contains(name, "resolver.clear_cache + _apply_modules") then
		return "Clears resolver caches and then applies every compiled module.", "Cold full-module apply path after resolver invalidation."
	elseif contains(name, "resolver.clear_cache") then
		return "Drops resolver session lookup caches.", "Invalidation cost paid only when the resolver cache must be rebuilt."
	elseif contains(name, "color | dynamic input baseline") then
		return "Mutates the packed colour input with one BitOp xor and stores it for the next call.", "Control cost used to keep pure colour probes data-dependent so LuaJIT cannot constant-fold the operation away."
	elseif contains(name, "color | string input baseline") then
		return "Alternates between two existing hex-string references.", "Control cost for the dynamic from_hex() probe; not subtracted automatically."
	elseif contains(name, "color | from_hex") then
		return "Parses #RRGGBB into ChromaFlow's packed 0xAARRGGBB representation.", "Colour-string boundary conversion."
	elseif contains(name, "color | to_rgb_hex") then
		return "Formats packed RGBA as #RRGGBB.", "Final GUI highlight colour rendering cost."
	elseif contains(name, "color | to_cterm") then
		return "Quantizes packed RGB to the nearest xterm-256 palette entry.", "Terminal colour quantization cost."
	elseif contains(name, "color | from_cterm") then
		return "Decodes an xterm-256 palette index to packed RGBA.", "Terminal pipeline input conversion."
	elseif contains(name, "color | mix") then
		return "Mixes two packed colours using the numeric RGB/RGBA path.", "One mix pipeline primitive."
	elseif contains(name, "color | opacity") then
		return "Computes effective alpha and pre-composited RGB against a background.", "One opacity pipeline primitive."
	elseif contains(name, "color | brightness") then
		return "Applies signed brightness to packed RGB channels.", "One brightness pipeline primitive."
	elseif contains(name, "color | lighten") or contains(name, "color | darken") then
		return "Applies the one-direction brightness convenience primitive.", "One lighten/darken pipeline primitive."
	elseif contains(name, "color | shiftHue") then
		return "Converts RGB↔HSL internally and rotates hue on a packed colour.", "The mathematically heaviest normal colour primitive."
	elseif contains(name, "color | gamma") then
		return "Applies gamma correction to packed RGB channels.", "One gamma pipeline primitive."
	elseif contains(name, "pipeline | construct") then
		return "Creates one pipeline operation table through the public channel API.", "The allocation cost paid while compiling/creating a pipeline, not while applying a prebuilt pipeline."
	elseif contains(name, "pipeline | apply nil") then
		return "Calls pipeline.apply() with no operations.", "Early-return floor for styles without a pipeline."
	elseif contains(name, "pipeline | apply 1 op") then
		return "Applies one prebuilt pipeline operation to packed colours.", "Single-operation runtime pipeline cost with construction excluded."
	elseif contains(name, "pipeline | apply 7 ops") then
		return "Applies a prebuilt seven-operation mixed pipeline.", "Representative multi-operation pipeline execution cost."
	elseif contains(name, "ColorSchemePre autocmd") then
		return "Executes only the ColorSchemePre event used by theme.apply().", "External autocmd contribution before highlight replacement."
	elseif contains(name, "reset_highlights") then
		return "Clears/reinitializes highlights in the same steady repeated state used by apply.", "Neovim highlight reset contribution."
	elseif contains(name, "refresh_catalog") then
		return "Refreshes the runtime highlight catalog.", "Runtime lookup/catalog maintenance after theme changes."
	elseif contains(name, "runtime.global_clear") then
		return "Propagates the compiler's global clear state into runtime state.", "Runtime clear bookkeeping during apply."
	elseif contains(name, "flatten + sort actions") then
		return "Flattens all module actions and sorts them by apply priority.", "Pure Lua action scheduling cost before Neovim writes."
	elseif contains(name, "run_action all") then
		return "Executes every already-sorted compiled action one by one.", "Core action execution cost for the complete theme."
	elseif contains(name, "resolver.clear_cache + _apply_modules") then
		return "Invalidates resolver caches then applies every compiled module.", "Cold apply-modules path after invalidation."
	elseif contains(name, "_apply_modules cached") then
		return "Applies every compiled module with resolver session caches already warm.", "Steady repeated module-apply path."
	elseif contains(name, "apply/action |") then
		return "Executes only the compiled actions of the named action kind.", "Breakdown of total action execution by resolver/raw style/link/clear kind."
	elseif contains(name, "runtime _theme_prepare") then
		return "Prepares sparse runtime overlays for an incoming compiled theme.", "Runtime pre-apply bookkeeping."
	elseif contains(name, "runtime _theme_applied") then
		return "Rebinds/recomposes surviving sparse runtime overlays after apply.", "Runtime post-apply bookkeeping."
	elseif contains(name, "ColorScheme autocmd") then
		return "Executes only the ColorScheme event.", "External autocmd contribution after highlights are applied."
	elseif contains(name, "refresh_consumers() no redraw") then
		return "Runs only configured Tree-sitter/LSP consumer refreshes, excluding redraw.", "Optional editor-consumer cost controlled by autoreload settings."
	elseif contains(name, "treesitter only") then
		return "Forces the Tree-sitter refresh helper in the current editor state.", "External Tree-sitter refresh cost; highly buffer/config dependent."
	elseif contains(name, "lsp semantic tokens only") then
		return "Forces the semantic-token refresh helper in the current editor state.", "External LSP semantic-token refresh cost; highly client/buffer dependent."
	elseif contains(name, "redraw! only") then
		return "Runs Neovim redraw! with no ChromaFlow work around it.", "Editor redraw cost ChromaFlow cannot meaningfully optimize internally."
	elseif contains(name, "treesitter + lsp + redraw") then
		return "Runs all consumer refresh helpers followed by redraw!.", "Upper consumer-side combination in the current editor state."
	elseif contains(name, "refresh_consumers() [configured]") then
		return "Runs the exact consumer policy currently configured in cf.config.", "Consumer tail included by theme.apply() for this benchmark setup."
	elseif contains(name, "theme.load_runtime all") then
		return "Loads every runtime .cf module requested by the compiled theme.", "Runtime module lookup/execute cost for the selected theme."
	elseif contains(name, "picker style state") then
		return "Reads the current sparse picker/runtime state for one real compiled target.", "Picker inspection cost before editing a style."
	elseif contains(name, "picker style write") then
		return "Writes one style through the runtime picker overlay path.", "Cost of one live picker style update, excluding UI key handling/rendering."
	elseif contains(name, "lineblend.refresh") then
		return "Runs LineBlend's cached refresh in the current state.", "Normal ChromaFlow post-reload LineBlend interaction."
	elseif contains(name, "lineblend.reload") then
		return "Runs LineBlend's hard reload path.", "Expensive diagnostic comparison only; ChromaFlow intentionally does not hard-reload LineBlend on normal reloads."
	elseif contains(name, "watcher.is_running") then
		return "Checks watcher state.", "Tiny service-state query."
	elseif contains(name, "watcher.set_themes") then
		return "Updates watcher default/active theme scopes without rebuilding the watcher.", "Normal watcher bookkeeping after a reload when watching is active."
	elseif contains(name, "diagnostic | _enabled") then
		return "Runs the diagnostic policy gate for two severities.", "Producer-side early-out cost in the active debug/severity configuration."
	elseif contains(name, "diagnostic | clear_pending") then
		return "Clears the pending diagnostic queue.", "Per-theme-cycle queue reset cost."
	elseif contains(name, "diagnostic | flush() empty") then
		return "Flushes an empty diagnostic queue after clearing it.", "No-record end-of-cycle diagnostic overhead."
	elseif contains(name, "colortrace | _source_mode") then
		return "Determines source tracing mode for one real theme file.", "Debug/picker source-trace gate cost."
	elseif contains(name, "colortrace | _cached(file)") then
		return "Looks up cached source-trace data for one real theme file.", "Hot picker/debug source cache lookup."
	elseif contains(name, "scan cached records") then
		return "Iterates the cached source-trace records for one real file.", "Cost of consuming trace metadata after lookup."
	elseif contains(name, "float | set_line same reference") then
		return "Sets a float line to the exact same span-table reference.", "Best-case early-out of the float diff renderer."
	elseif contains(name, "float | replace 3 spans") then
		return "Alternates one float line between two three-span layouts.", "Typical small diff/update cost."
	elseif contains(name, "float | set_lines 20x3 spans") then
		return "Alternates twenty lines containing three spans each.", "Bulk float model-update cost before explicit flush."
	elseif contains(name, "float | flush all 20x3 spans") then
		return "Flushes the current twenty-line/three-span float state to Neovim.", "Bulk renderer→Neovim write cost."
	elseif contains(name, "float | hide + open") then
		return "Hides and reopens the same float window.", "Window lifecycle cost rather than line diff cost."
	end
	return "Measures the named internal ChromaFlow phase directly.", "White-box decomposition probe; interpret it in the surrounding category rather than as a public API guarantee."
end

local function result_lines(result)
	local lines = {}
	local measured, represents = explanation(result.name)
	lines[#lines + 1] = "### " .. clean_name(result.name)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "- Measures: " .. measured
	lines[#lines + 1] = "- Represents: " .. represents
	lines[#lines + 1] = string.format("- Profile: %s; warmup %d calls.", format_count(result), result.warmup or 0)
	lines[#lines + 1] = ""
	lines[#lines + 1] = string.format(
		"`min %s · avg %s · p50 %s · p90 %s · p95 %s · p99 %s · max %s`",
		format_time(result.min), format_time(result.avg), format_time(result.p50), format_time(result.p90),
		format_time(result.p95), format_time(result.p99), format_time(result.max)
	)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "Tail: " .. tail_label(result) .. "."
	local count, unit = item_count(result.name)
	if count then
		lines[#lines + 1] = string.format("Average per listed item: **%s / %s**.", format_time(result.avg / count), unit:gsub("s$", ""))
	end
	return lines
end

local function find_result(results, needle)
	for i = 1, #results do
		if contains(results[i].name, needle) then return results[i] end
	end
end

local function append(lines, values)
	for i = 1, #values do lines[#lines + 1] = values[i] end
end

local function bool(value)
	return value and "true" or "false"
end

local function build_report(results, context)
	local lines = {
		"# ChromaFlow Full Benchmark",
		"",
		"This report separates user-visible end-to-end cost from white-box decomposition. Detailed sections overlap by design and **must not be added together**: many probes replay the same work at different boundaries, and cache state is intentionally measured both hot and cold.",
		"",
		"## Benchmark setup",
		"",
		"- Theme root: `" .. context.root .. "`",
		"- Default / active theme: `" .. context.default_name .. "` / `" .. context.active_name .. "`",
		string.format("- Theme shape: **%d modules**, **%d compiled actions**, **%d active module files**, **%d fallback files**, **%d runtime modules**.", context.modules, context.actions, context.active_files, context.fallback_files, context.runtime_modules),
		string.format("- Style cache after compile: **%d interned styles**.", context.style_cache),
		string.format("- ChromaFlow flags: picker=%s, diagnostic.debug=%s, watch=%s (running=%s), autoreload.lsp=%s, autoreload.treesitter=%s, lineblend.autostart=%s (active=%s), alpha=%s.",
			bool(context.picker), bool(context.debug), bool(context.watch), bool(context.watcher_running), bool(context.lsp), bool(context.treesitter), bool(context.lineblend_autostart), bool(context.lineblend_active), bool(context.alpha)),
		"- `start()` benchmarks ChromaFlow's built-in defaults independently of the caller's active setup, then restores the previous setup after the report is built.",
		string.format("- Runtime: Neovim %s, %s, JIT=%s, logical CPUs=%s.", context.nvim, context.platform, context.jit, tostring(context.cpus)),
		"- Measurement engine: `tests/benchmark.lua`; GC is collected before each benchmark, then the listed warmup is executed before timed samples.",
		"- Every probe keeps 100 statistical samples so p99 is meaningful; batch size is adapted to the expected operation cost (1 for ms/editor work up to 10,000 for pure colour math).",
		"",
		"## User-facing summary",
		"",
		"These are the values to look at first. The lower sections explain where they come from.",
		"",
		"| Operation | Avg | p95 | p99 | Tail | Meaning |",
		"| --- | ---: | ---: | ---: | --- | --- |",
	}

	local summaries = {
		{ "cf.reload()", "Public reload path" },
		{ "load_theme()", "Theme load plus diagnostic cycle" },
		{ "theme.load()", "Compile + apply" },
		{ "theme.compile()", "Compile only" },
		{ "theme.apply(precompiled)", "Apply an already compiled theme" },
	}
	for i = 1, #summaries do
		local result = find_result(results, summaries[i][1])
		if result then
			lines[#lines + 1] = string.format("| `%s` | %s | %s | %s | %s | %s |",
				summaries[i][1], format_time(result.avg), format_time(result.p95), format_time(result.p99), tail_label(result), summaries[i][2])
		end
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "### Reading the top numbers"
	lines[#lines + 1] = ""
	local reload = find_result(results, "cf.reload()")
	local compile = find_result(results, "theme.compile()")
	local apply = find_result(results, "theme.apply(precompiled)")
	if reload and compile and apply then
		lines[#lines + 1] = string.format("- `cf.reload()` averages **%s** with p99 **%s** (%s).", format_time(reload.avg), format_time(reload.p99), tail_label(reload))
		lines[#lines + 1] = string.format("- Standalone compile is **%s** and standalone apply is **%s**. As rough orientation those are %.1f%% and %.1f%% of reload average, but they are **not additive** because the probes have different boundaries/cache state.",
			format_time(compile.avg), format_time(apply.avg), compile.avg / reload.avg * 100, apply.avg / reload.avg * 100)
	end
	local action = find_result(results, "run_action all")
	if action and context.actions > 0 then
		lines[#lines + 1] = string.format("- Executing all **%d** already-compiled actions averages **%s**, or about **%s per action** in this aggregate probe.", context.actions, format_time(action.avg), format_time(action.avg / context.actions))
	end
	local groups = find_result(results, "compile_resolved_group all")
	local group_count = groups and item_count(groups.name)
	if groups and group_count then
		lines[#lines + 1] = string.format("- The captured DSL resolves %d groups in **%s** on average (~**%s/group**).", group_count, format_time(groups.avg), format_time(groups.avg / group_count))
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "## Detailed decomposition"
	lines[#lines + 1] = ""

	for _, section in ipairs(SECTION_ORDER) do
		local found = false
		for i = 1, #results do
			if results[i].section == section then found = true; break end
		end
		if found then
			local info = SECTION_INFO[section]
			lines[#lines + 1] = "## " .. info.title
			lines[#lines + 1] = ""
			lines[#lines + 1] = info.description
			lines[#lines + 1] = ""
			for i = 1, #results do
				local result = results[i]
				if result.section == section then
					append(lines, result_lines(result))
					lines[#lines + 1] = ""
				end
			end
		end
	end

	return lines
end

local function open_report(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true
	vim.bo[buf].filetype = "markdown"
	pcall(vim.api.nvim_buf_set_name, buf, "ChromaFlowBenchmark://full")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.cmd("new")
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	return buf
end

local function runtime_context(root, seed, default_name, active_name, active_files, fallback_files, sorted_actions, runtime_names)
	local version = vim.version()
	local jit_name = jit and ((jit.version or "LuaJIT") .. " " .. tostring(jit.arch or "?") .. "/" .. tostring(jit.os or "?")) or "off"
	local cpus = vim.uv.available_parallelism and vim.uv.available_parallelism() or "?"
	return {
		root = root,
		default_name = default_name,
		active_name = active_name,
		modules = #seed.modules,
		actions = #sorted_actions,
		active_files = #active_files,
		fallback_files = #fallback_files,
		runtime_modules = #runtime_names,
		style_cache = hl._style_cache_size(),
		picker = config.picker,
		debug = config.diagnostic.debug,
		watch = config.watch,
		watcher_running = watcher.is_running(),
		lsp = config.autoreload.lsp,
		treesitter = config.autoreload.treesitter,
		lineblend_autostart = config.lineblend.autostart,
		lineblend_active = lineblend.is_active(),
		alpha = config.alpha,
		nvim = string.format("%d.%d.%d", version.major, version.minor, version.patch),
		platform = (jit and tostring(jit.os or "?") .. "/" .. tostring(jit.arch or "?")) or "Lua",
		jit = jit_name,
		cpus = cpus,
	}
end

function M.run(opts)
	opts = opts or {}
	runtime_state = require("cf.fn.runtime")
	local root = opts.theme_path or config.theme_path
	assert(type(root) == "string" and root ~= "", "full_benchmark: theme_path is not configured")
	root = vim.fs.normalize(root)
	local root_stat = vim.uv.fs_stat(root)
	assert(root_stat and root_stat.type == "directory", "full_benchmark: theme root is not a directory: " .. root)

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

	local probe = {
		resolver_style = hl._build_style({ fg = "#123456" }, nil, nil),
		resolver_modifiers = { "readonly", "static" },
		target_vim = { vim = true },
		target_ts = { ts = true },
		target_lsp = { lsp = true },
		color_a = color.from_hex("#336699"),
		color_b = color.from_hex("#d07030"),
		color_bg = color.from_hex("#101820"),
		hex_inputs = { "#336699", "#34679a" },
		hex_index = 1,
	}
	probe.color_state = probe.color_a
	pipeline.set_background(probe.color_bg)
	probe.pipeline_one = { pipeline.shiftHue.fg(45) }
	probe.pipeline_seven = {
		pipeline.mix.fg(25, probe.color_b),
		pipeline.opacity.fg(85),
		pipeline.brightness.bg(12),
		pipeline.lighten.sp(8),
		pipeline.darken.fg(6),
		pipeline.shiftHue.bg(-35),
		pipeline.gamma.fg(1.10),
	}

	local context = runtime_context(root, seed, default_name, active_name, active_files, fallback_files, sorted_actions, runtime_names)
	active_results = {}
	seen_progress_sections = {}

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


		bench(opts, "04 resolver | cold type after clear", function()
			resolver.clear_cache()
			probe.sink = resolver.resolve("function", nil, probe.resolver_style)
		end)
		bench(opts, "04 resolver | type only", function()
			probe.sink = resolver.resolve("function", nil, probe.resolver_style)
		end)
		bench(opts, "04 resolver | modifier only", function()
			probe.sink = resolver.resolve(nil, "readonly", probe.resolver_style)
		end)
		bench(opts, "04 resolver | type + modifier", function()
			probe.sink = resolver.resolve("variable", "readonly", probe.resolver_style)
		end)
		bench(opts, "04 resolver | type + 2 modifiers", function()
			probe.sink = resolver.resolve("variable", probe.resolver_modifiers, probe.resolver_style)
		end)
		bench(opts, "04 resolver | type + filetype", function()
			probe.sink = resolver.resolve("function", nil, probe.resolver_style, "lua")
		end)
		bench(opts, "04 resolver | explicit TypeMod", function()
			probe.sink = resolver.resolve("variable", "readonly", probe.resolver_style, nil, nil, nil, true)
		end)
		bench(opts, "04 resolver | literal", function()
			probe.sink = resolver.resolve("CFBenchmarkLiteral", nil, probe.resolver_style)
		end)
		bench(opts, "04 resolver | target=vim", function()
			probe.sink = resolver.resolve("function", nil, probe.resolver_style, nil, probe.target_vim)
		end)
		bench(opts, "04 resolver | target=ts", function()
			probe.sink = resolver.resolve("function", nil, probe.resolver_style, nil, probe.target_ts)
		end)
		bench(opts, "04 resolver | target=lsp", function()
			probe.sink = resolver.resolve("function", nil, probe.resolver_style, nil, probe.target_lsp)
		end)

		bench(opts, "05 color | dynamic input baseline", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = probe.color_state
		end)
		bench(opts, "05 color | string input baseline", function()
			probe.hex_index = 3 - probe.hex_index
			probe.sink = probe.hex_inputs[probe.hex_index]
		end)
		bench(opts, "05 color | from_hex(dynamic)", function()
			probe.hex_index = 3 - probe.hex_index
			probe.sink = color.from_hex(probe.hex_inputs[probe.hex_index])
		end)
		bench(opts, "05 color | to_rgb_hex(dynamic packed)", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = color.to_rgb_hex(probe.color_state)
		end)
		bench(opts, "05 color | to_cterm(dynamic packed)", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = color.to_cterm(probe.color_state)
		end)
		bench(opts, "05 color | from_cterm(67/188)", function()
			probe.cterm = probe.cterm == 67 and 188 or 67
			probe.sink = color.from_cterm(probe.cterm)
		end, { setup = function() probe.cterm = 67 end })
		bench(opts, "05 color | mix(35)", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = color.mix(35, probe.color_b, probe.color_state)
		end)
		bench(opts, "05 color | opacity(85)", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink, probe.sink2 = color.opacity(probe.color_state, 85, probe.color_bg)
		end)
		bench(opts, "05 color | brightness(+20)", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = color.brightness(probe.color_state, 20)
		end)
		bench(opts, "05 color | lighten(20)", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = color.lighten(probe.color_state, 20)
		end)
		bench(opts, "05 color | darken(20)", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = color.darken(probe.color_state, 20)
		end)
		bench(opts, "05 color | shiftHue(45)", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = color.shiftHue(probe.color_state, 45)
		end)
		bench(opts, "05 color | gamma(1.10)", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = color.gamma(probe.color_state, 1.10)
		end)
		bench(opts, "05 pipeline | construct shiftHue.fg(45)", function()
			probe.sink = pipeline.shiftHue.fg(45)
		end)
		bench(opts, "05 pipeline | apply nil", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = pipeline.apply(probe.color_state, probe.color_bg, probe.color_b, nil, probe.color_a, probe.color_bg)
		end)
		bench(opts, "05 pipeline | apply 1 op", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = pipeline.apply(probe.color_state, probe.color_bg, probe.color_b, probe.pipeline_one, probe.color_a, probe.color_bg)
		end)
		bench(opts, "05 pipeline | apply 7 ops", function()
			probe.color_state = bxor(probe.color_state, 0x00010101)
			probe.sink = pipeline.apply(probe.color_state, probe.color_bg, probe.color_b, probe.pipeline_seven, probe.color_a, probe.color_bg)
		end)

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

	local results = active_results or {}
	active_results = nil
	seen_progress_sections = nil

	if not ok then
		error(err, 0)
	end

	local lines = build_report(results, context)
	local buffer
	if opts.open_report ~= false then
		buffer = open_report(lines)
	end
	vim.api.nvim_echo({ { string.format("ChromaFlow benchmark complete: %d probes", #results), "MoreMsg" } }, false, {})
	return {
		results = results,
		context = context,
		lines = lines,
		buffer = buffer,
	}
end

local function config_snapshot()
	return {
		alpha = config.alpha,
		theme_path = config.theme_path,
		watch = config.watch,
		picker = config.picker,
		autoreload = {
			lsp = config.autoreload.lsp,
			treesitter = config.autoreload.treesitter,
		},
		diagnostic = {
			debug = config.diagnostic.debug,
			severity_bias = config.diagnostic.severity_bias,
			severity = {
				hint = config.diagnostic.severity.hint,
				warn = config.diagnostic.severity.warn,
				error = config.diagnostic.severity.error,
			},
			messages = {
				info = config.diagnostic.messages.info,
				ok = config.diagnostic.messages.ok,
			},
		},
		lineblend = {
			autostart = config.lineblend.autostart,
			blend = config.lineblend.blend,
		},
	}
end

local function benchmark_setup(root)
	return {
		alpha = false,
		theme_path = root,
		watch = true,
		picker = false,
		autoreload = {
			lsp = false,
			treesitter = false,
		},
		diagnostic = {
			debug = false,
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
end

local function restore_config(previous)
	-- setup() intentionally treats nil as "leave unchanged". Put theme_path back to
	-- nil explicitly when the caller had never configured one, then let cf.setup()
	-- restore all service state (picker/debug/watcher/LineBlend) through normal paths.
	if previous.theme_path == nil then
		config.theme_path = nil
	end
	cf.setup(previous)
end

function M.start(theme_path)
	assert(vim.v.vim_did_enter ~= 0, "full_benchmark.start(): run after VimEnter")
	local root = theme_path == nil and DEFAULT_THEME_ROOT or theme_path
	assert(type(root) == "string" and root ~= "", "full_benchmark.start(): theme_path must be a non-empty string or nil")
	root = vim.fs.normalize(root)
	local stat = vim.uv.fs_stat(root)
	assert(stat and stat.type == "directory", "full_benchmark.start(): theme root is not a directory: " .. root)

	local previous = config_snapshot()
	local ok, result = xpcall(function()
		-- Benchmark against ChromaFlow's real defaults, independent of the active
		-- session setup. The caller's setup is restored after the report is built.
		cf.setup(benchmark_setup(root))
		return M.run({ theme_path = root })
	end, debug.traceback)

	local restore_ok, restore_err = xpcall(function()
		restore_config(previous)
	end, debug.traceback)

	if not ok then
		if not restore_ok then
			error(result .. "\n\nAdditionally failed to restore ChromaFlow setup:\n" .. restore_err, 0)
		end
		error(result, 0)
	end
	if not restore_ok then
		error(restore_err, 0)
	end
	return result
end

M.default_theme_path = DEFAULT_THEME_ROOT

return M
