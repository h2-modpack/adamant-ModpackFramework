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

import = function(path)
    dofile("../adamant-ModpackLib/src/" .. path)
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

import = function() end
import_as_fallback = function() end

dofile("src/main.lua")
AdamantModpackFramework_Internal = AdamantModpackFramework_Internal or {}
setmetatable(public, {
    __index = Framework,
})
rom.mods['adamant-ModpackFramework'] = public
FrameworkTestApi = setmetatable({}, {
    __index = function(_, key)
        local internal = AdamantModpackFramework_Internal
        if internal[key] ~= nil then
            return internal[key]
        end
        if Framework and Framework[key] ~= nil then
            return Framework[key]
        end
        return public[key]
    end,
    __newindex = function(_, key, value)
        AdamantModpackFramework_Internal[key] = value
        if type(Framework) == "table" then
            Framework[key] = value
        end
    end,
})
rawset(FrameworkTestApi, "withFactories", function(overrides, body)
    local previousInternal = {}
    local previousFramework = {}
    local keys = {}
    for key in pairs(overrides) do
        table.insert(keys, key)
        previousInternal[key] = AdamantModpackFramework_Internal[key]
        previousFramework[key] = Framework and Framework[key] or nil
        AdamantModpackFramework_Internal[key] = overrides[key]
        if type(Framework) == "table" then
            Framework[key] = overrides[key]
        end
    end

    local ok, result = pcall(body)

    for _, key in ipairs(keys) do
        AdamantModpackFramework_Internal[key] = previousInternal[key]
        if type(Framework) == "table" then
            Framework[key] = previousFramework[key]
        end
    end

    if not ok then
        error(result)
    end
    return result
end)
dofile("src/ui/theme.lua")
dofile("src/profiles.lua")
dofile("src/discovery.lua")
dofile("src/hash.lua")
dofile("src/ui/runtime.lua")
dofile("src/ui/profiles.lua")
dofile("src/ui/dev.lua")
dofile("src/ui/quick_setup.lua")
dofile("src/ui/module_tabs.lua")
dofile("src/ui.lua")

config = { ModEnabled = true, DebugMode = false }

MockDiscovery = {}

local function prepareDefinition(definition)
    return lib.prepareDefinition({}, definition)
end

local function makePersistedConfig(storage, overrides)
    local persisted = {
        Enabled = false,
        DebugMode = false,
    }
    local transientAliases = {}
    for _, root in ipairs(storage or {}) do
        if root.lifetime ~= "transient" then
            persisted[root.configKey] = overrides and overrides[root.alias] or root.default
        else
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

function MockDiscovery.create(moduleDefs)
    moduleDefs = moduleDefs or {}

    local discovery = {
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
            affectsRunData = def.affectsRunData == true,
            apply = def.apply,
            revert = def.revert,
            patchPlan = def.patchPlan,
            shortName = def.shortName,
            tooltip = def.tooltip,
        })
        local store, session = lib.createStore(persisted, definition)
        local host = lib.createModuleHost({
            definition = definition,
            store = store,
            session = session,
            drawTab = def.DrawTab,
            drawQuickContent = def.DrawQuickContent,
        })
        local module = {
            modName = def.modName or ("adamant-" .. def.id),
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
            affectsRunData = definition.affectsRunData == true,
            hashHints = definition.hashGroupPlan,
            storage = definition.storage,
        }

        rom.mods[module.modName] = module.mod

        table.insert(discovery.modules, module)
        discovery.modulesById[module.id] = module

        if host.hasQuickContent() then
            table.insert(discovery.modulesWithQuickContent, module)
        end

        module._tabLabel = definition.shortName or definition.name
        table.insert(discovery.tabOrder, module)
    end

    for _, def in ipairs(moduleDefs) do
        addModule(def)
    end

    function discovery.live.captureSnapshot()
        local snapshot = {
            hosts = {},
        }

        for _, module in ipairs(discovery.modules) do
            local mod = rom.mods[module.modName]
            local liveHost = type(mod) == "table" and type(mod.host) == "table" and mod.host or nil
            snapshot.hosts[module] = liveHost or false
        end

        return snapshot
    end

    function discovery.live.getHost(entry)
        local mod = rom.mods[entry.modName]
        local liveHost = type(mod) == "table" and type(mod.host) == "table" and mod.host or nil
        return liveHost
    end

    function discovery.snapshot.getHost(entry, snapshot)
        local host = snapshot.hosts[entry]
        return host or nil
    end

    function discovery.snapshot.isEntryEnabled(entry, snapshot)
        local host = discovery.snapshot.getHost(entry, snapshot)
        return host.read("Enabled") == true
    end

    function discovery.snapshot.setEntryEnabled(entry, enabled, snapshot)
        local host = discovery.snapshot.getHost(entry, snapshot)
        return host.setEnabled(enabled)
    end

    function discovery.snapshot.getStorageValue(module, aliasOrKey, snapshot)
        local host = discovery.snapshot.getHost(module, snapshot)
        return host.read(aliasOrKey)
    end

    function discovery.snapshot.setStorageValue(module, aliasOrKey, value, snapshot)
        local host = discovery.snapshot.getHost(module, snapshot)
        return host.writeAndFlush(aliasOrKey, value)
    end

    function discovery.snapshot.isDebugEnabled(entry, snapshot)
        local host = discovery.snapshot.getHost(entry, snapshot)
        return host.read("DebugMode") == true
    end

    function discovery.snapshot.setDebugEnabled(entry, value, snapshot)
        local host = discovery.snapshot.getHost(entry, snapshot)
        host.setDebugMode(value)
    end

    return discovery
end
