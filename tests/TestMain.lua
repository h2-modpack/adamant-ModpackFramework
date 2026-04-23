local lu = require('luaunit')

TestMain = {}

function TestMain:testGetRendererIsSafeBeforeInit()
    local render = public.getRenderer("missing-pack")
    lu.assertTrue(pcall(render))
end

function TestMain:testGetMenuBarIsSafeBeforeInit()
    local addMenuBar = public.getMenuBar("missing-pack")
    lu.assertTrue(pcall(addMenuBar))
end

function TestMain:testMasterToggleRollsBackTouchedRuntimeStateOnFailure()
    CaptureWarnings()

    local previousSetupRunData = SetupRunData
    local setupRunDataCalls = 0
    SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local previousImGui = rom.ImGui
    local masterCheckboxPass = 1
    local secondPassCurrent = nil

    local function noop() end

    rom.ImGui = {
        Begin = function() return true, true end,
        End = noop,
        SetNextWindowSize = noop,
        MenuItem = function() return true end,
        Checkbox = function(label, current)
            if label == "Enable Mod" then
                if masterCheckboxPass == 1 then
                    masterCheckboxPass = 2
                    return true, true
                end
                secondPassCurrent = current
                return current, false
            end
            return current, false
        end,
        IsItemHovered = function() return false end,
        SetTooltip = noop,
        Separator = noop,
        SameLine = noop,
        Spacing = noop,
        TextColored = noop,
        GetWindowWidth = function() return 1000 end,
        BeginChild = function() return true end,
        EndChild = noop,
        Selectable = function() return false end,
        BeginCombo = function() return false end,
        EndCombo = noop,
        PushItemWidth = noop,
        PopItemWidth = noop,
        Text = noop,
        TextColored = noop,
        GetCursorPosX = function() return 0 end,
        GetCursorPosY = function() return 0 end,
        SetCursorPos = noop,
        SetCursorPosX = noop,
        GetFrameHeight = function() return 20 end,
        GetFrameHeightWithSpacing = function() return 24 end,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemSpacing = { x = 8, y = 4 },
            }
        end,
        CalcTextSize = function(text) return #(tostring(text or "")) * 8 end,
        Button = function() return false end,
        InputText = function(_, value) return value, false end,
        GetClipboardText = function() return nil end,
        SetClipboardText = noop,
        CollapsingHeader = function() return false end,
        Indent = noop,
        Unindent = noop,
        PushID = noop,
        PopID = noop,
        PushStyleColor = noop,
        PopStyleColor = noop,
    }

    local firstState = { applied = 0, reverted = 0 }
    local secondState = { applied = 0, reverted = 0 }

    local discovery = MockDiscovery.create({
        {
            modName = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {},
            apply = function()
                firstState.applied = firstState.applied + 1
            end,
            revert = function()
                firstState.reverted = firstState.reverted + 1
            end,
        },
        {
            modName = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = true,
            storage = {},
            apply = function()
                secondState.applied = secondState.applied + 1
                error("apply boom")
            end,
            revert = function()
                secondState.reverted = secondState.reverted + 1
            end,
        },
    })

    local hudMarkers = {}
    local hud = {
        setModMarker = function(val)
            table.insert(hudMarkers, val)
        end,
        markHashDirty = noop,
        refreshHashIfIdle = noop,
        flushPendingHash = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = Framework.createTheme(lib)
    local def = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local config = {
        ModEnabled = false,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local builtUi = Framework.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
    builtUi.addMenuBar()

    local okFirst, errFirst = pcall(builtUi.renderWindow)
    local okSecond, errSecond = pcall(builtUi.renderWindow)
    local warnings = Warnings

    rom.ImGui = previousImGui
    SetupRunData = previousSetupRunData
    RestoreWarnings()

    lu.assertTrue(okFirst, tostring(errFirst))
    lu.assertTrue(okSecond, tostring(errSecond))
    lu.assertFalse(config.ModEnabled)
    lu.assertEquals(secondPassCurrent, false)
    lu.assertEquals(setupRunDataCalls, 0)
    lu.assertEquals(#hudMarkers, 0)
    lu.assertEquals(firstState.applied, 1)
    lu.assertEquals(firstState.reverted, 1)
    lu.assertEquals(secondState.applied, 1)
    lu.assertEquals(secondState.reverted, 0)
    lu.assertEquals(#warnings, 2)
    lu.assertStrContains(warnings[1], "[test-pack] Bravo apply failed: ")
    lu.assertStrContains(warnings[2], "[test-pack] Enable Mod toggle failed; restoring previous runtime state")
end

function TestMain:testQuickSetupRendersModuleQuickContent()
    local previousImGui = rom.ImGui
    local checkboxLabels = {}

    local function noop() end

    rom.ImGui = {
        Begin = function() return true, true end,
        End = noop,
        SetNextWindowSize = noop,
        MenuItem = function() return true end,
        Checkbox = function(label, current)
            table.insert(checkboxLabels, label)
            return current, false
        end,
        IsItemHovered = function() return false end,
        SetTooltip = noop,
        Separator = noop,
        SameLine = noop,
        Spacing = noop,
        TextColored = noop,
        GetWindowWidth = function() return 1000 end,
        BeginChild = function() return true end,
        EndChild = noop,
        Selectable = function() return false end,
        BeginCombo = function() return false end,
        EndCombo = noop,
        PushItemWidth = noop,
        PopItemWidth = noop,
        Text = noop,
        TextColored = noop,
        GetCursorPosX = function() return 0 end,
        GetCursorPosY = function() return 0 end,
        SetCursorPos = noop,
        SetCursorPosX = noop,
        GetFrameHeight = function() return 20 end,
        GetFrameHeightWithSpacing = function() return 24 end,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemSpacing = { x = 8, y = 4 },
            }
        end,
        CalcTextSize = function(text) return #(tostring(text or "")) * 8 end,
        Button = function() return false end,
        InputText = function(_, value) return value, false end,
        GetClipboardText = function() return nil end,
        SetClipboardText = noop,
        CollapsingHeader = function() return false end,
        Indent = noop,
        Unindent = noop,
        PushID = noop,
        PopID = noop,
        PushStyleColor = noop,
        PopStyleColor = noop,
    }

    local discovery = MockDiscovery.create({
        {
            modName = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {
                { type = "bool", alias = "FlagA", configKey = "FlagA", default = false },
            },
            DrawTab = function() end,
            DrawQuickContent = function(ui)
                ui.Checkbox("Quick B", false)
            end,
            apply = function() end,
            revert = function() end,
        },
    })

    local hud = {
        setModMarker = noop,
        markHashDirty = noop,
        refreshHashIfIdle = noop,
        flushPendingHash = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = Framework.createTheme(lib)
    local def = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local builtUi = Framework.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)

    rom.ImGui = previousImGui

    lu.assertTrue(ok, tostring(err))
    local joined = table.concat(checkboxLabels, "\n")
    lu.assertStrContains(joined, "Enable Mod")
    lu.assertStrContains(joined, "Quick B")
end

function TestMain:testQuickSetupUsesLatestLiveHostForQuickContent()
    local previousImGui = rom.ImGui
    local firstQuickRenders = 0
    local secondQuickRenders = 0

    local function noop() end

    rom.ImGui = {
        Begin = function() return true, true end,
        End = noop,
        SetNextWindowSize = noop,
        MenuItem = function() return true end,
        Checkbox = function(_, current) return current, false end,
        IsItemHovered = function() return false end,
        SetTooltip = noop,
        Separator = noop,
        SameLine = noop,
        Spacing = noop,
        TextColored = noop,
        GetWindowWidth = function() return 1000 end,
        BeginChild = function() return true end,
        EndChild = noop,
        Selectable = function() return false end,
        BeginCombo = function() return false end,
        EndCombo = noop,
        PushItemWidth = noop,
        PopItemWidth = noop,
        Text = noop,
        GetCursorPosX = function() return 0 end,
        GetCursorPosY = function() return 0 end,
        SetCursorPos = noop,
        SetCursorPosX = noop,
        GetFrameHeight = function() return 20 end,
        GetFrameHeightWithSpacing = function() return 24 end,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemSpacing = { x = 8, y = 4 },
            }
        end,
        CalcTextSize = function(text) return #(tostring(text or "")) * 8 end,
        Button = function() return false end,
        InputText = function(_, value) return value, false end,
        GetClipboardText = function() return nil end,
        SetClipboardText = noop,
        CollapsingHeader = function() return false end,
        Indent = noop,
        Unindent = noop,
        PushID = noop,
        PopID = noop,
        PushStyleColor = noop,
        PopStyleColor = noop,
    }

    local discovery = MockDiscovery.create({
        {
            modName = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {
                { type = "bool", alias = "FlagA", configKey = "FlagA", default = false },
            },
            DrawTab = function() end,
            DrawQuickContent = function()
                firstQuickRenders = firstQuickRenders + 1
            end,
            apply = function() end,
            revert = function() end,
        },
    })

    local hud = {
        setModMarker = noop,
        markHashDirty = noop,
        refreshHashIfIdle = noop,
        flushPendingHash = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = Framework.createTheme(lib)
    local def = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local builtUi = Framework.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
    builtUi.addMenuBar()
    local okFirst, errFirst = pcall(builtUi.renderWindow)

    local entry = discovery.modules[1]
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
        FlagA = false,
    }, entry.definition)
    local replacementHost = lib.createModuleHost({
        definition = entry.definition,
        store = store,
        session = session,
        drawTab = function() end,
        drawQuickContent = function()
            secondQuickRenders = secondQuickRenders + 1
        end,
    })
    rom.mods[entry.modName].host = replacementHost

    local okSecond, errSecond = pcall(builtUi.renderWindow)

    rom.ImGui = previousImGui

    lu.assertTrue(okFirst, tostring(errFirst))
    lu.assertTrue(okSecond, tostring(errSecond))
    lu.assertEquals(firstQuickRenders, 1)
    lu.assertEquals(secondQuickRenders, 1)
end

function TestMain:testAlwaysDrawRendererFlushesPendingHashWhenHostGuiDisappears()
    local previousGui = rom.gui
    local guiOpen = true
    local flushCalls = 0
    local runDataFlushCalls = 0

    rom.gui = {
        is_open = function()
            return guiOpen
        end,
    }

    local packId = "flush-pack"
    local alwaysDraw = public.getAlwaysDrawRenderer(packId)

    local capturedPacks = AdamantModpackFramework_Internal.packs
    local previousPack = capturedPacks and capturedPacks[packId] or nil
    capturedPacks[packId] = {
        ui = {
            flushPendingRunData = function()
                runDataFlushCalls = runDataFlushCalls + 1
            end,
        },
        hud = {
            flushPendingHash = function()
                flushCalls = flushCalls + 1
            end,
        },
    }

    alwaysDraw()
    guiOpen = false
    alwaysDraw()
    alwaysDraw()

    rom.gui = previousGui
    capturedPacks[packId] = previousPack

    lu.assertEquals(flushCalls, 1)
    lu.assertEquals(runDataFlushCalls, 1)
end

function TestMain:testDisablingRunDataModuleFlushesSetupRunDataWhenMenuCloses()
    local previousImGui = rom.ImGui
    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    local quickSetupRan = false
    local revertCalls = 0

    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local function noop() end

    rom.ImGui = {
        Begin = function() return true, true end,
        End = noop,
        SetNextWindowSize = noop,
        MenuItem = function() return true end,
        Checkbox = function(_, current) return current, false end,
        IsItemHovered = function() return false end,
        SetTooltip = noop,
        Separator = noop,
        SameLine = noop,
        Spacing = noop,
        TextColored = noop,
        GetWindowWidth = function() return 1000 end,
        BeginChild = function() return true end,
        EndChild = noop,
        Selectable = function() return false end,
        BeginCombo = function() return false end,
        EndCombo = noop,
        PushItemWidth = noop,
        PopItemWidth = noop,
        Text = noop,
        GetCursorPosX = function() return 0 end,
        GetCursorPosY = function() return 0 end,
        SetCursorPos = noop,
        SetCursorPosX = noop,
        GetFrameHeight = function() return 20 end,
        GetFrameHeightWithSpacing = function() return 24 end,
        GetStyle = function()
            return {
                FramePadding = { x = 4, y = 3 },
                ItemSpacing = { x = 8, y = 4 },
            }
        end,
        CalcTextSize = function(text) return #(tostring(text or "")) * 8 end,
        Button = function() return false end,
        InputText = function(_, value) return value, false end,
        GetClipboardText = function() return nil end,
        SetClipboardText = noop,
        CollapsingHeader = function() return false end,
        Indent = noop,
        Unindent = noop,
        PushID = noop,
        PopID = noop,
        PushStyleColor = noop,
        PopStyleColor = noop,
    }

    local discovery = MockDiscovery.create({
        {
            modName = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            affectsRunData = true,
            storage = {},
            apply = function() end,
            revert = function()
                revertCalls = revertCalls + 1
            end,
            DrawTab = function() end,
        },
    })

    local hud = {
        setModMarker = noop,
        markHashDirty = noop,
        refreshHashIfIdle = noop,
        flushPendingHash = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = Framework.createTheme(lib)
    local def = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
        renderQuickSetup = function(ctx)
            if not quickSetupRan then
                quickSetupRan = true
                ctx.setModulesEnabled({ "Alpha" }, false)
            end
        end,
    }
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local builtUi = Framework.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)
    builtUi.addMenuBar()

    rom.ImGui = previousImGui
    rom.game.SetupRunData = previousSetupRunData

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(quickSetupRan)
    lu.assertEquals(revertCalls, 1)
    lu.assertEquals(setupRunDataCalls, 1)
