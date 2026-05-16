local lu = require('luaunit')

TestMain = {}

function TestMain:setUp()
    local overlayState = AdamantModpackLib_Internal.overlays
    self.previousUiSuppressors = overlayState.uiSuppressors
    self.previousNextUiSuppressorId = overlayState.nextUiSuppressorId
    overlayState.uiSuppressors = {}
    overlayState.nextUiSuppressorId = 0
end

function TestMain:tearDown()
    local overlayState = AdamantModpackLib_Internal.overlays
    overlayState.uiSuppressors = self.previousUiSuppressors
    overlayState.nextUiSuppressorId = self.previousNextUiSuppressorId
end

function TestMain:testCreateGuiCallbacksAreSafeBeforeInit()
    local callbacks = public.createGuiCallbacks("missing-pack")
    local renderOk = pcall(callbacks.render)
    local alwaysDrawOk = pcall(callbacks.alwaysDraw)
    local menuBarOk = pcall(callbacks.menuBar)

    lu.assertTrue(renderOk)
    lu.assertTrue(alwaysDrawOk)
    lu.assertTrue(menuBarOk)
end

function TestMain:testCreateHudRegistersFrameworkHashOverlay()
    local previousScreenData = ScreenData
    local previousDefineOwned = lib.overlays.defineOwned
    local previousDispatchCommit = AdamantModpackLib_Internal.overlays.dispatchCommit
    local registeredOwner = nil
    local registeredLine = nil
    local projectedValue = nil
    local registeredOpts = nil
    local refreshCalls = 0

    ScreenData = {
        HUD = {
            ComponentData = {},
        },
    }

    lib.overlays.defineOwned = function(owner, register)
        registeredOwner = owner
        local registrar = {
            createLine = function(name, spec)
                registeredLine = name
                registeredOpts = spec
            end,
            onCommit = function(callback)
                registeredOpts._commit = callback
            end,
        }
        register(registrar)
        registeredOpts._commit({
            setLine = function(_, value)
                projectedValue = value
            end,
            refresh = function()
                refreshCalls = refreshCalls + 1
            end,
        }, {})
        return true
    end
    AdamantModpackLib_Internal.overlays.dispatchCommit = function()
        registeredOpts._commit({
            setLine = function(_, value)
                projectedValue = value
            end,
            refresh = function()
                refreshCalls = refreshCalls + 1
            end,
        }, {})
    end

    local theme = FrameworkTestApi.createTheme()
    local config = { ModEnabled = true }
    local hash = {
        GetConfigHash = function()
            return "hash", "fingerprint"
        end,
        ApplyConfigHash = function()
            return true
        end,
    }

    local hud = FrameworkTestApi.createHud("test-pack", 1, hash, theme, config, false)
    hud.setModMarker(false)

    ScreenData = previousScreenData
    lib.overlays.defineOwned = previousDefineOwned
    AdamantModpackLib_Internal.overlays.dispatchCommit = previousDispatchCommit

    lu.assertEquals(registeredOwner, "adamant-framework.test-pack.hud")
    lu.assertEquals(registeredLine, "hash")
    lu.assertEquals(registeredOpts.region, "middleRightStack")
    lu.assertEquals(registeredOpts.order, lib.overlays.order.framework + 1)
    lu.assertEquals(projectedValue, "")
    lu.assertFalse(registeredOpts.visible())
    lu.assertEquals(refreshCalls, 2)
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

    local moduleRegistry = {
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
    local theme = FrameworkTestApi.createTheme()
    local builtUi = FrameworkTestApi.createUI(moduleRegistry, hud, theme, {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, "test-pack", "Test Window", 1, {
        { Name = "", Hash = "", Tooltip = "" },
    })

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
        pluginGuid = "Alpha",
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
    lib.coordinator.register("startup-pack", { ModEnabled = true })

    FrameworkTestApi.withBootConstructors({
        createModuleRegistry = function()
            return {
                modules = { entry },
                refresh = function() end,
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
        createConfigHash = function()
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
        FrameworkTestApi.init(
            "startup-pack",
            "Startup Pack",
            {
                ModEnabled = true,
                DebugMode = false,
                Profiles = {
                    { Name = "", Hash = "", Tooltip = "" },
                },
            },
            1,
            {}
        )
    end)

    lib.coordinator.register("startup-pack", nil)
    rom.game.SetupRunData = previousSetupRunData

    lu.assertEquals(setupRunDataCalls, 1)
end

function TestMain:testModuleLoadedBeforeCoordinatorIsAppliedByFrameworkInit()
    local packId = "load-order-pack"
    lib.coordinator.register(packId, nil)

    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    local buildCalls = 0
    local target = { Value = "base" }

    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = "test-pack.Alpha",
        definition = definition,
        store = store,
        session = session,
        registerPatchMutation = function(plan)
            buildCalls = buildCalls + 1
            plan:set(target, "Value", "patched")
        end,
        drawTab = function() end,
    })
    authorHost.tryActivate()

    lu.assertEquals(buildCalls, 0)
    lib.coordinator.register(packId, {
        ModEnabled = true,
    })

    local entry = {
        id = definition.id,
        name = definition.name,
        pluginGuid = "Alpha",
        storage = definition.storage,
        affectsRunData = true,
        definition = definition,
    }

    FrameworkTestApi.withBootConstructors({
        createModuleRegistry = function()
            return {
                modules = { entry },
                refresh = function() end,
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
        createConfigHash = function()
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
        FrameworkTestApi.init(
            packId,
            "Load Order Pack",
            {
                ModEnabled = true,
                DebugMode = false,
                Profiles = {
                    { Name = "", Hash = "", Tooltip = "" },
                },
            },
            1,
            {}
        )
    end)

    local ok, err = host.revertMutation()
    lib.coordinator.register(packId, nil)
    rom.game.SetupRunData = previousSetupRunData

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "base")
    lu.assertEquals(setupRunDataCalls, 1)
end

function TestMain:testRepeatedInitReplacesPackStateAndKeepsStablePackIndex()
    local packId = "reinit-pack"
    local packRegistry = FrameworkPackRegistry
    local previousPack = packRegistry.packs[packId]
    local previousPackList = {}
    for i, value in ipairs(packRegistry.packList) do
        previousPackList[i] = value
    end

    local hudIndexes = {}
    local firstPack
    local secondPack

    lib.coordinator.register(packId, {
        ModEnabled = true,
    })

    FrameworkTestApi.withBootConstructors({
        createModuleRegistry = function()
            return {
                modules = {},
                refresh = function() end,
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
        end,
        createConfigHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function(_, packIndex)
            table.insert(hudIndexes, packIndex)
            return {
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            return {
                renderWindow = function() end,
                addMenuBar = function() end,
                flushPending = function() end,
            }
        end,
    }, function()
        local config = {
            ModEnabled = true,
            DebugMode = false,
            Profiles = {
                { Name = "", Hash = "", Tooltip = "" },
            },
        }
        firstPack = FrameworkTestApi.init(packId, "Reinit Pack", config, 1, {})
        secondPack = FrameworkTestApi.init(packId, "Reinit Pack", config, 1, {})
    end)

    local packIdCount = 0
    for _, value in ipairs(packRegistry.packList) do
        if value == packId then
            packIdCount = packIdCount + 1
        end
    end
    local activePack = packRegistry.packs[packId]

    packRegistry.packs[packId] = previousPack
    packRegistry.packList = previousPackList
    lib.coordinator.register(packId, nil)

    lu.assertTrue(firstPack ~= secondPack)
    lu.assertEquals(activePack, secondPack)
    lu.assertEquals(#hudIndexes, 2)
    lu.assertEquals(hudIndexes[1], hudIndexes[2])
    lu.assertEquals(firstPack._index, secondPack._index)
    lu.assertEquals(packIdCount, 1)
end

function TestMain:testFailedInitDoesNotRegisterPack()
    local packId = "failed-init-pack"
    local packRegistry = FrameworkPackRegistry
    local previousPack = packRegistry.packs[packId]
    local previousPackList = {}
    for i, value in ipairs(packRegistry.packList) do
        previousPackList[i] = value
    end

    lib.coordinator.register(packId, {
        ModEnabled = true,
    })

    FrameworkTestApi.withBootConstructors({
        createModuleRegistry = function()
            return {
                modules = {},
                refresh = function() end,
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
        end,
        createConfigHash = function()
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
            error("ui construction boom")
        end,
    }, function()
        local config = {
            ModEnabled = true,
            DebugMode = false,
            Profiles = {
                { Name = "", Hash = "", Tooltip = "" },
            },
        }
        lu.assertErrorMsgContains("ui construction boom", function()
            FrameworkTestApi.init(packId, "Failed Init Pack", config, 1, {})
        end)
    end)

    local packIdCount = 0
    for _, value in ipairs(packRegistry.packList) do
        if value == packId then
            packIdCount = packIdCount + 1
        end
    end

    packRegistry.packs[packId] = previousPack
    packRegistry.packList = previousPackList
    lib.coordinator.register(packId, nil)

    lu.assertEquals(packIdCount, 0)
    lu.assertEquals(packRegistry.packs[packId], previousPack)
end

function TestMain:testTryInitReturnsPackOnSuccess()
    local packId = "try-init-success-pack"
    local packRegistry = FrameworkPackRegistry
    local previousPack = packRegistry.packs[packId]
    local previousPackList = {}
    for i, value in ipairs(packRegistry.packList) do
        previousPackList[i] = value
    end

    lib.coordinator.register(packId, {
        ModEnabled = true,
    })

    local ok, pack, err
    FrameworkTestApi.withBootConstructors({
        createModuleRegistry = function()
            return {
                modules = {},
                refresh = function() end,
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
        end,
        createConfigHash = function()
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
        ok, pack, err = FrameworkTestApi.tryInit(packId, "Try Init Pack", {
            ModEnabled = true,
            DebugMode = false,
            Profiles = {
                { Name = "", Hash = "", Tooltip = "" },
            },
        }, 1, {})
    end)

    packRegistry.packs[packId] = previousPack
    packRegistry.packList = previousPackList
    lib.coordinator.register(packId, nil)

    lu.assertTrue(ok)
    lu.assertNotNil(pack)
    lu.assertNil(err)
end

function TestMain:testTryInitReturnsErrorAndDoesNotRegisterPack()
    CaptureWarnings()

    local packId = "try-init-fail-pack"
    local packRegistry = FrameworkPackRegistry
    local previousPack = packRegistry.packs[packId]
    local previousPackList = {}
    for i, value in ipairs(packRegistry.packList) do
        previousPackList[i] = value
    end

    lib.coordinator.register(packId, {
        ModEnabled = true,
    })

    local ok, pack, err
    FrameworkTestApi.withBootConstructors({
        createModuleRegistry = function()
            return {
                modules = {},
                refresh = function() end,
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
        end,
        createConfigHash = function()
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
            error("try init boom")
        end,
    }, function()
        ok, pack, err = FrameworkTestApi.tryInit(packId, "Try Init Pack", {
            ModEnabled = true,
            DebugMode = false,
            Profiles = {
                { Name = "", Hash = "", Tooltip = "" },
            },
        }, 1, {})
    end)

    local warnings = Warnings

    local packIdCount = 0
    for _, value in ipairs(packRegistry.packList) do
        if value == packId then
            packIdCount = packIdCount + 1
        end
    end

    packRegistry.packs[packId] = previousPack
    packRegistry.packList = previousPackList
    lib.coordinator.register(packId, nil)
    RestoreWarnings()

    lu.assertFalse(ok)
    lu.assertNil(pack)
    lu.assertStrContains(tostring(err), "try init boom")
    lu.assertEquals(packIdCount, 0)
    lu.assertEquals(packRegistry.packs[packId], previousPack)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "[try-init-fail-pack] Framework init failed; skipping pack:")
    lu.assertStrContains(warnings[1], "try init boom")
end

function TestMain:testInitStartupLifecycleWarningUsesPackPrefix()
    CaptureWarnings()

    local entry = {
        id = "Alpha",
        name = "Alpha",
        pluginGuid = "Alpha",
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
    lib.coordinator.register("startup-pack", { ModEnabled = true })

    FrameworkTestApi.withBootConstructors({
        createModuleRegistry = function()
            return {
                modules = { entry },
                refresh = function() end,
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
        createConfigHash = function()
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
        FrameworkTestApi.init(
            "startup-pack",
            "Startup Pack",
            {
                ModEnabled = true,
                DebugMode = false,
                Profiles = {
                    { Name = "", Hash = "", Tooltip = "" },
                },
            },
            1,
            {}
        )
    end)

    local warnings = Warnings
    lib.coordinator.register("startup-pack", nil)
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

    local firstState = { built = 0, target = { Value = "base" } }
    local secondState = { built = 0, target = { Value = "base" } }

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {},
            patchPlan = function(plan)
                firstState.built = firstState.built + 1
                plan:set(firstState.target, "Value", "patched")
            end,
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = true,
            storage = {},
            patchPlan = function()
                secondState.built = secondState.built + 1
                error("apply boom")
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

    local theme = FrameworkTestApi.createTheme()
    local setup = {
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

    local builtUi = FrameworkTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        setup.NUM_PROFILES, setup.defaultProfiles, setup.renderQuickSetup)
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
    lu.assertEquals(firstState.built, 1)
    lu.assertEquals(firstState.target.Value, "base")
    lu.assertEquals(secondState.built, 1)
    lu.assertEquals(secondState.target.Value, "base")
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

    local firstState = { built = 0, target = { Value = "base" } }
    local secondState = { built = 0, target = { Value = "base" } }

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = false,
            storage = {},
            patchPlan = function(plan)
                firstState.built = firstState.built + 1
                plan:set(firstState.target, "Value", "patched")
            end,
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = false,
            storage = {},
            patchPlan = function()
                secondState.built = secondState.built + 1
                error("apply boom")
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
            Alpha = false,
            Bravo = false,
        },
        debug = {},
    }
    local snapshotAccess = {
        get = function()
            return nil
        end,
        capture = function()
            return moduleRegistry.live.captureSnapshot()
        end,
        getHost = function(entry, snapshot)
            return moduleRegistry.snapshot.getHost(entry, snapshot)
        end,
    }
    local runtime = FrameworkTestApi.createUIRuntime({
        moduleRegistry = moduleRegistry,
        hud = hud,
        config = {
            ModEnabled = true,
            DebugMode = false,
        },
        packId = "test-pack",
        colors = {},
        staging = staging,
        snapshotAccess = snapshotAccess,
        snapshotToStaging = function() end,
        logging = FrameworkTestApi.logging,
    })

    local snapshot = moduleRegistry.live.captureSnapshot()
    local ok, err = runtime.setModulesEnabled({ "Alpha", "Bravo" }, true, snapshot)
    runtime.flushPendingRunData()

    local warnings = Warnings
    rom.game.SetupRunData = previousSetupRunData
    RestoreWarnings()

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "apply boom")
    lu.assertFalse(staging.modules.Alpha)
    lu.assertFalse(staging.modules.Bravo)
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Alpha, snapshot))
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Bravo, snapshot))
    lu.assertEquals(firstState.built, 1)
    lu.assertEquals(firstState.target.Value, "base")
    lu.assertEquals(secondState.built, 1)
    lu.assertEquals(secondState.target.Value, "base")
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

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {
                { type = "bool", alias = "FlagA", default = false },
            },
            DrawTab = function() end,
            DrawQuickContent = function(ui)
                ui.Checkbox("Quick B", false)
            end,
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

    local theme = FrameworkTestApi.createTheme()
    local setup = {
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

    local builtUi = FrameworkTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        setup.NUM_PROFILES, setup.defaultProfiles, setup.renderQuickSetup)
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

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {
                { type = "bool", alias = "FlagA", default = false },
            },
            DrawTab = function() end,
            DrawQuickContent = function()
                firstQuickRenders = firstQuickRenders + 1
            end,
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

    local theme = FrameworkTestApi.createTheme()
    local setup = {
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

    local builtUi = FrameworkTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        setup.NUM_PROFILES, setup.defaultProfiles, setup.renderQuickSetup)
    builtUi.addMenuBar()
    local okFirst, errFirst = pcall(builtUi.renderWindow)

    local entry = moduleRegistry.modules[1]
    local replacementDefinition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = entry.id,
        name = entry.name,
        modpack = entry.modpack,
        storage = {
            { type = "bool", alias = "FlagA", default = false },
        },
    })
    local store, session = CreateModuleState({
        Enabled = true,
        DebugMode = false,
        FlagA = false,
    }, replacementDefinition)
    local replacementHost, replacementAuthorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = entry.pluginGuid,
        definition = replacementDefinition,
        store = store,
        session = session,
        drawTab = function() end,
        drawQuickContent = function()
            secondQuickRenders = secondQuickRenders + 1
        end,
    })
    replacementAuthorHost.tryActivate()
    rom.mods[entry.pluginGuid].host = replacementHost

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
    local closeCalls = 0
    local alwaysDraw

    rom.gui = {
        is_open = function()
            return guiOpen
        end,
    }

    local packId = "flush-pack"
    alwaysDraw = public.createGuiCallbacks(packId).alwaysDraw

    local capturedPacks = FrameworkPackRegistry.packs
    local previousPack = capturedPacks and capturedPacks[packId] or nil
    capturedPacks[packId] = {
        ui = {
            flushPending = function()
                flushCalls = flushCalls + 1
            end,
            handleHostGuiClosed = function()
                closeCalls = closeCalls + 1
            end,
        },
    }

    alwaysDraw()
    guiOpen = false
    alwaysDraw()
    alwaysDraw()

    rom.gui = previousGui
    capturedPacks[packId] = previousPack

    lu.assertEquals(flushCalls, 0)
    lu.assertEquals(closeCalls, 1)
end

function TestMain:testHostGuiCloseReleasesOverlaySuppression()
    local flushCalls = 0
    local suppressCalls = 0
    local releaseCalls = 0
    local previousSuppressForUi = lib.overlays.suppressForUi
    local previousImGui = rom.ImGui
    local function noop() end

    lib.overlays.suppressForUi = function()
        suppressCalls = suppressCalls + 1
        return {
            release = function()
                releaseCalls = releaseCalls + 1
            end,
        }
    end
    rom.ImGui = {
        MenuItem = function()
            return true
        end,
    }

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {},
    })
    moduleRegistry.modules = {}
    moduleRegistry.modulesById = {}
    local hud = {
        flushPendingHash = function()
            flushCalls = flushCalls + 1
        end,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        applyConfigHash = function()
            return true
        end,
        markHashDirty = noop,
    }
    local theme = FrameworkTestApi.createTheme()
    local ui = FrameworkTestApi.createUI(moduleRegistry, hud, theme, {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {},
    }, "test-pack", "Test Window", 1, {
        { Name = "", Hash = "", Tooltip = "" },
    }, nil)

    ui.addMenuBar()
    ui.handleHostGuiClosed()

    rom.ImGui = previousImGui
    lib.overlays.suppressForUi = previousSuppressForUi

    lu.assertEquals(flushCalls, 1)
    lu.assertEquals(suppressCalls, 1)
    lu.assertEquals(releaseCalls, 1)
end

function TestMain:testDisablingRunDataModuleFlushesSetupRunDataWhenMenuCloses()
    local previousImGui = rom.ImGui
    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    local quickSetupRan = false

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

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {},
            patchPlan = function(plan)
                plan:set({}, "unused", true)
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

    local theme = FrameworkTestApi.createTheme()
    local setup = {
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

    local builtUi = FrameworkTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        setup.NUM_PROFILES, setup.defaultProfiles, setup.renderQuickSetup)
    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)
    builtUi.addMenuBar()

    rom.ImGui = previousImGui
    rom.game.SetupRunData = previousSetupRunData

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(quickSetupRan)
    lu.assertEquals(setupRunDataCalls, 1)
end
