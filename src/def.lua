-- luacheck: no unused args
---@meta adamant-ModpackFramework

---@class AdamantModpackFramework
local Framework = {}

---@alias AdamantModpackFramework.Color number[]

---@class AdamantModpackFramework.Config
---@field ModEnabled boolean Whether the coordinated pack is enabled.
---@field DebugMode boolean Whether framework/lib debug warnings should be visible.
---@field Profiles AdamantModpackFramework.Profile[]

---@class AdamantModpackFramework.Profile
---@field Name string
---@field Hash string
---@field Tooltip string

---@class AdamantModpackFramework.InitOpts
---@field moduleOrder? string[] Ordered module ids to pin first in the sidebar.
---@field renderQuickSetup? fun(ctx: AdamantModpackFramework.QuickSetupContext) Coordinator-owned Custom Quick Setup renderer.
---@field hideHashMarker? boolean Suppress the HUD hash marker while keeping the coordinator UI active.

---@class AdamantModpackFramework.ThemeColors
---@field text AdamantModpackFramework.Color
---@field textDisabled AdamantModpackFramework.Color
---@field info AdamantModpackFramework.Color
---@field warning AdamantModpackFramework.Color
---@field success AdamantModpackFramework.Color
---@field error AdamantModpackFramework.Color
---@field mixed AdamantModpackFramework.Color

---@class AdamantModpackFramework.Theme
---@field colors AdamantModpackFramework.ThemeColors
---@field ImGuiTreeNodeFlags table
---@field PushTheme fun()
---@field PopTheme fun()

---@class AdamantModpackFramework.QuickSetupContext
---@field ui table ImGui API table.
---@field colors AdamantModpackFramework.ThemeColors
---@field theme AdamantModpackFramework.Theme
---@field getModulesStatus fun(moduleIds: string[]): string, AdamantModpackFramework.Color, boolean
---@field setModulesEnabled fun(moduleIds: string[], enabled: boolean): boolean, string?

---@class AdamantModpackFramework.PackRuntime
---@field discovery table Opaque framework discovery runtime.
---@field hash table Opaque framework hash runtime.
---@field hud table Opaque framework HUD runtime.
---@field ui table Opaque framework UI runtime.

---@param packId string Stable coordinator pack id.
---@param windowTitle string Main framework window title.
---@param config AdamantModpackFramework.Config Chalk-managed coordinator config.
---@param numProfiles integer Number of saved profile slots to normalize and render.
---@param defaultProfiles table Coordinator-owned default profile data.
---@param opts? AdamantModpackFramework.InitOpts Optional coordinator setup controls.
---@return AdamantModpackFramework.PackRuntime
function Framework.init(packId, windowTitle, config, numProfiles, defaultProfiles, opts)
end

---@param packId string
function Framework.registerGui(packId)
end

return Framework
