-- =============================================================================
-- MODULE DISCOVERY
-- =============================================================================
-- Auto-discovers all installed modules that opt in via definition.modpack = packId.
-- Under the lean framework contract, every coordinated module gets its own top-level tab.
-- Modules render themselves through DrawTab; DrawQuickContent is optional.

--- Create the discovery subsystem for one coordinator pack.
--- @param packId string Pack identifier used to filter opted-in modules.
--- @param config table Coordinator config table containing at least `DebugMode`.
--- @param lib table Adamant Modpack Lib export.
--- @return table discovery Discovery object with `run`, state accessors, and discovered entry lists.
function Framework.createDiscovery(packId, config, lib)
    local Discovery = {}
    local contractWarn = lib.logging.warn
    local warnIf = lib.logging.warnIf
    local inferShape = lib.mutation.inferShape
    local mutatesRunData = lib.mutation.mutatesRunData
    local setEnabled = lib.mutation.setEnabled

    local function GetStore(mod)
        return type(mod.store) == "table" and mod.store or nil
    end

    local function ReadPersisted(mod, key)
        return GetStore(mod).read(key)
    end

    local function WritePersisted(mod, key, value)
        GetStore(mod).write(key, value)
    end

    local function GetUiState(mod)
        local store = GetStore(mod)
        return store and store.uiState or nil
    end

    local function SetEntryEnabled(entry, enabled)
        local ok, err = setEnabled(entry.definition, GetStore(entry.mod), enabled)
        if not ok then
            contractWarn(packId,
                "%s %s failed: %s", entry.modName, enabled and "enable" or "disable", err)
        end
        return ok, err
    end

    local function BuildEntry(entry)
        local def = entry.def
        local mod = entry.mod
        local modName = entry.modName

        return {
            modName = modName,
            mod = mod,
            definition = def,
            id = def.id,
            name = def.name,
            shortName = def.shortName,
            tooltip = def.tooltip or "",
            default = def.default,
            storage = def.storage,
            uiState = GetUiState(mod),
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
                table.insert(found, { modName = modName, mod = mod, def = mod.definition })
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
            local mod = entry.mod
            local def = entry.def
            local inferredMutationShape, mutationInfo = inferShape(def)
            local hasLifecycle = mutationInfo.hasManual or mutationInfo.hasPatch
            local lifecycleRequired = mutatesRunData(def)
            local store = GetStore(mod)
            local hasDrawTab = type(mod.DrawTab) == "function"
            local hasQuickContent = type(mod.DrawQuickContent) == "function"

            if mutatesRunData(def) and not inferredMutationShape then
                contractWarn(packId,
                    "%s: affectsRunData=true but module exposes neither patchPlan nor apply/revert",
                    modName)
            end

            if duplicateNamespaces[def.id] then
                -- Already warned once for the full collision set above.
            elseif not def.id or not def.name or (lifecycleRequired and not hasLifecycle) then
                contractWarn(packId,
                    "Skipping %s: missing id/name or lifecycle (patchPlan/apply/revert)", modName)
            elseif type(def.storage) ~= "table" then
                contractWarn(packId, "Skipping %s: missing definition.storage", modName)
            elseif not store or type(store.read) ~= "function" or type(store.write) ~= "function" then
                contractWarn(packId, "%s: module is missing public.store", modName)
            elseif not hasDrawTab then
                contractWarn(packId,
                    "%s: coordinated modules must expose DrawTab under the lean framework contract",
                    modName)
            else
                local discovered = BuildEntry(entry)
                table.insert(Discovery.modules, discovered)
                Discovery.modulesById[def.id] = discovered
                if hasQuickContent then
                    table.insert(Discovery.modulesWithQuickContent, discovered)
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

    function Discovery.isEntryEnabled(entry)
        return ReadPersisted(entry.mod, "Enabled") == true
    end

    function Discovery.setEntryEnabled(entry, enabled)
        return SetEntryEnabled(entry, enabled)
    end

    function Discovery.getStorageValue(entry, aliasOrKey)
        return ReadPersisted(entry.mod, aliasOrKey)
    end

    function Discovery.setStorageValue(entry, aliasOrKey, value)
        WritePersisted(entry.mod, aliasOrKey, value)
    end

    function Discovery.isModuleEnabled(module)
        return Discovery.isEntryEnabled(module)
    end

    function Discovery.setModuleEnabled(module, enabled)
        return Discovery.setEntryEnabled(module, enabled)
    end

    function Discovery.isDebugEnabled(entry)
        return ReadPersisted(entry.mod, "DebugMode") == true
    end

    function Discovery.setDebugEnabled(entry, val)
        WritePersisted(entry.mod, "DebugMode", val)
    end

    return Discovery
end
