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

local function attachModule(modName, definition, persisted, exports)
    exports = exports or {}
    definition = lib.prepareDefinition({}, definition)
    local store, session = lib.createStore(persisted or {}, definition)
    if type(definition.storage) == "table" and session then
        exports.host = lib.createModuleHost({
            definition = definition,
            store = store,
            session = session,
            drawTab = exports.DrawTab,
            drawQuickContent = exports.DrawQuickContent,
        })
    else
        exports.host = {
            getDefinition = function()
                return definition
            end,
            getIdentity = function()
                return {
                    id = definition.id,
                    modpack = definition.modpack,
                }
            end,
            getMeta = function()
                return {
                    name = definition.name,
                    shortName = definition.shortName,
                    tooltip = definition.tooltip,
                }
            end,
            getHashHints = function()
                return definition.hashGroupPlan
            end,
            affectsRunData = function()
                return definition.affectsRunData == true
            end,
            hasDrawTab = function()
                return type(exports.DrawTab) == "function"
            end,
            drawTab = function(...)
                if type(exports.DrawTab) == "function" then
                    return exports.DrawTab(...)
                end
            end,
            hasQuickContent = function()
                return type(exports.DrawQuickContent) == "function"
            end,
            drawQuickContent = function(...)
                if type(exports.DrawQuickContent) == "function" then
                    return exports.DrawQuickContent(...)
                end
            end,
        }
    end
    rom.mods[modName] = exports
    return exports
end

TestDiscovery = {}

function TestDiscovery:setUp()
    resetMods()
    CaptureWarnings()
end

function TestDiscovery:tearDown()
    RestoreWarnings()
end

function TestDiscovery:testModulesDiscoverDrawTabAndQuickContent()
    attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        shortName = "Pool",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false }, {
        DrawTab = function() end,
        DrawQuickContent = function() end,
    })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.modules, 1)
    lu.assertEquals(#discovery.modulesWithQuickContent, 1)
    lu.assertEquals(#discovery.tabOrder, 1)
    lu.assertEquals(discovery.tabOrder[1]._tabLabel, "Pool")
end

function TestDiscovery:testHostSnapshotUsesLiveHostAndWarnsWhenHostIsMissing()
    local exports = attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false }, {
        DrawTab = function() end,
    })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    local entry = discovery.modules[1]
    local replacement = {
        getDefinition = function()
            return entry.definition
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
        hasDrawTab = function() return true end,
        drawTab = function() end,
        hasQuickContent = function() return false end,
        drawQuickContent = function() end,
    }

    exports.host = replacement

    local liveSnapshot = discovery.live.captureSnapshot()
    lu.assertEquals(discovery.snapshot.getHost(entry, liveSnapshot), replacement)
    lu.assertTrue(discovery.snapshot.isEntryEnabled(entry, liveSnapshot))

    exports.host = nil

    local missingSnapshot = discovery.live.captureSnapshot()
    lu.assertNil(discovery.snapshot.getHost(entry, missingSnapshot))
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "module host is unavailable")
end

function TestDiscovery:testCapturedSnapshotIsStableAcrossHostReplacement()
    local exports = attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false }, {
        DrawTab = function() end,
    })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    local entry = discovery.modules[1]
    local originalHost = exports.host
    local capturedSnapshot = discovery.live.captureSnapshot()

    local replacement = {
        getDefinition = function()
            return entry.definition
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
        hasDrawTab = function() return true end,
        drawTab = function() end,
        hasQuickContent = function() return false end,
        drawQuickContent = function() end,
    }
    exports.host = replacement

    lu.assertEquals(discovery.snapshot.getHost(entry, capturedSnapshot), originalHost)
    lu.assertEquals(discovery.live.getHost(entry), replacement)

    local freshSnapshot = discovery.live.captureSnapshot()
    lu.assertEquals(discovery.snapshot.getHost(entry, freshSnapshot), replacement)
    lu.assertEquals(discovery.snapshot.getHost(entry, capturedSnapshot), originalHost)
end

