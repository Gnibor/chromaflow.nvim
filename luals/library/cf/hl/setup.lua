---@meta

---@class CFPipelineOperation
local CFPipelineOperation = {}

---@class CFRuntimeFunctionContext
---@field frame integer Zero-based runtime action frame. Frame 0 is evaluated immediately.
---@field tick? integer Requested function tick in milliseconds; nil for an untimed runtime function.
---@field delta number Actual milliseconds since the previous action tick.
---@field elapsed number Actual milliseconds since the runtime action started.

---@alias CFRuntimeManipulator fun(style:CFHighlightSet, ctx:CFRuntimeFunctionContext): CFHighlightSet?

---@class CFRuntimeFunctionOperation: CFPipelineOperation
---@field [integer] CFRuntimeFunctionOperation Index with a positive millisecond value, e.g. `r:func("pulse")[300]`.
local RuntimeFunctionOperation = {}

---@class CFStyleTargets
---@field vim? boolean
---@field ts? boolean
---@field lsp? boolean

---@alias CFStyleTargetName "vim"|"ts"|"lsp"

---@class CFThemeConfig
---@field style_targets? CFStyleTargets Hard upper bound for writable target systems.
---@field style_targets_clear? CFStyleTargets Global clear mask applied before modules.
---@field only_style_target? CFStyleTargetName Convenience hard boundary; disables and globally clears the other target systems.

---@class CFHighlightSet
---@field fg? CFColor
---@field bg? CFColor
---@field sp? CFColor
---@field altfont? boolean
---@field bg_indexed? boolean
---@field blink? boolean
---@field bold? boolean
---@field conceal? boolean
---@field standout? boolean
---@field underline? boolean
---@field undercurl? boolean
---@field underdouble? boolean
---@field underdotted? boolean
---@field underdashed? boolean
---@field strikethrough? boolean
---@field italic? boolean
---@field reverse? boolean
---@field nocombine? boolean
---@field blend? integer
---@field ctermfg? integer|string Terminal foreground; use a numeric 0..255 index when manipulating it with .cfg.
---@field ctermbg? integer|string Terminal background; use a numeric 0..255 index for .cbg or as the backdrop of opacity.cfg.
---@field cterm? table<string, boolean>
---@field default? boolean
---@field dim? boolean
---@field fg_indexed? boolean
---@field force? boolean
---@field overline? boolean

---@class CFTypeModStyle: CFHighlightSet
---@field pipeline? CFPipelineOperation[] Further manipulates the finished base-group colors.
---@field link? string Link this typemod instead of styling it.
---@field priority? number ChromaFlow compile priority. Inherits the group priority when omitted.

---@alias CFGroupTypeMod boolean|CFTypeModStyle

---@class CFSemanticGroupStyle: CFHighlightSet
---@field pipeline? CFPipelineOperation[]
---@field types? string[] Additional semantic types linked to the primary type.
---@field typemods? table<string, CFGroupTypeMod> Type+TypeMod handling.
---@field style_targets? CFStyleTargets Per-group target override inside config/module permissions.
---@field style_targets_clear? CFStyleTargets Per-group clear action, independent from style_targets.
---@field link? string Semantic link target. Mutually exclusive with style fields/pipeline.
---@field priority? number ChromaFlow compile priority. Higher runs later; equal priority keeps compile order.

---@class CFResolvedGroupStyle: CFHighlightSet
---@field pipeline? CFPipelineOperation[]
---@field types? string[] Additional resolver base types linked to the primary type.
---@field typemods? table<string, CFGroupTypeMod> Semantic TypeMod names resolved without a filetype context.
---@field style_targets? CFStyleTargets Per-group target override inside config/module permissions.
---@field style_targets_clear? CFStyleTargets Per-group clear action, independent from style_targets.
---@field link? string Resolver target type/base name. Mutually exclusive with style fields/pipeline.
---@field priority? number ChromaFlow compile priority.

---@class CFRawGroupStyle: CFHighlightSet
---@field pipeline? CFPipelineOperation[]
---@field types? string[] Additional exact hl_groups linked to the primary raw group.
---@field typemods? table<string, CFGroupTypeMod> Keys are full literal hl_group names.
---@field link? string Exact literal link target. Mutually exclusive with style fields/pipeline.
---@field priority? number ChromaFlow compile priority.
---@field clear? boolean Clear each literal base/group/typemod target immediately before setting/linking it.

---@class CFModuleModStyle: CFHighlightSet
---@field pipeline? CFPipelineOperation[]
---@field link? string Semantic target Type for a mod-only link.
---@field priority? number ChromaFlow compile priority.

---@alias CFModuleMod false|CFModuleModStyle

---@class CFGroupDeclaration
---@field _cf_declaration true
---@field kind "language"|"plugin"|"ui"|"raw"
---@field action "group"
---@field name string
---@field spec CFSemanticGroupStyle|CFResolvedGroupStyle|CFRawGroupStyle
---@field source? CFDiagnosticSource
local CFGroupDeclaration = {}

