local hl = require("cf.hl.setup")
local c = hl.colors
local l = hl.language
local raw = hl.raw

return l.setup("lua", {
	style_targets = {
		vim = true,
		ts = true,
		lsp = true,
	},

	mods = {
		deprecated = {
			sp = c.red,
			undercurl = true,
			priority = 20,
			pipeline = {
				hl.opacity.sp(75),
			},
		},
	},

	l:group("function", {
		fg = c["function"],
		bold = true,
		priority = 100,
		pipeline = {
			hl.shiftHue.fg(10),
		},
		types = {
			"method",
			"constructor",
		},
		typemods = {
			readonly = true,
			static = false,
			deprecated = {
				fg = c.black,
				sp = c.red,
				undercurl = true,
				priority = 120,
				pipeline = {
					hl.opacity.sp(75),
				},
			},
			documentation = {
				link = "comment",
			},
		},
	}),

	l:group("method", {
		link = "function",
	}),

	l:link("constructor", "function"),

	raw:group("@cf.literal.demo", {
		fg = c.fg,
		clear = true,
		types = {
			"CFDemoAlias",
		},
		pipeline = {
			hl.opacity.fg(90),
		},
		typemods = {
			["@cf.literal.demo.readonly"] = true,
			["@cf.literal.demo.linked"] = {
				link = "@cf.literal.demo",
			},
		},
	}),

	raw:link("CFDemoRawLink", "@cf.literal.demo"),
})
