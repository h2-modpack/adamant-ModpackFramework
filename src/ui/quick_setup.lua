local ctx = ...

local ui = rom.ImGui
local renderQuickSetup = ctx.renderQuickSetup
local profiles = ctx.profiles
local staging = ctx.staging
local runtime = ctx.runtime
local snapshotAccess = ctx.snapshotAccess
local colors = ctx.colors
local theme = ctx.theme

local quickSetupContext = {
    ui = ui,
    colors = colors,
    theme = theme,
    getModulesStatus = runtime.getModulesStatus,
    setModulesEnabled = function(moduleIds, enabled)
        return runtime.setModulesEnabled(moduleIds, enabled, snapshotAccess.get())
    end,
}

local function draw(quickList, snapshot)
    profiles.drawQuickSelector()

    ui.Separator()
    ui.Spacing()

    if type(renderQuickSetup) == "function" then
        renderQuickSetup(quickSetupContext)
    end

    for _, entry in ipairs(quickList or {}) do
        if staging.modules[entry.id] then
            local host = snapshotAccess.getHost(entry, snapshot)
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

return draw
