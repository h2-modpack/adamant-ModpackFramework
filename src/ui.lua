-- =============================================================================
-- UI: Main window, sidebar, tab rendering
-- =============================================================================
-- Registration (add_imgui / add_to_menu_bar) is handled by the coordinator;
-- this factory only returns { renderWindow, addMenuBar }.

local internal = AdamantModpackFramework_Internal

--- Create the main ImGui UI subsystem for one coordinator pack.
--- @param discovery table Discovery object.
--- @param hud table HUD object.
--- @param theme table Theme object.
--- @param def table Coordinator definition table containing profile and layout metadata.
--- @param config table Coordinator config table.
--- @param lib table Adamant Modpack Lib export.
--- @param packId string Pack identifier used in warnings.
--- @param windowTitle string Window title shown in the mod menu.
--- @return table ui UI object exposing `{ renderWindow, addMenuBar }`.
function internal.createUI(discovery, hud, theme, def, config, lib, packId, windowTitle)
    local ui                 = rom.ImGui
    local DEFAULT_WINDOW_WIDTH = 1280
    local DEFAULT_WINDOW_HEIGHT = 840

    -- Unpack theme for convenient access
    local colors             = theme.colors

    local SIDEBAR_RATIO      = theme.SIDEBAR_RATIO
    local FIELD_MEDIUM       = theme.FIELD_MEDIUM
    local FIELD_NARROW       = theme.FIELD_NARROW
    local FIELD_WIDE         = theme.FIELD_WIDE
    local PushTheme          = theme.PushTheme
    local PopTheme           = theme.PopTheme
    local currentSnapshot    = nil

    local function CaptureSnapshot()
        return discovery.live.captureSnapshot()
    end

    local function GetSnapshotHost(entry, snapshot)
        return discovery.snapshot.getHost(entry, snapshot or currentSnapshot)
    end

    local function DrawColoredText(color, text)
        ui.TextColored(color[1], color[2], color[3], color[4], text)
    end
    -- =============================================================================
    -- STAGING TABLE (performance cache — avoids Chalk reads in render loop)
    -- =============================================================================
    -- Plain Lua tables mirroring each module's Chalk config.
    -- UI reads/writes go through staging. Chalk is only touched in event handlers.

    local staging = {
        ModEnabled = config.ModEnabled == true, -- snapshot once
        modules    = {},                        -- [module.id] = bool
        debug      = {},                        -- [module.id] = bool (DebugMode per entry)
    }

    local profiles = nil

    --- Snapshot all Chalk configs into staging (called at init and after profile load).
    local function SnapshotToStaging()
        local snapshot = CaptureSnapshot()
        staging.ModEnabled = config.ModEnabled == true

        -- Grouped modules
        for _, m in ipairs(discovery.modules) do
            staging.modules[m.id] = discovery.snapshot.isEntryEnabled(m, snapshot)
            staging.debug[m.id] = discovery.snapshot.isDebugEnabled(m, snapshot)
            local host = GetSnapshotHost(m, snapshot)
            if host then
                host.reloadFromConfig()
            end
        end
        if profiles then
            profiles.snapshot()
        end
    end

    -- Initialize staging from current configs
    SnapshotToStaging()

    local runtime = internal.createUIRuntime({
        discovery = discovery,
        hud = hud,
        config = config,
        lib = lib,
        packId = packId,
        colors = colors,
        staging = staging,
        captureSnapshot = CaptureSnapshot,
        getSnapshotHost = GetSnapshotHost,
        getCurrentSnapshot = function()
            return currentSnapshot
        end,
        snapshotToStaging = SnapshotToStaging,
        onProfileLoaded = function()
            if profiles then
                profiles.markSlotLabelsDirty()
            end
        end,
    })

    profiles = internal.createUIProfiles({
        ui = ui,
        config = config,
        def = def,
        colors = colors,
        drawColoredText = DrawColoredText,
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
        discovery = discovery,
        runtime = runtime,
        getSnapshotHost = GetSnapshotHost,
        drawColoredText = DrawColoredText,
        colors = colors,
        theme = theme,
        getCurrentSnapshot = function()
            return currentSnapshot
        end,
    })

    local moduleTabs = internal.createUIModuleTabs({
        ui = ui,
        staging = staging,
        runtime = runtime,
        getSnapshotHost = GetSnapshotHost,
    })

    -- =============================================================================
    -- SIDE TAB DEFINITIONS
    -- =============================================================================

    local selectedTab = "Quick Setup"

    local cachedTabList = nil
    local cachedQuickList = nil  -- ordered list of modules with DrawQuickContent

    local function BuildTabList()
        if cachedTabList then return cachedTabList end
        cachedTabList = { "Quick Setup" }
        cachedQuickList = {}
        local quickContentById = {}

        for _, entry in ipairs(discovery.modulesWithQuickContent or {}) do
            quickContentById[entry.id] = true
        end

        for _, entry in ipairs(discovery.tabOrder or {}) do
            table.insert(cachedTabList, entry._tabLabel)
            if quickContentById[entry.id] then
                table.insert(cachedQuickList, entry)
            end
        end

        table.insert(cachedTabList, "Profiles")
        table.insert(cachedTabList, "Dev")
        return cachedTabList
    end

    local dev = internal.createUIDev({
        ui = ui,
        config = config,
        lib = lib,
        colors = colors,
        discovery = discovery,
        staging = staging,
        drawColoredText = DrawColoredText,
        resyncAllSessions = runtime.resyncAllSessions,
    })

    local moduleByTabLabel = {}
    for _, entry in ipairs(discovery.modules) do
        moduleByTabLabel[entry._tabLabel] = entry
    end

    -- =============================================================================
    -- MAIN WINDOW
    -- =============================================================================

    local function DrawMainWindow(snapshot)
        -- Read from staging, not Chalk
        local val, chg = ui.Checkbox("Enable Mod", staging.ModEnabled)
        if chg then
            runtime.setPackRuntimeState(val, snapshot)
        end
        if ui.IsItemHovered() then ui.SetTooltip("Toggle the entire modpack on or off.") end

        if not staging.ModEnabled then
            ui.Separator()
            DrawColoredText(colors.warning, "Mod is currently disabled. All changes have been reverted.")
            return
        end

        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        local tabs = BuildTabList()
        local totalW = ui.GetWindowWidth()
        local sidebarW = totalW * SIDEBAR_RATIO

        -- Sidebar (proportional width, fill remaining height)
        ui.BeginChild("Sidebar", sidebarW, 0, true)
        for _, tabName in ipairs(tabs) do
            if ui.Selectable(tabName, selectedTab == tabName) then
                selectedTab = tabName
            end
        end
        ui.EndChild()

        ui.SameLine()

        -- Content panel (0 height = fill remaining space)
        ui.BeginChild("TabContent", 0, 0, true)
        ui.Spacing()

        if selectedTab == "Quick Setup" then
            quickSetup.draw(cachedQuickList, snapshot)
        elseif selectedTab == "Profiles" then
            profiles.draw()
        elseif selectedTab == "Dev" then
            dev.draw(snapshot)
        elseif moduleByTabLabel[selectedTab] then
            moduleTabs.draw(moduleByTabLabel[selectedTab], snapshot)
        end

        ui.EndChild()
    end

    -- =============================================================================
    -- RETURNED API
    -- =============================================================================

    local _showModWindow = false
    local _didSeedWindowSize = false

    local function SeedWindowSize()
        if _didSeedWindowSize then
            return
        end
        ui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        _didSeedWindowSize = true
    end

    local function renderWindow()
        hud.refreshHashIfIdle()
        if _showModWindow then
            PushTheme()
            SeedWindowSize()
            local open, shouldDraw = ui.Begin(windowTitle, _showModWindow)
            local renderOk = true
            local renderErr = nil
            if shouldDraw then
                local previousSnapshot = currentSnapshot
                currentSnapshot = CaptureSnapshot()
                local ok, err = xpcall(function()
                    DrawMainWindow(currentSnapshot)
                end, debug.traceback)
                currentSnapshot = previousSnapshot
                renderOk = ok
                renderErr = err
            end
            ui.End()
            if open == false then
                runtime.flushPendingRunData()
                hud.flushPendingHash()
                _showModWindow = false
            end
            PopTheme()
            if renderOk == false then
                error(renderErr)
            end
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
