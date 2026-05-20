local lu = require('luaunit')

TestLibHost = {}

function TestLibHost:testCommitSessionFlushesManagedAliasState()
    local config = { Flag = false, Enabled = false, DebugMode = false }
    local definition = LibModuleHost.prepareDefinition({}, {
        id = "ManagedState",
        name = "Managed State",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    local store, session = CreateModuleState(config, definition)
    local host, authorHost = LibModuleHost.create({
        pluginGuid = "test-managed-state",
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    session.write("Flag", true)

    authorHost.activate()
    local ok, err = host.flush()

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(config.Flag)
    lu.assertFalse(session.isDirty())
end

TestLibValidation = {}

function TestLibValidation:testDuplicateStorageAliasesFail()
    lu.assertErrorMsgContains("duplicate alias 'Flag'", function()
        LibStorage.validate({
            { type = "bool", alias = "Flag", default = false },
            { type = "bool", alias = "Flag", default = false },
        }, "DuplicateStorage")
    end)
end


