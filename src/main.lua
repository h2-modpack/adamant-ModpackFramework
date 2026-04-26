-- =============================================================================
-- ADAMANT-MODPACK-FRAMEWORK
-- =============================================================================

local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
Framework = {}
AdamantModpackFramework_Internal = AdamantModpackFramework_Internal or {}

local internal = AdamantModpackFramework_Internal
internal.packs = internal.packs or {}
internal.packList = internal.packList or {}
internal.frameworkGeneration = internal.frameworkGeneration or 0

import "ui/theme.lua"
import "discovery.lua"
import "hash.lua"
import "hud.lua"
import "ui.lua"

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

    local numProfiles = params.def.NUM_PROFILES
    assert(type(numProfiles) == "number" and numProfiles > 0 and math.floor(numProfiles) == numProfiles,
        "Framework.init: def.NUM_PROFILES must be a positive integer")
    assert(type(params.def.defaultProfiles) == "table",
        "Framework.init: def.defaultProfiles must be a table")

    internal.normalizeProfiles(params.config.Profiles, numProfiles)
end

function Framework.auditSavedProfiles(packId, profiles, discovery, lib)
    return internal.auditSavedProfiles(packId, profiles, discovery, lib)
end

local function EnsurePackCurrent(packId)
    local pack = internal.packs[packId]
    if not pack then
        return nil
    end
    if pack._generation ~= internal.frameworkGeneration and type(pack._params) == "table" then
        pack = Framework.init(pack._params)
    end
    return pack
end

function Framework.init(params)
    local lib = rom.mods["adamant-ModpackLib"]
    ValidateInitParams(params)

    lib.lifecycle.registerCoordinator(params.packId, params.config)
    import_as_fallback(rom.game)

    local packIndex = internal.packs[params.packId] and internal.packs[params.packId]._index or nil
    if not packIndex then
        table.insert(internal.packList, params.packId)
        packIndex = #internal.packList
    end

    local discovery = Framework.createDiscovery(params.packId, params.config, lib)
    local hash = Framework.createHash(discovery, params.config, lib, params.packId)
    local theme = Framework.createTheme(lib)

    discovery.run(params.def.moduleOrder)

    local startupSnapshot = discovery.live.captureSnapshot()
    local needsRunDataSetup = false
    for _, entry in ipairs(discovery.modules) do
        local host = discovery.snapshot.getHost(entry, startupSnapshot)
        if host then
            local ok, err = host.applyOnLoad()
            if not ok then
                lib.logging.warn(params.packId,
                    "%s startup lifecycle failed: %s",
                    tostring(entry.name or entry.id or "module"),
                    tostring(err))
            elseif entry.affectsRunData then
                needsRunDataSetup = true
            end
        end
    end

    if needsRunDataSetup then
        rom.game.SetupRunData()
    end

    internal.auditSavedProfiles(params.packId, params.config.Profiles, discovery, lib)

    local hud = Framework.createHud(params.packId, packIndex, hash, theme, params.config, params.modutil,
        params.hideHashMarker == true)
    local ui = Framework.createUI(discovery, hud, theme, params.def, params.config, lib, params.packId,
        params.windowTitle)

    local pack = {
        discovery = discovery,
        hash = hash,
        hud = hud,
        ui = ui,
        _index = packIndex,
        _generation = internal.frameworkGeneration,
        _params = params,
    }
    internal.packs[params.packId] = pack

    if params.config.ModEnabled then
        hud.setModMarker(true)
    end

    return pack
end

public.init = Framework.init

public.getRenderer = function(packId)
    return function()
        local pack = EnsurePackCurrent(packId)
        if not pack or not pack.ui then
            return
        end
        pack.ui.renderWindow()
    end
end

public.getMenuBar = function(packId)
    return function()
        local pack = EnsurePackCurrent(packId)
        if not pack or not pack.ui then
            return
        end
        pack.ui.addMenuBar()
    end
end

public.getAlwaysDrawRenderer = function(packId)
    local wasGuiOpen = rom.gui.is_open() == true

    return function()
        local isGuiOpen = rom.gui.is_open() == true

        if wasGuiOpen and not isGuiOpen then
            local pack = EnsurePackCurrent(packId)
            if pack then
                if pack.ui then
                    pack.ui.flushPendingRunData()
                end
                if pack.hud then
                    pack.hud.flushPendingHash()
                end
            end
        end

        wasGuiOpen = isGuiOpen
    end
end
