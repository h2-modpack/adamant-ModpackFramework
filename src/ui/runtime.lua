local internal = AdamantModpackFramework_Internal

function internal.createUIRuntime(ctx)
    local discovery = ctx.discovery
    local hud = ctx.hud
    local config = ctx.config
    local lib = ctx.lib
    local packId = ctx.packId
    local colors = ctx.colors
    local staging = ctx.staging
    local captureSnapshot = ctx.captureSnapshot
    local getSnapshotHost = ctx.getSnapshotHost
    local getCurrentSnapshot = ctx.getCurrentSnapshot
    local snapshotToStaging = ctx.snapshotToStaging
    local onProfileLoaded = ctx.onProfileLoaded

    local contractWarn = lib.logging.warn
    local mutatesRunData = lib.lifecycle.mutatesRunData

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

    function Runtime.finishUiChange(definition)
        if mutatesRunData(definition) then
            Runtime.markRunDataDirty()
        end
        Runtime.invalidateHash()
        hud.markHashDirty()
    end

    function Runtime.toggleEntry(entry, enabled, snapshot)
        local ok = discovery.snapshot.setEntryEnabled(entry, enabled, snapshot)
        if not ok then
            return
        end
        staging.modules[entry.id] = enabled
        Runtime.finishUiChange(entry.definition)
    end

    function Runtime.getModulesStatus(moduleIds)
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

    function Runtime.setModulesEnabled(moduleIds, enabled, snapshot)
        local changed = false
        local needsRunData = false
        local touched = {}
        snapshot = snapshot or getCurrentSnapshot() or captureSnapshot()

        for _, moduleId in ipairs(moduleIds or {}) do
            local entry = discovery.modulesById[moduleId]
            if entry and staging.modules[moduleId] ~= enabled then
                local previousEnabled = staging.modules[moduleId] == true
                local ok, err = discovery.snapshot.setEntryEnabled(entry, enabled, snapshot)
                if ok then
                    table.insert(touched, {
                        entry = entry,
                        previousEnabled = previousEnabled,
                    })
                    staging.modules[moduleId] = enabled
                    changed = true
                    if mutatesRunData(entry.definition) then
                        needsRunData = true
                    end
                else
                    local rollbackErrors = {}
                    for i = #touched, 1, -1 do
                        local touchedEntry = touched[i].entry
                        local rollbackOk, rollbackErr = discovery.snapshot.setEntryEnabled(
                            touchedEntry,
                            touched[i].previousEnabled,
                            snapshot
                        )
                        if rollbackOk then
                            staging.modules[touchedEntry.id] = touched[i].previousEnabled
                        else
                            table.insert(rollbackErrors,
                                string.format("%s: %s",
                                    tostring(touchedEntry.modName or touchedEntry.id or "unknown"),
                                    tostring(rollbackErr)))
                        end
                    end

                    contractWarn(packId,
                        "Module batch toggle failed; restoring previous module states: %s",
                        tostring(err))
                    if #rollbackErrors > 0 then
                        contractWarn(packId,
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

    function Runtime.setEntryRuntimeState(entry, state, snapshot)
        local host = getSnapshotHost(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end

        local ok, err
        if state then
            ok, err = host.applyMutation()
        else
            ok, err = host.revertMutation()
        end
        if not ok then
            contractWarn(packId,
                "%s %s failed: %s", entry.modName or "unknown", state and "apply" or "revert", err)
        end
        return ok, err
    end

    local function rollBackTouchedEntries(touched, previousState, snapshot)
        local rollbackErrors = {}
        for i = #touched, 1, -1 do
            local rollbackEntry = touched[i]
            local rollbackOk, rollbackErr = Runtime.setEntryRuntimeState(rollbackEntry, previousState, snapshot)
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

    function Runtime.setPackRuntimeState(state, snapshot)
        local previousState = staging.ModEnabled == true
        local touched = {}
        snapshot = snapshot or getCurrentSnapshot() or captureSnapshot()

        for _, m in ipairs(discovery.modules) do
            if staging.modules[m.id] then
                local ok, err = Runtime.setEntryRuntimeState(m, state, snapshot)
                if not ok then
                    contractWarn(packId,
                        "Enable Mod toggle failed; restoring previous runtime state")
                    rollBackTouchedEntries(touched, previousState, snapshot)
                    return false, err
                end
                table.insert(touched, m)
            end
        end

        staging.ModEnabled = state
        config.ModEnabled = state
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

    function Runtime.commitEntrySession(entry, snapshot)
        local host = getSnapshotHost(entry, snapshot)
        if not host then
            return
        end

        local ok, err, committed = host.commitIfDirty()
        if ok and committed then
            Runtime.finishUiChange(entry.definition)
        elseif ok == false then
            contractWarn(packId,
                "%s session commit failed; restored previous config where possible: %s",
                tostring(entry.name or entry.id or entry.modName or "module"),
                tostring(err))
        end
    end

    function Runtime.resyncAllSessions()
        local snapshot = captureSnapshot()
        for _, m in ipairs(discovery.modules) do
            local host = getSnapshotHost(m, snapshot)
            if host then
                host.resync()
            end
        end
        snapshotToStaging()
    end

    return Runtime
end
