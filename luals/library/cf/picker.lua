---@meta

---@class CFPickerDetachType
---@field parent string
---@field child string
---@field base CFHighlightSet
---@field remove_from_types boolean
---@field copy_parent_metadata boolean

---@class CFPickerEdit
---@field target? CFRuntimeTarget
---@field source CFDiagnosticSource
---@field action? table
---@field kind? string
---@field name? string
---@field type_name? string
---@field typemod? string
---@field detach_type? CFPickerDetachType
---@field pipeline_edit? CFPipelineEdit
---@field value? boolean Rule edit value for a TypeMod.

---@class CFPickerAPI
local M = {}

---Enable picker source tracking.
---@return CFPickerAPI
function M.start() end

---Discard staged picker edits and disable source tracking.
---@return CFPickerAPI
function M.stop() end

---Open the highlight picker for the current cursor position.
---@return CFMenu? menu Nil when no highlight is available.
function M.open() end

---Internal save handoff; returned tables are owned by the picker.
---@return table<string, CFPickerEdit>
function M._style_edits() end

---@return table<string, CFPickerEdit>
function M._rule_edits() end

---@return table<string, CFPickerEdit>
function M._pipeline_edits() end

---@return string[]
function M._style_flags() end

---@return string[]
function M._style_fields() end

return M
