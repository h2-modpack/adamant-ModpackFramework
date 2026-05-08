local lu = require('luaunit')

TestLibHost = {}

function TestLibHost:testCommitSessionFlushesManagedAliasState()
    local config = { Flag = false, Enabled = false, DebugMode = false }
    local definition = lib.prepareDefinition({}, {
        id = "ManagedState",
        name = "Managed State",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    local store, session = lib.createStore(config, definition)

    session.write("Flag", true)

    local ok, err = lib.lifecycle.commitSession(definition, nil, nil, store, session)

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(config.Flag)
    lu.assertFalse(session.isDirty())
end

TestLibValidation = {}

function TestLibValidation:testDuplicateStorageAliasesFail()
    lu.assertErrorMsgContains("duplicate alias 'Flag'", function()
        AdamantModpackLib_Internal.storage.validate({
            { type = "bool", alias = "Flag", default = false },
            { type = "bool", alias = "Flag", default = false },
        }, "DuplicateStorage")
    end)
end


