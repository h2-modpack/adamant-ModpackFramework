# Quick Setup

This document covers the Framework Quick Setup surface.

Use [README.md](README.md) as the entrypoint for Framework docs.

## What Quick Setup Is

Quick Setup is the top-level framework panel for compact, high-frequency controls.

Typical content:
- a small coordinator-owned control surface
- a small per-module quick surface

## Render Order

Quick Setup renders in this order:

1. built-in profile quick selector
2. coordinator-owned content from `opts.renderQuickSetup(ctx)`
3. each discovered enabled module with quick content support

This happens inside [`src/ui.lua`](src/ui.lua).

## Coordinator Quick Content

Coordinators may inject their own quick content through:

```lua
local function renderQuickSetup(ctx)
    ...
end

Framework.init(PACK_ID, "My Modpack", config, #config.Profiles, defaultProfiles, {
    renderQuickSetup = renderQuickSetup,
})
```

`ctx` fields:
- `ui`
- `colors`
- `theme`
- `getModulesStatus(moduleIds)`
- `setModulesEnabled(moduleIds, enabled)`

Keep coordinator quick content coordinator-scoped. Module controls belong in that module's draw/host surface.

The built-in profile selector always renders before coordinator content. It lets users load saved
profiles from the main Quick Setup tab without opening the Profiles tab.

## Module Quick Content

Modules participate in Quick Setup through:

```lua
internal.DrawQuickContent = function(ui, session)
    ...
end

internal.host, internal.store = lib.createModule({
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
```

Framework behavior:
- only enabled modules render their quick content
- Framework snapshots live module hosts at the start of the UI operation
- module quick content is called through that snapshot host's `drawQuickContent(ui)`
- the draw callback receives the restricted author `session`
- if the module dirty-stages persisted state during quick content, Framework commits it after draw

## What Belongs In Quick Setup

Good fits:
- one or two high-frequency controls
- fast run-setup toggles
- controls you want without opening the full module tab

Better suited for full module tabs:
- the full module UI copied into Quick Setup
- large audit/configuration surfaces
- controls that only make sense in deep configuration

## Related Docs

- [README.md](README.md)
- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
