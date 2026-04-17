# Hash and Profile ABI

This document defines the compatibility contract for Framework hashing and profile storage.

If a change alters:
- how a module is identified
- how a persisted storage field is keyed
- how defaults are interpreted
- how a value is serialized

treat it as ABI work, not cleanup.

## Scope

This applies to:
- shared hashes created by Framework
- coordinator profile slots stored in Chalk config
- discovered coordinated modules

It does not describe the full UI contract.
It only covers serialized identity and value encoding.

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

can change how old hashes decode or what new hashes look like.

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

## Current Compatibility Behavior

Framework currently provides limited compatibility behavior:
- hash format version check on decode
- unknown keys are ignored
- missing keys fall back to defaults
- saved coordinator profiles are audited at `Framework.init(...)` and warn on unknown field keys inside known module namespaces

Framework does not automatically preserve compatibility for:
- renamed module ids
- renamed aliases
- changed defaults
- changed encoding semantics
- changed hash group layout

Those are author-owned compatibility tasks.

## Recommended Rules

Once a module is publicly shipped:
- do not rename `definition.id`
- do not rename persisted storage root `alias`
- do not casually change defaults
- do not casually change `definition.hashGroups`

If you must change one of these, handle it as compatibility work with an explicit migration plan.
