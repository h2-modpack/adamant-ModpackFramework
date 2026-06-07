# adamant-ModpackFramework

Reusable coordinator framework for Hades II modpacks built on
`adamant-ModpackLib`.

ModpackFramework gives a pack one shared in-game control surface. It discovers
modules that belong to the pack, renders their tabs, coordinates quick setup,
and handles profile/hash workflows through a single coordinator UI.

It provides:

- module discovery for one `packId`
- a shared coordinator window
- module tab ordering and rendering
- Quick Setup aggregation
- profile import/export and config hash loading
- HUD fingerprint display for the active settings
- pack-level enable/disable behavior with rollback on failure

Modules participate by exposing a Lib managed module:

```lua
local data = import("mods/data.lua")
local logic = import("mods/logic.lua", nil, {
    data = data,
})
local ui = import("mods/ui.lua", nil, {
    data = data,
})

local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
})
if not module then
    return
end

module.data.define(data.buildStorage())
module.ui.tab(ui.drawTab)
module.ui.quickContent(ui.drawQuickContent)
logic.register(module)

local ok = module.activate()
if not ok then
    return
end
```

If a module does not register runtime hooks, skip the hook declaration call.
Module activation publishes the created live module into Lib's live-module
registry. Framework discovers modules through that registry rather than reading
module globals directly.

## Getting Started

For the full new-pack walkthrough, start with the
[`ModpackBootstrap` Getting Started guide](https://github.com/h2-modpack/ModpackBootstrap/blob/main/docs/GETTING_STARTED.md).
This repo documents the Framework coordinator contract once a pack workspace
exists.

Use Framework through the generated pack workflow:

- Create a new pack with
  [`ModpackBootstrap`](https://github.com/h2-modpack/ModpackBootstrap). It
  generates the shell repo, coordinator package, shared Lib/Framework
  submodules, and `ModpackTools/`.
- Add modules to an existing pack with
  `python ModpackTools/new_module/create.py --package-id My_Module --title "My Module"`.
- Use [`ModpackModuleTemplate`](https://github.com/h2-modpack/ModpackModuleTemplate)
  as the standalone module repo shape.
- Validate a shell workspace with `python ModpackTools/test_all.py`.

Framework itself owns runtime coordinator orchestration. It is not the pack
bootstrapper or the module template source.

## Docs

- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
  Bootstrap, discovery, and coordinator/module wiring.
- [QUICK_SETUP.md](QUICK_SETUP.md)
  How pack-level Quick Setup content is assembled.
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
  Compatibility rules for module ids, storage aliases/defaults, and value codecs.
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for framework behavior and compatibility-sensitive changes.

## Module Discovery

The framework discovers modules that expose:

- a Lib-published live module
- `liveModule.getPackId() == PACK_ID`
- `liveModule.getModuleId()`
- `liveModule.getMeta().name`
- `liveModule.getStorage()`
- `liveModule.drawTab()`

Discovered modules render through:

- `liveModule.drawTab()`
- optional `liveModule.drawQuickContent()`

The module-authored callbacks registered with Lib receive
`drawTab(host, ui)` and `drawQuickContent(host, ui)`. Framework calls the live
module wrapper methods; Lib supplies the callback host plus `ui.draw`,
`ui.data`, `ui.status`, `ui.actions`, `ui.controls`, and `ui.shared`.

Sidebar behavior:

- one top-level tab per discovered module
- `opts.moduleOrder` may pin known module ids first
- `opts.moduleOrder` and discovered module order define the tab list

Coordinator bootstrap calls:

```lua
Framework.registerCoordinator(PACK_ID, config)

local ok = Framework.createPack(PACK_ID, "My Modpack", config, #config.Profiles, defaultProfiles, {
    moduleOrder = {
        "ExampleModule",
    },
    drawPackQuickContent = drawPackQuickContent,
})
if not ok then
    return
end
```

`Framework.createPack(...)` is the coordinator-safe entrypoint. It logs creation
failures and skips publishing the pack.

## Validation

```bash
cd adamant-ModpackFramework
lua52.exe tests/all.lua
```
