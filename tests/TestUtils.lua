-- =============================================================================
-- Test utilities: mock engine globals and load Framework for testing
-- =============================================================================

public = {}
_PLUGIN = { guid = "test-framework" }

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

ScreenData = {
    HUD = {
        ComponentData = {},
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

import = function(path, fenv, ...)
    local chunk = assert(loadfile("../adamant-ModpackLib/src/" .. path, "t", fenv or _ENV))
    return chunk(...)
end

Warnings = {}

function CaptureWarnings()
    Warnings = {}
    lib.config.DebugMode = true
    _originalPrint = print
    print = function(msg)
        table.insert(Warnings, msg)
    end
end

function RestoreWarnings()
    lib.config.DebugMode = false
    print = _originalPrint or print
    Warnings = {}
end

dofile("../adamant-ModpackLib/src/main.lua")
lib = public
rom.mods['adamant-ModpackLib'] = lib

function CreateModuleState(config, definition)
    local state = AdamantModpackLib_Internal.moduleState.create(config, definition)
    return state.store, state.session
end

import = function(path, fenv, ...)
    local chunk = assert(loadfile("src/" .. path, "t", fenv or _ENV))
    return chunk(...)
end
import_as_fallback = function() end

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

local function GetBootConstructors()
    local index = 1
    while true do
        local name, value = debug.getupvalue(public.init, index)
        if not name then
            break
        end
        if name == "bootConstructors" then
            return value
        end
        index = index + 1
    end
    error("public.init missing bootConstructors upvalue")
end

rawset(FrameworkTestApi, "withBootConstructors", function(overrides, body)
    local bootConstructors = GetBootConstructors()
    local previousConstructors = {}
    local keys = {}
    for key in pairs(overrides) do
        table.insert(keys, key)
        previousConstructors[key] = bootConstructors[key]
        bootConstructors[key] = overrides[key]
    end

    local ok, result = pcall(body)

    for _, key in ipairs(keys) do
        bootConstructors[key] = previousConstructors[key]
    end

    if not ok then
        error(result)
    end
    return result
end)
local logging = import("logging.lua")
local createHashGroupBuilder = import("hash_group_builder.lua", nil, {
    logging = logging,
})
local createModuleRegistry = import("module_registry.lua", nil, {
    logging = logging,
})
local createTheme = import("ui/theme.lua")
local hashCodec = import("hash_codec.lua")
local createConfigHash = import("config_hash.lua", nil, {
    hashCodec = hashCodec,
    createHashGroupBuilder = createHashGroupBuilder,
    logging = logging,
})
local createHud = import("hud.lua")
local createUI = import("ui.lua", nil, {
    logging = logging,
})

rawset(FrameworkTestApi, "createHashGroupBuilder", createHashGroupBuilder)
rawset(FrameworkTestApi, "createModuleRegistry", createModuleRegistry)
rawset(FrameworkTestApi, "createTheme", createTheme)
rawset(FrameworkTestApi, "createConfigHash", createConfigHash)
rawset(FrameworkTestApi, "createHud", createHud)
rawset(FrameworkTestApi, "createUI", createUI)
rawset(FrameworkTestApi, "logging", logging)
rawset(FrameworkTestApi, "createUIRuntime", function(ctx)
    return import("ui/runtime.lua", nil, ctx)
end)
local profileTools = import("profiles.lua", nil, {
    hashCodec = hashCodec,
    createHashGroupBuilder = createHashGroupBuilder,
    logging = logging,
})
rawset(FrameworkTestApi, "normalizeProfiles", profileTools.normalizeProfiles)
rawset(FrameworkTestApi, "auditSavedProfiles", profileTools.auditSavedProfiles)

config = { ModEnabled = true, DebugMode = false }

MockModuleRegistry = {}

local function prepareDefinition(definition)
    return AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, definition)
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
        if root.stage == false then
            transientAliases[root.alias] = true
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
        local store, session = CreateModuleState(persisted, definition)
        local pluginGuid = def.pluginGuid or ("adamant-" .. def.id)
        local host, authorHost = AdamantModpackLib_Internal.moduleHost.create({
            pluginGuid = pluginGuid,
            definition = definition,
            store = store,
            session = session,
            drawTab = def.DrawTab or function() end,
            drawQuickContent = def.DrawQuickContent,
            registerPatchMutation = def.patchPlan,
        })
        authorHost.tryActivate()
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
            local liveHost = lib.getLiveModuleHost(module.pluginGuid)
            snapshot.hosts[module] = liveHost or false
        end

        return snapshot
    end

    function moduleRegistry.live.getHost(entry)
        return lib.getLiveModuleHost(entry.pluginGuid)
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
