vim.opt.runtimepath:prepend(vim.fn.getcwd())

require("cf")
local hl = require("cf.hl.setup")
local diagnostic = require("cf.diagnostic")

assert(diagnostic.configure({ severity = { hint = true } }))
diagnostic.clear_pending()
hl._begin({ fg = "#aabbcc" }, { style_targets = { vim = true } })

local language = hl.language
local module = language.setup("lua", {
	mods = { CFResolverUnknownModA = { fg = "#aabbcc" } },
	language:group("CFResolverUnknownTypeA", { fg = "#aabbcc" }),
})
hl._apply_modules({ module })

local pending = diagnostic.pending()
assert(#pending == 2, "type and modifier must each produce a diagnostic")
local seen = {}
for _, item in ipairs(pending) do
	assert(item.severity == diagnostic.severity.HINT)
	assert(item.source.file:match("resolver_hint_apply_headless%.lua$"), "hint lost its declaration source")
	assert(item.code == "cf.hl.resolver.unresolved_literal")
	seen[item.message] = true
end
assert(seen["cf.hl.resolver: type: CFResolverUnknownTypeA used a literal fallback"])
assert(seen["cf.hl.resolver: typemod: CFResolverUnknownModA used a literal fallback"])

-- A list passed by an action produces one diagnostic for each missing entry.
diagnostic.clear_pending()
local action = {
	kind = "resolver_style",
	typemod = { "CFResolverUnknownModB", "CFResolverUnknownModC" },
	style = { fg = 0xaabbcc },
	targets = { vim = true },
	priority = 0,
	sequence = 1,
	_cf_diagnostic_source = module.actions[1]._cf_diagnostic_source,
}
assert(action._cf_diagnostic_source, "compiled action did not carry a diagnostic source")
hl._apply_modules({ { actions = { action } } })
pending = diagnostic.pending()
assert(#pending == 2, "list hints were collapsed in the action runner")
assert(pending[1].message:find("CFResolverUnknownModB", 1, true))
assert(pending[2].message:find("CFResolverUnknownModC", 1, true))

diagnostic.clear_pending()
local debug_module = language.setup("go", {
	mods = { CFResolverUnknownModD = { fg = "#aabbcc" } },
})
assert(debug_module.actions[1]._cf_diagnostic_source, "debug compilation lost the diagnostic source")
hl._apply_modules({ debug_module })
pending = diagnostic.pending()
assert(#pending == 1 and pending[1].message:find("CFResolverUnknownModD", 1, true))

diagnostic.clear_pending()
hl._apply_modules({ { actions = {
	{
		kind = "resolver_link", type_name = "CFResolverUnknownLinkSource",
		target_type = "CFResolverUnknownLinkTarget", priority = 0, sequence = 1,
		_cf_diagnostic_source = action._cf_diagnostic_source,
	},
	{
		kind = "resolver_clear", typemod = "CFResolverUnknownModE",
		priority = 0, sequence = 2,
		_cf_diagnostic_source = action._cf_diagnostic_source,
	},
} } })
pending = diagnostic.pending()
assert(#pending == 3, "link source, link target and clear must each produce a hint")
assert(pending[1].message:find("type: CFResolverUnknownLinkSource", 1, true))
assert(pending[2].message:find("type: CFResolverUnknownLinkTarget", 1, true))
assert(pending[3].message:find("typemod: CFResolverUnknownModE", 1, true))

assert(diagnostic.configure({ severity = { hint = false } }))
diagnostic.clear_pending()
hl._apply_modules({ { actions = { action } } })
assert(#diagnostic.pending() == 0, "disabled hints were reported")

assert(diagnostic.configure({ debug = true }))
hl._apply_modules({ { actions = { action } } })
pending = diagnostic.pending()
assert(#pending == 2, "debug mode must show both resolver hints despite the hint filter")
assert(pending[1].message:find("CFResolverUnknownModB", 1, true))
assert(pending[2].message:find("CFResolverUnknownModC", 1, true))

print("cf.nvim resolver apply diagnostics: OK")
