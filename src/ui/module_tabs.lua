local internal = AdamantModpackFramework_Internal

function internal.createUIModuleTabs(ctx)
    local ui = ctx.ui
    local staging = ctx.staging
    local runtime = ctx.runtime
    local getSnapshotHost = ctx.getSnapshotHost

    local ModuleTabs = {}

    local function drawEntryBody(entry, snapshot)
        local host = getSnapshotHost(entry, snapshot)
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
        if ui.IsItemHovered() and entry.definition.tooltip then
            ui.SetTooltip(entry.definition.tooltip)
        end

        if not enabled then return end

        ui.Spacing()
        drawEntryBody(entry, snapshot)
    end

    return ModuleTabs
end
