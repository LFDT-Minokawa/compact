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
the standard library event serialization format,
and ad hoc casts between some types and Compact byte vectors.

With the exception of some of the byte vector casts,
these formats are currently considered inmplementation details.
There is no official definition other than the implementation itself.
They are not versioned and can change between Compact releases.
The three formats do not necessarily agree with each other.

This CoIP proposes a single defined and versioned serialization format used to encode all Compact values.

## Motivation

Contract and DApp developers would like to use serialization for interoperability.
[High-level motivation: why might a DApp want to serialize/deserialize Compact data?]

There are three different binary serialization formats.

### The public ledger serialization format

In the Midnight Network, a contract's public ledger state is a binary-encoded `StateValue`
defined by the Midnight ledger's [on-chain runtime specification](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-10/spec/onchain-runtime.md#values).
In a `StateValue`, Compact values are held in individual `Cell`s that each contain a binary-encoded
*Field-Aligned Binary* (FAB) `AlignedValue`.
The FAB binary format is defined by the Midnight ledger's [Field-Aligned Binary specification](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-10/spec/field-aligned-binary.md).
The binary encoding of the on-chain runtime's `StateValue` and the ledger's FAB `AlignedValue` are determined by the ledger
and out of Compact's control.

However, the serialization of Compact typed values into FAB `AlignedValue`s is fully under Compact's control.
The Compact compiler and runtime can determine their own serialization format,
and the ledger will simply store and retrieve whatever serialized data it is given.

An `AlignedValue` is a sequence of pairs of `ValueAtom`s and `AlignmentAtoms`.
A `ValueAtom` is a blob of bytes, in JavaScript it is a `Uint8Array`.
An `AlignmentAtom` is a tag telling how to deserialize the `ValueAtom`.

The actual implementation of `AlignedValue` serialization and deserialization is in the Compact runtime,
using so-called *descriptor* objects.
Descriptors are JavaScript objects that have `toValue` and `alignment` function properties used for serialization as FAB `AlignedValue`s.
`toValue` converts a Compact value's JavaScript representation into a FAB `Value`
(an array of `ValueAtoms`, i.e., byte arrays).
`alignment` converts a Compact value's JavaScript representation into a FAB `Alignment`
(an array of alignment segments, but for Compact the segments are always alignment atoms).
Together a descriptor's `toValue` and `alignment` properties can be used to convert a Compact value to a FAB `AlignedValue`
by zipping together pairs of value atoms and alignment atoms.

Descriptors also have a `fromValue` function property used for deserialization.
`fromValue` converts a FAB `Value` (an array of value atoms) into the JavaScript representation of a Compact value,
using the descriptor's alignment.

The ledger serialization format is defined for all Compact values.
There is no specification other than the Compact runtime's implementation of descriptors.
It is not versioned, and there is no compatibility guarantee made between versions of the Compact runtime.

**Note:** the encoding of a contract's public ledger state into an on-chain runtime `StateValue` containing individual `Cell`s
is also fully under the Compact's control.
Specifying that encoding is outside the scope of this CoIP.

Compact code does not have explicit access to FAB `Value` serialization of Compact typed values.
Serialization and deserialization is implicit,
and happens whenever values are written into or read from the ledger.

### The event serialization format

