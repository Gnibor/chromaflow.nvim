-- Run with the bundled Neovim, -u NONE -i NONE -l, from cf.nvim.
vim.opt.runtimepath:prepend(vim.fn.getcwd())
require("cf")

local color = require("cf.color")
local config = require("cf.config")
local pipeline = require("cf.hl.pipeline")
local hl = require("cf.hl.setup")
local backend = require("cf.hl.runtime")

local function equal(actual, expected, message)
	assert(actual == expected, (message or "mismatch") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

equal(color.to_cterm(0xFF000000), 16, "black")
equal(color.to_cterm("#ffffff"), 231, "white")
equal(color.to_cterm("#ff0000"), 196, "red")
equal(color.to_cterm("#00ff00"), 46, "green")
equal(color.to_cterm("#0000ff"), 21, "blue")
equal(color.to_cterm("#808080"), 244, "gray")
equal(color.to_cterm("#ff000040"), 196, "alpha is discarded")
equal(color.to_cterm(0x00FF0000), 196)
equal(color.from_cterm(0), 0xFF000000)
equal(color.from_cterm(15), 0xFFFFFFFF)
for _, value in ipairs({ -1, 256, 1.5, "red", false, math.huge }) do
	assert(not pcall(color.from_cterm, value), "invalid index accepted")
end
assert(not pcall(color.from_cterm, 0 / 0))
assert(not pcall(color.to_cterm, {}))

-- Independent palette + exhaustive nearest-entry oracle for channel boundaries
-- and deterministic RGB samples. No platform-dependent ANSI slots in output.
local palette = {}
local levels = { 0, 95, 135, 175, 215, 255 }
for r = 0, 5 do
	for g = 0, 5 do
		for b = 0, 5 do palette[16 + 36 * r + 6 * g + b] = { levels[r + 1], levels[g + 1], levels[b + 1] } end
	end
end
for i = 0, 23 do palette[232 + i] = { 8 + i * 10, 8 + i * 10, 8 + i * 10 } end
local function distance(r, g, b, entry)
	return (r - entry[1]) ^ 2 + (g - entry[2]) ^ 2 + (b - entry[3]) ^ 2
end
local function check_nearest(r, g, b)
	local packed = 0xFF000000 + r * 65536 + g * 256 + b
	local index = color.to_cterm(packed)
	assert(index >= 16 and index <= 255)
	local actual = distance(r, g, b, palette[index])
	for i = 16, 255 do assert(actual <= distance(r, g, b, palette[i]), "not nearest palette entry") end
end
for i = 16, 255 do
	local p = palette[i]
	equal(color.from_cterm(i), 0xFF000000 + p[1] * 65536 + p[2] * 256 + p[3])
	equal(color.to_cterm(color.from_cterm(i)), i, "palette round trip")
end
for i = 0, 255 do
	check_nearest(i, i, i)
	check_nearest(i, (i * 73) % 256, (i * 151) % 256)
end
for _, r in ipairs({ 47, 48, 115, 116, 155, 156, 195, 196, 235, 236 }) do
	for _, g in ipairs({ 0, 95, 115, 128, 135, 215, 255 }) do check_nearest(r, g, 117) end
end

local fg, bg, sp = 0xFF90A0B0, 0xFF203040, 0xFFEE5577
hl._begin({ bg = bg }, {})
config.alpha = false
local cases = {
	{ "mix", 25, 0xFFFF0000 }, { "opacity", 50 }, { "brightness", -20 },
	{ "lighten", 10 }, { "darken", 10 }, { "shiftHue", 45 }, { "gamma", 1.4 },
}
for _, case in ipairs(cases) do
	local name, a, b = unpack(case)
	for _, channel in ipairs({ "fg", "bg" }) do
		local cchannel = "c" .. channel
		local field = "cterm" .. channel
		local rf, rb = pipeline.apply(fg, bg, sp, { pipeline[name][channel](a, b) })
		local expected = color.to_cterm(channel == "fg" and rf or rb)
		local spec = { fg = fg, bg = bg, sp = sp, pipeline = { hl[name][cchannel](a, b) } }
		local style = hl._build_style(spec)
		equal(style[field], expected, name .. "." .. cchannel)
		equal(style.fg, fg, "cfg changed fg")
		equal(style.bg, bg, "cbg changed bg")
		equal(style.sp, sp, "cterm changed sp")
		equal(spec[field], nil, "mutated declaration")
		local df, db, ds, trace, cfg, cbg = pipeline.debug_apply(fg, bg, sp, spec.pipeline[1])
		equal(df, fg); equal(db, bg); equal(ds, sp)
		equal(trace.channel, cchannel)
		equal(color.to_cterm(channel == "fg" and cfg or cbg), expected, "debug result")
		assert(pipeline[name].csp == nil)
	end
end

local original = hl._build_style({ fg = fg, bg = bg, ctermfg = 196, ctermbg = 21, pipeline = { hl.lighten.fg(10) } })
equal(original.ctermfg, 196); equal(original.ctermbg, 21)
equal(original.fg, color.lighten(fg, 10), "existing fg operation changed")
local explicit = hl._build_style({ fg = fg, ctermfg = 0, ctermbg = 21, pipeline = { hl.lighten.cfg(100) } })
equal(explicit.ctermfg, 231, "zero index must not fall back to fg")
equal(explicit.ctermbg, 21, "untouched terminal background changed")
equal(explicit.fg, fg)
local named_bg = hl._build_style({ fg = fg, ctermbg = "Red", pipeline = { hl.lighten.cfg(10) } })
equal(named_bg.ctermbg, "Red", "unrelated named cterm field was decoded")
local named_fg = hl._build_style({ bg = bg, ctermfg = "Blue", pipeline = { hl.darken.cbg(10) } })
equal(named_fg.ctermfg, "Blue", "unrelated named cterm field was decoded")
local only = hl._build_style({ ctermfg = 196, pipeline = { hl.darken.cfg(50) } })
equal(only.ctermfg, color.to_cterm(color.darken(color.from_cterm(196), 50)))
equal(only.fg, nil)
assert(not pcall(hl._build_style, { pipeline = { hl.darken.cfg(10) } }))
assert(not pcall(hl._build_style, { pipeline = { hl.darken.cbg(10) } }))

-- Multiple operations retain RGB precision until the final palette conversion.
local operations = { hl.brightness.cfg(7), hl.gamma.cfg(1.2), hl.mix.cfg(23, sp), hl.darken.cbg(8) }
local mixed = color.mix(23, sp, color.gamma(color.brightness(fg, 7), 1.2))
local chain = hl._build_style({ fg = fg, bg = bg, pipeline = operations })
equal(chain.ctermfg, color.to_cterm(mixed))
equal(chain.ctermbg, color.to_cterm(color.darken(bg, 8)))
equal(chain.fg, fg); equal(chain.bg, bg)
local interleaved = hl._build_style({ fg = fg, bg = bg, pipeline = {
	hl.lighten.fg(10), hl.darken.cfg(20), hl.darken.fg(30), hl.gamma.cfg(1.2),
} })
equal(interleaved.fg, color.darken(color.lighten(fg, 10), 30))
equal(interleaved.ctermfg, color.to_cterm(color.gamma(color.darken(color.lighten(fg, 10), 20), 1.2)))
local terminal_backdrop = hl._build_style({ fg = fg, bg = bg, pipeline = {
	hl.lighten.cbg(10), hl.opacity.cfg(40),
} })
equal(terminal_backdrop.ctermfg, color.to_cterm(color.opacity(fg, 40, color.lighten(bg, 10))))
local _, _, _, work_fg, work_bg = pipeline.apply(fg, bg, sp, operations)
equal(work_fg, mixed); equal(work_bg, color.darken(bg, 8))
local unchanged_fg, unchanged_bg, unchanged_sp, unchanged_cfg, unchanged_cbg = pipeline.apply(fg, bg, sp, nil, mixed, bg)
equal(unchanged_fg, fg); equal(unchanged_bg, bg); equal(unchanged_sp, sp)
equal(unchanged_cfg, mixed); equal(unchanged_cbg, bg)

-- cterm opacity always composites, even when GUI alpha output is enabled.
config.alpha = true
local opaque = color.opacity(color.from_cterm(196), 50, color.from_cterm(21))
local alpha = hl._build_style({ fg = fg, bg = bg, ctermfg = 196, ctermbg = 21, pipeline = { hl.opacity.cfg(50) } })
equal(alpha.ctermfg, color.to_cterm(opaque))
equal(alpha.fg, fg); equal(alpha.bg, bg)
local ctbg = hl._build_style({ bg = bg, ctermbg = 196, pipeline = { hl.opacity.cbg(50) } })
equal(ctbg.ctermbg, color.to_cterm(color.opacity(color.from_cterm(196), 50, bg)))
config.alpha = false

-- Complete styles still intern, resolve and materialize with numeric indices.
equal(chain, hl._build_style({ fg = fg, bg = bg, pipeline = operations }), "style interning")
local module = hl.ui.setup({ hl.raw:group("CFTermTest", { fg = fg, bg = bg, pipeline = operations,
	typemods = { CFTermMod = { pipeline = { hl.lighten.cfg(10) } } },
}) })
module:apply()
local base = vim.api.nvim_get_hl(0, { name = "CFTermTest", link = false })
equal(base.ctermfg, chain.ctermfg); equal(base.ctermbg, chain.ctermbg)
equal(base.fg, fg - 0xFF000000); equal(base.bg, bg - 0xFF000000)
local mod = vim.api.nvim_get_hl(0, { name = "CFTermMod", link = false })
equal(mod.ctermfg, color.to_cterm(color.lighten(color.from_cterm(chain.ctermfg), 10)))
equal(backend.group_style("CFTermTest"), chain)

-- Runtime preview/reset/reload and callback boundaries use the same style path.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/only/runtime", "p")
vim.fn.writefile({ "only", "only" }, root .. "/.cf-theme")
vim.fn.writefile({ "return { bg = '#203040', fg = '#90a0b0' }" }, root .. "/only/color.cf")
vim.fn.writefile({
	"local h = require('cf.hl.setup')",
	"return h.ui.setup({ h.ui:group('CFTermRuntime', { fg = h.colors.fg, bg = h.colors.bg, ctermfg = 196, ctermbg = 21 }) })",
}, root .. "/only/ui.cf")
vim.fn.writefile({
	"local h = require('cf.hl.setup'); local r = h.runtime",
	"function r.change(style) assert(style.ctermfg == 231); style.ctermfg = 46; return style end",
	"return r.setup({",
	" r:group('dim', { pipeline = { h.darken.cfg(20) } }),",
	" r:group('callback', { pipeline = { h.lighten.cfg(100), r:func('change'), h.darken.cfg(50) } }),",
	"})",
}, root .. "/only/runtime/cterm.cf")
local theme = require("cf.theme")
local r = hl.runtime("cterm")
local target = hl.ui.CFTermRuntime
theme.load(root)
local function current() return vim.api.nvim_get_hl(0, { name = "CFTermRuntime", link = false }) end
r.apply(target, r.groups.dim)
local dim = color.to_cterm(color.darken(color.from_cterm(196), 20))
equal(current().ctermfg, dim); equal(current().fg, fg - 0xFF000000)
r.apply(target, r.groups.dim)
equal(current().ctermfg, dim, "runtime drift")
theme.load(root)
equal(current().ctermfg, dim, "reload lost runtime diff")
r.reset(target)
equal(current().ctermfg, 196)
r.apply(target, r.groups.callback)
equal(current().ctermfg, color.to_cterm(color.darken(color.from_cterm(46), 50)), "callback mutation ignored")
r.reset(target)
equal(current().ctermfg, 196)

-- Debug tracing recognizes the additional builders without involving the picker.
local trace_path = root .. "/only/debug.cf"
vim.fn.writefile({
	"local h = require('cf.hl.setup')",
	"return h.ui.setup({ h.raw:group('CFTermDebug', {",
	" fg = h.colors.fg, bg = h.colors.bg,",
	" pipeline = {",
	"  h.lighten.cfg(10),",
	"  h.darken.cbg(5),",
	" },",
	"}) })",
}, trace_path)
local diagnostic = require("cf.diagnostic")
local colortrace = require("cf.colortrace")
diagnostic.configure({ debug = true })
colortrace.set_debug(true)
local buf = vim.fn.bufadd(trace_path)
vim.fn.bufload(buf)
vim.api.nvim_win_set_buf(0, buf)
local recorded = {}
local record = colortrace._record
colortrace._record = function(owner, source, trace, index, debug_)
	recorded[#recorded + 1] = { source = source, trace = trace }
	return record(owner, source, trace, index, debug_)
end
theme.load(root)
colortrace._record = record
equal(#recorded, 2, "debug wrapper count")
equal(recorded[1].trace.channel, "cfg")
equal(recorded[2].trace.channel, "cbg")
equal(recorded[1].source.line, 5, "cfg source location")
equal(recorded[2].source.line, 6, "cbg source location")
local traced = vim.api.nvim_get_hl(0, { name = "CFTermDebug", link = false })
equal(traced.ctermfg, color.to_cterm(color.lighten(fg, 10)))
equal(traced.ctermbg, color.to_cterm(color.darken(bg, 5)))
equal(traced.fg, fg - 0xFF000000); equal(traced.bg, bg - 0xFF000000)
colortrace.set_debug(false)
diagnostic.clear()
vim.fn.delete(root, "rf")
print("cf.nvim cterm tests: OK")
