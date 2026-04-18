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

import "ui_theme.lua"
import "discovery.lua"
import "hash.lua"
import "hud.lua"
import "ui.lua"

local _packs = {}
local _packList = {}

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

function Framework.init(params)
    local lib = rom.mods["adamant-ModpackLib"]
    ValidateInitParams(params)

    lib.coordinator.register(params.packId, params.config)
    import_as_fallback(rom.game)

    local packIndex = _packs[params.packId] and _packs[params.packId]._index or nil
    if not packIndex then
        table.insert(_packList, params.packId)
        packIndex = #_packList
    end

    local discovery = Framework.createDiscovery(params.packId, params.config, lib)
    local hash = Framework.createHash(discovery, params.config, lib, params.packId)
    local theme = Framework.createTheme()

    discovery.run(params.def and params.def.moduleOrder)

    AuditSavedProfiles(params.packId, params.config.Profiles, discovery, lib)

    local hud = Framework.createHud(params.packId, packIndex, hash, theme, params.config, params.modutil,
        params.hideHashMarker == true)
    local ui = Framework.createUI(discovery, hud, theme, params.def, params.config, lib, params.packId,
        params.windowTitle)

    _packs[params.packId] = { discovery = discovery, hash = hash, hud = hud, ui = ui, _index = packIndex }

    if params.config.ModEnabled then
        hud.setModMarker(true)
    end

    return _packs[params.packId]
end

public.init = Framework.init

public.getRenderer = function(packId)
    return function()
        local pack = _packs[packId]
        if not pack or not pack.ui or type(pack.ui.renderWindow) ~= "function" then
            return
        end
        pack.ui.renderWindow()
    end
end

public.getMenuBar = function(packId)
    return function()
        local pack = _packs[packId]
        if not pack or not pack.ui or type(pack.ui.addMenuBar) ~= "function" then
            return
        end
        pack.ui.addMenuBar()
    end
end

public.getAlwaysDrawRenderer = function(packId)
    local wasGuiOpen = type(rom) == "table"
        and type(rom.gui) == "table"
        and type(rom.gui.is_open) == "function"
        and rom.gui.is_open() == true or false

    return function()
        local isGuiOpen = type(rom) == "table"
            and type(rom.gui) == "table"
            and type(rom.gui.is_open) == "function"
            and rom.gui.is_open() == true or false

        if wasGuiOpen and not isGuiOpen then
            local pack = _packs[packId]
            if pack and pack.hud and type(pack.hud.flushPendingHash) == "function" then
                pack.hud.flushPendingHash()
            end
        end

        wasGuiOpen = isGuiOpen
    end
end
