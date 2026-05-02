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
local lib = rom.mods["adamant-ModpackLib"]
local config = chalk.auto("config.lua")
local loader = reload.auto_single()

local function init()
    lib.lifecycle.registerCoordinator(PACK_ID, config)
    Framework.init({
        packId = PACK_ID,
        windowTitle = "My Modpack",
        config = config,
        def = def,
    })
end

local function registerGui()
    local Framework = rom.mods["adamant-ModpackFramework"]

    rom.gui.add_imgui(Framework.getRenderer(PACK_ID))
    rom.gui.add_always_draw_imgui(Framework.getAlwaysDrawRenderer(PACK_ID))
    rom.gui.add_to_menu_bar(Framework.getMenuBar(PACK_ID))
end

modutil.once_loaded.game(function()
    loader.load(registerGui, init)
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
  Ordered list of module ids to pin first in the sidebar. Unknown entries are warned and ignored.
- `renderQuickSetup(ctx)`
  Coordinator-owned Quick Setup content. See [QUICK_SETUP.md](QUICK_SETUP.md).

Optional top-level params:
- `hideHashMarker`
  Suppresses the HUD hash marker while keeping the rest of the coordinator surface active.

## Discovery Contract

Framework discovers modules through Lib's live-host registry:

```lua
local host = lib.getLiveModuleHost(modName)
host.getIdentity().modpack == PACK_ID
```

Each discovered coordinated module must expose:
- `host.getIdentity().id`
- `host.getMeta().name`
- `host.getStorage()`
- `host.drawTab(ui)`

`host.drawQuickContent(...)` is optional.

Lib owns module definition preparation and lifecycle validation before the host is published.
Framework trusts Lib-created hosts and calls the host lifecycle surface:
- `host.applyOnLoad()`
- `host.applyMutation()`
- `host.revertMutation()`
- `host.commitIfDirty()`

Framework skips modules that are missing:
- live host registry entry
- host identity `id` or meta `name`
- host storage contract

## Window Model

Framework renders:
- one sidebar tab per discovered module
- Quick Setup
- Profiles
- Dev

The sidebar is module-based: one tab per discovered module, in discovery order.

Module tabs are simple:
- Framework renders the enable checkbox
- Framework snapshots the current module hosts at the start of the UI operation
- Framework calls the selected module host's `drawTab(ui)` when enabled
- if staged state is dirty after draw, Framework commits it through that snapshot host's `commitIfDirty()`

## Quick Setup

Quick Setup renders in this order:
1. built-in profile quick selector
2. coordinator-owned content from `def.renderQuickSetup(ctx)`
3. each discovered enabled module with quick content support

Quick content is provided by coordinator code or module hosts.

See [QUICK_SETUP.md](QUICK_SETUP.md).

## Reload Behavior

Coordinator bootstrap normally reruns `Framework.init(...)` from the reload body.

The coordinator owns init parameters and re-calls `Framework.init(params)` when the coordinator/framework layer reloads.
Framework replaces the current pack state for the same `packId` while preserving that pack's stable HUD/index slot.

Coordinated module behavior reloads do not rebuild the pack. Instead:
- discovery metadata remains static for the process
- UI and hash paths snapshot the module's current live host at the start of each operation

Coordinated module structural reloads can request a pack rebuild through Lib's coordinator rebuild callback.
If no callback is registered or the request is rejected, the module warns that a full reload is required.

## Hash and Profiles

Hash/profile behavior is built on:
- module enable state
- validated persisted storage roots
- optional `definition.hashGroupPlan`

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
