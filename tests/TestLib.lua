local lu = require('luaunit')

TestLibHost = {}

function TestLibHost:testCommitSessionFlushesManagedAliasState()
    local config = { Flag = false, Enabled = false, DebugMode = false }
    local definition = AdamantModpackLib_Internal.moduleHost.prepareDefinition({}, {
        id = "ManagedState",
        name = "Managed State",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    local store, session = CreateModuleState(config, definition)
    local host, authorHost = AdamantModpackLib_Internal.moduleHost.create({
        pluginGuid = "test-managed-state",
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    session.write("Flag", true)

    authorHost.tryActivate()
    local ok, err = host.flush()

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


