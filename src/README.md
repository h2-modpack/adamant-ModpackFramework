# adamant-ModpackFramework

Shared coordinator UI framework for adamant Hades II modpacks.

This package is a dependency used by modpacks. On its own, it does not add gameplay
content. When a supported modpack is installed, the framework provides the shared
in-game modpack window, profile/hash import and export, Quick Setup, and HUD
fingerprint display.

## For Players

Install this when a modpack lists it as a dependency. Most mod managers install it
automatically.

In game, supported modpacks use this framework to expose:
- one shared modpack menu
- per-module settings tabs
- quick setup controls
- saved profile slots
- copy/paste config hashes
- a small HUD fingerprint for the active settings

## For Mod Authors

Author-facing contracts and integration docs live in the repository root:
- `README.md`
- `COORDINATOR_GUIDE.md`
- `QUICK_SETUP.md`
- `HASH_PROFILE_ABI.md`

This packaged README is intentionally player/package oriented.
