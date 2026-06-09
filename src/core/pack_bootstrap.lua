local deps = ...
local rom = deps.rom
local logging = deps.logging
local profileTools = deps.profileTools
local constructors = deps.constructors
local frameworkRuntime = deps.frameworkRuntime

local function disposePack(pack)
    local packUi = pack and pack.ui
    if not packUi then
        return
    end

    if packUi.dispose ~= nil then
        packUi.dispose()
    elseif packUi.handleGuiClosed ~= nil then
        packUi.handleGuiClosed()
    end
end

local function validateCreatePackArgs(packId, config, numProfiles, defaultProfiles, opts)
    assert(type(packId) == "string" and packId ~= "",
        "Framework.createPack: packId must be a non-empty string")
    assert(type(config) == "table", "Framework.createPack: config must be a table")
    assert(type(defaultProfiles) == "table",
        "Framework.createPack: defaultProfiles must be a table")
    assert(opts == nil or type(opts) == "table",
        "Framework.createPack: opts must be a table when provided")
    opts = opts or {}
    assert(opts.hideHashMarker == nil or type(opts.hideHashMarker) == "boolean",
        "Framework.createPack: hideHashMarker must be a boolean when provided")
    assert(opts.moduleOrder == nil or type(opts.moduleOrder) == "table",
        "Framework.createPack: opts.moduleOrder must be a table when provided")
    assert(opts.drawPackQuickContent == nil or type(opts.drawPackQuickContent) == "function",
        "Framework.createPack: opts.drawPackQuickContent must be a function when provided")
    assert(type(config.ModEnabled) == "boolean",
        "Framework.createPack: config.ModEnabled must be a boolean")
    assert(type(config.DebugMode) == "boolean",
        "Framework.createPack: config.DebugMode must be a boolean")
    assert(type(numProfiles) == "number" and numProfiles > 0 and math.floor(numProfiles) == numProfiles,
        "Framework.createPack: numProfiles must be a positive integer")

    profileTools.normalizeProfiles(config.Profiles, numProfiles)
    return opts
end

local function validateRuntimePrerequisites()
    assert(rom and type(rom.ImGui) == "table",
        "Framework.createPack: rom.ImGui is not ready; call Framework.createPack after game load")
    assert(rom.game and type(rom.game.SetupRunData) == "function",
        "Framework.createPack: rom.game.SetupRunData is not ready; call Framework.createPack after game load")
end

local function validateCoordinatorArgs(packId, displayName, config, rebuildCallback)
    assert(type(packId) == "string" and packId ~= "",
        "Framework.registerCoordinator: packId must be a non-empty string")
    if config == nil then
        assert(displayName == nil,
            "Framework.registerCoordinator: displayName must be nil when clearing registration")
    else
        assert(type(displayName) == "string" and displayName ~= "",
            "Framework.registerCoordinator: displayName must be a non-empty string")
    end
    assert(config == nil or type(config) == "table",
        "Framework.registerCoordinator: config must be a table when provided")
    assert(config == nil or type(config.ModEnabled) == "boolean",
        "Framework.registerCoordinator: config.ModEnabled must be a boolean")
    assert(rebuildCallback == nil or type(rebuildCallback) == "function",
        "Framework.registerCoordinator: rebuildCallback must be a function when provided")
end

local function registerCoordinator(packId, displayName, config, rebuildCallback)
    validateCoordinatorArgs(packId, displayName, config, rebuildCallback)
    frameworkRuntime.coordinator.register(packId, displayName, config)
    frameworkRuntime.coordinator.registerRebuild(packId, rebuildCallback)
    return true
end

local function createPackOrThrow(packId, config, numProfiles, defaultProfiles, opts)
    opts = validateCreatePackArgs(packId, config, numProfiles, defaultProfiles, opts)
    validateRuntimePrerequisites()

    assert(frameworkRuntime.coordinator.isRegistered(packId),
        "Framework.createPack: coordinator must register before createPack; see Core/main.lua")
    local windowTitle = frameworkRuntime.coordinator.getDisplayName(packId)
    assert(type(windowTitle) == "string" and windowTitle ~= "",
        "Framework.createPack: coordinator displayName is missing; register coordinator before createPack")

    local existingPack = FrameworkPackRegistry.packs[packId]
    local packIndex = existingPack and existingPack._index or #FrameworkPackRegistry.packList + 1

    local moduleRegistry = constructors.createModuleRegistry(packId, config, frameworkRuntime)
    local configHash = constructors.createConfigHash(moduleRegistry, config, packId, frameworkRuntime.hashing)
    local theme = constructors.createTheme()
    local auditSavedProfiles = function(auditPackId, profileSlots, auditModuleRegistry)
        return profileTools.auditSavedProfiles(auditPackId, profileSlots, auditModuleRegistry, frameworkRuntime.hashing)
    end

    moduleRegistry.refresh(opts.moduleOrder)

    local hud = constructors.createHud(packId, packIndex, configHash, theme, config,
        opts.hideHashMarker == true, frameworkRuntime)
    local ui = constructors.createUI(moduleRegistry, hud, theme, config, packId, windowTitle,
        numProfiles, defaultProfiles, opts.drawPackQuickContent, auditSavedProfiles, frameworkRuntime)

    auditSavedProfiles(packId, config.Profiles, moduleRegistry)

    local pack = {
        moduleRegistry = moduleRegistry,
        configHash = configHash,
        hud = hud,
        ui = ui,
        _index = packIndex,
    }

    local ok, err = xpcall(function()
        hud.install()
    end, debug.traceback)
    if not ok then
        disposePack(pack)
        error(err, 0)
    end

    disposePack(existingPack)

    if not existingPack then
        table.insert(FrameworkPackRegistry.packList, packId)
    end
    FrameworkPackRegistry.packs[packId] = pack

    if config.ModEnabled then
        hud.setModMarker(true)
    end

    return pack
end

local function createPack(packId, config, numProfiles, defaultProfiles, opts)
    local ok, pack = xpcall(function()
        return createPackOrThrow(packId, config, numProfiles, defaultProfiles, opts)
    end, debug.traceback)

    if ok then
        return true, pack, nil
    end

    local err = tostring(pack)
    local logPackId = type(packId) == "string" and packId ~= "" and packId or "framework"
    logging.warn(logPackId, "Framework createPack failed; skipping pack: %s", err)
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
                pack.ui.handleGuiClosed()
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
    registerCoordinator = registerCoordinator,
    createPack = createPack,
    createPackOrThrow = createPackOrThrow,
    createGuiCallbacks = createGuiCallbacks,
}
