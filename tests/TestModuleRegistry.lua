local lu = require('luaunit')

local function resetMods()
    rom.mods = {
        ['SGG_Modding-ENVY'] = {
            auto = function() return {} end,
        },
        ['SGG_Modding-Chalk'] = {
            auto = function() return { DebugMode = false } end,
        },
        ['adamant-ModpackLib'] = lib,
        ['adamant-ModpackFramework'] = public,
    }
end

local function attachModule(pluginGuid, definition, persisted, exports)
    exports = exports or {}
    local patchPlan = definition.patchPlan
    definition = LibManagedModule.prepareDefinition({}, {
        modpack = definition.modpack,
        id = definition.id,
        name = definition.name,
        shortName = definition.shortName,
        tooltip = definition.tooltip,
        storage = definition.storage,
    })
    local persistentState, stagedState = CreateModuleState(persisted or {}, definition)
    local function adaptDraw(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(callbackHost, ui)
            return callback(ui.draw, ui.data, ui.actions, ui, callbackHost)
        end
    end
    local function adaptPatch(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(callbackHost, runtime, plan)
            return callback(plan, callbackHost, runtime and runtime.data or nil, runtime)
        end
    end
    local mutationBundle = {
        patchMutation = nil,
    }
    if patchPlan ~= nil then
        local mutations = assert(LibTestImports["core/mutations/00_init.lua"], "Lib mutation bundle missing")
        mutations.lifecycle.declarePatch(mutationBundle, adaptPatch(patchPlan))
    end
    local liveModule = LibManagedModule.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = persistentState,
        stagedState = stagedState,
        mutationBundle = mutationBundle,
        drawTab = adaptDraw(exports.DrawTab),
        drawQuickContent = adaptDraw(exports.DrawQuickContent),
    })
    liveModule.activate()
    exports.liveModule = liveModule
    rom.mods[pluginGuid] = exports
    return exports
end

TestModuleRegistry = {}

function TestModuleRegistry:setUp()
    resetMods()
    CaptureWarnings()
end

function TestModuleRegistry:tearDown()
    RestoreWarnings()
end

function TestModuleRegistry:testModulesRegisterDrawTabAndQuickContent()
    attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        shortName = "Pool",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    }, { Enabled = false, DebugMode = false, EnabledFlag = false }, {
        DrawTab = function() end,
        DrawQuickContent = function() end,
    })

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", { DebugMode = false })
    moduleRegistry.refresh()

    lu.assertEquals(#moduleRegistry.modules, 1)
    lu.assertEquals(#moduleRegistry.modulesWithQuickContent, 1)
    lu.assertEquals(#moduleRegistry.tabOrder, 1)
    lu.assertEquals(moduleRegistry.tabOrder[1]._tabLabel, "Pool")
end

function TestModuleRegistry:testSnapshotUsesLiveModuleAndWarnsWhenLiveModuleIsMissing()
    local exports = attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    }, { Enabled = false, DebugMode = false, EnabledFlag = false }, {
        DrawTab = function() end,
    })

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", { DebugMode = false })
    moduleRegistry.refresh()

    local entry = moduleRegistry.modules[1]
    local replacement = {
        getStorage = function()
            return entry.storage
        end,
        getOwnerId = function()
            return "test-GodPool"
        end,
        getModuleId = function()
            return entry.id
        end,
        getPackId = function()
            return entry.modpack
        end,
        getMeta = function()
            return {
                name = entry.name,
                shortName = entry.shortName,
                tooltip = entry.tooltip,
            }
        end,
        affectsRunData = function()
            return true
        end,
        read = function(key)
            if key == "Enabled" then
                return true
            end
            return false
        end,
        writeAndFlush = function() return true end,
        setEnabled = function() return true end,
        setDebugMode = function() end,
        drawTab = function() end,
    }

    exports.liveModule = replacement
    SetRuntimeLiveModule("test-GodPool", replacement)

    local liveSnapshot = moduleRegistry.live.captureSnapshot()
    lu.assertEquals(moduleRegistry.snapshot.getLiveModule(entry, liveSnapshot), replacement)
    lu.assertTrue(moduleRegistry.snapshot.isEntryEnabled(entry, liveSnapshot))
    lu.assertTrue(moduleRegistry.snapshot.affectsRunData(entry, liveSnapshot))

    exports.liveModule = nil
    SetRuntimeLiveModule("test-GodPool", nil)

    local missingSnapshot = moduleRegistry.live.captureSnapshot()
    lu.assertNil(moduleRegistry.snapshot.getLiveModule(entry, missingSnapshot))
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "live module is unavailable")
end

