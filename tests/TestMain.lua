local lu = require('luaunit')

TestMain = {}

local function snapshotTable(source)
    local snapshot = {}
    for key, value in pairs(source) do
        snapshot[key] = value
    end
    return snapshot
end

local function replaceTableContents(target, source)
    for key in pairs(target) do
        target[key] = nil
    end
    for key, value in pairs(source) do
        target[key] = value
    end
end

local function readPackRestoreMarker(moduleRegistry, entry, snapshot)
    return moduleRegistry.snapshot.getHost(entry, snapshot).read("AdamantFramework_PackRestoreSnapshot")
end

function TestMain:setUp()
    local overlays = LibOverlays
    self.previousUiSuppressors = overlays.uiSuppressors
    self.previousNextUiSuppressorId = overlays.nextUiSuppressorId
    overlays.uiSuppressors = {}
    overlays.nextUiSuppressorId = 0
end

function TestMain:tearDown()
    local overlays = LibOverlays
    overlays.uiSuppressors = self.previousUiSuppressors
    overlays.nextUiSuppressorId = self.previousNextUiSuppressorId
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

function TestMain:testCreateUIReloadsModulesBeforeCapturingStartupStaging()
    local function noop() end

    local entry = {
        id = "Alpha",
        name = "Alpha",
        pluginGuid = "Alpha",
        _tabLabel = "Alpha",
    }
    local host = {
        reloaded = false,
        reloadFromConfig = function(hostSelf)
            hostSelf.reloaded = true
        end,
    }
    local sawReloadBeforeEnabledRead = false
    local sawReloadBeforeDebugRead = false
    local moduleRegistry = {
        modules = { entry },
        modulesById = {
            Alpha = entry,
        },
        modulesWithQuickContent = {},
        tabOrder = { entry },
        live = {
            captureSnapshot = function()
                return {
                    hosts = {
                        [entry] = host,
                    },
                }
            end,
        },
        snapshot = {
            getHost = function(_, snapshot)
                return snapshot.hosts[entry]
            end,
            isEntryEnabled = function(_, snapshot)
                sawReloadBeforeEnabledRead = snapshot.hosts[entry].reloaded == true
                return true
            end,
            isDebugEnabled = function(_, snapshot)
                sawReloadBeforeDebugRead = snapshot.hosts[entry].reloaded == true
                return false
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

    FrameworkTestApi.createUI(moduleRegistry, hud, theme, {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, "test-pack", "Test Window", 1, {
        { Name = "", Hash = "", Tooltip = "" },
    })

    lu.assertTrue(sawReloadBeforeEnabledRead)
    lu.assertTrue(sawReloadBeforeDebugRead)
end

function TestMain:testCreateHudRegistersFrameworkHashOverlay()
    local overlayOrder = {
        framework = 0,
        module = 1000,
        debug = 2000,
    }
    local registeredPack = nil
    local registeredScope = nil
    local registeredLine = nil
    local projectedValue = nil
    local registeredOpts = nil
    local refreshCalls = 0

    local frameworkRuntime = {
        overlays = {
            order = overlayOrder,
            define = function(packId, scope, register)
                registeredPack = packId
                registeredScope = scope
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
            end,
        },
    }

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

    local hud = FrameworkTestApi.createHud("test-pack", 1, hash, theme, config, false, frameworkRuntime)
    hud.install()
    hud.setModMarker(false)

    lu.assertEquals(registeredPack, "test-pack")
    lu.assertEquals(registeredScope, "hud")
    lu.assertEquals(registeredLine, "hash")
    lu.assertEquals(registeredOpts.region, "middleRightStack")
    lu.assertEquals(registeredOpts.order, overlayOrder.framework + 1)
    lu.assertEquals(projectedValue, "")
    lu.assertFalse(registeredOpts.visible())
    lu.assertEquals(refreshCalls, 2)
end

function TestMain:testCreateHudInstallClearsFrameworkHashOverlayWhenHidden()
    local registeredPack = nil
    local registeredScope = nil
    local createLineCalls = 0
    local commitCalls = 0

    local frameworkRuntime = {
        overlays = {
            order = {
                framework = 0,
            },
            define = function(packId, scope, register)
                registeredPack = packId
                registeredScope = scope
                register({
                    createLine = function()
                        createLineCalls = createLineCalls + 1
                    end,
                    onCommit = function()
                        commitCalls = commitCalls + 1
                    end,
                })
                return true
            end,
        },
    }

    local hud = FrameworkTestApi.createHud("test-pack", 1, {
        GetConfigHash = function()
            return "hash", "fingerprint"
        end,
        ApplyConfigHash = function()
            return true
        end,
    }, FrameworkTestApi.createTheme(), { ModEnabled = true }, true, frameworkRuntime)

    hud.install()

    lu.assertEquals(registeredPack, "test-pack")
    lu.assertEquals(registeredScope, "hud")
    lu.assertEquals(createLineCalls, 0)
    lu.assertEquals(commitCalls, 0)
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

function TestMain:testInitLeavesStartupMutationSyncToHostActivation()
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
    local host = {}

    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end
    public.registerCoordinator("startup-pack", { ModEnabled = true })

    local harness = CreateFrameworkHarness({
        constructors = {
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
                install = function() end,
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
        },
    })
    harness.createPackOrThrow(
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

    public.registerCoordinator("startup-pack", nil)
    rom.game.SetupRunData = previousSetupRunData

    lu.assertEquals(setupRunDataCalls, 0)
end

function TestMain:testModuleActivationOwnsStartupSyncBeforeFrameworkInit()
    local packId = "load-order-pack"
    public.registerCoordinator(packId, nil)

    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    local buildCalls = 0
    local target = { Value = "base" }

    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local definition = LibModuleHost.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local persistentState, stagedState = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local mutationBundle = {
        patchMutation = nil,
    }
    LibTestImports["core/mutations/00_init.lua"].lifecycle.declarePatch(mutationBundle, function(_, _, plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", "patched")
    end)
    local host = LibModuleHost.create({
        pluginGuid = "test-pack.Alpha",
        definition = definition,
        persistentState = persistentState,
        stagedState = stagedState,
        mutationBundle = mutationBundle,
        drawTab = function() end,
    })
    host.activate()

    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "patched")
    lu.assertEquals(setupRunDataCalls, 1)
    public.registerCoordinator(packId, {
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

    local harness = CreateFrameworkHarness({
        constructors = {
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
                install = function() end,
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
        },
    })
    harness.createPackOrThrow(
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

    local ok, err = host.revertMutation()
    public.registerCoordinator(packId, nil)
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

    public.registerCoordinator(packId, {
        ModEnabled = true,
    })

    local harness = CreateFrameworkHarness({
        constructors = {
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
                install = function() end,
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
        },
    })
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    firstPack = harness.createPackOrThrow(packId, "Reinit Pack", config, 1, {})
    secondPack = harness.createPackOrThrow(packId, "Reinit Pack", config, 1, {})

    local packIdCount = 0
    for _, value in ipairs(packRegistry.packList) do
        if value == packId then
            packIdCount = packIdCount + 1
        end
    end
    local activePack = packRegistry.packs[packId]

    packRegistry.packs[packId] = previousPack
    packRegistry.packList = previousPackList
    public.registerCoordinator(packId, nil)

    lu.assertTrue(firstPack ~= secondPack)
    lu.assertEquals(activePack, secondPack)
    lu.assertEquals(#hudIndexes, 2)
    lu.assertEquals(hudIndexes[1], hudIndexes[2])
    lu.assertEquals(firstPack._index, secondPack._index)
    lu.assertEquals(packIdCount, 1)
end

function TestMain:testRepeatedInitDisposesPreviousOpenUiSuppression()
    local packId = "reinit-dispose-pack"
    local packRegistry = FrameworkPackRegistry
    local previousPack = packRegistry.packs[packId]
    local previousPackList = {}
    for i, value in ipairs(packRegistry.packList) do
        previousPackList[i] = value
    end

    local previousImGui = rom.ImGui
    local suppressCalls = 0
    local releaseCalls = 0
    local flushCalls = 0
    local frameworkRuntime = lib.createFrameworkRuntime("adamant-ModpackFramework")
    local hashing = frameworkRuntime.hashing

    public.registerCoordinator(packId, {
        ModEnabled = true,
    })
    local testFrameworkRuntime = {
        diagnostics = frameworkRuntime.diagnostics,
        coordinator = frameworkRuntime.coordinator,
        hashing = hashing,
        modules = frameworkRuntime.modules,
        overlays = frameworkRuntime.overlays,
        ui = {
            suppressOverlays = function()
                suppressCalls = suppressCalls + 1
                local released = false
                return {
                    release = function()
                        if released then
                            return
                        end
                        released = true
                        releaseCalls = releaseCalls + 1
                    end,
                }
            end,
            areOverlaysSuppressed = function()
                return suppressCalls > releaseCalls
            end,
        },
    }
    rom.ImGui = {
        MenuItem = function()
            return true
        end,
    }

    local harness = CreateFrameworkHarness({
        frameworkRuntime = testFrameworkRuntime,
        constructors = {
            createModuleRegistry = function()
                return {
                    modules = {},
                    modulesById = {},
                    tabOrder = {},
                    modulesWithQuickContent = {},
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
                        isEntryEnabled = function()
                            return false
                        end,
                        isDebugEnabled = function()
                            return false
                        end,
                    },
                }
            end,
            createConfigHash = function()
                return {}
            end,
            createTheme = function()
                return {
                    colors = {
                        textDisabled = {},
                        warning = {},
                        success = {},
                        info = {},
                    },
                    PushTheme = function() end,
                    PopTheme = function() end,
                }
            end,
            createHud = function()
                return {
                    install = function() end,
                    setModMarker = function() end,
                    setMarkerVisible = function() end,
                    flushPendingHash = function()
                        flushCalls = flushCalls + 1
                    end,
                    getConfigHash = function()
                        return "", ""
                    end,
                    applyConfigHash = function()
                        return true
                    end,
                    markHashDirty = function() end,
                }
            end,
        },
    })
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local firstPack = harness.createPackOrThrow(packId, "Reinit Dispose Pack", config, 1, {})
    firstPack.ui.addMenuBar()
    local secondPack = harness.createPackOrThrow(packId, "Reinit Dispose Pack", config, 1, {})
    local releaseCallsAfterReinit = releaseCalls
    local flushCallsAfterReinit = flushCalls
    firstPack.ui.addMenuBar()
    local suppressCallsAfterDisposedProbe = suppressCalls
    local releaseCallsAfterDisposedProbe = releaseCalls
    local flushCallsAfterDisposedProbe = flushCalls

    local activePack = packRegistry.packs[packId]

    rom.ImGui = previousImGui
    packRegistry.packs[packId] = previousPack
    packRegistry.packList = previousPackList
    public.registerCoordinator(packId, nil)

    lu.assertTrue(firstPack ~= secondPack)
    lu.assertEquals(activePack, secondPack)
    lu.assertEquals(suppressCallsAfterDisposedProbe, 1)
    lu.assertEquals(releaseCallsAfterReinit, 1)
    lu.assertEquals(releaseCallsAfterDisposedProbe, 1)
    lu.assertEquals(flushCallsAfterReinit, 1)
    lu.assertEquals(flushCallsAfterDisposedProbe, 1)
end

function TestMain:testFailedInitDoesNotRegisterPack()
    local packId = "failed-init-pack"
    local packRegistry = FrameworkPackRegistry
    local hudInstallCalls = 0
    local previousPack = packRegistry.packs[packId]
    local previousPackList = {}
    for i, value in ipairs(packRegistry.packList) do
        previousPackList[i] = value
    end

    public.registerCoordinator(packId, {
        ModEnabled = true,
    })

    local harness = CreateFrameworkHarness({
        constructors = {
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
                install = function()
                    hudInstallCalls = hudInstallCalls + 1
                end,
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            error("ui construction boom")
        end,
        },
    })
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    lu.assertErrorMsgContains("ui construction boom", function()
        harness.createPackOrThrow(packId, "Failed Init Pack", config, 1, {})
    end)

    local packIdCount = 0
    for _, value in ipairs(packRegistry.packList) do
        if value == packId then
            packIdCount = packIdCount + 1
        end
    end

    packRegistry.packs[packId] = previousPack
    packRegistry.packList = previousPackList
    public.registerCoordinator(packId, nil)

    lu.assertEquals(packIdCount, 0)
    lu.assertEquals(packRegistry.packs[packId], previousPack)
    lu.assertEquals(hudInstallCalls, 0)
end

function TestMain:testTryInitReturnsPackOnSuccess()
    local packId = "try-init-success-pack"
    local packRegistry = FrameworkPackRegistry
    local previousPack = packRegistry.packs[packId]
    local previousPackList = {}
    for i, value in ipairs(packRegistry.packList) do
        previousPackList[i] = value
    end

    public.registerCoordinator(packId, {
        ModEnabled = true,
    })

    local ok, pack, err
    local harness = CreateFrameworkHarness({
        constructors = {
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
                install = function() end,
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
        },
    })
    ok, pack, err = harness.createPack(packId, "Create Pack", {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, 1, {})

    packRegistry.packs[packId] = previousPack
    packRegistry.packList = previousPackList
    public.registerCoordinator(packId, nil)

    lu.assertTrue(ok)
    lu.assertNotNil(pack)
    lu.assertNil(err)
end

function TestMain:testTryInitReturnsErrorAndDoesNotRegisterPack()
    CaptureWarnings()

    local packId = "create-pack-fail-pack"
    local packRegistry = FrameworkPackRegistry
    local previousPack = packRegistry.packs[packId]
    local previousPackList = {}
    for i, value in ipairs(packRegistry.packList) do
        previousPackList[i] = value
    end

    public.registerCoordinator(packId, {
        ModEnabled = true,
    })

    local ok, pack, err
    local harness = CreateFrameworkHarness({
        constructors = {
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
                install = function() end,
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            error("try init boom")
        end,
        },
    })
    ok, pack, err = harness.createPack(packId, "Create Pack", {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, 1, {})

    local warnings = Warnings

    local packIdCount = 0
    for _, value in ipairs(packRegistry.packList) do
        if value == packId then
            packIdCount = packIdCount + 1
        end
    end

    packRegistry.packs[packId] = previousPack
    packRegistry.packList = previousPackList
    public.registerCoordinator(packId, nil)
    RestoreWarnings()

    lu.assertFalse(ok)
    lu.assertNil(pack)
    lu.assertStrContains(tostring(err), "try init boom")
    lu.assertEquals(packIdCount, 0)
    lu.assertEquals(packRegistry.packs[packId], previousPack)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "[create-pack-fail-pack] Framework createPack failed; skipping pack:")
    lu.assertStrContains(warnings[1], "try init boom")
end

function TestMain:testMasterToggleRollsBackTouchedRuntimeStateOnFailure()
    CaptureWarnings()

    local config = {
        ModEnabled = false,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    public.registerCoordinator("test-pack", config)
    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    rom.game.SetupRunData = function()
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
        GetContentRegionAvail = function() return 1000 end,
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
            enabled = false,
            values = {
                AdamantFramework_PackRestoreSnapshot = 2,
            },
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
            values = {
                AdamantFramework_PackRestoreSnapshot = 2,
            },
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
    local builtUi = FrameworkTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        setup.NUM_PROFILES, setup.defaultProfiles, setup.drawPackQuickContent)
    builtUi.addMenuBar()

    local okFirst, errFirst = pcall(builtUi.renderWindow)
    local okSecond, errSecond = pcall(builtUi.renderWindow)
    local warnings = Warnings

    rom.ImGui = previousImGui
    rom.game.SetupRunData = previousSetupRunData
    public.registerCoordinator("test-pack", nil)
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
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "[test-pack] Enable Mod toggle failed; restoring previous runtime state: ")
    lu.assertStrContains(warnings[1], "apply boom")
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
    local function noop() end
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

function TestMain:testPackDisableSnapshotsModuleEnabledState()
    local config = {
        ModEnabled = true,
        DebugMode = false,
    }
    public.registerCoordinator("test-pack", config)

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {},
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = false,
            storage = {},
        },
    })
    local staging = {
        ModEnabled = true,
        modules = {
            Alpha = true,
            Bravo = false,
        },
        debug = {},
    }
    local hudMarkers = {}
    local runtime = FrameworkTestApi.createUIRuntime({
        moduleRegistry = moduleRegistry,
        hud = {
            markHashDirty = function() end,
            setModMarker = function(value)
                hudMarkers[#hudMarkers + 1] = value
            end,
        },
        config = config,
        packId = "test-pack",
        colors = {},
        staging = staging,
        snapshotAccess = {
            get = function() return nil end,
            capture = function() return moduleRegistry.live.captureSnapshot() end,
            getHost = function(entry, snapshot)
                return moduleRegistry.snapshot.getHost(entry, snapshot)
            end,
        },
        snapshotToStaging = function() end,
        logging = FrameworkTestApi.logging,
    })
    local snapshot = moduleRegistry.live.captureSnapshot()

    local ok, err = runtime.setPackRuntimeState(false, snapshot)

    public.registerCoordinator("test-pack", nil)

    lu.assertTrue(ok, tostring(err))
    lu.assertFalse(config.ModEnabled)
    lu.assertFalse(staging.ModEnabled)
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Alpha, snapshot))
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Bravo, snapshot))
    lu.assertEquals(
        readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Alpha, snapshot),
        2)
    lu.assertEquals(
        readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Bravo, snapshot),
        1)
    lu.assertEquals(hudMarkers, { false })
