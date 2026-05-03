# Changelog


## [Unreleased]

### Changed

- Framework pack state now persists on `AdamantModpackFramework_Internal`
- coordinated packs rebuild themselves when Framework reloads or when a coordinated module republishes its host
- HUD fingerprint wrapping now uses Lib's reload-stable hook registration instead of raw ModUtil wrapping
- hash serialization now escapes reserved token characters inside keys and values
- coordinator docs now show the supported bootstrap contract:
  - coordinator registration before `Framework.init(...)`
  - `Framework.registerGui(PACK_ID)` for GUI callback registration
  - optional `hideHashMarker`
- `Framework.init(...)` now uses positional required arguments plus an optional `opts` table instead of nested `params.def`

## [1.0.0] - 2026-04-20

Initial public release of the adamant Modpack Framework surface.

### Added

- coordinator discovery and module tab ordering
- shared main-window UI for coordinated modpacks
- Quick Setup, Profiles, and Dev coordinator tabs
- hash/profile export and import flow through the HUD layer
- coordinated module hosting through Lib module hosts
- master pack toggle handling with transactional runtime rollback
- shared theme, HUD, discovery, and UI factory surfaces

[unreleased]: https://github.com/h2-modpack/adamant-ModpackFramework/compare/1.0.0...HEAD
[1.0.0]: https://github.com/h2-modpack/adamant-ModpackFramework/compare/3f77c5cdfcb8803d9c5b8ef486021c3711ee074d...1.0.0
