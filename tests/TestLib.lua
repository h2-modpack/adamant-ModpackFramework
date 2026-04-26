local lu = require('luaunit')

TestLibHost = {}

function TestLibHost:testCommitSessionFlushesManagedAliasState()
    local config = { Flag = false, Enabled = false, DebugMode = false }
    local definition = lib.prepareDefinition({}, {
        id = "ManagedState",
        name = "Managed State",
        storage = {
            { type = "bool", alias = "Flag", configKey = "Flag", default = false },
        },
        affectsRunData = false,
    })
    local store, session = lib.createStore(config, definition)

    session.write("Flag", true)

    local ok, err = lib.lifecycle.commitSession(definition, store, session)

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(config.Flag)
    lu.assertFalse(session.isDirty())
end

TestLibValidation = {}

function TestLibValidation:testDuplicateStorageAliasesWarn()
    CaptureWarnings()
    AdamantModpackLib_Internal.storage.validate({
        { type = "bool", alias = "Flag", configKey = "FlagA", default = false },
        { type = "bool", alias = "Flag", configKey = "FlagB", default = false },
    }, "DuplicateStorage")
    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "duplicate alias 'Flag'")
end


