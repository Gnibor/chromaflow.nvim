vim.opt.runtimepath:prepend(vim.fn.getcwd())

local cf = require("cf")
local diagnostic = require("cf.diagnostic")
cf.setup({
	theme_path = vim.fs.joinpath(vim.fn.getcwd(), "examples", "themes"),
	watch = false,
	diagnostic = { severity = { hint = true } },
})

local hints = {}
for _, item in ipairs(diagnostic.history()) do
	if item.code == "cf.hl.resolver.unresolved_literal" then
		hints[#hints + 1] = item.message
	end
end

local expected_semantic = {
	"typemod: comment.documentation",
	"typemod: string.documentation",
	"typemod: constant.readonly",
	"typemod: variable.readonly",
	"typemod: variable.static",
	"typemod: function.static",
	"typemod: function.declaration",
	"typemod: type.builtin",
}
for _, semantic in ipairs(expected_semantic) do
	for _, message in ipairs(hints) do
		assert(not message:find(semantic, 1, true), "known Dark Theme TypeMod was hinted: " .. semantic)
	end
end

print("cf.nvim dark theme semantic TypeMod hints: OK")
