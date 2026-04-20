# Quick Setup

This document covers the current Framework Quick Setup surface.

Use [README.md](README.md) as the entrypoint for Framework docs.

## What Quick Setup Is

Quick Setup is the top-level framework panel for high-frequency controls.

It is meant for:
- a small coordinator-owned control surface
- a small per-module quick surface

It is not meant to mirror full module tabs.

## Render Order

Quick Setup renders in this order:

1. coordinator-owned content from `def.renderQuickSetup(ctx)`
2. each discovered module that exposes `DrawQuickContent(ui, session)`

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

Keep coordinator quick content coordinator-scoped.
If a control belongs to a module, put it in that module's `DrawQuickContent`.

## Module Quick Content

Modules participate in Quick Setup through:

```lua
public.DrawQuickContent = function(ui, session)
    ...
end
```

Framework behavior:
- only enabled modules render their quick content
- module quick content receives the module managed `session`
- if the module dirty-stages persisted state during quick content, Framework commits it after draw

## What Was Removed

The old quick surface is gone:
- no quick-node discovery from `definition.ui`
- no `quick = true`
- no `quickId`
- no `selectQuickUi`
- no special-module-only quick path

Quick Setup is now immediate-mode only.

## What Belongs In Quick Setup

Good Quick Setup content:
- one or two high-frequency controls
- fast run-setup toggles
- controls you want without opening the full module tab

Bad Quick Setup content:
- the full module UI copied into Quick Setup
- large audit/configuration surfaces
- controls that only make sense in deep configuration

## Related Docs

- [README.md](README.md)
- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
