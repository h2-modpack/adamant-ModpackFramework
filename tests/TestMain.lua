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

function TestMain:testRenderWindowCleansUpImguiStacksBeforeRethrow()
    local previousImGui = rom.ImGui
    local endCalls = 0
    local popStyleCalls = 0

    local function noop() end

    rom.ImGui = {
        Begin = function() return true, true end,
        End = function()
            endCalls = endCalls + 1
        end,
        SetNextWindowSize = noop,
        MenuItem = function() return true end,
        Checkbox = function()
            error("draw boom")
        end,
        PushStyleColor = noop,
        PopStyleColor = function()
            popStyleCalls = popStyleCalls + 1
        end,
    }

    local discovery = {
        modules = {},
        modulesWithQuickContent = {},
        tabOrder = {},
        live = {
            captureSnapshot = function()
                return { hosts = {} }
            end,
        },
        snapshot = {
            getHost = function()
                return nil
            end,
        },
    }
    local hud = {
        flushPendingHash = noop,
        setMarkerVisible = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
        markHashDirty = noop,
    }
    local theme = FrameworkTestApi.createTheme(lib)
    local builtUi = FrameworkTestApi.createUI(discovery, hud, theme, {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, lib, "test-pack", "Test Window")

    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)

    rom.ImGui = previousImGui

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "draw boom")
    lu.assertEquals(endCalls, 1)
    lu.assertEquals(popStyleCalls, 1)
end

