local ctx = ...

local ui = rom.ImGui
local config = ctx.config
local colors = ctx.colors
local moduleRegistry = ctx.moduleRegistry
local staging = ctx.staging
local runtime = ctx.runtime

local function draw(snapshot)
    lib.imguiHelpers.textColored(ui, colors.info, "Developer options for module authors and debugging.")
    ui.Spacing()

    -- Framework debug gates framework-owned warnings such as module indexing, hash import,
    -- and framework-managed runtime mutation failures.
    -- Load-time schema validation lives in Lib.
    -- Read/write directly from config - intentional exception to the staging pattern.
    -- These flags have no external writers (no profile load),
    -- so staging would add complexity with no correctness benefit.
    -- lib.config.DebugMode is shared across packs: direct reads reflect changes from
    -- other pack Dev tabs immediately, whereas staging would go stale.
    local fwVal, fwChg = ui.Checkbox("Framework Debug", config.DebugMode == true)
    if fwChg then
        config.DebugMode = fwVal
    end
    if ui.IsItemHovered() then
        ui.SetTooltip(
        "Print framework diagnostics for module indexing, hash parsing, and runtime mutation failures.")
    end

    local libVal, libChg = ui.Checkbox("Lib Debug", lib.config.DebugMode == true)
    if libChg then
        lib.config.DebugMode = libVal
    end
    if ui.IsItemHovered() then
        ui.SetTooltip(
        "Print lib-internal diagnostic warnings (schema errors, unknown field types). Shared across all packs.")
    end

    if ui.Button("Resync Sessions") then
        runtime.resyncAllSessions()
    end

    lib.imguiHelpers.textColored(ui, colors.info, "Per-Module Debug")
    ui.Spacing()

    for _, entry in ipairs(moduleRegistry.modules) do
        local val, chg = ui.Checkbox(entry._debugLabel, staging.debug[entry.id])
        if chg then
            staging.debug[entry.id] = val
            moduleRegistry.snapshot.setDebugEnabled(entry, val, snapshot)
        end
    end
end

return draw
