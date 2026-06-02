std = "lua52"
max_line_length = 200

globals = {
    "rom",
    "public",
    "Framework",
    "FrameworkPackRegistry",
    "lib",
    "_PLUGIN",
    "AdamantModpackFramework_Internal"
}

read_globals = {
    "import",
}

files["tests/*.lua"] = {
    globals = {
        "CaptureWarnings",
        "CreateFrameworkHarness",
        "CreateModuleState",
        "FrameworkTestApi",
        "GetRuntimeLiveModules",
        "ImGuiCol",
        "ImGuiComboFlags",
        "ImGuiTreeNodeFlags",
        "LibModuleHost",
        "LibModuleState",
        "LibOverlays",
        "LibStorage",
        "LibTestImportOverrides",
        "LibTestImports",
        "MockModuleRegistry",
        "RestoreWarnings",
        "SetRuntimeLiveModule",
        "TestAuditProfiles",
        "TestConfigHashBase62",
        "TestConfigHashStorage",
        "TestLibHost",
        "TestLibValidation",
        "TestMain",
        "TestModuleRegistry",
        "Warnings",
        "_originalPrint",
        "config",
        "import",
        "print",
    },
    read_globals = {
        "AdamantModpackLib_Runtime",
    },
    ignore = {
        "212/self",
    },
}
