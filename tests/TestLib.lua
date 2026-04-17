local lu = require('luaunit')

TestLibHost = {}

function TestLibHost:testCommitStateFlushesManagedAliasState()
    local config = { Flag = false, Enabled = false, DebugMode = false }
    local definition = {
        id = "ManagedState",
        name = "Managed State",
        storage = {
            { type = "bool", alias = "Flag", configKey = "Flag", default = false },
        },
        affectsRunData = false,
    }
    local store = lib.store.create(config, definition)
    local uiState = store.uiState

    uiState.set("Flag", true)

    local ok, err = lib.host.commitState(definition, store, uiState)

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(config.Flag)
    lu.assertFalse(uiState.isDirty())
end

function TestLibHost:testCommitStateRejectsMissingUiState()
    local ok, err = lib.host.commitState({ id = "Missing" }, { read = function() return false end }, nil)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "uiState is missing transactional commit helpers")
end

TestLibValidation = {}

function TestLibValidation:testDuplicateStorageAliasesWarn()
    CaptureWarnings()
    lib.storage.validate({
        { type = "bool", alias = "Flag", configKey = "FlagA", default = false },
        { type = "bool", alias = "Flag", configKey = "FlagB", default = false },
    }, "DuplicateStorage")
    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "duplicate alias 'Flag'")
end
