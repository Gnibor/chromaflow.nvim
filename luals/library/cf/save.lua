---@meta

---@class CFSaveFile
---@field path string
---@field original string
---@field content string

---@class CFSavePlan
---@field files CFSaveFile[]
---@field count integer Number of changed picker edits.

local M = {}

---Read literal source positions and expressions for a compiled pipeline.
---@param edit CFPipelineEditorEdit
---@param compiled_operations? CFPipelineOperation[]
---@return CFPipelineSource
function M._pipeline_source(edit, compiled_operations) end

---Build and validate source edits without writing files.
---@return CFSavePlan
function M.plan() end

---Write all files in a validated save plan.
---@param plan CFSavePlan
---@return integer file_count
function M.write(plan) end

---Plan, write, and report confirmed picker edits.
---@return integer edit_count
---@return integer file_count
function M.save() end

return M
