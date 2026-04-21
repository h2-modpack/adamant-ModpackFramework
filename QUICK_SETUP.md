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

1. coordinator-owned content from `def.renderQuickSetup(ctx)`
2. each discovered module whose `host.hasQuickContent()` is true

This happens inside [`src/ui.lua`](src/ui.lua).

## Coordinator Quick Content

Coordinators may inject their own quick content through:

```lua
def.renderQuickSetup = function(ctx)
    ...
end
```

Current `ctx` fields:
- `ui`
- `colors`
- `theme`
- `drawColoredText`

Keep coordinator quick content coordinator-scoped. Module controls belong in that module's draw/host surface.

## Module Quick Content

Modules participate in Quick Setup through:

```lua
internal.DrawQuickContent = function(ui, session)
    ...
end

public.host = lib.createModuleHost({
    definition = public.definition,
    store = store,
    session = session,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
```

Framework behavior:
- only enabled modules render their quick content
- module quick content is called through `entry.host.drawQuickContent(ui)`
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
