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
local config = chalk.auto("config.lua")
local loader = reload.auto_single()

local function init()
    Framework.init({
        packId = PACK_ID,
        windowTitle = "My Modpack",
        config = config,
        def = def,
        modutil = modutil,
    })
end

modutil.once_loaded.game(function()
    rom.gui.add_imgui(Framework.getRenderer(PACK_ID))
    rom.gui.add_to_menu_bar(Framework.getMenuBar(PACK_ID))
    loader.load(init, init)
end)
```

Use `loader.load(init, init)` unless you have a specific reload reason to split setup paths.

## `Framework.init(params)`

Required:
- `packId`
- `windowTitle`
- `config`
- `def`
- `modutil`

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

## Discovery Contract

Framework discovers modules by:

```lua
public.definition.modpack = PACK_ID
```

Each discovered coordinated module must expose:
- `definition.id`
- `definition.name`
- `definition.storage`
- public `store`
- public `DrawTab`

`DrawQuickContent` is optional.

Lifecycle shape is inferred from:
- `patchPlan`
- `apply/revert`
- or both

Framework skips modules that are missing:
- `definition.storage`
- public `store`
- public `DrawTab`
- required lifecycle for `affectsRunData = true`

## Window Model

Framework now renders:
- one sidebar tab per discovered module
- Quick Setup
- Profiles
- Dev

There is no category/subgroup grouping anymore.
There is no special-module split anymore.

Module tabs are simple:
- Framework renders the enable checkbox
- Framework calls `entry.mod.DrawTab(ui, entry.uiState)` when enabled
- if `uiState` is dirty after draw, Framework commits it through `lib.host.commitState(...)`

## Quick Setup

Quick Setup renders in this order:
1. coordinator-owned content from `def.renderQuickSetup(ctx)`
2. each discovered module with `DrawQuickContent`

There is no quick-node discovery from `definition.ui`.
There is no `selectQuickUi` path anymore.

See [QUICK_SETUP.md](QUICK_SETUP.md).

## Hash and Profiles

Hash/profile behavior is built on:
- module enable state
- validated persisted storage roots
- optional `definition.hashGroups`

Profile load:
- writes decoded persisted values
- reloads managed `uiState`
- reapplies enabled/runtime state
- rolls the operation back on failure

Compatibility-sensitive details are documented in [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md).

## Runtime Transactions

Framework-owned operations are transactional when practical:
- per-entry enable/disable
- coordinator master `ModEnabled` toggle
- managed `uiState` commit
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
