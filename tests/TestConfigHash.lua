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
    local liveModule = moduleRegistry.live.getLiveModule(module)
    local biomeLiveModule = moduleRegistry.live.getLiveModule(biome)
    local editSnapshot = moduleRegistry.live.captureSnapshot()
    moduleRegistry.snapshot.setEntryEnabled(module, false, editSnapshot)
    liveModule.writeAndFlush("EnabledFlag", false)
    liveModule.writeAndFlush("Count", 3)
    moduleRegistry.snapshot.setEntryEnabled(biome, false, editSnapshot)
    biomeLiveModule.writeAndFlush("Mode", "Vanilla")

    lu.assertTrue(configHash.ApplyConfigHash(canonical))
    lu.assertTrue(liveModule.read("Enabled"))
    lu.assertTrue(liveModule.read("EnabledFlag"))
    lu.assertEquals(liveModule.read("Count"), 7)
    lu.assertTrue(biomeLiveModule.read("Enabled"))
    lu.assertEquals(biomeLiveModule.read("Mode"), "Chaos")
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
    local liveModule = moduleRegistry.live.getLiveModule(module)

    lu.assertStrContains(canonical, "BiomeControl.Filter=Apollo%7CZeus%3DPoseidon%25Chaos")
    lu.assertNotStrContains(canonical, "Apollo|Zeus")

    liveModule.writeAndFlush("Filter", "")
    lu.assertTrue(configHash.ApplyConfigHash(canonical))
    lu.assertEquals(liveModule.read("Filter"), "Apollo|Zeus=Poseidon%Chaos")
end

function TestConfigHashStorage:testTableStorageRoundTripsThroughCanonicalHash()
    local moduleRegistry = MockModuleRegistry.create({
        {
            id = "GodPool",
            name = "God Pool",
            enabled = true,
            storage = {
                {
                    type = "table",
                    alias = "Rows",
                    minRows = 0,
                    maxRows = 3,
                    defaultRows = 0,
                    row = {
                        { type = "bool", alias = "Flag", default = false },
                        { type = "string", alias = "Note", default = "", maxLen = 32 },
                    },
                },
            },
            values = {
                Rows = {
                    { Flag = true, Note = "a|b=%c" },
                },
            },
        },
    })
    local configHash = makeConfigHash(moduleRegistry)
    local canonical = configHash.GetConfigHash()
    local module = moduleRegistry.modulesById.GodPool
    local liveModule = moduleRegistry.live.getLiveModule(module)

    lu.assertStrContains(canonical, "GodPool.Rows=")
    lu.assertNotStrContains(canonical, "a|b")

    liveModule.writeAndFlush("Rows", {})
    lu.assertEquals(liveModule.read("Rows"), {})

    lu.assertTrue(configHash.ApplyConfigHash(canonical))
    lu.assertEquals(liveModule.read("Rows"), {
        { Flag = true, Note = "a|b=%c" },
    })
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

    moduleRegistry.live.getLiveModule(moduleRegistry.modulesById.GodPool).writeAndFlush("EnabledFlag", true)
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
    local liveModule = moduleRegistry.live.getLiveModule(module)

    local ok = configHash.ApplyConfigHash("_v=2|GodPool=1|GodPool.EnabledFlag=1")

    lu.assertFalse(ok)
    lu.assertFalse(liveModule.read("Enabled"))
    lu.assertFalse(liveModule.read("EnabledFlag"))
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
    local biomeLiveModule = moduleRegistry.live.getLiveModule(moduleRegistry.modulesById.BiomeControl)
    local godPoolLiveModule = moduleRegistry.live.getLiveModule(moduleRegistry.modulesById.GodPool)
    failApply = true

    local ok = configHash.ApplyConfigHash("_v=2|BiomeControl.Mode=Chaos|GodPool=1|GodPool.EnabledFlag=1")

    lu.assertFalse(ok)
    lu.assertEquals(biomeLiveModule.read("Mode"), "Vanilla")
    lu.assertFalse(godPoolLiveModule.read("EnabledFlag"))
    lu.assertTrue(godPoolLiveModule.read("Enabled"))
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
    local liveModule = moduleRegistry.live.getLiveModule(moduleRegistry.modulesById.GodPool)

    local ok = configHash.ApplyConfigHash("_v=999|GodPool=1|GodPool.EnabledFlag=1")

    lu.assertFalse(ok)
    lu.assertFalse(liveModule.read("Enabled"))
    lu.assertFalse(liveModule.read("EnabledFlag"))
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
    local liveModule = moduleRegistry.live.getLiveModule(moduleRegistry.modulesById.GodPool)

    local ok = configHash.ApplyConfigHash("_v=2|GodPool=enabled|GodPool.EnabledFlag=1")

    lu.assertFalse(ok)
    lu.assertFalse(liveModule.read("Enabled"))
    lu.assertFalse(liveModule.read("EnabledFlag"))
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
    local liveModule = moduleRegistry.live.getLiveModule(moduleRegistry.modulesById.GodPool)

    local ok = configHash.ApplyConfigHash("_v=2|GodPool.Count=not-a-number")

    lu.assertFalse(ok)
    lu.assertEquals(liveModule.read("Count"), 3)
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
    local liveModule = moduleRegistry.live.getLiveModule(moduleRegistry.modulesById.GodPool)

    local ok = configHash.ApplyConfigHash("_v=2|GodPool.Rows=not-a-table")

    lu.assertFalse(ok)
    lu.assertEquals(liveModule.read("Rows"), {})
    assertWarningContains("invalid storage root 'Rows' hash value")
    RestoreWarnings()
end

function TestConfigHashStorage:testApplyConfigHashIgnoresMalformedLooseSegmentsAndUnknownKeys()
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
    local configHash = makeConfigHash(moduleRegistry)
    local liveModule = moduleRegistry.live.getLiveModule(moduleRegistry.modulesById.GodPool)

    local ok = configHash.ApplyConfigHash(
        "_v=2|LooseSegment|GodPool=1|UnknownModule.Mode=Chaos|GodPool.MissingField=bad|GodPool.EnabledFlag=1"
    )

    lu.assertTrue(ok)
    lu.assertTrue(liveModule.read("Enabled"))
    lu.assertTrue(liveModule.read("EnabledFlag"))
    lu.assertEquals(liveModule.read("Count"), 3)
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

    moduleRegistry.live.getLiveModule(moduleRegistry.modulesById.GodPool).stage("FilterText", "Apollo")
    local canonical = makeConfigHash(moduleRegistry).GetConfigHash()

    lu.assertStrContains(canonical, "GodPool.EnabledFlag=1")
    lu.assertNotStrContains(canonical, "FilterText")
end

