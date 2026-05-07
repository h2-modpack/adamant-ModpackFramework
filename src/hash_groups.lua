function Framework.createHashGroups(lib, packId)
    local HashGroups = {}
    local contractWarn = lib.logging.warn
    local getStorageAliases = lib.hashing.getAliases
    local getPackWidth = lib.hashing.getPackWidth
    local writeBitsValue = lib.hashing.writePackedBits

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

    HashGroups.encodeValue = EncodeGroupMemberValue
    HashGroups.decodeValue = DecodeGroupMemberValue

    local function ValidateGroupAlias(aliasNodes, alias, groupKey)
        local node = aliasNodes[alias]
        if not node then
            contractWarn(packId, "hashGroups: unknown alias '%s' in group '%s'", alias, groupKey)
            return nil
        end
        if alias == "Enabled" then
            contractWarn(packId,
                "hashGroups: alias '%s' in group '%s' is encoded as module enable state; storage groups cannot include it",
                alias, groupKey)
            return nil
        end
        if node._isBitAlias then
            contractWarn(packId,
                "hashGroups: alias '%s' in group '%s' is a packed child alias; only root storage aliases are supported",
                alias, groupKey)
            return nil
        end
        if node._hash ~= true then
            contractWarn(packId,
                "hashGroups: alias '%s' in group '%s' is excluded from hashes; only hash root aliases are supported",
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

    function HashGroups.build(storage, hashHints)
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

    return HashGroups
end
