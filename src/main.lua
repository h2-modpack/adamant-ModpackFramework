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
--   })
--
-- Framework.init can be called on every hot reload; subsequent calls update subsystem
-- instances in place. GUI registration is the coordinator's responsibility:
--   rom.gui.add_imgui(Framework.getRenderer(packId))
--   rom.gui.add_always_draw_imgui(Framework.getAlwaysDrawRenderer(packId))
--   rom.gui.add_to_menu_bar(Framework.getMenuBar(packId))

local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

AdamantModpackFramework_Internal = AdamantModpackFramework_Internal or {}
local internal = AdamantModpackFramework_Internal
internal.packs = internal.packs or {}
internal.packIndices = internal.packIndices or {}
internal.nextPackIndex = internal.nextPackIndex or 1
internal.callbacks = internal.callbacks or {}
internal.frameworkGeneration = (internal.frameworkGeneration or 0) + 1

import "ui/theme.lua"
import "profiles.lua"
import "discovery.lua"
import "hash.lua"
import "hud.lua"
import "ui/runtime.lua"
import "ui/profiles.lua"
import "ui/dev.lua"
import "ui/quick_setup.lua"
import "ui/module_tabs.lua"
import "ui.lua"

local _packs = internal.packs
local _packIndices = internal.packIndices

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

    local numProfiles = params.def.NUM_PROFILES
    assert(type(numProfiles) == "number" and numProfiles > 0 and math.floor(numProfiles) == numProfiles,
        "Framework.init: def.NUM_PROFILES must be a positive integer")
    assert(type(params.def.defaultProfiles) == "table",
        "Framework.init: def.defaultProfiles must be a table")

    internal.normalizeProfiles(params.config.Profiles, numProfiles)
end

local function RememberInitParams(params)
    return {
        packId = params.packId,
        windowTitle = params.windowTitle,
        config = params.config,
        def = params.def,
        hideHashMarker = params.hideHashMarker,
    }
end

function public.init(params)
    local lib = rom.mods["adamant-ModpackLib"]
    ValidateInitParams(params)

    lib.lifecycle.registerCoordinator(params.packId, params.config)
    import_as_fallback(rom.game)

    local packIndex = _packIndices[params.packId]
    if not packIndex then
        packIndex = internal.nextPackIndex
        internal.nextPackIndex = internal.nextPackIndex + 1
        _packIndices[params.packId] = packIndex
    end

    local discovery = internal.createDiscovery(params.packId, params.config, lib)
    local hash = internal.createHash(discovery, params.config, lib, params.packId)
    local theme = internal.createTheme(lib)

    discovery.run(params.def and params.def.moduleOrder)
    local startupSnapshot = discovery.captureHostSnapshot()
    local needsRunDataSetup = false
    for _, entry in ipairs(discovery.modules) do
        local host = discovery.getSnapshotHost(entry, startupSnapshot)
        local ok, err
        if host then
            ok, err = host.applyOnLoad()
        end
        if not ok then
            lib.logging.warn(params.packId, "%s startup lifecycle failed: %s",
                tostring(entry.name or entry.id or "module"),
                tostring(err))
        elseif lib.lifecycle.mutatesRunData(entry.definition) then
            needsRunDataSetup = true
        end
    end
    if needsRunDataSetup then
        rom.game.SetupRunData()
    end

    internal.auditSavedProfiles(params.packId, params.config.Profiles, discovery, lib)

    local hud = internal.createHud(params.packId, packIndex, hash, theme, params.config, lib,
        params.hideHashMarker == true)
    local ui = internal.createUI(discovery, hud, theme, params.def, params.config, lib, params.packId,
        params.windowTitle)

    _packs[params.packId] = {
        discovery = discovery,
        hash = hash,
        hud = hud,
        ui = ui,
        initParams = RememberInitParams(params),
        frameworkGeneration = internal.frameworkGeneration,
        packIndex = packIndex,
    }

    if params.config.ModEnabled then
        hud.setModMarker(true)
    end

    return _packs[params.packId]
end

local function EnsurePackCurrent(packId)
    local pack = _packs[packId]
    if not pack or not pack.initParams then
        return pack
    end

    local currentGeneration = internal.frameworkGeneration or 0
    if pack.frameworkGeneration ~= currentGeneration then
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
                if pack and pack.ui and type(pack.ui.flushPendingRunData) == "function" then
                    pack.ui.flushPendingRunData()
                end
                if pack and pack.hud then
                    pack.hud.flushPendingHash()
                end
            end

            wasGuiOpen = isGuiOpen
        end
    end)
end
