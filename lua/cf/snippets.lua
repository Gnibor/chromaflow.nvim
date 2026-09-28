local M = {}

local configured = false

local function is_cf_buffer()
	local name = vim.api.nvim_buf_get_name(0)
	return name ~= "" and name:sub(-3) == ".cf"
end

local function is_lua_buffer()
	return vim.bo.filetype == "lua" and not is_cf_buffer()
end

local function cf_opts()
	return {
		condition = is_cf_buffer,
		show_condition = is_cf_buffer,
	}
end

local function lua_opts()
	return {
		condition = is_lua_buffer,
		show_condition = is_lua_buffer,
	}
end

function M.setup(ls)
	if configured then
		return
	end

	assert(type(ls) == "table", "cf.snippets: LuaSnip instance is required")
	assert(type(ls.add_snippets) == "function", "cf.snippets: invalid LuaSnip instance")

	local s = ls.snippet
	local t = ls.text_node
	local i = ls.insert_node

	local function group(trigger, receiver, name)
		return s({
			trig = trigger,
			name = name,
			dscr = name,
		}, {
			t(receiver .. ':group("'),
			i(1, "group"),
			t({ '", {', "\t" }),
			i(0),
			t({ "", "})," }),
		}, cf_opts())
	end

	local function link(trigger, receiver, name)
		return s({
			trig = trigger,
			name = name,
			dscr = name,
		}, {
			t(receiver .. ':link("'),
			i(1, "source"),
			t('", "'),
			i(2, "target"),
			t('"),'),
			i(0),
		}, cf_opts())
	end

	ls.add_snippets("lua", {
		s({
			trig = "language",
			name = "ChromaFlow language module",
			dscr = "Create a ChromaFlow language theme module.",
		}, {
			t({
				'local hl = require("cf.hl.setup")',
				"local c = hl.colors",
				"local l = hl.language",
				"",
				'return l.setup("',
			}),
			i(1, "language"),
			t({ '", {', "\t" }),
			i(0),
			t({ "", "})" }),
		}, cf_opts()),

		s({
			trig = "plugin",
			name = "ChromaFlow plugin module",
			dscr = "Create a ChromaFlow plugin theme module.",
		}, {
			t({
				'local hl = require("cf.hl.setup")',
				"local c = hl.colors",
				"local p = hl.plugin",
				"",
				'return p.setup("',
			}),
			i(1, "plugin"),
			t({
				'", {',
				"\tstyle_targets = { vim = true, ts = false, lsp = false },",
				"\t",
			}),
			i(0),
			t({ "", "})" }),
		}, cf_opts()),

		s({
			trig = "ui",
			name = "ChromaFlow UI module",
			dscr = "Create a ChromaFlow UI theme module.",
		}, {
			t({
				'local hl = require("cf.hl.setup")',
				"local c = hl.colors",
				"local u = hl.ui",
				"",
				"return u.setup({",
				"\t",
			}),
			i(0),
			t({ "", "})" }),
		}, cf_opts()),

		s({
			trig = "runtime",
			name = "ChromaFlow runtime module",
			dscr = "Create a ChromaFlow runtime theme module.",
		}, {
			t({
				'local hl = require("cf.hl.setup")',
				"local c = hl.colors",
				"local r = hl.runtime",
				"",
				"return r.setup({",
				"\t",
			}),
			i(0),
			t({ "", "})" }),
		}, cf_opts()),

		group("lg", "l", "ChromaFlow language group"),
		link("ll", "l", "ChromaFlow language link"),
		group("pg", "p", "ChromaFlow plugin group"),
		link("pl", "p", "ChromaFlow plugin link"),
		group("ug", "u", "ChromaFlow UI group"),
		link("ul", "u", "ChromaFlow UI link"),
		group("rg", "r", "ChromaFlow runtime group"),
		group("rawg", "raw", "ChromaFlow raw group"),
		link("rawl", "raw", "ChromaFlow raw link"),

		s({
			trig = "cfruntime",
			name = "ChromaFlow runtime API",
			dscr = "Load a ChromaFlow runtime module from a normal Lua file.",
		}, {
			t({
				'local hl = require("cf.hl.setup")',
				'local r = hl.runtime("',
			}),
			i(1, "module"),
			t('")'),
			i(0),
		}, lua_opts()),
	}, { key = "cf.nvim" })

	configured = true
end

return M
