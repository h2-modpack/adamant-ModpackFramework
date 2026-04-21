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
public.host = lib.createModuleHost({
    definition = public.definition,
    store = store,
    session = session,
    hookOwner = internal,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
```

If a module does not register runtime hooks, `hookOwner` and `registerHooks` may be omitted.

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

- `definition.modpack = PACK_ID`
- `definition.id`
- `definition.name`
- `definition.storage`
- `public.host`

Discovered modules render through:

- `host.drawTab(ui)`
- optional `host.drawQuickContent(ui)`

Sidebar behavior:

- one top-level tab per discovered module
- `moduleOrder` may pin known labels first
- `moduleOrder` and discovered module order define the tab list

## Validation

```bash
cd adamant-ModpackFramework
lua5.2 tests/all.lua
```
