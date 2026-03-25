# Contributing to adamant-Modpack_Framework

Reusable orchestration library for Hades 2 modpacks. Provides discovery, config hashing, HUD fingerprint, and the shared UI window. Coordinators call `Framework.init(params)` and get everything for free.

## Architecture

```
src/
  main.lua        -- Framework table, ENVY wiring, Framework.init, imports sub-files
  discovery.lua   -- createDiscovery(packId, config, lib)
  hash.lua        -- createHash(discovery, config, lib, packId)
  ui_theme.lua    -- createTheme()
  hud.lua         -- createHud(packId, packIndex, hash, theme, config, modutil)
  ui.lua          -- createUI(discovery, hash, hud, theme, def, config, lib, packId, windowTitle)
```

Each sub-file exposes one factory function on the `Framework` table. `Framework.init` wires them together, handles GUI registration, and returns the pack table. Factory params replace the old `Core.*` global namespace — state is closed over, not shared.

Coordinators own: their Chalk config, `def` (NUM_PROFILES, defaultProfiles), and their `packId`. Framework owns everything else.

## Key systems

### Discovery (discovery.lua — `createDiscovery`)

Auto-discovers all installed modules that opt in via `definition.modpack = packId`. No registry required — modules are picked up automatically on load.

- Regular modules: `def.special` is nil/false
- Special modules: `def.special = true`
- All metadata (id, name, category, group, tooltip, default) lives in each module's `public.definition`
- Modules are sorted alphabetically by display name; categories and groups are also sorted alphabetically

A new category tab is created automatically the first time a module with an unseen `def.category` is discovered. No Framework changes needed to add a new module or category.

### Config hash (hash.lua — `createHash`)

Pure encoding logic with no engine dependencies — fully testable in standalone Lua. Uses a **key-value canonical string** format:

```
_v=1|ModId=1|ModId.configKey=value|adamant-SpecialName.configKey=value
```

- Only non-default values are encoded — adding new fields with defaults is non-breaking
- Keys are sorted alphabetically for stable output
- Value encoding is delegated to `lib.FieldTypes[field.type].toHash/fromHash`
- `_v` version token must be present or the hash is rejected

`GetConfigHash(source)` returns `canonical, fingerprint` — the canonical string is used for import/export, the 12-char base62 fingerprint is shown on the HUD. `ApplyConfigHash(hash)` decodes and applies a canonical string; unknown keys are ignored and missing keys reset to defaults.

### HUD (hud.lua — `createHud`)

Manages the fingerprint overlay. Each pack registers its own component named `"ModpackMark_<packId>"`, positioned at `Y = 250 + (packIndex - 1) * 24` so multiple packs stack vertically without overlap. Returns `{ setModMarker, updateHash, getConfigHash, applyConfigHash }`.

### UI (ui.lua — `createUI`)

Uses a **staging table** — a plain Lua cache mirroring Chalk configs for fast per-frame reads. Chalk is only written when the user makes a change.

Key handlers:

| Function | Purpose |
|---|---|
| `ToggleModule(module, val)` | Enable/disable a boolean module |
| `ChangeOption(module, key, val)` | Change an inline option (triggers revert + apply if dataMutation) |
| `ToggleSpecial(special, val)` | Enable/disable a special module |
| `SetModuleState(module, state)` | Game-side only apply/revert (no Chalk, no staging) |
| `LoadProfile(hash)` | Apply a hash string to all modules and re-snapshot staging |
| `SetBugFixes(val)` | Bulk toggle all modules in the `"Bug Fixes"` category |

Returns `{ renderWindow, addMenuBar }`. Registration with `rom.gui` is handled by `Framework.init`, not by `createUI`.

### Dev tab (ui.lua — `DrawDev`)

Two independent debug controls:

| Control | What it gates | Config key |
|---|---|---|
| Framework Debug | `lib.warn(packId, enabled, msg)` calls — schema errors, discovery warnings | `config.DebugMode` (coordinator's config) |
| Lib Debug | lib-internal diagnostics | `lib.config.DebugMode` (shared across all packs) |
| Per-module Debug | `lib.log(name, enabled, msg)` in each module's own code | Each module's `config.DebugMode` |

Framework Debug and Lib Debug are written directly (no staging) — they have no external writers so staging would add complexity with no correctness benefit.

### Theme (ui_theme.lua — `createTheme`)

Declarative colors and layout constants. No parameters — returns the same palette every time. Future: could accept an `overrides` table for pack-specific colors.

## Hot reload

`Framework.init` is safe to call on every reload. Sub-system instances are recreated fresh each call; GUI callbacks are registered only once per `packId` (guarded by `_registered[packId]`). The callbacks use late-binding via `_packs[packId]` so they automatically pick up the new instances.

## Tests

```
cd adamant-modpack-Framework
lua5.1 tests/all.lua
```

Tests use `Framework.createHash(mockDiscovery, ...)` directly — no global patching, no engine required. See `tests/TestUtils.lua` for the mock scaffold.

## How-tos

### Adding a new category

Set `def.category` to a new string in a module's `public.definition`. The tab appears automatically — no Framework change needed.

## Guidelines

- **Never rename `def.id` or `field.configKey` after release** — these are hash keys; renaming silently resets that field to default for anyone with an existing profile
- **`"Bug Fixes"` is a reserved category string** — modules using this exact string get a bulk enable/disable toggle in the Quick Setup tab. Spelling variations create a separate tab without the bulk toggle
- All module apply/revert calls go through `pcall` — use `lib.warn` for framework errors, never crash
- UI reads from staging, not Chalk — always keep staging in sync
- Theme is data-driven — don't hardcode counts or layout numbers
- **`def.options` configKeys must be flat strings** — table-path keys (e.g. `{"Parent", "Child"}`) are only valid in `def.stateSchema` (special modules). Discovery warns and skips any option with a table configKey. If your config needs nested structure, make it a special module
