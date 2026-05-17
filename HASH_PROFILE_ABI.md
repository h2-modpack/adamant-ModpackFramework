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
- keys and values are token-escaped before joining with `=` and `|`

`ModuleId=1` is the Lib-injected `Enabled` alias encoded as module enable
state. Framework does not also emit `ModuleId.Enabled`.

The same string is used for:
- portable sharing
- local coordinator profile slots

### Token Escaping

The canonical string uses `=` between each key/value pair and `|` between entries.
Literal reserved characters inside keys or values are escaped before serialization:

| Raw character | Encoded token |
| --- | --- |
| `%` | `%25` |
| `|` | `%7C` |
| `=` | `%3D` |

Encoding applies to token contents only. The envelope delimiters remain raw:

```text
ModuleId.Filter=Apollo%7CZeus%3DPoseidon%25Chaos
```

decodes to:

```text
ModuleId.Filter = Apollo|Zeus=Poseidon%Chaos
```

Always encode `%` before other reserved characters, and decode after splitting the
canonical string into entries. This keeps persisted string storage values safe when
they contain hash delimiters.

## Frozen ABI Surface

Treat the following as frozen after release unless you are doing deliberate compatibility work:
- `definition.id`
- `definition.name` for user-facing module identity
- persisted storage root `alias`
- storage `default`
- storage type `toHash(...)`
- storage type `fromHash(...)`
- `definition.hashGroupPlan` key prefixes, item boundaries, and alias order

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

### `definition.name`

Lib requires every module to declare a display name. Framework uses it for
module UI labels when `shortName` is absent and for diagnostics. Changing it does
not move hash keys, but it is still user-facing metadata and should be treated as
intentional UI compatibility work.

### Storage root `alias`

Storage values are encoded under:

```text
ModuleId.alias=value
```

`alias` is the hash key.

Lib also uses `alias` as the managed persistence key for ordinary storage roots.
Aliases are direct flat storage identifiers.

Only roots with `hash ~= false` participate in hash/profile serialization.

Exception: Lib injects `Enabled` as normal prepared storage, but Framework
serializes it through the module-level `ModuleId=1` key so module enabled state
keeps the historical hash format. Lib-injected `DebugMode` has `hash = false`.

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

Framework token escaping is also part of the wire envelope. Storage type codecs
should return their logical token value; Framework owns escaping delimiters in the
outer key/value format.

### `definition.hashGroupPlan`

When a module declares hash groups, the group surface becomes part of the wire format.

Compatibility-sensitive parts are:
- group key
- which root aliases belong to the group
- member order inside the group

## Hash Groups

`definition.hashGroupPlan` provides optional grouping hints that let Framework compress multiple small persisted root values into one base62 token.

Supported members:
- root `bool`
- root `int`
- root `packedInt` with derivable pack width

Not supported:
- packed child aliases
- `Enabled`
- roots declared with `hash = false`

Reason:
- packed child aliases already belong to a packed root
- `Enabled` is encoded as module enable state
- non-hash state is intentionally not part of portable/shared config state

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
- `definition.id` - identifies the module in hashes and profiles
- persisted storage root `alias` names - identify values within a module's namespace
- storage defaults - consumed when a persisted value is absent
- `definition.hashGroupPlan` layout - determines grouped hash encoding

Changing any of these is a compatibility event and requires an explicit compatibility plan.
