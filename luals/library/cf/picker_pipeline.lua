---@meta

---@class CFPipelineEditorEdit
---@field target CFRuntimeTarget
---@field name string
---@field source CFDiagnosticSource
---@field kind? string
---@field type_name? string
---@field typemod? string
---@field detach_type? CFPickerDetachType

---@class CFPipelineSourceStep
---@field text string Original operation expression.
---@field source CFDiagnosticSource

---@class CFPipelineSource
---@field fields table<string, string> Original colour expressions by style field.
---@field steps CFPipelineSourceStep[]
---@field comments string[]
---@field signature string SHA-256 of the source file.

---@class CFPipelineEditStep
---@field original? integer One-based original operation index.
---@field name "mix"|"opacity"|"brightness"|"lighten"|"darken"|"shiftHue"|"gamma"
---@field channel "fg"|"bg"|"sp"|"cfg"|"cbg"
---@field value? number
---@field color_expr? string

---@class CFPipelineEdit
---@field fields table<string, string> Replacement colour expressions.
---@field original CFPipelineSource
---@field steps? CFPipelineEditStep[] Replacement operation order, when changed.

---@class CFPipelineEditorStyle: CFHighlightSet
---@field pipeline? CFPipelineOperation[]
---@field link? string

---@class CFPipelineEditorOptions
---@field edit CFPipelineEditorEdit Picker source/target edit.
---@field spec CFPipelineEditorStyle Style containing the pipeline to edit.
---@field reset? boolean Start from an empty pipeline.
---@field inherited? CFHighlightSet
---@field pending? CFPipelineEdit Previously staged pipeline edit.
---@field on_back fun() Reopen the parent picker screen.
---@field on_commit fun(edit:CFPipelineEdit?) Stage or clear the pipeline edit.

---@class CFPipelineDraftStep
---@field original? integer
---@field op CFPipelineOperation
---@field value? number
---@field color_expr? string

---@class CFPipelineDraft
---@field fields table<string, CFPipelinePaletteEntry> Selected palette entries.
---@field steps CFPipelineDraftStep[]

---@class CFPipelinePaletteEntry
---@field label string
---@field expr string
---@field value integer

---@class CFPipelineEditor
---@field row integer
---@field col integer
---@field draft CFPipelineDraft
---@field palette CFPipelinePaletteEntry[]
---@field cancel fun(back:boolean)
---@field accept fun()
---@field adjust fun(amount:number)
---@field delete fun()
---@field insert fun()
---@field enter fun()

local M = {}

---Close the active pipeline editor, if one is open.
function M.close() end

---@param opts CFPipelineEditorOptions
---@return CFPipelineEditor
function M.open(opts) end

return M