end

function TestMain:testRendererRebuildsWhenFrameworkGenerationChanges()
    local previousCreateDiscovery = Framework.createDiscovery
    local previousCreateHash = Framework.createHash
    local previousCreateTheme = Framework.createTheme
    local previousCreateHud = Framework.createHud
    local previousCreateUI = Framework.createUI

    local packId = "generation-pack"
    local initCount = 0
    local renderCount = 0
    local previousGeneration = AdamantModpackFramework_Internal.frameworkGeneration

    Framework.createDiscovery = function()
        return {
            modules = {},
            run = function() end,
            captureHostSnapshot = function()
                return { hosts = {} }
            end,
            getSnapshotHost = function()
                return nil
            end,
        }
    end

    Framework.createHash = function()
        return {}
    end

    Framework.createTheme = function()
        return { colors = {} }
    end

    Framework.createHud = function()
        return {
            setModMarker = function() end,
        }
    end

    Framework.createUI = function()
        initCount = initCount + 1
        local currentInit = initCount
        return {
            renderWindow = function()
                renderCount = renderCount + currentInit
            end,
            addMenuBar = function() end,
        }
    end

    Framework.init({
        packId = packId,
        windowTitle = "Registry Pack",
        config = {
            ModEnabled = true,
            DebugMode = false,
            Profiles = {
                { Name = "", Hash = "", Tooltip = "" },
            },
        },
        def = {
            NUM_PROFILES = 1,
            defaultProfiles = {},
        },
    })

    local render = public.getRenderer(packId)
    render()
    AdamantModpackFramework_Internal.frameworkGeneration = previousGeneration + 1
    render()

    Framework.createDiscovery = previousCreateDiscovery
    Framework.createHash = previousCreateHash
    Framework.createTheme = previousCreateTheme
    Framework.createHud = previousCreateHud
    Framework.createUI = previousCreateUI
    AdamantModpackFramework_Internal.frameworkGeneration = previousGeneration

    lu.assertEquals(initCount, 2)
    lu.assertEquals(renderCount, 3)
end
