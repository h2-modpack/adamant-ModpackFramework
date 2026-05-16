local function createHashGroupBuilder()
    local HashGroupBuilder = {}

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

    HashGroupBuilder.encodeValue = EncodeGroupMemberValue
    HashGroupBuilder.decodeValue = DecodeGroupMemberValue

    local function GetPreparedGroupMember(aliasNodes, alias)
        local node = aliasNodes[alias]
        local width = node and lib.hashing.getPackWidth(node) or nil
        assert(node ~= nil and width ~= nil, "hashGroups: expected prepared hash group alias")
        return node, width
    end

    local function FlushPackedGroup(groups, groupedAliases, key, members)
        if #members == 0 then
            return
        end

        local packedDefault = 0
        for _, member in ipairs(members) do
            local encoded = EncodeGroupMemberValue(member.node, member.node.default)
            packedDefault = lib.hashing.writePackedBits(packedDefault, member.offset, member.width, encoded)
            groupedAliases[member.alias] = true
        end
        table.insert(groups, {
            key = key,
            members = members,
            packedDefault = packedDefault,
        })
    end

    function HashGroupBuilder.build(storage, hashHints)
        local aliasNodes = lib.hashing.getAliases(storage)
        local groups = {}
        local groupedAliases = {}

        for groupIndex, groupHint in ipairs(hashHints or {}) do
            local keyPrefix = groupHint.keyPrefix
            local groupNumber = 1
            local offset = 0
            local members = {}

            local function flushCurrentGroup()
                local key = keyPrefix .. "_" .. tostring(groupNumber)
                FlushPackedGroup(groups, groupedAliases, key, members)
                members = {}
                offset = 0
                groupNumber = groupNumber + 1
            end

            for _, item in ipairs(groupHint.items) do
                local aliases = type(item) == "string" and { item } or item

                local itemMembers = {}
                local itemWidth = 0
                for _, alias in ipairs(aliases) do
                    local node, width = GetPreparedGroupMember(aliasNodes, alias)
                    table.insert(itemMembers, {
                        alias = alias,
                        node = node,
                        width = width,
                    })
                    itemWidth = itemWidth + width
                end

                assert(itemWidth <= 32, "hashGroups: expected prepared hash group item width")

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
            end

            flushCurrentGroup()
        end

        return groups, groupedAliases
    end

    return HashGroupBuilder
end

return createHashGroupBuilder