function TestModuleRegistry:testCapturedSnapshotIsStableAcrossLiveModuleReplacement()
    local exports = attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    }, { Enabled = false, DebugMode = false, EnabledFlag = false }, {
        DrawTab = function() end,
    })

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", { DebugMode = false })
    moduleRegistry.refresh()

    local entry = moduleRegistry.modules[1]
    local originalLiveModule = exports.liveModule
    local capturedSnapshot = moduleRegistry.live.captureSnapshot()

    local replacement = {
        getStorage = function()
            return entry.storage
        end,
        getOwnerId = function()
            return "test-GodPool"
        end,
        getModuleId = function()
            return entry.id
        end,
        getPackId = function()
            return entry.modpack
        end,
        getMeta = function()
            return {
                name = entry.name,
                shortName = entry.shortName,
                tooltip = entry.tooltip,
            }
        end,
        affectsRunData = function()
            return true
        end,
        read = function() return "replacement" end,
        writeAndFlush = function() return true end,
        setEnabled = function() return true end,
        setDebugMode = function() end,
        drawTab = function() end,
    }
    exports.liveModule = replacement
    SetRuntimeLiveModule("test-GodPool", replacement)

    lu.assertEquals(moduleRegistry.snapshot.getLiveModule(entry, capturedSnapshot), originalLiveModule)
    lu.assertEquals(moduleRegistry.live.getLiveModule(entry), replacement)

    local freshSnapshot = moduleRegistry.live.captureSnapshot()
    lu.assertEquals(moduleRegistry.snapshot.getLiveModule(entry, freshSnapshot), replacement)
    lu.assertTrue(moduleRegistry.snapshot.affectsRunData(entry, freshSnapshot))
    lu.assertFalse(moduleRegistry.snapshot.affectsRunData(entry, capturedSnapshot))
    lu.assertEquals(moduleRegistry.snapshot.getLiveModule(entry, capturedSnapshot), originalLiveModule)
end

function TestModuleRegistry:testLiveModuleSnapshotWarnsOnceWhenLiveModuleStaysMissing()
    local exports = attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    }, { Enabled = false, DebugMode = false, EnabledFlag = false }, {
        DrawTab = function() end,
    })

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", { DebugMode = false })
    moduleRegistry.refresh()
    exports.liveModule = nil
    SetRuntimeLiveModule("test-GodPool", nil)

    moduleRegistry.live.captureSnapshot()
    moduleRegistry.live.captureSnapshot()

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "live module is unavailable")
end

