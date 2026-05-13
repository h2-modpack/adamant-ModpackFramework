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

Modules participate by exposing a Lib module host:

```lua
local host = lib.tryCreateModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = {
        modpack = PACK_ID,
        id = MODULE_ID,
        name = "Example Module",
        storage = internal.BuildStorage(),
    },
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
if not host then
    return
end

local ok = host.tryActivate()
if not ok then
    return
end
```

If a module does not register runtime hooks, `registerHooks` may be omitted.
Host activation publishes the created host into Lib's live-host registry. Framework discovers modules
through that registry rather than reading module globals directly.

## Docs

- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
  Bootstrap, discovery, and coordinator/module integration.
- [QUICK_SETUP.md](QUICK_SETUP.md)
  How pack-level Quick Setup content is assembled.
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
  Compatibility rules for module ids, storage aliases/defaults, and hash groups.
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for framework behavior and compatibility-sensitive changes.

## Module Discovery

The framework discovers modules that expose:

- a Lib-published live host
- `host.getIdentity().modpack == PACK_ID`
- `host.getIdentity().id`
- `host.getMeta().name`
- `host.getStorage()`
- `host.drawTab(imgui)`

Discovered modules render through:

- `host.drawTab(imgui)`
- optional `host.drawQuickContent(imgui)`

The module-authored callbacks registered with Lib receive
`drawTab(imgui, session, host)` and
`drawQuickContent(imgui, session, host)`. Framework calls the full host methods;
Lib supplies the author session and author host.

Sidebar behavior:

- one top-level tab per discovered module
- `opts.moduleOrder` may pin known module ids first
- `opts.moduleOrder` and discovered module order define the tab list

Coordinator bootstrap calls:

```lua
local ok = Framework.tryInit(PACK_ID, "My Modpack", config, #config.Profiles, defaultProfiles, {
    moduleOrder = {
        "ExampleModule",
    },
    renderQuickSetup = renderQuickSetup,
})
if not ok then
    return
end
```

`Framework.tryInit(...)` is the coordinator-safe entrypoint. It logs init failures
and skips publishing the pack. `Framework.init(...)` is the strict variant for tests
or callers that want errors to propagate.

## Validation

```bash
cd adamant-ModpackFramework
lua52.exe tests/all.lua
```
