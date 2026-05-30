local lu = require('luaunit')

local function makeConfigHash(moduleRegistry)
    return FrameworkTestApi.createConfigHash(moduleRegistry, { DebugMode = false }, "test-pack")
end

local function assertWarningContains(fragment)
    for _, warning in ipairs(Warnings) do
        if string.find(warning, fragment, 1, true) then
            return
        end
    end
    lu.fail("expected warning containing '" .. fragment .. "'")
end

TestConfigHashStorage = {}

function TestConfigHashStorage:testAllDefaultsProduceVersionOnlyCanonical()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            enabled = false,
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
                { type = "int", alias = "Count", default = 3, min = 1, max = 9 },
            },
            values = {
                EnabledFlag = false,
                Count = 3,
            },
        },
    })

    local canonical = makeConfigHash(moduleRegistry).GetConfigHash()

    lu.assertEquals(canonical, "_v=2")
end

function TestConfigHashStorage:testRegularAndSpecialStorageRoundTrip()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            enabled = true,
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
                { type = "int", alias = "Count", default = 3, min = 1, max = 9 },
            },
            values = {
                EnabledFlag = true,
                Count = 7,
            },
        },
        {
            id = "BiomeControl",
            name = "Biome Control",
            enabled = true,
            storage = {
                { type = "string", alias = "Mode", default = "Vanilla" },
            },
            values = {
                Mode = "Chaos",
            },
            DrawTab = function() end,
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local canonical = configHash.GetConfigHash()

    lu.assertStrContains(canonical, "GodPool=1")
    lu.assertStrContains(canonical, "GodPool.EnabledFlag=1")
    lu.assertStrContains(canonical, "GodPool.Count=7")
    lu.assertStrContains(canonical, "BiomeControl=1")
    lu.assertStrContains(canonical, "BiomeControl.Mode=Chaos")

    local module = moduleRegistry.modulesById.GodPool
    local biome = moduleRegistry.modulesById.BiomeControl
    local moduleHost = moduleRegistry.live.getHost(module)
    local biomeHost = moduleRegistry.live.getHost(biome)
    local editSnapshot = moduleRegistry.live.captureSnapshot()
    moduleRegistry.snapshot.setEntryEnabled(module, false, editSnapshot)
    moduleHost.writeAndFlush("EnabledFlag", false)
    moduleHost.writeAndFlush("Count", 3)
    moduleRegistry.snapshot.setEntryEnabled(biome, false, editSnapshot)
    biomeHost.writeAndFlush("Mode", "Vanilla")

    lu.assertTrue(configHash.ApplyConfigHash(canonical))
    lu.assertTrue(moduleHost.read("Enabled"))
    lu.assertTrue(moduleHost.read("EnabledFlag"))
    lu.assertEquals(moduleHost.read("Count"), 7)
    lu.assertTrue(biomeHost.read("Enabled"))
    lu.assertEquals(biomeHost.read("Mode"), "Chaos")
end

function TestConfigHashStorage:testStringStorageEscapesHashDelimiters()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "BiomeControl",
            name = "Biome Control",
            enabled = true,
            storage = {
                { type = "string", alias = "Filter", default = "" },
            },
            values = {
                Filter = "Apollo|Zeus=Poseidon%Chaos",
            },
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local canonical = configHash.GetConfigHash()
    local module = moduleRegistry.modulesById.BiomeControl
    local host = moduleRegistry.live.getHost(module)

    lu.assertStrContains(canonical, "BiomeControl.Filter=Apollo%7CZeus%3DPoseidon%25Chaos")
    lu.assertNotStrContains(canonical, "Apollo|Zeus")

    host.writeAndFlush("Filter", "")
    lu.assertTrue(configHash.ApplyConfigHash(canonical))
    lu.assertEquals(host.read("Filter"), "Apollo|Zeus=Poseidon%Chaos")
end

function TestConfigHashStorage:testFingerprintChangesWithConfig()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            enabled = false,
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            values = { EnabledFlag = false },
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local canonicalA, fingerprintA = configHash.GetConfigHash()

    moduleRegistry.live.getHost(moduleRegistry.modulesById.GodPool).writeAndFlush("EnabledFlag", true)
    local canonicalB, fingerprintB = configHash.GetConfigHash()

    lu.assertNotEquals(canonicalA, canonicalB)
    lu.assertNotEquals(fingerprintA, fingerprintB)
end

function TestConfigHashStorage:testApplyConfigHashRollsBackWhenEnableFails()
    local buildCalls = 0
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            enabled = false,
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            values = { EnabledFlag = false },
            patchPlan = function()
                buildCalls = buildCalls + 1
                error("apply boom")
            end,
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local module = moduleRegistry.modulesById.GodPool
    local moduleHost = moduleRegistry.live.getHost(module)

    local ok = configHash.ApplyConfigHash("_v=2|GodPool=1|GodPool.EnabledFlag=1")

    lu.assertFalse(ok)
    lu.assertFalse(moduleHost.read("Enabled"))
    lu.assertFalse(moduleHost.read("EnabledFlag"))
    lu.assertEquals(buildCalls, 1)
end

function TestConfigHashStorage:testApplyConfigHashRollsBackWhenFlushFails()
    local failApply = false
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "BiomeControl",
            name = "Biome Control",
            enabled = false,
            storage = {
                { type = "string", alias = "Mode", default = "Vanilla" },
            },
            values = {
                Mode = "Vanilla",
            },
        },
        {
            id = "GodPool",
            enabled = true,
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            values = { EnabledFlag = false },
            patchPlan = function()
                if failApply then
                    failApply = false
                    error("apply boom")
                end
            end,
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local biomeHost = moduleRegistry.live.getHost(moduleRegistry.modulesById.BiomeControl)
    local godHost = moduleRegistry.live.getHost(moduleRegistry.modulesById.GodPool)
    failApply = true

    local ok = configHash.ApplyConfigHash("_v=2|BiomeControl.Mode=Chaos|GodPool=1|GodPool.EnabledFlag=1")

    lu.assertFalse(ok)
    lu.assertEquals(biomeHost.read("Mode"), "Vanilla")
    lu.assertFalse(godHost.read("EnabledFlag"))
    lu.assertTrue(godHost.read("Enabled"))
end

function TestConfigHashStorage:testApplyConfigHashRejectsUnsupportedVersion()
    CaptureWarnings()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            enabled = false,
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            values = { EnabledFlag = false },
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local moduleHost = moduleRegistry.live.getHost(moduleRegistry.modulesById.GodPool)

    local ok = configHash.ApplyConfigHash("_v=999|GodPool=1|GodPool.EnabledFlag=1")

    lu.assertFalse(ok)
    lu.assertFalse(moduleHost.read("Enabled"))
    lu.assertFalse(moduleHost.read("EnabledFlag"))
    assertWarningContains("is not supported")
    RestoreWarnings()
end

function TestConfigHashStorage:testApplyConfigHashRejectsInvalidModuleEnableToken()
    CaptureWarnings()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            enabled = false,
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
            },
            values = { EnabledFlag = false },
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local moduleHost = moduleRegistry.live.getHost(moduleRegistry.modulesById.GodPool)

    local ok = configHash.ApplyConfigHash("_v=2|GodPool=enabled|GodPool.EnabledFlag=1")

    lu.assertFalse(ok)
    lu.assertFalse(moduleHost.read("Enabled"))
    lu.assertFalse(moduleHost.read("EnabledFlag"))
    assertWarningContains("invalid module enable value")
    RestoreWarnings()
