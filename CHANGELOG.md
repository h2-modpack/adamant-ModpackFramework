# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

Initial public release of the adamant Modpack Framework surface.

### Added

- coordinator discovery and module tab ordering
- shared main-window UI for coordinated modpacks
- Quick Setup, Profiles, and Dev coordinator tabs
- hash/profile export and import flow through the HUD layer
- coordinated module hosting through module `public.host`
- master pack toggle handling with transactional runtime rollback
- shared theme, HUD, discovery, and UI factory surfaces

### Notes

- this release documents the current lean coordinator/framework contract
- framework hosting assumes modules expose `public.definition` and `public.host`

[Unreleased]: https://github.com/h2-modpack/adamant-ModpackFramework/compare/HEAD