The [CoIP-3 events](https://github.com/LFDT-Minokawa/compact/blob/main/coips/coip-0003.md) proposal,
which has been implemented,
adds generic `serialize<T,#N>` and `deserialize<T,#N>` circuits.
These are required to be defined at least for all the standard event types defined in CoIP-3.
They are additionally required by CoIP-3 to be able to be performed in circuit.

`serialize` and `deserialize` have been implemented for all Compact data types,
though there are some current exceptions (e.g., foreign curve points) where they are intended to be but are not yet implemented.
The implementation is by code generation in the compiler.
The `expand-serialize` pass in [compiler/analysis-passes/expand-serialize.ss](https://github.com/LFDT-Minokawa/compact/blob/main/compiler/analysis-passes/expand-serialize.ss)
generates an intermediate representation which is further compiled to JavaScript and ZKIR.
`serialize` produces a flat Compact byte vector (`Bytes<N>`) containing the serialized representation.

The serialization format is intended to be defined for all Compact values,
though CoIP-3 does not require this.
There is no specification other than the Compact compiler's code generation implementation.
It is not versioned, and there is no compatibility guarantee made between versions of Compact.
It is not required to be the same as the ledger serialization format, and it has a separate implementation.
Where it does agree with the ledger serialization format, that agreement is coincidental and not something that is guaranteed.

### Casting to and from byte vectors

The Compact language also allows type casts using the keyword `as`,
and some types support casting to and from Compact byte vectors (`Bytes<N>` objects).
These casts are ad hoc and not necessarily defined for all types.

The available casts are defined in the [Compact Reference](https://github.com/LFDT-Minokawa/compact/blob/main/doc/compact-reference.mdx).
There is no compatibility guarantee made between versions of Compact.

### A note on hashing

The Compact standard library provides hashing functions.
One of them is `persistentHash<T>`, which uses the SHA-256 algorithm.
In generated JavaScript code this works for all Compact types.
In ZK proofs, however, it **does not** work for Compact types that contain `Opaque`-typed subparts.
The reason is that `Opaque`-typed values are represented in circuit by a Poseidon hash of their value,
and a SHA-256 hash of the Poseidon hash of the value will not agree with a SHA-256 hash of the value itself.

The documentation for `persistentHash` reads:

> This function is a non-circuit-optimised compression function from arbitrary values to a 256-bit bytestring.
> It is guaranteed to persist between upgrades, and to consistently use the SHA-256 compression algorithm.
> It *should* be used to derive state data, and not for consistency checks where avoidable.

This is unclear, and developers have interpreted it as meaning that hashing the same Compact typed value will
always produce the same hash.
This is **not** what is actually guaranteed.
`persistentHash` is implemented by using the SHA-256 algorithm on the FAB serialization of the Compact data.
Since the serialization of Compact data into FAB is **not stable**,
the hash would change if Compact ever changed this serialization format.

### A note on the in-circuit representation of the ledger serialization

ZKIR circuits operate on ledger serialized values.
These are, however, represented as sequences of native field values and not as arrays of bytes.
The ledger's Field-Aligned Binary specification defines [a translation](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-8/spec/field-aligned-binary.md#field-representation)
from the binary encoding (an array of byte arrays) plus a sequence of alignment tags into the field representation.
This encoding interprets the alignment tags to determine how to encode each byte array as a sequence of fields.

JavaScript execution of a circuit collects the data necessary to construct a proof:
private inputs including circuit inputs,
and public inputs including Impact code that was executed.
The data collected by JavaScript execution is FAB encoded.
Before sending it to the proof server to construct a proof,
the Midnight.js library converts it to the field encoding by interpreting the alignment tags.

This field encoding is under the control of the Compact toolchain, because it emits the alignment tags.
However, ZKIR is a typed-language,
and so the field encoding of ZKIR typed values must agree with what the separate ZKIR implementation expects.
ZKIR has an implicit "decode" operation when it uses a field-encoded public or private input,
which converts that field encoding into a native ZKIR encoding.

It is important to note that this encoding is mostly irrelevant to the ledger.
The Compact compiler and the ZKIR implementation need to agree on it, but the ledger does not know what it is.
The exception is that the public inputs representing Impact code have a specific encoding as field elements
in-circuit that the ledger relies on.

## Specification

This CoIP proposes a specified binary serialization format for in-language event serialization.
The ledger serialization agrees with this format.
The format is designed to be efficient in circuit.
It agrees with Compact `Bytes` casts where they are available.
The format is versioned, with major and minor versions.

### Version bytes

The result of a call to `serialize` is a byte vector that starts with a pair of **major** and **minor** version bytes, followed by the raw serialized representation of the Compact object.

```
 Byte 0  Byte 1
+-------+-------+-----------------------------------+
| MAJOR | MINOR | RAW SERIALIZED REPRESENTATION ... |
+-------+-------+-----------------------------------+
```

The format defined in this CoIP is version 1.0, so a serialized object will start with the pair of bytes `[0x1,0x0]`.
The format currently implemented by the compiler, as of this time of writing this proposal, is version 0.0.
**This CoIP proposes adding the pair of bytes `[0x0,0x0]` to every object serialized by the current implementation.**

The minor version will be incremented whenever there is a **non-breaking** format change.
A change from version X to version Y is non-breaking if and only if:

1. the version Y serializer can serialize all Compact values that the version X serializer can,
   and produces the same raw serialized representation
2. the version Y deserializer can deserialize all byte vectors produced by the version X serializer.

So for instance, if X is 1.4 and Y is 1.5, then this implies that the version 1.5 deserializer will
be able to deserialize binary data tagged with version 1.4.
In fact, the version 1.5 deserializer will be able to deserialize all versions 1.x
where x is less than or equal to 5.

Practically speaking, for the 1.0 format defined in this proposal,
the only non-breaking changes will be to add serialization of new types.
That format needs a minor version increment, because the previous version's deserializer will not
be able to recognize the new types.

The major version will be incremented and the minor version will be set to 0 whenever there is a
**breaking** format change.

It is desirable to minimize the disruption of minor version changes,
such as providing support for deserializing older versions or a migration path.
However, this CoIP does not propose or mandate any specific approach.

### Raw serialized representations

The raw serialized representation is specified by the type-directed rules below.
The ledger serialization format is also defined below.
It will agree with the raw serialization representation in the following sense:
if the ledger alignment atoms are dropped so that there is a sequence of value atoms (`Uint8Array`s),
trailing zeros are added back using the alignment atoms,
and the value atoms are then concatenated,
then this produces exactly the same bytes as raw event serialization.

Raw serialization followed by raw deserialization of a value of type `T` is the identity on `T`,
producing an equal value.
Raw deserialization followed by raw serialization of a byte vector `Bytes<N>` is not necessarily
the identity on `Bytes<N>`, however if `Bytes<N>` was produced by serialization then
this **is** the identity on `Bytes<N>`.

#### Boolean

The raw serialization is a single-element byte vector.
`true` is serialized as `[1]` and `false` is serialized as `[0]`.
Raw deserialization fails on any other byte vector than the canonical ones `[0x0]` and `[0x1]`.

The ledger serialization has `{ tag: 'bytes', length: 1 }`,
and the serialization is the same except that the trailing zero is dropped as required by the ledger
(so `false` is serialized as an empty `Uint8Array`).
Ledger deserialization fails on any other `Uint8Array` than the canonical ones `[]` and `[0x1]`.

There is currently no in-language cast from `Boolean` to `Bytes<1>`.
There are transitive casts through `Field` and `Uint` types,
for instance if `b:Boolean` then `b as Uint<1> as Bytes<1>` will work.
It is also possible to simply write `Bytes [b ? 1 : 0]`.
Likewise, there are transitive casts from `Bytes<1>` to `Boolean`,
for instance if `b:Bytes<1>` then `b as Uint<1> as Boolean` will work.
It is also possible to simply write `assert(b[0] <= 1, "deserialization failure"), b[0] == 1`.

#### Uint<0..N>

The raw serialization is a byte vector `Bytes<M>`,
where `M` is the maximum of 1 and the number of bytes required to represent the maximum value `N-1`
(so `M` is at least 1).
The byte vector contains the little-endian encoding of the `Uint`'s value.
Raw deserialization fails if the little endian encoding represents an
unsigned integer greater than or equal to `N`.

The ledger serialization has `{ tag: 'bytes', length: M }` for the same `M` as above,
and the serialization is the little endian encoding of the value with trailing zeros dropped.
Ledger deserialization fails on a `Uint8Array` that represents an unsigned integer
greater than or equal to `N`.

There is a cast from `Uint<0..N>` to `Bytes<M>` that produces the raw serialized representation.
There is also a cast from `Bytes<M>` to `Uint<0..N>` that fails if the byte vector represents
the little-endian encoding of an unsigned integer greater than or equal to `N`.

Compact sized integer types `Uint<N>`behave exactly as the bounded unsigned integer type `Uint<0..M>` where `M` is `2^N`.
So for instance, `Uint<8>` is serialized as `Bytes<1>` and `Uint<16>` is serialized as (little-endian) `Bytes<2>`, etc.

#### Field

The raw serialization is a byte vector `Bytes<32>`.
The byte vector contains the little-endian encoding of the `Field`'s value.
Raw deserialization converts a byte vector to an unsigned integer,
and then reduces that number modulo the field order.

The ledger serialization has `{ tag: 'field' }`.
This will accept a `Uint8Array` up to length 32 and deserialize it as
an unsigned integer, reduced modulo the field order.

There is a cast from `Field` to `Bytes<32>` that obeys these rules[^1].

#### Bytes<N>

The raw serialization is the byte vector itself.

The ledger serialization has `{ tag: 'bytes', length: N }`.

#### Opaque<'Uint8Array'>

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
  
### The serialization format

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

#### Bytes<N>

These are Compact primitive types.

The ledger serialization is `Bytes<N>`, that is as a byte vector containing the bytes in order.
As usual, trailing zeros are dropped and recovered on deserialization using the length.
See `CompactTypeBytes`.

#### Opaque<'Uint8Array'>

This is a Compact primitive type.

The ledger serialization of a JavaScript `Uint8Array` is as a byte vector containing the bytes of the `Uint8Array`,
**without** trailing zeros dropped to be recovered on deserialization.
It has an alignment tag of `compress`, **not** `bytes`.
This means that the actual value (the full byte vector) is stored in the ledger,
but when converting to a sequence of native field values in circuit,
the Poseidon hashing algorithm is (currently) used to get a single native field value.
See `CompactTypeOpaqueUint8Array`.

#### Opaque<'string'>

This is a Compact primitive type.

The ledger serialization of a JavaScript `string` is as a byte vector containing the bytes of the UTF-8 encoding of the string,
**without** trailing zeros dropped to be recovered on deserialization.
It has an alignment tag of `compress`, **not** `bytes`.
This means that the actual value (the UTF-8 encoding of the string) is stored in the ledger,
but as for `Opaque<'Uint8Array'>` it is represented in circuit by a hash of the bytes.
See `CompactTypeOpaqueString`.

#### JubjubScalar

This is a Compact standard library type.

This is serialized in the ledger exactly as the type `Field`, with the alignment tag `field`.
Note that on deserialization, the value represented by the byte vector is (1) reduced by the native field modulus (**wrong!**),
and (2) allowed to be outside the range of `JubjubScalar`.
The compiler is therefore required to ensure that every ledger-serialized `JubjubScalar` is in the correct range.
It does this (currently) by prohibiting arithmetic on `JubjubScalar` and by checking the value is in range (and failing if not) on casts to `JubjubScalar`.
See `CompactTypeJubjubScalar`.

The event serialization format is `x as Bytes<32>`.

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

## Security Implications

Analyze the potential security implications of the proposed change.  Are there
any new attack vectors or vulnerabilities introduced?  How will they be
mitigated.

## How to Teach This

Explain how to teach users, including both new and experienced ones, how to use
the CoIP in their own work.

## Implementation

Discuss how the proposed change could be implemented.  What parts of the Compact
toolchain or the blockchain environment will need to be modified?  What are the
dependencies, if any?

Provide a link to a reference implementation, if there is one, and describe any
limitations.

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

