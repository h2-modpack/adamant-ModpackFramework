local deps = ...
local rom = deps.rom
local hashCodec = deps.hashCodec
local logging = deps.logging

local function createConfigHash(moduleRegistry, config, packId, hashing)
    local HASH_VERSION = 2
    local ConfigHash = {}

    local function ReadPersisted(entry, key, snapshot)
        return moduleRegistry.snapshot.getStorageValue(entry, key, snapshot)
    end

    local function StagePersisted(entry, key, value, snapshot)
        local host = moduleRegistry.snapshot.getHost(entry, snapshot)
        if not host then
            return false, "live module is unavailable"
        end
        return host.stage(key, value)
    end

    local function FormatEntryError(entry, action, err)
        return string.format("%s %s failed: %s",
            tostring(entry.name or entry.id or entry.pluginGuid or "module"),
            action,
            tostring(err))
    end

    local function StagePersistedChecked(entry, key, value, snapshot)
        local ok, err = StagePersisted(entry, key, value, snapshot)
        if ok == false then
            return false, FormatEntryError(entry, "stage " .. tostring(key), err)
        end
        return true, nil
    end

    local function FlushManagedState(snapshot)
        for _, entry in ipairs(moduleRegistry.modules) do
            local host = moduleRegistry.snapshot.getHost(entry, snapshot)
            if host then
                local ok, err = host.flush()
                if ok == false then
                    return false, FormatEntryError(entry, "flush", err)
                end
            end
        end
        return true, nil
    end

    local function ReloadManagedState()
        local snapshot = moduleRegistry.live.captureSnapshot()
        for _, entry in ipairs(moduleRegistry.modules) do
            local host = moduleRegistry.snapshot.getHost(entry, snapshot)
            if host then
                host.reloadFromConfig()
            end
        end
    end

    local function ClonePersistedValue(value)
        if type(value) == "table" then
            return rom.game.DeepCopyTable(value)
        end
        return value
    end

    local function GetRootStorage(entry)
        local roots = {}
        for _, root in ipairs(hashing.getRoots(entry.storage)) do
            if root.alias ~= "Enabled" then
                roots[#roots + 1] = root
            end
        end
        return roots
    end

    local function CaptureApplySnapshot(snapshot)
        local captured = {
            moduleEnabled = {},
            moduleStorage = {},
        }

        for _, entry in ipairs(moduleRegistry.modules) do
            captured.moduleEnabled[entry] = moduleRegistry.snapshot.isEntryEnabled(entry, snapshot)
            local roots = {}
            for _, root in ipairs(GetRootStorage(entry)) do
                table.insert(roots, {
                    alias = root.alias,
                    value = ClonePersistedValue(ReadPersisted(entry, root.alias, snapshot)),
                })
            end
            captured.moduleStorage[entry] = roots
        end

        return captured
    end

    local function RestoreApplySnapshot(snapshot, captured)
        local rollbackErrors = {}

        for _, entry in ipairs(moduleRegistry.modules) do
            local roots = captured.moduleStorage[entry] or {}
            for _, root in ipairs(roots) do
                local ok, err = StagePersisted(entry, root.alias, ClonePersistedValue(root.value), snapshot)
                if ok == false then
                    table.insert(rollbackErrors,
                        FormatEntryError(entry, "stage " .. tostring(root.alias), err))
                end
            end
        end

        local flushOk, flushErr = FlushManagedState(snapshot)
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

    local function FailApplyHash(snapshot, captured, err)
        logging.warn(packId,
            "ApplyConfigHash failed; restoring previous state: %s",
            tostring(err))
        local rollbackOk, rollbackErr = RestoreApplySnapshot(snapshot, captured)
        if not rollbackOk then
            logging.warn(packId,
                "ApplyConfigHash rollback incomplete: %s",
                tostring(rollbackErr))
        end
        return false
    end

    local BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    local function EncodeBase62(n)
        if n == 0 then return "0" end
        local result = ""
        while n > 0 do
            local idx = (n % 62) + 1
            result = string.sub(BASE62, idx, idx) .. result
            n = math.floor(n / 62)
        end
        return result
    end

    local function HashChunk(str, seed, multiplier)
        local h = seed
        for i = 1, #str do
            h = (h * multiplier + string.byte(str, i)) % 1073741824
        end
        return h
    end

    local function EncodeBase62Fixed(n, width)
        local s = EncodeBase62(n)
        while #s < width do s = "0" .. s end
        return s
    end

    local function Fingerprint(str)
        local h1 = HashChunk(str, 5381, 33)
        local h2 = HashChunk(str, 52711, 37)
        return EncodeBase62Fixed(h1, 6) .. EncodeBase62Fixed(h2, 6)
    end

    local function EncodeValue(root, value, entryLabel)
        local encoded = hashing.toHash(root, value)
        assert(encoded ~= nil, string.format(
            "GetConfigHash: expected hashable prepared %s '%s'",
            entryLabel,
            tostring(root.alias)
        ))
        return encoded
    end

    local function DecodeValue(root, str, entryLabel)
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

    local function DecodeModuleEnabled(entry, stored)
        if stored == nil then
            return false, nil
        end
        if stored == "1" then
            return true, nil
        end
        if stored == "0" then
            return false, nil
        end
        return nil, FormatEntryError(entry, "decode enabled", "invalid module enable value '" .. tostring(stored) .. "'")
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

            for _, root in ipairs(GetRootStorage(entry)) do
                local current = ReadPersisted(entry, root.alias, snapshot)
                if not hashing.valuesEqual(root, current, root.default) then
                    local encoded = EncodeValue(root, current, "storage root")
                    if encoded ~= nil then
                        kv[entry.id .. "." .. root.alias] = encoded
                    end
                end
            end
        end

        local payload = hashCodec.serialize(kv)
        local canonical = "_v=" .. HASH_VERSION .. (payload ~= "" and "|" .. payload or "")
        return canonical, Fingerprint(canonical)
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
        local captured = CaptureApplySnapshot(snapshot)
        local moduleTargets = {}
        for _, entry in ipairs(moduleRegistry.modules) do
            local stored = kv[entry.id]
            local enabledTarget, enabledErr = DecodeModuleEnabled(entry, stored)
            if enabledErr ~= nil then
                return FailApplyHash(snapshot, captured, enabledErr)
            end
            moduleTargets[entry] = enabledTarget == true
        end

        local okWrite, writeSucceeded, writeErr = xpcall(function()
            for _, entry in ipairs(moduleRegistry.modules) do
                for _, root in ipairs(GetRootStorage(entry)) do
                    local stored = kv[entry.id .. "." .. root.alias]
                    if stored ~= nil then
                        local decoded, decodeErr = DecodeValue(root, stored, "storage root")
                        if decodeErr ~= nil then
                            return false, FormatEntryError(entry, "decode " .. tostring(root.alias), decodeErr)
                        end
                        local ok, err = StagePersistedChecked(entry, root.alias,
                            decoded, snapshot)
                        if ok == false then
                            return false, err
                        end
                    else
                        local ok, err = StagePersistedChecked(entry, root.alias, root.default, snapshot)
                        if ok == false then
                            return false, err
                        end
                    end
                end
            end

            local flushOk, flushErr = FlushManagedState(snapshot)
            if flushOk == false then
                return false, flushErr
            end
            return true, nil
        end, debug.traceback)
        if not okWrite then
            return FailApplyHash(snapshot, captured, writeSucceeded)
        end
        if writeSucceeded == false then
            return FailApplyHash(snapshot, captured, writeErr)
        end

        ReloadManagedState()

        for _, entry in ipairs(moduleRegistry.modules) do
            local ok, err = moduleRegistry.snapshot.setEntryEnabled(entry, moduleTargets[entry], snapshot)
            if ok == false then
                return FailApplyHash(snapshot, captured, err)
            end
        end

        return true
    end

    return ConfigHash
end

return createConfigHash