function TestModuleRegistry:testModuleWithOnlyBuiltInStorageIsRegistered()
    attachModule("test-BuiltInsOnly", {
        modpack = "test-pack",
        id = "BuiltInsOnly",
        name = "Built Ins Only",
    }, { Enabled = false, DebugMode = false }, {
        DrawTab = function() end,
    })

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", { DebugMode = false })
    moduleRegistry.refresh()

    lu.assertEquals(#moduleRegistry.modules, 1)
    lu.assertEquals(moduleRegistry.modules[1].id, "BuiltInsOnly")
    lu.assertEquals(#Warnings, 0)
end

function TestModuleRegistry:testPackDisableSuspendsThroughModuleLifecycle()
    local exports = attachModule("test-PackRestore", {
        modpack = "test-pack",
        id = "PackRestore",
        name = "Pack Restore",
        storage = {},
    }, { Enabled = true, DebugMode = false }, {
        DrawTab = function() end,
    })

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", { DebugMode = false })
    moduleRegistry.refresh()
    local entry = moduleRegistry.modules[1]
    local snapshot = moduleRegistry.live.captureSnapshot()

    local ok, err, receipt = moduleRegistry.snapshot.suspendForPackDisable(entry, snapshot)
    lu.assertTrue(ok, tostring(err))

    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(entry, snapshot))
    lu.assertEquals(exports.liveModule.read("AdamantFramework_PackRestoreSnapshot"), 2)

    ok, err = moduleRegistry.snapshot.rollbackPackTransition(entry, receipt, snapshot)
    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(moduleRegistry.snapshot.isEntryEnabled(entry, snapshot))
    lu.assertEquals(exports.liveModule.read("AdamantFramework_PackRestoreSnapshot"), 0)
end

function TestModuleRegistry:testMissingDrawTabIsRejectedByLibManagedModuleCreation()
    local ok, err = pcall(function()
        attachModule("test-NoDrawTab", {
        modpack = "test-pack",
        id = "NoDrawTab",
        name = "No DrawTab",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    }, { Enabled = false, DebugMode = false, EnabledFlag = false })
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "drawTab is required")
end

function TestModuleRegistry:testDuplicateIdsSkipConflictingEntries()
    attachModule("test-Alpha", {
        modpack = "test-pack",
        id = "SharedId",
        name = "Alpha",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    }, { Enabled = false, DebugMode = false, Flag = false }, {
        DrawTab = function() end,
    })
    attachModule("test-Bravo", {
        modpack = "test-pack",
        id = "SharedId",
        name = "Bravo",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    }, { Enabled = false, DebugMode = false, Flag = false }, {
        DrawTab = function() end,
    })

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", { DebugMode = false })
    moduleRegistry.refresh()

    lu.assertEquals(#moduleRegistry.modules, 0)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "duplicate hash namespace 'SharedId'")
end

function TestModuleRegistry:testTabOrderPinsKnownIdsFirst()
    attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "FlagA", default = false },
        },
    }, { Enabled = false, DebugMode = false, FlagA = false }, {
        DrawTab = function() end,
    })
    attachModule("test-Biome", {
        modpack = "test-pack",
        id = "BiomeControl",
        name = "Biome Control",
        shortName = "Biome",
        storage = {
            { type = "bool", alias = "FlagB", default = false },
        },
    }, { Enabled = false, DebugMode = false, FlagB = false }, {
        DrawTab = function() end,
    })
    attachModule("test-BoonBans", {
        modpack = "test-pack",
        id = "BoonBans",
        name = "Boon Bans",
        storage = {
            { type = "bool", alias = "FlagC", default = false },
        },
    }, { Enabled = false, DebugMode = false, FlagC = false }, {
        DrawTab = function() end,
    })

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", { DebugMode = false })
    moduleRegistry.refresh({ "BiomeControl", "GodPool" })

    lu.assertEquals(#moduleRegistry.tabOrder, 3)
    lu.assertEquals(moduleRegistry.tabOrder[1].id, "BiomeControl")
    lu.assertEquals(moduleRegistry.tabOrder[2].id, "GodPool")
    lu.assertEquals(moduleRegistry.tabOrder[3].id, "BoonBans")
end

function TestModuleRegistry:testTabOrderIgnoresLabels()
    attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "FlagA", default = false },
        },
    }, { Enabled = false, DebugMode = false, FlagA = false }, {
        DrawTab = function() end,
    })
    attachModule("test-Biome", {
        modpack = "test-pack",
        id = "BiomeControl",
        name = "Biome Control",
        shortName = "Biome",
        storage = {
            { type = "bool", alias = "FlagB", default = false },
        },
    }, { Enabled = false, DebugMode = false, FlagB = false }, {
        DrawTab = function() end,
    })

    local moduleRegistry = FrameworkTestApi.createModuleRegistry("test-pack", { DebugMode = false })
    moduleRegistry.refresh({ "Biome", "God Pool", "GodPool" })

    lu.assertEquals(#moduleRegistry.tabOrder, 2)
    lu.assertEquals(moduleRegistry.tabOrder[1].id, "GodPool")
    lu.assertEquals(moduleRegistry.tabOrder[2].id, "BiomeControl")
end
