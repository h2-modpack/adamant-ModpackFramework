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
dofile("src/ui_theme.lua")
dofile("src/discovery.lua")
dofile("src/hash.lua")
dofile("src/ui.lua")

config = { ModEnabled = true, DebugMode = false }

MockDiscovery = {}

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
    }

    local function addModule(def)
        local persisted = makePersistedConfig(def.storage, def.values)
        persisted.Enabled = def.enabled == true
        persisted.DebugMode = def.debug == true

        local definition = {
            id = def.id,
            name = def.name or def.id,
            modpack = def.modpack or "test-pack",
            default = def.default == true,
            storage = def.storage or {},
            hashGroups = def.hashGroups,
            affectsRunData = def.affectsRunData == true,
            apply = def.apply,
            revert = def.revert,
            patchPlan = def.patchPlan,
            shortName = def.shortName,
            tooltip = def.tooltip,
        }
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
            host = host,
            definition = definition,
            id = definition.id,
            name = definition.name,
            default = definition.default,
            storage = definition.storage,
        }

        table.insert(discovery.modules, module)
        discovery.modulesById[module.id] = module

        if module.host.hasQuickContent() then
            table.insert(discovery.modulesWithQuickContent, module)
        end

        module._tabLabel = definition.shortName or definition.name
        table.insert(discovery.tabOrder, module)
    end

    for _, def in ipairs(moduleDefs) do
        addModule(def)
    end

    function discovery.isModuleEnabled(module)
        return module.host.read("Enabled") == true
    end

    function discovery.isEntryEnabled(entry)
        return discovery.isModuleEnabled(entry)
    end

    function discovery.setModuleEnabled(module, enabled)
        return module.host.setEnabled(enabled)
    end

    function discovery.setEntryEnabled(entry, enabled)
        return discovery.setModuleEnabled(entry, enabled)
    end

    function discovery.getStorageValue(module, aliasOrKey)
        return module.host.read(aliasOrKey)
    end

    function discovery.setStorageValue(module, aliasOrKey, value)
        return module.host.writeAndFlush(aliasOrKey, value)
    end

    function discovery.isDebugEnabled(entry)
        return entry.host.read("DebugMode") == true
    end

    function discovery.setDebugEnabled(entry, value)
        entry.host.setDebugMode(value)
    end

    return discovery
end


