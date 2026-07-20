# Compact toolchain 0.33.0

- **Date**: 2026-07-21
- **Language version:** 0.25.0
- **Compact runtime version:** 0.18.0
- **Environment**: to-be-filled. For the full compatibility matrix, see the [release notes overview](https://docs.midnight.network/relnotes/overview)

## High-level summary

Version 0.33.0 of the Compact toolchain has to-be-filled.  You can update to this version with `compact update` (as long as it is the most recent version) or `compact update 0.33`.

## Audience

These release notes are intended for Compact smart contract developers and for DApp developers who use the Compact runtime.

## What changed

Compact now supports multi-contract systems. You can declare contract types, hold references to other deployed contracts as values, and call one contract's circuits from another. This is the first stage of support for contracts that work together as a system. Supporting cross-contract calls in the Compact runtime changes the shape of `CircuitContext` and the signature of `createCircuitContext`; these are breaking changes for DApp code that uses the runtime directly.

## New features

### Contract to contract calls

**Description**: Compact now supports building multiple smart contracts that work together as a system. Three new language features make this possible: contract types, references to other contracts as values, and calls from within a circuit to another contract's circuits. This is the first stage of support  for multi-contract systems.

#### Contract types

A `contract` declaration names a collection of circuit signatures — each with its parameter types, return type, and purity — that another contract may depend on:

```compact
contract Inner {
  circuit add(value: Field): Field;
}
```

A contract type is an ordinary program-defined type. It is not itself a contract; it describes the circuits a contract must export in order to be used through that type.

#### Asserting that a contract implements an type

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

First, the runtime must be able to read a callee's current ledger state. You supply this through a **contract state provider**: an object with a `getContractState(blockHash, address)` method, exported from the new `providers.ts` module as the `ContractStateProvider` interface. The runtime calls it to resolve each cross-contract callee.

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
