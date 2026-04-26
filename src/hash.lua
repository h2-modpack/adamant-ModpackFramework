function Framework.createHash(discovery, config, lib, packId)
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

    local function ReadPersisted(entry, key, snapshot)
        if snapshot then
            return discovery.snapshot.getStorageValue(entry, key, snapshot)
        end
        local host = discovery.live.getHost(entry)
        return host and host.read(key) or nil
    end

    local function StagePersisted(entry, key, value, snapshot)
        local host = discovery.snapshot.getHost(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end
        return host.stage(key, value)
    end

    local function FlushManagedSessions(snapshot)
        for _, m in ipairs(discovery.modules) do
            local host = discovery.snapshot.getHost(m, snapshot)
            if host then
                host.flush()
            end
        end
    end

    local function ReloadManagedSession()
        local snapshot = discovery.live.captureSnapshot()
        for _, m in ipairs(discovery.modules) do
            local host = discovery.snapshot.getHost(m, snapshot)
            if host then
                host.reloadFromConfig()
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

    local function ValidateGroupAlias(aliasNodes, alias, groupKey)
        local node = aliasNodes[alias]
        if not node then
            contractWarn(packId, "hashGroups: unknown alias '%s' in group '%s'", alias, groupKey)
            return nil
        end
        if node._isBitAlias then
            contractWarn(packId,
                "hashGroups: alias '%s' in group '%s' is a packed child alias; only root storage aliases are supported",
                alias, groupKey)
            return nil
        end
        if node._lifetime == "transient" then
            contractWarn(packId,
                "hashGroups: alias '%s' in group '%s' is transient; only persisted root aliases are supported",
                alias, groupKey)
            return nil
        end
        local width = getPackWidth(node)
        if not width then
            contractWarn(packId,
                "hashGroups: alias '%s' in group '%s' cannot be packed (no derivable width)",
                alias, groupKey)
            return nil
        end
        return node, width
    end

    local function FlushPackedGroup(groups, groupedAliases, key, members)
        if #members == 0 then
            return
        end

        local packedDefault = 0
        for _, member in ipairs(members) do
            local encoded = EncodeGroupMemberValue(member.node, member.node.default)
            packedDefault = writeBitsValue(packedDefault, member.offset, member.width, encoded)
            groupedAliases[member.alias] = true
        end
        table.insert(groups, {
            key = key,
            members = members,
            packedDefault = packedDefault,
        })
    end

    local function BuildHashGroups(storage, hashHints)
        local aliasNodes = getStorageAliases(storage)
        local groups = {}
        local groupedAliases = {}
        local seenKeys = {}

        for groupIndex, groupHint in ipairs(hashHints or {}) do
            local keyPrefix = type(groupHint.keyPrefix) == "string" and groupHint.keyPrefix or ("#" .. groupIndex)
            local groupNumber = 1
            local offset = 0
            local members = {}

            local function flushCurrentGroup()
                local key = keyPrefix .. "_" .. tostring(groupNumber)
                if seenKeys[key] then
                    contractWarn(packId,
                        "hashGroups: duplicate group key '%s' at index %d; group will be skipped",
                        key, groupIndex)
                    members = {}
                    offset = 0
                    return
                end
                seenKeys[key] = true
                FlushPackedGroup(groups, groupedAliases, key, members)
                members = {}
                offset = 0
                groupNumber = groupNumber + 1
            end

            for _, item in ipairs(groupHint.items or {}) do
                local aliases = type(item) == "string" and { item } or item
                if type(aliases) ~= "table" then
                    goto continue_item
                end

                local itemMembers = {}
                local itemWidth = 0
                local valid = true
                for _, alias in ipairs(aliases) do
                    local node, width = ValidateGroupAlias(aliasNodes, alias, keyPrefix)
                    if not node then
                        valid = false
                        break
                    end
                    table.insert(itemMembers, {
                        alias = alias,
                        node = node,
                        width = width,
                    })
                    itemWidth = itemWidth + width
                end

                if not valid then
                    goto continue_item
                end

                if itemWidth > 32 then
                    contractWarn(packId,
                        "hashGroups: group '%s' exceeds 32 bits at item %d",
                        keyPrefix, groupIndex)
                    goto continue_item
                end

                if offset + itemWidth > 32 then
                    flushCurrentGroup()
                end

                for _, member in ipairs(itemMembers) do
                    table.insert(members, {
                        alias = member.alias,
                        node = member.node,
                        width = member.width,
                        offset = offset,
                    })
                    offset = offset + member.width
                end

                ::continue_item::
            end

            flushCurrentGroup()
        end

        return groups, groupedAliases
    end

    local function GetEntryHashMeta(entry)
        if type(entry.storage) ~= "table" then
            return {}, {}
        end
        return BuildHashGroups(entry.storage, entry.hashHints)
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

    local function CaptureApplySnapshot(snapshot)
        local captured = {
            moduleEnabled = {},
            moduleStorage = {},
        }

        for _, m in ipairs(discovery.modules) do
            captured.moduleEnabled[m] = discovery.snapshot.isEntryEnabled(m, snapshot)
            local roots = {}
            for _, root in ipairs(GetRootStorage(m)) do
                table.insert(roots, {
                    alias = root.alias,
                    value = ClonePersistedValue(ReadPersisted(m, root.alias, snapshot)),
                })
            end
            captured.moduleStorage[m] = roots
        end

        return captured
    end

    local function RestoreApplySnapshot(snapshot, captured)
        local rollbackErrors = {}

        for _, m in ipairs(discovery.modules) do
            local roots = captured.moduleStorage[m] or {}
            for _, entry in ipairs(roots) do
                StagePersisted(m, entry.alias, ClonePersistedValue(entry.value), snapshot)
            end
        end

        FlushManagedSessions(snapshot)

        for _, m in ipairs(discovery.modules) do
            local previousEnabled = captured.moduleEnabled[m]
            local ok, err = discovery.snapshot.setEntryEnabled(m, previousEnabled, snapshot)
            if ok == false then
                table.insert(rollbackErrors, string.format("%s: %s", tostring(m.modName or m.id), tostring(err)))
            end
        end

        if #rollbackErrors > 0 then
            return false, table.concat(rollbackErrors, "; ")
        end
        return true, nil
    end

    local function FailApplyHash(snapshot, captured, err)
        contractWarn(packId,
            "ApplyConfigHash failed; restoring previous state: %s",
            tostring(err))
        local rollbackOk, rollbackErr = RestoreApplySnapshot(snapshot, captured)
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
        local kv = {}
        local snapshot = source and nil or discovery.live.captureSnapshot()

        for _, m in ipairs(discovery.modules) do
            local enabled
            if source then
                enabled = source.modules and source.modules[m.id]
            else
                enabled = discovery.snapshot.isEntryEnabled(m, snapshot)
            end
            if enabled == nil then enabled = false end
            if enabled then
                kv[m.id] = "1"
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

        local snapshot = discovery.live.captureSnapshot()
        local captured = CaptureApplySnapshot(snapshot)
        local moduleTargets = {}
        for _, m in ipairs(discovery.modules) do
            local stored = kv[m.id]
            moduleTargets[m] = stored == "1"
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
                            StagePersisted(m, member.alias, DecodeGroupMemberValue(member.node, encoded), snapshot)
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
                            StagePersisted(m, root.alias, DecodeValue(root, stored, "storage root"), snapshot)
                        else
                            StagePersisted(m, root.alias, root.default, snapshot)
                        end
                    end
                end
            end

            FlushManagedSessions(snapshot)
        end, debug.traceback)
        if not okWrite then
            return FailApplyHash(snapshot, captured, writeErr)
        end

        ReloadManagedSession()

        for _, m in ipairs(discovery.modules) do
            local ok, err = discovery.snapshot.setEntryEnabled(m, moduleTargets[m], snapshot)
            if ok == false then
                return FailApplyHash(snapshot, captured, err)
            end
        end

        return true
    end

    return Hash
end
