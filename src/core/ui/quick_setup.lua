local ctx = ...

local rom = ctx.rom
local ui = rom.ImGui
local drawPackQuickContent = ctx.drawPackQuickContent
local profiles = ctx.profiles
local staging = ctx.staging
local runtime = ctx.runtime
local snapshotAccess = ctx.snapshotAccess
local colors = ctx.colors
local theme = ctx.theme

local function TextColored(imgui, color, text)
    imgui.TextColored(color[1], color[2], color[3], color[4], text)
end

local packQuickContentContext = {
    ui = ui,
    colors = colors,
    theme = theme,
    getModulesStatus = runtime.getModulesStatus,
    setModulesEnabled = function(moduleIds, enabled)
        return runtime.setModulesEnabled(moduleIds, enabled, snapshotAccess.get())
    end,
}

local function drawEntryHeader(entry, snapshot)
    local enabled = staging.modules[entry.id] or false
    local label = entry.name or entry.id
    local startX = ui.GetCursorPosX()
    local toggleWidth = 110
    local toggleX = math.max(startX + 220, startX + ui.GetContentRegionAvail() - toggleWidth)

    TextColored(ui, colors.info, label)
    ui.SameLine()
    ui.SetCursorPosX(toggleX)

    local value, changed = ui.Checkbox("Enabled##quick_" .. tostring(entry.id), enabled)
    if changed then
        local ok = runtime.toggleEntry(entry, value, snapshot)
        if ok then
            enabled = value == true
        end
    end
    if ui.IsItemHovered() and entry.tooltip then
        ui.SetTooltip(entry.tooltip)
    end

    return enabled
end

local function draw(quickList, snapshot)
    profiles.drawQuickSelector()

    ui.Separator()
    ui.Spacing()

    if type(drawPackQuickContent) == "function" then
        drawPackQuickContent(packQuickContentContext)
    end

    for _, entry in ipairs(quickList or {}) do
        ui.Separator()
        ui.Spacing()

        local enabled = drawEntryHeader(entry, snapshot)
        local host = snapshotAccess.getHost(entry, snapshot)

        if enabled and host and type(host.drawQuickContent) == "function" then
            ui.Spacing()
            host.drawQuickContent()
        end

        runtime.commitEntryState(entry, snapshot)
    end
end

return draw
