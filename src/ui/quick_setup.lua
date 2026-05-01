local internal = AdamantModpackFramework_Internal
local lib = rom.mods["adamant-ModpackLib"]

function internal.createUIQuickSetup(ctx)
    local ui = rom.ImGui
    local def = ctx.def
    local profiles = ctx.profiles
    local staging = ctx.staging
    local runtime = ctx.runtime
    local snapshots = ctx.snapshots
    local colors = ctx.colors
    local theme = ctx.theme

    local quickSetupContext = {
        ui = ui,
        colors = colors,
        theme = theme,
        getModulesStatus = runtime.getModulesStatus,
        setModulesEnabled = function(moduleIds, enabled)
            return runtime.setModulesEnabled(moduleIds, enabled, snapshots.get())
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
                local host = snapshots.getHost(entry, snapshot)
                if not host then
                    goto continue
                end

                ui.Separator()
                ui.Spacing()
                lib.imguiHelpers.textColored(ui, colors.info, entry.name or entry.id)
                ui.Spacing()
                host.drawQuickContent(ui)
                runtime.commitEntrySession(entry, snapshot)
            end
            ::continue::
        end
    end

    return QuickSetup
end
