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

There are three different ways to serialize and deserialize Compact values as arrays of bytes in the Midnight Network:
the public ledger encoding,
the in-language serialization format,
and ad hoc casts between some types and Compact `Bytes<N>` byte vector values.

All three of these formats are currently considered implementation details,
with no official definition other then the implementation itself.
The are not versioned, and could change between Compact toolchain releases.
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
and out of the Compact toolchain's control.

However, the serialization of Compact typed values into FAB `AlignedValue`s is fully under the Compact toolchain's control.
The toolchain can determing its own serialization format, and the ledger will store whatever serialized data it is given.
The actual implementation of `AlignedValue` serialization and deserialization is in the Compact runtime,
using so-called *descriptor* objects.

Descriptors are JavaScript objects that have `toValue` and `alignment` function properties used for serialization.
`toValue` converts a Compact value's JavaScript representation into a FAB `Value`
(an array of value atoms, i.e., byte arrays).
`alignment` converts a Compact value's JavaScript representation into a FAB `Alignment`
(an array of alignment segments, but the segments are always alignment atoms).
Together a descriptor's `toValue` and `alignment` properties can be used to convert a Compact value to a FAB `AlignedValue`
by zipping together pairs of value atoms and alignment atoms.

Descriptors also have a `fromValue` function property used for deserialization.
The alignment atoms are not used during deserialization.
They exist as instructions to define an intended conversion from the binary value atoms to
sequences of the Midnight ledger's native field values.
`fromValue` converts a FAB `Value` (an array of value atoms) into the JavaScript representation of a Compact value.

The ledger serialization format is defined for all Compact values.
There is no specification other than the Compact runtime's implementation of descriptors.
It is not versioned, and there is no compatibility guarantee made between versions of the Compact runtime.

**Note:** the encoding of a contract's public ledger state into an on-chain runtime `StateValue` containing individual `Cell`s
is also fully under the Compact toolchain's control.
Specifying that encoding is outside the scope of this CoIP.

Compact code does not have explicit access to FAB `Value` serialization of Compact typed values.

### The event serialization format

The [CoIP-3 events](https://github.com/LFDT-Minokawa/compact/blob/main/coips/coip-0003.md) proposal,
which has been implemented,
adds generic `serialize<T,#N>` and `deserialize<T,#N>` circuits.
These are required to be defined at least for all the standard event types defined in CoIP-3.
They are additionally required to be performed in circuit.

`serialize` and `deserialize` have been implemented for all Compact data types,
though there are some current exceptions (e.g., foreign curve points) where they are intended to be but are not yet implemented.
The implementation is by code generation in the compiler.
The `expand-serialize` pass in [compiler/analysis-passes/expand-serialize.ss](https://github.com/LFDT-Minokawa/compact/blob/main/compiler/analysis-passes/expand-serialize.ss)
generates an intermediate representation which is further compiled to JavaScript and ZKIR.
`serialize` produces a flat Compact byte vector (`Bytes<N>`) containing the serialized representation.

The serialization format is intended to be defined for all Compact values, but CoIP-3 does not require this.
There is no specification other than the Compact compiler's code generation implementation.
It is not versioned, and there is no compatibility guarantee made between versions of the Compact toolchain.
It is not required to be the same as the ledger serialization format, and it has a separate implementation.
Where it does agree with the ledger serialization format, that agreement is coincidental and not something that is guaranteed.

### Casting to and from byte vectors

The Compact language also allows type casts using the keyword `as`,
and some types support casting to and from Compact byte vectors (`Bytes<N>` objects).
These casts are ad hoc and not necessarily defined for all types.

The available casts are defined in the [Compact Reference](https://github.com/LFDT-Minokawa/compact/blob/main/doc/compact-reference.mdx).
The serialization format is not specified and is an implementation detail.
There is no compatibility guarantee made between versions of the Compact toolchain.

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
the hash would change if the Compact toolchain ever changed this serialization format.

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

If necessary, include footnotes in the CoIP text using GitHub's footnote
syntax[^1].  Keep the footnote heading at the bottom of the document.

[^1]: See the [GitHub Markdown guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#footnotes).