end

function TestMain:testPackEnableRestoresPersistedPackRestoreMarkers()
    local config = {
        ModEnabled = false,
        DebugMode = false,
    }
    public.registerCoordinator("test-pack", config)

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = false,
            values = {
                AdamantFramework_PackRestoreSnapshot = 2,
            },
            storage = {},
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = false,
            values = {
                AdamantFramework_PackRestoreSnapshot = 1,
            },
            storage = {},
        },
    })
    local staging = {
        ModEnabled = false,
        modules = {
            Alpha = false,
            Bravo = false,
        },
        debug = {},
    }
    local hudMarkers = {}
    local runtime = FrameworkTestApi.createUIRuntime({
        moduleRegistry = moduleRegistry,
        hud = {
            markHashDirty = function() end,
            setModMarker = function(value)
                hudMarkers[#hudMarkers + 1] = value
            end,
        },
        config = config,
        packId = "test-pack",
        colors = {},
        staging = staging,
        snapshotAccess = {
            get = function() return nil end,
            capture = function() return moduleRegistry.live.captureSnapshot() end,
            getHost = function(entry, snapshot)
                return moduleRegistry.snapshot.getHost(entry, snapshot)
            end,
        },
        snapshotToStaging = function() end,
        logging = FrameworkTestApi.logging,
    })
    local snapshot = moduleRegistry.live.captureSnapshot()

    local ok, err = runtime.setPackRuntimeState(true, snapshot)

    public.registerCoordinator("test-pack", nil)

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(config.ModEnabled)
    lu.assertTrue(staging.ModEnabled)
    lu.assertTrue(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Alpha, snapshot))
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Bravo, snapshot))
    lu.assertEquals(
        readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Alpha, snapshot),
        0)
    lu.assertEquals(
        readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Bravo, snapshot),
        0)
    lu.assertEquals(hudMarkers, { true })
