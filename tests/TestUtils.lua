-- =============================================================================
-- Test utilities: mock engine globals and load Framework for testing
-- =============================================================================

public = {}
_PLUGIN = { guid = "adamant-ModpackFramework" }

local function deepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepCopy(v)
    end
    return copy
end

rom = {
    mods = {},
    game = {
        DeepCopyTable = deepCopy,
        SetupRunData = function() end,
    },
    ImGui = {},
    ImGuiCond = {
        FirstUseEver = 1,
    },
    ImGuiCol = {
        Text = 1,
        TextDisabled = 2,
        WindowBg = 3,
        ChildBg = 4,
        Header = 5,
        HeaderHovered = 6,
        HeaderActive = 7,
        Button = 8,
        ButtonHovered = 9,
        ButtonActive = 10,
        FrameBg = 11,
        FrameBgHovered = 12,
        FrameBgActive = 13,
        CheckMark = 14,
        Tab = 15,
        TabHovered = 16,
        TabActive = 17,
        Separator = 18,
        Border = 19,
        TitleBgActive = 20,
    },
    gui = {
        add_to_menu_bar = function() end,
        add_imgui = function() end,
        add_always_draw_imgui = function() end,
        is_open = function() return true end,
    },
}

rom.mods['SGG_Modding-ENVY'] = {
    auto = function() return {} end,
}

rom.mods['SGG_Modding-Chalk'] = {
    auto = function() return { DebugMode = false } end,
}

rom.mods['SGG_Modding-ModUtil'] = {
    once_loaded = {
        game = function() end,
    },
    mod = {
        Path = {
            Wrap = function() end,
        },
    },
}

ImGuiComboFlags = {
    NoPreview = 64,
}

ImGuiCol = rom.ImGuiCol

ImGuiTreeNodeFlags = {
    None = 0,
    Selected = 1,
    Framed = 2,
    AllowOverlap = 4,
    NoTreePushOnOpen = 8,
    NoAutoOpenOnLog = 16,
    DefaultOpen = 32,
    OpenOnDoubleClick = 64,
    OpenOnArrow = 128,
    Leaf = 256,
    Bullet = 512,
    FramePadding = 1024,
    SpanAvailWidth = 2048,
    SpanFullWidth = 4096,
    NavLeftJumpsBackHere = 8192,
    CollapsingHeader = 26,
}

LibTestImports = {}
LibTestImportOverrides = {}

import = function(path, fenv, ...)
    local override = LibTestImportOverrides[path]
    if override ~= nil then
        if type(override) == "function" then
            return override(path, fenv, ...)
        end
        return override
    end

    local chunk = assert(loadfile("../adamant-ModpackLib/src/" .. path, "t", fenv or _ENV))
    local result = chunk(...)
    if result ~= nil then
        LibTestImports[path] = result
    end
    return result
end

Warnings = {}

function CaptureWarnings()
    Warnings = {}
    lib.createFrameworkRuntime("adamant-ModpackFramework").diagnostics.setLibDebugEnabled(true)
    _originalPrint = print
    print = function(msg)
        table.insert(Warnings, msg)
    end
end

function RestoreWarnings()
    lib.createFrameworkRuntime("adamant-ModpackFramework").diagnostics.setLibDebugEnabled(false)
    print = _originalPrint or print
    Warnings = {}
end

dofile("../adamant-ModpackLib/src/main.lua")
lib = public
rom.mods['adamant-ModpackLib'] = lib
local defaultFrameworkRuntime = lib.createFrameworkRuntime("adamant-ModpackFramework")

function GetRuntimeLiveHosts()
    local runtimeRoot = assert(AdamantModpackLib_Runtime, "Lib runtime missing")
    local registry = assert(runtimeRoot.registry, "Lib registry missing")
    local hosts = assert(registry.hosts, "host registry missing")
    return assert(hosts.live, "runtime live hosts missing")
end

function SetRuntimeLiveHost(pluginGuid, host)
    local liveHosts = GetRuntimeLiveHosts()
    local previousHost = liveHosts[pluginGuid]
    liveHosts[pluginGuid] = host
    return previousHost
end

