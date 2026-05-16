local deps = ...
local hashCodec = deps.hashCodec
local createHashGroupBuilder = deps.createHashGroupBuilder
local logging = deps.logging
local profiles = {}

function profiles.normalizeProfiles(profileSlots, numProfiles)
    assert(type(profileSlots) == "table", "Framework.init: config.Profiles must be a table")

    for i = 1, numProfiles do
        local profile = profileSlots[i]
        assert(type(profile) == "table",
            string.format(
                "Framework.init: config.Profiles[%d] is missing; ensure config.lua declares all %d profile entries",
                i, numProfiles))
        profile.Name = profile.Name ~= nil and tostring(profile.Name) or ""
        profile.Hash = profile.Hash ~= nil and tostring(profile.Hash) or ""
        profile.Tooltip = profile.Tooltip ~= nil and tostring(profile.Tooltip) or ""
    end
end

--- Scan saved profiles against the current discovered key surface.
--- Warns when a profile contains a field key for a known module that
--- no longer exists, indicating a likely rename. Namespaces absent from the module registry
--- are skipped silently because "not installed" and "renamed" are indistinguishable.
function profiles.auditSavedProfiles(packId, profileSlots, moduleRegistry)
    local knownModules = {}
    local issueCount = 0
    local hashGroupBuilder = createHashGroupBuilder(packId)

    for _, entry in ipairs(moduleRegistry.modules) do
        local fields = {}
        if entry.storage then
            local groups, groupedAliases = hashGroupBuilder.build(entry.storage, entry.hashHints)
            for _, group in ipairs(groups or {}) do
                fields[tostring(group.key)] = true
            end
            for _, root in ipairs(lib.hashing.getRoots(entry.storage)) do
                if root.alias ~= "Enabled" and not groupedAliases[root.alias] then
                    fields[tostring(root.alias)] = true
                end
            end
        end
        knownModules[entry.id] = fields
    end

    for i, profile in ipairs(profileSlots) do
        local hash = profile.Hash
        if hash and hash ~= "" then
            local profileLabel = (profile.Name ~= "" and profile.Name) or ("slot " .. i)
            for key in pairs(hashCodec.deserialize(hash)) do
                if key and key ~= "_v" then
                    local moduleId, field = string.match(key, "^([^.]+)%.(.+)$")
                    if moduleId and field then
                        local moduleFields = knownModules[moduleId]
                        if moduleFields and not moduleFields[field] then
                            issueCount = issueCount + 1
                            logging.warn(packId,
                                "Profile '%s': unrecognized key '%s' - possible rename or removed option",
                                profileLabel, key)
                        end
                    end
                end
            end
        end
    end

    return issueCount
end

return profiles
