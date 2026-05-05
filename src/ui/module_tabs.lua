local internal = AdamantModpackFramework_Internal

function internal.createUIModuleTabs(ctx)
    local ui = rom.ImGui
    local staging = ctx.staging
    local runtime = ctx.runtime
    local snapshots = ctx.snapshots

    local ModuleTabs = {}

    local function drawEntryBody(entry, snapshot)
        local host = snapshots.getHost(entry, snapshot)
        if not host then
            return
        end

        host.drawTab(ui)

        runtime.commitEntrySession(entry, snapshot)
    end

    function ModuleTabs.draw(entry, snapshot)
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

    return ModuleTabs
end