LibStorage = setmetatable({}, {
    __index = function(_, key)
        return assert(LibTestImports["core/storage/00_init.lua"], "LibStorage test service missing")[key]
    end,
    __newindex = function(_, key, value)
        assert(LibTestImports["core/storage/00_init.lua"], "LibStorage test service missing")[key] = value
    end,
})
LibModuleState = setmetatable({}, {
    __index = function(_, key)
        return assert(LibTestImports["core/module_state/00_init.lua"], "LibModuleState test service missing")[key]
    end,
    __newindex = function(_, key, value)
        assert(LibTestImports["core/module_state/00_init.lua"], "LibModuleState test service missing")[key] = value
    end,
})
LibModuleHost = setmetatable({}, {
    __index = function(_, key)
        return assert(LibTestImports["core/module_bootstrap/host.lua"], "LibModuleHost test service missing")[key]
    end,
    __newindex = function(_, key, value)
        assert(LibTestImports["core/module_bootstrap/host.lua"], "LibModuleHost test service missing")[key] = value
    end,
})
local function GetLibOverlayService()
    local bundle = assert(LibTestImports["core/overlays/00_init.lua"], "LibOverlays test bundle missing")
    return assert(bundle.service, "LibOverlays test service missing")
end

local function GetLibOverlayState()
    return assert(LibTestImports["core/overlays/registry.lua"], "LibOverlays test registry missing")
end

LibOverlays = setmetatable({}, {
    __index = function(_, key)
        local state = GetLibOverlayState()
        if key == "uiSuppressors" or key == "nextUiSuppressorId" then
            return state[key]
        end
        return GetLibOverlayService()[key]
    end,
    __newindex = function(_, key, value)
        local state = GetLibOverlayState()
        if key == "uiSuppressors" or key == "nextUiSuppressorId" then
            state[key] = value
            return
        end
        GetLibOverlayService()[key] = value
    end,
})

function CreateModuleState(config, definition)
    local state = LibModuleState.create(config, definition)
    return state.persistentState, state.stagedState
end

import = function(path, fenv, ...)
    local chunk = assert(loadfile("src/" .. path, "t", fenv or _ENV))
    return chunk(...)
end

dofile("src/main.lua")
FrameworkPackRegistry = FrameworkPackRegistry or {}
rom.mods['adamant-ModpackFramework'] = public
FrameworkTestApi = setmetatable({}, {
    __index = function(_, key)
        return public[key]
    end,
    __newindex = function(_, key, value)
        rawset(public, key, value)
    end,
})

local function makeFrameworkImportEnv(importOverrides)
    local env = {}

    local function importWithOverrides(path, fenv, ...)
        local override = importOverrides and importOverrides[path] or nil
        if override ~= nil then
            return override
        end

        local chunk = assert(loadfile("src/" .. path, "t", fenv or env))
        return chunk(...)
    end

    env.import = importWithOverrides
    return setmetatable(env, {
        __index = _ENV,
    })
end

local function mapConstructorOverrides(constructors)
    constructors = constructors or {}
    local importOverrides = {}
    local constructorPaths = {
        createModuleRegistry = "core/modules/registry.lua",
        createConfigHash = "core/hash/config_hash.lua",
        createHud = "core/hud/runtime.lua",
        createUI = "core/ui/window.lua",
        createTheme = "core/ui/theme.lua",
    }

    for name, path in pairs(constructorPaths) do
        if constructors[name] ~= nil then
            importOverrides[path] = constructors[name]
        end
    end

    return importOverrides
end

function CreateFrameworkHarness(opts)
    opts = opts or {}
    local harnessRom = opts.rom or rom
    local harnessFrameworkRuntime = opts.frameworkRuntime or defaultFrameworkRuntime
    local env = makeFrameworkImportEnv(mapConstructorOverrides(opts.constructors))
    local frameworkCore = assert(loadfile("src/core/init.lua", "t", env))({
        rom = harnessRom,
        frameworkRuntime = harnessFrameworkRuntime,
    })

    return {
        rom = harnessRom,
        frameworkRuntime = harnessFrameworkRuntime,
        packRegistry = FrameworkPackRegistry,
        registerCoordinator = frameworkCore.registerCoordinator,
        createPack = frameworkCore.createPack,
        createPackOrThrow = frameworkCore.createPackOrThrow,
        createGuiCallbacks = frameworkCore.createGuiCallbacks,
    }
