# adamant-ModpackFramework

Reusable coordinator framework for adamant modpacks.

Framework now owns:
- module discovery for one `packId`
- config hashing and profile load
- HUD fingerprint rendering
- the shared coordinator window

Framework does not define module UI shapes anymore.
Under the current contract, each discovered coordinated module renders itself through:
- `DrawTab(ui, session)`
- optional `DrawQuickContent(ui, session)`

## Docs

- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
  Bootstrap, discovery, and the live coordinator/module contract.
- [QUICK_SETUP.md](QUICK_SETUP.md)
  Current Quick Setup model: coordinator quick content plus module `DrawQuickContent`.
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
  Compatibility rules for module ids, storage aliases/defaults, and hash groups.
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for framework behavior and compatibility-sensitive changes.

## Current Framework Contract

Discovery includes modules that expose:
- `definition.modpack = PACK_ID`
- `definition.id`
- `definition.name`
- `definition.storage`
- public `store`
- public `session`
- public `DrawTab`

`DrawQuickContent` is optional.

Framework sidebar behavior is now:
- one top-level tab per discovered module
- `moduleOrder` may pin known labels first
- no category/subgroup grouping
- no special-module split

## Validation

```bash
cd adamant-ModpackFramework
lua5.2 tests/all.lua
```
