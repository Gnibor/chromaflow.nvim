---@meta

---@alias CFDiagnosticSeverityName "hint"|"warn"|"warning"|"error"
---@alias CFDiagnosticSeverity CFDiagnosticSeverityName|integer
---@alias CFDiagnosticTag string
---@alias CFDiagnosticMessageKind "info"|"ok"
---@alias CFDiagnosticForm "diagnostic"|"message"
---@alias CFDiagnosticOutputForm "diagnostic"|"message"|"assert"

---@class CFDiagnosticSource
---@field file string
---@field line integer 1-based source line.
---@field col integer 1-based source column.
---@field end_line? integer 1-based end line for a captured DSL call.
---@field end_col? integer 1-based end column for a captured DSL call.

---@class CFDiagnosticContext
---@field kind? string
---@field name? string

---@class CFDiagnosticRecordData
---@field message string
---@field source CFDiagnosticSource
---@field context? CFDiagnosticContext
---@field tags? CFDiagnosticTag[]
---@field code? string|integer
---@field data? any

---@class CFDiagnosticAssertionData: CFDiagnosticRecordData
---@field severity? CFDiagnosticSeverity Defaults to ERROR; ASSERT is only a render fallback.

---@class CFDiagnosticRecord
---@field id integer
---@field time_ns integer
---@field form CFDiagnosticForm
---@field message string
---@field source CFDiagnosticSource
---@field context? CFDiagnosticContext
---@field tags CFDiagnosticTag[]
---@field code? string|integer
---@field data? any
---@field severity? integer Only for `form == "diagnostic"`.
---@field kind? CFDiagnosticMessageKind Only for `form == "message"`.
---@field message_policy? boolean Only for `form == "message"`; false bypasses the normal message visibility filter.

---@class CFDiagnosticConfigure
---@field severity_bias? integer
---@field severity? { hint?: boolean, warn?: boolean, error?: boolean }
---@field messages? { info?: boolean, ok?: boolean }

---@class CFDiagnosticPolicy: CFDiagnosticConfigure
---@field severity_bias integer
---@field severity { hint: boolean, warn: boolean, error: boolean }
---@field messages { info: boolean, ok: boolean }

---@class CFDiagnosticAPI
---@field severity { HINT: integer, WARN: integer, ERROR: integer, MIN: integer, MAX: integer }
---@field tag { DEPRECATED: string, UNNECESSARY: string }
---@field message { INFO: "info", OK: "ok" }
---@field form { DIAGNOSTIC: "diagnostic", MESSAGE: "message", ASSERT: "assert" }
local M = {}

---@param opts? CFDiagnosticConfigure
---@return boolean ok
---@return string? error
function M.configure(opts) end

---@return CFDiagnosticPolicy
function M.policy() end

---@param value CFDiagnosticSeverity
---@return "hint"|"warn"|"error"|nil
---@return string? error
function M.classify(value) end

---@param value CFDiagnosticSeverity
---@return integer? effective
---@return string? error
function M.effective_severity(value) end

---@param severity CFDiagnosticSeverity
---@param data CFDiagnosticRecordData
---@return CFDiagnosticRecord? record
---@return string? error
function M.report(severity, data) end

---@param kind CFDiagnosticMessageKind
---@param data CFDiagnosticRecordData
---@return CFDiagnosticRecord? record
---@return string? error
function M.user_message(kind, data) end

---@param data CFDiagnosticRecordData
---@return CFDiagnosticRecord? record
---@return string? error
function M.info(data) end

---@param data CFDiagnosticRecordData
---@return CFDiagnosticRecord? record
---@return string? error
function M.ok(data) end

---Compatibility helper that enqueues an ERROR diagnostic. ASSERT itself is chosen only at flush time.
---@param data CFDiagnosticAssertionData
---@return CFDiagnosticRecord? record
---@return string? error
function M.assertion(data) end

---@param record CFDiagnosticRecord
---@return boolean
function M.visible(record) end

---@param record CFDiagnosticRecord
---@return CFDiagnosticOutputForm? form
function M.output_form(record) end

---@param record CFDiagnosticRecord
---@return string? text
---@return string? error
function M.format(record) end

---@return integer rendered
function M.flush() end

---Render pending records for one source buffer without clearing diagnostics in other buffers.
---@param bufnr integer
---@return integer rendered
function M.flush_buffer(bufnr) end

---Open the ChromaFlow diagnostic float for the current line, when available.
function M.open_float() end

---@return CFDiagnosticRecord[]
function M.pending() end

---@return CFDiagnosticRecord[]
function M.history() end

function M.clear_pending() end
function M.clear_history() end

---@param bufnr? integer
---@return boolean ok
---@return string? error
function M.clear_rendered(bufnr) end

function M.clear() end

return M