function TestMain:testInitBatchesRunDataSetupAfterCoordinatedStartupSync()
    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0

    local entry = {
        id = "Alpha",
        name = "Alpha",
        modName = "Alpha",
        storage = {},
        affectsRunData = true,
        definition = {
            id = "Alpha",
            name = "Alpha",
            affectsRunData = true,
        },
    }
    local host = {
        applyOnLoad = function()
            return true
        end,
    }

    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    FrameworkTestApi.withFactories({
        createDiscovery = function()
            return {
                modules = { entry },
                run = function() end,
                live = {
                    captureSnapshot = function()
                        return { hosts = { [entry] = host } }
                    end,
                },
                snapshot = {
                    getHost = function(_, snapshot)
                        return snapshot.hosts[entry]
                    end,
                },
            }
        end,
        createHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function()
            return {
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            return {
                renderWindow = function() end,
                addMenuBar = function() end,
            }
        end,
    }, function()
        FrameworkTestApi.init({
            packId = "startup-pack",
            windowTitle = "Startup Pack",
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
    end)

    rom.game.SetupRunData = previousSetupRunData

    lu.assertEquals(setupRunDataCalls, 1)
end

function TestMain:testModuleLoadedBeforeCoordinatorIsAppliedByFrameworkInit()
    local packId = "load-order-pack"
    lib.lifecycle.registerCoordinator(packId, nil)

    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    local applyCalls = 0
    local revertCalls = 0

    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local definition = lib.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
        affectsRunData = true,
        apply = function()
            applyCalls = applyCalls + 1
        end,
        revert = function()
            revertCalls = revertCalls + 1
        end,
    })
    local store, session = lib.createStore({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = lib.createModuleHost({
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertEquals(applyCalls, 0)
    lib.lifecycle.registerCoordinator(packId, {
        ModEnabled = true,
    })

    local entry = {
        id = definition.id,
        name = definition.name,
        modName = "Alpha",
        storage = definition.storage,
        affectsRunData = true,
        definition = definition,
    }

    FrameworkTestApi.withFactories({
        createDiscovery = function()
            return {
                modules = { entry },
                run = function() end,
                live = {
                    captureSnapshot = function()
                        return { hosts = { [entry] = host } }
                    end,
                },
                snapshot = {
                    getHost = function(_, snapshot)
                        return snapshot.hosts[entry]
                    end,
                },
            }
        end,
        createHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function()
            return {
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            return {
                renderWindow = function() end,
                addMenuBar = function() end,
            }
        end,
    }, function()
        FrameworkTestApi.init({
            packId = packId,
            windowTitle = "Load Order Pack",
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
    end)

    local ok, err = host.revertMutation()
    lib.lifecycle.registerCoordinator(packId, nil)
    rom.game.SetupRunData = previousSetupRunData

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(applyCalls, 1)
    lu.assertEquals(revertCalls, 1)
    lu.assertEquals(setupRunDataCalls, 1)
end

function TestMain:testInitStartupLifecycleWarningUsesPackPrefix()
    CaptureWarnings()

    local entry = {
        id = "Alpha",
        name = "Alpha",
        modName = "Alpha",
        storage = {},
        definition = {
            id = "Alpha",
            name = "Alpha",
        },
    }
    local host = {
        applyOnLoad = function()
            return false, "startup boom"
        end,
    }

    FrameworkTestApi.withFactories({
        createDiscovery = function()
            return {
                modules = { entry },
                run = function() end,
                live = {
                    captureSnapshot = function()
                        return { hosts = { [entry] = host } }
                    end,
                },
                snapshot = {
                    getHost = function(_, snapshot)
                        return snapshot.hosts[entry]
                    end,
                },
            }
        end,
        createHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function()
            return {
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            return {
                renderWindow = function() end,
                addMenuBar = function() end,
            }
        end,
    }, function()
        FrameworkTestApi.init({
            packId = "startup-pack",
            windowTitle = "Startup Pack",
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
    end)

    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(#warnings, 1)
    lu.assertEquals(warnings[1], "[startup-pack] Alpha startup lifecycle failed: startup boom")
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
        flushPendingHash = noop,
        setMarkerVisible = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = FrameworkTestApi.createTheme(lib)
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

    local builtUi = FrameworkTestApi.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
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

function TestMain:testModuleBatchToggleRollsBackTouchedModulesOnFailure()
    CaptureWarnings()

    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local firstState = { applied = 0, reverted = 0 }
    local secondState = { applied = 0, reverted = 0 }

    local discovery = MockDiscovery.create({
        {
            modName = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            affectsRunData = true,
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
            affectsRunData = true,
            storage = {},
            apply = function()
                secondState.applied = secondState.applied + 1
            end,
            revert = function()
                secondState.reverted = secondState.reverted + 1
                error("revert boom")
            end,
        },
    })

    local markHashDirtyCalls = 0
    local hud = {
        markHashDirty = function()
            markHashDirtyCalls = markHashDirtyCalls + 1
        end,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        setMarkerVisible = noop,
    }
    local staging = {
        ModEnabled = true,
        modules = {
            Alpha = true,
            Bravo = true,
        },
        debug = {},
    }
    local runtime = AdamantModpackFramework_Internal.createUIRuntime({
        discovery = discovery,
        hud = hud,
        config = {
            ModEnabled = true,
            DebugMode = false,
        },
        lib = lib,
        packId = "test-pack",
        colors = {},
        staging = staging,
        captureSnapshot = function()
            return discovery.live.captureSnapshot()
        end,
        getSnapshotHost = function(entry, snapshot)
            return discovery.snapshot.getHost(entry, snapshot)
        end,
        getCurrentSnapshot = function()
            return nil
        end,
        snapshotToStaging = function() end,
    })

    local snapshot = discovery.live.captureSnapshot()
    local ok, err = runtime.setModulesEnabled({ "Alpha", "Bravo" }, false, snapshot)
    runtime.flushPendingRunData()

    local warnings = Warnings
    rom.game.SetupRunData = previousSetupRunData
    RestoreWarnings()

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "revert boom")
    lu.assertTrue(staging.modules.Alpha)
    lu.assertTrue(staging.modules.Bravo)
    lu.assertTrue(discovery.snapshot.isEntryEnabled(discovery.modulesById.Alpha, snapshot))
    lu.assertTrue(discovery.snapshot.isEntryEnabled(discovery.modulesById.Bravo, snapshot))
    lu.assertEquals(firstState.reverted, 1)
    lu.assertEquals(firstState.applied, 1)
    lu.assertEquals(secondState.reverted, 1)
    lu.assertEquals(secondState.applied, 0)
    lu.assertEquals(markHashDirtyCalls, 0)
    lu.assertEquals(setupRunDataCalls, 0)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "[test-pack] Module batch toggle failed; restoring previous module states: ")
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
        flushPendingHash = noop,
        setMarkerVisible = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = FrameworkTestApi.createTheme(lib)
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

    local builtUi = FrameworkTestApi.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
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
        flushPendingHash = noop,
        setMarkerVisible = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = FrameworkTestApi.createTheme(lib)
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

    local builtUi = FrameworkTestApi.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
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
            setMarkerVisible = function() end,
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
        flushPendingHash = noop,
        setMarkerVisible = noop,
        updateHash = noop,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
    }

    local theme = FrameworkTestApi.createTheme(lib)
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

    local builtUi = FrameworkTestApi.createUI(discovery, hud, theme, def, config, lib, "test-pack", "Test Window")
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