function TestDiscovery:testHostSnapshotWarnsOnceWhenHostStaysMissing()
    local exports = attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false }, {
        DrawTab = function() end,
    })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()
    exports.host = nil

    discovery.live.captureSnapshot()
    discovery.live.captureSnapshot()

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "module host is unavailable")
end

function TestDiscovery:testSnapshotAccessRequiresCapturedSnapshot()
    attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false }, {
        DrawTab = function() end,
    })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertErrorMsgContains(
        "discovery.snapshot access requires a captured host snapshot",
        function()
            discovery.snapshot.getHost(discovery.modules[1])
        end)
end

function TestDiscovery:testMissingStorageSkipsModule()
    attachModule("test-MissingStorage", {
        modpack = "test-pack",
        id = "MissingStorage",
        name = "Missing Storage",
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false }, {
        DrawTab = function() end,
    })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.modules, 0)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "missing definition.storage")
end

function TestDiscovery:testMissingDrawTabSkipsModule()
    attachModule("test-NoDrawTab", {
        modpack = "test-pack",
        id = "NoDrawTab",
        name = "No DrawTab",
        storage = {
            { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, EnabledFlag = false })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.modules, 0)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "must expose host.drawTab")
end

function TestDiscovery:testDuplicateIdsSkipConflictingEntries()
    attachModule("test-Alpha", {
        modpack = "test-pack",
        id = "SharedId",
        name = "Alpha",
        storage = {
            { type = "bool", alias = "Flag", configKey = "Flag", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, Flag = false }, {
        DrawTab = function() end,
    })
    attachModule("test-Bravo", {
        modpack = "test-pack",
        id = "SharedId",
        name = "Bravo",
        storage = {
            { type = "bool", alias = "Flag", configKey = "Flag", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, Flag = false }, {
        DrawTab = function() end,
    })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.modules, 0)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "duplicate hash namespace 'SharedId'")
end

function TestDiscovery:testTabOrderPinsKnownIdsFirst()
    attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "FlagA", configKey = "FlagA", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, FlagA = false }, {
        DrawTab = function() end,
    })
    attachModule("test-Biome", {
        modpack = "test-pack",
        id = "BiomeControl",
        name = "Biome Control",
        shortName = "Biome",
        storage = {
            { type = "bool", alias = "FlagB", configKey = "FlagB", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, FlagB = false }, {
        DrawTab = function() end,
    })
    attachModule("test-BoonBans", {
        modpack = "test-pack",
        id = "BoonBans",
        name = "Boon Bans",
        storage = {
            { type = "bool", alias = "FlagC", configKey = "FlagC", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, FlagC = false }, {
        DrawTab = function() end,
    })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run({ "BiomeControl", "GodPool" })

    lu.assertEquals(#discovery.tabOrder, 3)
    lu.assertEquals(discovery.tabOrder[1].id, "BiomeControl")
    lu.assertEquals(discovery.tabOrder[2].id, "GodPool")
    lu.assertEquals(discovery.tabOrder[3].id, "BoonBans")
end

function TestDiscovery:testTabOrderIgnoresLabels()
    attachModule("test-GodPool", {
        modpack = "test-pack",
        id = "GodPool",
        name = "God Pool",
        storage = {
            { type = "bool", alias = "FlagA", configKey = "FlagA", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, FlagA = false }, {
        DrawTab = function() end,
    })
    attachModule("test-Biome", {
        modpack = "test-pack",
        id = "BiomeControl",
        name = "Biome Control",
        shortName = "Biome",
        storage = {
            { type = "bool", alias = "FlagB", configKey = "FlagB", default = false },
        },
        apply = function() end,
        revert = function() end,
    }, { Enabled = false, DebugMode = false, FlagB = false }, {
        DrawTab = function() end,
    })

    local discovery = FrameworkTestApi.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run({ "Biome", "God Pool", "GodPool" })

    lu.assertEquals(#discovery.tabOrder, 2)
    lu.assertEquals(discovery.tabOrder[1].id, "GodPool")
    lu.assertEquals(discovery.tabOrder[2].id, "BiomeControl")
end