end
local logging = import("core/logging.lua")
local createHashGroupBuilder = import("core/hash/group_builder.lua")
local createModuleRegistry = import("core/modules/registry.lua", nil, {
    rom = rom,
    logging = logging,
})
local createTheme = import("core/ui/theme.lua", nil, {
    rom = rom,
})
local hashCodec = import("core/hash/codec.lua")
local createConfigHash = import("core/hash/config_hash.lua", nil, {
    rom = rom,
    hashCodec = hashCodec,
    createHashGroupBuilder = createHashGroupBuilder,
    logging = logging,
})
local createHud = import("core/hud/runtime.lua")
local createUI = import("core/ui/window.lua", nil, {
    rom = rom,
    logging = logging,
})

local function createDefaultFrameworkRuntime()
    return {
        diagnostics = defaultFrameworkRuntime.diagnostics,
        hashing = defaultFrameworkRuntime.hashing,
        modules = defaultFrameworkRuntime.modules,
        overlays = {
            order = {
                framework = 0,
                module = 1000,
                debug = 2000,
            },
            define = function()
                return true
            end,
        },
        ui = {
            suppressOverlays = function()
                return {
                    release = function() end,
                }
            end,
            areOverlaysSuppressed = function()
                return false
            end,
        },
    }
end

local function createTestUI(moduleRegistry, hud, theme, config, packId, windowTitle, numProfiles,
                            defaultProfiles, drawPackQuickContent, auditSavedProfiles, frameworkRuntime)
    return createUI(moduleRegistry, hud, theme, config, packId, windowTitle, numProfiles, defaultProfiles,
        drawPackQuickContent, auditSavedProfiles, frameworkRuntime or createDefaultFrameworkRuntime())
end

local function createTestHud(packId, packIndex, configHash, theme, config, hideHashMarker, frameworkRuntime)
    return createHud(packId, packIndex, configHash, theme, config, hideHashMarker,
        frameworkRuntime or createDefaultFrameworkRuntime())
end

rawset(FrameworkTestApi, "createHashGroupBuilder", function(hashing)
    return createHashGroupBuilder(hashing or defaultFrameworkRuntime.hashing)
end)
rawset(FrameworkTestApi, "createModuleRegistry", function(packId, testConfig, frameworkRuntime)
    return createModuleRegistry(packId, testConfig, frameworkRuntime or createDefaultFrameworkRuntime())
end)
rawset(FrameworkTestApi, "createTheme", createTheme)
rawset(FrameworkTestApi, "createConfigHash", function(moduleRegistry, testConfig, packId, hashing)
    return createConfigHash(moduleRegistry, testConfig, packId, hashing or defaultFrameworkRuntime.hashing)
end)
rawset(FrameworkTestApi, "createHud", createTestHud)
rawset(FrameworkTestApi, "createUI", createTestUI)
rawset(FrameworkTestApi, "logging", logging)
rawset(FrameworkTestApi, "createUIRuntime", function(ctx)
    local runtimeCtx = {}
    for key, value in pairs(ctx) do
        runtimeCtx[key] = value
    end
    runtimeCtx.lib = runtimeCtx.lib or lib
    runtimeCtx.rom = runtimeCtx.rom or rom
    return import("core/ui/runtime.lua", nil, runtimeCtx)
end)
local profileTools = import("core/profiles/audit.lua", nil, {
    hashCodec = hashCodec,
    createHashGroupBuilder = createHashGroupBuilder,
    logging = logging,
})
rawset(FrameworkTestApi, "normalizeProfiles", profileTools.normalizeProfiles)
rawset(FrameworkTestApi, "auditSavedProfiles", function(packId, profileSlots, moduleRegistry, hashing)
    return profileTools.auditSavedProfiles(packId, profileSlots, moduleRegistry, hashing or defaultFrameworkRuntime.hashing)
end)

config = { ModEnabled = true, DebugMode = false }

MockModuleRegistry = {}

local function prepareDefinition(definition)
    return LibModuleHost.prepareDefinition({}, definition)
end

local function makePersistedConfig(storage, overrides)
    local persisted = {
        Enabled = false,
        DebugMode = false,
    }
    local transientAliases = {}
    for _, root in ipairs(storage or {}) do
        if root.persist == false then
            transientAliases[root.alias] = true
        else
            persisted[root.alias] = overrides and overrides[root.alias] or root.default
        end
    end
    if overrides then
        for key, value in pairs(overrides) do
            if persisted[key] == nil and not transientAliases[key] then
                persisted[key] = value
            end
        end
    end
    return persisted
end

