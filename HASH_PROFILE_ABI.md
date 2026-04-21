# Hash and Profile ABI

This document defines the compatibility contract for Framework hashing and profile storage.

If a change alters:
- how a module is identified
- how a persisted storage field is keyed
- how defaults are interpreted
- how a value is serialized

treat it as ABI work, not cleanup.

## Scope

Covered data:
- shared hashes created by Framework
- coordinator profile slots stored in Chalk config
- discovered coordinated modules

For UI and host behavior, use [README.md](README.md) and [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md).

## Canonical Format

Framework encodes config state into a canonical key-value string:

```text
_v=1|ModuleId=1|ModuleId.alias=value
```

Properties:
- `_v` is the hash format version and must be present
- keys are sorted alphabetically before final serialization
- only non-default values are encoded
- unknown keys are ignored on decode
- missing keys decode to current defaults

The same string is used for:
- portable sharing
- local coordinator profile slots

## Frozen ABI Surface

Treat the following as frozen after release unless you are doing deliberate compatibility work:
- `definition.id`
- persisted storage root `alias`
- storage `default`
- storage type `toHash(...)`
- storage type `fromHash(...)`
- `definition.hashGroups` keys, membership, and member order

These are the wire format.

## Why Each One Matters

### `definition.id`

Module enable state is encoded under the module id.

Changing:

```lua
definition.id = "OldName"
```

to:

```lua
definition.id = "NewName"
```

moves the module into a new hash namespace.

### Storage root `alias`

Storage values are encoded under:

```text
ModuleId.alias=value
```

`alias` is the hash key.
`configKey` is the Chalk persistence path.

If `alias` is omitted, it defaults to the stringified `configKey`, which means `configKey` becomes the hash key and is implicitly frozen.

### `default`

Framework only encodes non-default values.

Changing a default is a compatibility change even if the field name stays the same.

### `toHash(...)` / `fromHash(...)`

Field type serialization is part of the wire format.

Changing:
- accepted strings
- normalization rules
- numeric formatting
- fallback behavior

can change how existing hashes decode or what future hashes look like.

### `definition.hashGroups`

When a module declares hash groups, the group surface becomes part of the wire format.

Compatibility-sensitive parts are:
- group key
- which root aliases belong to the group
- member order inside the group

## Hash Groups

`definition.hashGroups` compresses multiple small persisted root values into one base62 token.

Supported members:
- root `bool`
- root `int`
- root `packedInt` with derivable pack width

Not supported:
- packed child aliases
- transient root aliases

Reason:
- packed child aliases already belong to a packed root
- transient state is intentionally not part of portable/shared config state

## Decode Behavior

Framework provides these decode guarantees:
- hash format version check on decode
- unknown keys are ignored
- missing keys fall back to defaults
- saved coordinator profiles are audited at `Framework.init(...)` and warn on unknown field keys inside known module namespaces

Module authors own compatibility plans for:
- renamed module ids
- renamed aliases
- changed defaults
- changed encoding semantics
- changed hash group layout

## Shipped-Module Invariants

Once a module is publicly shipped, the following are part of its ABI and should be treated as stable:
- `definition.id` — identifies the module in hashes and profiles
- persisted storage root `alias` names — identify values within a module's namespace
- storage defaults — consumed when a persisted value is absent
- `definition.hashGroups` layout — determines hash encoding

Changing any of these is a compatibility event and requires an explicit compatibility plan.
