local internal = AdamantModpackFramework_Internal

function internal.createHash(discovery, config, lib, packId)
    local HASH_VERSION = 1
    local Hash = {}
    local contractWarn = lib.logging.warn
    local warnIf = lib.logging.warnIf
    local getStorageAliases = lib.hashing.getAliases
    local getPackWidth = lib.hashing.getPackWidth
    local writeBitsValue = lib.hashing.writePackedBits
    local readBitsValue = lib.hashing.readPackedBits
    local getStorageRoots = lib.hashing.getRoots
    local valuesEqual = lib.hashing.valuesEqual
    local encodeHashValue = lib.hashing.toHash
    local decodeHashValue = lib.hashing.fromHash

    local function CaptureSnapshot()
        return discovery.live.captureSnapshot()
    end

    local function GetSnapshotHost(entry, snapshot)
        return discovery.snapshot.getHost(entry, snapshot)
    end

    local function ReadPersisted(entry, key, snapshot)
        local host = GetSnapshotHost(entry, snapshot)
        if not host then
            return nil
        end
        return host.read(key)
    end

    local function StagePersisted(entry, key, value, snapshot)
        local host = GetSnapshotHost(entry, snapshot)
        if host then
            host.stage(key, value)
        end
    end

    local function FlushManagedSessions(snapshot)
        for _, m in ipairs(discovery.modules) do
            local host = GetSnapshotHost(m, snapshot)
            if host then
                host.flush()
            end
        end
    end

    local function EncodeGroupMemberValue(node, value)
        if node.type == "bool" then
            return value == true and 1 or 0
        end
        local min = math.floor(node.min or 0)
        local v = math.floor(tonumber(value) or min)
        if node.min then v = math.max(math.floor(node.min), v) end
        if node.max then v = math.min(math.floor(node.max), v) end
        return v - min
    end

    local function DecodeGroupMemberValue(node, encoded)
        if node.type == "bool" then
            return encoded ~= 0
        end
        return encoded + math.floor(node.min or 0)
    end

    local function BuildHashGroups(storage, hashGroupsDecl)
        local aliasNodes = getStorageAliases(storage)
        local groups = {}
        local groupedAliases = {}
        local seenKeys = {}

        for groupIndex, groupDecl in ipairs(hashGroupsDecl) do
            local key = type(groupDecl.key) == "string" and groupDecl.key or ("#" .. groupIndex)
            if seenKeys[key] then
                contractWarn(packId, "hashGroups: duplicate group key '%s' at index %d; group will be skipped", key, groupIndex)
                goto continue
            end
            seenKeys[key] = true
            local members = {}
            local offset = 0
            local valid = true

            for _, alias in ipairs(groupDecl) do
                local node = aliasNodes[alias]
                if not node then
                    contractWarn(packId, "hashGroups: unknown alias '%s' in group '%s'", alias, key)
                    valid = false
                    break
                end
                if node._isBitAlias then
                    contractWarn(packId, "hashGroups: alias '%s' in group '%s' is a packed child alias; only root storage aliases are supported", alias, key)
                    valid = false
                    break
                end
                if node._lifetime == "transient" then
                    contractWarn(packId,
                        "hashGroups: alias '%s' in group '%s' is transient; only persisted root aliases are supported",
                        alias, key)
                    valid = false
                    break
                end
                local width = getPackWidth(node)
                if not width then
                    contractWarn(packId, "hashGroups: alias '%s' in group '%s' cannot be packed (no derivable width)", alias, key)
                    valid = false
                    break
                end
                if offset + width > 32 then
                    contractWarn(packId, "hashGroups: group '%s' exceeds 32 bits at alias '%s'", key, alias)
                    valid = false
                    break
                end
                table.insert(members, { alias = alias, node = node, offset = offset, width = width })
                offset = offset + width
            end

            if valid and #members > 0 then
                local packedDefault = 0
                for _, member in ipairs(members) do
                    local encoded = EncodeGroupMemberValue(member.node, member.node.default)
                    packedDefault = writeBitsValue(packedDefault, member.offset, member.width, encoded)
                end
                table.insert(groups, { key = key, members = members, packedDefault = packedDefault })
                for _, member in ipairs(members) do
                    groupedAliases[member.alias] = true
                end
            end
            ::continue::
        end

        return groups, groupedAliases
    end

    local function GetEntryHashMeta(entry)
        local storage = entry.storage
        local definition = entry.definition
        if not storage or not definition or type(definition.hashGroups) ~= "table" then
            return {}, {}
        end
        return BuildHashGroups(storage, definition.hashGroups)
    end

    local moduleHashMeta = {}

    local function EnsureEntryHashMeta(cache, entry)
        local meta = cache[entry]
        if meta then
            return meta
        end

        local groups, groupedAliases = GetEntryHashMeta(entry)
        meta = { groups = groups, groupedAliases = groupedAliases }
        cache[entry] = meta
        return meta
    end

    local function ClonePersistedValue(value)
        if type(value) == "table" then
            return rom.game.DeepCopyTable(value)
        end
        return value
    end

    local function GetRootStorage(entry)
        if type(entry.storage) ~= "table" then
            return {}
        end
        return getStorageRoots(entry.storage)
    end

    local function ReloadManagedSession(snapshot)
        for _, m in ipairs(discovery.modules) do
            local host = GetSnapshotHost(m, snapshot)
            if host then
                host.reloadFromConfig()
            end
        end
    end

    local function CaptureApplyState(hostSnapshot)
        local state = {
            moduleEnabled = {},
            moduleStorage = {},
        }

        for _, m in ipairs(discovery.modules) do
            state.moduleEnabled[m] = discovery.snapshot.isModuleEnabled(m, hostSnapshot)
            local roots = {}
            for _, root in ipairs(GetRootStorage(m)) do
                table.insert(roots, {
                    alias = root.alias,
                    value = ClonePersistedValue(ReadPersisted(m, root.alias, hostSnapshot)),
                })
            end
            state.moduleStorage[m] = roots
        end

        return state
    end

    local function RestoreApplyState(state, snapshot)
        local rollbackErrors = {}

        for _, m in ipairs(discovery.modules) do
            local roots = state.moduleStorage[m] or {}
            for _, entry in ipairs(roots) do
                StagePersisted(m, entry.alias, ClonePersistedValue(entry.value), snapshot)
            end
        end

        FlushManagedSessions(snapshot)

        for _, m in ipairs(discovery.modules) do
            local previousEnabled = state.moduleEnabled[m]
            local ok, err = discovery.snapshot.setModuleEnabled(m, previousEnabled, snapshot)
            if ok == false then
                table.insert(rollbackErrors, string.format("%s: %s", tostring(m.modName or m.id), tostring(err)))
            end
        end

        if #rollbackErrors > 0 then
            return false, table.concat(rollbackErrors, "; ")
        end
        return true, nil
    end

    local function FailApplyHash(state, err, snapshot)
        contractWarn(packId,
            "ApplyConfigHash failed; restoring previous state: %s",
            tostring(err))
        local rollbackOk, rollbackErr = RestoreApplyState(state, snapshot)
        if not rollbackOk then
            contractWarn(packId,
                "ApplyConfigHash rollback incomplete: %s",
                tostring(rollbackErr))
        end
        return false
    end

    local BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

    function Hash.EncodeBase62(n)
        if n == 0 then return "0" end
        local result = ""
        while n > 0 do
            local idx = (n % 62) + 1
            result = string.sub(BASE62, idx, idx) .. result
            n = math.floor(n / 62)
        end
        return result
    end

    function Hash.DecodeBase62(str)
        local n = 0
        for i = 1, #str do
            local c = string.sub(str, i, i)
            local idx = string.find(BASE62, c, 1, true)
            if not idx then return nil end
            n = n * 62 + (idx - 1)
        end
        return n
    end

    local function Serialize(kv)
        local keys = {}
        for k in pairs(kv) do
            table.insert(keys, k)
        end
        table.sort(keys)
        local parts = {}
        for _, k in ipairs(keys) do
            table.insert(parts, k .. "=" .. kv[k])
        end
        return table.concat(parts, "|")
    end

    local function Deserialize(str)
        local kv = {}
        if not str or str == "" then return kv end
        for entry in string.gmatch(str .. "|", "([^|]*)|") do
            local k, v = string.match(entry, "^([^=]+)=(.*)$")
            if k and v then
                kv[k] = v
            end
        end
        return kv
    end

    local function HashChunk(str, seed, multiplier)
        local h = seed
        for i = 1, #str do
            h = (h * multiplier + string.byte(str, i)) % 1073741824
        end
        return h
    end

    local function EncodeBase62Fixed(n, width)
        local s = Hash.EncodeBase62(n)
        while #s < width do s = "0" .. s end
        return s
    end

    local function Fingerprint(str)
        local h1 = HashChunk(str, 5381, 33)
        local h2 = HashChunk(str, 52711, 37)
        return EncodeBase62Fixed(h1, 6) .. EncodeBase62Fixed(h2, 6)
    end

    local function EncodeValue(root, value, entryLabel)
        local encoded = encodeHashValue(root, value)
        if encoded == nil then
            contractWarn(packId,
                "GetConfigHash: skipping %s '%s' with unknown storage type '%s'",
                entryLabel, tostring(root.alias), tostring(root.type))
            return nil
        end
        return encoded
    end

    local function DecodeValue(root, str, entryLabel)
        local decoded = decodeHashValue(root, str)
        if decoded == nil then
            contractWarn(packId,
                "ApplyConfigHash: defaulting %s '%s' with unknown storage type '%s'",
                entryLabel, tostring(root.alias), tostring(root.type))
            return root.default
        end
        return decoded
    end

    function Hash.GetConfigHash(source)
        local snapshot = CaptureSnapshot()
        local kv = {}

        for _, m in ipairs(discovery.modules) do
            local enabled
            if source then
                enabled = source.modules and source.modules[m.id]
            else
                enabled = discovery.snapshot.isModuleEnabled(m, snapshot)
            end
            if enabled == nil then enabled = false end
            local default = m.default == true
            if enabled ~= default then
                kv[m.id] = enabled and "1" or "0"
            end

            local meta = EnsureEntryHashMeta(moduleHashMeta, m)
            for _, group in ipairs(meta.groups) do
                local packedValue = 0
                local isDefault = true
                for _, member in ipairs(group.members) do
                    local value = ReadPersisted(m, member.alias, snapshot)
                    local encoded = EncodeGroupMemberValue(member.node, value)
                    if encoded ~= EncodeGroupMemberValue(member.node, member.node.default) then
                        isDefault = false
                    end
                    packedValue = writeBitsValue(packedValue, member.offset, member.width, encoded)
                end
                if not isDefault then
                    kv[m.id .. "." .. group.key] = Hash.EncodeBase62(packedValue)
                end
            end

            for _, root in ipairs(GetRootStorage(m)) do
                if not meta.groupedAliases[root.alias] then
                    local current = ReadPersisted(m, root.alias, snapshot)
                    if not valuesEqual(root, current, root.default) then
                        local encoded = EncodeValue(root, current, "storage root")
                        if encoded ~= nil then
                            kv[m.id .. "." .. root.alias] = encoded
                        end
                    end
                end
            end
        end

        local payload = Serialize(kv)
        local canonical = "_v=" .. HASH_VERSION .. (payload ~= "" and "|" .. payload or "")
        return canonical, Fingerprint(canonical)
    end

    function Hash.ApplyConfigHash(hash)
        if hash == nil or hash == "" then
            warnIf(packId, config.DebugMode, "ApplyConfigHash: empty hash")
            return false
        end

        local kv = Deserialize(hash)
        if kv["_v"] == nil then
            warnIf(packId, config.DebugMode,
                "ApplyConfigHash: unrecognized format (missing version key)")
            return false
        end

        local version = tonumber(kv["_v"]) or 1
        if version > HASH_VERSION then
            contractWarn(packId,
                "ApplyConfigHash: hash version %d is newer than supported (%d)",
                version, HASH_VERSION)
        end

        local snapshot = CaptureSnapshot()
        local state = CaptureApplyState(snapshot)
        local moduleTargets = {}
        for _, m in ipairs(discovery.modules) do
            local stored = kv[m.id]
            if stored ~= nil then
                moduleTargets[m] = stored == "1"
            else
                moduleTargets[m] = m.default == true
            end
        end

        local okWrite, writeErr = xpcall(function()
            for _, m in ipairs(discovery.modules) do
                local meta = EnsureEntryHashMeta(moduleHashMeta, m)
                for _, group in ipairs(meta.groups) do
                    local stored = kv[m.id .. "." .. group.key]
                    if stored ~= nil then
                        local packedValue = Hash.DecodeBase62(stored) or group.packedDefault
                        for _, member in ipairs(group.members) do
                            local encoded = readBitsValue(packedValue, member.offset, member.width)
                            StagePersisted(m, member.alias,
                                DecodeGroupMemberValue(member.node, encoded), snapshot)
                        end
                    else
                        for _, member in ipairs(group.members) do
                            StagePersisted(m, member.alias, member.node.default, snapshot)
                        end
                    end
                end

                for _, root in ipairs(GetRootStorage(m)) do
                    if not meta.groupedAliases[root.alias] then
                        local stored = kv[m.id .. "." .. root.alias]
                        if stored ~= nil then
                            StagePersisted(m, root.alias,
                                DecodeValue(root, stored, "storage root"), snapshot)
                        else
                            StagePersisted(m, root.alias, root.default, snapshot)
                        end
                    end
                end
            end

            FlushManagedSessions(snapshot)

        end, debug.traceback)
        if not okWrite then
            return FailApplyHash(state, writeErr, snapshot)
        end

        ReloadManagedSession(snapshot)

        for _, m in ipairs(discovery.modules) do
            local ok, err = discovery.snapshot.setModuleEnabled(m, moduleTargets[m], snapshot)
            if ok == false then
                return FailApplyHash(state, err, snapshot)
            end
        end

        return true
    end

    return Hash
end