---@class CFLinkDeclaration
---@field _cf_declaration true
---@field kind "language"|"plugin"|"ui"|"raw"
---@field action "link"
---@field name string Source group.
---@field target string Target group.
---@field source? CFDiagnosticSource
local CFLinkDeclaration = {}

---@alias CFModuleDeclaration CFGroupDeclaration|CFLinkDeclaration

---@class CFModuleSpec
---@field [integer] CFModuleDeclaration? Sparse declaration slots are valid; ignored DSL calls can leave nil holes.
---@field style_targets? CFStyleTargets Module target defaults inside config permissions.
---@field style_targets_clear? CFStyleTargets Clear each group/typemod/link in this module before materializing it.
---@field mods? table<string, CFModuleMod> Mods without a concrete Type. The resolver maps them to language-specific or global Vim/TS/LSP forms.

---@class CFUnaryPipelineAPI
---@field fg fun(value:number): CFPipelineOperation
---@field bg fun(value:number): CFPipelineOperation
---@field sp fun(value:number): CFPipelineOperation
---@field cfg fun(value:number): CFPipelineOperation Terminal foreground only; writes ctermfg, not fg.
---@field cbg fun(value:number): CFPipelineOperation Terminal background only; writes ctermbg, not bg.

---@class CFMixPipelineAPI
---@field fg fun(percent:number, addedColor:CFColor): CFPipelineOperation
---@field bg fun(percent:number, addedColor:CFColor): CFPipelineOperation
---@field sp fun(percent:number, addedColor:CFColor): CFPipelineOperation
---@field cfg fun(percent:number, addedColor:CFColor): CFPipelineOperation Terminal foreground only; addedColor is ARGB/hex, not an index.
---@field cbg fun(percent:number, addedColor:CFColor): CFPipelineOperation Terminal background only; addedColor is ARGB/hex, not an index.

---@class CFLanguageModule: CFCompiledModule
---@field kind "language"
---@field name? string

---@class CFPluginModule: CFCompiledModule
---@field kind "plugin"
---@field name string

---@class CFUIModule: CFCompiledModule
---@field kind "ui"

---@class CFRuntimeTarget
---@operator call(...): nil Calling a semantic target inside a loaded `.cf` file is treated as an unknown DSL call and ignored with a HINT; outside that context it errors at runtime.
---@field [string] CFRuntimeTarget A typemod-specific target, e.g. `hl.language.lua.variable.readonly`.
local RuntimeTarget = {}

---@class CFRuntimeLanguageScope
---@operator call(...): nil Calling a dynamic language scope as a DSL method (for example a typo such as `l:goup(...)`) is ignored with a HINT while a `.cf` file is loading.
---@field [string] CFRuntimeTarget Semantic type target in one language/filetype.
local RuntimeLanguageScope = {}

---@class CFRuntimePluginScope
---@operator call(...): nil Calling a dynamic plugin scope as a DSL method is ignored with a HINT while a `.cf` file is loading.
---@field [string] CFRuntimeTarget Resolver-backed target inside one plugin identity.
local RuntimePluginScope = {}

---@class CFRuntimeActionStyle: CFHighlightSet
---@field pipeline? (CFPipelineOperation|CFRuntimeFunctionOperation)[] Applied after explicit action fields. `apply()` uses the theme base; `replace()` has no inherited base.

---@class CFRuntimeGroupDeclaration
---@field _cf_runtime_declaration true
---@field name string
---@field spec CFRuntimeActionStyle
---@field source? CFDiagnosticSource
local RuntimeGroupDeclaration = {}

---@alias CFRuntimeModuleSpec CFRuntimeGroupDeclaration[]

---@class CFRuntimeModuleDefinition
---@field _cf_runtime_module true
---@field name string
---@field groups table<string, CFRuntimeActionStyle>
---@field group_ticks table<string, integer?> Millisecond interval per action, if timed.
---@field group_sources table<string, CFDiagnosticSource?>
---@field declarations CFRuntimeModuleSpec
---@field source? CFDiagnosticSource
---@field exports table<string, any> Functions and values assigned to the runtime DSL proxy.
local RuntimeModuleDefinition = {}

---@class CFRuntimeAction
local RuntimeAction = {}

---@class CFRuntimeGroups
---@field [string] CFRuntimeAction
local RuntimeGroups = {}

---@class CFRuntimeModule
---@field groups CFRuntimeGroups
---@field g CFRuntimeGroups Short alias for `groups`.
---@field apply fun(target:CFRuntimeTarget, action:CFRuntimeAction):boolean Apply an action as a delta to the current theme base.
---@field replace fun(target:CFRuntimeTarget, action:CFRuntimeAction):boolean Replace the target style with the runtime action style.
---@field reset fun(target:CFRuntimeTarget):boolean Remove this target's runtime override and restore the theme base.
---@field clear fun(target:CFRuntimeTarget):boolean Clear every concrete hl_group owned by the semantic target.
---@field [string] any Runtime-module exports such as functions assigned with `function r.foo(...) ... end`.
local RuntimeModule = {}

