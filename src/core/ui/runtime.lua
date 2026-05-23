local ctx = ...

local function createUIRuntime()
    local moduleRegistry = ctx.moduleRegistry
    local rom = ctx.rom
    local hud = ctx.hud
    local config = ctx.config
    local packId = ctx.packId
    local colors = ctx.colors
    local staging = ctx.staging
    local snapshotAccess = ctx.snapshotAccess
    local snapshotToStaging = ctx.snapshotToStaging
    local logging = ctx.logging
    local onProfileLoaded = ctx.onProfileLoaded

    local cachedHash = nil
    local cachedFingerprint = nil
    local runDataDirty = false

    local Runtime = {}

    function Runtime.invalidateHash()
        cachedHash = nil
        cachedFingerprint = nil
    end

    function Runtime.markRunDataDirty()
        runDataDirty = true
    end

    function Runtime.flushPendingRunData()
        if not runDataDirty then
            return
        end
        rom.game.SetupRunData()
        runDataDirty = false
    end

    function Runtime.getCachedHash()
        if not cachedHash then
            cachedHash, cachedFingerprint = hud.getConfigHash(staging)
        end
        return cachedHash, cachedFingerprint
    end

    function Runtime.finishUiChange(entry)
        if entry and entry.affectsRunData then
            Runtime.markRunDataDirty()
        end
        Runtime.invalidateHash()
        hud.markHashDirty()
    end

    function Runtime.toggleEntry(entry, enabled, snapshot)
        local ok, err = moduleRegistry.snapshot.setEntryEnabled(entry, enabled, snapshot)
        if not ok then
            return false, err
        end
        staging.modules[entry.id] = enabled
        Runtime.finishUiChange(entry)
        return true, nil
    end

    function Runtime.getModulesStatus(moduleIds)
        local total = 0
        local enabledCount = 0

        for _, moduleId in ipairs(moduleIds or {}) do
            local entry = moduleRegistry.modulesById[moduleId]
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

    function Runtime.setModulesEnabled(moduleIds, enabled, snapshot)
        local changed = false
        local needsRunData = false
        local touched = {}
        snapshot = snapshot or snapshotAccess.get() or snapshotAccess.capture()

        for _, moduleId in ipairs(moduleIds or {}) do
            local entry = moduleRegistry.modulesById[moduleId]
            if entry and staging.modules[moduleId] ~= enabled then
                local previousEnabled = staging.modules[moduleId] == true
                local ok, err = moduleRegistry.snapshot.setEntryEnabled(entry, enabled, snapshot)
                if ok then
                    table.insert(touched, {
                        entry = entry,
                        previousEnabled = previousEnabled,
                    })
                    staging.modules[moduleId] = enabled
                    changed = true
                    if entry.affectsRunData then
                        needsRunData = true
                    end
                else
                    local rollbackErrors = {}
                    for i = #touched, 1, -1 do
                        local touchedEntry = touched[i].entry
                        local rollbackOk, rollbackErr = moduleRegistry.snapshot.setEntryEnabled(
                            touchedEntry,
                            touched[i].previousEnabled,
                            snapshot
                        )
                        if rollbackOk then
                            staging.modules[touchedEntry.id] = touched[i].previousEnabled
                        else
                            table.insert(rollbackErrors,
                                string.format("%s: %s",
                                    tostring(touchedEntry.pluginGuid or touchedEntry.id or "unknown"),
                                    tostring(rollbackErr)))
                        end
                    end

                    logging.warn(packId,
                        "Module batch toggle failed; restoring previous module states: %s",
                        tostring(err))
                    if #rollbackErrors > 0 then
                        logging.warn(packId,
                            "Module batch toggle rollback incomplete: %s",
                            table.concat(rollbackErrors, "; "))
                    end

                    return false, err
                end
            end
        end

        if not changed then
            return true, nil
        end

        if needsRunData then
            Runtime.markRunDataDirty()
        end
        Runtime.invalidateHash()
        hud.markHashDirty()
        return true, nil
    end

    local function setEntryEnabledWithStaging(entry, enabled, snapshot)
        local ok, err = moduleRegistry.snapshot.setEntryEnabled(entry, enabled, snapshot)
        if ok then
            staging.modules[entry.id] = enabled == true
        end
        return ok, err
    end

    local function syncEntryEnabledStaging(entry, snapshot)
        staging.modules[entry.id] = moduleRegistry.snapshot.isEntryEnabled(entry, snapshot) == true
    end

    local function rollBackTouchedEntries(touched, snapshot)
        local rollbackErrors = {}
        for i = #touched, 1, -1 do
            local touchedEntry = touched[i]
            local rollbackOk, rollbackErr = moduleRegistry.snapshot.rollbackPackTransition(
                touchedEntry.entry,
                touchedEntry.receipt,
                snapshot)
            if not rollbackOk then
                table.insert(rollbackErrors,
                    string.format("%s: %s",
                        tostring(touchedEntry.entry.pluginGuid or touchedEntry.entry.id or "unknown"),
                        tostring(rollbackErr)))
            else
                syncEntryEnabledStaging(touchedEntry.entry, snapshot)
            end
        end
        if #rollbackErrors > 0 then
            logging.warn(packId,
                "Enable Mod rollback incomplete: %s",
                table.concat(rollbackErrors, "; "))
        end
    end

    local function rollBackRestoredEntries(touched, snapshot, previousPackState)
        local rollbackErrors = {}
        for i = #touched, 1, -1 do
            local touchedEntry = touched[i]
            local rollbackOk, rollbackErr = setEntryEnabledWithStaging(touchedEntry.entry, false, snapshot)
            if not rollbackOk then
                rollbackErrors[#rollbackErrors + 1] = string.format(
                    "%s: %s",
                    tostring(touchedEntry.entry.pluginGuid or touchedEntry.entry.id or "unknown"),
                    tostring(rollbackErr))
            end
        end

        config.ModEnabled = previousPackState
        staging.ModEnabled = previousPackState

        for i = #touched, 1, -1 do
            local touchedEntry = touched[i]
            local rollbackOk, rollbackErr = moduleRegistry.snapshot.restorePackTransitionState(
                touchedEntry.entry,
                touchedEntry.receipt,
                snapshot)
            if not rollbackOk then
                rollbackErrors[#rollbackErrors + 1] = string.format(
                    "%s: %s",
                    tostring(touchedEntry.entry.pluginGuid or touchedEntry.entry.id or "unknown"),
                    tostring(rollbackErr))
            else
                syncEntryEnabledStaging(touchedEntry.entry, snapshot)
            end
        end

        if #rollbackErrors > 0 then
            logging.warn(packId,
                "Enable Mod rollback incomplete: %s",
                table.concat(rollbackErrors, "; "))
        end
    end

    local function suspendEntry(entry, snapshot)
        local ok, err, receipt = moduleRegistry.snapshot.suspendForPackDisable(entry, snapshot)
        if not ok then
            return false, err
        end
        syncEntryEnabledStaging(entry, snapshot)
        return true, nil, {
            entry = entry,
            receipt = receipt,
        }
    end

    local function restoreEntry(entry, snapshot)
        local ok, err, receipt = moduleRegistry.snapshot.restoreForPackEnable(entry, snapshot)
        if not ok then
            return false, err
        end
        syncEntryEnabledStaging(entry, snapshot)
        return true, nil, {
            entry = entry,
            receipt = receipt,
        }
    end

    function Runtime.reconcilePackDisabledState(snapshot)
        if config.ModEnabled == true then
            return true, nil
        end

        local errors = {}
        snapshot = snapshot or snapshotAccess.get() or snapshotAccess.capture()
        for _, entry in ipairs(moduleRegistry.modules) do
            local ok, err = moduleRegistry.snapshot.ensureSuspendedForPackDisable(entry, snapshot)
            if ok then
                syncEntryEnabledStaging(entry, snapshot)
            else
                errors[#errors + 1] = string.format("%s: %s",
                    tostring(entry.pluginGuid or entry.id or "unknown"),
                    tostring(err))
            end
        end

        if #errors > 0 then
            local err = table.concat(errors, "; ")
            logging.warn(packId,
                "Pack disabled startup sync incomplete: %s",
                err)
            return false, err
        end
        return true, nil
    end

    function Runtime.setPackRuntimeState(state, snapshot)
        local previousState = staging.ModEnabled == true
        local touched = {}
        snapshot = snapshot or snapshotAccess.get() or snapshotAccess.capture()

        if previousState == (state == true) then
            return true, nil
        end

        if state == true then
            config.ModEnabled = true
        end

        for _, entry in ipairs(moduleRegistry.modules) do
            local ok, err, receipt
            if state then
                ok, err, receipt = restoreEntry(entry, snapshot)
            else
                ok, err, receipt = suspendEntry(entry, snapshot)
            end
            if not ok then
                logging.warn(packId,
                    "Enable Mod toggle failed; restoring previous runtime state: %s",
                    tostring(err))
                if state then
                    rollBackRestoredEntries(touched, snapshot, previousState)
                else
                    config.ModEnabled = previousState
                    staging.ModEnabled = previousState
                    rollBackTouchedEntries(touched, snapshot)
                end
                return false, err
            end
            if receipt then
                touched[#touched + 1] = receipt
            end
        end

        staging.ModEnabled = state == true
        config.ModEnabled = state == true
        Runtime.markRunDataDirty()
        hud.setModMarker(state)
        return true, nil
    end

    function Runtime.loadProfile(profileHash)
        if hud.applyConfigHash(profileHash) then
            Runtime.markRunDataDirty()
            snapshotToStaging()
            Runtime.invalidateHash()
            if type(onProfileLoaded) == "function" then
                onProfileLoaded()
            end
            hud.updateHash()
            return true
        end
        return false
    end

    function Runtime.commitEntryState(entry, snapshot)
        local host = snapshotAccess.getHost(entry, snapshot)
        if not host then
            return
        end

        local ok, err, committed = host.commitIfDirty()
        if ok and committed then
            Runtime.finishUiChange(entry)
        elseif ok == false then
            logging.warn(packId,
                "%s state commit failed; restored previous config where possible: %s",
                tostring(entry.name or entry.id or entry.pluginGuid or "module"),
                tostring(err))
        end
    end

    function Runtime.resyncAllState()
        local snapshot = snapshotAccess.capture()
        for _, entry in ipairs(moduleRegistry.modules) do
            local host = snapshotAccess.getHost(entry, snapshot)
            if host then
                host.resync()
            end
        end
        snapshotToStaging()
    end

    return Runtime
end

return createUIRuntime()
