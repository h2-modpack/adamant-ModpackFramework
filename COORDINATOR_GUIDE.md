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
local defaultProfiles = {}

local function drawPackQuickContent(ctx)
    -- Optional coordinator quick controls.
end

local function init()
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
end

local function registerGui()
    local Framework = rom.mods["adamant-ModpackFramework"]

    local callbacks = Framework.createGuiCallbacks(PACK_ID)
    rom.gui.add_imgui(callbacks.render)
    rom.gui.add_always_draw_imgui(callbacks.alwaysDraw)
    rom.gui.add_to_menu_bar(callbacks.menuBar)
end

modutil.once_loaded.game(function()
    loader.load(registerGui, init)
end)
```

## `Framework.createPack(packId, windowTitle, config, numProfiles, defaultProfiles, opts?)`

Coordinator mods should call `Framework.createPack(...)`. It logs creation
failures and skips publishing the pack when construction fails.

## Init Arguments

Required:
- `packId`
- `windowTitle`
- `config`
- `numProfiles`
- `defaultProfiles`

`config` must contain:
- `ModEnabled`
- `DebugMode`
- `Profiles`

Optional `opts` fields:
- `moduleOrder`
  Ordered list of module ids to pin first in the sidebar. Unknown entries are warned and ignored.
- `drawPackQuickContent(ctx)`
  Coordinator-owned Quick Setup content. See [QUICK_SETUP.md](QUICK_SETUP.md).
- `hideHashMarker`
  Suppresses the HUD hash marker while keeping the rest of the coordinator surface active.

## Discovery Contract

Framework discovers modules through Lib's live-module registry:

```lua
-- Conceptual filter over Lib-published live modules.
host.getPackId() == PACK_ID
```

Direct live-host lookup is keyed by `pluginGuid`. Framework discovery filters
the registry by prepared host identity instead of looking modules up by module
id.

Each discovered coordinated module must expose:
- `host.getModuleId()`
- `host.getMeta().name`
- `host.getStorage()`
- `host.drawTab()`

`host.drawQuickContent()` is optional.

These are full Lib host methods. The module-authored callbacks registered with
Lib receive the author surfaces as `drawTab(draw, state, actions)` and
`drawQuickContent(draw, state, actions)`. The draw object contains `imgui`,
`widgets`, `nav`, and draw-safe logging; the other arguments provide staged data
and staged actions.

Lib owns module definition preparation and lifecycle validation before the host
is published. Framework trusts Lib-created hosts. Runtime state transitions are
routed through the same host lifecycle methods authors use:
- `host.setEnabled(enabled)`
- `host.commitIfDirty()`

Pack disable snapshots each discovered module's current `Enabled` value, then
disables modules through Lib's host pack-suspension lifecycle. Pack enable
restores that snapshot through the matching host lifecycle path and clears it
after a successful restore. The snapshot is persisted in Lib-managed internal
storage, so a disabled pack can survive a full game restart and still restore
the prior module mix when re-enabled.

Framework skips modules that are missing:
- live module registry entry
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
- Framework snapshots live module hosts at the start of the UI operation
- Framework calls the selected module host's `drawTab()` when enabled
- if staged state is dirty after draw, Framework commits it through that snapshot host's `commitIfDirty()`

## Quick Setup

Quick Setup renders in this order:
1. built-in profile quick selector
2. coordinator-owned content from `opts.drawPackQuickContent(ctx)`
3. each discovered enabled module with quick content support

Quick content is provided by coordinator code or module hosts.

See [QUICK_SETUP.md](QUICK_SETUP.md).

## Reload Behavior

Coordinator bootstrap normally reruns `Framework.createPack(...)` from the reload body.

The coordinator owns init arguments and re-calls `Framework.createPack(...)` when the coordinator/framework layer reloads.
Framework replaces pack state for the same `packId` while preserving that pack's stable HUD/index slot.

Coordinated module behavior reloads do not rebuild the pack. Instead:
- discovery metadata remains static for the process
- UI and hash paths snapshot the module's live host at the start of each operation

Coordinated module structural reloads can request a pack rebuild through the
callback registered with `Framework.registerCoordinator(...)`.
If no callback is registered or the request is rejected, the module warns that a full reload is required.

## Hash and Profiles

Hash/profile behavior is built on:
- module enable state
- validated persisted storage roots
- optional `definition.hashGroupPlan`

Profile load:
- stages decoded persisted values through each module host/state plumbing
- flushes staged managed values to config
- reapplies enabled/runtime state
- rolls the operation back on failure

Compatibility-sensitive details are documented in [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md).

## Runtime Transactions

Framework-owned operations are transactional when practical:
- per-entry enable/disable
- coordinator master `ModEnabled` toggle
- managed staged-state commit
- profile/hash load

The intended outcome is:
- commit the new state
- or restore the previous persisted/runtime state and warn

## Debug and Warnings

Framework debug:
- `config.DebugMode`

Lib debug:
- `lib.createFrameworkRuntime(...).diagnostics`

Framework warnings use Framework-owned logging helpers.

## Related Docs

- [README.md](README.md)
- [QUICK_SETUP.md](QUICK_SETUP.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
