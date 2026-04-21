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
    exports.definition = definition
    local store, session = lib.createStore(persisted or {}, definition)
    if type(definition.storage) == "table" and session then
        exports.host = lib.createModuleHost({
            definition = definition,
            store = store,
            session = session,
            drawTab = exports.DrawTab,
            drawQuickContent = exports.DrawQuickContent,
        })
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

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.modules, 1)
    lu.assertEquals(#discovery.modulesWithQuickContent, 1)
    lu.assertEquals(#discovery.tabOrder, 1)
    lu.assertEquals(discovery.tabOrder[1]._tabLabel, "Pool")
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

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
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

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
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

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run()

    lu.assertEquals(#discovery.modules, 0)
    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "duplicate hash namespace 'SharedId'")
end

function TestDiscovery:testTabOrderPinsKnownLabelsFirst()
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

    local discovery = Framework.createDiscovery("test-pack", { DebugMode = false }, lib)
    discovery.run({ "Biome", "God Pool" })

    lu.assertEquals(#discovery.tabOrder, 2)
    lu.assertEquals(discovery.tabOrder[1].id, "BiomeControl")
    lu.assertEquals(discovery.tabOrder[2].id, "GodPool")
end
