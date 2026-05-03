-- Discovers coordinated modules through the Lib live-host registry and snapshots live host pointers
-- so UI/runtime work can tolerate hot-replaced hosts safely.

function Framework.createDiscovery(packId, config, lib)
    local Discovery = {}
    local contractWarn = lib.logging.warn
    local warnIf = lib.logging.warnIf
    local warnedMissingHosts = {}

    local function GetHost(pluginGuid)
        return lib.getLiveModuleHost(pluginGuid)
    end

    local function ReadStorage(host)
        return host.getStorage()
    end

    local function ReadIdentity(host)
        return host.getIdentity()
    end

    local function ReadMeta(host)
        return host.getMeta()
    end

    local function ReadHashHints(host)
        return host.getHashHints()
    end

    local function ReadAffectsRunData(host)
        return host.affectsRunData() == true
    end

    local function ReadPersisted(entry, key, snapshot)
        local host = Discovery.snapshot.getHost(entry, snapshot)
        if not host then
            return nil
        end
        return host.read(key)
    end

    local function WriteStagedAndFlush(entry, key, value, snapshot)
        local host = Discovery.snapshot.getHost(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end
        return host.writeAndFlush(key, value)
    end

    local function SetEntryEnabled(entry, enabled, snapshot)
        local host = Discovery.snapshot.getHost(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end

        local ok, err = host.setEnabled(enabled)
        if not ok then
            contractWarn(packId,
                "%s %s failed: %s", entry.pluginGuid, enabled and "enable" or "disable", err)
        end
        return ok, err
    end

    local function BuildEntry(found)
        local identity = found.identity
        local meta = found.meta

        return {
            pluginGuid = found.pluginGuid,
            mod = found.mod,
            id = identity.id,
            modpack = identity.modpack,
            name = meta.name or identity.id,
            shortName = meta.shortName,
            tooltip = meta.tooltip or "",
            affectsRunData = found.affectsRunData,
            hashHints = found.hashHints,
            storage = found.storage,
            _enableLabel = "Enable " .. tostring(meta.name or identity.id or found.pluginGuid),
            _debugLabel = tostring(meta.name or identity.id or found.pluginGuid)
                .. "##" .. tostring(identity.id or found.pluginGuid),
        }
    end

    Discovery.modules = {}
    Discovery.modulesById = {}
    Discovery.modulesWithQuickContent = {}
    Discovery.tabOrder = {}
    Discovery.live = {}
    Discovery.snapshot = {}

    function Discovery.run(moduleOrder)
        Discovery.modules = {}
        Discovery.modulesById = {}
        Discovery.modulesWithQuickContent = {}
        Discovery.tabOrder = {}

        local found = {}
        for pluginGuid, mod in pairs(rom.mods) do
            local host = GetHost(pluginGuid)
            if host then
                local identity = ReadIdentity(host)
                if identity.modpack == packId then
                    table.insert(found, {
                        pluginGuid = pluginGuid,
                        mod = mod,
                        host = host,
                        storage = ReadStorage(host),
                        identity = identity,
                        meta = ReadMeta(host),
                        hashHints = ReadHashHints(host),
                        affectsRunData = ReadAffectsRunData(host),
                    })
                end
            end
        end

        table.sort(found, function(a, b)
            local aName = a.meta.name or a.identity.id or a.pluginGuid
            local bName = b.meta.name or b.identity.id or b.pluginGuid
            return aName < bName
        end)

        local duplicateNamespaces = {}
        local namespaceEntries = {}
        for _, entry in ipairs(found) do
            local namespace = entry.identity.id
            if namespace ~= nil then
                namespaceEntries[namespace] = namespaceEntries[namespace] or {}
                table.insert(namespaceEntries[namespace], entry.pluginGuid)
            end
        end

        for namespace, entries in pairs(namespaceEntries) do
            if namespace == "_v" then
                duplicateNamespaces[namespace] = true
                table.sort(entries)
                contractWarn(packId,
                    "reserved hash namespace '%s' is used by: %s; skipping all conflicting entries",
                    tostring(namespace), table.concat(entries, ", "))
            elseif #entries > 1 then
                duplicateNamespaces[namespace] = true
                table.sort(entries)
                contractWarn(packId,
                    "duplicate hash namespace '%s' across entries: %s; skipping all conflicting entries",
                    tostring(namespace), table.concat(entries, ", "))
            end
        end

        for _, foundModule in ipairs(found) do
            local pluginGuid = foundModule.pluginGuid
            local host = foundModule.host
            local id = foundModule.identity.id
            local name = foundModule.meta.name
            local hasQuickContent = host and type(host.drawQuickContent) == "function"

            if not duplicateNamespaces[id] then
                if not id or not name then
                    contractWarn(packId,
                        "Skipping %s: missing id/name", pluginGuid)
                elseif type(foundModule.storage) ~= "table" then
                    contractWarn(packId, "Skipping %s: missing host storage contract", pluginGuid)
                else
                    local discovered = BuildEntry(foundModule)
                    table.insert(Discovery.modules, discovered)
                    Discovery.modulesById[discovered.id] = discovered
                    if hasQuickContent then
                        table.insert(Discovery.modulesWithQuickContent, discovered)
                    end
                end
            end
        end

        local labelCount = {}
        for _, entry in ipairs(Discovery.modules) do
            local label = entry.shortName or entry.name
            labelCount[label] = (labelCount[label] or 0) + 1
        end

        local labelIndex = {}
        for _, entry in ipairs(Discovery.modules) do
            local label = entry.shortName or entry.name
            if labelCount[label] > 1 then
                labelIndex[label] = (labelIndex[label] or 0) + 1
                entry._tabLabel = label .. " (" .. labelIndex[label] .. ")"
                warnIf(packId, config.DebugMode,
                    "%s: shortName '%s' is shared by multiple modules. Rendering as '%s'.",
                    entry.pluginGuid, label, entry._tabLabel)
            else
                entry._tabLabel = label
            end
        end

        local placed = {}
        if type(moduleOrder) == "table" then
            for _, moduleId in ipairs(moduleOrder) do
                if type(moduleId) == "string" and Discovery.modulesById[moduleId] then
                    local entry = Discovery.modulesById[moduleId]
                    if not placed[entry.id] then
                        placed[entry.id] = true
                        table.insert(Discovery.tabOrder, entry)
                    end
                elseif type(moduleId) == "string" then
                    warnIf(packId, config.DebugMode,
                        "moduleOrder contains unknown module id '%s'; entry ignored", moduleId)
                end
            end
        end

        for _, entry in ipairs(Discovery.modules) do
            if not placed[entry.id] then
                table.insert(Discovery.tabOrder, entry)
            end
        end
    end

    function Discovery.live.captureSnapshot()
        local snapshot = { hosts = {} }

        for _, entry in ipairs(Discovery.modules) do
            local host = GetHost(entry.pluginGuid)
            snapshot.hosts[entry] = host or false
            if not host and not warnedMissingHosts[entry.pluginGuid] then
                warnedMissingHosts[entry.pluginGuid] = true
                contractWarn(packId, "%s: module host is unavailable", entry.pluginGuid)
            end
        end

        return snapshot
    end

    function Discovery.live.getHost(entry)
        return GetHost(entry.pluginGuid)
    end

    local function RequireSnapshot(snapshot)
        assert(type(snapshot) == "table" and type(snapshot.hosts) == "table",
            "discovery.snapshot access requires a captured host snapshot")
    end

    function Discovery.snapshot.getHost(entry, snapshot)
        RequireSnapshot(snapshot)
        local host = snapshot.hosts[entry]
        return host or nil
    end

    function Discovery.snapshot.isEntryEnabled(entry, snapshot)
        return ReadPersisted(entry, "Enabled", snapshot) == true
    end

    function Discovery.snapshot.setEntryEnabled(entry, enabled, snapshot)
        return SetEntryEnabled(entry, enabled, snapshot)
    end

    function Discovery.snapshot.getStorageValue(module, aliasOrKey, snapshot)
        return ReadPersisted(module, aliasOrKey, snapshot)
    end

    function Discovery.snapshot.setStorageValue(module, aliasOrKey, value, snapshot)
        return WriteStagedAndFlush(module, aliasOrKey, value, snapshot)
    end

    function Discovery.snapshot.isDebugEnabled(entry, snapshot)
        return ReadPersisted(entry, "DebugMode", snapshot) == true
    end

    function Discovery.snapshot.setDebugEnabled(entry, value, snapshot)
        local host = Discovery.snapshot.getHost(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end
        host.setDebugMode(value)
        return true
    end

    return Discovery
end
