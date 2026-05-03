import "ui/runtime.lua"
import "ui/profiles.lua"
import "ui/dev.lua"
import "ui/quick_setup.lua"
import "ui/module_tabs.lua"

function Framework.createUI(discovery, hud, theme, config, packId, windowTitle, numProfiles,
                            defaultProfiles, renderQuickSetup)
    local internal = AdamantModpackFramework_Internal
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

    local snapshots = {
        current = nil,
    }

    function snapshots.capture()
        snapshots.current = discovery.live.captureSnapshot()
        return snapshots.current
    end

    function snapshots.get()
        return snapshots.current
    end

    function snapshots.getHost(entry, snapshot)
        return discovery.snapshot.getHost(entry, snapshot or snapshots.current)
    end

    local profiles

    local function snapshotToStaging()
        staging.ModEnabled = config.ModEnabled == true
        local snapshot = snapshots.capture()

        for _, entry in ipairs(discovery.modules) do
            staging.modules[entry.id] = discovery.snapshot.isEntryEnabled(entry, snapshot)
            staging.debug[entry.id] = discovery.snapshot.isDebugEnabled(entry, snapshot)

            local host = snapshots.getHost(entry, snapshot)
            if host then
                host.reloadFromConfig()
            end
        end

        if profiles then
            profiles.snapshot()
        end
    end

    local runtime = internal.createUIRuntime({
        discovery = discovery,
        hud = hud,
        config = config,
        packId = packId,
        colors = colors,
        staging = staging,
        snapshots = snapshots,
        snapshotToStaging = snapshotToStaging,
        onProfileLoaded = function()
            if profiles then
                profiles.markSlotLabelsDirty()
            end
        end,
    })

    profiles = internal.createUIProfiles({
        config = config,
        colors = colors,
        numProfiles = numProfiles,
        defaultProfiles = defaultProfiles,
        packId = packId,
        discovery = discovery,
        runtime = runtime,
    })

    local quickSetup = internal.createUIQuickSetup({
        renderQuickSetup = renderQuickSetup,
        theme = theme,
        profiles = profiles,
        staging = staging,
        runtime = runtime,
        snapshots = snapshots,
        colors = colors,
    })

    local moduleTabs = internal.createUIModuleTabs({
        staging = staging,
        runtime = runtime,
        snapshots = snapshots,
    })

    local dev = internal.createUIDev({
        config = config,
        colors = colors,
        discovery = discovery,
        staging = staging,
        runtime = runtime,
    })

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
            lib.imguiHelpers.textColored(ui, colors.warning, "Mod is currently disabled. All changes have been reverted.")
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

    local function flushPending()
        runtime.flushPendingRunData()
        hud.flushPendingHash()
    end

    local function handleHostGuiClosed()
        flushPending()
        hud.setMarkerVisible(true)
    end

    local function closeWindow()
        flushPending()
        hud.setMarkerVisible(true)
        _showModWindow = false
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
                drawMainWindow(snapshots.capture())
            end
        end, debug.traceback)

        if beganWindow then
            ui.End()
        end
        PopTheme()

        if openState == false then
            closeWindow()
        end

        if not ok then
            error(err)
        end
    end

    local function addMenuBar()
        if ui.MenuItem("Show Mod Menu") then
            if _showModWindow then
                closeWindow()
            else
                hud.setMarkerVisible(false)
                _showModWindow = true
            end
        end
    end

    return {
        renderWindow = renderWindow,
        addMenuBar = addMenuBar,
        flushPending = flushPending,
        handleHostGuiClosed = handleHostGuiClosed,
    }
end
