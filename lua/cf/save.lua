local M = {}

local api = vim.api
local uv = vim.uv
local color = require("cf.color")

local function source_same(a, b)
	return a ~= nil and b ~= nil
		and a.file == b.file
		and a.line == b.line
		and a.col == b.col
end

local function read_file(path)
	local fd, err = io.open(path, "rb")
	assert(fd, "cf.save: cannot read " .. tostring(path) .. ": " .. tostring(err))
	local data = fd:read("*a")
	fd:close()
	return data
end

local function write_file(path, data)
	local fd, err = io.open(path, "wb")
	assert(fd, "cf.save: cannot write " .. tostring(path) .. ": " .. tostring(err))
	local ok, write_err = fd:write(data)
	local close_ok, close_err = fd:close()
	assert(ok, "cf.save: cannot write " .. tostring(path) .. ": " .. tostring(write_err))
	assert(close_ok, "cf.save: cannot close " .. tostring(path) .. ": " .. tostring(close_err))
end

local function line_starts(source)
	local starts = { 1 }
	local pos = 1
	while true do
		local nl = source:find("\n", pos, true)
		if not nl then break end
		starts[#starts + 1] = nl + 1
		pos = nl + 1
	end
	return starts
end

local function byte_at(starts, row, col)
	local start = starts[row + 1]
	assert(start ~= nil, "cf.save: Tree-sitter row outside source")
	return start + col
end

local function node_bytes(node, starts)
	local sr, sc, er, ec = node:range()
	return byte_at(starts, sr, sc), byte_at(starts, er, ec)
end

local function node_text(node, source)
	return vim.treesitter.get_node_text(node, source)
end

-- Picker pipeline operations already carry their exact function-call ranges from
-- the compile/colortrace source pass. Keep those ranges authoritative instead of
-- finding the same call a second time during save. Source ranges are 1-based and
-- their end position is exclusive, matching Tree-sitter after the +1 conversion.
local function traced_bytes(range, starts)
	assert(range and range.line and range.col and range.end_line and range.end_col,
		"cf.save: pipeline operation has no complete source range; reload first")
	local first_line = assert(starts[range.line], "cf.save: pipeline start line outside source")
	local end_line = assert(starts[range.end_line], "cf.save: pipeline end line outside source")
	return first_line + range.col - 1, end_line + range.end_col - 1
end

local function traced_text(range, source, starts)
	local first, last = traced_bytes(range, starts)
	return source:sub(first, last - 1)
end

local function parse(source, path)
	local ok_parser, parser = pcall(vim.treesitter.get_string_parser, source, "lua")
	assert(ok_parser and parser, "cf.save: Lua parser unavailable for " .. tostring(path))
	local ok_trees, trees = pcall(parser.parse, parser)
	assert(ok_trees and type(trees) == "table" and trees[1], "cf.save: failed to parse " .. tostring(path))
	return trees[1]:root()
end

local function find_call_at(root, line, col)
	local wanted_row = line - 1
	local wanted_col = col - 1
	local found
	local function visit(node)
		if found then return end
		if node:type() == "function_call" then
			local row, column = node:range()
			if row == wanted_row and column == wanted_col then
				found = node
				return
			end
		end
		for child in node:iter_children() do
			visit(child)
			if found then return end
		end
	end
	visit(root)
	return found
end

local function named_children(node)
	local out = {}
	for i = 0, node:named_child_count() - 1 do
		out[#out + 1] = node:named_child(i)
	end
	return out
end

local function call_name(call, source)
	local callee = call:named_child(0)
	if not callee then return nil end
	local count = callee:named_child_count()
	if count > 0 then
		return node_text(callee:named_child(count - 1), source)
	end
	return node_text(callee, source)
end

local function call_arguments(call)
	for child in call:iter_children() do
		if child:type() == "arguments" then return child end
	end
	return nil
end

local function call_table(call)
	local args = call_arguments(call)
	if not args then return nil end
	local result
	for i = 0, args:named_child_count() - 1 do
		local child = args:named_child(i)
		if child:type() == "table_constructor" then result = child end
	end
	return result
end

local function decode_string_literal(text)
	local chunk = load("return " .. text, "cf.save-key", "t", {})
	if not chunk then return nil end
	local ok, value = pcall(chunk)
	if ok and type(value) == "string" then return value end
	return nil
end

local function field_parts(field, source)
	local children = named_children(field)
	if #children < 2 then return nil, nil end
	local key_node = children[1]
	local value_node = children[#children]
	local kind = key_node:type()
	local key
	if kind == "identifier" then
		key = node_text(key_node, source)
	elseif kind == "string" then
		key = decode_string_literal(node_text(key_node, source))
	end
	return key, value_node
end

local function table_fields(tbl, source)
	local fields = {}
	local order = {}
	for child in tbl:iter_children() do
		if child:type() == "field" then
			local key, value = field_parts(child, source)
			if key ~= nil then
				fields[key] = { node = child, value = value }
				order[#order + 1] = key
			end
		end
	end
	return fields, order
end

local function call_first_string(call, source)
	local args = call_arguments(call)
	if not args then return nil end
	for i = 0, args:named_child_count() - 1 do
		local child = args:named_child(i)
		if child:type() == "string" then
			return decode_string_literal(node_text(child, source))
		end
		if child:type() ~= "comment" then break end
	end
	return nil
end

local lua_keywords = {}
for word in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%S+") do
	lua_keywords[word] = true
end

local function call_first_string_node(call)
	local args = call_arguments(call)
	if not args then return nil end
	for i = 0, args:named_child_count() - 1 do
		local child = args:named_child(i)
		if child:type() == "string" then return child end
		if child:type() ~= "comment" then break end
	end
end

local function lua_literal(value)
	local kind = type(value)
	if kind == "nil" then return "nil" end
	if kind == "boolean" or kind == "number" then return tostring(value) end
	if kind == "string" then return string.format("%q", value) end
	assert(kind == "table", "cf.save: unsupported inherited style value " .. kind)
	local parts = {}
	local seen = {}
	for i = 1, #value do
		parts[#parts + 1] = lua_literal(value[i])
		seen[i] = true
	end
	local keys = {}
	for key in pairs(value) do if not seen[key] then keys[#keys + 1] = key end end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for i = 1, #keys do
		local key = keys[i]
		local rendered_key = type(key) == "string" and key:match("^[%a_][%w_]*$") and not lua_keywords[key]
			and key or ("[" .. lua_literal(key) .. "]")
		parts[#parts + 1] = rendered_key .. " = " .. lua_literal(value[key])
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function apply_text_edits(source, edits)
	table.sort(edits, function(a, b)
		if a.first ~= b.first then return a.first > b.first end
		return a.last > b.last
	end)
	for i = 1, #edits do
		local edit = edits[i]
		-- Adjacent field removals may both include the same comma. Their
		-- offsets refer to the original source: delete the union only once.
		local previous = edits[i - 1]
		local last = edit.last
		if previous and edit.text == "" and previous.text == "" then
			last = math.min(last, previous.first)
		end
		if last >= edit.first then
			source = source:sub(1, edit.first - 1) .. edit.text .. source:sub(last)
		end
	end
	return source
end

local function line_bounds(source, starts, row)
	local first = starts[row + 1]
	local next_first = starts[row + 2]
	local last = next_first and (next_first - 1) or (#source + 1)
	return first, last
end

local function removal_edit(field, source, starts)
	local first, last = node_bytes(field, starts)
	local sr, sc, er, ec = field:range()
	local next_node = field:next_sibling()
	local prev_node = field:prev_sibling()

	if next_node and next_node:type() == "," then
		local _, comma_last = node_bytes(next_node, starts)
		last = comma_last
	elseif prev_node and prev_node:type() == "," then
		local comma_first = node_bytes(prev_node, starts)
		first = comma_first
	end

	-- A standalone field line can disappear completely. This keeps multiline
	-- theme files tidy while comments/inline fields fall back to the exact AST
	-- removal above and are therefore never swallowed accidentally.
	if sr == er then
		local line_first, line_last = line_bounds(source, starts, sr)
		local before = source:sub(line_first, first - 1)
		local after = source:sub(last, line_last - 1):gsub("\r?\n$", "")
		if before:match("^%s*$") and after:match("^%s*$") then
			return { first = line_first, last = line_last, text = "" }
		end
	end

	return { first = first, last = last, text = "" }
end

local function table_insert_edit(tbl, fields, additions, source, starts)
	if #additions == 0 then return nil end
	local sr, _, er, ec = tbl:range()
	local _, close_pos = node_bytes(tbl, starts)
	-- node end is immediately after `}`.
	close_pos = close_pos - 1

	if sr ~= er and source:sub(starts[er + 1], close_pos - 1):match("^%s*$") then
		local close_line_first = starts[er + 1]
		local close_indent = source:sub(close_line_first, close_pos - 1)
		local child_indent
		for _, field in pairs(fields) do
			local fr, fc = field.node:range()
			if fr ~= nil then
				child_indent = source:sub(starts[fr + 1], starts[fr + 1] + fc - 1):match("^%s*")
				break
			end
		end
		if child_indent == nil then child_indent = close_indent .. "\t" end
		local text = {}
		for i = 1, #additions do
			local add = additions[i]
			text[#text + 1] = child_indent .. add.name .. " = " .. tostring(add.value) .. ",\n"
		end
		local last_token
		for child in tbl:iter_children() do
			if child:type() ~= "comment" and child:type() ~= "}" then last_token = child end
		end
		local separator
		if last_token and last_token:type() == "field" then
			local _, pos = node_bytes(last_token, starts)
			separator = { first = pos, last = pos, text = "," }
		end
		return { first = close_line_first, last = close_line_first, text = table.concat(text) }, separator
	end

	local before_close = source:sub(1, close_pos - 1)
	local tail = before_close:match("([^%s])%s*$")
	local prefix = " "
	if tail and tail ~= "{" and tail ~= "," then prefix = ", " end
	local parts = {}
	for i = 1, #additions do
		local add = additions[i]
		parts[i] = add.name .. " = " .. tostring(add.value)
	end
	local suffix = source:sub(close_pos - 1, close_pos - 1):match("%s") and "" or " "
	return { first = close_pos, last = close_pos, text = prefix .. table.concat(parts, ", ") .. suffix }
end

local function field_key(name)
	-- Highlight/modifier names are data, not Lua identifiers (e.g. defaultLibrary
	-- or a custom name containing dots). Bracket spelling is always unambiguous.
	return "[" .. string.format("%q", name) .. "]"
end

local function rewrite_bool_table(source, tbl, desired)
	local starts = line_starts(source)
	local fields = table_fields(tbl, source)
	local edits = {}
	local additions = {}

	for i = 1, #desired do
		local change = desired[i]
		local field = fields[change.name]
		if change.set then
			if field then
				local first, last = node_bytes(field.value, starts)
				edits[#edits + 1] = { first = first, last = last, text = tostring(change.value) }
			else
				local name = change.name
				if lua_keywords[name] or not name:match("^[%a_][%w_]*$") then name = field_key(name) end
				additions[#additions + 1] = { name = name, value = change.value }
			end
		elseif field then
			edits[#edits + 1] = removal_edit(field.node, source, starts)
		end
	end

	local updated = apply_text_edits(source, edits)
	if #additions == 0 then return updated end
	-- Re-find the table after removals/replacements before adding fields. This
	-- avoids overlapping edits and handles a last field without a trailing comma.
	local row, col = tbl:range()
	local root = parse(updated, "picker style insertion")
	local function find(node)
		local r, c = node:range()
		if node:type() == "table_constructor" and r == row and c == col then return node end
		for child in node:iter_children() do
			local found = find(child)
			if found then return found end
		end
	end
	local fresh = assert(find(root), "cf.save: edited table moved unexpectedly")
	local insertion, separator = table_insert_edit(fresh, table_fields(fresh, updated), additions, updated, line_starts(updated))
	local inserts = { insertion }
	if separator then inserts[#inserts + 1] = separator end
	return apply_text_edits(updated, inserts)
end

local function style_fields()
	return require("cf.picker")._style_fields()
end

local function style_changes(base, current)
	local out = {}
	local flags = style_fields()
	for i = 1, #flags do
		local name = flags[i]
		local before = base and base[name]
		local after = current and current[name]
		if before ~= after then
			out[#out + 1] = {
				name = name,
				set = after ~= nil,
				value = after,
			}
		end
	end
	return out
end

local function inherited_style(edit)
	local current = require("cf.theme").current()
	local modules = current and current.modules
	if type(modules) ~= "table" then return {} end
	for i = 1, #modules do
		local actions = modules[i].actions
		if type(actions) == "table" then
			for j = 1, #actions do
				local action = actions[j]
				if source_same(action._cf_source, edit.source) then
					if edit.action.kind:sub(1, 9) == "resolver_" then
						if action.kind == "resolver_style" and action.typemod == nil and type(action.style) == "table" then
							return action.style
						end
					elseif edit.action.kind == "raw_style" then
						if action.kind == "raw_style" and action.name ~= edit.action.name and type(action.style) == "table" then
							return action.style
						end
					end
				end
			end
		end
	end
	return {}
end

local function direct_typemod_changes(edit, current)
	local inherited = inherited_style(edit)
	local out = {}
	local flags = style_fields()
	for i = 1, #flags do
		local name = flags[i]
		local desired = current and current[name]
		local parent = inherited and inherited[name]

		if desired == parent then
			-- Returning to the parent value is representable by removing a direct
			-- TypeMod override.
			out[#out + 1] = { name = name, set = false }
		elseif desired ~= nil then
			-- A concrete boolean or numeric value has a direct representation.
			out[#out + 1] = { name = name, set = true, value = desired }
		else
			-- The live runtime can remove a field from the complete TypeMod style,
			-- but a TypeMod source table starts from the finished parent Type style.
			-- If the parent supplies this flag, source `unset` would inherit it again
			-- and therefore mean something different. Leave that one source field
			-- untouched; other independently representable edits still save.
		end
	end
	return out
end

local function field_value_table(field, source)
	if not field then return nil end
	local _, value = field_parts(field.node, source)
	if value and value:type() == "table_constructor" then return value end
	return nil
end

local function replace_node(source, node, text)
	local starts = line_starts(source)
	local first, last = node_bytes(node, starts)
	return apply_text_edits(source, { { first = first, last = last, text = text } })
end

local function rendered_override_table(changes)
	local parts = {}
	for i = 1, #changes do
		if changes[i].set then
			parts[#parts + 1] = changes[i].name .. " = " .. tostring(changes[i].value)
		end
	end
	if #parts == 0 then return nil end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Cold source rewrite only: never execute theme text to discover/edit Mods.
local function rewrite_qualifier(source, spec, container, name, set, value)
	local fields = table_fields(spec, source)
	local parent = field_value_table(fields[container], source)
	if parent then
		return rewrite_bool_table(source, parent, { { name = name, set = set, value = value } })
	end
	assert(fields[container] == nil, "cf.save: " .. container .. " must be a literal table to edit")
	if not set then return source end
	return rewrite_bool_table(source, spec, {
		{ name = container, set = true, value = "{ " .. field_key(name) .. " = " .. tostring(value) .. " }" },
	})
end

local function rewrite_typemod_value(source, value_node, desired, edit)
	if value_node:type() == "true" then
		local rendered = rendered_override_table(desired)
		if rendered == nil then return source end
		return replace_node(source, value_node, rendered)
	end
	assert(value_node:type() == "table_constructor", "cf.save: editable TypeMod style is not a style table")

	local existing = table_fields(value_node, source)
	local remaining = 0
	local has_effect = false
	local desired_by_name = {}
	for i = 1, #desired do desired_by_name[desired[i].name] = desired[i] end
	for key in pairs(existing) do
		local change = desired_by_name[key]
		if not change or change.set then
			remaining = remaining + 1
			if key ~= "priority" then has_effect = true end
		end
	end
	for i = 1, #desired do
		local change = desired[i]
		if change.set and existing[change.name] == nil then
			remaining = remaining + 1
			has_effect = true
		end
	end

	if remaining == 0 then
		return replace_node(source, value_node, "true")
	end
	assert(
		has_effect,
		"cf.save: cannot preserve a TypeMod table containing only priority after removing its direct style; the DSL has no inherited-style-with-custom-priority form"
	)
	return rewrite_bool_table(source, value_node, desired)
end

-- Source-side pipeline descriptors contain expressions/positions, never a
-- second live style. Read Lua syntax, do not execute palette/theme expressions.
local function pipeline_table(source, edit)
	local call = assert(find_call_at(parse(source, edit.source.file), edit.source.line, edit.source.col),
		"cf.save: pipeline source moved; reload first")
	local spec = assert(call_table(call), "cf.save: pipeline source has no literal table")
	local container = edit.kind == "Mod" and "mods" or (edit.kind == "TypeMod" and "typemods" or nil)
	if not container then return spec, nil, spec end
	local fields = table_fields(spec, source)
	local qualifiers = field_value_table(fields[container], source)
	assert(not fields[container] or qualifiers, "cf.save: qualifier container must be a literal table")
	local qualified = qualifiers and table_fields(qualifiers, source)[edit.typemod]
	local value = qualified and qualified.value
	assert(not value or value:type() == "table_constructor" or value:type() == "true" or value:type() == "false",
		"cf.save: qualifier must be a literal table or boolean")
	return spec, container, value and value:type() == "table_constructor" and value or nil
end

function M._pipeline_source(edit, compiled_operations)
	local source = read_file(edit.source.file)
	local result = { fields = {}, steps = {}, comments = {}, signature = vim.fn.sha256(source) }
	-- A Type supplied only through another group's `types = { ... }` has no
	-- local pipeline source yet. Its effective parent result is the editor base;
	-- the parent pipeline must never be presented as the child's own pipeline.
	if edit.detach_type then return result end
	local _, _, spec = pipeline_table(source, edit)
	if not spec then
		assert(not compiled_operations or #compiled_operations == 0,
			"cf.save: compiled pipeline has no literal source table; reload first")
		return result
	end
	local fields = table_fields(spec, source)
	for _, name in ipairs({ "fg", "bg", "sp", "ctermfg", "ctermbg" }) do
		if fields[name] then result.fields[name] = node_text(fields[name].value, source) end
	end
	if not fields.pipeline then
		assert(not compiled_operations or #compiled_operations == 0,
			"cf.save: compiled pipeline disappeared from source; reload first")
		return result
	end
	local operations = assert(field_value_table(fields.pipeline, source), "cf.save: pipeline must be a literal table to edit")
	for node in operations:iter_children() do
		if node:type() == "comment" then result.comments[#result.comments + 1] = node_text(node, source) end
	end
	compiled_operations = compiled_operations or {}
	local starts = line_starts(source)
	for i = 1, #compiled_operations do
		local operation = compiled_operations[i]
		local range = type(operation) == "table" and operation._cf_source or nil
		assert(range and range.file == edit.source.file,
			"cf.save: pipeline operation lost its compile source; reload first")
		result.steps[i] = { text = traced_text(range, source, starts), source = range }
	end
	return result
end

local function operation_expression(step, original)
	if not step.original then
		return ('hl.%s.%s(%s%s)'):format(step.name, step.channel,
			tostring(step.value), step.color_expr and (", " .. step.color_expr) or "")
	end
	local original_step = assert(original.steps[step.original], "cf.save: pipeline operation disappeared")
	local text = assert(original_step.text, "cf.save: pipeline operation lost its traced source text")
	if step.value == nil and not step.color_expr then return text end
	local wrapped = "return " .. text
	local root = parse(wrapped, "pipeline operation")
	local call = assert(find_call_at(root, 1, 8), "cf.save: unsupported operation expression")
	local args = named_children(assert(call_arguments(call)))
	local expressions = {}
	for _, arg in ipairs(args) do if arg:type() ~= "comment" then expressions[#expressions + 1] = arg end end
	local changes, starts = {}, line_starts(wrapped)
	for index, replacement in pairs({ [1] = step.value and tostring(step.value), [2] = step.color_expr }) do
		local first, last = node_bytes(assert(expressions[index], "cf.save: operation argument missing"), starts)
		changes[#changes + 1] = { first = first, last = last, text = replacement }
	end
	return apply_text_edits(wrapped, changes):sub(8)
end

local DETACH_KEEP = {
	priority = true,
	typemods = true,
	style_targets = true,
	style_targets_clear = true,
}

local function detached_style_expression(name, value)
	if (name == "fg" or name == "bg" or name == "sp") and type(value) == "number" then
		return string.format("%q", color.to_hex(value))
	end
	return lua_literal(value)
end

local function table_layout_indent(source, tbl)
	local starts = line_starts(source)
	local _, _, er = tbl:range()
	local close_first = starts[er + 1]
	local close_indent = close_first and source:sub(close_first, (starts[er + 2] or (#source + 1)) - 1):match("^%s*") or ""
	local fields = table_fields(tbl, source)
	local field_indent
	for _, field in pairs(fields) do
		local fr, fc = field.node:range()
		local prefix = source:sub(starts[fr + 1], starts[fr + 1] + fc - 1)
		if prefix:match("^%s*$") then field_indent = prefix; break end
	end
	field_indent = field_indent or (close_indent .. "	")
	local unit = "	"
	if #field_indent > #close_indent and field_indent:sub(1, #close_indent) == close_indent then
		local suffix = field_indent:sub(#close_indent + 1)
		if suffix ~= "" then unit = suffix end
	end
	return field_indent, unit
end

local function detached_pipeline_expression(delta, source, spec)
	if not delta or not delta.steps or #delta.steps == 0 then return nil end
	local field_indent, unit = table_layout_indent(source, spec)
	local step_indent = field_indent .. unit
	local lines = {}
	for i = 1, #delta.steps do
		lines[i] = operation_expression(delta.steps[i], delta.original) .. ","
	end
	return "{\n" .. step_indent .. table.concat(lines, "\n" .. step_indent) .. "\n" .. field_indent .. "}"
end

local function replace_first_string(source, value)
	local root = parse(source, "detached group")
	local call = assert(find_call_at(root, 1, 1), "cf.save: detached group call disappeared")
	local node = assert(call_first_string_node(call), "cf.save: detached group has no name")
	return replace_node(source, node, string.format("%q", value))
end

local function detached_group_text(source, call, edit, state)
	local fragment = node_text(call, source)
	local root = parse(fragment, "detached group")
	local cloned_call = assert(find_call_at(root, 1, 1), "cf.save: cannot clone inherited group")
	local spec = assert(call_table(cloned_call), "cf.save: inherited group has no table specification")
	local existing = table_fields(spec, fragment)
	local desired = {}
	local order = {}
	local function set(name, enabled, value)
		if desired[name] == nil then order[#order + 1] = name end
		desired[name] = { name = name, set = enabled, value = value }
	end

	-- The clone keeps declaration metadata/TypeMods, but never the parent's
	-- semantic fan-out, external link or colour pipeline. The child starts from
	-- the parent's already-finished effective style.
	for name in pairs(existing) do
		if not DETACH_KEEP[name] then set(name, false) end
	end
	set("types", false)
	set("link", false)
	set("pipeline", false)

	local base = {}
	for name, value in pairs(edit.detach_type.base or state.base or {}) do base[name] = value end
	local current = state.current or base
	for _, name in ipairs(style_fields()) do base[name] = current[name] end
	for name, value in pairs(base) do
		set(name, true, detached_style_expression(name, value))
	end

	local delta = edit.pipeline_edit
	if delta then
		for name, expression in pairs(delta.fields or {}) do set(name, true, expression) end
		local expression = detached_pipeline_expression(delta, fragment, spec)
		set("pipeline", expression ~= nil, expression)
	end

	local changes = {}
	for i = 1, #order do changes[i] = desired[order[i]] end
	fragment = rewrite_bool_table(fragment, spec, changes)
	return replace_first_string(fragment, edit.detach_type.child)
end

local function remove_inherited_type_edit(source, call, child)
	local spec = assert(call_table(call), "cf.save: inherited group has no table specification")
	local fields = table_fields(spec, source)
	local types_field = assert(fields.types, "cf.save: inherited Type is no longer listed in types")
	local types = assert(field_value_table(types_field, source), "cf.save: types must be a literal table to detach a Type")
	local found
	local values = 0
	for node in types:iter_children() do
		if node:type() == "field" then
			local children = named_children(node)
			if #children == 1 then
				values = values + 1
				local value = children[1]
				if value:type() == "string" and decode_string_literal(node_text(value, source)) == child then found = node end
			end
		end
	end
	assert(found, "cf.save: inherited Type disappeared from parent types; reload first")
	local starts = line_starts(source)
	if values == 1 then return removal_edit(types_field.node, source, starts) end
	return removal_edit(found, source, starts)
end

local function insertion_after_declaration(source, call, text)
	local field = call
	while field and field:type() ~= "field" do field = field:parent() end
	assert(field, "cf.save: inherited group is not a module declaration")
	local starts = line_starts(source)
	local sr, sc, er = field:range()
	local indent = source:sub(starts[sr + 1], starts[sr + 1] + sc - 1)
	local _, last = node_bytes(field, starts)
	local comma = field:next_sibling()
	if comma and comma:type() == "," then
		local _, comma_last = node_bytes(comma, starts)
		last = comma_last
		local next_line = starts[er + 2]
		if next_line and source:sub(last, next_line - 1):match("^%s*$") then
			return { first = next_line, last = next_line, text = indent .. text .. ",\n" }
		end
		return { first = last, last = last, text = " " .. text .. "," }
	end
	return { first = last, last = last, text = ",\n" .. indent .. text }
end

local function rewrite_detached_type(source, edit, state)
	local src = edit.source
	local root = parse(source, src.file)
	local call = assert(find_call_at(root, src.line, src.col), "cf.save: inherited group moved; reload first")
	assert(call_name(call, source) == "group", "cf.save: inherited Type source is not group()")
	assert(call_first_string(call, source) == edit.detach_type.parent, "cf.save: inherited Type parent changed; reload first")

	local style_delta = style_changes(state.base, state.current)
	if not edit.pipeline_edit and #style_delta == 0 then return source, false end

	local child = detached_group_text(source, call, edit, state)
	local edits = {
		remove_inherited_type_edit(source, call, edit.detach_type.child),
		insertion_after_declaration(source, call, child),
	}
	return apply_text_edits(source, edits), true
end

local function rewrite_pipeline(source, edit)
	local root_spec, container, spec = pipeline_table(source, edit)
	local delta = edit.pipeline_edit
	local changes = {}
	for name, expression in pairs(delta.fields) do
		changes[#changes + 1] = { name = name, set = true, value = expression }
	end
	table.sort(changes, function(a, b) return a.name < b.name end)
	if delta.steps then
		local lines = {}
		for _, comment in ipairs(delta.original.comments) do lines[#lines + 1] = comment end
		for _, step in ipairs(delta.steps) do lines[#lines + 1] = operation_expression(step, delta.original) .. "," end
		local row, col = (spec or root_spec):range()
		local starts = line_starts(source)
		local indent = source:sub(starts[row + 1], starts[row + 1] + col - 1):match("^%s*") or ""
		local field_indent
		if spec then
			local fields = table_fields(spec, source)
			local pipeline_field = fields.pipeline
			if pipeline_field then
				local fr, fc = pipeline_field.node:range()
				local prefix = source:sub(starts[fr + 1], starts[fr + 1] + fc - 1)
				if prefix:match("^%s*$") then field_indent = prefix end
			end
			if field_indent == nil then
				for _, field in pairs(fields) do
					local fr, fc = field.node:range()
					local prefix = source:sub(starts[fr + 1], starts[fr + 1] + fc - 1)
					if prefix:match("^%s+$") then
						field_indent = prefix
						break
					end
				end
			end
		end
		field_indent = field_indent or (indent .. "\t")
		local unit = "\t"
		if #field_indent > #indent and field_indent:sub(1, #indent) == indent then
			local suffix = field_indent:sub(#indent + 1)
			if suffix ~= "" then unit = suffix end
		end
		local step_indent = field_indent .. unit
		local expression = "{\n" .. step_indent .. table.concat(lines, "\n" .. step_indent) .. "\n" .. field_indent .. "}"
		changes[#changes + 1] = { name = "pipeline", set = #delta.steps > 0 or #lines > 0, value = expression }
	end
	if #changes == 0 then return source, false end
	if spec then return rewrite_bool_table(source, spec, changes), true end
	return rewrite_qualifier(source, root_spec, container, edit.typemod, true, rendered_override_table(changes) or "{}"), true
end

local function rewrite_one(source, edit, state)
	if edit.detach_type then return rewrite_detached_type(source, edit, state) end
	if edit.pipeline_edit then return rewrite_pipeline(source, edit) end
	local src = edit.source
	assert(src and src.file and src.line and src.col, "cf.save: picker edit has no exact source")
	local root = parse(source, src.file)
	local call = find_call_at(root, src.line, src.col)
	assert(call, ("cf.save: source declaration moved in %s; reload before saving"):format(src.file))
	local name = call_name(call, source)
	local spec = call_table(call)
	assert(spec, "cf.save: source declaration has no table specification")
	local action = edit.action
	assert(action ~= nil, "cf.save: picker edit lost compiled action")
	if edit.rule then
		assert(name == "group", "cf.save: TypeMod rule source is not group()")
		return rewrite_qualifier(source, spec, "typemods", edit.typemod, edit.value ~= nil, edit.value), true
	end
	assert(action.kind == "resolver_style" or action.kind == "raw_style"
		or action.kind == "resolver_clear" or action.kind == "resolver_link",
		"cf.save: Style save requires a compiled action")

	local base = state.base or {}
	local current = state.current or {}
	local changes = style_changes(base, current)
	if #changes == 0 then return source, false end

	if action.typemod ~= nil and action.type_name == nil then
		assert(name == "setup", "cf.save: module Mod source is not setup()")
		local fields = table_fields(spec, source)
		local mods = field_value_table(fields.mods, source)
		local mod_fields = mods and table_fields(mods, source) or {}
		local field = mod_fields[action.typemod]
		local value = field_value_table(field, source)
		if not value then
			local rendered = rendered_override_table(changes)
			return rewrite_qualifier(source, spec, "mods", action.typemod, rendered ~= nil, rendered), true
		end
		changes[#changes + 1] = { name = "link", set = false }
		return rewrite_bool_table(source, value, changes), true
	end

	local group_name = call_first_string(call, source)
	local is_typemod = action.typemod ~= nil
	if action.kind == "raw_style" and group_name ~= action.name then
		is_typemod = true
	end

	if not is_typemod then
		assert(name == "group", "cf.save: base Style source is not group()")
		return rewrite_bool_table(source, spec, changes), true
	end

	assert(name == "group", "cf.save: TypeMod source is not group()")
	local typemod = action.typemod or action.name
	local fields = table_fields(spec, source)
	local typemods = field_value_table(fields.typemods, source)
	local typemod_fields = typemods and table_fields(typemods, source) or {}
	local field = typemod_fields[typemod]
	local direct = direct_typemod_changes(edit, current)
	if not field then
		local rendered = rendered_override_table(direct)
		return rewrite_qualifier(source, spec, "typemods", typemod, rendered ~= nil, rendered), true
	end
	local _, value = field_parts(field.node, source)
	assert(value, "cf.save: TypeMod source value is missing")
	if value:type() == "false" then
		return rewrite_qualifier(source, spec, "typemods", typemod, true, rendered_override_table(direct) or "true"), true
	end
	direct[#direct + 1] = { name = "link", set = false }
	return rewrite_typemod_value(source, value, direct, edit), true
end

local function sorted_edits()
	local picker = require("cf.picker")
	local edits = picker._style_edits()
	local out = {}
	local detached = {}
	local function add_detached(key, edit, pipeline_edit)
		local merged = detached[key]
		if not merged then
			merged = vim.tbl_extend("force", {}, edit)
			merged.pipeline_edit = nil
			detached[key] = merged
			out[#out + 1] = merged
		end
		if pipeline_edit then merged.pipeline_edit = pipeline_edit end
	end
	for key, edit in pairs(edits) do
		if edit.detach_type then add_detached(key, edit) else out[#out + 1] = edit end
	end
	for _, rule in pairs(picker._rule_edits and picker._rule_edits() or {}) do
		local copy = vim.tbl_extend("force", {}, rule, { rule = true })
		out[#out + 1] = copy
	end
	for key, edit in pairs(picker._pipeline_edits and picker._pipeline_edits() or {}) do
		if edit.detach_type then add_detached(key, edit, edit.pipeline_edit) else out[#out + 1] = edit end
	end
	table.sort(out, function(a, b)
		local as = a.source or {}
		local bs = b.source or {}
		if as.file ~= bs.file then return tostring(as.file) < tostring(bs.file) end
		if as.line ~= bs.line then return (as.line or 0) > (bs.line or 0) end
		if as.col ~= bs.col then return (as.col or 0) > (bs.col or 0) end
		if a.rule ~= b.rule then return a.rule == true end
		if (a.pipeline_edit ~= nil) ~= (b.pipeline_edit ~= nil) then return a.pipeline_edit == nil end
		return (a.typemod or a.name or "") < (b.typemod or b.name or "")
	end)
	return out
end

function M.plan()
	local runtime = require("cf.fn.runtime")
	local edits = sorted_edits()
	local files = {}
	local count = 0

	for i = 1, #edits do
		local edit = edits[i]
		local source = edit.source
		assert(source and source.file, "cf.save: picker edit has no source file")
		local file = files[source.file]
		if not file then
			local original = read_file(source.file)
			file = { path = source.file, original = original, content = original }
			files[source.file] = file
		end
		if edit.pipeline_edit then
			assert(vim.fn.sha256(file.original) == edit.pipeline_edit.original.signature,
				"cf.save: pipeline source changed on disk; reload before saving")
		end
		local state = not edit.rule and (edit.detach_type or not edit.pipeline_edit) and runtime._picker_style_state(edit.target) or nil
		local before = file.content
		local updated, changed = rewrite_one(before, edit, state)
		file.content = updated
		if changed and updated ~= before then count = count + 1 end
	end

	local writes = {}
	for _, file in pairs(files) do
		if file.content ~= file.original then
			-- Refuse to persist syntactically broken output before touching disk.
			local parsed = parse(file.content, file.path)
			assert(not parsed:has_error(), "cf.save: refusing invalid Lua output for " .. file.path)
			local chunk, err = loadstring(file.content, "@" .. file.path)
			assert(chunk, "cf.save: refusing invalid Lua output: " .. tostring(err))
			writes[#writes + 1] = file
		end
	end
	table.sort(writes, function(a, b) return a.path < b.path end)
	return { files = writes, count = count }
end

function M.write(plan)
	assert(type(plan) == "table" and type(plan.files) == "table", "cf.save.write: invalid plan")
	if #plan.files == 0 then return 0 end

	local staged = {}
	local pid = tostring(uv.os_getpid())
	for i = 1, #plan.files do
		local file = plan.files[i]
		local temp = file.path .. ".cfsave." .. pid .. ".tmp"
		pcall(uv.fs_unlink, temp)
		write_file(temp, file.content)
		local stat = uv.fs_stat(file.path)
		if stat and stat.mode then pcall(uv.fs_chmod, temp, stat.mode) end
		staged[#staged + 1] = { path = file.path, temp = temp }
	end

	for i = 1, #staged do
		local item = staged[i]
		local ok, err = uv.fs_rename(item.temp, item.path)
		if not ok then
			for j = i, #staged do pcall(uv.fs_unlink, staged[j].temp) end
			error("cf.save: cannot replace " .. item.path .. ": " .. tostring(err), 2)
		end
	end
	return #plan.files
end

function M.save()
	local plan = M.plan()
	M.write(plan)
	return plan.count, #plan.files
end

return M