end

function TestConfigHashStorage:testApplyConfigHashRejectsInvalidScalarStorageToken()
    CaptureWarnings()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            enabled = false,
            storage = {
                { type = "int", alias = "Count", default = 3, min = 1, max = 9 },
            },
            values = { Count = 3 },
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local moduleHost = moduleRegistry.live.getHost(moduleRegistry.modulesById.GodPool)

    local ok = configHash.ApplyConfigHash("_v=2|GodPool.Count=not-a-number")

    lu.assertFalse(ok)
    lu.assertEquals(moduleHost.read("Count"), 3)
    assertWarningContains("invalid storage root 'Count' hash value")
    RestoreWarnings()
end

function TestConfigHashStorage:testApplyConfigHashRejectsInvalidTableStorageToken()
    CaptureWarnings()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            enabled = false,
            storage = {
                {
                    type = "table",
                    alias = "Rows",
                    minRows = 0,
                    maxRows = 2,
                    defaultRows = 0,
                    row = {
                        { type = "bool", alias = "Flag", default = false },
                    },
                },
            },
            values = { Rows = {} },
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local moduleHost = moduleRegistry.live.getHost(moduleRegistry.modulesById.GodPool)

    local ok = configHash.ApplyConfigHash("_v=2|GodPool.Rows=not-a-table")

    lu.assertFalse(ok)
    lu.assertEquals(moduleHost.read("Rows"), {})
    assertWarningContains("invalid storage root 'Rows' hash value")
    RestoreWarnings()
end

function TestConfigHashStorage:testTransientRootsAreExcludedFromHash()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            enabled = false,
            storage = {
                { type = "bool", alias = "EnabledFlag", default = false },
                { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
            },
            values = {
                EnabledFlag = true,
                FilterText = "Apollo",
            },
        },
    })

    moduleRegistry.live.getHost(moduleRegistry.modulesById.GodPool).stage("FilterText", "Apollo")
    local canonical = makeConfigHash(moduleRegistry).GetConfigHash()

    lu.assertStrContains(canonical, "GodPool.EnabledFlag=1")
    lu.assertNotStrContains(canonical, "FilterText")
end

