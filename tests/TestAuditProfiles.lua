local lu = require('luaunit')

TestAuditProfiles = {}

function TestAuditProfiles:setUp()
    CaptureWarnings()
end

function TestAuditProfiles:tearDown()
    RestoreWarnings()
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
