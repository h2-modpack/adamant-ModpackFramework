-- Indexes coordinated modules through the Lib live-module registry and snapshots live module pointers
-- so UI/runtime work can tolerate hot-replaced modules safely.

local deps = ...
local rom = deps.rom
local logging = deps.logging

local function createModuleRegistry(packId, config, frameworkRuntime)
    local ModuleRegistry = {}
    local warnedMissingModules = {}
    local modules = assert(frameworkRuntime and frameworkRuntime.modules,
        "core/modules/registry: framework runtime modules are required")

    local function getLiveModule(pluginGuid)
        return modules.getLiveModule(pluginGuid)
    end

    local function ReadStorage(liveModule)
        return liveModule.getStorage()
    end

    local function ReadMeta(liveModule)
        return liveModule.getMeta()
    end

    local function ReadPersisted(entry, alias, snapshot)
        local liveModule = ModuleRegistry.snapshot.getLiveModule(entry, snapshot)
        if not liveModule then
            return nil
        end
        return liveModule.read(alias)
    end

    local function WriteStagedAndFlush(entry, alias, value, snapshot)
        local liveModule = ModuleRegistry.snapshot.getLiveModule(entry, snapshot)
        if not liveModule then
            return false, "live module is unavailable"
        end
        return liveModule.writeAndFlush(alias, value)
    end

    local function SetEntryEnabled(entry, enabled, snapshot)
        local liveModule = ModuleRegistry.snapshot.getLiveModule(entry, snapshot)
        if not liveModule then
            return false, "live module is unavailable"
        end

        local ok, err = liveModule.setEnabled(enabled)
        if not ok then
            logging.warn(packId,
                "%s %s failed: %s", entry.pluginGuid, enabled and "enable" or "disable", err)
        end
        return ok, err
    end

    local function RunPackLifecycle(entry, snapshot, actionName, invoke)
        local liveModule = ModuleRegistry.snapshot.getLiveModule(entry, snapshot)
        if not liveModule then
            return false, "live module is unavailable"
        end

        local ok, err, nextReceipt = invoke(liveModule)
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
            local liveModule = getLiveModule(pluginGuid)
            if liveModule then
                local liveModulePackId = liveModule.getPackId()
                if liveModulePackId == packId then
                    table.insert(found, {
                        pluginGuid = pluginGuid,
                        mod = mod,
                        liveModule = liveModule,
                        storage = ReadStorage(liveModule),
                        moduleId = liveModule.getModuleId(),
                        packId = liveModulePackId,
                        meta = ReadMeta(liveModule),
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
            local liveModule = foundModule.liveModule
            local id = foundModule.moduleId
            local hasQuickContent = liveModule and type(liveModule.drawQuickContent) == "function"

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
        local snapshot = { liveModules = {} }

        for _, entry in ipairs(ModuleRegistry.modules) do
            local liveModule = getLiveModule(entry.pluginGuid)
            snapshot.liveModules[entry] = liveModule or false
            if not liveModule and not warnedMissingModules[entry.pluginGuid] then
                warnedMissingModules[entry.pluginGuid] = true
                logging.warn(packId, "%s: live module is unavailable", entry.pluginGuid)
            end
        end

        return snapshot
    end

    function ModuleRegistry.live.getLiveModule(entry)
        return getLiveModule(entry.pluginGuid)
    end

    function ModuleRegistry.snapshot.getLiveModule(entry, snapshot)
        local liveModule = snapshot.liveModules[entry]
        return liveModule or nil
    end

    function ModuleRegistry.snapshot.isEntryEnabled(entry, snapshot)
        return ReadPersisted(entry, "Enabled", snapshot) == true
    end

    function ModuleRegistry.snapshot.affectsRunData(entry, snapshot)
        local liveModule = ModuleRegistry.snapshot.getLiveModule(entry, snapshot)
        return liveModule ~= nil and liveModule.affectsRunData() == true
    end

    function ModuleRegistry.snapshot.setEntryEnabled(entry, enabled, snapshot)
        return SetEntryEnabled(entry, enabled, snapshot)
    end

    function ModuleRegistry.snapshot.suspendForPackDisable(entry, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack suspend", function(liveModule)
            return liveModule.suspendForPackDisable()
        end)
    end

    function ModuleRegistry.snapshot.ensureSuspendedForPackDisable(entry, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack suspend", function(liveModule)
            return liveModule.ensureSuspendedForPackDisable()
        end)
    end

    function ModuleRegistry.snapshot.restoreForPackEnable(entry, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack restore", function(liveModule)
            return liveModule.restoreForPackEnable()
        end)
    end

    function ModuleRegistry.snapshot.rollbackPackTransition(entry, receipt, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack rollback", function(liveModule)
            return liveModule.rollbackPackTransition(receipt)
        end)
    end

    function ModuleRegistry.snapshot.restorePackTransitionState(entry, receipt, snapshot)
        return RunPackLifecycle(entry, snapshot, "pack state restore", function(liveModule)
            return liveModule.restorePackTransitionState(receipt)
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
        local liveModule = ModuleRegistry.snapshot.getLiveModule(entry, snapshot)
        if not liveModule then
            return false, "live module is unavailable"
        end
        liveModule.setDebugMode(value)
        return true
    end

    return ModuleRegistry
end

return createModuleRegistry
