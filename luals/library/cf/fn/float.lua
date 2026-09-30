---@meta

---@class CFFloatOptions
---@field width? integer
---@field height? integer
---@field relative? "editor"|"cursor"|"win"
---@field row? number
---@field col? number
---@field anchor? "NW"|"NE"|"SW"|"SE"
---@field border? string
---@field title? string
---@field title_pos? "left"|"center"|"right"
---@field focusable? boolean
---@field zindex? integer
---@field win? integer
---@field enter? boolean
---@field cursor_hl? string|false

---@class CFFloatSpan
---@field col integer Zero-based screen column.
---@field text string Single-line text.
---@field hl? string Highlight group.

---@class CFFloat
local Float = {}

---Create an independent floating renderer. Rows are one-based.
---@param opts? CFFloatOptions
---@return CFFloat
function Float.new(opts) end

function Float:open() end
function Float:hide() end
function Float:close() end

---@param row integer One-based row.
---@param line CFFloatSpan[]
function Float:set_line(row, line) end

---@param start_row integer One-based start row.
---@param lines CFFloatSpan[][]
function Float:set_lines(start_row, lines) end

---@param row integer
function Float:clear_line(row) end

function Float:clear() end

---@param row? integer Repaint one cached row, or all rows when omitted.
function Float:flush(row) end

---@param opts CFFloatOptions
function Float:configure(opts) end

---@return boolean
function Float:is_open() end

---@return integer? bufnr
function Float:buf() end

---@return integer? winid
function Float:win() end

return Float
