local api = vim.api

local Float = {}
Float.__index = Float

local defaults = {
    width = 1,
    height = 1,
    relative = "editor",
    row = 0,
    col = 0,
    anchor = "NW",
    border = "none",
    title = "",
    title_pos = "left",
    focusable = true,
    zindex = 50,
}

local function integer(value, minimum)
    return type(value) == "number" and value >= minimum and value < math.huge and value % 1 == 0
end

local function check_row(row)
    assert(integer(row, 1), "row must be a positive integer (1-based)")
end

local function buffer_valid(self)
    return self._buf ~= nil and api.nvim_buf_is_valid(self._buf) and api.nvim_buf_is_loaded(self._buf)
end

local function window_valid(self)
    return self._win ~= nil and api.nvim_win_is_valid(self._win)
end

-- guicursor is global: at most one focused float owns its saved value.
local cursor_owner, saved_cursor

local function restore_cursor(self)
    if cursor_owner == self then
        local previous = saved_cursor
        cursor_owner, saved_cursor = nil, nil
        vim.o.guicursor = previous
    end
end

local function apply_cursor(self)
    if not self._cursor_hl or cursor_owner == self or api.nvim_get_current_win() ~= self._win then
        return
    end
    if cursor_owner then
        restore_cursor(cursor_owner)
    end
    local previous = vim.o.guicursor
    -- The final all-modes entry overrides only highlights, keeping the user's
    -- shapes and blink settings, including the language-mapping cursor style.
    vim.o.guicursor = (previous == "" and "" or previous .. ",") .. "a:" .. self._cursor_hl
    cursor_owner, saved_cursor = self, previous
end

local function cleanup_cursor(self)
    restore_cursor(self)
    if self._cursor_group then
        api.nvim_del_augroup_by_id(self._cursor_group)
        self._cursor_group = nil
    end
end

local function ensure_cursor(self)
    if not self._cursor_hl then
        return
    end
    if not self._cursor_group then
        local group = api.nvim_create_augroup("nvim_float_cursor_" .. self._ns, { clear = true })
        self._cursor_group = group
        api.nvim_create_autocmd({ "WinEnter", "WinLeave" }, {
            group = group,
            callback = function(event)
                if event.event == "WinEnter" then
                    apply_cursor(self)
                else
                    restore_cursor(self)
                end
            end,
        })
        api.nvim_create_autocmd("WinClosed", {
            group = group,
            pattern = tostring(self._win),
            callback = function()
                cleanup_cursor(self)
            end,
        })
    end
    -- nvim_open_win(..., true, ...) emits WinEnter before returning its ID.
    apply_cursor(self)
end

local function ensure_anchor_lines(self, count)
    local previous = self._anchors
    if previous == count then
        return
    end

    local added = {}
    for i = 1, count - previous do
        added[i] = ""
    end
    api.nvim_set_option_value("modifiable", true, { buf = self._buf })
    local ok, err = pcall(api.nvim_buf_set_lines, self._buf, math.min(previous, count), previous, true, added)
    api.nvim_set_option_value("modifiable", false, { buf = self._buf })
    if not ok then
        error(err, 0)
    end
    self._anchors = count
end

local function patch_line(self, row, line, cached)
    assert(type(line) == "table", "line must be an array of spans")
    if not cached then
        cached = { marks = {} }
        self._lines[row] = cached
    end
    -- Validation happens as each span is patched. If a later span fails,
    -- invalidate the reference so retrying the previous line cannot be skipped.
    cached.ref = nil
    self._last_row = math.max(self._last_row, row)
    local marks = cached.marks
    local opts = self._mark_opts
    local chunk = opts.virt_text[1]
    local count = #line
    for i = 1, count do
        local span = line[i]
        assert(type(span) == "table", "span must be a table")
        local col, text, hl = span.col, span.text, span.hl
        assert(integer(col, 0), "span.col must be a non-negative integer")
        assert(type(text) == "string" and not text:find("\n", 1, true),
            "span.text must be a string without newlines")
        assert(hl == nil or type(hl) == "string", "span.hl must be a string or nil")
        chunk[1], chunk[2] = text, hl
        opts.id = marks[i]
        opts.virt_text_win_col = col
        -- Empty buffer lines have no byte column > 0. Position visible text
        -- using screen cells, while keeping every mark anchored at byte 0.
        marks[i] = api.nvim_buf_set_extmark(self._buf, self._ns, row - 1, 0, opts)
    end
    for i = #marks, count + 1, -1 do
        api.nvim_buf_del_extmark(self._buf, self._ns, marks[i])
        marks[i] = nil
    end
    cached.ref = line
