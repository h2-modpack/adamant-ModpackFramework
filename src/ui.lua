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

    local uiContext = {
        ui = ui,
        discovery = discovery,
        hud = hud,
        theme = theme,
        def = def,
        config = config,
        lib = lib,
        packId = packId,
        colors = colors,
        staging = staging,
        drawColoredText = drawColoredText,
        captureSnapshot = captureSnapshot,
        getSnapshotHost = getSnapshotHost,
        getCurrentSnapshot = getCurrentSnapshot,
        fieldMedium = FIELD_MEDIUM,
        fieldNarrow = FIELD_NARROW,
        fieldWide = FIELD_WIDE,
    }

    local function snapshotToStaging()
        staging.ModEnabled = config.ModEnabled == true
        local snapshot = captureSnapshot()

        for _, entry in ipairs(discovery.modules) do
            staging.modules[entry.id] = discovery.snapshot.isEntryEnabled(entry, snapshot)
            staging.debug[entry.id] = discovery.snapshot.isDebugEnabled(entry, snapshot)

            local host = getSnapshotHost(entry, snapshot)
            if host then
                host.reloadFromConfig()
            end
        end

        if uiContext.profiles then
            uiContext.profiles.snapshot()
        end
    end

    uiContext.snapshotToStaging = snapshotToStaging
    uiContext.onProfileLoaded = function()
        if uiContext.profiles then
            uiContext.profiles.markSlotLabelsDirty()
        end
    end

    local runtime = internal.createUIRuntime(uiContext)
    uiContext.runtime = runtime

    local profiles = internal.createUIProfiles(uiContext)
    uiContext.profiles = profiles

    local quickSetup = internal.createUIQuickSetup(uiContext)
    local moduleTabs = internal.createUIModuleTabs(uiContext)
    local dev = internal.createUIDev(uiContext)

    snapshotToStaging()

    local moduleByTabLabel = {}
    local cachedTabList = nil
    local cachedQuickList = nil
    local selectedTab = "Quick Setup"
    local _showModWindow = false

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
        ui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
    end

    local function renderWindow()
        if not _showModWindow then
            return
        end
        hud.setMarkerVisible(false)

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
            hud.setMarkerVisible(true)
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
                hud.setMarkerVisible(true)
            else
                hud.setMarkerVisible(false)
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
