local internal = AdamantModpackFramework_Internal

function internal.normalizeProfiles(profiles, numProfiles)
    assert(type(profiles) == "table", "Framework.init: config.Profiles must be a table")

    for i = 1, numProfiles do
        local profile = profiles[i]
        assert(type(profile) == "table",
            string.format(
                "Framework.init: config.Profiles[%d] is missing; ensure config.lua declares all %d profile entries",
                i, numProfiles))
        profile.Name = profile.Name or ""
        profile.Hash = profile.Hash or ""
        profile.Tooltip = profile.Tooltip or ""
    end
end

--- Scan saved profiles against the current discovered key surface.
--- Warns when a profile contains a field key for a known module that
--- no longer exists, indicating a likely rename. Namespaces absent from discovery
--- are skipped silently because "not installed" and "renamed" are indistinguishable.
function internal.auditSavedProfiles(packId, profiles, discovery, lib)
    local knownModules = {}
    local issueCount = 0

    for _, m in ipairs(discovery.modules) do
        local fields = {}
        if m.storage then
            for _, root in ipairs(m.storage) do
                if root._isRoot and root.alias ~= nil then
                    fields[tostring(root.alias)] = true
                end
            end
        end
        knownModules[m.id] = fields
    end

    for i, profile in ipairs(profiles) do
        local hash = profile.Hash
        if hash and hash ~= "" then
            local profileLabel = (profile.Name ~= "" and profile.Name) or ("slot " .. i)
            for entry in string.gmatch(hash .. "|", "([^|]*)|") do
                local key = string.match(entry, "^([^=]+)=")
                if key and key ~= "_v" then
                    local namespace, field = string.match(key, "^([^.]+)%.(.+)$")
                    if not namespace then
                        namespace = key
                        field = nil
                    end

                    if field then
                        local moduleFields = knownModules[namespace]
                        if moduleFields and not moduleFields[field] then
                            issueCount = issueCount + 1
                            lib.logging.warn(packId,
                                "Profile '%s': unrecognized key '%s.%s' - possible rename or removed option",
                                profileLabel, namespace, field)
                        end
                    end
                end
            end
        end
    end

    return issueCount
end
