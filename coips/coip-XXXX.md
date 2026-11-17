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

[TODO: rewrite the document in light of the exceptions, like foreign field types.
We can just say that we want to make these agree where feasible.
Or we can say that raw serialization is computed "in terms of" the cast but is
not necessarily exactly the cast expression.]

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
whatever format version the program was compiled for.

**Reading version bytes.**
`deserialize<T, N>` fails unless its argument's version bytes are exactly the version of `T`.
It then deserializes the raw serialized representation that follows.

The **format version of a program** is the format version of the compiler that compiled it.
The version rules have the following consequences:

- The minor version of a serialized value depends only on its type,
  not on the format version of the program that serialized it.
- If two programs have format versions with the same major version, and if `T` is serializable
  in both programs;
  then `deserialize<T, N>` in either program accepts the bytes written by `serialize<T, N>`
  in the other.
  In particular, a program with an older format version can read values written by a program
  with a newer format version, provided that the type is serializable in the older version.
- `deserialize` in a program never reads a serialized value with a different major version.
  Supporting values written with an older major version,
  or migrating them, is outside the scope of this CoIP.
- Because the version of a type is fixed, the serialized value for a given Compact value is unique
  with respect to its major version.
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
so its size is the serialized size of the event's type.

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
they extend to any larger size argument.

All of these invariants hold both for JavaScript execution and in circuit.
Moreover, JavaScript execution and circuit execution of `serialize<T, N+2>` and `deserialize<T, N+2>` agree:
they produce the same results for the same arguments,
and `deserialize<T, N+2>` fails in one exactly when it fails in the other.

#### Round tripping

For all values `x` of type `T`:

```
deserialize<T, N+2>(serialize<T, N+2>(x)) == x
```

A serialized value `b` of type `T` is **accepted** if and only if `deserialize<T, N+2>(b)` does not fail.
An accepted serialized value `b` is **canonical** for `T` if and only if:

```
serialize<T, N+2>(deserialize<T, N+2>(b)) == b
```

A raw serialized representation `r` of type `T` is **canonical** if and only if
the serialized value consisting of the version bytes of `T` followed by `r`
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

This section specifies, for every serializable type `T`:

- the **raw serialized size** of `T`, a number of bytes determined by `T` alone;
- **raw serialization**, which maps each value of type `T` to its raw serialized representation,
  a byte vector of the raw serialized size of `T`;
- **raw deserialization**, which maps a byte vector of the raw serialized size of `T`
  either to a value of type `T` or to failure;
- the **ledger serialization** of `T`, the FAB alignment of `T`,
  and the value atoms that represent each value of type `T` in the ledger.

