local internal = AdamantModpackFramework_Internal

function internal.createUIQuickSetup(ctx)
    local ui = ctx.ui
    local def = ctx.def
    local profiles = ctx.profiles
    local staging = ctx.staging
    local runtime = ctx.runtime
    local getSnapshotHost = ctx.getSnapshotHost
    local drawColoredText = ctx.drawColoredText
    local colors = ctx.colors
    local theme = ctx.theme
    local getCurrentSnapshot = ctx.getCurrentSnapshot

    local quickSetupContext = {
        ui = ui,
        colors = colors,
        theme = theme,
        drawColoredText = drawColoredText,
        getModulesStatus = runtime.getModulesStatus,
        setModulesEnabled = function(moduleIds, enabled)
            return runtime.setModulesEnabled(moduleIds, enabled, getCurrentSnapshot())
        end,
    }

    local QuickSetup = {}

    function QuickSetup.draw(quickList, snapshot)
        profiles.drawQuickSelector()

        ui.Separator()
        ui.Spacing()

        if type(def.renderQuickSetup) == "function" then
            def.renderQuickSetup(quickSetupContext)
        end

        for _, entry in ipairs(quickList or {}) do
            if staging.modules[entry.id] then
                local host = getSnapshotHost(entry, snapshot)
                if not host then
                    goto continue
                end

                ui.Separator()
                ui.Spacing()
                drawColoredText(colors.info, entry.name or entry.id)
                ui.Spacing()
                host.drawQuickContent(ui)
                runtime.commitEntrySession(entry, snapshot)
            end
            ::continue::
        end
    end

    return QuickSetup
end
