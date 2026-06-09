# Changelog

## [Unreleased]

## [2.0.0] - 2026-06-09

### Changed

- Hash/profile storage filtering now follows Lib's explicit `hash` storage axis instead of the old transient/runtime flags.
- Updated hash/profile ABI docs for direct alias-owned managed storage keys.
- Framework now treats Lib-injected `Enabled` storage as the module-level hash key while excluding `DebugMode` and non-hash storage from hash/profile output.
- Coordinators now register pack metadata through `Framework.registerCoordinator(...)` instead of calling Lib coordinator APIs directly.
- `Framework.createPack(...)` is now the only public pack construction entrypoint; the prior split strict/safe construction surfaces were retired.
- GUI registration now uses stable callbacks from `Framework.createGuiCallbacks(packId)` so coordinator code owns the ROM GUI callsite.
- Framework implementation files now live under `src/core/...`; root `src/main.lua` only assembles the public surface.
- Pack enable/disable now drives coordinated modules through Lib live-module lifecycle methods. Disabling a pack snapshots each module's prior enabled state and enabling the pack restores that snapshot, so mutations and shared publications use the same path as module-level toggles.
- Framework now reconciles discovered modules when a pack starts disabled, preserving the pack-restore snapshot while ensuring module runtime effects stay suspended.
- Removed `definition.hashGroupPlan` and grouped hash/profile encoding. Hashes now use semantic module/storage keys only, with future shortening expected to happen through whole-string compression.
- Bumped the config hash ABI to version 2 and reject older versions instead of attempting partial migration from grouped hashes.

## [1.1.0] - 2026-05-05

### Added

- Added a LuaLS public definition file at `src/def.lua` for the Framework module export, pack creation contract, theme data, Quick Setup context, and pack runtime.
- Added `Framework.createGuiCallbacks(packId)` as the supported GUI callback entrypoint for coordinator mods.
- Added `definition.hashGroupPlan` support through a dedicated hash-group builder for compact grouped hash/profile encoding.
- Added saved-profile auditing during framework initialization and from the Profiles tab.
- Added player-facing `THUNDERSTORE_README.md` packaging support.

### Changed

- `Framework.createPack(...)` now uses positional required arguments plus an optional `opts` table instead of nested `params.def`.
- Framework pack state now persists on `FrameworkPackRegistry`, so repeated coordinator/framework reloads replace pack state without duplicating pack slots.
- Framework discovery now resolves modules through Lib's live-module registry instead of reading module public globals directly.
- UI and hash operations now snapshot current live modules at operation start, so ordinary module behavior reloads can update through Lib-published live modules without rediscovery.
- Coordinated packs can rebuild when a coordinated module republishes a structurally changed live module and Lib requests a coordinator rebuild.
- The main UI was split into focused runtime, profile, Quick Setup, module-tab, dev, and theme files.
- Profile/hash updates now flush on menu close instead of periodic HUD refreshes while the main UI is open.
- HUD fingerprint wrapping now uses Lib's reload-stable hook registration instead of raw ModUtil wrapping.
- HUD hash markers now use Lib's managed overlay stack instead of direct HUD component mutation.
- Framework UI now uses Lib's global UI overlay suppression gate, making configuration UI and gameplay overlays mutually exclusive on screen.
- Hash/profile serialization now escapes reserved token characters inside keys and values.
- Runtime-only storage aliases are rejected from hash groups so transient runtime markers cannot enter hash/profile output.
- Hash computation now rejects hashes from newer unsupported hash ABI versions instead of warning and continuing.
- `Hash.GetConfigHash(...)` now only supports the live pack state path; the unfinished profile-source argument was removed.
- The HUD hash marker can be suppressed with `opts.hideHashMarker` while keeping the coordinator UI active.
- Packaged README content moved out of `src/README.md`; package metadata now points at `THUNDERSTORE_README.md`.

### Fixed

- Fixed coordinated module startup lifecycle batching so `SetupRunData()` runs once after startup sync when needed.
- Fixed profile/hash apply failures to restore prior config/runtime state where possible.
- Fixed master pack and module batch toggles to roll back touched runtime state on failure.
- Fixed HUD refresh callback stacking across Framework reloads.
- Fixed stale UI state seams by routing Profiles, Quick Setup, and module tabs through explicit runtime/state flows.

### Documentation

- Rewrote coordinator docs around the supported bootstrap contract:
  - coordinator registration before `Framework.createPack(...)`
  - `Framework.createGuiCallbacks(PACK_ID)` for GUI callback registration
  - positional `Framework.createPack(...)` arguments plus optional `opts`
  - Lib live-module discovery and snapshot runtime behavior
- Expanded `HASH_PROFILE_ABI.md` with hash/profile invariants, token escaping, decode behavior, and shipped-module compatibility rules.
- Updated Quick Setup docs for coordinator-owned `opts.drawPackQuickContent(ctx)` and module quick content.
- Updated README and contributor docs to focus on the live-module coordinator/module contract.

### Tests

- Expanded Framework test coverage for discovery, hashing/profile rollback, startup lifecycle sync, repeated init, GUI registration, Quick Setup live-module behavior, and UI stack cleanup.
- Updated the test harness to isolate Framework factories and exercise Lib live-module discovery paths.

## [1.0.0] - 2026-04-20

Initial public release of the adamant Modpack Framework surface.

### Added

- coordinator discovery and module tab ordering
- shared main-window UI for coordinated modpacks
- Quick Setup, Profiles, and Dev coordinator tabs
- hash/profile export and import flow through the HUD layer
- coordinated module discovery through Lib live modules
- master pack toggle handling with transactional runtime rollback
- shared theme, HUD, discovery, and UI factory surfaces

[unreleased]: https://github.com/h2-modpack/adamant-ModpackFramework/compare/2.0.0...HEAD
[2.0.0]: https://github.com/h2-modpack/adamant-ModpackFramework/compare/1.1.0...2.0.0
[1.1.0]: https://github.com/h2-modpack/adamant-ModpackFramework/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/h2-modpack/adamant-ModpackFramework/compare/3f77c5cdfcb8803d9c5b8ef486021c3711ee074d...1.0.0
