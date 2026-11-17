---
CoIP: X
Title: Compact Serialization Format
Authors:
  - Kevin Millikin (kmillikin)
Status: Draft
Category: Language
Created: 2026-09-30
Requires: None
Replaces: None
---

<!--
 This file is part of Compact.
 Copyright (C) 2026 Midnight Foundation
 SPDX-License-Identifier: Apache-2.0
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License. 
-->

## Abstract

There are three different binary serialization formats for Compact values:
the public ledger encoding,
the standard library's event serialization format (`serialize` and `deserialize`),
and `as` casts between some types and byte vectors.

With the exception of some of the byte vector casts,
these formats are currently considered implementation details with no specification.
They are not versioned and can change between Compact releases.
The three formats do not necessarily agree with each other.

This CoIP specifies a single raw serialized representation for all Compact types other
than types containing contract types and opaque types.
The ledger encoding and the byte-vector casts are required to agree with it.
Standard-library serialized values carry major and minor version bytes,
with defined rules for breaking and non-breaking changes.
The standard library's byte-oriented hashing functions compute a hash of
the raw serialized representation of major version 1, so hashes are stable across Compact releases.

The proposal changes the semantics of casts from `Bytes` to `Field`.

## Motivation

Compact values are already communicated in serialized form.
[Events](https://github.com/LFDT-Minokawa/compact/blob/main/coips/coip-0003.md)
are emitted as byte vectors and decoded off-chain by indexers and wallets.
Hashes of serialized Compact values are used as map keys, Merkle leaves, and commitments
that persist in contract state across upgrades.
Contract authors can build their own message formats by hand using `Bytes` casts.

Each of these depends on binary encodings that are either unspecified or specified independently of each other.
Off-chain decoders can only be written by reverse engineering the compiler's source code.
A standard-library byte-oriented hash function is stable only as long as the undocumented encoding is unchanged.
There is no rule guaranteeing that a value written by one compiler version can be read by
another compiler version.
The existing encodings are separate implementations and already disagree for several types.

This CoIP addresses these problems by proposing one specified raw serialization format
and versioned serialized values.
The ledger encoding, the byte-vector casts, and the standard library's byte-oriented hashing functions
agree with this encoding.
The rest of this section describes the three existing formats and how they relate.

### The public ledger serialization format

In the Midnight Network, a contract's public ledger state is a binary-encoded `StateValue`
defined by the Midnight ledger's [on-chain runtime specification](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-10/spec/onchain-runtime.md#values).
Compact values are held in individual `Cell`s within the `StateValue`,
and each `Cell` contains a *Field-Aligned Binary* (FAB) `AlignedValue`
as defined by the ledger's [Field-Aligned Binary specification](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-10/spec/field-aligned-binary.md).

The binary encodings of `StateValue` and `AlignedValue` are determined by the ledger
and out of Compact's control.
Everything above them is under Compact's control:
how Compact values are serialized into `AlignedValue`s,
and how a contract's public state is laid out as `Cell`s in a `StateValue`.
The ledger simply stores and retrieves whatever it is given.
This CoIP is concerned only with how Compact values are serialized.
Changes to the state layout and changes to ledger formats are out of scope.

An `AlignedValue` is a FAB `Value`, a sequence of value atoms,
paired with a FAB `Alignment`, a same-length sequence of alignment atoms describing them.
A value atom is a blob of bytes (in JavaScript, a `Uint8Array`).
An alignment atom tells how to interpret the corresponding value atom.

Compact uses three kinds of alignment atoms:
- `{ tag: 'field' }` for a native field element,
- `{ tag: 'bytes', length: N }` for a byte vector of length `N`, and
- `{ tag: 'compress' }` for an arbitrary-length byte string that is represented  in circuit by a commitment.

`field` and `bytes` value atoms are stored with trailing zero bytes dropped.

Serialization into aligned values is implemented in the Compact runtime
using so-called *descriptor* objects.
A descriptor has a `toValue` function that converts a Compact value's JavaScript representation into a FAB `Value`,
and an `alignment` function that gives the type's FAB `Alignment`.
Together, they produce an `AlignedValue`.
A descriptor has a `fromValue` function that converts a FAB `Value` back into a JavaScript representation
using the type's alignment.

This format is used for more than just ledger state.
The standard library hashing functions hash a value's FAB representation.
Public and private proof inputs are passed from JavaScript to the proof server in FAB form.

The ledger serialization format is defined for all Compact values.
There is no specification other than the Compact runtime's implementation of descriptors.
It is not versioned, and there is no compatibility guarantee made between versions of the Compact runtime.

Compact code does not have explicit access to FAB `Value` serialization of Compact typed values.
Serialization and deserialization is implicit,
and happens whenever values are written into or read from the ledger.

### The event serialization format

The [CoIP-3 events](https://github.com/LFDT-Minokawa/compact/blob/main/coips/coip-0003.md) proposal,
which has been implemented,
adds generic `serialize<T, #N>` and `deserialize<T, #N>` circuits to the standard library.
CoIP-3 requires them to be defined at least for the standard event types, and to be usable in circuit.
`emit` uses the same format to encode an event's payload.

The format is a flat byte vector with no type information:
each atomic value is encoded in a fixed number of bytes,
and compound values are encoded by concatenating the encodings of their parts.
`serialize<T, N>` converts a value of type `T` into a value of type `Bytes<N>`,
where `N` must be at least the serialized size of `T`.
If it is larger, the result is padded with zero bytes.
`deserialize<T, N>` converts a value of type `Bytes<N>` into a value of type `T`,
where `N` must be at least the serialized size of `T`.
If it is larger, `deserialize` ignores any bytes beyond the serialized size of `T` and does not check them.

The format is implemented for all Compact types except types containing contract types and opaque types.
The implementation is by code generation in the compiler.
The `expand-serialize` pass in [compiler/analysis-passes/expand-serialize.ss](https://github.com/LFDT-Minokawa/compact/blob/main/compiler/analysis-passes/expand-serialize.ss)
generates an intermediate representation which is further compiled to JavaScript and ZKIR.

There is no specification other than the Compact compiler's code generation implementation.
The format is not versioned, and there is no compatibility guarantee made between versions of Compact.
It has a separate implementation from the ledger serialization format and is not required to agree with it.
Where the two do agree, that is coincidental rather than guaranteed,
and they currently disagree for several types,
including the foreign field types, `Uint<0..1>`, and single-element enumerations.

### Casting to and from byte vectors

The Compact language also allows type casts using the keyword `as`,
and some types support casting to and from Compact byte vectors (`Bytes<N>`).
These casts are defined in the [Compact Reference](https://github.com/LFDT-Minokawa/compact/blob/main/doc/compact-reference.mdx),
but they are ad hoc: they exist only for some types, and they were not designed as a serialization format.

The available casts are:

- `Field` and `Uint` types, to and from `Bytes<N>` for any non-zero `N`.
  The byte vector is the little-endian encoding of the value.
  A cast to `Bytes<N>` fails if the value does not fit in `N` bytes,
  and a cast from `Bytes<N>` fails if the encoded value exceeds the target type's maximum value.
- The foreign field types to and from `Bytes<32>`, also little-endian.
  Unlike `Field` and `Uint`, a cast from `Bytes<32>` cannot fail.
  The encoded value is reduced modulo the corresponding field order.
- `Bytes<64>` can additionally be cast to `Curve25519Scalar`.
- Vectors and tuples of `N` byte-sized unsigned integers to and from `Bytes<N>`,
  where the conversion is element-by-element.

There are no direct casts between `Bytes` and `Boolean`, enumeration types, `JubjubScalar`,
structure types, curve points, or opaque types.
Some of these can be reached by casting through an intermediate value of `Field` or `Uint` type.

Where a cast does exist and the target size is the type's serialized size,
the cast currently agrees with the event serialization format because the implementation
of event serialization is in terms of the cast.
It does not necessarily agree with the ledger serialization format;
for example the two differ for the foreign field types.
As with the other formats, there is no compatibility guarantee between versions of Compact.

### A note on hashing

The Compact standard library provides hashing functions.
One of them is `persistentHash<T>`, which uses the SHA-256 algorithm.
Its documentation reads:

> This function is a non-circuit-optimised compression function from arbitrary values to a 256-bit bytestring.
> It is guaranteed to persist between upgrades, and to consistently use the SHA-256 compression algorithm.
> It *should* be used to derive state data, and not for consistency checks where avoidable.

This is unclear, and developers have interpreted it as meaning that hashing the same Compact typed value will
always produce the same hash.
This is **not** what is actually guaranteed.
`persistentHash` applies SHA-256 to the FAB serialization of the Compact value:
- `field` atoms as 32 little-endian bytes,
- `bytes` atoms padded to their length, and
- `compress` atoms replaced by a 32-byte commitment to their contents.

Only the use of SHA-256 is guaranteed to persist.
Since the serialization of Compact values into FAB is **not stable**,
the hash of a given value would change if Compact ever changed this serialization format.

Such hashes are typically stored in contract state as map keys, Merkle tree leaves, or commitments
so a change in the format could silently invalidate that state.

The same applies to the standard library functions `persistentCommit`, `keccak256`, and `sha512`,
which hash the FAB serialization of the Compact value.

None of these hashing functions can be applied to values whose type contains an opaque type;
the compiler rejects this statically.
The on-chain runtime can compute such a hash, because it hashes the commitment to an
opaque value rather than its bytes.
However, ZKIR cannot reconstruct a `compress` atom from its in-circuit representation and so
it cannot compute the same commitment in circuit.

### A note on the in-circuit representation of the ledger serialization

ZKIR circuits operate on ledger serialized values,
but they represent them as sequences of native field elements rather than as arrays of bytes.
This is sometimes thought of as a fourth serialization format.
It is not:
it is a different *representation* of the FAB serialization,
obtained from it by a fixed translation.

The ledger's Field-Aligned Binary specification defines [this translation](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-10/spec/field-aligned-binary.md#field-representation)
from an `AlignedValue`, a sequence of value atoms together with their alignment atoms,
into a sequence of field elements.
Each value atom is translated according to its alignment atom:

- a `field` atom becomes a single field element;
- a `bytes` atom of length `N` becomes `ceiling(N/31)` field elements, each holding up to 31 bytes of it;
- a `compress` atom becomes a single field element, a commitment to its contents.

Compact chooses the alignment atoms, through its descriptors, but it has no other say in the translation.
Once a Compact value has been serialized into FAB,
its field representation is determined.
Any change to Compact's FAB serialization therefore changes the field representation too,
and specifying the FAB serialization specifies both.
The translation is reversible for `field` and `bytes` atoms,
but not for `compress` atoms, whose contents cannot be recovered from their commitment.

The field representation is used wherever Compact values reach the proof server.
JavaScript execution of a circuit collects the data necessary to construct a proof:
private inputs including circuit inputs,
and public inputs including the Impact code that was executed.
This data is FAB encoded,
and the Midnight.js library translates it into the field representation before sending it to the proof server.
`transientHash` also hashes this representation of its argument.

Because ZKIR is a typed language,
the field representation of each ZKIR-typed value must also be the one that the separate ZKIR implementation expects.
ZKIR has an implicit "decode" operation when it uses a field-encoded public or private input,
which converts the field representation into ZKIR's native representation of the value.
This constrains the alignments Compact can choose.
For example, ZKIR expects a `Secp256k1Base` value `v` as two field elements,
holding the low 192 bits and the high 64 bits of `v - 1`.
Compact therefore serializes such a value into FAB as a 24-byte atom and an 8-byte atom containing `v - 1`,
so that the translation produces exactly those two field elements.
This is why the ledger serialization of the foreign field types differs from their event serialization.

It is important to note that the field representation is mostly irrelevant to the ledger.
The Compact compiler and the ZKIR implementation need to agree on it, but the ledger does not know what it is.
The exception is that the public inputs representing Impact code have a specific field representation
that the ledger relies on.

## Specification

This section specifies a binary serialization format for Compact values.
It defines:

- the **raw serialized representation** of every serializable type,
  in [Raw serialized representations](#raw-serialized-representations);
- **serialized values**, which are raw serialized representations preceded by two version bytes,
  as produced by the standard library's `serialize` and consumed by its `deserialize`,
  in [Version bytes](#version-bytes);
- the [Invariants](#invariants) that `serialize`, `deserialize`,
  and the byte-oriented hashing functions are required to satisfy.

It also requires the existing formats to agree with the raw serialized representation:

- the ledger serialization of a value, as produced by the Compact runtime's descriptors,
  agrees with its raw serialized representation in the sense defined in
  [Raw serialized representations](#raw-serialized-representations);
- where a cast between a type and `Bytes<N>` exists and `N` is the size of the type's raw serialized representation,
  the cast to `Bytes<N>` produces the raw serialized representation,
  and the cast from `Bytes<N>` agrees with raw deserialization;
- JavaScript execution and circuit execution agree,
  producing the same results and failing on the same inputs.

The format is designed around the following decisions.

**Type-directed.**
A raw serialized representation contains no type information.
Serialization and deserialization are always performed at a type known at compile time,
and the size of a type's raw serialized representation is determined by the type alone.

**Atomic and compound types.**
Each **atomic type** has its own rule giving its raw serialized representation.
The raw serialized representation of a value of a **compound type**
(a tuple, vector, or structure)
is the concatenation of the raw serialized representations of its parts, in order.
A type that is defined to be serialized as some other type,
such as an enumeration type serialized as a `Uint` type,
is treated as an atomic type whose rule refers to that other type.

**Little-endian.**
Numeric values are encoded in little-endian byte order.

**Efficient in circuit.**
The rules are chosen so that serialization and deserialization of field-based types
correspond to ZKIR's `ToBytes` and `FromBytes` instructions where possible.

**Canonical and non-canonical representations.**
Serialization always produces a canonical raw serialized representation.
Deserialization of some atomic types also accepts non-canonical raw serialized representations.
The rules for each atomic type say whether it has non-canonical representations, and what they are.
The consequences for hashing are stated in [Deserialization and hashing](#deserialization-and-hashing).

The rules in this section are normative.
Examples, notes, and stated consequences are not.

### Version bytes

A **format version** is a pair of a major version and a minor version, written `MAJOR.MINOR`.
Each is a number from 0 to 255.
The format defined by this CoIP is version 1.0.
The format implemented by the compiler at the time of writing is designated version 0.0.

A **serialized value** is a byte vector consisting of two **version bytes**, `MAJOR` and `MINOR`,
followed by the raw serialized representation of a Compact value,
as defined in [Raw serialized representations](#raw-serialized-representations).
The **serialized size** of a type `T` is two plus the size of its raw serialized representation.

```
 Byte 0  Byte 1
+-------+-------+-----------------------------------+
| MAJOR | MINOR | RAW SERIALIZED REPRESENTATION ... |
+-------+-------+-----------------------------------+
```

**Breaking and non-breaking changes.**
A change from format version X to format version Y is **non-breaking** if and only if:

1. every type that has a raw serialized representation in version X has the same raw serialized representation in version Y, and
2. every serialized value that version X can deserialize, version Y can also deserialize, producing an equal value.

Any other change is **breaking**.
A non-breaking change increments the minor version.
A breaking change increments the major version and sets the minor version to 0.
For example, adding a raw serialized representation for a type that previously had none is non-breaking,
while changing the raw serialized representation of an existing type is breaking.

**Type versions.**
Within a major version `M`, the **version of a type** `T` is `M.N`,
where `N` is the least minor version in which every type occurring in `T` has a raw serialized representation.
The types occurring in `T` are `T` itself and, recursively, the types of its elements, fields, and components.
For version 1.0, every type with a raw serialized representation has version 1.0.

**Writing version bytes.**
`serialize<T, N>` writes the version of `T` as its version bytes,
whatever the minor version of the compiler that produced it.

**Reading version bytes.**
`deserialize<T, N>` fails unless its argument's version bytes are exactly the version of `T`.
It then deserializes the raw serialized representation that follows.

These rules have the following consequences:

- A value of type `T` is readable by any compiler with the same major version that supports `T`,
  whether that compiler is older or newer than the one that wrote it.
  In particular, an older compiler can read values written by a newer one,
  provided the value's type existed in the older version.
- A compiler never reads a serialized value with a different major version.
  Supporting values written with an older major version,
  or migrating them, is outside the scope of this CoIP.
- Because the version of a type is fixed, the serialized value for a given Compact value is unique.
  Two serialized values of the same type are equal if and only if the values they encode are equal,
  as long as the raw serialized representations involved are canonical.
- Hashing is defined on the raw serialized representation, without the version bytes;
  see [Serialization and hashing](#serialization-and-hashing).

**This CoIP proposes adding the version bytes `[0x00, 0x00]` to every value serialized by the current implementation.**
Since this changes the output of `serialize`, it is itself a breaking change to the current, unversioned format.

### Standard library API

The standard library provides two circuits for serialization:

```compact
circuit serialize<T, #N>(x: T): Bytes<N>;
circuit deserialize<T, #N>(b: Bytes<N>): T;
```

`T` must be a serializable type,
and `N` must be at least the serialized size `M` of `T`;
otherwise the program is rejected at compile time.

`serialize<T, N>(x)` is the serialized value of `x`
followed by `N - M` zero bytes.

`deserialize<T, N>(b)` reads a serialized value from the first `M` bytes of `b`.
It fails if the version bytes are not the version of `T`,
or if the rules for `T` reject the raw serialized representation.
Otherwise it returns the value it encodes.
The remaining `N - M` bytes of `b` are ignored and not checked.

When `N` is equal to `M`, `serialize<T, N>` produces exactly a serialized value
and `deserialize<T, N>` reads exactly a serialized value.
`emit` serializes an event's payload in this way.
An event payload is the serialized value of the event,
including its version bytes and with no trailing bytes,
so its size is the serialized size of the event't type.

### Invariants

This section states properties that the serialization rules,
`serialize`, `deserialize`, and the byte-oriented hashing functions are required to satisfy.
The rules in [Raw serialized representations](#raw-serialized-representations) are designed so that they hold.

A **serializable type** is a Compact type that has a raw serialized representation.
These are the types that contain no contract types and no opaque types.

Throughout this section, `T` is a serializable type and
`N` is the size of its raw serialized representation,
and so its serialized size is `N+2`.
For a serialized value `b` of type `Bytes<N+2>`,
`slice<N>(b, 2)` is its raw serialized representation without the version bytes.

`N+2` is not valid as a Compact size parameter,
in the invariants below it stands in for the Compact literal `M` such that `M` is equal to `N+2`.

The invariants are stated for size argument `N+2`, by definition of serialization for larger sizes
they extend to any larger size argument except that a serialized value with non-zero trailing bytes
is accepted but not canonical.

All of these invariants hold both for JavaScript execution and in circuit.
Moreover, JavaScript execution and circuit execution of `serialize<T, N+2>` and `deserialize<T, N+2>` agree:
they produce the same results for the same arguments,
and `deserialize<T, N+2>` fails in one exactly when it fails in the other.

#### Round tripping

For all values `x` of type `T`:

```
deserialize<T, N+2>(serialize<T, N+2>(x)) == x
```

A serialized value `b` of type `T` is **accepted** if `deserialize<T, N+2>(b)` does not fail.
An accepted serialized value `b` is **canonical** for `T` if:

```
serialize<T, N+2>(deserialize<T, N+2>(b)) == b
```

A raw serialized representation `r` of type `T` is **canonical** if
the serialized value consisting of the version bytes of `T` follwed by `r`
is canonical.

Every serialized value produced by `serialize<T, N+2>` is canonical.
`deserialize<T, N+2>` accepts only the exact version of `T`,
so an accepted argument's version bytes are the only possible ones.
Some accepted serialized values are not canonical:
the rules for some atomic types accept more than one raw serialized representation of the same value,
for example a `Field` whose encoded integer is at least the field order.
The rules for each atomic type say whether it has non-canonical representations.
A serialized value of a compound type is canonical if and only if the raw serialized representations of all of its parts are canonical.

For a value `x` of type `T`, `serialize<T, N+2>(x)` is the unique canonical serialized value `b` with `deserialize<T, N+2>(b) == x`.

#### Serialization and hashing

For all values `x` of type `T`:

```
persistentHash<T>(x) == persistentHash<Bytes<N>>(slice<N>(serialize<T, N+2>(x), 2))
```

and for all byte vectors `v` of type `Bytes<N>`,
`persistentHash<Bytes<N>>(v)` is the SHA-256 hash of the `N` bytes of `v`.
That is, `persistentHash<T>(x)` is the SHA-256 hash of the raw serialized representation of `x`.
The version bytes are not hashed.

`persistentHash` is defined in terms of the raw serialized representations of major version 1.
A future major version that changes the raw serialized representation of a type
does not change the result of `persistentHash` for that type.

`persistentHash<T>(x)` depends only on the raw serialized representation of `x`, and not on `T`.
Values of different types with the same raw serialized representation have the same hash;
for example, `persistentHash<Uint<8>>(5) == persistentHash<Bytes<1>>([5])`.
Programs that need hashes of different kinds of data to be distinct
must include a distinguishing value in the data being hashed,
as the standard library does with domain separators.

The same invariants hold for `keccak256` and `sha512`,
which hash the raw serialized representation with Keccak-256 and SHA-512 respectively:

```
keccak256<T>(x) == keccak256<Bytes<N>>(slice<N>(serialize<T, N+2>(x), 2))
sha512<T>(x)    == sha512<Bytes<N>>(slice<N>(serialize<T, N+2>(x), 2))
```

They also hold for `persistentCommit`, for every opening `rand` of type `Bytes<32>`:

```
persistentCommit<T>(x, rand) == persistentCommit<Bytes<N>>(slice<N>(serialize<T, N+2>(x), 2), rand)
```

As for `persistentHash`, these functions are defined in terms of the raw serialized representations of major version 1,
and do not depend on `T` except through the raw serialized representation of their argument.

#### Deserialization and hashing

For all serialized values `b` accepted by `deserialize<T, N+2>`:

```
persistentHash<T>(deserialize<T, N+2>(b)) == persistentHash<Bytes<N>>(slice<N>(serialize<T, N+2>(deserialize<T, N+2>(b)), 2))
```

This follows from the previous hashing invariant where `x` is `deserialize<T, N+2>(b)`.
If `b` is canonical for `T`, then also:

```
persistentHash<T>(deserialize<T, N+2>(b)) == persistentHash<Bytes<N>>(slice<N>(b, 2))
```

This follows from replacing `serialize<T, N+2>(deserialize<T, N+2>(b))` with `b` on the right-hand side,
because `b` is canonical.
If `b` is not canonical, this second equation does not hold in general.

A program that deserializes a value from bytes it did not produce itself,
and that hashes or compares those bytes,
should hash or compare the deserialized value (or its re-serialization) rather than the bytes it received,
unless it knows that they are canonical.

The same holds for `persistentCommit` (with the same opening on both sides), `keccak256`, and `sha512`.

#### Transient hashing

These invariants do not apply to `transientHash`.
`transientHash` is defined on the field representation of a value's ledger serialization,
not on its raw serialized representation,
and `transientHash<T>(x)` is in general not equal to the transient hash of `serialize<T, N+2>(x)` or of its raw serialized representation.

### Raw serialized representations

The raw serialized representation is specified by the type-directed rules below.
The ledger serialization format is also defined below.
It will agree with the raw serialization representation in the following sense:
if the ledger alignment atoms are dropped so that there is a sequence of value atoms (`Uint8Array`s),
trailing zeros are added back using the alignment atoms,
and the value atoms are then concatenated,
then this produces exactly the same bytes as raw event serialization.

[TODO: restate this in terms of the new invariants]
Raw serialization followed by raw deserialization of a value of type `T` is the identity on `T`,
producing an equal value.
Raw deserialization followed by raw serialization of a byte vector `Bytes<N>` is not necessarily
the identity on `Bytes<N>`, however if `Bytes<N>` was produced by serialization then
this **is** the identity on `Bytes<N>`.

#### Atomic Types

**Boolean:** This is a built in Compact type.
The raw serialized representation is `Bytes<1>`, a single-element byte vector.
`true` is serialized as `[1]` and `false` is serialized as `[0]`.
Raw deserialization fails on any other byte vector than the canonical ones `[0x0]` and `[0x1]`.

The ledger serialization has `{ tag: 'bytes', length: 1 }`.
Ledger deserialization will reject non-canonical serialized values.

There ar currently no in-language casts between `Boolean` and `Bytes<1>` in either direction.
The raw serialization rule is captured by the Compact code `Bytes [b ? 1 : 0]`;
and the raw deserialization rule is captured by the Compact code
`(assert(b[0] <= 1, "deserialization failure"), b[0] == 1)`.

**Uint<0..N>:** These are built in Compact types.
The raw serialized representation is a byte vector `Bytes<M>`,
where `M` is the maximum of 1 and the number of bytes required to represent the maximum value `N-1`
(so `M` is at least 1).
The byte vector contains the little-endian encoding of the unsigned integer's value.
Raw deserialization fails if the little endian encoding represents an
unsigned integer greater than or equal to `N`.

The ledger serialization has `{ tag: 'bytes', length: M }` for the same `M` as above.
Ledger deserialization will reject non-canonical serialized values.

The cast from `Uint<0..N>` to `Bytes<M>` produces the raw serialized representation.
The cast from `Bytes<M>` to `Uint<0..N>` deserializes the raw serialized representation.

It fails if little-endian encoded unsigned integer represented by the byte vector is greater than
or equal to `N`.

**Uint<N>:** These are built in Compact types.
Compact sized integer types `Uint<N>` are serialized exactly as
the bounded unsigned integer type `Uint<0..M>` where `M` is `2^N`.

So for instance, `Uint<8>` has the same raw serialized representation as `Uint<0..256>`,
that is `Bytes<1>`;
and `Uint<16>` is (little-endian) `Bytes<2>`; etc.

**Field:** This is a built in Compact type.
The raw serialized representation is a byte vector `Bytes<32>`.
The byte vector contains the canonical little-endian encoding of the native field's value.
Raw deserialization converts a byte vector to an unsigned integer,
and then reduces that number modulo the field order.

The ledger serialization has `{ tag: 'field' }`.
This will accept a `Uint8Array` up to length 32 and deserialize it as
an unsigned integer, reduced modulo the field order.

There are casts between `Field` and `Bytes<32>` that obeys these rules[^1].

**JubjubScalar:** This is a Compact standard library type.
The raw serialized representation is a byte vector `Bytes<32>`.
The byte vector contains the little-endian encoding of the Jubjub scalar's value.
Raw deserialization converts a byte vector to an unsigned integer,
and then reduces that number modulo the field order.

The ledger serialization has `{ tag: 'field' }`.
This will accept a `Uint8Array` up to length 32 and deserialize it as
an unsigned integer, reduced modulo the field order.

There is a cast between `JubjubScalar` and `Bytes<32>` that obeys these rules[^2].

**Secp256k1Base:** 

[The ledger stores v-1 as a 24-byte atom followed by an 8-byte atom.
Ledger decoding range checks, it does not reduce by the field order.
Event serialization writes a single little-endian vector, not split and not offset.
Deserialization reduces modulo the field order.
So does the Compact cast from `Bytes<32>`.
In-circuit there are two encodings, the `to_bytes/from_bytes` encoding
which agrees with event serialization, and the `public_input/private_input` encoding
which agrees with the field encoding of the ledger encoding.

To have the same encoding, we need to reconcile this difference.
Ask the Crypto team, it will require changes to ZKIR.]

**Bytes<N>:** These are built-in Compact types.
The raw serialized representation is the byte vector itself.

The ledger serialization has `{ tag: 'bytes', length: N }`.

In Compact, the raw serialized representation of `b: Bytes<N>` is just `b` itself.

**Enumeration Types:** These are program-defined Compact types.
The raw serialized representation of a value an enumeration type
is its zero-based element index in declaration order.
It uses the same encoding as `Uint<0..N>`, where `N` is the number of enumeration elements.
Specifically, it is a byte vector `Bytes<M>` where `M` is the maximum of 1 and
the number of bytes required to represent the zero-based index of the last declared element.
It is encoded in little-endian order.

The ledger serialization has `{ tag: 'bytes', length: M }` for the same `M` as above.

In Compact, the raw serialized representation of `e: T` where `T` is an enumeration type
can be obtained by `e as Uint<0..N> as Bytes<M>` for `N` and `M` as above.
Likewise the raw serialized representation `b: Bytes<M>` can be deserialized by
`b as as Uint<0..N> as T`.

**Opaque<'Uint8Array'>:** This is a built in Compact type.
The raw serialized representation is `Bytes<N>`
where `N` is the length of the `Uint8Array`.
The byte vector contains the bytes of the `Uint8Array` in order.

The ledger serialization has `{ tag: 'compress' }`.
This tag does not have a length property, but it is not needed for deserialization because
"compress" values are allowed by the ledger to have trailing zeros.

There is no way other than serialization to convert a Compact `Opaque<'Uint8Array'>` to a byte vector.

[Note: should we disallow this, even for serialization by the runtime?
Can we support this in circuit at all?
We could try using a serialization witness to provide the byte vector representation
and assert that the `transient_hash` is equal to the in-circuit value of the input.]

**Opaque<'string'>:** [Needs to be filled out.]

#### Compound Types


Key ideas:

1. The serialized format is versioned with a pair of MAJOR / MINOR version bytes.
   We will use semantic versioning (we need some thought to consider if and how we could add
   new optional fields to a serialized representation).
1. The ledger format and the event serialization format agree (except maybe: the ledger format does not have a version tag)
1. Base types use the in-circuit `to_bytes`/`from_bytes` encoding.
1. `as` casts to `Bytes` exist for all base types and they agree with serialization in the sense that
    1. casting to `Bytes` produces the ledger encoding of the same value
    1. round tripping from a type `T` to `Bytes` and back is the identity on `T`
       (but not necessarily in the opposite directions,
       e.g., casting from `Bytes` to a foreign field type reduces modulo the field modulus)
  This allows Compact code to implement serialization and deserialization of parts of structures.
1. Hashing (`persistentHash` but also the other hashing functions) will be explicitly defined as
   hashing the serialized representation of a Compact value.

This design enables some implementation improvements, not mandated by this CoIP.

- The descriptors can implement serialization in JS, instead of using code generated by the compiler.
  If we want to guarantee that `serialize` agrees with the ledger encoding via `toValue`,
  we can have `serialize` call `toValue` and then flatten.
  If we want to guarantee that `deserialize` agrees with the ledger encoding via `fromValue`,
  we can have `fromValue` flatten and then call `deserialize`.
- The compiler can keep explicit `serialize` and `deserialize` instructions further into the backend,
  rather than translating them into intermediate representation instructions early in the compiler.
  The JS target can simply emit a call to a method of a type's descriptor.
  The ZKIR target can implement serialization and deserializeion in-circuit for ZKIR types
  by using `to_bytes`/`from_bytes`.
- We can change the proof server to take FAB encoded values, rather then the FAB field encoding.
  Then, for ZKIR-typed values, we do not necessarily have to convert it to the field encoding and then convert
  that encoding to the native ZKIR encoding.
  Because we've adopted the native ZKIR encoding for serializing ZKIR types into FAB,
  we already have it available without the intermediate field encoding and decoding.
  This removes the field encoding performed by Midnight.js,
  in favor of letting the ZKIR language perform its own type-directed handling of FAB.
  
### Serialization Format Version 1.0

This is draft text, outlining the current ledger format,
the current event serialization format,
and the `Bytes` serialization format where it exists.
It then describes the proposed serialization format.

TODO: massage it into a forward-looking specification, relegate changes from the existing format to an appendix?

When describing the ledger serialization of a Compact type,
we use `Field` to mean that it is serialized as a native field element (with the alignment atom tag 'field')
we use `Bytes<N>` to mean that it is serialized as a byte vector (with the alignment atom tag 'bytes' and the length N).

### Base types

Serialization is defined in terms of the serialization of **base types**.
These include some of the Compact primitive types and standard library-defined types.

#### Secp256k1Base, Secp256k1Scalar, Secp256r1Base, Secp256r1Scalar, Curve25519Base

These are Compact standard library types.
These so-called "foreign fields" are all serialized in the same way.
They have different maximum values, but they all fit in 32 bytes.
They are encoded as little-endian numbers in 32 bytes, then split into four 8-byte limbs.
Then they are serialized as a pair of byte vectors,
where the first one is 24 bytes holding the first three (little endian) limbs
and the second on is 8 bytes holding the last little endian limb.
The ZKIR representation of these fields has 1 subtracted from the value (modulo the respective field order).
For the benefit of ZKIR, we therefore serialize these by first subrtracting one,
and add one (modulo the field order) on deserialization.
The alignment tags are `Bytes<24>` and `Bytes<8>`, so ledger serialization will drop trailing zeros
from each byte vector and recover them on deserialization.
Deserialization checks that the serialized value is in range.
It **does not** reduce by the field order like `Field` deserialization does.
See the implementation of `ForeignField8_24`.

Note that this encoding is the for the benefit of ZKIR.
Remember, the ledger does not know nor care how we will interpret this `Bytes<24>`/`Bytes<8>` pair
in either Compact or in ZKIR.

The maximum values of each of these fields is larger than the native field size.
If they were encoded as a single `Bytes<32>`, then they would be represented as a pair of
native field in circuit in ZKIR private and public inputs,
where the first one held the low 31 bytes and the last one held the high byte.
By splitting them the way they are split, they will be represented instead as a pair of fields
where the first one holds the low 24 bytes (3 limbs) and the last one holds the high 8 bytes (1 limb).
It is then more efficient in circuit to extract the ZKIR limb representation from the field representation
than if it has been simply `Bytes<32>`.

The event serialization format is `x as Bytes<32>`.

#### Curve25519Scalar

This is a Compact standard library type.
The maximum value of this foreign field is less than the maximum value of the native field.
It fits in 253 bits (32 bytes without needing the three high bits, native fields need 255 bits).
It is encoded as a little-endian number in 32 bytes (guaranteed to have zeros in the three high bit positions),
then split into five limbs each consisting of 51 bits (255 bits total, guaranteed to have zeros in the two high bit positions of the last limb).
Because the ledger can only serialize even numbers of bytes,
the limbs are packed with the first four (little endian) limbs in a byte vector `Bytes<26>`
(208 bits, where the low 204 are used), and the last (little endian) limb in a byte vector `Bytes<7>`
(56 bytes, where the low 51 are used).
Like the other foreign field types `Secp256k1Base`, etc., the in-circuit representation subtracts one modulo the field order.
For the benefit of the ZKIR implementation, we perform that subtraction serialization
and add one (modulo the field order) on deserialization.
Deserialization checks that the serialized value is in range.
See `CompactTypeCurve25519Scalar`.

The event serialization format is `x as Bytes<32>`.

#### JubjubPoint

This is a Compact standard library type.
Conceptually a pair of native field values.
This is serialized in the ledger as a pair of serialized field values,
the coordinates with x-coordinate first and y-coordinate second.
See `CompactTypeJubjubPoint`.

Event serialization is not yet implemented for this type.

#### Curve25519Point

This is a Compact standard library type.
Conceptually a pair of `Curve25519Base` values.
This is serialized exactly as the pair of coordinates, according to `Curve25519Base` above.
That is, as four byte vectors `Bytes<24>`, `Bytes<8>`, `Bytes<24>`, `Bytes<8>`
containing the little endian encoding of the coordinates in order X-coordinate first
and Y-coordinate second, and where the serialized values have had one subtracted modulo the field order.
See `CompactTypeCurve25519Point`.

Event serialization is not yet implemented for this type.

#### Secp256k1Point, Secp256r1Point

These are Compact standard library types.
Conceptually they are a pair of, respectively, `Secp256k1Base` and `Secp256r1Base` values.
However, the "zero" (additive identity) point does not have affine X- and Y-coordinates.
So there is also an "identity" flag in the serialized representation.
For non-identity points, the serialized representation is the pair of base field coordinates with the
X-coordinate first and the Y-coordinate second, followed by the serialization of a 0 native field value
marking it as a non-identity point.
This is given alignment tag `field`, but since it is only ever the value 0,
the serialized representation is just the empty byte vector.
Deserialization as a field produces the value 0 from this representation.
For the identity point, the serialized representation is a pair of base field 0 values,
followed by a 1 native field value.
The base field is serialized as `Bytes<24>` followed by `Bytes<8>` as above.
Because the serialized representation has one subtracted from it modulo the field order,
these are vectors representing the maximum field value.
See `CompactTypeSecp256k1Point` and `CompactTypeSecp256r1Point`.

Event serialization is not yet implemented for these types.

## Rationale

Explain the design decisions that were made and the reasons behind them.

## Backwards Compatibility

Describe how the proposed solution affects existing systems, applications, and
users.  Is it a breaking change?

- The cast from `Bytes<32> to `Field` is a breaking change.
- Writing the version bytes for 0.0 is a breaking change.
- Changing emit to emit versioned events is a breaking change.

## Security Implications

Analyze the potential security implications of the proposed change.  Are there
any new attack vectors or vulnerabilities introduced?  How will they be
mitigated.

- The change to `Bytes<32>` to `Field` cast behavior is
  security-relevant.  Contracts that failed before will now silently
  contain collisions.  This would effect, e.g., a contract that turns
  the result of `persistentHash` into a `Field` to use as a map key or
  other identifier.  You should use the `Bytes<32>` value itself.
- Casts from byte vectors to foreign field types
  are also not injective ("one-to-one").

## How to Teach This

Explain how to teach users, including both new and experienced ones, how to use
the CoIP in their own work.

## Implementation

Discuss how the proposed change could be implemented.  What parts of the Compact
toolchain or the blockchain environment will need to be modified?  What are the
dependencies, if any?

Provide a link to a reference implementation, if there is one, and describe any
limitations.

### Runtime Support

Propose adding `serialize` and `deserialize` methods to descriptors.

## Rejected Ideas

Describe other ideas that were considered and explain why they were ultimately
not adopted.

## References

Link to relevant related work, such as research papers or similar features in
other contexts.

## Acknowledgements

Acknowledge non-authors who helped with the CoIP.

## Copyright

All contributions submitted in this CoIP must be licenced under the Apache
License, version 2.0.  Include the paragraph below.

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Footnotes

[^1]: As of this writing, casts from `Bytes<N>` to `Field` will fail if the byte vector represents
a value outside the range of `Field`.  This CoIP is proposing that we change that in the language
definition.

[^2]: The ledger serialization implemented by the Compact runtime will instead reduce the
serialized value via the native BLS12-381 field order (**wrong!**) and will therefore produce
values out of range.  The compiler therefore must ensure that `JubjubScalar` values are in range.
It does this by prohibiting arithmetic on `JubjubScalar`
and explicitly checking that the value is in range on casts to `JubjubScalar.`
