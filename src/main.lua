-- =============================================================================
-- ADAMANT-MODPACK-FRAMEWORK
-- =============================================================================
-- Reusable modpack orchestration library: discovery, hash, HUD, and UI.
--
-- Usage (from a coordinator mod's main.lua):
--
--   local Framework = rom.mods['adamant-ModpackFramework']
--   Framework.init({
--       packId      = "speedrun",
--       windowTitle = "Speedrun Modpack",
--       config      = config,    -- coordinator's Chalk config
--       def         = def,       -- { NUM_PROFILES, defaultProfiles }
--       modutil     = modutil,
--   })
--
-- Framework.init can be called on every hot reload; subsequent calls update subsystem
-- instances in place. GUI registration is the coordinator's responsibility:
--   rom.gui.add_imgui(Framework.getRenderer(packId))
--   rom.gui.add_to_menu_bar(Framework.getMenuBar(packId))

local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
Framework = {}
AdamantModpackFramework_Internal = AdamantModpackFramework_Internal or {}
local internal = AdamantModpackFramework_Internal
internal.packs = internal.packs or {}
internal.packList = internal.packList or {}
internal.callbacks = internal.callbacks or {}
internal.frameworkGeneration = (internal.frameworkGeneration or 0) + 1

import "ui_theme.lua"
import "discovery.lua"
import "hash.lua"
import "hud.lua"
import "ui.lua"

local _packs = internal.packs
local _packList = internal.packList

local function GetCurrentFramework()
    return rom.mods["adamant-ModpackFramework"]
end

local function ValidateInitParams(params)
    assert(type(params) == "table", "Framework.init: params must be a table")
    assert(type(params.packId) == "string" and params.packId ~= "",
        "Framework.init: packId must be a non-empty string")
    assert(type(params.windowTitle) == "string" and params.windowTitle ~= "",
        "Framework.init: windowTitle must be a non-empty string")
    assert(type(params.config) == "table", "Framework.init: config must be a table")
    assert(type(params.def) == "table", "Framework.init: def must be a table")
    assert(params.hideHashMarker == nil or type(params.hideHashMarker) == "boolean",
        "Framework.init: hideHashMarker must be a boolean when provided")
    assert(type(params.config.ModEnabled) == "boolean",
        "Framework.init: config.ModEnabled must be a boolean")
    assert(type(params.config.DebugMode) == "boolean",
        "Framework.init: config.DebugMode must be a boolean")
    assert(type(params.config.Profiles) == "table",
        "Framework.init: config.Profiles must be a table")

    local numProfiles = params.def.NUM_PROFILES
    assert(type(numProfiles) == "number" and numProfiles > 0 and math.floor(numProfiles) == numProfiles,
        "Framework.init: def.NUM_PROFILES must be a positive integer")
    assert(type(params.def.defaultProfiles) == "table",
        "Framework.init: def.defaultProfiles must be a table")

    for i = 1, numProfiles do
        local profile = params.config.Profiles[i]
        assert(type(profile) == "table",
            string.format(
                "Framework.init: config.Profiles[%d] is missing; ensure config.lua declares all %d profile entries",
                i, numProfiles))
        profile.Name = profile.Name or ""
        profile.Hash = profile.Hash or ""
        profile.Tooltip = profile.Tooltip or ""
    end
end

--- Scan saved profiles against the current discovered key surface.
--- Warns when a profile contains a field key for a known module that
--- no longer exists, indicating a likely rename. Namespaces absent from discovery
--- are skipped silently because "not installed" and "renamed" are indistinguishable.
local function AuditSavedProfiles(packId, profiles, discovery, lib)
    local knownModules = {}

    for _, m in ipairs(discovery.modules) do
        local fields = {}
        if m.storage then
            for _, root in ipairs(m.storage) do
                if root._isRoot and root.alias ~= nil then
                    fields[tostring(root.alias)] = true
                end
            end
        end
        knownModules[m.id] = fields
    end

    for i, profile in ipairs(profiles) do
        local hash = profile.Hash
        if hash and hash ~= "" then
            local profileLabel = (profile.Name ~= "" and profile.Name) or ("slot " .. i)
            for entry in string.gmatch(hash .. "|", "([^|]*)|") do
                local key = string.match(entry, "^([^=]+)=")
                if key and key ~= "_v" then
                    local namespace, field = string.match(key, "^([^.]+)%.(.+)$")
                    if not namespace then
                        namespace = key
                        field = nil
                    end

                    if field then
                        local moduleFields = knownModules[namespace]
                        if moduleFields and not moduleFields[field] then
                            lib.logging.warn(packId,
                                "Profile '%s': unrecognized key '%s.%s' - possible rename or removed option",
                                profileLabel, namespace, field)
                        end
                    end
                end
            end
        end
    end
end

Framework.auditSavedProfiles = AuditSavedProfiles

local function RememberInitParams(params)
    return {
        packId = params.packId,
        windowTitle = params.windowTitle,
        config = params.config,
        def = params.def,
        hideHashMarker = params.hideHashMarker,
    }
end

function Framework.init(params)
    local lib = rom.mods["adamant-ModpackLib"]
    ValidateInitParams(params)

    lib.lifecycle.registerCoordinator(params.packId, params.config)
    import_as_fallback(rom.game)

    local packIndex = _packs[params.packId] and _packs[params.packId]._index or nil
    if not packIndex then
        table.insert(_packList, params.packId)
        packIndex = #_packList
    end

    local discovery = Framework.createDiscovery(params.packId, params.config, lib)
    local hash = Framework.createHash(discovery, params.config, lib, params.packId)
    local theme = Framework.createTheme(lib)

    discovery.run(params.def and params.def.moduleOrder)
    for _, entry in ipairs(discovery.modules) do
        local ok, err = entry.host.applyOnLoad()
        if not ok then
            lib.logging.warn("%s startup lifecycle failed: %s",
                tostring(entry.name or entry.id or "module"),
                tostring(err))
        end
    end

    AuditSavedProfiles(params.packId, params.config.Profiles, discovery, lib)

    local hud = Framework.createHud(params.packId, packIndex, hash, theme, params.config, lib,
        params.hideHashMarker == true)
    local ui = Framework.createUI(discovery, hud, theme, params.def, params.config, lib, params.packId,
        params.windowTitle)

    _packs[params.packId] = {
        discovery = discovery,
        hash = hash,
        hud = hud,
        ui = ui,
        initParams = RememberInitParams(params),
        frameworkGeneration = internal.frameworkGeneration,
        moduleRegistryVersion = lib.getModuleRegistryVersion(params.packId),
        _index = packIndex,
    }

    if params.config.ModEnabled then
        hud.setModMarker(true)
    end

    return _packs[params.packId]
end

public.init = Framework.init

local function EnsurePackCurrent(packId)
    local pack = _packs[packId]
    if not pack or not pack.initParams then
        return pack
    end

    local lib = rom.mods["adamant-ModpackLib"]
    if not lib or type(lib.getModuleRegistryVersion) ~= "function" then
        return pack
    end

    local currentVersion = lib.getModuleRegistryVersion(packId)
    local currentGeneration = internal.frameworkGeneration or 0
    if currentVersion ~= pack.moduleRegistryVersion or pack.frameworkGeneration ~= currentGeneration then
        local framework = GetCurrentFramework()
        local init = framework and framework.init
        if type(init) == "function" then
            return init(pack.initParams)
        end
    end

    return pack
end

local function GetStableCallback(kind, packId, factory)
    local callbacks = internal.callbacks
    local key = tostring(packId)
    local bucket = callbacks[kind]
    if not bucket then
        bucket = {}
        callbacks[kind] = bucket
    end

    local callback = bucket[key]
    if callback then
        return callback
    end

    callback = factory(packId)
    bucket[key] = callback
    return callback
end

public.getRenderer = function(packId)
    return GetStableCallback("renderer", packId, function(currentPackId)
        return function()
            local pack = EnsurePackCurrent(currentPackId)
            if not pack or not pack.ui then
                return
            end
            pack.ui.renderWindow()
        end
    end)
end

public.getMenuBar = function(packId)
    return GetStableCallback("menuBar", packId, function(currentPackId)
        return function()
            local pack = EnsurePackCurrent(currentPackId)
            if not pack or not pack.ui then
                return
            end
            pack.ui.addMenuBar()
        end
    end)
end

public.getAlwaysDrawRenderer = function(packId)
    return GetStableCallback("alwaysDraw", packId, function(currentPackId)
        local wasGuiOpen = rom.gui.is_open() == true

        return function()
            local pack = EnsurePackCurrent(currentPackId)
            local isGuiOpen = rom.gui.is_open() == true

            if wasGuiOpen and not isGuiOpen then
                if pack and pack.hud then
                    pack.hud.flushPendingHash()
                end
            end

            wasGuiOpen = isGuiOpen
        end
    end)
end
