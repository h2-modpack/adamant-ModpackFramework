local lu = require('luaunit')

TestLibSpecialUiPass = {}

function TestLibSpecialUiPass:testFlushesManagedStateAndCallsCallback()
    local modConfig = {
        Flag = false,
    }
    local schema = {
        { type = "checkbox", configKey = "Flag", default = false },
    }
    local specialState = lib.createSpecialState(modConfig, schema)

    local flushed = false
    local didFlush = lib.runSpecialUiPass({
        name = "MySpecial",
        config = modConfig,
        schema = schema,
        specialState = specialState,
        validateEnabled = false,
        draw = function(_, state)
            state.set("Flag", true)
        end,
        onFlushed = function()
            flushed = true
        end,
    })

    lu.assertTrue(didFlush)
    lu.assertTrue(flushed)
    lu.assertTrue(modConfig.Flag)
end

function TestLibSpecialUiPass:testValidationUsesSingleLibOwnedToggle()
    local modConfig = {
        Flag = false,
    }
    local schema = {
        { type = "checkbox", configKey = "Flag", default = false },
    }
    local specialState = lib.createSpecialState(modConfig, schema)

    local previousValidation = lib.config.DebugSpecialConfigWrites
    local previousLegacyValidation = lib.config.DebugStateValidation
    lib.config.DebugSpecialConfigWrites = true
    lib.config.DebugStateValidation = false
    CaptureWarnings()

    lib.runSpecialUiPass({
        name = "MySpecial",
        config = modConfig,
        schema = schema,
        specialState = specialState,
        draw = function()
            modConfig.Flag = true
        end,
    })

    local warnings = Warnings
    RestoreWarnings()
    lib.config.DebugSpecialConfigWrites = previousValidation
    lib.config.DebugStateValidation = previousLegacyValidation

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "special UI modified config directly")
end

function TestLibSpecialUiPass:testValidationWarnsOnMixedManagedAndDirectWrites()
    local modConfig = {
        FlagA = false,
        FlagB = false,
    }
    local schema = {
        { type = "checkbox", configKey = "FlagA", default = false },
        { type = "checkbox", configKey = "FlagB", default = false },
    }
    local specialState = lib.createSpecialState(modConfig, schema)

    CaptureWarnings()

    lib.runSpecialUiPass({
        name = "MySpecial",
        config = modConfig,
        schema = schema,
        specialState = specialState,
        validateEnabled = true,
        draw = function(_, state)
            state.set("FlagA", true)
            modConfig.FlagB = true
        end,
    })

    local warnings = Warnings
    RestoreWarnings()

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "special UI modified config directly")
    lu.assertTrue(modConfig.FlagA)
end

TestLibSchemaValidation = {}

function TestLibSchemaValidation:testDuplicateConfigKeysWarn()
    local previousDebugMode = lib.config.DebugMode
    lib.config.DebugMode = true
    CaptureWarnings()

    lib.validateSchema({
        { type = "checkbox", configKey = "Flag", default = false },
        { type = "checkbox", configKey = "Flag", default = false },
    }, "DuplicateSchema")

    local warnings = Warnings
    RestoreWarnings()
    lib.config.DebugMode = previousDebugMode

    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "duplicate configKey 'Flag'")
end