end

-- Returns true if cached lines were restored after losing the backing buffer.
local function ensure_buffer(self, count, skip_row, skip_end_row)
    if buffer_valid(self) then
        ensure_anchor_lines(self, count)
        return false
    end

    -- A valid but unloaded buffer has lost its extmarks as well.
    if self._buf ~= nil and api.nvim_buf_is_valid(self._buf) then
        api.nvim_buf_delete(self._buf, { force = true })
    end
    self._buf = api.nvim_create_buf(false, true)
    self._anchors = 1
    api.nvim_set_option_value("bufhidden", "hide", { buf = self._buf })
    api.nvim_set_option_value("swapfile", false, { buf = self._buf })
    api.nvim_set_option_value("undolevels", -1, { buf = self._buf })
    api.nvim_set_option_value("modifiable", false, { buf = self._buf })
    ensure_anchor_lines(self, count)

    for row, cached in pairs(self._lines) do
        cached.marks = {}
        if cached.ref and (not skip_row or row < skip_row or row > (skip_end_row or skip_row)) then
            patch_line(self, row, cached.ref, cached)
        end
    end
    return true
end

local function delete_line_marks(self, cached, valid)
    for i = #cached.marks, 1, -1 do
        if valid then
            api.nvim_buf_del_extmark(self._buf, self._ns, cached.marks[i])
        end
        cached.marks[i] = nil
    end
end

local function validate_config(config)
    assert(integer(config.width, 1), "width must be a positive integer")
    assert(integer(config.height, 1), "height must be a positive integer")
    assert(integer(config.zindex, 1), "zindex must be a positive integer")
    assert(config.relative == "editor" or config.relative == "cursor" or config.relative == "win",
        "relative must be editor, cursor or win")
    assert(config.anchor == "NW" or config.anchor == "NE" or config.anchor == "SW" or config.anchor == "SE",
        "anchor must be NW, NE, SW or SE")
    for _, key in ipairs({ "row", "col" }) do
        local value = config[key]
        assert(type(value) == "number" and value > -math.huge and value < math.huge,
            key .. " must be a finite number")
    end
    assert(type(config.border) == "string", "border must be a Neovim border style name")
    assert(type(config.title) == "string", "title must be a string")
    assert(config.title_pos == "left" or config.title_pos == "center" or config.title_pos == "right",
        "title_pos must be left, center or right")
    assert(type(config.focusable) == "boolean", "focusable must be a boolean")
    assert(config.win == nil or integer(config.win, 0), "win must be a window ID")
end

