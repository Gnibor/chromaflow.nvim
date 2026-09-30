---@meta

---@class CFColorTraceRecord
---@field index integer
---@field owner? CFDiagnosticSource
---@field source CFDiagnosticSource
---@field trace CFPipelineTrace
---@field pipeline_index integer

---@class CFColorTraceCacheEntry
---@field file string
---@field records CFColorTraceRecord[]
---@field by_source table<string, CFColorTraceRecord>

local M = {}

---Enable or disable live ColorTrace diagnostics.
---@param enabled boolean
function M.set_enabled(enabled) end

---Enable or disable the picker's source trace cache.
---@param enabled boolean
function M.set_picker(enabled) end

---@return boolean
function M.color_trace_enabled() end

---@return boolean
function M.picker_enabled() end

---Emit a cached file trace for the current compiled theme, if one exists.
---@param path string
---@param compiled CFCompiledTheme
---@return integer? record_count Nil means no valid cache; zero is a valid empty cache.
function M.emit_file(path, compiled) end

---Internal source and compile hooks used by the theme loader and picker.
---@param path string
---@return boolean trace_source
---@return boolean emit_color_trace
function M._source_mode(path) end

---@param path string
function M._source_begin(path) end

---@param owner_source? CFDiagnosticSource
---@param source CFDiagnosticSource
---@param trace CFPipelineTrace
---@param pipeline_index integer
---@param emit_color_trace boolean
function M._record(owner_source, source, trace, pipeline_index, emit_color_trace) end

function M._compile_begin() end

---@param compiled CFCompiledTheme
function M._compile_finish(compiled) end

function M._compile_abort() end

---@param compiled CFCompiledTheme
function M._activate(compiled) end

---@param path string
---@param compiled CFCompiledTheme
---@return integer? token
function M._reuse_begin(path, compiled) end

---@param token integer
function M._reuse_end(token) end

---@param path string
---@param compiled CFCompiledTheme
---@return CFColorTraceCacheEntry? entry
function M._cached(path, compiled) end

return M
