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
local definition = lib.prepareDefinition(internal, dataDefaults, {
    modpack = PACK_ID,
    ...
})

lib.createModuleHost({
    definition = definition,
    store = store,
    session = session,
    hookOwner = internal,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
```

If a module does not register runtime hooks, `hookOwner` and `registerHooks` may be omitted.
Lib publishes the created host into its live-host registry. Framework discovers modules
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
- `host.drawTab(ui)`

Discovered modules render through:

- `host.drawTab(ui)`
- optional `host.drawQuickContent(ui)`

Sidebar behavior:

- one top-level tab per discovered module
- `opts.moduleOrder` may pin known module ids first
- `opts.moduleOrder` and discovered module order define the tab list

Coordinator bootstrap calls:

```lua
Framework.init(PACK_ID, "My Modpack", config, #config.Profiles, defaultProfiles, {
    moduleOrder = {
        "ExampleModule",
    },
    renderQuickSetup = renderQuickSetup,
})
```

## Validation

```bash
cd adamant-ModpackFramework
lua52.exe tests/all.lua
```
