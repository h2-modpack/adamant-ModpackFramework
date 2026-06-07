local deps = ...
local rom = deps.rom
local hashCodec = deps.hashCodec
local logging = deps.logging

local function createConfigHash(moduleRegistry, config, packId, hashing)
    local HASH_VERSION = 2
    local ConfigHash = {}

    local function readPersisted(entry, key, snapshot)
        return moduleRegistry.snapshot.getStorageValue(entry, key, snapshot)
    end

    local function stagePersisted(entry, key, value, snapshot)
        local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        if not liveModule then
            return false, "live module is unavailable"
        end
        return liveModule.stage(key, value)
    end

    local function formatEntryError(entry, action, err)
        return string.format("%s %s failed: %s",
            tostring(entry.name or entry.id or entry.pluginGuid or "module"),
            action,
            tostring(err))
    end

    local function stagePersistedChecked(entry, key, value, snapshot)
        local ok, err = stagePersisted(entry, key, value, snapshot)
        if ok == false then
            return false, formatEntryError(entry, "stage " .. tostring(key), err)
        end
        return true, nil
    end

    local function flushManagedState(snapshot)
        for _, entry in ipairs(moduleRegistry.modules) do
            local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
            if liveModule then
                local ok, err = liveModule.flush()
                if ok == false then
                    return false, formatEntryError(entry, "flush", err)
                end
            end
        end
        return true, nil
    end

    local function reloadManagedState()
        local snapshot = moduleRegistry.live.captureSnapshot()
        for _, entry in ipairs(moduleRegistry.modules) do
            local liveModule = moduleRegistry.snapshot.getLiveModule(entry, snapshot)
            if liveModule then
                liveModule.reloadFromConfig()
            end
        end
    end

    local function clonePersistedValue(value)
        if type(value) == "table" then
            return rom.game.DeepCopyTable(value)
        end
        return value
    end

    local function getRootStorage(entry)
        local roots = {}
        for _, root in ipairs(hashing.getRoots(entry.storage)) do
            if root.alias ~= "Enabled" then
                roots[#roots + 1] = root
            end
        end
        return roots
    end

    local function captureApplySnapshot(snapshot)
        local captured = {
            moduleEnabled = {},
            moduleStorage = {},
        }

        for _, entry in ipairs(moduleRegistry.modules) do
            captured.moduleEnabled[entry] = moduleRegistry.snapshot.isEntryEnabled(entry, snapshot)
            local roots = {}
            for _, root in ipairs(getRootStorage(entry)) do
                table.insert(roots, {
                    alias = root.alias,
                    value = clonePersistedValue(readPersisted(entry, root.alias, snapshot)),
                })
            end
            captured.moduleStorage[entry] = roots
        end

        return captured
    end

    local function restoreApplySnapshot(snapshot, captured)
        local rollbackErrors = {}

        for _, entry in ipairs(moduleRegistry.modules) do
            local roots = captured.moduleStorage[entry] or {}
            for _, root in ipairs(roots) do
                local ok, err = stagePersisted(entry, root.alias, clonePersistedValue(root.value), snapshot)
                if ok == false then
                    table.insert(rollbackErrors,
                        formatEntryError(entry, "stage " .. tostring(root.alias), err))
                end
            end
        end

        local flushOk, flushErr = flushManagedState(snapshot)
        if flushOk == false then
            table.insert(rollbackErrors, flushErr)
        end

        for _, entry in ipairs(moduleRegistry.modules) do
            local previousEnabled = captured.moduleEnabled[entry]
            local ok, err = moduleRegistry.snapshot.setEntryEnabled(entry, previousEnabled, snapshot)
            if ok == false then
                table.insert(rollbackErrors,
                    string.format("%s: %s", tostring(entry.pluginGuid or entry.id), tostring(err)))
            end
        end

        if #rollbackErrors > 0 then
            return false, table.concat(rollbackErrors, "; ")
        end
        return true, nil
    end

    local function failApplyHash(snapshot, captured, err)
        logging.warn(packId,
            "ApplyConfigHash failed; restoring previous state: %s",
            tostring(err))
        local rollbackOk, rollbackErr = restoreApplySnapshot(snapshot, captured)
        if not rollbackOk then
            logging.warn(packId,
                "ApplyConfigHash rollback incomplete: %s",
                tostring(rollbackErr))
        end
        return false
    end

    local BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    local function encodeBase62(n)
        if n == 0 then return "0" end
        local result = ""
        while n > 0 do
            local idx = (n % 62) + 1
            result = string.sub(BASE62, idx, idx) .. result
            n = math.floor(n / 62)
        end
        return result
    end

    local function hashChunk(str, seed, multiplier)
        local h = seed
        for i = 1, #str do
            h = (h * multiplier + string.byte(str, i)) % 1073741824
        end
        return h
    end

    local function encodeBase62Fixed(n, width)
        local s = encodeBase62(n)
        while #s < width do s = "0" .. s end
        return s
    end

    local function fingerprint(str)
        local h1 = hashChunk(str, 5381, 33)
        local h2 = hashChunk(str, 52711, 37)
        return encodeBase62Fixed(h1, 6) .. encodeBase62Fixed(h2, 6)
    end

    local function encodeValue(root, value, entryLabel)
        local encoded = hashing.toHash(root, value)
        assert(encoded ~= nil, string.format(
            "GetConfigHash: expected hashable prepared %s '%s'",
            entryLabel,
            tostring(root.alias)
        ))
        return encoded
    end

    local function decodeValue(root, str, entryLabel)
        if hashing.isHashTokenValid(root, str) == false then
            return nil, string.format(
                "invalid %s '%s' hash value '%s'",
                entryLabel,
                tostring(root.alias),
                tostring(str)
            )
        end

        local decoded = hashing.fromHash(root, str)
        assert(decoded ~= nil, string.format(
            "ApplyConfigHash: expected hashable prepared %s '%s'",
            entryLabel,
            tostring(root.alias)
        ))
        return decoded, nil
    end

    local function decodeModuleEnabled(entry, stored)
        if stored == nil then
            return false, nil
        end
        if stored == "1" then
            return true, nil
        end
        if stored == "0" then
            return false, nil
        end
        return nil, formatEntryError(entry, "decode enabled", "invalid module enable value '" .. tostring(stored) .. "'")
    end

    function ConfigHash.GetConfigHash()
        local kv = {}
        local snapshot = moduleRegistry.live.captureSnapshot()

        for _, entry in ipairs(moduleRegistry.modules) do
            local enabled = moduleRegistry.snapshot.isEntryEnabled(entry, snapshot)
            if enabled == nil then enabled = false end
            if enabled then
                kv[entry.id] = "1"
            end

            for _, root in ipairs(getRootStorage(entry)) do
                local current = readPersisted(entry, root.alias, snapshot)
                if not hashing.valuesEqual(root, current, root.default) then
                    local encoded = encodeValue(root, current, "storage root")
                    if encoded ~= nil then
                        kv[entry.id .. "." .. root.alias] = encoded
                    end
                end
            end
        end

        local payload = hashCodec.serialize(kv)
        local canonical = "_v=" .. HASH_VERSION .. (payload ~= "" and "|" .. payload or "")
        return canonical, fingerprint(canonical)
    end

    function ConfigHash.ApplyConfigHash(hash)
        if hash == nil or hash == "" then
            logging.warnIf(packId, config.DebugMode, "ApplyConfigHash: empty hash")
            return false
        end

        local kv = hashCodec.deserialize(hash)
        if kv["_v"] == nil then
            logging.warnIf(packId, config.DebugMode,
                "ApplyConfigHash: unrecognized format (missing version key)")
            return false
        end

        local version = tonumber(kv["_v"]) or 1
        if version ~= HASH_VERSION then
            logging.warn(packId,
                "ApplyConfigHash: hash version %d is not supported (%d required)",
                version, HASH_VERSION)
            return false
        end

        local snapshot = moduleRegistry.live.captureSnapshot()
        local captured = captureApplySnapshot(snapshot)
        local moduleTargets = {}
        for _, entry in ipairs(moduleRegistry.modules) do
            local stored = kv[entry.id]
            local enabledTarget, enabledErr = decodeModuleEnabled(entry, stored)
            if enabledErr ~= nil then
                return failApplyHash(snapshot, captured, enabledErr)
            end
            moduleTargets[entry] = enabledTarget == true
        end

        local okWrite, writeSucceeded, writeErr = xpcall(function()
            for _, entry in ipairs(moduleRegistry.modules) do
                for _, root in ipairs(getRootStorage(entry)) do
                    local stored = kv[entry.id .. "." .. root.alias]
                    if stored ~= nil then
                        local decoded, decodeErr = decodeValue(root, stored, "storage root")
                        if decodeErr ~= nil then
                            return false, formatEntryError(entry, "decode " .. tostring(root.alias), decodeErr)
                        end
                        local ok, err = stagePersistedChecked(entry, root.alias,
                            decoded, snapshot)
                        if ok == false then
                            return false, err
                        end
                    else
                        local ok, err = stagePersistedChecked(entry, root.alias, root.default, snapshot)
                        if ok == false then
                            return false, err
                        end
                    end
                end
            end

            local flushOk, flushErr = flushManagedState(snapshot)
            if flushOk == false then
                return false, flushErr
            end
            return true, nil
        end, debug.traceback)
        if not okWrite then
            return failApplyHash(snapshot, captured, writeSucceeded)
        end
        if writeSucceeded == false then
            return failApplyHash(snapshot, captured, writeErr)
        end

        reloadManagedState()

        for _, entry in ipairs(moduleRegistry.modules) do
            local ok, err = moduleRegistry.snapshot.setEntryEnabled(entry, moduleTargets[entry], snapshot)
            if ok == false then
                return failApplyHash(snapshot, captured, err)
            end
        end

        return true
    end

    return ConfigHash
end

return createConfigHash
