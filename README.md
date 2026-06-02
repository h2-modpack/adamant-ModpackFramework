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
local logic = import("mods/logic.lua").bind(data)
local ui = import("mods/ui.lua").bind(data)

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
logic.registerHooks(module)

local ok = module.activate()
if not ok then
    return
end
```

If a module does not register runtime hooks, skip the hook declaration call.
Host activation publishes the created host into Lib's live-module registry. Framework discovers modules
through that registry rather than reading module globals directly.

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
- `host.getPackId() == PACK_ID`
- `host.getModuleId()`
- `host.getMeta().name`
- `host.getStorage()`
- `host.drawTab()`

Discovered modules render through:

- `host.drawTab()`
- optional `host.drawQuickContent()`

The module-authored callbacks registered with Lib receive
`drawTab(host, ui)` and `drawQuickContent(host, ui)`. Framework calls the live
`ModuleHost` wrapper methods; Lib supplies the callback host plus `ui.draw`,
`ui.data`, `ui.actions`, `ui.controls`, and `ui.shared`.

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
