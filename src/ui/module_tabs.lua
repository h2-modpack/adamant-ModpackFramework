local ctx = ...

local ui = rom.ImGui
local staging = ctx.staging
local runtime = ctx.runtime
local snapshotAccess = ctx.snapshotAccess

local function drawEntryBody(entry, snapshot)
    local host = snapshotAccess.getHost(entry, snapshot)
    if not host then
        return
    end

    host.drawTab(ui)

    runtime.commitEntrySession(entry, snapshot)
end

local function draw(entry, snapshot)
    local enabled = staging.modules[entry.id] or false
    local val, chg = ui.Checkbox(entry._enableLabel, enabled)
    if chg then
        runtime.toggleEntry(entry, val, snapshot)
    end
    if ui.IsItemHovered() and entry.tooltip then
        ui.SetTooltip(entry.tooltip)
    end

    if not enabled then return end

    ui.Spacing()
    drawEntryBody(entry, snapshot)
end

return draw
