local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
Framework = {}
---@module "adamant-ModpackLib"
---@type AdamantModpackLib
lib = mods["adamant-ModpackLib"]
AdamantModpackFramework_Internal = AdamantModpackFramework_Internal or {}

local internal = AdamantModpackFramework_Internal
internal.packs = internal.packs or {}
internal.packList = internal.packList or {}

import "ui/theme.lua"
import "profiles.lua"
import "discovery.lua"
import "hash_groups.lua"
import "hash.lua"
import "hud.lua"
import "ui.lua"

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

    internal.normalizeProfiles(config.Profiles, numProfiles)
    return opts
end

function Framework.init(packId, windowTitle, config, numProfiles, defaultProfiles, opts)
    opts = ValidateInitArgs(packId, windowTitle, config, numProfiles, defaultProfiles, opts)
    assert(lib.isModuleCoordinated(packId),
        "Framework.init: coordinator must register before init; see Core/main.lua")

    import_as_fallback(rom.game)

    local packIndex = internal.packs[packId] and internal.packs[packId]._index or nil
    if not packIndex then
        table.insert(internal.packList, packId)
        packIndex = #internal.packList
    end

    local discovery = Framework.createDiscovery(packId, config, lib)
    local hash = Framework.createHash(discovery, config, lib, packId)
    local theme = Framework.createTheme(lib)

    discovery.run(opts.moduleOrder)

    local startupSnapshot = discovery.live.captureSnapshot()
    local needsRunDataSetup = false
    for _, entry in ipairs(discovery.modules) do
        local host = discovery.snapshot.getHost(entry, startupSnapshot)
        if host then
            local ok, err = host.applyOnLoad()
            if not ok then
                lib.logging.warn(packId,
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

    internal.auditSavedProfiles(packId, config.Profiles, discovery, lib)

    local hud = Framework.createHud(packId, packIndex, hash, theme, config,
        opts.hideHashMarker == true)
    local ui = Framework.createUI(discovery, hud, theme, config, packId, windowTitle,
        numProfiles, defaultProfiles, opts.renderQuickSetup)

    local pack = {
        discovery = discovery,
        hash = hash,
        hud = hud,
        ui = ui,
        _index = packIndex,
    }
    internal.packs[packId] = pack

    if config.ModEnabled then
        hud.setModMarker(true)
    end

    return pack
end

public.init = Framework.init

function Framework.registerGui(packId)
    assert(type(packId) == "string" and packId ~= "",
        "Framework.registerGui: packId must be a non-empty string")

    local wasGuiOpen = rom.gui.is_open() == true

    rom.gui.add_imgui(function()
        local pack = internal.packs[packId]
        if not pack or not pack.ui then
            return
        end
        pack.ui.renderWindow()
    end)

    rom.gui.add_always_draw_imgui(function()
        local isGuiOpen = rom.gui.is_open() == true

        if wasGuiOpen and not isGuiOpen then
            local pack = internal.packs[packId]
            if pack and pack.ui then
                pack.ui.flushPending()
            end
        end

        wasGuiOpen = isGuiOpen
    end)

    rom.gui.add_to_menu_bar(function()
        local pack = internal.packs[packId]
        if not pack or not pack.ui then
            return
        end
        pack.ui.addMenuBar()
    end)
end

public.registerGui = Framework.registerGui
