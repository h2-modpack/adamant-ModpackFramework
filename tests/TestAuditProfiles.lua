local lu = require('luaunit')

TestAuditProfiles = {}

function TestAuditProfiles:setUp()
    CaptureWarnings()
end

function TestAuditProfiles:tearDown()
    RestoreWarnings()
end

function TestAuditProfiles:testNormalizeProfilesCoercesProfileTextFieldsToStrings()
    local tooltip = { "tip" }
    local profiles = {
        { Name = 123, Hash = false, Tooltip = tooltip },
    }

    FrameworkTestApi.normalizeProfiles(profiles, 1)

    lu.assertEquals(profiles[1].Name, "123")
    lu.assertEquals(profiles[1].Hash, "false")
    lu.assertEquals(profiles[1].Tooltip, tostring(tooltip))
end

function TestAuditProfiles:testKnownStorageAliasesProduceNoWarnings()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
        },
    })

    -- SpecialBiome is not a discovered module; its hash keys are an unknown namespace and
    -- should be silently ignored (not installed vs. renamed are indistinguishable).
    FrameworkTestApi.auditSavedProfiles("test-pack", {
        { Name = "Known", Hash = "_v=1|GodPool=1|GodPool.EnabledFlag=1|SpecialBiome=1|SpecialBiome.Mode=Chaos", Tooltip = "" },
    }, discovery, lib)

    lu.assertEquals(#Warnings, 0)
end

function TestAuditProfiles:testUnknownKeyInKnownNamespaceWarns()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
        },
    })

    FrameworkTestApi.auditSavedProfiles("test-pack", {
        { Name = "Broken", Hash = "_v=1|GodPool.MissingField=1", Tooltip = "" },
    }, discovery, lib)

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "Profile 'Broken': unrecognized key 'GodPool.MissingField'")
end

function TestAuditProfiles:testKnownHashGroupKeysProduceNoWarnings()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            storage = {
                { type = "int", alias = "PoolOne", default = 0, min = 0, max = 3 },
                { type = "int", alias = "PoolTwo", default = 0, min = 0, max = 3 },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "pool",
                    items = { "PoolOne", "PoolTwo" },
                },
            },
        },
    })

    FrameworkTestApi.auditSavedProfiles("test-pack", {
        { Name = "Grouped", Hash = "_v=1|GodPool.pool_1=5", Tooltip = "" },
    }, discovery, lib)

    lu.assertEquals(#Warnings, 0)
end

function TestAuditProfiles:testGroupedRootAliasesWarnBecauseDecoderIgnoresThem()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            storage = {
                { type = "int", alias = "PoolOne", default = 0, min = 0, max = 3 },
                { type = "int", alias = "PoolTwo", default = 0, min = 0, max = 3 },
            },
            hashGroupPlan = {
                {
                    keyPrefix = "pool",
                    items = { "PoolOne", "PoolTwo" },
                },
            },
        },
    })

    FrameworkTestApi.auditSavedProfiles("test-pack", {
        { Name = "Stale", Hash = "_v=1|GodPool.PoolOne=2|GodPool.pool_1=5", Tooltip = "" },
    }, discovery, lib)

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "Profile 'Stale': unrecognized key 'GodPool.PoolOne'")
end

function TestAuditProfiles:testBuiltInEnabledAliasWarnsBecauseDecoderUsesModuleKey()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
        },
    })

    FrameworkTestApi.auditSavedProfiles("test-pack", {
        { Name = "Stale", Hash = "_v=1|GodPool=1|GodPool.Enabled=1", Tooltip = "" },
    }, discovery, lib)

    lu.assertEquals(#Warnings, 1)
    lu.assertStrContains(Warnings[1], "Profile 'Stale': unrecognized key 'GodPool.Enabled'")
end

function TestAuditProfiles:testUnknownNamespaceIsIgnored()
    local discovery = MockDiscovery.create({
        {
            id = "GodPool",
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
        },
    })

    FrameworkTestApi.auditSavedProfiles("test-pack", {
        { Name = "Foreign", Hash = "_v=1|UnknownModule.Field=1", Tooltip = "" },
    }, discovery, lib)

    lu.assertEquals(#Warnings, 0)
end
