# Compact toolchain 0.33.0

- **Date**: 2026-07-21
- **Language version:** 0.25.0
- **Compact runtime version:** 0.18.0
- **Environment**: to-be-filled. For the full compatibility matrix, see the [release notes overview](https://docs.midnight.network/relnotes/overview)

## High-level summary

Version 0.33.0 of the Compact toolchain is a major release.  It is the first version that supports Midnight ledger version 9.  This ledger version is incompatible with ledger version 8 currently deployed on Midnight Mainnet.

Ledger version 9 will be, but is not yet, deployed on Midnight Mainnet.  If you are building contracts to be deployed to the current (as of July 21) Midnight Mainnet, you should continue to use Compact toolchain 0.31.x.

You can update to version 0.33.0 using the Compact devtools.  `compact update` will update to the latest released version, and `compact update 0.33` will specifically update to the latest patch release of toolchain 0.33.  You can also switch back to toolchain version 0.31.x with `compact update 0.31`.

## Audience

These release notes are intended for Compact smart contract developers and for DApp developers who use the Compact runtime.

## What changed

In addition to the switch from Midnight ledger version 8 to version 9, this release has some major new features.

Compact now supports _cross-contract calls_.  You can declare contract types, use references to other deployed contracts as values, and call one contract's circuits from another.  This is the first stage of support for multi-contract systems: contracts that work together as a system.  Supporting cross-contract calls in the Compact runtime changes the type `CircuitContext` and the signature of `createCircuitContext`; these are **breaking changes** for DApp code that uses the runtime directly.

Compact now supports _events_.  [More here].

Compact toolchain 0.33 has support for a new ZKIR circuit format, ZKIR version 3.  This format is selected by passing the flag `--feature-zkir-v3` to the compact compiler (`compact compile --feature-zkir-v3`).  ZKIR version 3 has new suppport for cryptographic features that are not available in ZKIR version 2: Keccak-256 hashing, secp256k1 curve points and base and scalar fields, and ECDSA signature verification in the Compact standard library.

## New features

### Cross-contract calls

**Description**: Compact now supports building multiple smart contracts that work together as a system. Three new language features make this possible: contract types, references to other contracts as values, and calls from within a circuit to another contract's circuits. This is the first stage of support for multi-contract systems.

#### Contract types

A `contract` declaration names a collection of circuit signatures — each with its parameter types, return type, and purity — that another contract may depend on:

```compact
contract Inner {
  circuit add(value: Field): Field;
}
```

A contract type is an ordinary program-defined type. It is not itself a contract; it describes the circuits a contract must export in order to be used through that type.

#### Asserting that a contract implements a type

A contract can assert that it implements a contract type with a top-level `contract implements` declaration:

```compact
contract implements Inner;
```

A contract implements a type whenever it exports a matching circuit — same parameter types, return type, and purity — for every circuit the type declares. When the assertion is present, the compiler verifies it and rejects the contract at compile time if any required circuit is missing or has a non-matching signature. The assertion is optional: it is a compile-time check you opt into, not a prerequisite for a contract to be used as a value.

#### Contract references

Because a contract type is an ordinary type, a value of that type — a *contract reference* — may be used wherever other values can: as a circuit or witness parameter, as a struct field, or as the element or value type of a ledger collection:

```compact
export ledger inner: Inner;
export ledger registry: Map<Field, Inner>;
export ledger queue: List<Inner>;
```

A reference is introduced from application code by passing a deployed contract's address where a value of the contract type is expected. For example, a constructor can take a reference and store it:

```compact
constructor(i: Inner) {
  inner = disclose(i);
}
```

#### Cross-contract calls

Given a contract reference, a circuit can call any circuit named in the reference's type using ordinary method-call syntax, `reference.circuit(args...)`:

```compact
export circuit add(value: Field): Field {
  return inner.add(disclose(value));
}
```

The called circuit runs in the callee contract, against the callee's own ledger state, and its result is returned to the caller.

#### Runtime support for cross-contract calls

DApp developers who use the Compact runtime should be aware of two things when a contract makes cross-contract calls.

First, the runtime must be able to read the called contract's current ledger state. This is supplied through a **contract state provider**: an object with a `getContractState(blockHash, address)` method, exported from the new `providers.ts` module as the `ContractStateProvider` interface. The runtime calls it to resolve each cross-contract callee.

Second, every cross-contract call is checked by a set of dynamic safety guards. A call is rejected (throwing at runtime) when:

1. it would re-enter a contract already executing on the call stack (for example `A → A`, or `A → B → A`). The re-entrancy guard is enabled by default;
2. the deployed verifier key for the called circuit does not match the type the compiler resolved — this throws the new `ContractInterfaceMismatchError` and prevents a call whose target address points at a different contract than expected;
3. the callee's actual purity disagrees with the type's declaration;
4. the callee invokes a witness — cross-contract callees must have no private state; or
5. the target is the default (all zero) contract address.

Restrictions (1-4) will be relaxed as support for those features is added in future releases.

### Emitting events

**Description**: There is a new expression form `emit(e)` that takes a standard event and appends the emitted  events, in order of evaluation, to the enclosing exported circuit's context, where it can be read from TypeScript via the `events` field of `CircuitContext`.

The Compact standard library defines the standard event types. 

The type of every `emit` form is `[]`.

Evaluation of `emit(e)` proceeds by evaluating `e`, computing its canonical byte encoding, and emitting a structured `VersionedLogItem` with three fields:
- `version`, the event format version (presently `1`),
- `eventType`, identifying the declared event type by its tag, and
- `data`, containing the byte encoding.

The canonical byte encoding of an event is created via the equivalent of `serialize<T, #n>`. A generic `serialize` circuit is defined in the Compact standard library along with a `deserialize` counterpart.

### The `JubjubScalar` type

**Description**: Previously, the standard library circuits `ecMul` and `ecMulGenerator` took a native (BLS12-381) `Field` value as their second and first argument respectively.  The native curve is Jubjub and these circuit arguments should be values in the Jubjub scalar field.  The Jubjub scalar field is a prime field with a smaller field modulus than the native field.  There was therefore a slight ambiguity when a value was passed that exceeded the Jubjub scalar field modulus.

Compact toolchain 0.33 introduces a builtin type `JubjubScalar`.  The standard library circuits `ecMul` and `ecMulGenerator` now take a `JubjubScalar` value as their second and first argument respectively.  There is a cast from `Field` to `JubjubScalar` and from `JubjubScalar` to `Field`.  The cast from `Field` to `JubjubScalar` will not fail for values out of range, but will instead reduce the `Field` value modulo the Jubjub scalar modulus.  The cast from `JubjubScalar` to `Field` will not fail because the maximum `Field` value is larger than the maximum `JubjubScalar` value.  Do note that round tripping by casting from `Field` to `JubjubScalar` and back to `Field` will possibly give a different value than the original one.

There is likewise a cast from all `Uint` types to `JubjubScalar`, this cast behaves the same as the cast from `Field` to `JubjubScalar`.  There is also a cast from `JubjubScalar` to all `Uint` types.  This cast will fail at runtime if the actual Jubjub scalar value is too large for the target `Uint` type.

`default<JubjubScalar>` is zero.  Arithmetic is not supported for the `JubjubScalar` type.  Equals and not-equals comparisons are supported, but other relational comparisons are not supported.

The Compact runtime exports new `bigint` constants `JUBJUB_SCALAR_MODULUS` and `MAX_JUBJUB_SCALAR`.

### The secp256k1 curve

**Description**: Compact now has support for the secp256k1 curve used in Bitcoin and Ethereum signatures.  There is a standard library type `Secp256k1Point` representing curve points.  There are standard library circuits `secp256k1PointX` and `secp2561kPointY` to extract the affine X- and Y-coordinates of a value of type `Secp256k1Point`.  There is no way in Compact to explicitly construct secp256k1 points, but note that they can be obtained from witnesses and passed as circuit inputs.

`default<Secp256k1Point>` is the additive identity point, a point `b` such that `ecAdd(a, b)` equals `a` for any point `a`.  Equals and not-equals comparisons are supported for secp256k1 points.

The elliptic curve operations `ecAdd`, `ecMul`, and `ecMulGenerator` are overloaded to work with secp256k1 types.

There are a pair of new builtin field types, `Secp256k1Base` and `Secp256k1Scalar`.  The X- and Y-coordinates of a `Secp256k1Point` have type `Secp256k1Base`.  The field arguments to `ecMul` and `ecMulGenerator` for `Secp256k1Point` have type `Secp256k1Scalar`.  The default values of both of these fields are zero.  Arithmetic is supported via standard library circuits (**not** the binary arithmetic operators).  `add` performs addition, `mul` performs multiplication, `neg` is the additive inverse (a value `b` such that `add(a, b)` is `a` for all field values `a`), and `inv` is the multiplicative inverse (a value `b` such that `mul(a, b)` is `a` for all field values `b`).  Equals and not-equals comparisons are supported for these types, but other relational comparisons are not supported.

There are casts to and from both secp256k1 fields and `Bytes<32>`.  The `Bytes<32>` representation of a secp256k1 field value is little-endian.  The casts targeting `Bytes<32>` cannot fail (the maximum values of both fields fit in 32 bytes).  The casts from `Bytes<32>` will fail if the resulting value would exceed the target type's maximum value.  Therefore, round-tripping through `Bytes<32>` always succeeds and gives the same value; round tripping through a secp256k1 field type will only work if the original `Bytes<32>` value is a valid value for that field type.

This feature is **only available with the new ZKIR v3 backend**.  To enable it, pass the flag `--feature-zkir-v3` when invoking the compiler.  Note that you will need a proof server release that supports ZKIR version 3.0 construct proofs involving this feature.

The Compact runtime has types and functions to manipulate values of the secp256k1 types.

### ECDSA signature verification

**Description**: Compact circuits can now verify ECDSA signatures in circuit.  There is a standard library struct type `Secp256k1EcdsaSignature` and a circuit `secp256k1EcdsaVerify`.  `secp256k1EcdsaVerify` takes a `Bytes<32>` message hash, a `secp256k1EcdsaSignature` signature containing a pair of `Secp256k1Scalar`s, and a `Secp256k1Point` public key.

It returns a boolean value telling whether the verification succeeded.  If you want to ensure that a signature verifies in Compact, you should `assert` that the result of `secp256k1EcdsaVerify` is is true.

Note that there are JavaScript utilities for working with signatures (such as recovering a public key from a message hash and a signature) in the Noble curves JS package (https://www.npmjs.com/package/@noble/secp256k1).  This is the library that the Compact runtime uses.

Also note that `secp256k1EcdsaVerify` will verify high-s signatures, where the `s` component of a `Secp256k1EcdsaSignature { r, s }`

## Improvements

## Deprecations

## Breaking changes

### `CircuitContext` is restructured to model a call tree

To support cross-contract calls, the Compact runtime's `CircuitContext` now models an entire call tree rather than a single contract execution. This is a **breaking change** for DApp code that constructs or reads a `CircuitContext` directly.

Per-call state moves into a new `callContext` member. Fields that were previously at the top level — `currentPrivateState`, `currentZswapLocalState`, and `currentQueryContext` — are now reached through `circuitContext.callContext`. The context also gains call-tree-wide members, including per-contract-address maps of query contexts and gas costs, the retained deployed states of resolved callees, and a depth-first trace of the proof data for the root circuit and every sub-call.

### `createCircuitContext` has a new signature

`createCircuitContext` gains a leading `circuitId` argument and new trailing `stateProvider`, `parentBlockHash`, and `reentrancyGuard` arguments. The new trailing arguments are only needed by circuits that make cross-contract calls; the re-entrancy guard is enabled by default, and you can pass `reentrancyGuard: false` to opt out (for example, in tests that deliberately exercise recursion). This is a **breaking change** to the runtime API.

### `CircuitResults` no longer carries `proofData`

`CircuitResults` no longer has a `proofData` field. The proof data for each circuit run — the root circuit and every sub-call — is now collected in the proof-data trace on the context. This is a **breaking change** for code that read `proofData` from a circuit's results.

## Fixed defect list
