local lu = require('luaunit')

TestLibManagedModule = {}

function TestLibManagedModule:testCommitStagedStateFlushesManagedAliasState()
    local config = { Flag = false, Enabled = false, DebugMode = false }
    local definition = LibManagedModule.prepareDefinition({}, {
        id = "ManagedState",
        name = "Managed State",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    local persistentState, stagedState = CreateModuleState(config, definition)
    local liveModule = LibManagedModule.create({
        pluginGuid = "test-managed-state",
        definition = definition,
        persistentState = persistentState,
        stagedState = stagedState,
        drawTab = function() end,
    })

    stagedState.write("Flag", true)

    liveModule.activate()
    local ok, err = liveModule.flush()

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(config.Flag)
    lu.assertFalse(stagedState.isDirty())
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


