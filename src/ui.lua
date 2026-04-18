-- =============================================================================
-- UI: Main window, sidebar, tab rendering
-- =============================================================================
-- All Core.* globals replaced with closed-over factory parameters.
-- Registration (add_imgui / add_to_menu_bar) is handled by Framework.init —
-- this factory only returns { renderWindow, addMenuBar }.

--- Create the main ImGui UI subsystem for one coordinator pack.
--- @param discovery table Discovery object returned by `Framework.createDiscovery(...)`.
--- @param hud table HUD object returned by `Framework.createHud(...)`.
--- @param theme table Theme object returned by `Framework.createTheme(...)`.
--- @param def table Coordinator definition table containing profile and layout metadata.
--- @param config table Coordinator config table.
--- @param lib table Adamant Modpack Lib export.
--- @param packId string Pack identifier used in warnings.
--- @param windowTitle string Window title shown in the mod menu.
--- @return table ui UI object exposing `{ renderWindow, addMenuBar }`.
function Framework.createUI(discovery, hud, theme, def, config, lib, packId, windowTitle)
    local ui                 = rom.ImGui
    local DEFAULT_WINDOW_WIDTH = 1280
    local DEFAULT_WINDOW_HEIGHT = 840
    local contractWarn       = lib.logging.warn
    local mutatesRunData     = lib.mutation.mutatesRunData
    local applyDefinition    = lib.mutation.apply
    local revertDefinition   = lib.mutation.revert
    local commitState        = lib.host.commitState
    local auditAndResyncState = lib.host.auditAndResyncState

    -- Unpack theme for convenient access
    local colors             = theme.colors

    local SIDEBAR_RATIO      = theme.SIDEBAR_RATIO
    local FIELD_MEDIUM       = theme.FIELD_MEDIUM
    local FIELD_NARROW       = theme.FIELD_NARROW
    local FIELD_WIDE         = theme.FIELD_WIDE
    local PushTheme          = theme.PushTheme
    local PopTheme           = theme.PopTheme

    local function DrawColoredText(color, text)
        ui.TextColored(color[1], color[2], color[3], color[4], text)
    end
    -- =============================================================================
    -- STAGING TABLE (performance cache — avoids Chalk reads in render loop)
    -- =============================================================================
    -- Plain Lua tables mirroring each module's Chalk config.
    -- UI reads/writes go through staging. Chalk is only touched in event handlers.

    local staging = {
        ModEnabled = config.ModEnabled == true, -- snapshot once
        modules    = {},                        -- [module.id] = bool
        debug      = {},                        -- [module.id] = bool (DebugMode per entry)
    }

    -- Profile staging: plain copies of config.Profiles
    local profileStaging = {}

    --- Snapshot all Chalk configs into staging (called at init and after profile load).
    local function SnapshotToStaging()
        staging.ModEnabled = config.ModEnabled == true

        -- Grouped modules
        for _, m in ipairs(discovery.modules) do
            staging.modules[m.id] = discovery.isEntryEnabled(m)
            staging.debug[m.id] = discovery.isDebugEnabled(m)
            local uiState = m.mod.store and m.mod.store.uiState
            if uiState and uiState.reloadFromConfig then
                uiState.reloadFromConfig()
            end
        end

        -- Profiles
        for i, p in ipairs(config.Profiles) do
            profileStaging[i] = {
                Name    = p.Name or "",
                Hash    = p.Hash or "",
                Tooltip = p.Tooltip or "",
            }
        end
    end

    -- Initialize staging from current configs
    SnapshotToStaging()

    -- =============================================================================
    -- CACHED DISPLAY DATA (rebuilt on dirty flag, never per-frame)
    -- =============================================================================

    local NUM_PROFILES = def.NUM_PROFILES

    local slotLabels = {}
    local slotOccupied = {}
    local slotLabelsDirty = true

    local cachedHash = nil
    local cachedFingerprint = nil

    local selectedProfileSlot = 1
    local selectedProfileCombo = 0
    local importHashBuffer = ""
    local importFeedback = nil
    local importFeedbackColor = nil
    local importFeedbackTime = nil
    local FEEDBACK_DURATION = 2.0
    local function SetImportFeedback(text, color)
        importFeedback = text
        importFeedbackColor = color
        importFeedbackTime = os.clock()
    end

    local function InvalidateHash()
        cachedHash = nil
        cachedFingerprint = nil
    end

    local function GetCachedHash()
        if not cachedHash then
            cachedHash, cachedFingerprint = hud.getConfigHash(staging)
        end
        return cachedHash, cachedFingerprint
    end

    local function RebuildSlotLabels()
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

    -- =============================================================================
    -- TOGGLE HELPERS (event handlers — OK to touch Chalk here)
    -- =============================================================================

    local function FinishUiChange(definition, enabled)
        if mutatesRunData(definition) and enabled then
            rom.game.SetupRunData()
        end
        InvalidateHash()
        hud.markHashDirty()
    end

    local function ToggleEntry(entry, enabled, stagingBucket, stagingKey)
        local ok = discovery.setEntryEnabled(entry, enabled)
        if not ok then
            return
        end
        stagingBucket[stagingKey] = enabled
        FinishUiChange(entry.definition, enabled)
    end

    local function GetModulesStatus(moduleIds)
        local total = 0
        local enabledCount = 0

        for _, moduleId in ipairs(moduleIds or {}) do
            local entry = discovery.modulesById[moduleId]
            if entry then
                total = total + 1
                if staging.modules[moduleId] then
                    enabledCount = enabledCount + 1
                end
            end
        end

        if total == 0 then
            return "Unavailable", colors.textDisabled, false
        end
        if enabledCount == 0 then
            return "Disabled", colors.warning, true
        end
        if enabledCount == total then
            return "Enabled", colors.success, true
        end
        return string.format("Mixed (%d/%d)", enabledCount, total), colors.info, true
    end

    local function SetModulesEnabled(moduleIds, enabled)
        local changed = false
        local needsRunData = false

        for _, moduleId in ipairs(moduleIds or {}) do
            local entry = discovery.modulesById[moduleId]
            if entry and staging.modules[moduleId] ~= enabled then
                local ok = discovery.setEntryEnabled(entry, enabled)
                if ok then
                    staging.modules[moduleId] = enabled
                    changed = true
                    if mutatesRunData(entry.definition) and enabled then
                        needsRunData = true
                    end
                end
            end
        end

        if not changed then
            return
        end

        if needsRunData then
            rom.game.SetupRunData()
        end
        InvalidateHash()
        hud.markHashDirty()
    end

    local function OnUiStateFlushed(definition, enabled)
        FinishUiChange(definition, enabled)
    end

    --- Apply enable/disable on the game side only without persisting an entry's Enabled bit.
    --- Used by the coordinator master toggle to suspend/resume already-selected entries.
    local function SetEntryRuntimeState(entry, state)
        local ok, err
        if state then
            ok, err = applyDefinition(entry.definition, entry.mod.store)
        else
            ok, err = revertDefinition(entry.definition, entry.mod.store)
        end
        if not ok then
            contractWarn(packId,
                "%s %s failed: %s", entry.modName or "unknown", state and "apply" or "revert", err)
        end
        return ok, err
    end

    local function RollBackTouchedEntries(touched, previousState)
        local rollbackErrors = {}
        for i = #touched, 1, -1 do
            local rollbackEntry = touched[i]
            local rollbackOk, rollbackErr = SetEntryRuntimeState(rollbackEntry, previousState)
            if not rollbackOk then
                table.insert(rollbackErrors,
                    string.format("%s: %s",
                        tostring(rollbackEntry.modName or rollbackEntry.id or "unknown"),
                        tostring(rollbackErr)))
            end
        end
        if #rollbackErrors > 0 then
            contractWarn(packId,
                "Enable Mod rollback incomplete: %s",
                table.concat(rollbackErrors, "; "))
        end
    end

    --- Apply the coordinator master toggle transactionally across all selected entries.
    --- On failure, already-touched entries are restored to the previous pack runtime state.
    --- @param state boolean
    --- @return boolean, string|nil
    local function SetPackRuntimeState(state)
        local previousState = staging.ModEnabled == true
        local touched = {}

        for _, m in ipairs(discovery.modules) do
            if staging.modules[m.id] then
                local ok, err = SetEntryRuntimeState(m, state)
                if not ok then
                    contractWarn(packId,
                        "Enable Mod toggle failed; restoring previous runtime state")
                    RollBackTouchedEntries(touched, previousState)
                    return false, err
                end
                table.insert(touched, m)
            end
        end

        staging.ModEnabled = state
        config.ModEnabled = state
        rom.game.SetupRunData()
        hud.setModMarker(state)
        return true, nil
    end

    --- Load a profile hash: decode, apply to all module configs, re-snapshot.
    local function LoadProfile(profileHash)
        if hud.applyConfigHash(profileHash) then
            rom.game.SetupRunData()
            SnapshotToStaging()
            InvalidateHash()
            slotLabelsDirty = true
            hud.updateHash()
            return true
        end
        return false
    end

    local quickSetupContext = {
        ui              = ui,
        colors          = colors,
        theme           = theme,
        drawColoredText = DrawColoredText,
        getModulesStatus = GetModulesStatus,
        setModulesEnabled = SetModulesEnabled,
    }

    local defaultProfiles = def.defaultProfiles

    -- =============================================================================
    -- GENERIC TAB CONTENT RENDERER
    -- =============================================================================

    local function CommitEntryUiState(entry, enabled)
        local uiState = entry.uiState
        if not uiState or not uiState.isDirty or not uiState.isDirty() then
            return
        end

        local ok = commitState(entry.definition, entry.mod.store, uiState)
        if ok then
            OnUiStateFlushed(entry.definition, enabled)
        end
    end

    local function DrawEntryBody(entry, enabled)
        if not enabled or type(entry.mod.DrawTab) ~= "function" then
            return
        end

        entry.mod.DrawTab(ui, entry.uiState)

        CommitEntryUiState(entry, enabled)
    end

    -- =============================================================================
    -- SIDE TAB DEFINITIONS
    -- =============================================================================

    local selectedTab = "Quick Setup"

    local cachedTabList = nil
    local cachedQuickList = nil  -- ordered list of modules with DrawQuickContent

    local function BuildTabList()
        if cachedTabList then return cachedTabList end
        cachedTabList = { "Quick Setup" }
        cachedQuickList = {}

        for _, entry in ipairs(discovery.tabOrder or {}) do
            table.insert(cachedTabList, entry._tabLabel)
            if type(entry.mod.DrawQuickContent) == "function" then
                table.insert(cachedQuickList, entry)
            end
        end

        table.insert(cachedTabList, "Profiles")
        table.insert(cachedTabList, "Dev")
        return cachedTabList
    end

    local function AuditAndResyncAllUiState()
        for _, m in ipairs(discovery.modules) do
            local uiState = m.mod.store and m.mod.store.uiState
            if uiState then
                auditAndResyncState(m.name or m.id or m.modName, uiState)
            end
        end
        SnapshotToStaging()
    end

    local moduleByTabLabel = {}
    for _, entry in ipairs(discovery.modules) do
        moduleByTabLabel[entry._tabLabel] = entry
    end

    -- =============================================================================
    -- TAB CONTENT DRAWERS
    -- =============================================================================

    local function DrawQuickSetup()
        local winW = ui.GetWindowWidth()

        DrawColoredText(colors.info, "Select a profile to automatically configure the modpack:")
        ui.Spacing()

        if slotLabelsDirty then RebuildSlotLabels() end

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
                if ui.Button("Load") then LoadProfile(h) end
            end
        end

        ui.Separator()
        ui.Spacing()

        if type(def.renderQuickSetup) == "function" then
            def.renderQuickSetup(quickSetupContext)
        end

        for _, entry in ipairs(cachedQuickList or {}) do
            if staging.modules[entry.id] and entry.mod.DrawQuickContent then
                ui.Separator()
                ui.Spacing()
                DrawColoredText(colors.info, entry.name or entry.id)
                ui.Spacing()
                entry.mod.DrawQuickContent(ui, entry.uiState)
                CommitEntryUiState(entry, staging.modules[entry.id])
            end
        end
    end

    local function DrawModuleTab(entry)
        local enabled = staging.modules[entry.id] or false
        local val, chg = ui.Checkbox(entry._enableLabel, enabled)
        if chg then
            ToggleEntry(entry, val, staging.modules, entry.id)
        end
        if ui.IsItemHovered() and entry.definition.tooltip then
            ui.SetTooltip(entry.definition.tooltip)
        end

        if not enabled then return end

        ui.Spacing()
        DrawEntryBody(entry, enabled)
    end

    local function DrawProfiles()
        local winW = ui.GetWindowWidth()

        -- Export / Import
        DrawColoredText(colors.info, "Export / Import")
        ui.Indent()

        -- Read cached hash (computed from staging, not Chalk)
        local canonical, fingerprint = GetCachedHash()
        ui.Text("Config ID:")
        ui.SameLine()
        DrawColoredText(colors.success, fingerprint)
        ui.SameLine()
        if ui.Button("Copy") then
            ui.SetClipboardText(canonical)
            SetImportFeedback("Copied to clipboard!", colors.success)
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
            if LoadProfile(importHashBuffer) then
                SetImportFeedback("Imported successfully!", colors.success)
            else
                SetImportFeedback("Invalid hash.", colors.error)
            end
        end

        ui.Unindent()
        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        -- Profile Slot Selector
        DrawColoredText(colors.info, "Saved Profiles")
        ui.Indent()

        if slotLabelsDirty then RebuildSlotLabels() end

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

        -- Read from profileStaging, not Chalk
        local ps = profileStaging[selectedProfileSlot]
        local hasData = ps.Hash ~= ""

        ui.Text("Name:")
        ui.SameLine()
        ui.PushItemWidth(winW * FIELD_NARROW)
        local newName, nameChanged = ui.InputText("##SlotName", ps.Name, 64)
        if nameChanged then
            ps.Name = newName
            config.Profiles[selectedProfileSlot].Name = newName -- write to Chalk
            slotLabelsDirty = true
        end
        ui.PopItemWidth()

        ui.Text("Tooltip:")
        ui.SameLine()
        ui.PushItemWidth(winW * FIELD_WIDE)
        local newTooltip, tooltipChanged = ui.InputText("##SlotTooltip", ps.Tooltip, 256)
        if tooltipChanged then
            ps.Tooltip = newTooltip
            config.Profiles[selectedProfileSlot].Tooltip = newTooltip -- write to Chalk
        end
        ui.PopItemWidth()

        ui.Spacing()

        if ui.Button("Save Current") then
            local h = GetCachedHash()
            ps.Hash = h
            config.Profiles[selectedProfileSlot].Hash = h -- write to Chalk
            if ps.Name == "" then
                ps.Name = "Profile " .. selectedProfileSlot
                config.Profiles[selectedProfileSlot].Name = ps.Name
            end
            slotLabelsDirty = true
            SetImportFeedback("Profile saved.", colors.success)
        end

        if hasData then
            ui.SameLine()
            if ui.Button("Load") then
                if LoadProfile(ps.Hash) then
                    SetImportFeedback("Profile loaded.", colors.success)
                else
                    SetImportFeedback("Failed to load profile.", colors.error)
                end
            end
            ui.SameLine()
            if ui.Button("Copy Hash") then
                ui.SetClipboardText(ps.Hash)
                SetImportFeedback("Copied to clipboard!", colors.success)
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
                SetImportFeedback("Slot cleared.", colors.textDisabled)
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
            SetImportFeedback("Default profiles restored.", colors.success)
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
                DrawColoredText(importFeedbackColor, importFeedback)
            end
        end
    end

    local function DrawDev()
        DrawColoredText(colors.info, "Developer options for module authors and debugging.")
        ui.Spacing()

        -- Framework debug gates framework-owned warnings such as discovery, hash import,
        -- and framework-managed apply/revert failures.
        -- Load-time schema validation lives in Lib.
        -- Read/write directly from config — intentional exception to the staging pattern.
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
            "Print framework diagnostics for discovery, hash parsing, and apply/revert failures.")
        end

        local libVal, libChg = ui.Checkbox("Lib Debug", lib.config.DebugMode == true)
        if libChg then
            lib.config.DebugMode = libVal
        end
        if ui.IsItemHovered() then
            ui.SetTooltip(
            "Print lib-internal diagnostic warnings (schema errors, unknown field types). Shared across all packs.")
        end

        if ui.Button("Audit + Resync UI State") then
            AuditAndResyncAllUiState()
        end

        DrawColoredText(colors.info, "Per-Module Debug")
        ui.Spacing()

        for _, entry in ipairs(discovery.modules) do
            local val, chg = ui.Checkbox(entry._debugLabel, staging.debug[entry.id])
            if chg then
                staging.debug[entry.id] = val
                discovery.setDebugEnabled(entry, val)
            end
        end
    end

    -- =============================================================================
    -- MAIN WINDOW
    -- =============================================================================

    local function DrawMainWindow()
        -- Read from staging, not Chalk
        local val, chg = ui.Checkbox("Enable Mod", staging.ModEnabled)
        if chg then
            SetPackRuntimeState(val)
        end
        if ui.IsItemHovered() then ui.SetTooltip("Toggle the entire modpack on or off.") end

        if not staging.ModEnabled then
            ui.Separator()
            DrawColoredText(colors.warning, "Mod is currently disabled. All changes have been reverted.")
            return
        end

        ui.Spacing()
        ui.Separator()
        ui.Spacing()

        local tabs = BuildTabList()
        local totalW = ui.GetWindowWidth()
        local sidebarW = totalW * SIDEBAR_RATIO

        -- Sidebar (proportional width, fill remaining height)
        ui.BeginChild("Sidebar", sidebarW, 0, true)
        for _, tabName in ipairs(tabs) do
            if ui.Selectable(tabName, selectedTab == tabName) then
                selectedTab = tabName
            end
        end
        ui.EndChild()

        ui.SameLine()

        -- Content panel (0 height = fill remaining space)
        ui.BeginChild("TabContent", 0, 0, true)
        ui.Spacing()

        if selectedTab == "Quick Setup" then
            DrawQuickSetup()
        elseif selectedTab == "Profiles" then
            DrawProfiles()
        elseif selectedTab == "Dev" then
            DrawDev()
        elseif moduleByTabLabel[selectedTab] then
            DrawModuleTab(moduleByTabLabel[selectedTab])
        end

        ui.EndChild()
    end

    -- =============================================================================
    -- RETURNED API
    -- =============================================================================

    local _showModWindow = false
    local _didSeedWindowSize = false

    local function SeedWindowSize()
        if _didSeedWindowSize then
            return
        end
        ui.SetNextWindowSize(DEFAULT_WINDOW_WIDTH, DEFAULT_WINDOW_HEIGHT, rom.ImGuiCond.FirstUseEver)
        _didSeedWindowSize = true
    end

    local function renderWindow()
        hud.refreshHashIfIdle()
        if _showModWindow then
            PushTheme()
            SeedWindowSize()
            local shouldDraw, open = ui.Begin(windowTitle, true)
            if shouldDraw then
                DrawMainWindow()
            end
            ui.End()
            if open == false then
                hud.flushPendingHash()
                _showModWindow = false
            end
            PopTheme()
        end
    end

    local function addMenuBar()
        if ui.MenuItem("Show Mod Menu") then
            if _showModWindow then
                hud.flushPendingHash()
            end
            _showModWindow = not _showModWindow
        end
    end

    return { renderWindow = renderWindow, addMenuBar = addMenuBar }
end
