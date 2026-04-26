import "ui/runtime.lua"
import "ui/profiles.lua"
import "ui/dev.lua"
import "ui/quick_setup.lua"
import "ui/module_tabs.lua"

function Framework.createUI(discovery, hud, theme, def, config, lib, packId, windowTitle)
    local internal = AdamantModpackFramework_Internal
    local ui = rom.ImGui
    local DEFAULT_WINDOW_WIDTH = 1280
    local DEFAULT_WINDOW_HEIGHT = 840

    local colors = theme.colors
    local SIDEBAR_RATIO = theme.SIDEBAR_RATIO
    local FIELD_MEDIUM = theme.FIELD_MEDIUM
    local FIELD_NARROW = theme.FIELD_NARROW
    local FIELD_WIDE = theme.FIELD_WIDE
    local PushTheme = theme.PushTheme
    local PopTheme = theme.PopTheme

    local currentSnapshot = nil
    local staging = {
        ModEnabled = config.ModEnabled == true,
        modules = {},
        debug = {},
    }

    local function drawColoredText(color, text)
        ui.TextColored(color[1], color[2], color[3], color[4], text)
    end

    local function captureSnapshot()
        currentSnapshot = discovery.live.captureSnapshot()
        return currentSnapshot
    end

    local function getCurrentSnapshot()
        return currentSnapshot
    end

    local function getSnapshotHost(entry, snapshot)
        return discovery.snapshot.getHost(entry, snapshot)
    end

    local profiles
    local runtime

    local function snapshotToStaging()
        staging.ModEnabled = config.ModEnabled == true
        local snapshot = captureSnapshot()

        for _, m in ipairs(discovery.modules) do
            staging.modules[m.id] = discovery.snapshot.isModuleEnabled(m, snapshot)
            staging.debug[m.id] = discovery.snapshot.isDebugEnabled(m, snapshot)

            local host = getSnapshotHost(m, snapshot)
            if host then
                host.reloadFromConfig()
            end
        end

        if profiles then
            profiles.snapshot()
        end
    end

    runtime = internal.createUIRuntime({
        discovery = discovery,
        hud = hud,
        config = config,
        lib = lib,
        packId = packId,
        colors = colors,
        staging = staging,
        captureSnapshot = captureSnapshot,
        getSnapshotHost = getSnapshotHost,
        getCurrentSnapshot = getCurrentSnapshot,
        snapshotToStaging = snapshotToStaging,
        onProfileLoaded = function()
            if profiles then
                profiles.markSlotLabelsDirty()
            end
        end,
    })

    profiles = internal.createUIProfiles({
        ui = ui,
        config = config,
        colors = colors,
        def = def,
        drawColoredText = drawColoredText,
        getCachedHash = runtime.getCachedHash,
        loadProfile = runtime.loadProfile,
        fieldMedium = FIELD_MEDIUM,
        fieldNarrow = FIELD_NARROW,
        fieldWide = FIELD_WIDE,
    })

    local quickSetup = internal.createUIQuickSetup({
        ui = ui,
        def = def,
        profiles = profiles,
        staging = staging,
        runtime = runtime,
        getSnapshotHost = getSnapshotHost,
        drawColoredText = drawColoredText,
        colors = colors,
        theme = theme,
        getCurrentSnapshot = getCurrentSnapshot,
    })

    local moduleTabs = internal.createUIModuleTabs({
        ui = ui,
        staging = staging,
        runtime = runtime,
        getSnapshotHost = getSnapshotHost,
    })

    local dev = internal.createUIDev({
        ui = ui,
        config = config,
        lib = lib,
        colors = colors,
        discovery = discovery,
        staging = staging,
        drawColoredText = drawColoredText,
        resyncAllSessions = runtime.resyncAllSessions,
    })

    snapshotToStaging()

    local moduleByTabLabel = {}
    local cachedTabList = nil
    local cachedQuickList = nil
    local selectedTab = "Quick Setup"
    local _showModWindow = false
    local _didSeedWindowSize = false

    for _, entry in ipairs(discovery.modules) do
        moduleByTabLabel[entry._tabLabel] = entry
    end

    local function buildTabList()
        if cachedTabList then
            return cachedTabList
        end

        cachedTabList = { "Quick Setup" }
        cachedQuickList = {}

        for _, entry in ipairs(discovery.tabOrder) do
            table.insert(cachedTabList, entry._tabLabel)
        end

        for _, entry in ipairs(discovery.modulesWithQuickContent) do
            table.insert(cachedQuickList, entry)
        end

        table.insert(cachedTabList, "Profiles")
        table.insert(cachedTabList, "Dev")
        return cachedTabList
    end

    local function drawQuickSetup(snapshot)
        quickSetup.draw(cachedQuickList, snapshot)
    end

    local function drawProfiles()
        profiles.draw()
    end

    local function drawDev(snapshot)
        dev.draw(snapshot)
    end

    local function drawModuleTab(entry, snapshot)
        moduleTabs.draw(entry, snapshot)
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
            drawColoredText(colors.warning, "Mod is currently disabled. All changes have been reverted.")
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
            drawQuickSetup(snapshot)
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
        if _didSeedWindowSize then
            return
        end
        ui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        _didSeedWindowSize = true
    end

    local function renderWindow()
        hud.refreshHashIfIdle()
        if not _showModWindow then
            return
        end

        PushTheme()

        local beganWindow = false
        local openState = _showModWindow
        local ok, err = xpcall(function()
            seedWindowSize()
            local shouldDraw
            openState, shouldDraw = ui.Begin(windowTitle, _showModWindow)
            beganWindow = true
            if shouldDraw then
                drawMainWindow(captureSnapshot())
            end
        end, debug.traceback)

        if beganWindow then
            ui.End()
        end
        PopTheme()

        if openState == false then
            runtime.flushPendingRunData()
            hud.flushPendingHash()
            _showModWindow = false
        end

        if not ok then
            error(err)
        end
    end

    local function addMenuBar()
        if ui.MenuItem("Show Mod Menu") then
            if _showModWindow then
                runtime.flushPendingRunData()
                hud.flushPendingHash()
            end
            _showModWindow = not _showModWindow
        end
    end

    return {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
        flushPendingRunData = runtime.flushPendingRunData,
    }
end