end

function TestMain:testRuntimeResetAllModulesCommitsModuleDefaults()
    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            values = {
                Flag = true,
            },
            storage = {
                { type = "bool", alias = "Flag", default = false },
            },
            patchPlan = function(plan)
                plan:set({}, "unused", true)
            end,
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = false,
            values = {
                Count = 4,
            },
            storage = {
                { type = "int", alias = "Count", default = 1, min = 0, max = 9 },
            },
        },
    })
    local snapshotToStagingCalls = 0
    local markHashDirtyCalls = 0
    local updateHashCalls = 0
    local runtime = FrameworkTestApi.createUIRuntime({
        moduleRegistry = moduleRegistry,
        hud = {
            markHashDirty = function()
                markHashDirtyCalls = markHashDirtyCalls + 1
            end,
            updateHash = function()
                updateHashCalls = updateHashCalls + 1
            end,
        },
        config = {
            ModEnabled = true,
            DebugMode = false,
        },
        packId = "test-pack",
        colors = {},
        staging = {
            ModEnabled = true,
            modules = {},
            debug = {},
        },
        snapshotAccess = {
            get = function() return nil end,
            capture = function() return moduleRegistry.live.captureSnapshot() end,
            getHost = function(entry, snapshot)
                return moduleRegistry.snapshot.getHost(entry, snapshot)
            end,
        },
        snapshotToStaging = function()
            snapshotToStagingCalls = snapshotToStagingCalls + 1
        end,
        logging = FrameworkTestApi.logging,
    })
    local snapshot = moduleRegistry.live.captureSnapshot()
    local alpha = moduleRegistry.modulesById.Alpha
    local bravo = moduleRegistry.modulesById.Bravo

    local ok, err, resetCount = runtime.resetAllModules()
    runtime.flushPendingRunData()
    rom.game.SetupRunData = previousSetupRunData

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(resetCount, 3)
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(alpha, snapshot))
    lu.assertFalse(moduleRegistry.snapshot.getStorageValue(alpha, "Flag", snapshot))
    lu.assertEquals(moduleRegistry.snapshot.getStorageValue(bravo, "Count", snapshot), 1)
    lu.assertEquals(snapshotToStagingCalls, 1)
    lu.assertEquals(markHashDirtyCalls, 1)
    lu.assertEquals(updateHashCalls, 1)
    lu.assertEquals(setupRunDataCalls, 2)
