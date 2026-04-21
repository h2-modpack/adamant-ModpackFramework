# Coordinator Guide

This guide covers the supported `adamant-ModpackFramework` contract for coordinator mods.

## What the Coordinator Owns

The coordinator owns:
- `packId`
- Chalk config
- default profiles
- GUI registration
- any coordinator-specific Quick Setup content

Framework owns:
- discovery
- config hashing / profile load
- HUD fingerprint
- main pack window

## Bootstrap Pattern

Recommended coordinator shape:

```lua
local Framework = rom.mods["adamant-ModpackFramework"]
local config = chalk.auto("config.lua")
local loader = reload.auto_single()

local function init()
    Framework.init({
        packId = PACK_ID,
        windowTitle = "My Modpack",
        config = config,
        def = def,
    })
end

modutil.once_loaded.game(function()
    rom.gui.add_imgui(Framework.getRenderer(PACK_ID))
    rom.gui.add_always_draw_imgui(Framework.getAlwaysDrawRenderer(PACK_ID))
    rom.gui.add_to_menu_bar(Framework.getMenuBar(PACK_ID))
    loader.load(nil, init)
end)
```

## `Framework.init(params)`

Required:
- `packId`
- `windowTitle`
- `config`
- `def`

`config` must contain:
- `ModEnabled`
- `DebugMode`
- `Profiles`

`def` must contain:
- `NUM_PROFILES`
- `defaultProfiles`

Optional `def` fields:
- `moduleOrder`
  Ordered list of module labels to pin first in the sidebar. Unknown entries are warned and ignored.
- `renderQuickSetup(ctx)`
  Coordinator-owned Quick Setup content. See [QUICK_SETUP.md](QUICK_SETUP.md).

Optional top-level params:
- `hideHashMarker`
  Suppresses the HUD hash marker while keeping the rest of the coordinator surface active.

## Discovery Contract

Framework discovers modules by:

```lua
public.definition.modpack = PACK_ID
```

Each discovered coordinated module must expose:
- `definition.id`
- `definition.name`
- `definition.storage`
- public `host`

`host.drawQuickContent(...)` is optional.

Lifecycle shape is inferred from:
- `patchPlan`
- `apply/revert`
- or both

Framework skips modules that are missing:
- `definition.storage`
- public `host`
- host draw support
- required lifecycle for `affectsRunData = true`

## Window Model

Framework renders:
- one sidebar tab per discovered module
- Quick Setup
- Profiles
- Dev

The sidebar is module-based: one tab per discovered module, in discovery order.

Module tabs are simple:
- Framework renders the enable checkbox
- Framework calls `entry.host.drawTab(ui)` when enabled
- if staged state is dirty after draw, Framework commits it through `entry.host.commitIfDirty()`

## Quick Setup

Quick Setup renders in this order:
1. coordinator-owned content from `def.renderQuickSetup(ctx)`
2. each discovered module whose `host.hasQuickContent()` is true

Quick content is provided by coordinator code or module hosts.

See [QUICK_SETUP.md](QUICK_SETUP.md).

## Reload Behavior

Coordinator bootstrap normally reruns `Framework.init(...)` from the reload body.

Framework keeps the pack session current by rebuilding from the stored init params when:
- the coordinator reloads
- a coordinated module publishes a refreshed host for the same `packId`

## Hash and Profiles

Hash/profile behavior is built on:
- module enable state
- validated persisted storage roots
- optional `definition.hashGroups`

Profile load:
- stages decoded persisted values through each module host/session plumbing
- flushes staged managed values to config
- reapplies enabled/runtime state
- rolls the operation back on failure

Compatibility-sensitive details are documented in [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md).

## Runtime Transactions

Framework-owned operations are transactional when practical:
- per-entry enable/disable
- coordinator master `ModEnabled` toggle
- managed `session` commit
- profile/hash load

The intended outcome is:
- commit the new state
- or restore the previous persisted/runtime state and warn

## Debug and Warnings

Framework debug:
- `config.DebugMode`

Lib debug:
- `lib.config.DebugMode`

Framework warnings use:
- `lib.logging.warn(...)`
- `lib.logging.warnIf(...)`

## Related Docs

- [README.md](README.md)
- [QUICK_SETUP.md](QUICK_SETUP.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
