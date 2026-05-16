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
    definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        modpack = definition.modpack,
        id = definition.id,
        name = definition.name,
        shortName = definition.shortName,
        tooltip = definition.tooltip,
        storage = definition.storage,
        hashGroupPlan = definition.hashGroupPlan,
    })
    local store, session = CreateModuleState(persisted or {}, definition)
    local host, authorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        drawTab = exports.DrawTab,
        drawQuickContent = exports.DrawQuickContent,
        registerPatchMutation = patchPlan,
    })
    authorHost.tryActivate()
    exports.host = host
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

function TestModuleRegistry:testHostSnapshotUsesLiveHostAndWarnsWhenHostIsMissing()
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
        getIdentity = function()
            return {
                id = entry.id,
                modpack = entry.modpack,
            }
        end,
        getMeta = function()
            return {
                name = entry.name,
                shortName = entry.shortName,
                tooltip = entry.tooltip,
            }
        end,
        affectsRunData = function()
            return entry.affectsRunData == true
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

    exports.host = replacement
    AdamantModpackLib_Internal.liveModuleHosts["test-GodPool"] = replacement

    local liveSnapshot = moduleRegistry.live.captureSnapshot()
    lu.assertEquals(moduleRegistry.snapshot.getHost(entry, liveSnapshot), replacement)
    lu.assertTrue(moduleRegistry.snapshot.isEntryEnabled(entry, liveSnapshot))

    exports.host = nil
    AdamantModpackLib_Internal.liveModuleHosts["test-GodPool"] = nil

    local missingSnapshot = moduleRegistry.live.captureSnapshot()
    lu.assertNil(moduleRegistry.snapshot.getHost(entry, missingSnapshot))
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "module host is unavailable")
end

function TestModuleRegistry:testCapturedSnapshotIsStableAcrossHostReplacement()
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
    local originalHost = exports.host
    local capturedSnapshot = moduleRegistry.live.captureSnapshot()

    local replacement = {
        getStorage = function()
            return entry.storage
        end,
        getIdentity = function()
            return {
                id = entry.id,
                modpack = entry.modpack,
            }
        end,
        getMeta = function()
            return {
                name = entry.name,
                shortName = entry.shortName,
                tooltip = entry.tooltip,
            }
        end,
        affectsRunData = function()
            return entry.affectsRunData == true
        end,
        read = function() return "replacement" end,
        writeAndFlush = function() return true end,
        setEnabled = function() return true end,
        setDebugMode = function() end,
        drawTab = function() end,
    }
    exports.host = replacement
    AdamantModpackLib_Internal.liveModuleHosts["test-GodPool"] = replacement

    lu.assertEquals(moduleRegistry.snapshot.getHost(entry, capturedSnapshot), originalHost)
    lu.assertEquals(moduleRegistry.live.getHost(entry), replacement)

    local freshSnapshot = moduleRegistry.live.captureSnapshot()
    lu.assertEquals(moduleRegistry.snapshot.getHost(entry, freshSnapshot), replacement)
    lu.assertEquals(moduleRegistry.snapshot.getHost(entry, capturedSnapshot), originalHost)
end

function TestModuleRegistry:testHostSnapshotWarnsOnceWhenHostStaysMissing()
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
    exports.host = nil
    AdamantModpackLib_Internal.liveModuleHosts["test-GodPool"] = nil

    moduleRegistry.live.captureSnapshot()
    moduleRegistry.live.captureSnapshot()

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "module host is unavailable")
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

function TestModuleRegistry:testMissingDrawTabIsRejectedByLibHostCreation()
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