local function configure_window(self, opts)
    assert(type(opts) == "table", "opts must be a table")
    local enter = self._enter
    if opts.enter ~= nil then
        assert(type(opts.enter) == "boolean", "enter must be a boolean")
        enter = opts.enter
    end
    local cursor_hl = self._cursor_hl
    if opts.cursor_hl ~= nil then
        cursor_hl = opts.cursor_hl
        assert(cursor_hl == false or (type(cursor_hl) == "string" and cursor_hl:match("^[%w_@.]+$")),
            "cursor_hl must be a highlight group name or false")
        if cursor_hl then
            -- These prefixes are parsed as cursor shape/blink directives by
            -- guicursor rather than highlight names.
            local lower = cursor_hl:lower()
            for _, prefix in ipairs({ "block", "ver", "hor", "blinkwait", "blinkon", "blinkoff" }) do
                assert(lower:sub(1, #prefix) ~= prefix, "cursor_hl conflicts with a guicursor directive")
            end
        end
    end
    local config = {}
    for key, value in pairs(self._config) do
        config[key] = value
    end
    local changed = false
    for key, value in pairs(opts) do
        assert(defaults[key] ~= nil or key == "win" or key == "enter" or key == "cursor_hl",
            "unsupported float option: " .. tostring(key))
        if key ~= "enter" and key ~= "cursor_hl" and config[key] ~= value then
            changed = true
            config[key] = value
        end
    end
    validate_config(config)
    if changed then
        if window_valid(self) then
            api.nvim_win_set_config(self._win, config)
        end
        self._config = config
        if buffer_valid(self) then
            ensure_anchor_lines(self, math.max(config.height, self._last_row))
        end
    end
    self._enter = enter
    if cursor_hl ~= self._cursor_hl then
        cleanup_cursor(self)
        self._cursor_hl = cursor_hl
        if window_valid(self) then
            ensure_cursor(self)
        end
    end
end

local function ensure_window(self)
    if window_valid(self) then
        if api.nvim_win_get_buf(self._win) ~= self._buf then
            api.nvim_win_set_buf(self._win, self._buf)
        end
        ensure_cursor(self)
        return
    end
    cleanup_cursor(self)
    self._win = api.nvim_open_win(self._buf, self._enter, self._config)
    api.nvim_set_option_value("wrap", false, { win = self._win })
    ensure_cursor(self)
end

---Create an independent renderer. Rows are 1-based; span columns are screen cells, 0-based.
function Float.new(opts)
    local self = setmetatable({
        _lines = {},
        _last_row = 0,
        _anchors = 0,
        _enter = false,
        _cursor_hl = false,
        _config = { style = "minimal" },
        _mark_opts = {
            virt_text = { {} },
            virt_text_pos = "overlay",
            right_gravity = false,
        },
    }, Float)
    for key, value in pairs(defaults) do
        self._config[key] = value
    end
    configure_window(self, opts or {})
    self._ns = api.nvim_create_namespace("")
    return self
end

function Float:open()
    ensure_buffer(self, math.max(self._config.height, self._last_row))
    ensure_window(self)
end

function Float:hide()
    if window_valid(self) then
        api.nvim_win_close(self._win, true)
    end
    cleanup_cursor(self)
    self._win = nil
end

function Float:close()
    self:hide()
    if self._buf ~= nil and api.nvim_buf_is_valid(self._buf) then
        api.nvim_buf_delete(self._buf, { force = true })
    end
    self._buf = nil
    self._anchors = 0
    self._last_row = 0
    self._lines = {}
    -- Release the last text/highlight/ID held by the reusable API options.
    self._mark_opts.id = nil
    self._mark_opts.virt_text_win_col = nil
    self._mark_opts.virt_text[1][1] = nil
    self._mark_opts.virt_text[1][2] = nil
end

function Float:set_line(row, line)
    local cached = self._lines[row]
    if cached and cached.ref == line then
        return
    end
    check_row(row)
    ensure_buffer(self, math.max(self._config.height, self._last_row, row), row)
    patch_line(self, row, line, cached)
end

function Float:set_lines(start_row, lines)
    check_row(start_row)
    assert(type(lines) == "table", "lines must be an array of lines")
    local count = #lines
    local end_row = start_row + count - 1
    local ready, restored = false, false
    for i = 1, count do
        local row = start_row + i - 1
        local line = lines[i]
        local cached = self._lines[row]
        if restored or not cached or cached.ref ~= line then
            if not ready then
                -- Earlier unchanged rows are restored by ensure_buffer if
                -- necessary. This loop restores/patches the remaining range.
                restored = ensure_buffer(self, math.max(self._config.height, self._last_row, end_row), row, end_row)
                ready = true
            end
            patch_line(self, row, line, cached)
        end
    end
end

function Float:clear_line(row)
    check_row(row)
    local cached = self._lines[row]
    if not cached then
        return
    end
    local valid = buffer_valid(self)
    delete_line_marks(self, cached, valid)
    self._lines[row] = nil
    if row == self._last_row then
        local last = 0
        for remaining in pairs(self._lines) do
            last = math.max(last, remaining)
        end
        self._last_row = last
        if valid then
            ensure_anchor_lines(self, math.max(self._config.height, last))
        end
    end
end

function Float:clear()
    local valid = buffer_valid(self)
    if valid then
        api.nvim_buf_clear_namespace(self._buf, self._ns, 0, -1)
    end
    self._lines = {}
    self._last_row = 0
    if valid then
        ensure_anchor_lines(self, self._config.height)
    end
end

function Float:flush(row)
    if row ~= nil then
        check_row(row)
        local cached = self._lines[row]
        if cached and cached.ref then
            ensure_buffer(self, math.max(self._config.height, self._last_row), row)
            patch_line(self, row, cached.ref, cached)
        end
        return
    end
    if next(self._lines) == nil then
        return
    end
    if ensure_buffer(self, math.max(self._config.height, self._last_row)) then
        return
    end
    for cached_row, cached in pairs(self._lines) do
        if cached.ref then
            patch_line(self, cached_row, cached.ref, cached)
        end
    end
end

function Float:configure(opts)
    configure_window(self, opts)
end

function Float:is_open()
    return window_valid(self)
end

function Float:buf()
    if buffer_valid(self) then
        return self._buf
    end
end

function Float:win()
    if window_valid(self) then
        return self._win
    end
end

return Float