end

function TestMain:testDisabledPackCreationSuspendsEnabledModules()
    local config = {
        ModEnabled = false,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    public.registerCoordinator("test-pack", config)

    local target = { Value = "base" }
    local buildCalls = 0
    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {},
            patchPlan = function(plan)
                buildCalls = buildCalls + 1
                plan:set(target, "Value", "patched")
            end,
        },
    })
    lu.assertEquals(target.Value, "patched")

    local function noop() end
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

    FrameworkTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        1, config.Profiles)
    local snapshot = moduleRegistry.live.captureSnapshot()

    public.registerCoordinator("test-pack", nil)

    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "base")
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Alpha, snapshot))
    lu.assertEquals(readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Alpha, snapshot), 2)
end

function TestMain:testQuickSetupRendersModuleQuickContent()
    local imgui = rom.ImGui
    local previousImGui = snapshotTable(imgui)
    local checkboxLabels = {}

    local function noop() end

    replaceTableContents(imgui, {
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
        GetContentRegionAvail = function() return 1000 end,
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
    })

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
            DrawQuickContent = function(draw)
                draw.imgui.Checkbox("Quick B", false)
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
        setup.NUM_PROFILES, setup.defaultProfiles, setup.drawPackQuickContent)
    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)

    replaceTableContents(imgui, previousImGui)

    lu.assertTrue(ok, tostring(err))
    local joined = table.concat(checkboxLabels, "\n")
    lu.assertStrContains(joined, "Enable Mod")
    lu.assertStrContains(joined, "Quick B")
