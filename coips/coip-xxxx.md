---
CoIP: X
Title: Log Expression for Structured Event Emission
Authors:
  - Dominik Zajkowski (dzajkowski)
Status: Draft
Category: Language
Created: 2026-05-15
Requires: none
Replaces: none
---

<!--
This file is part of Compact.

Copyright (C) 2026 Minokawa project contributors
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

Compact has no mechanism for contracts to emit structured notifications about activity.

This CoIP adds a `emit` expression that accepts a struct instance.
`log` is a disclosure site, the compiler enforces that all fields are already disclosed, same as ledger writes and circuit returns.
The expression returns the struct passed to it.

Phase 1 restricts `log` to the [standard event structs](#appendix-a-standard-events) shipped as part of the Compact standard library.

## Motivation

Compact contracts can modify ledger fields and return values from circuits, but have no way to signal what happened during execution.
The only way to observe contract activity is to diff state between transactions.
This requires knowledge of the contract's internal state structure, knowledge that is fragile and breaks when the contract evolves.
Events still require knowledge of the contract's implementation, but provide an interface that can be kept stable more easily.

Event emission is a well-established pattern in smart contract languages (Solidity, Ink!, Sway), proven useful over years of adoption.
Compact's privacy-preserving design means a direct copy is not appropriate.
This CoIP focuses on emission of already-disclosed data, a practical first step that improves the developer experience without introducing new disclosure concerns.

## Specification

### The `log` expression

`log` is a new expression that accepts a struct instance.

```compact
log(<struct instance>)
```

**Semantics:**
- `log` is a disclosure site — all field values must be already disclosed.
- The expression returns the struct passed to it.
- Multiple `log` calls per circuit are allowed.
- Inside conditional branches, the log executes only if the branch is taken.

**Example:**

```compact
circuit spend(...): [] {
    // ... spend logic ...
    log(ShieldedSpend { nullifier: disclose(old_nullifier) });
}
```

### Phase 1 restrictions

`log` accepts only structs from the [standard events](#appendix-a-standard-events) package shipped in the Compact standard library.
The compiler rejects `log` calls with structs not in this set.
A single log event must not exceed 1 KB serialized.
These restrictions can be loosened in future CoIPs.

### Standard events package

The standard library ships a set of predefined event structs for common Midnight operations.
See [Appendix A: Standard Events](#appendix-a-standard-events) for the full list of definitions.

## Rationale

**Why `log` instead of `emit`?**

`emit` implies a runtime action with guaranteed delivery.
`log` is more neutral — it records data, and what happens downstream is outside the language's scope.

**Why disclosure enforcement?**

This CoIP scopes `log` to already-disclosed values.
Emitting private data is a different problem with different tradeoffs (encryption, topic-based filtering, recipient key management).
Limiting to disclosed data keeps the first iteration simple and avoids new privacy concerns.

**Why restrict to standard event structs in Phase 1?**

A fixed set of known structs lets downstream tooling ship with built-in support.
Unrestricted arbitrary structs require schema discovery mechanisms that are not yet in place.
The `Misc` escape hatch covers custom use cases without blocking adoption.

**Why return the struct?**

Returning the struct promotes using standard event structs as data carriers — a value can be logged and used in the same expression.
This encourages adoption of the standard events as a natural part of data flow rather than a separate bookkeeping step.

## Backwards Compatibility

`log` is a new keyword.
If an existing contract uses `log` as an identifier, it will cause a compilation error.
No other breaking changes to existing language constructs, syntax, or semantics.

## Security Implications

`log` is a disclosure site scoped to already-disclosed values.
No new private data leakage is introduced.

A contract can emit misleading events — `log` records the contract author's claim, not independently verifiable facts.
This is inherent to any event system.

## How to Teach This

For new users: `log` works like `print` — it records a value for external observers without affecting contract state.
Unlike `print`, it requires all values to be disclosed.

For experienced Compact users: `log` is another disclosure site, same rules as ledger writes and circuit returns.
It compiles to a struct emission that downstream consumers can subscribe to.

```compact
circuit spend(...): [] {
    // ... spend logic ...
    log(ShieldedSpend { nullifier: disclose(old_nullifier) });
}
```

## Implementation

**Parser:** Add `log` as a keyword. Parse `log(<struct instance>)` as an expression.

**Type checker:** Verify the struct is in the standard events set. Verify all fields satisfy disclosure rules. Infer return type as the struct type.

**Code generation:** Map standard event structs to their corresponding `LogEventType` variant. Emit the serialized struct as the payload.

**Standard library:** Add the standard events package with predefined struct definitions.

**compact-runtime:** Capture log events during local circuit execution.

## Rejected Ideas

**`emit` keyword:** Implies guaranteed delivery to an external consumer. `log` is more accurate — the language records data, downstream interpretation is not its concern.

**Arbitrary struct emission in Phase 1:** Requires schema discovery mechanisms (TypeScript descriptors, IR-based field resolution) that are not yet in place.
Restricting to a known set enables built-in tooling support now; future CoIPs can loosen this.

**Separate `event` type declaration:** Early drafts proposed a dedicated `event` keyword distinct from `struct`.
This adds language surface for no semantic benefit — an event is a struct that gets logged.

## Open Questions

- What is the impact of `log` on the ZK circuit model? Adding `log` calls changes a circuit's public outputs. Does this have implications for proof generation or verification beyond additional instructions?

## References

- [MIP-xxxx: Public Contract Log Emission for Compact Smart Contracts](https://github.com/midnightntwrk/midnight-improvement-proposals/pull/107)
- [Ethereum Logs and Events](https://docs.soliditylang.org/en/latest/abi-spec.html#events)

## Acknowledgements

Great thanks for review and input to:
  - Parisa Ataei (@pataei)
  - Kent Dybvig (@dybvig)
  - Thomas Kerber (@tkerber)
  - Andrzej Kopeć (@kapke)

## Copyright

All contributions submitted in this CoIP must be licensed under the Apache License, version 2.0.

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Appendix A: Standard Events

### Shielded Coin Events

```compact
struct ShieldedSpend {
    nullifier: Bytes<32>          // hint: indexed
}

struct ShieldedReceive {
    commitment: Bytes<32>,        // hint: indexed
    ciphertext: Maybe<Bytes<512>>,// hint: indexed
    contractAddress: Maybe<ContractAddress>
}

struct ShieldedMint {
    commitment: Bytes<32>,       // hint: indexed
    domainSep: Bytes<32>,        // hint: indexed
    amount: Maybe<Uint<128>>
}

struct ShieldedBurn {
    nullifier: Bytes<32>,        // hint: indexed
    amount: Maybe<Uint<128>>
}
```

### Unshielded Token Events

```compact
struct UnshieldedSpend {
    sender: Either<ZswapCoinPublicKey, ContractAddress>,     // hint: indexed
    domainSep: Bytes<32>,        // hint: indexed
    tokenType: Bytes<32>,        // hint: indexed
    amount: Uint<128>
}

struct UnshieldedReceive {
    recipient: Either<ZswapCoinPublicKey, ContractAddress>,  // hint: indexed
    domainSep: Bytes<32>,        // hint: indexed
    tokenType: Bytes<32>,        // hint: indexed
    amount: Uint<128>
}

struct UnshieldedMint {
    domainSep: Bytes<32>,        // hint: indexed
    tokenType: Bytes<32>,        // hint: indexed
    amount: Uint<128>
}

struct UnshieldedBurn {
    sender: Either<ZswapCoinPublicKey, ContractAddress>,     // hint: indexed
    tokenType: Bytes<32>,        // hint: indexed
    amount: Uint<128>
}
```

### Lifecycle Events

```compact
struct Paused {}
struct Unpaused {}
```

### Misc

```compact
struct Misc {
    name: Bytes<32>,
    payload: Bytes<256>
}
```

The indexer stores the raw payload but has no built-in schema knowledge for `Misc`.
Any indexing is entirely on the end user.

# Appendix B. Zerocash Example

The `spend` circuit from the zerocash example contract (`examples/zerocash.compact`) illustrates the before/after.

## Before

```compact
ledger nullifiers: Set<nullifier>;
ledger commitments: HistoricMerkleTree<32, commitment>;
ledger ciphertexts: Opaque<"Uint8Array">;

circuit spend(dest_public_key: public_key, input_coin: coin_info): [] {
  const source_secret_key = private$zk_secret_key();
  const old_nullifier = derive_nullifier(input_coin, source_secret_key);
  assert(!nullifiers.member(old_nullifier), "spend: Coin already spent");
  nullifiers.insert(old_nullifier);
  const source_public_key = derive_zk_public_key(source_secret_key);
  const old_commitment = commitment_from_coin_info(input_coin, source_public_key);
  const commitment_path = context$path_of(old_commitment);
  assert(commitments.checkRoot(disclose(merkleTreePathRoot<32, commitment>(commitment_path))) &&
         old_commitment == commitment_path.leaf,
         "spend: Illegal state: merkle path not recognized by public state");
  const fresh_coin_info = context$new_coin_info();
  const fresh_commitment = commitment_from_coin_info(fresh_coin_info, dest_public_key.zk);
  commitments.insert(fresh_commitment);
  const ciphertext = disclose(context$encrypt(dest_public_key.encryption, fresh_coin_info));
  ciphertexts.write(ciphertext);
  private$remove_coin(input_coin);
}
```

The values already public on-chain:
- **`old_nullifier`** — disclosed hash, inserted into the public `nullifiers` Set.
- **`fresh_commitment`** — disclosed hash, inserted into the public `commitments` MerkleTree.
- **`ciphertext`** — encrypted coin info, written to the public `ciphertexts` ledger field.

To detect spends, a consumer must poll the full state, diff Merklized structures, and trial-decrypt every ciphertext.

## After

```compact
circuit spend(dest_public_key: public_key, input_coin: coin_info): [] {
  // ... existing logic unchanged ...

  log(ShieldedSpend { nullifier: disclose(old_nullifier) });
}
```

`old_nullifier` is already disclosed.
The `log` adds no new information — the data is already available on-chain.
The difference is that the contract is now explicit about which state changes are important, and consumers can discover them without knowledge of the contract's internal state layout.
