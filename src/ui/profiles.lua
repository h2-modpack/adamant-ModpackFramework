local internal = AdamantModpackFramework_Internal
local FIELD_MEDIUM = 0.5
local FIELD_NARROW = 0.3
local FIELD_WIDE = 0.85

function internal.createUIProfiles(ctx)
    local ui = rom.ImGui
    local config = ctx.config
    local colors = ctx.colors
    local NUM_PROFILES = ctx.numProfiles
    local defaultProfiles = ctx.defaultProfiles
    local packId = ctx.packId
    local discovery = ctx.discovery
    local runtime = ctx.runtime
    local FEEDBACK_DURATION = 2.0

    local slotLabels = {}
    local slotOccupied = {}
    local slotLabelsDirty = true

    local selectedProfileSlot = 1
    local selectedProfileCombo = 0
    local importHashBuffer = ""
    local importFeedback = nil
    local importFeedbackColor = nil
    local importFeedbackTime = nil

    local Profiles = {}

    local function setImportFeedback(text, color)
        importFeedback = text
        importFeedbackColor = color
        importFeedbackTime = os.clock()
    end

    local function clearExpiredFeedback()
        if importFeedback and os.clock() - importFeedbackTime > FEEDBACK_DURATION then
            importFeedback = nil
            importFeedbackColor = nil
            importFeedbackTime = nil
        end
    end

    local function rebuildSlotLabels()
        for i, p in ipairs(config.Profiles) do
            local name = p.Name or ""
            local hasName = p.Name ~= ""
            slotOccupied[i] = hasName
            if hasName then
                slotLabels[i] = i .. ": " .. name
            else
                slotLabels[i] = i .. ": (empty)"
            end
        end
        slotLabelsDirty = false
    end

    function Profiles.snapshot()
        slotLabelsDirty = true
    end

    function Profiles.markSlotLabelsDirty()
        slotLabelsDirty = true
    end

    function Profiles.tick()
        clearExpiredFeedback()
    end

    function Profiles.drawQuickSelector()
        local winW = ui.GetWindowWidth()

        lib.imguiHelpers.textColored(ui, colors.info, "Select a profile to automatically configure the modpack:")
        ui.Spacing()

        if slotLabelsDirty then rebuildSlotLabels() end

        local comboPreview = "Select..."
        if selectedProfileCombo > 0 and selectedProfileCombo <= NUM_PROFILES and slotOccupied[selectedProfileCombo] then
            comboPreview = slotLabels[selectedProfileCombo]
        end

        ui.PushItemWidth(winW * FIELD_MEDIUM)
        if ui.BeginCombo("Profile", comboPreview) then
            for i = 1, NUM_PROFILES do
                if slotOccupied[i] then
                    ui.PushID(i)
                    if ui.Selectable(slotLabels[i], i == selectedProfileCombo) then
                        selectedProfileCombo = i
                    end
                    if ui.IsItemHovered() then
                        local tip = config.Profiles[i].Tooltip or ""
                        if tip ~= "" then ui.SetTooltip(tip) end
                    end
                    ui.PopID()
                end
            end
            ui.EndCombo()
        end
        ui.PopItemWidth()

        ui.SameLine()
        local sel = selectedProfileCombo
        if sel > 0 and sel <= NUM_PROFILES then
            local h = config.Profiles[sel].Hash or ""
            if h ~= "" then
                if ui.Button("Load") then runtime.loadProfile(h) end
            end
        end
    end

    function Profiles.draw()
        local winW = ui.GetWindowWidth()

        lib.imguiHelpers.textColored(ui, colors.info, "Export / Import")
        ui.Indent()

        local canonical, fingerprint = runtime.getCachedHash()
        ui.Text("Config ID:")
        ui.SameLine()
        lib.imguiHelpers.textColored(ui, colors.success, fingerprint)
        ui.SameLine()
        if ui.Button("Copy") then
            ui.SetClipboardText(canonical)
            setImportFeedback("Copied to clipboard!", colors.success)
        end

        ui.Spacing()
        ui.Text("Import Hash:")
        ui.SameLine()
        ui.PushItemWidth(winW * FIELD_MEDIUM)
        local newText, changed = ui.InputText("##ImportHash", importHashBuffer, 2048)
        if changed then importHashBuffer = newText end
        ui.PopItemWidth()
        ui.SameLine()
        if ui.Button("Paste") then
            local clip = ui.GetClipboardText()
            if clip then importHashBuffer = clip end
        end
        ui.SameLine()
        if ui.Button("Import") then
            if runtime.loadProfile(importHashBuffer) then
                setImportFeedback("Imported successfully!", colors.success)
            else
                setImportFeedback("Invalid hash.", colors.error)
            end
        end

        ui.Unindent()
        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        lib.imguiHelpers.textColored(ui, colors.info, "Saved Profiles")
        ui.Indent()

        if slotLabelsDirty then rebuildSlotLabels() end

        ui.PushItemWidth(winW * FIELD_NARROW)
        if ui.BeginCombo("Slot", slotLabels[selectedProfileSlot]) then
            for i, label in ipairs(slotLabels) do
                if ui.Selectable(label, i == selectedProfileSlot) then
                    selectedProfileSlot = i
                end
            end
            ui.EndCombo()
        end
        ui.PopItemWidth()

        ui.Spacing()

        local ps = config.Profiles[selectedProfileSlot]
        local currentName = ps.Name or ""
        local currentHash = ps.Hash or ""
        local currentTooltip = ps.Tooltip or ""
        local hasData = currentHash ~= ""

        ui.Text("Name:")
        ui.SameLine()
        ui.PushItemWidth(winW * FIELD_NARROW)
        local newName, nameChanged = ui.InputText("##SlotName", currentName, 64)
        if nameChanged then
            ps.Name = newName
            slotLabelsDirty = true
        end
        ui.PopItemWidth()

        ui.Text("Tooltip:")
        ui.SameLine()
        ui.PushItemWidth(winW * FIELD_WIDE)
        local newTooltip, tooltipChanged = ui.InputText("##SlotTooltip", currentTooltip, 256)
        if tooltipChanged then
            ps.Tooltip = newTooltip
        end
        ui.PopItemWidth()

        ui.Spacing()

        if ui.Button("Save Current") then
            local h = runtime.getCachedHash()
            ps.Hash = h
            if (ps.Name or "") == "" then
                ps.Name = "Profile " .. selectedProfileSlot
            end
            slotLabelsDirty = true
            setImportFeedback("Profile saved.", colors.success)
        end

        if hasData then
            ui.SameLine()
            if ui.Button("Load") then
                if runtime.loadProfile(ps.Hash) then
                    setImportFeedback("Profile loaded.", colors.success)
                else
                    setImportFeedback("Failed to load profile.", colors.error)
                end
            end
            ui.SameLine()
            if ui.Button("Copy Hash") then
                ui.SetClipboardText(currentHash)
                setImportFeedback("Copied to clipboard!", colors.success)
            end
            ui.SameLine()
            if ui.Button("Clear") then
                ps.Name = ""
                ps.Hash = ""
                ps.Tooltip = ""
                slotLabelsDirty = true
                setImportFeedback("Slot cleared.", colors.textDisabled)
            end
            if ui.IsItemHovered() then
                ui.SetTooltip("Permanently clears this profile slot.")
            end
        end

        ui.Unindent()
        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        if ui.Button("Restore Default Profiles") then
            for i = 1, NUM_PROFILES do
                local d = defaultProfiles[i]
                local cp = config.Profiles[i]
                if d then
                    cp.Name = d.Name
                    cp.Hash = d.Hash
                    cp.Tooltip = d.Tooltip
                else
                    cp.Name = ""
                    cp.Hash = ""
                    cp.Tooltip = ""
                end
            end
            slotLabelsDirty = true
            setImportFeedback("Default profiles restored.", colors.success)
        end
        if ui.IsItemHovered() then
            ui.SetTooltip("Overwrites ALL profile slots with the shipped defaults. Custom profiles will be lost.")
        end

        ui.SameLine()
        if ui.Button("Audit Saved Profiles") then
            local issueCount = internal.auditSavedProfiles(packId, config.Profiles, discovery, lib)
            if issueCount == 0 then
                setImportFeedback("All saved profiles look valid.", colors.success)
            else
                setImportFeedback(
                    string.format("Profile audit found %d issue%s. Check warnings/log.",
                        issueCount,
                        issueCount == 1 and "" or "s"),
                    colors.warning)
            end
        end
        if ui.IsItemHovered() then
            ui.SetTooltip("Check all saved profile hashes against the currently discovered module surface.")
        end

        ui.Spacing()
        if importFeedback then
            lib.imguiHelpers.textColored(ui, importFeedbackColor, importFeedback)
        end
    end

    Profiles.snapshot()
    return Profiles
end
