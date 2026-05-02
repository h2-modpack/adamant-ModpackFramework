# Contributing to adamant-ModpackFramework

`adamant-ModpackFramework` owns coordinator orchestration:
- discovery
- hashing
- HUD
- the shared coordinator UI

Treat its runtime behavior and warnings as public coordinator contract.

## Read This First

- [README.md](README.md)
- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
- [QUICK_SETUP.md](QUICK_SETUP.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)

## Contribution Rules

- Keep docs aligned with the supported framework contract.
- Prefer explicit contract warnings over silent skips.
- Treat hash/profile ABI changes as compatibility work, not refactoring.
- Keep Framework focused on coordinator orchestration. Module UI belongs to module hosts.

## Validation

```bash
cd adamant-ModpackFramework
lua52.exe tests/all.lua
```
