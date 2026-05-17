local logging = import "logging.lua"
local hashCodec = import "hash_codec.lua"
local createTheme = import "ui/theme.lua"
local createModuleRegistry = import("module_registry.lua", nil, {
    logging = logging,
})
local createHashGroupBuilder = import("hash_group_builder.lua", nil, {
    logging = logging,
})
local profileTools = import("profiles.lua", nil, {
    hashCodec = hashCodec,
    createHashGroupBuilder = createHashGroupBuilder,
    logging = logging,
})
local createConfigHash = import("config_hash.lua", nil, {
    hashCodec = hashCodec,
    createHashGroupBuilder = createHashGroupBuilder,
    logging = logging,
})
local createHud = import "hud.lua"
local createUI = import("ui.lua", nil, {
    logging = logging,
})

local bootConstructors = {
    createModuleRegistry = createModuleRegistry,
    createConfigHash = createConfigHash,
    createHud = createHud,
    createUI = createUI,
    createTheme = createTheme,
}

local function ValidateInitArgs(packId, windowTitle, config, numProfiles, defaultProfiles, opts)
    assert(type(packId) == "string" and packId ~= "",
        "Framework.init: packId must be a non-empty string")
    assert(type(windowTitle) == "string" and windowTitle ~= "",
        "Framework.init: windowTitle must be a non-empty string")
    assert(type(config) == "table", "Framework.init: config must be a table")
    assert(type(defaultProfiles) == "table",
        "Framework.init: defaultProfiles must be a table")
    assert(opts == nil or type(opts) == "table",
        "Framework.init: opts must be a table when provided")
    opts = opts or {}
    assert(opts.hideHashMarker == nil or type(opts.hideHashMarker) == "boolean",
        "Framework.init: hideHashMarker must be a boolean when provided")
    assert(opts.moduleOrder == nil or type(opts.moduleOrder) == "table",
        "Framework.init: opts.moduleOrder must be a table when provided")
    assert(opts.renderQuickSetup == nil or type(opts.renderQuickSetup) == "function",
        "Framework.init: opts.renderQuickSetup must be a function when provided")
    assert(type(config.ModEnabled) == "boolean",
        "Framework.init: config.ModEnabled must be a boolean")
    assert(type(config.DebugMode) == "boolean",
        "Framework.init: config.DebugMode must be a boolean")
    assert(type(numProfiles) == "number" and numProfiles > 0 and math.floor(numProfiles) == numProfiles,
        "Framework.init: numProfiles must be a positive integer")

    profileTools.normalizeProfiles(config.Profiles, numProfiles)
    return opts
end

local function ValidateRuntimePrerequisites()
    assert(rom and type(rom.ImGui) == "table",
        "Framework.init: rom.ImGui is not ready; call Framework.init after game load")
    assert(rom.game and type(rom.game.SetupRunData) == "function",
        "Framework.init: rom.game.SetupRunData is not ready; call Framework.init after game load")
    assert(ScreenData and ScreenData.HUD and ScreenData.HUD.ComponentData,
        "Framework.init: game HUD globals are not ready; call Framework.init after game load")
    assert(lib and lib.overlays and type(lib.overlays.defineSystem) == "function",
        "Framework.init: adamant-ModpackLib overlays are not available")
end

local function init(packId, windowTitle, config, numProfiles, defaultProfiles, opts)
    opts = ValidateInitArgs(packId, windowTitle, config, numProfiles, defaultProfiles, opts)
    assert(lib.coordinator.isRegistered(packId),
        "Framework.init: coordinator must register before init; see Core/main.lua")

    import_as_fallback(rom.game)
    ValidateRuntimePrerequisites()

    local existingPack = FrameworkPackRegistry.packs[packId]
    local packIndex = existingPack and existingPack._index or #FrameworkPackRegistry.packList + 1

    local moduleRegistry = bootConstructors.createModuleRegistry(packId, config)
    local configHash = bootConstructors.createConfigHash(moduleRegistry, config, packId)
    local theme = bootConstructors.createTheme()

    moduleRegistry.refresh(opts.moduleOrder)

    local hud = bootConstructors.createHud(packId, packIndex, configHash, theme, config,
        opts.hideHashMarker == true)
    local ui = bootConstructors.createUI(moduleRegistry, hud, theme, config, packId, windowTitle,
        numProfiles, defaultProfiles, opts.renderQuickSetup, profileTools.auditSavedProfiles)

    profileTools.auditSavedProfiles(packId, config.Profiles, moduleRegistry)

    local pack = {
        moduleRegistry = moduleRegistry,
        configHash = configHash,
        hud = hud,
        ui = ui,
        _index = packIndex,
    }
    if not existingPack then
        table.insert(FrameworkPackRegistry.packList, packId)
    end
    FrameworkPackRegistry.packs[packId] = pack

    if config.ModEnabled then
        hud.setModMarker(true)
    end

    return pack
end

local function tryInit(packId, windowTitle, config, numProfiles, defaultProfiles, opts)
    local ok, pack = xpcall(function()
        return init(packId, windowTitle, config, numProfiles, defaultProfiles, opts)
    end, debug.traceback)

    if ok then
        return true, pack, nil
    end

    local err = tostring(pack)
    local logPackId = type(packId) == "string" and packId ~= "" and packId or "framework"
    logging.warn(logPackId, "Framework init failed; skipping pack: %s", err)
    return false, nil, err
end

local function createGuiCallbacks(packId)
    assert(type(packId) == "string" and packId ~= "",
        "Framework.createGuiCallbacks: packId must be a non-empty string")

    local wasGuiOpen = rom.gui.is_open() == true

    local function render()
        local pack = FrameworkPackRegistry.packs[packId]
        if not pack or not pack.ui then
            return
        end
        pack.ui.renderWindow()
    end

    local function alwaysDraw()
        local isGuiOpen = rom.gui.is_open() == true

        if wasGuiOpen and not isGuiOpen then
            local pack = FrameworkPackRegistry.packs[packId]
            if pack and pack.ui then
                pack.ui.handleHostGuiClosed()
            end
        end

        wasGuiOpen = isGuiOpen
    end

    local function menuBar()
        local pack = FrameworkPackRegistry.packs[packId]
        if not pack or not pack.ui then
            return
        end
        pack.ui.addMenuBar()
    end

    return {
        render = render,
        alwaysDraw = alwaysDraw,
        menuBar = menuBar,
    }
end

return {
    init = init,
    tryInit = tryInit,
    createGuiCallbacks = createGuiCallbacks,
}
