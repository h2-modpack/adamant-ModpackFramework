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

---@class AdamantModpackFramework.PackOpts
---@field moduleOrder? string[] Ordered module ids to pin first in the sidebar.
---@field drawPackQuickContent? fun(ctx: AdamantModpackFramework.PackQuickContentContext) Coordinator-owned Quick Setup renderer.
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

---@class AdamantModpackFramework.PackQuickContentContext
---@field ui table ImGui API table.
---@field colors AdamantModpackFramework.ThemeColors
---@field theme AdamantModpackFramework.Theme
---@field getModulesStatus fun(moduleIds: string[]): string, AdamantModpackFramework.Color, boolean
---@field setModulesEnabled fun(moduleIds: string[], enabled: boolean): boolean, string?

---@class AdamantModpackFramework.PackRuntime
---@field moduleRegistry table Opaque framework module registry runtime.
---@field configHash table Opaque framework config-hash runtime.
---@field hud table Opaque framework HUD runtime.
---@field ui AdamantModpackFramework.UIRuntime Opaque framework UI runtime.

---@class AdamantModpackFramework.UIRuntime
---@field renderWindow fun()
---@field addMenuBar fun()
---@field flushPending fun()
---@field handleGuiClosed fun()
---@field dispose fun()

---@class AdamantModpackFramework.GuiCallbacks
---@field render fun() Main Framework window renderer for `rom.gui.add_imgui(...)`.
---@field alwaysDraw fun() Always-draw callback for `rom.gui.add_always_draw_imgui(...)`.
---@field menuBar fun() Menu-bar callback for `rom.gui.add_to_menu_bar(...)`.

---@param packId string Stable coordinator pack id.
---@param displayName string Human-facing coordinator pack name.
---@param config AdamantModpackFramework.Config? Chalk-managed coordinator config, or nil to clear registration.
---@param rebuildCallback? fun(reason: table): boolean Callback invoked after coordinated module structural changes.
---@return boolean ok
function Framework.registerCoordinator(packId, displayName, config, rebuildCallback)
end

---@param packId string Stable coordinator pack id.
---@param config AdamantModpackFramework.Config Chalk-managed coordinator config.
---@param numProfiles integer Number of saved profile slots to normalize and render.
---@param defaultProfiles table Coordinator-owned default profile data.
---@param opts? AdamantModpackFramework.PackOpts Optional coordinator setup controls.
---@return boolean ok
---@return AdamantModpackFramework.PackRuntime? pack
---@return string? err
function Framework.createPack(packId, config, numProfiles, defaultProfiles, opts)
end

---@param packId string Stable coordinator pack id.
---@return AdamantModpackFramework.GuiCallbacks callbacks Register these from the coordinator so ROM attributes the GUI to the pack plugin, not Framework.
function Framework.createGuiCallbacks(packId)
end

return Framework
