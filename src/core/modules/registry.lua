-- Indexes coordinated modules through the Lib live-module registry and snapshots live host pointers
-- so UI/runtime work can tolerate hot-replaced hosts safely.

local deps = ...
local rom = deps.rom
local logging = deps.logging

local function createModuleRegistry(packId, config, frameworkRuntime)
    local ModuleRegistry = {}
    local warnedMissingHosts = {}
    local modules = assert(frameworkRuntime and frameworkRuntime.modules,
        "core/modules/registry: framework runtime modules are required")

    local function GetHost(pluginGuid)
        return modules.getLiveHost(pluginGuid)
    end

    local function ReadStorage(host)
        return host.getStorage()
    end

    local function ReadMeta(host)
        return host.getMeta()
    end

    local function ReadHashHints(host)
        return host.getHashHints()
    end

    local function ReadPersisted(entry, alias, snapshot)
        local host = ModuleRegistry.snapshot.getHost(entry, snapshot)
        if not host then
            return nil
        end
        return host.read(alias)
    end

    local function WriteStagedAndFlush(entry, alias, value, snapshot)
        local host = ModuleRegistry.snapshot.getHost(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end
        return host.writeAndFlush(alias, value)
    end

    local function SetEntryEnabled(entry, enabled, snapshot)
        local host = ModuleRegistry.snapshot.getHost(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end

        local ok, err = host.setEnabled(enabled)
        if not ok then
            logging.warn(packId,
                "%s %s failed: %s", entry.pluginGuid, enabled and "enable" or "disable", err)
        end
        return ok, err
    end

    local function RunPackLifecycle(entry, snapshot, actionName, invoke)
        local host = ModuleRegistry.snapshot.getHost(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end

        local ok, err, nextReceipt = invoke(host)
        if not ok then
            logging.warn(packId,
                "%s %s failed: %s", entry.pluginGuid, actionName, err)
        end
        return ok, err, nextReceipt
    end

    local function BuildEntry(found)
        local meta = found.meta
        local moduleId = found.moduleId

        return {
            pluginGuid = found.pluginGuid,
            mod = found.mod,
            id = moduleId,
            modpack = found.packId,
            name = meta.name or moduleId,
            shortName = meta.shortName,
            tooltip = meta.tooltip or "",
            hashHints = found.hashHints,
            storage = found.storage,
            _enableLabel = "Enable " .. tostring(meta.name or moduleId or found.pluginGuid),
            _debugLabel = tostring(meta.name or moduleId or found.pluginGuid)
                .. "##" .. tostring(moduleId or found.pluginGuid),
        }
    end

    ModuleRegistry.modules = {}
    ModuleRegistry.modulesById = {}
    ModuleRegistry.modulesWithQuickContent = {}
    ModuleRegistry.tabOrder = {}
    ModuleRegistry.live = {}
    ModuleRegistry.snapshot = {}

    function ModuleRegistry.refresh(moduleOrder)
        ModuleRegistry.modules = {}
        ModuleRegistry.modulesById = {}
        ModuleRegistry.modulesWithQuickContent = {}
        ModuleRegistry.tabOrder = {}

        local found = {}
        for pluginGuid, mod in pairs(rom.mods) do
            local host = GetHost(pluginGuid)
            if host then
                local hostPackId = host.getPackId()
                if hostPackId == packId then
                    table.insert(found, {
                        pluginGuid = pluginGuid,
                        mod = mod,
                        host = host,
                        storage = ReadStorage(host),
                        moduleId = host.getModuleId(),
                        packId = hostPackId,
                        meta = ReadMeta(host),
                        hashHints = ReadHashHints(host),
                    })
                end
            end
        end

        table.sort(found, function(a, b)
            local aName = a.meta.name or a.moduleId or a.pluginGuid
            local bName = b.meta.name or b.moduleId or b.pluginGuid
            return aName < bName
        end)

        local duplicateNamespaces = {}
        local namespaceEntries = {}
        for _, entry in ipairs(found) do
            local namespace = entry.moduleId
            if namespace ~= nil then
                namespaceEntries[namespace] = namespaceEntries[namespace] or {}
                table.insert(namespaceEntries[namespace], entry.pluginGuid)
            end
        end

        for namespace, entries in pairs(namespaceEntries) do
            if namespace == "_v" then
                duplicateNamespaces[namespace] = true
                table.sort(entries)
                logging.warn(packId,
                    "reserved hash namespace '%s' is used by: %s; skipping all conflicting entries",
                    tostring(namespace), table.concat(entries, ", "))
            elseif #entries > 1 then
                duplicateNamespaces[namespace] = true
                table.sort(entries)
                logging.warn(packId,
                    "duplicate hash namespace '%s' across entries: %s; skipping all conflicting entries",
                    tostring(namespace), table.concat(entries, ", "))
            end
        end

        for _, foundModule in ipairs(found) do
            local host = foundModule.host
            local id = foundModule.moduleId
            local hasQuickContent = host and type(host.drawQuickContent) == "function"

            if not duplicateNamespaces[id] then
                local discovered = BuildEntry(foundModule)
                table.insert(ModuleRegistry.modules, discovered)
                ModuleRegistry.modulesById[discovered.id] = discovered
                if hasQuickContent then
                    table.insert(ModuleRegistry.modulesWithQuickContent, discovered)
                end
            end
        end

        local labelCount = {}
        for _, entry in ipairs(ModuleRegistry.modules) do
            local label = entry.shortName or entry.name
            labelCount[label] = (labelCount[label] or 0) + 1
        end

        local labelIndex = {}
        for _, entry in ipairs(ModuleRegistry.modules) do
            local label = entry.shortName or entry.name
            if labelCount[label] > 1 then
                labelIndex[label] = (labelIndex[label] or 0) + 1
                entry._tabLabel = label .. " (" .. labelIndex[label] .. ")"
                logging.warnIf(packId, config.DebugMode,
                    "%s: shortName '%s' is shared by multiple modules. Rendering as '%s'.",
                    entry.pluginGuid, label, entry._tabLabel)
            else
                entry._tabLabel = label
            end
        end

        local placed = {}
        if type(moduleOrder) == "table" then
            for _, moduleId in ipairs(moduleOrder) do
                if type(moduleId) == "string" and ModuleRegistry.modulesById[moduleId] then
                    local entry = ModuleRegistry.modulesById[moduleId]
                    if not placed[entry.id] then
                        placed[entry.id] = true
                        table.insert(ModuleRegistry.tabOrder, entry)
                    end
                elseif type(moduleId) == "string" then
                    logging.warnIf(packId, config.DebugMode,
                        "moduleOrder contains unknown module id '%s'; entry ignored", moduleId)
                end
            end
        end

        for _, entry in ipairs(ModuleRegistry.modules) do
            if not placed[entry.id] then
                table.insert(ModuleRegistry.tabOrder, entry)
            end
        end
    end

    function ModuleRegistry.live.captureSnapshot()
        local snapshot = { hosts = {} }

        for _, entry in ipairs(ModuleRegistry.modules) do
            local host = GetHost(entry.pluginGuid)
            snapshot.hosts[entry] = host or false
            if not host and not warnedMissingHosts[entry.pluginGuid] then
                warnedMissingHosts[entry.pluginGuid] = true
                logging.warn(packId, "%s: module host is unavailable", entry.pluginGuid)
            end
        end

        return snapshot
    end

    function ModuleRegistry.live.getHost(entry)
        return GetHost(entry.pluginGuid)
    end

    function ModuleRegistry.snapshot.getHost(entry, snapshot)
        local host = snapshot.hosts[entry]
        return host or nil
    end

    function ModuleRegistry.snapshot.isEntryEnabled(entry, snapshot)
        return ReadPersisted(entry, "Enabled", snapshot) == true
    end

    function ModuleRegistry.snapshot.affectsRunData(entry, snapshot)
        local host = ModuleRegistry.snapshot.getHost(entry, snapshot)
        return host ~= nil and host.affectsRunData() == true
    end

    function ModuleRegistry.snapshot.setEntryEnabled(entry, enabled, snapshot)
        return SetEntryEnabled(entry, enabled, snapshot)
    end

    function ModuleRegistry.snapshot.suspendForPackDisable(entry, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack suspend", function(host)
            return host.suspendForPackDisable()
        end)
    end

    function ModuleRegistry.snapshot.ensureSuspendedForPackDisable(entry, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack suspend", function(host)
            return host.ensureSuspendedForPackDisable()
        end)
    end

    function ModuleRegistry.snapshot.restoreForPackEnable(entry, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack restore", function(host)
            return host.restoreForPackEnable()
        end)
    end

    function ModuleRegistry.snapshot.rollbackPackTransition(entry, receipt, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack rollback", function(host)
            return host.rollbackPackTransition(receipt)
        end)
    end

    function ModuleRegistry.snapshot.restorePackTransitionState(entry, receipt, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack state restore", function(host)
            return host.restorePackTransitionState(receipt)
        end)
    end

    function ModuleRegistry.snapshot.getStorageValue(module, alias, snapshot)
        return ReadPersisted(module, alias, snapshot)
    end

    function ModuleRegistry.snapshot.setStorageValue(module, alias, value, snapshot)
        return WriteStagedAndFlush(module, alias, value, snapshot)
    end

    function ModuleRegistry.snapshot.isDebugEnabled(entry, snapshot)
        return ReadPersisted(entry, "DebugMode", snapshot) == true
    end

    function ModuleRegistry.snapshot.setDebugEnabled(entry, value, snapshot)
        local host = ModuleRegistry.snapshot.getHost(entry, snapshot)
        if not host then
            return false, "module host is unavailable"
        end
        host.setDebugMode(value)
        return true
    end

    return ModuleRegistry
end

return createModuleRegistry
