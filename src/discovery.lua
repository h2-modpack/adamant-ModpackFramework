-- =============================================================================
-- MODULE DISCOVERY
-- =============================================================================
-- Auto-discovers all installed modules that opt in via definition.modpack = packId.
-- Under the lean framework contract, every coordinated module gets its own top-level tab.
-- Modules render themselves through DrawTab; DrawQuickContent is optional.

local internal = AdamantModpackFramework_Internal

--- Create the discovery subsystem for one coordinator pack.
--- @param packId string Pack identifier used to filter opted-in modules.
--- @param config table Coordinator config table containing at least `DebugMode`.
--- @param lib table Adamant Modpack Lib export.
--- @return table discovery Discovery object with `run`, state accessors, and discovered entry lists.
function internal.createDiscovery(packId, config, lib)
    local Discovery = {}
    local contractWarn = lib.logging.warn
    local warnIf = lib.logging.warnIf
    local inferMutation = lib.lifecycle.inferMutation
    local mutatesRunData = lib.lifecycle.mutatesRunData

    local function GetLiveHost(modName)
        local mod = rom.mods[modName]
        return type(mod) == "table" and type(mod.host) == "table" and mod.host or nil
    end

    local function WarnMissingHost(entry)
        contractWarn(packId, "%s: module host is unavailable", tostring(entry.modName or entry.id or "module"))
    end

    local function ResolveLiveHost(entry)
        local host = GetLiveHost(entry.modName)
        if type(host) == "table" then
            return host
        end
        WarnMissingHost(entry)
        return nil
    end

    local function GetSnapshotHost(entry, snapshot)
        if snapshot and snapshot.hosts then
            local host = snapshot.hosts[entry]
            if host ~= nil then
                return host or nil
            end
        end

        WarnMissingHost(entry)
        return nil
    end

    local function GetHostForAccess(entry, snapshot)
        if snapshot ~= nil then
            return GetSnapshotHost(entry, snapshot)
        end
        return ResolveLiveHost(entry)
    end

    local function ReadPersisted(entry, key, snapshot)
        local host = GetHostForAccess(entry, snapshot)
        if not host then
            return nil
        end
        return host.read(key)
    end

    local function WriteStagedAndFlush(entry, key, value, snapshot)
        local host = GetHostForAccess(entry, snapshot)
        if host then
            return host.writeAndFlush(key, value)
        end
        return false
    end

    local function SetEntryEnabled(entry, enabled, snapshot)
        local host = GetHostForAccess(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end

        local ok, err = host.setEnabled(enabled)
        if not ok then
            contractWarn(packId,
                "%s %s failed: %s", entry.modName, enabled and "enable" or "disable", err)
        end
        return ok, err
    end

    local function SetEntryDebugMode(entry, val, snapshot)
        local host = GetHostForAccess(entry, snapshot)
        if host then
            host.setDebugMode(val)
        end
    end

    local function BuildEntry(modName, def)
        return {
            modName = modName,
            definition = def,
            id = def.id,
            name = def.name,
            shortName = def.shortName,
            default = def.default,
            storage = def.storage,
            _enableLabel = "Enable " .. tostring(def.name),
            _debugLabel = tostring(def.name or def.id or modName)
                .. "##" .. tostring(def.id or modName),
        }
    end

    -- Populated by Discovery.run()
    Discovery.modules = {}               -- ordered list of discovered modules
    Discovery.modulesById = {}           -- id -> module entry
    Discovery.modulesWithQuickContent = {}
    Discovery.tabOrder = {}              -- ordered list of module entries for the sidebar

    --- Discover all modules for this pack.
    --- @param moduleOrder table|nil Ordered list of module labels to pin first in the sidebar.
    function Discovery.run(moduleOrder)
        Discovery.modules = {}
        Discovery.modulesById = {}
        Discovery.modulesWithQuickContent = {}
        Discovery.tabOrder = {}

        local found = {}
        for modName, mod in pairs(rom.mods) do
            if type(mod) == "table" and mod.definition
                and mod.definition.modpack and mod.definition.modpack == packId then
                table.insert(found, { modName = modName, def = mod.definition })
            end
        end

        table.sort(found, function(a, b)
            return (a.def.name or a.def.id or a.modName) < (b.def.name or b.def.id or b.modName)
        end)

        local duplicateNamespaces = {}
        local namespaceEntries = {}
        for _, entry in ipairs(found) do
            local namespace = entry.def.id
            if namespace ~= nil then
                namespaceEntries[namespace] = namespaceEntries[namespace] or {}
                table.insert(namespaceEntries[namespace], entry.modName)
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

        for _, entry in ipairs(found) do
            local modName = entry.modName
            local def = entry.def
            local inferredMutationShape, mutationInfo = inferMutation(def)
            local hasLifecycle = mutationInfo.hasManual or mutationInfo.hasPatch
            local lifecycleRequired = mutatesRunData(def)
            local host = GetLiveHost(modName)
            local hasDrawTab = host and host.hasDrawTab() == true
            local hasQuickContent = host and host.hasQuickContent() == true

            if lifecycleRequired and not inferredMutationShape then
                contractWarn(packId,
                    "%s: affectsRunData=true but module exposes neither patchPlan nor apply/revert",
                    modName)
            end

            if not duplicateNamespaces[def.id] then
                if not def.id or not def.name or (lifecycleRequired and not hasLifecycle) then
                    contractWarn(packId,
                        "Skipping %s: missing id/name or lifecycle (patchPlan/apply/revert)", modName)
                elseif type(def.storage) ~= "table" then
                    contractWarn(packId, "Skipping %s: missing definition.storage", modName)
                elseif not host then
                    contractWarn(packId, "%s: module is missing public.host", modName)
                elseif not hasDrawTab then
                    contractWarn(packId,
                        "%s: coordinated modules must expose host.drawTab under the lean framework contract",
                        modName)
                else
                    local discovered = BuildEntry(modName, def)
                    table.insert(Discovery.modules, discovered)
                    Discovery.modulesById[def.id] = discovered
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
        local moduleByLabel = {}
        for _, entry in ipairs(Discovery.modules) do
            local label = entry.shortName or entry.name
            if labelCount[label] > 1 then
                labelIndex[label] = (labelIndex[label] or 0) + 1
                entry._tabLabel = label .. " (" .. labelIndex[label] .. ")"
                warnIf(packId, config.DebugMode,
                    "%s: shortName '%s' is shared by multiple modules. Rendering as '%s'.",
                    entry.modName, label, entry._tabLabel)
            else
                entry._tabLabel = label
            end
            moduleByLabel[entry._tabLabel] = entry
            if entry.name and not moduleByLabel[entry.name] then
                moduleByLabel[entry.name] = entry
            end
            if entry.id and not moduleByLabel[entry.id] then
                moduleByLabel[entry.id] = entry
            end
        end

        local placed = {}
        if type(moduleOrder) == "table" then
            for _, name in ipairs(moduleOrder) do
                if type(name) == "string" and moduleByLabel[name] then
                    local entry = moduleByLabel[name]
                    if not placed[entry.id] then
                        placed[entry.id] = true
                        table.insert(Discovery.tabOrder, entry)
                    end
                elseif type(name) == "string" then
                    warnIf(packId, config.DebugMode,
                        "moduleOrder contains unknown module label '%s'; entry ignored", name)
                end
            end
        end

        for _, entry in ipairs(Discovery.modules) do
            if not placed[entry.id] then
                table.insert(Discovery.tabOrder, entry)
            end
        end
    end

    function Discovery.captureHostSnapshot()
        local snapshot = {
            hosts = {},
        }

        for _, entry in ipairs(Discovery.modules) do
            snapshot.hosts[entry] = ResolveLiveHost(entry) or false
        end

        return snapshot
    end

    function Discovery.getCurrentHost(entry)
        return ResolveLiveHost(entry)
    end

    function Discovery.getSnapshotHost(entry, snapshot)
        return GetSnapshotHost(entry, snapshot)
    end

    function Discovery.isEntryEnabled(entry, snapshot)
        return ReadPersisted(entry, "Enabled", snapshot) == true
    end

    function Discovery.setEntryEnabled(entry, enabled, snapshot)
        return SetEntryEnabled(entry, enabled, snapshot)
    end

    function Discovery.getStorageValue(entry, aliasOrKey, snapshot)
        return ReadPersisted(entry, aliasOrKey, snapshot)
    end

    function Discovery.setStorageValue(entry, aliasOrKey, value, snapshot)
        return WriteStagedAndFlush(entry, aliasOrKey, value, snapshot)
    end

    function Discovery.isModuleEnabled(module, snapshot)
        return Discovery.isEntryEnabled(module, snapshot)
    end

    function Discovery.setModuleEnabled(module, enabled, snapshot)
        return Discovery.setEntryEnabled(module, enabled, snapshot)
    end

    function Discovery.isDebugEnabled(entry, snapshot)
        return ReadPersisted(entry, "DebugMode", snapshot) == true
    end

    function Discovery.setDebugEnabled(entry, val, snapshot)
        SetEntryDebugMode(entry, val, snapshot)
    end

    return Discovery
end
