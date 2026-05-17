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
local defaultProfiles = {}

local function renderQuickSetup(ctx)
    -- Optional coordinator quick controls.
end

local function init()
    lib.coordinator.register(PACK_ID, config)
    local ok = Framework.tryInit(PACK_ID, "My Modpack", config, #config.Profiles, defaultProfiles, {
        moduleOrder = {
            "ExampleModule",
        },
        renderQuickSetup = renderQuickSetup,
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

## `Framework.tryInit(packId, windowTitle, config, numProfiles, defaultProfiles, opts?)`

Coordinator mods should call `Framework.tryInit(...)`. It logs initialization
failures and skips publishing the pack when construction fails.

`Framework.init(...)` is the strict variant. It has the same arguments, returns
the pack runtime on success, and raises on failure.

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
- `renderQuickSetup(ctx)`
  Coordinator-owned Quick Setup content. See [QUICK_SETUP.md](QUICK_SETUP.md).
- `hideHashMarker`
  Suppresses the HUD hash marker while keeping the rest of the coordinator surface active.

## Discovery Contract

Framework discovers modules through Lib's live-host registry:

```lua
-- Conceptual filter over Lib-published live hosts.
host.getIdentity().modpack == PACK_ID
```

Direct live-host lookup is keyed by `pluginGuid`. Framework discovery filters
the registry by prepared host identity instead of looking modules up by module
id.

Each discovered coordinated module must expose:
- `host.getIdentity().id`
- `host.getMeta().name`
- `host.getStorage()`
- `host.drawTab(imgui)`

`host.drawQuickContent(...)` is optional.

These are full Lib host methods. The module-authored callbacks registered with
Lib receive the author surfaces as `drawTab(imgui, session, host)` and
`drawQuickContent(imgui, session, host)`.

Lib owns module definition preparation and lifecycle validation before the host is published.
Framework trusts Lib-created hosts. Activation-time mutation sync is owned by
Lib; Framework only calls runtime transition/session methods:
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
- Framework snapshots live module hosts at the start of the UI operation
- Framework calls the selected module host's `drawTab(imgui)` when enabled
- if staged state is dirty after draw, Framework commits it through that snapshot host's `commitIfDirty()`

## Quick Setup

Quick Setup renders in this order:
1. built-in profile quick selector
2. coordinator-owned content from `opts.renderQuickSetup(ctx)`
3. each discovered enabled module with quick content support

Quick content is provided by coordinator code or module hosts.

See [QUICK_SETUP.md](QUICK_SETUP.md).

## Reload Behavior

Coordinator bootstrap normally reruns `Framework.tryInit(...)` from the reload body.

The coordinator owns init arguments and re-calls `Framework.tryInit(...)` when the coordinator/framework layer reloads.
Framework replaces pack state for the same `packId` while preserving that pack's stable HUD/index slot.

Coordinated module behavior reloads do not rebuild the pack. Instead:
- discovery metadata remains static for the process
- UI and hash paths snapshot the module's live host at the start of each operation

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

Framework warnings use Framework-owned logging helpers.

## Related Docs

- [README.md](README.md)
- [QUICK_SETUP.md](QUICK_SETUP.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
