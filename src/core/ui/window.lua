local deps = ...
local rom = deps.rom
local logging = deps.logging

local function TextColored(ui, color, text)
    ui.TextColored(color[1], color[2], color[3], color[4], text)
end

local function createUI(moduleRegistry, hud, theme, config, packId, windowTitle, numProfiles,
                        defaultProfiles, drawPackQuickContent, auditSavedProfiles, frameworkRuntime)
    local ui = rom.ImGui
    local DEFAULT_WINDOW_WIDTH = 1280
    local DEFAULT_WINDOW_HEIGHT = 840
    local SIDEBAR_RATIO = 0.2

    local colors = theme.colors
    local PushTheme = theme.PushTheme
    local PopTheme = theme.PopTheme

    local staging = {
        ModEnabled = config.ModEnabled == true,
        modules = {},
        debug = {},
    }

    local snapshotAccess = {
        current = nil,
    }

    function snapshotAccess.capture()
        snapshotAccess.current = moduleRegistry.live.captureSnapshot()
        return snapshotAccess.current
    end

    function snapshotAccess.get()
        return snapshotAccess.current
    end

    function snapshotAccess.getLiveModule(entry, snapshot)
        return moduleRegistry.snapshot.getLiveModule(entry, snapshot or snapshotAccess.current)
    end

    local profiles

    local function snapshotToStaging()
        staging.ModEnabled = config.ModEnabled == true
        local snapshot = snapshotAccess.capture()

        for _, entry in ipairs(moduleRegistry.modules) do
            local liveModule = snapshotAccess.getLiveModule(entry, snapshot)
            if liveModule then
                liveModule.reloadFromConfig()
            end

            staging.modules[entry.id] = moduleRegistry.snapshot.isEntryEnabled(entry, snapshot)
            staging.debug[entry.id] = moduleRegistry.snapshot.isDebugEnabled(entry, snapshot)
        end

        if profiles then
            profiles.snapshot()
        end
    end

    local runtime = import("core/ui/runtime.lua", nil, {
        rom = rom,
        moduleRegistry = moduleRegistry,
        hud = hud,
        config = config,
        packId = packId,
        colors = colors,
        staging = staging,
        snapshotAccess = snapshotAccess,
        snapshotToStaging = snapshotToStaging,
        logging = logging,
        onProfileLoaded = function()
            if profiles then
                profiles.markSlotLabelsDirty()
            end
        end,
    })

    profiles = import("core/ui/profiles.lua", nil, {
        rom = rom,
        config = config,
        colors = colors,
        numProfiles = numProfiles,
        defaultProfiles = defaultProfiles,
        packId = packId,
        moduleRegistry = moduleRegistry,
        runtime = runtime,
        auditSavedProfiles = auditSavedProfiles,
    })

    local drawQuickSetup = import("core/ui/quick_setup.lua", nil, {
        rom = rom,
        drawPackQuickContent = drawPackQuickContent,
        theme = theme,
        profiles = profiles,
        staging = staging,
        runtime = runtime,
        snapshotAccess = snapshotAccess,
        colors = colors,
    })

    local drawModuleTab = import("core/ui/module_tabs.lua", nil, {
        rom = rom,
        staging = staging,
        runtime = runtime,
        snapshotAccess = snapshotAccess,
    })

    local drawDev = import("core/ui/dev.lua", nil, {
        rom = rom,
        config = config,
        colors = colors,
        moduleRegistry = moduleRegistry,
        staging = staging,
        runtime = runtime,
        frameworkRuntime = frameworkRuntime,
    })

    runtime.reconcilePackDisabledState()
    snapshotToStaging()

    local moduleByTabLabel = {}
    local cachedTabList = nil
    local cachedQuickList = nil
    local selectedTab = "Quick Setup"
    local _showModWindow = false
    local uiSuppressionToken = nil
    local disposed = false

    for _, entry in ipairs(moduleRegistry.modules) do
        moduleByTabLabel[entry._tabLabel] = entry
    end

    local function buildTabList()
        if cachedTabList then
            return cachedTabList
        end

        cachedTabList = { "Quick Setup" }
        cachedQuickList = {}

        for _, entry in ipairs(moduleRegistry.tabOrder) do
            table.insert(cachedTabList, entry._tabLabel)
        end

        for _, entry in ipairs(moduleRegistry.tabOrder) do
            table.insert(cachedQuickList, entry)
        end

        table.insert(cachedTabList, "Profiles")
        table.insert(cachedTabList, "Dev")
        return cachedTabList
    end

    local function drawProfiles()
        profiles.draw()
    end

    local function drawMainWindow(snapshot)
        local val, chg = ui.Checkbox("Enable Mod", staging.ModEnabled)
        if chg then
            runtime.setPackRuntimeState(val, snapshot)
        end
        if ui.IsItemHovered() then
            ui.SetTooltip("Toggle the entire modpack on or off.")
        end

        if not staging.ModEnabled then
            ui.Separator()
            TextColored(ui, colors.warning, "Mod is currently disabled. All changes have been reverted.")
            return
        end

        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        local tabs = buildTabList()
        local totalW = ui.GetWindowWidth()
        local sidebarW = totalW * SIDEBAR_RATIO

        ui.BeginChild("Sidebar", sidebarW, 0, true)
        for _, tabName in ipairs(tabs) do
            if ui.Selectable(tabName, selectedTab == tabName) then
                selectedTab = tabName
            end
        end
        ui.EndChild()

        ui.SameLine()

        ui.BeginChild("TabContent", 0, 0, true)
        ui.Spacing()

        if selectedTab == "Quick Setup" then
            drawQuickSetup(cachedQuickList, snapshot)
        elseif selectedTab == "Profiles" then
            drawProfiles()
        elseif selectedTab == "Dev" then
            drawDev(snapshot)
        elseif moduleByTabLabel[selectedTab] then
            drawModuleTab(moduleByTabLabel[selectedTab], snapshot)
        end

        ui.EndChild()
    end

    local function seedWindowSize()
        ui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
    end

    local function flushPending()
        runtime.flushPendingRunData()
        hud.flushPendingHash()
    end

    local function suppressOverlays()
        if not uiSuppressionToken then
            uiSuppressionToken = frameworkRuntime.ui.suppressOverlays()
        end
    end

    local function releaseOverlaySuppression()
        if uiSuppressionToken then
            uiSuppressionToken.release()
            uiSuppressionToken = nil
        end
    end

    local function handleGuiClosed()
        if disposed then
            return
        end
        flushPending()
        releaseOverlaySuppression()
    end

    local function closeWindow()
        if disposed then
            return
        end
        flushPending()
        _showModWindow = false
        releaseOverlaySuppression()
    end

    local function dispose()
        if disposed then
            return
        end
        disposed = true
        flushPending()
        _showModWindow = false
        releaseOverlaySuppression()
    end

    local function renderWindow()
        if disposed then
            return
        end
        if not _showModWindow then
            return
        end
        suppressOverlays()

        PushTheme()

        local beganWindow = false
        local openState = _showModWindow
        local ok, err = xpcall(function()
            profiles.tick()
            seedWindowSize()
            local shouldDraw
            openState, shouldDraw = ui.Begin(windowTitle, _showModWindow)
            beganWindow = true
            if shouldDraw then
                drawMainWindow(snapshotAccess.capture())
            end
        end, debug.traceback)

        if beganWindow then
            ui.End()
        end
        PopTheme()

        if not ok then
            error(err)
        end

        if openState == false then
            closeWindow()
        end
    end

    local function addMenuBar()
        if disposed then
            return
        end
        if ui.MenuItem("Show Mod Menu") then
            if _showModWindow then
                closeWindow()
            else
                _showModWindow = true
                suppressOverlays()
            end
        end
    end

    return {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
        flushPending = flushPending,
        handleGuiClosed = handleGuiClosed,
        dispose = dispose,
    }
end

return createUI
