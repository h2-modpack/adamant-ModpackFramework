local internal = AdamantModpackFramework_Internal

function internal.createUIProfiles(ctx)
    local ui = ctx.ui
    local config = ctx.config
    local colors = ctx.colors
    local def = ctx.def
    local drawColoredText = ctx.drawColoredText
    local getCachedHash = ctx.getCachedHash
    local loadProfile = ctx.loadProfile
    local fieldMedium = ctx.fieldMedium
    local fieldNarrow = ctx.fieldNarrow
    local fieldWide = ctx.fieldWide

    local NUM_PROFILES = def.NUM_PROFILES
    local defaultProfiles = def.defaultProfiles
    local FEEDBACK_DURATION = 2.0

    local profileStaging = {}
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

    local function rebuildSlotLabels()
        for i, p in ipairs(profileStaging) do
            local hasName = p.Name ~= ""
            slotOccupied[i] = hasName
            if hasName then
                slotLabels[i] = i .. ": " .. p.Name
            else
                slotLabels[i] = i .. ": (empty)"
            end
        end
        slotLabelsDirty = false
    end

    function Profiles.snapshot()
        for i, p in ipairs(config.Profiles) do
            profileStaging[i] = {
                Name = p.Name or "",
                Hash = p.Hash or "",
                Tooltip = p.Tooltip or "",
            }
        end
        slotLabelsDirty = true
    end

    function Profiles.markSlotLabelsDirty()
        slotLabelsDirty = true
    end

    function Profiles.drawQuickSelector()
        local winW = ui.GetWindowWidth()

        drawColoredText(colors.info, "Select a profile to automatically configure the modpack:")
        ui.Spacing()

        if slotLabelsDirty then rebuildSlotLabels() end

        local comboPreview = "Select..."
        if selectedProfileCombo > 0 and selectedProfileCombo <= NUM_PROFILES and slotOccupied[selectedProfileCombo] then
            comboPreview = slotLabels[selectedProfileCombo]
        end

        ui.PushItemWidth(winW * fieldMedium)
        if ui.BeginCombo("Profile", comboPreview) then
            for i = 1, NUM_PROFILES do
                if slotOccupied[i] then
                    ui.PushID(i)
                    if ui.Selectable(slotLabels[i], i == selectedProfileCombo) then
                        selectedProfileCombo = i
                    end
                    if ui.IsItemHovered() then
                        local tip = profileStaging[i].Tooltip
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
            local h = profileStaging[sel].Hash
            if h ~= "" then
                if ui.Button("Load") then loadProfile(h) end
            end
        end
    end

    function Profiles.draw()
        local winW = ui.GetWindowWidth()

        -- Export / Import
        drawColoredText(colors.info, "Export / Import")
        ui.Indent()

        -- Read cached hash (computed from staging, not Chalk)
        local canonical, fingerprint = getCachedHash()
        ui.Text("Config ID:")
        ui.SameLine()
        drawColoredText(colors.success, fingerprint)
        ui.SameLine()
        if ui.Button("Copy") then
            ui.SetClipboardText(canonical)
            setImportFeedback("Copied to clipboard!", colors.success)
        end

        ui.Spacing()
        ui.Text("Import Hash:")
        ui.SameLine()
        ui.PushItemWidth(winW * fieldMedium)
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
            if loadProfile(importHashBuffer) then
                setImportFeedback("Imported successfully!", colors.success)
            else
                setImportFeedback("Invalid hash.", colors.error)
            end
        end

        ui.Unindent()
        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        -- Profile Slot Selector
        drawColoredText(colors.info, "Saved Profiles")
        ui.Indent()

        if slotLabelsDirty then rebuildSlotLabels() end

        ui.PushItemWidth(winW * fieldNarrow)
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

        -- Read from profileStaging, not Chalk
        local ps = profileStaging[selectedProfileSlot]
        local hasData = ps.Hash ~= ""

        ui.Text("Name:")
        ui.SameLine()
        ui.PushItemWidth(winW * fieldNarrow)
        local newName, nameChanged = ui.InputText("##SlotName", ps.Name, 64)
        if nameChanged then
            ps.Name = newName
            config.Profiles[selectedProfileSlot].Name = newName -- write to Chalk
            slotLabelsDirty = true
        end
        ui.PopItemWidth()

        ui.Text("Tooltip:")
        ui.SameLine()
        ui.PushItemWidth(winW * fieldWide)
        local newTooltip, tooltipChanged = ui.InputText("##SlotTooltip", ps.Tooltip, 256)
        if tooltipChanged then
            ps.Tooltip = newTooltip
            config.Profiles[selectedProfileSlot].Tooltip = newTooltip -- write to Chalk
        end
        ui.PopItemWidth()

        ui.Spacing()

        if ui.Button("Save Current") then
            local h = getCachedHash()
            ps.Hash = h
            config.Profiles[selectedProfileSlot].Hash = h -- write to Chalk
            if ps.Name == "" then
                ps.Name = "Profile " .. selectedProfileSlot
                config.Profiles[selectedProfileSlot].Name = ps.Name
            end
            slotLabelsDirty = true
            setImportFeedback("Profile saved.", colors.success)
        end

        if hasData then
            ui.SameLine()
            if ui.Button("Load") then
                if loadProfile(ps.Hash) then
                    setImportFeedback("Profile loaded.", colors.success)
                else
                    setImportFeedback("Failed to load profile.", colors.error)
                end
            end
            ui.SameLine()
            if ui.Button("Copy Hash") then
                ui.SetClipboardText(ps.Hash)
                setImportFeedback("Copied to clipboard!", colors.success)
            end
            ui.SameLine()
            if ui.Button("Clear") then
                ps.Name = ""
                ps.Hash = ""
                ps.Tooltip = ""
                local cp = config.Profiles[selectedProfileSlot]
                cp.Name = ""
                cp.Hash = ""
                cp.Tooltip = ""
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
                local cp = config.Profiles[i] -- Chalk write
                if d then
                    profileStaging[i] = { Name = d.Name, Hash = d.Hash, Tooltip = d.Tooltip }
                    cp.Name = d.Name
                    cp.Hash = d.Hash
                    cp.Tooltip = d.Tooltip
                else
                    profileStaging[i] = { Name = "", Hash = "", Tooltip = "" }
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

        -- Status bar: single feedback line for all profile actions
        ui.Spacing()
        if importFeedback then
            if os.clock() - importFeedbackTime > FEEDBACK_DURATION then
                importFeedback = nil
            else
                drawColoredText(importFeedbackColor, importFeedback)
            end
        end
    end

    Profiles.snapshot()
    return Profiles
end