The rules are type-directed.
[Atomic types](#atomic-types) gives a rule for each atomic type,
and [Compound types](#compound-types) gives a rule for each compound type
in terms of the rules for their parts.

A type alias, structural or nominal, has the raw serialized representation,
raw deserialization, and ledger serialization of the type it is an alias for.

**Agreement with the ledger serialization.**
For a value `x` of type `T`,
the **padded ledger bytes** of `x` are obtained from its ledger serialization as follows:
each value atom is extended with trailing zero bytes to the width given by its alignment atom,
32 bytes for `{ tag: 'field' }` and `N` bytes for `{ tag: 'bytes', length: N }`,
and the extended value atoms are then concatenated in order.
The ledger serialization is required to agree with the raw serialized representation:

1. For every value `x` of type `T`,
   the padded ledger bytes of `x` are exactly the raw serialized representation of `x`.
2. For every ledger serialization that is a [valid FAB value](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-10/spec/field-aligned-binary.md#validity)
   for the alignment of `T`
   (in particular, whose non-`compress` value atoms have no trailing zero bytes)
   and is accepted by ledger deserialization,
   raw deserialization of its padded ledger bytes does not fail
   and produces the same value as ledger deserialization.

Ledger deserialization may reject ledger serializations whose padded ledger bytes raw deserialization would accept.
The rules for each atomic type say where it does so.

Some rules include Compact code that computes raw serialization or raw deserialization.
This code is illustrative, not normative.

#### Atomic types

**Boolean:** This is a built-in Compact type.

The raw serialized size is 1.
`false` is serialized as `[0x00]` and `true` is serialized as `[0x01]`.

Raw deserialization accepts `[0x00]`, producing `false`, and `[0x01]`, producing `true`.
It fails on any other byte vector.
There are no non-canonical raw serialized representations.

The ledger serialization has the alignment `{ tag: 'bytes', length: 1 }`.
`false` is represented by the empty value atom `[]` and `true` by the value atom `[0x01]`.

There are no casts between `Boolean` and `Bytes<1>`.
For `b: Boolean`, raw serialization is computed by the Compact code `Bytes[b ? 1 : 0]`,
or equivalently `b as Uint<1> as Bytes<1>`.
For `v: Bytes<1>`, raw deserialization is computed by `v as Uint<1> as Boolean`:
the cast from `Bytes<1>` to `Uint<1>` fails if `v[0]` is greater than 1.

**Uint<0..N>:** These are built-in Compact types.
Their values are the unsigned integers in the range `0` to `N-1`, where `N` is at least 1.

The raw serialized size is `M`,
the maximum of 1 and the number of bytes needed to represent `N-1`.
A value is serialized as the `M`-byte little-endian encoding of the unsigned integer.
Since `N-1` is at most the implementation's maximum `Uint` value, 256^31-1,
`M` is at most 31.

Raw deserialization interprets the byte vector as a little-endian unsigned integer.
It fails if that integer is greater than or equal to `N`, and otherwise produces it.
There are no non-canonical raw serialized representations.

The ledger serialization has the alignment `{ tag: 'bytes', length: M }`, for the same `M`.
A value is represented by its little-endian encoding with trailing zero bytes removed;
in particular, `0` is represented by the empty value atom `[]`.

The cast from `Uint<0..N>` to `Bytes<M>` computes raw serialization,
and the cast from `Bytes<M>` to `Uint<0..N>` computes raw deserialization.

**Uint<N>:** These are built-in Compact types.
`Uint<N>` is the same type as `Uint<0..2^N>`,
and so it has the same raw serialized representation, raw deserialization, ledger serialization, and casts.

Its raw serialized size is the maximum of 1 and `N/8` rounded up.
For example, `Uint<8>` has raw serialized size 1, `Uint<16>` has raw serialized size 2,
and `Uint<12>` has raw serialized size 2, with raw deserialization failing unless the top four bits are zero.
`Uint<0>` is `Uint<0..1>`; its raw serialized size is 1, and raw deserialization accepts only `[0x00]`.

**Field:** This is a built-in Compact type.
Its values are the integers `0` to `p-1`,
where `p` is the order of the native field of the proving system
(the scalar field of BLS12-381).

The raw serialized size is 32.
A value is serialized as the 32-byte little-endian encoding of the integer.

Raw deserialization interprets the byte vector as a little-endian unsigned integer,
and produces that integer reduced modulo `p`.
It never fails.
A raw serialized representation is canonical if and only if the integer it encodes is less than `p`.
Every value has at least one non-canonical raw serialized representation in addition to its canonical one,
since 2^256 is more than twice `p`.

The ledger serialization has the alignment `{ tag: 'field' }`.
A value is represented by its little-endian encoding with trailing zero bytes removed;
in particular, `0` is represented by the empty value atom `[]`.
Ledger deserialization is stricter than raw deserialization:
it rejects a value atom that encodes an integer greater than or equal to `p`.
Such value atoms are not canonical in the sense of the FAB specification's
[canonical field values](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-10/spec/field-aligned-binary.md#canonical-field-values),
which is a different notion from canonical raw serialized representations.

The cast from `Field` to `Bytes<32>` computes raw serialization.
The cast from `Bytes<32>` to `Field` computes raw deserialization[^1].

**Bytes<N>:** These are built-in Compact types, for any `N` from 0 up to the implementation's maximum byte-vector length.

The raw serialized size is `N`.
A value `b` is serialized as `b` itself.

Raw deserialization produces its argument unchanged.
It never fails.
There are no non-canonical raw serialized representations.

The ledger serialization has the alignment `{ tag: 'bytes', length: N }`.
A value is represented by the value atom consisting of its bytes with trailing zero bytes removed;
in particular, a value whose bytes are all zero, including the value of `Bytes<0>`,
is represented by the empty value atom `[]`.

No cast is needed:
in Compact, the raw serialized representation of `b: Bytes<N>` is `b` itself.

**JubjubScalar:** This is a Compact standard library type.
Its values are the integers `0` to `r-1`,
where `r` is the order of the scalar field of the Jubjub embedded curve.
Since `r` is less than both 2^252 and the native field order `p`,
every `JubjubScalar` value is also a `Field` value.

The raw serialized size is 32.
A value is serialized as the 32-byte little-endian encoding of the integer.

Raw deserialization interprets the byte vector as a little-endian unsigned integer,
and produces that integer reduced modulo `r`.
It never fails.
A raw serialized representation is canonical if and only if the integer it encodes is less than `r`.
Since 2^256 is more than 17 times `r`,
every value has at least 16 non-canonical raw serialized representations in addition to its canonical one.

The ledger serialization has the alignment `{ tag: 'field' }`.
A value is represented by its little-endian encoding with trailing zero bytes removed;
in particular, `0` is represented by the empty value atom `[]`.
Ledger deserialization is stricter than raw deserialization:
it rejects a value atom that encodes an integer greater than or equal to `r`.

There are no casts between `JubjubScalar` and `Bytes<32>`.
For `x: JubjubScalar`, raw serialization is computed by the Compact code `x as Field as Bytes<32>`.
For `v: Bytes<32>`, the Compact code `v as Field as JubjubScalar` computes raw deserialization
when `v` encodes an integer less than `p`, and in particular when `v` is canonical,
but not in general:
the cast to `Field` reduces modulo `p` before the cast to `JubjubScalar` reduces modulo `r`.

**Secp256k1Base, Secp256k1Scalar, Secp256r1Base, Secp256r1Scalar, Curve25519Base:**
These are Compact standard library types.
For each type, let `p` be the order of its field.
The values of the type are the integers `0` to `p-1`.

The raw serialized size is 32.
A value `v` is serialized as the 32-byte little-endian encoding of `(v - 1) mod p`.
In particular, `0` is serialized as the encoding of `p - 1`.

Raw deserialization interprets the byte vector as a little-endian unsigned integer `n`,
and produces `((n mod p) + 1) mod p`.
It never fails.
A raw serialized representation is canonical if and only if `n` is less than `p`.
A value `v` has a non-canonical raw serialized representation if and only if `((v - 1) mod p) + p` is less than `2^256`.
For `Curve25519Base` this holds for every value;
for the other types, whose moduli are close to `2^256`, it holds for only a small fraction of values.

The ledger serialization has the alignment
`{ tag: 'bytes', length: 24 }, { tag: 'bytes', length: 8 }`.
The two value atoms are the first 24 bytes and the last 8 bytes of the raw serialized representation,
each with trailing zero bytes removed.
Ledger deserialization is stricter than raw deserialization:
it rejects a ledger serialization whose padded ledger bytes encode an integer greater than or equal to `p`.

The casts between these types and `Bytes<32>` do not compute raw serialization and raw deserialization.
The cast from the type to `Bytes<32>` produces the 32-byte little-endian encoding of `v` itself,
and the cast from `Bytes<32>` to the type reduces the encoded integer modulo `p`.
The two are related by field arithmetic.
For `x` of one of these types `T` and `b: Bytes<32>`, with

    const one = Bytes[1, ...default<Bytes<31>>] as T;

raw serialization of `x` is computed by `(x - one) as Bytes<32>`,
and raw deserialization of `b` is computed by `(b as T) + one`.

**Curve25519Scalar:** This is a Compact standard library type.
Let `q` be the order of its field.
The values of the type are the integers `0` to `q-1`.
Since `q` is between `2^252` and `2^253`,
`(v - 1) mod q` is less than `2^253` for every value `v`.

The raw serialized size is 33.
For a value `v`, let `w` be `(v - 1) mod q`.
`v` is serialized as the 26-byte little-endian encoding of `w mod 2^204`,
followed by the 7-byte little-endian encoding of `w` divided by `2^204`, rounded down.
In particular, `0` is serialized using `w = q - 1`.

Raw deserialization interprets the first 26 bytes as a little-endian unsigned integer `l`,
and the last 7 bytes as a little-endian unsigned integer `h`.
It fails if `l` is greater than or equal to `2^204`,
or if `h` is greater than or equal to `2^49`.
Otherwise it produces `((n mod q) + 1) mod q`, where `n` is `l + h * 2^204`.
Unlike the other field types, raw deserialization of `Curve25519Scalar` can fail.
An accepted raw serialized representation is canonical if and only if `n` is less than `q`.
A value `v` has a non-canonical raw serialized representation if and only if `((v - 1) mod q) + q` is less than `2^253`,
which holds for all but a small fraction of values.

The ledger serialization has the alignment
`{ tag: 'bytes', length: 26 }, { tag: 'bytes', length: 7 }`.
The two value atoms are the first 26 bytes and the last 7 bytes of the raw serialized representation,
each with trailing zero bytes removed.
Ledger deserialization is stricter than raw deserialization:
it rejects a ledger serialization whose padded ledger bytes are not accepted by raw deserialization,
or encode an `n` greater than or equal to `q`.

The casts between `Curve25519Scalar` and `Bytes<32>`, and the cast from `Bytes<64>` to `Curve25519Scalar`,
do not compute raw serialization and raw deserialization.
The cast from `Curve25519Scalar` to `Bytes<32>` produces the 32-byte little-endian encoding of `v` itself,
and the casts from `Bytes<32>` and `Bytes<64>` reduce the encoded integer modulo `q`.
For `r: Bytes<33>`, raw deserialization is computed by the Compact code:

```compact
const one = Bytes[1, ...default<Bytes<31>>] as Curve25519Scalar;
const l = slice<26>(r, 0) as Uint<204>;
const h = slice<7>(r, 26) as Uint<49>;
const n = (l as Field) + (h as Field) * 25711008708143844408671393477458601640355247900524685364822016; // 2^204
((n as Bytes<32>) as Curve25519Scalar) + one
```

There is no corresponding Compact code for raw serialization,
since Compact has no operation that splits an integer at bit 204.
Raw serialization of `x` is the unique canonical raw serialized representation
that raw deserialization maps to `x`.

**JubjubPoint:** This is a Compact standard library type.
Its values are the points of the prime-order subgroup of the Jubjub embedded curve,
each given by its affine coordinates `x` and `y`, which are `Field` values.
The identity point is `(0, 1)`.

The raw serialized size is 64.
A point is serialized as the raw serialized representation of `x` as a `Field`,
followed by that of `y` as a `Field`.

Raw deserialization applies the raw deserialization of `Field` to the first 32 bytes and to the last 32 bytes,
producing coordinates `x` and `y`.
It fails unless `(x, y)` is a point on the Jubjub curve that lies in the prime-order subgroup,
and otherwise produces that point.
An accepted raw serialized representation is canonical if and only if both of its parts are canonical as `Field` representations.

The ledger serialization has the alignment `{ tag: 'field' }, { tag: 'field' }`.
The two value atoms are the ledger serializations of `x` and `y` as `Field` values.
Ledger deserialization is stricter than raw deserialization exactly where that of `Field` is,
and also fails unless the resulting coordinates are those of a point in the prime-order subgroup.

This CoIP adds casts between `JubjubPoint` and `Bytes<32>`, which do not compute raw serialization and raw deserialization.
The cast to `Bytes<32>` produces the compressed encoding of the point:
the 32-byte little-endian encoding of `y`,
with the least significant bit of `x` stored in the most significant bit of the last byte.
The cast from `Bytes<32>` fails unless its argument is the compressed encoding of a point in the prime-order subgroup,
and otherwise produces that point.
In particular, it fails if the encoded `y` is not less than the field order,
or if `x` would be 0 and the most significant bit of the last byte is set.

**Secp256k1Point, Secp256r1Point:** These are Compact standard library types.
For each type, the values are the points of the secp256k1 or secp256r1 curve,
including the identity point.
A point other than the identity is given by its affine coordinates `x` and `y`,
which are `Secp256k1Base` or `Secp256r1Base` values respectively.
The identity point has no affine coordinates.

The raw serialized size is 96.
A point other than the identity is serialized as the raw serialized representation of `x`,
followed by that of `y`,
followed by the raw serialized representation of `0` as a `Field`.
The identity point is serialized as the raw serialized representation of `0` as the base field type, twice,
followed by the raw serialized representation of `1` as a `Field`.

Raw deserialization applies the raw deserialization of the base field type to the first 32 bytes and to the next 32 bytes,
producing `x` and `y`.
It interprets the last 32 bytes as a little-endian unsigned integer, the **identity flag**,
and fails unless the identity flag is 0 or 1.
If the identity flag is 1, it produces the identity point.
If the identity flag is 0, it fails unless `(x, y)` is a point on the curve,
and otherwise produces that point.
An accepted raw serialized representation is canonical if and only if both base field parts are canonical
and, when the identity flag is 1, both base field parts are the raw serialized representation of `0`.

The ledger serialization has the alignment of the base field type, twice, followed by `{ tag: 'field' }`.
The value atoms are the ledger serializations of the two base field parts,
followed by the ledger serialization of the identity flag as a `Field`.
Ledger deserialization is stricter than raw deserialization exactly where that of the base field type is,
and has the same requirements on the identity flag and on `(x, y)`.

This CoIP adds casts between these types and `Bytes<33>`, which do not compute raw serialization and raw deserialization.
The cast to `Bytes<33>` produces the SEC1 compressed encoding of a point other than the identity,
and 33 zero bytes for the identity point.
The cast from `Bytes<33>` produces the identity point from 33 zero bytes.
Otherwise it fails unless its argument is the SEC1 compressed encoding of a point on the curve,
with the encoded `x` less than the field order,
and produces that point.

**Curve25519Point:** This is a Compact standard library type.
Its values are the points of the prime-order subgroup of Curve25519 in its twisted Edwards form (the curve of Ed25519),
each given by its affine coordinates `x` and `y`, which are `Curve25519Base` values.
The identity point is `(0, 1)`.

The raw serialized size is 64.
A point is serialized as the raw serialized representation of `x`,
followed by that of `y`.

Raw deserialization applies the raw deserialization of `Curve25519Base` to the first 32 bytes and to the last 32 bytes,
producing coordinates `x` and `y`.
It fails unless `(x, y)` is a point on the curve that lies in the prime-order subgroup,
and otherwise produces that point.
An accepted raw serialized representation is canonical if and only if both of its parts are canonical as `Curve25519Base` representations.

The ledger serialization has the alignment of `Curve25519Base`, twice.
The value atoms are the ledger serializations of `x` and `y`.
Ledger deserialization is stricter than raw deserialization exactly where that of `Curve25519Base` is,
and also fails unless the resulting coordinates are those of a point in the prime-order subgroup.

This CoIP adds casts between `Curve25519Point` and `Bytes<32>`, which do not compute raw serialization and raw deserialization.
The cast to `Bytes<32>` produces the encoding of the point specified by RFC 8032.
The cast from `Bytes<32>` fails unless its argument is the canonical RFC 8032 encoding of a point in the prime-order subgroup,
and otherwise produces that point.
In particular, it fails if the encoded `y` is not less than the field order,
or if `x` would be 0 and the sign bit is set.

**Enumeration types:** These are program-defined Compact types.
For an enumeration type `E` with `N` elements,
the **index** of an element is its zero-based position in the declaration of `E`.
An enumeration type is serialized as the bounded unsigned integer type `Uint<0..N>`:
its raw serialized representation, raw deserialization, and ledger serialization
are those of `Uint<0..N>` applied to the index.

So the raw serialized size is `M`,
the maximum of 1 and the number of bytes needed to represent `N-1`,
and an element is serialized as the `M`-byte little-endian encoding of its index.
Raw deserialization fails if the encoded integer is greater than or equal to `N`,
and otherwise produces the element with that index.
There are no non-canonical raw serialized representations.
The ledger serialization has the alignment `{ tag: 'bytes', length: M }`,
and an element is represented by the little-endian encoding of its index with trailing zero bytes removed.

There are no casts between enumeration types and `Bytes<M>`.
For `e: E`, raw serialization is computed by the Compact code `e as Uint<0..N> as Bytes<M>`,
and for `b: Bytes<M>`, raw deserialization is computed by `b as Uint<0..N> as E`.

#### Compound types

The rules for compound types follow the same structure as the rules for atomic types.

**Tuple types `[T1, ..., Tn]`:** These are built-in Compact types, for any `n` including 0.

The raw serialized size is the sum of the raw serialized sizes of `T1`, ..., `Tn`;
in particular, the raw serialized size of `[]` is 0.
A value `[x1, ..., xn]` is serialized as the concatenation,
in order, of the raw serialized representations of `x1`, ..., `xn`.

Raw deserialization divides its argument into consecutive parts
whose sizes are the raw serialized sizes of `T1`, ..., `Tn`, in order,
and applies the raw deserialization of each `Ti` to the corresponding part.
It fails if and only if any of these fails,
and otherwise produces the tuple of the resulting values.
An accepted raw serialized representation is canonical if and only if every part is canonical.

The ledger serialization has the alignment formed by concatenating the alignments of `T1`, ..., `Tn`, in order.
A value is represented by the concatenation, in order, of the value atoms representing `x1`, ..., `xn`.
Ledger deserialization divides the value atoms in the same way,
and is stricter than raw deserialization exactly where the ledger deserialization of some `Ti` is.

For `x: [T1, ..., Tn]`, raw serialization can be computed in Compact element by element:
if `s1`, ..., `sn` compute the raw serializations of `x[0]`, ..., `x[n-1]`,
then `Bytes[...s1, ..., ...sn]` computes the raw serialization of `x`.
Likewise, for a raw serialized representation `r`,
raw deserialization can be computed by applying raw deserialization of each `Ti`
to `slice<Si>(r, Oi)`, where `Si` is the raw serialized size of `Ti`
and `Oi` is the sum of the raw serialized sizes of `T1`, ..., `T(i-1)`,
and building the tuple of the results.
This is possible whenever the raw serialization or raw deserialization of each element type can be computed in Compact.

**Vector types `Vector<N, T>`:** These are built-in Compact types.
`Vector<N, T>` is the same type as the tuple type `[T, ..., T]` with `N` occurrences of `T`,
and so it has the same raw serialized representation, raw deserialization, ledger serialization, and casts.
In particular, its raw serialized size is `N` times that of `T`,
and the raw serialized size of `Vector<0, T>` is 0.

**Structure types:** These are program-defined Compact types and standard library types.
A structure type whose fields, in declaration order, have types `T1`, ..., `Tn`
has the raw serialized representation, raw deserialization, and ledger serialization
of the tuple type `[T1, ..., Tn]`,
applied to the tuple of its field values in declaration order.
Field names are not represented.
A generic structure type is serialized according to its instantiation.

Raw serialization and raw deserialization can be computed in Compact field by field,
as for tuples, building the structure with a structure creation expression.

## Rationale

This proposal rests on four ideas.
The specification follows from them.

**The ledger serialization does not change.**
Existing contract state is stored in the ledger serialization,
and `persistentHash` and the other byte-oriented hashing functions currently hash it.
The inputs to ZKIR circuits are also determined by it:
values are passed to the proof server in the FAB field representation of their ledger serialization,
and ZKIR decodes each type from that representation.
Leaving the ledger serialization unchanged, and adopting it as the raw serialized representation,
means that are no changes to stored ledger values, existing hashes,
and the ZKIR implementation.
Where the event serialization format disagreed with the ledger serialization,
it is the event serialization format that changes.

**The standard library API is unchanged.**
`serialize<T, N>` and `deserialize<T, N>` keep their current signatures, including the size parameter.
Changing them was considered but left out of this CoIP to limit its scope.

**Serialization is efficient in circuit.**
Every serializable type has a raw serialized size fixed by the type,
so serialization and deserialization have a fixed shape in circuit.
The rules for each type are chosen so that they can be implemented with a short sequence of ZKIR instructions.
Where accepting non-canonical representations is cheaper in circuit than rejecting them,
as for the field types, raw deserialization accepts them.

**Casts between types and byte vectors match ZKIR where possible.**
For the field types and the curve point types,
casts to and from `Bytes` have the semantics of ZKIR's `to_bytes` and `from_bytes` instructions:
little-endian encodings for the field types,
and standard compressed encodings for the point types.
These casts can therefore be implemented directly in circuit.
Where these semantics differ from the raw serialized representation,
the rule for each type says how the two are related.

## Backwards Compatibility

The proposal makes several changes that break backwards compatibility.

**Programs that use `serialize`/`deserialize`.**
The serialized size of existing types grows by two, so calls to `serialize` and `deserialize`
likely need their size bounds to be changed.
Programs that had at least two bytes of padding in `serialize` or `deserialize` will still
compile but the version bytes shift the serialized representation by two
even if there were no other changes to the serialized representation.
Bytes serialized by the current implementation won't deserialize with this proposal due to the
missing version bytes.

**Changes to the standard-library serialized representation of existing types.**
Several existing types are proposed to be serialized differently.
There are the following breaking changes:

- `Uint<0..1>` (equivalently `Uint<0>`) and single-element enumeration types.
  Previously they were serialized as zero bytes, the proposal is that thier raw serialized representation
  is one byte.  Inside compound types, this shifts subsequent elements or fields.
- The non-`Curve25519Scalar` foreign fields.
  Previously they were little-endian encodings of their unsigned value,
  the proposal is to serialize `(v - 1) mod p` to match the ledger serialization.
- `Curve25519Scalar`.
  Previously it was a little-endian encoding of its unsigned value,
  the proposal is to match the somewhat complicated ledger encoding.
  Deserialization could not fail before, with the proposal it can if the structure is not correct.
- `Field` deserialization.
  Previously, representations of values greater than or equal to the field order failed,
  the proposal is that they are reduced modulo the field order.

There are also some non-breaking changes.

- `JubjubScalar` is serializable.
  Previously, it was not serializable due to a bug in the compiler.
- The four curve point types are serializable.
  Previously, serialization for them was unimplemented.

**`Bytes<M>` to `Field` casts.**
Previously these would fail for the encoding of out of range values.
With the proposal they will reduce modulo the field order.
For `M` < 32 nothing changes.
Code that relied on the failure as a range check will now succeed.

**The ledger and the Compact runtime.**
The ledger serialization itself is unchanged.
The proposal makes ledger deserialization stricter in two places:

- `JubjubScalar` ledger deserialization will reject values between `r` (the Jubjub scalar field modulus)
  and `p` (the native BLS12-381 field modulus).
  Previously they were allowed and resulted in values outside the `JubjubScalar` range.
  This was benign so long as the values were serialized into the ledger state by Compact code.
- The proposal requires the point types to be validated to lie on the curve when deserialized
  from the ledger.
  This can cause existing ledger state to fail to deserialize, if invalid curve points were
  written to it.

**Deployed contracts that use `serialize`/`deserialize`.**
The ZKIR representation of these circuits will change so their verifier keys will change
when recompiled.
This is a normal consequence of recompilation, but maintainers should be aware of it.

## Security Implications

**Casts from byte vectors to field types are not injective.**
This CoIP changes casts from `Bytes<M>` to `Field`, for `M` of 32 or more,
to reduce the encoded integer modulo the field order rather than fail.
Distinct byte vectors can therefore produce the same `Field` value,
where previously one of them would have caused a run-time error.
This affects, for example, a contract that casts the result of `persistentHash` to `Field`
to use as a map key or other identifier;
such a contract should use the `Bytes<32>` value itself.
Casts from byte vectors to the foreign field types were already not injective.

**Deserialized values can have more than one serialized form.**
Raw deserialization accepts non-canonical representations for the field types,
and `deserialize` ignores bytes beyond the serialized size.
A program that hashes, signs, or compares bytes it received,
rather than the value it deserialized from them,
can therefore accept two different byte vectors as representing the same value.
Such a program should hash or compare the deserialized value, or its re-serialization;
see [Deserialization and hashing](#deserialization-and-hashing).

**Hashes do not depend on types.**
`persistentHash` and the other byte-oriented hashing functions hash only the raw serialized representation,
so values of different types with the same representation have the same hash.
Programs that need hashes of different kinds of data to be distinct
must include a domain separator in the data being hashed.

**Deserialization no longer produces invalid values.**
Raw deserialization and ledger deserialization reject points that are not on the curve
(or, for `JubjubPoint` and `Curve25519Point`, not in the prime-order subgroup),
and ledger deserialization of `JubjubScalar` rejects values that are not less than the Jubjub scalar field order.
Previously, ledger deserialization in JavaScript could produce such values,
on which JavaScript and circuit execution could disagree.
Invalid points can still be introduced by other means,
which are outside the scope of this CoIP:
`constructJubjubPoint` does not validate its result,
and points returned by witnesses are not validated.

## How to Teach This

The central idea to teach is this:
the byte-oriented hash of a Compact value is the hash of its raw serialized representation.
For a value `x` of a serializable type `T` whose raw serialized size is `N`,
`persistentHash<T>(x)` is the SHA-256 hash of the `N` bytes `slice<N>(serialize<T, N+2>(x), 2)`,
and the same holds for `persistentCommit`, `keccak256`, and `sha512`.
Anyone who can produce the raw serialized representation of a value,
in Compact or in another language,
can therefore compute its hash.

Most Compact programmers will notice no other change:
the ledger serialization, the results of the byte-oriented hashing functions,
and the payloads of standard events are all unchanged.
The changes are visible to programmers who use `serialize` and `deserialize`,
who cast between field or point types and byte vectors,
or who decode Compact values outside Compact.

**For Compact programmers using `serialize` and `deserialize`.**
A serialized value now begins with two version bytes,
so its size is two more than the raw serialized size of its type,
and the size argument of `serialize` and `deserialize` must allow for this.
The raw serialized representation of `x: T` is `slice<N>(serialize<T, N+2>(x), 2)`,
where `N` is the raw serialized size of `T`,
and this is exactly what `persistentHash<T>(x)` hashes.
Code that hashes, signs, or compares serialized bytes received from elsewhere
should do so on the deserialized value, or on its re-serialization,
rather than on the received bytes.

**For Compact programmers using casts to and from byte vectors.**
Casts are not always the same as serialization.
For the foreign field types and the point types, casts to `Bytes` use the standard encodings of those types,
which differ from their raw serialized representations.
In particular, for a value `x` of one of the foreign field types,
`persistentHash<T>(x)` is not equal to `persistentHash<Bytes<32>>(x as Bytes<32>)`.
Casts from byte vectors to `Field` now reduce modulo the field order instead of failing.

**For implementers outside Compact.**
Indexers, wallets, and other tools that decode Compact values,
or that recompute hashes of them,
should implement the rules in [Raw serialized representations](#raw-serialized-representations).
Event payloads are raw serialized representations, without version bytes;
their format is identified by the event version.

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

[^1]: A cast from `Bytes<M>` to `Field` currently fails if the encoded integer is greater than or equal to `p`.
This CoIP changes such casts, for every `M`, to reduce the encoded integer modulo `p` instead.
For `M` less than 32 this makes no difference, since the encoded integer is always less than `p`.
For `M` equal to 32 it makes the cast agree with raw deserialization.
See [Backwards Compatibility](#backwards-compatibility) and [Security Implications](#security-implications).

[^2]: The ledger serialization implemented by the Compact runtime will instead reduce the
serialized value via the native BLS12-381 field order (**wrong!**) and will therefore produce
values out of range.  The compiler therefore must ensure that `JubjubScalar` values are in range.
It does this by prohibiting arithmetic on `JubjubScalar`
and explicitly checking that the value is in range on casts to `JubjubScalar.`