---@class CFRuntimeAPI
---@operator call(string): CFRuntimeModule Load a runtime module by logical name, without `.cf`.
---@field groups CFRuntimeGroups Available on the module-scoped proxy while executing runtime/*.cf.
---@field g CFRuntimeGroups Short alias for `groups`.
---@field apply fun(target:CFRuntimeTarget, action:CFRuntimeAction):boolean Available on the module-scoped proxy.
---@field replace fun(target:CFRuntimeTarget, action:CFRuntimeAction):boolean
---@field reset fun(target:CFRuntimeTarget):boolean
---@field clear fun(target:CFRuntimeTarget):boolean
---@field [string] any Module-local exports while executing a runtime `.cf` file. group/func/setup are reserved DSL methods.
local Runtime = {}

---@param name string
---@param spec CFRuntimeActionStyle At least one highlight field or a pipeline; group/link/priority/target metadata is invalid here.
---@return CFRuntimeGroupDeclaration
function Runtime:group(name, spec) end

---Adapt a named module function (`r[name]`) into a full-style runtime pipeline operation.
---@param name string
---@return CFRuntimeFunctionOperation
function Runtime:func(name) end

---@param spec CFRuntimeModuleSpec Array of r:group() declarations; may be called once per runtime module load.
---@return CFRuntimeModuleDefinition
function Runtime.setup(spec) end

---@class CFLanguageAPI
---@field [string] CFRuntimeLanguageScope Runtime semantic targets by language, e.g. `hl.language.lua.variable`.
local Language = {}

---@param name string Semantic base type.
---@param spec CFSemanticGroupStyle
---@return CFGroupDeclaration
function Language:group(name, spec) end

---Create a semantic source -> semantic target link declaration.
---@param source string Semantic source type.
---@param target string Semantic target type.
---@return CFLinkDeclaration
function Language:link(source, target) end

---Use a dot call: `l.setup("lua", {...})` or `l.setup(nil, {...})` for global syntax groups.
---The first argument is positional and cannot be omitted.
---@param language string|nil Language/filetype context; nil means global syntax groups.
---@param spec CFModuleSpec
---@return CFLanguageModule
function Language.setup(language, spec) end

---@class CFPluginAPI
---@field [string] CFRuntimePluginScope Runtime semantic targets by plugin identity.
local Plugin = {}

---@param name string Resolver base group name. Actual Vim/TS/LSP form is selected by style_targets.
---@param spec CFResolvedGroupStyle
---@return CFGroupDeclaration
function Plugin:group(name, spec) end

---Create a resolver-backed plugin source -> target link declaration. Uses module style_targets.
---@param source string Resolver source base name.
---@param target string Resolver target base name.
---@return CFLinkDeclaration
function Plugin:link(source, target) end

---@param name string Plugin/fallback identity; it is not a filetype.
---@param spec CFModuleSpec Resolved plugin groups need module or group style_targets; p:link() and module mods need module style_targets.
---@return CFPluginModule
function Plugin.setup(name, spec) end

---@class CFUIAPI
---@field [string] CFRuntimeTarget Runtime target for a UI semantic group.
local UI = {}

---@param name string Resolver base group name. UI defaults to Vim; style_targets may override it.
---@param spec CFResolvedGroupStyle
---@return CFGroupDeclaration
function UI:group(name, spec) end

---Create a resolver-backed UI source -> target link declaration. UI defaults to Vim targets.
---@param source string Resolver source base name.
---@param target string Resolver target base name.
---@return CFLinkDeclaration
function UI:link(source, target) end

---@param spec CFModuleSpec style_targets overrides the Vim-only UI default.
---@return CFUIModule
function UI.setup(spec) end

---@class CFRawAPI
---@field [string] CFRuntimeTarget Runtime target for an exact raw hl_group.
local Raw = {}

---Create one literal hl_group declaration. No semantic resolution, target
---classification, filetype suffixing or Vim/TS/LSP expansion is performed.
---@param name string Exact hl_group name.
---@param spec CFRawGroupStyle
---@return CFGroupDeclaration
function Raw:group(name, spec) end

---Create one exact literal source -> target link declaration.
---@param source string Exact source hl_group.
---@param target string Exact target hl_group.
---@return CFLinkDeclaration
function Raw:link(source, target) end

---Public `require("cf.hl.setup")` theme/DSL surface.
---@class CFHLSetup
---@field colors table<string, any> The single resolved color.cf table for the current compile.
---@field language CFLanguageAPI
---@field plugin CFPluginAPI
---@field ui CFUIAPI
---@field raw CFRawAPI Literal group/link escape hatch usable inside any l/p/u setup table.
---@field runtime CFRuntimeAPI Callable runtime-module loader and runtime action DSL.
---@field mix CFMixPipelineAPI
---@field opacity CFUnaryPipelineAPI
---@field brightness CFUnaryPipelineAPI
---@field lighten CFUnaryPipelineAPI
---@field darken CFUnaryPipelineAPI
---@field shiftHue CFUnaryPipelineAPI
---@field gamma CFUnaryPipelineAPI
local M = {}

return M