end

function TestMain:testQuickSetupUsesLatestLiveModuleForQuickContent()
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
        GetContentRegionAvail = function() return 1000 end,
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
        setup.NUM_PROFILES, setup.defaultProfiles, setup.drawPackQuickContent)
    builtUi.addMenuBar()
    local okFirst, errFirst = pcall(builtUi.renderWindow)

    local entry = moduleRegistry.modules[1]
    local replacementDefinition = LibModuleHost.prepareDefinition({}, {
        id = entry.id,
        name = entry.name,
        modpack = entry.modpack,
        storage = {
            { type = "bool", alias = "FlagA", default = false },
        },
    })
    local persistentState, stagedState = CreateModuleState({
        Enabled = true,
        DebugMode = false,
        FlagA = false,
    }, replacementDefinition)
    local replacementHost = LibModuleHost.create({
        pluginGuid = entry.pluginGuid,
        definition = replacementDefinition,
        persistentState = persistentState,
        stagedState = stagedState,
        drawTab = function() end,
        drawQuickContent = function()
            secondQuickRenders = secondQuickRenders + 1
        end,
    })
    replacementHost.activate()
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
    local previousImGui = rom.ImGui
    local function noop() end

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
    }, nil, nil, {
        ui = {
            suppressOverlays = function()
                suppressCalls = suppressCalls + 1
                return {
                    release = function()
                        releaseCalls = releaseCalls + 1
                    end,
                }
            end,
        },
    })

    ui.addMenuBar()
    ui.handleHostGuiClosed()

    rom.ImGui = previousImGui

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
        GetContentRegionAvail = function() return 1000 end,
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
    setupRunDataCalls = 0

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
        drawPackQuickContent = function(ctx)
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
        setup.NUM_PROFILES, setup.defaultProfiles, setup.drawPackQuickContent)
    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)
    builtUi.addMenuBar()

    rom.ImGui = previousImGui
    rom.game.SetupRunData = previousSetupRunData

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(quickSetupRan)
    lu.assertEquals(setupRunDataCalls, 1)
end