function MockModuleRegistry.create(moduleDefs)
    moduleDefs = moduleDefs or {}

    local moduleRegistry = {
        modules = {},
        modulesById = {},
        modulesWithQuickContent = {},
        tabOrder = {},
        live = {},
        snapshot = {},
    }

    local function addModule(def)
        local persisted = makePersistedConfig(def.storage, def.values)
        persisted.Enabled = def.enabled == true
        persisted.DebugMode = def.debug == true

        local definition = prepareDefinition({
            id = def.id,
            name = def.name or def.id,
            modpack = def.modpack or "test-pack",
            storage = def.storage or {},
            hashGroupPlan = def.hashGroupPlan,
            shortName = def.shortName,
            tooltip = def.tooltip,
        })
        local persistentState, stagedState = CreateModuleState(persisted, definition)
        local pluginGuid = def.pluginGuid or ("adamant-" .. def.id)
        local host, authorHost = LibModuleHost.create({
            pluginGuid = pluginGuid,
            definition = definition,
            persistentState = persistentState,
            stagedState = stagedState,
            drawTab = def.DrawTab or function() end,
            drawQuickContent = def.DrawQuickContent,
        })
        if def.patchPlan ~= nil then
            authorHost.mutation.patch(def.patchPlan)
        end
        authorHost.activate()
        local module = {
            pluginGuid = pluginGuid,
            mod = {
                definition = definition,
                host = host,
            },
            definition = definition,
            id = definition.id,
            name = definition.name,
            shortName = definition.shortName,
            tooltip = definition.tooltip,
            modpack = definition.modpack,
            affectsRunData = host.affectsRunData(),
            hashHints = definition.hashGroupPlan,
            storage = definition.storage,
        }

        rom.mods[module.pluginGuid] = module.mod

        table.insert(moduleRegistry.modules, module)
        moduleRegistry.modulesById[module.id] = module

        if type(host.drawQuickContent) == "function" then
            table.insert(moduleRegistry.modulesWithQuickContent, module)
        end

        module._tabLabel = definition.shortName or definition.name
        table.insert(moduleRegistry.tabOrder, module)
    end

    for _, def in ipairs(moduleDefs) do
        addModule(def)
    end

    function moduleRegistry.live.captureSnapshot()
        local snapshot = {
            hosts = {},
        }

        for _, module in ipairs(moduleRegistry.modules) do
            local liveHost = defaultFrameworkRuntime.modules.getLiveHost(module.pluginGuid)
            snapshot.hosts[module] = liveHost or false
        end

        return snapshot
    end

    function moduleRegistry.live.getHost(entry)
        return defaultFrameworkRuntime.modules.getLiveHost(entry.pluginGuid)
    end

    function moduleRegistry.snapshot.getHost(entry, snapshot)
        local host = snapshot.hosts[entry]
        return host or nil
    end

    function moduleRegistry.snapshot.isEntryEnabled(entry, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        return host.read("Enabled") == true
    end

    function moduleRegistry.snapshot.setEntryEnabled(entry, enabled, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        return host.setEnabled(enabled)
    end

    function moduleRegistry.snapshot.suspendForPackDisable(entry, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        return host.suspendForPackDisable()
    end

    function moduleRegistry.snapshot.ensureSuspendedForPackDisable(entry, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        return host.ensureSuspendedForPackDisable()
    end

    function moduleRegistry.snapshot.restoreForPackEnable(entry, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        return host.restoreForPackEnable()
    end

    function moduleRegistry.snapshot.rollbackPackTransition(entry, receipt, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        return host.rollbackPackTransition(receipt)
    end

    function moduleRegistry.snapshot.restorePackTransitionState(entry, receipt, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        return host.restorePackTransitionState(receipt)
    end

    function moduleRegistry.snapshot.getStorageValue(module, alias, snapshot)
        local host = moduleRegistry.snapshot.getHost(module, snapshot)
        return host.read(alias)
    end

    function moduleRegistry.snapshot.setStorageValue(module, alias, value, snapshot)
        local host = moduleRegistry.snapshot.getHost(module, snapshot)
        return host.writeAndFlush(alias, value)
    end

    function moduleRegistry.snapshot.isDebugEnabled(entry, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        return host.read("DebugMode") == true
    end

    function moduleRegistry.snapshot.setDebugEnabled(entry, value, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        host.setDebugMode(value)
    end

    return moduleRegistry
end
