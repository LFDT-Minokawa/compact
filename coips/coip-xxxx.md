---
CoIP: xxxx
Title: A language-agnostic representation of a compiled contract in contract-info.json
Authors:
  - Rodrigo Quelhas (RomarQ)
Status: Draft
Category: Tooling
Created: 2026-07-16
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

The Compact compiler emits the off-chain half of a compiled contract only as generated TypeScript, so only TypeScript SDKs can use a contract. This CoIP adds a language-agnostic description of each circuit's body to `contract-info.json`, the machine-readable file the compiler already writes: a typed body per circuit (`ir`), the bodies of the helper circuits they call (`helpers`), and a format version. The bodies serialize from the compiler's analyzed form (`Lnodisclose`), so the whole compiler change stays inside the pass that already writes the file. With these, an SDK in any language can execute circuits locally with a small interpreter, instead of embedding a JavaScript engine. A reference emitter and a reference consumer (in Rust) already run the approach end to end. The emitter serializes the analyzed form; re-targeting the consumer to it is the main remaining work. This draft describes the design shape, to start the discussion.

## Motivation

The only first-class way to use a compiled contract today is the generated TypeScript plus `@midnight-ntwrk/compact-runtime`. An SDK in another language must embed a JavaScript engine, or reimplement the TypeScript backend and track compiler internals release after release. Both are workarounds for the same gap: no language-neutral artifact describes what a circuit does off-chain.

Off-chain execution is half of every contract call. Before an SDK can prove anything, it must run the circuit body locally: apply the ledger operations to the contract state, call witnesses (the application's private-state callbacks), and record the public transcript (the ledger reads and writes the transaction declares). That run also produces the proof preimage, the input the prover feeds to ZKIR. ZKIR is already versioned and language-neutral, but it sits after this step: it consumes the preimage, and it does not build transcripts, call witnesses, or read contract state.

```
 Compact source
       |
       |  parse, type check, analyze
       v
 analyzed circuit body ---lower + flatten---> ZKIR   (proving IR, already shared)
       |
       |  today: TypeScript codegen only
       |  this CoIP: also serialize as "ir" in contract-info.json
       v
 executable circuit body
       |
       |  execute locally: apply ledger ops, call witnesses
       v
 public transcript + proof preimage
       |
       |  prove: run ZKIR over the preimage
       v
     proof
```

[MPS-0022](https://github.com/midnightntwrk/midnight-improvement-proposals/blob/main/mps/mps-0022-standard-contract-representation.md) states the problem and argues for a standard representation, but it leaves the format open on purpose. This CoIP proposes the format: serialize the circuit body the compiler already has, in the file it already writes.

## Specification

This section fixes the design shape. The full field-level schema (each op's fields, the type encoding, the ledger-op encoding) lives in the reference implementation and becomes a normative appendix after the community agrees on the shape.

An SDK that executes a circuit locally needs four things:

1. The body of each exported circuit, with witness calls and ledger operations explicit.
2. The Compact types, because the byte encoding of a value depends on its type.
3. The ledger layout, to find each field in the contract state.
4. A format version, to detect compatibility.

`contract-info.json` already carries the signatures and the ledger layout, but without a documented schema. This CoIP documents that schema and adds the missing parts:

```
{
  "contract-info-version": "0.1.0",   // NEW: version of this format
  "compiler-version": "0.31.104",     // provenance, not the compatibility contract
  "language-version": "0.23.104",
  "runtime-version": "0.16.101",      // the on-chain runtime the ledger ops target
  "circuits":  [ ... ],               // signatures, plus a NEW per-circuit "ir" body
  "helpers":   [ ... ],               // NEW: bodies of the helper circuits the exported bodies call
  "witnesses": [ ... ],               // signatures only; a witness stays a callback the SDK provides
  "contracts": [ ... ],               // imported contract names
  "ledger":    [ ... ]                // one entry per ledger field
}
```

### The circuit body

Each exported circuit keeps its signature (`name`, `pure`, `proof`, `arguments`, `result-type`) and gains one field:

```
"ir": { "body": Stmt, "result": null }
```

The `result` field is reserved for a future use; the emitter always writes `null` today, and the circuit's return value is the value of the body's final expression statement. Every exported circuit carries a body, pure and impure alike. The compiler serializes it from the analyzed form (`Lnodisclose`), the stage where it already writes `contract-info.json` and generates the TypeScript. This is a design constraint of the CoIP: the whole compiler change stays inside the `save-contract-info` pass, and the compilation pipeline does not change.

The body is a tree of statements and expressions. Each node is a JSON object tagged by `op`. The vocabulary covers:

- values and bindings
- logic, arithmetic, and comparison
- control, including the bounded loops (`map` and `fold`)
- data construction and access: structs, tuples, vectors, and slices
- casts
- effects: witness calls, helper-circuit calls, ledger operations, and cross-contract calls

Enum members and helper circuits stay by name; nothing is unrolled or inlined. The shared core keeps the node shapes the reference emitter already produces (`var`, `lit`, `assert`, `if-expr`, `eq`, `new`, `call-witness`, `ledger-query`, `contract-call`, and so on), and the analyzed level adds the loop, slice, helper-call, and named-enum forms. The exact op set is fixed in the field-level schema.

A `ledger-query` holds the ordered Impact VM ops (`idx`, `push`, `addi`, `ins`, `popeq`, and so on) that the compiler already expands for one ledger ADT operation. Their encoding tracks the on-chain runtime named by `runtime-version`.

### Types

One encoding, keyed on `type-name`, serves the whole file: structs inline their fields, and enums list their members. A consumer derives each value's byte layout from its type. The reference emitter's default mode still writes a second, post-lowering encoding (keyed on `type`) inside bodies, plus a `structs` side table of monomorphized layouts; its analyzed mode implements the selected design and needs neither.

### The ledger layout

Each `ledger` entry describes one field of the contract state: its `name`, its `index` in the state, whether it is `exported`, its ledger ADT kind (`Cell`, `Counter`, `Map`, `Set`, `List`, `MerkleTree`, or `HistoricMerkleTree`), and the kind's element types in the type encoding. The example below lists four.

### Versioning

`contract-info-version` is a semantic version of this format, and it starts at `0.1.0`. An additive change (a new op, a new optional field) bumps minor. A change that removes or repurposes anything, or changes the meaning of an existing op, bumps major. A consumer refuses an unknown major and fails closed on an unknown `op`. The field is independent of `compiler-version`: a compiler release that does not touch the schema does not bump it. While the version stays at `0.x`, a minor bump can still break.

### Example: the bulletin-board contract

The [bulletin-board contract](https://github.com/Moonsong-Labs/midnight-rs/blob/main/tests/conformance/fixtures/bboard/bboard.compact), the standard Compact example, covers every element of the format: an enum, a struct, four ledger fields, a witness, one pure circuit, and two impure circuits:

```compact
pragma language_version >= 0.16.0;

import CompactStandardLibrary;

export enum STATE { vacant, occupied }

export ledger state: STATE;
export ledger message: Maybe<Opaque<"string">>;
export ledger instance: Counter;
export ledger poster: Bytes<32>;

constructor() {
    state = STATE.vacant;
    message = none<Opaque<"string">>();
    instance.increment(1);
}

witness local_secret_key(): Bytes<32>;

export circuit post(new_message: Opaque<"string">): [] {
    assert(state == STATE.vacant, "Attempted to post to an occupied board");
    poster = disclose(public_key(local_secret_key(), instance as Field as Bytes<32>));
    message = some<Opaque<"string">>(disclose(new_message));
    state = STATE.occupied;
}

export circuit take_down(): Opaque<"string"> {
    assert(state == STATE.occupied, "Attempted to take down post from an empty board");
    assert(poster == public_key(local_secret_key(), instance as Field as Bytes<32>),
        "Attempted to take down post, but not the current poster");
    const former_msg = message.value;
    state = STATE.vacant;
    instance.increment(1);
    message = none<Opaque<"string">>();
    return former_msg;
}

export circuit public_key(sk: Bytes<32>, instance: Bytes<32>): Bytes<32> {
    return persistentHash<Vector<3, Bytes<32>>>([pad(32, "bboard:pk:"), instance, sk]);
}
```

All JSON below is real output of the reference emitter's analyzed mode, which serializes the selected form (see Reference implementation). One type encoding appears throughout, enum members stay by name, and helper circuits stay calls.

The four `ledger` entries use the type encoding. The enum keeps its members, and `Maybe` inlines its fields:

```json
[
  { "name": "state", "index": 0, "exported": true, "storage": "Cell",
    "type": { "type-name": "Enum", "name": "STATE", "elements": ["vacant", "occupied"] } },
  { "name": "message", "index": 1, "exported": true, "storage": "Cell",
    "type": { "type-name": "Struct", "name": "Maybe", "elements": [
      { "name": "is_some", "type": { "type-name": "Boolean" } },
      { "name": "value", "type": { "type-name": "Opaque", "tsType": "string" } } ] } },
  { "name": "instance", "index": 2, "exported": true, "storage": "Counter" },
  { "name": "poster", "index": 3, "exported": true, "storage": "Cell",
    "type": { "type-name": "Bytes", "length": 32 } }
]
```

The witness is a signature only, because the SDK provides the callback at run time:

```json
{ "name": "local_secret_key", "arguments": [], "result-type": { "type-name": "Bytes", "length": 32 } }
```

The `helpers` array carries the bodies of the called circuits: `none`, `public_key`, and `some` here. The `some` entry shows one in full, with the `Maybe` construction the interpreter evaluates when `post` stores a message:

```json
{ "name": "some",
  "params": [ { "name": "value", "type": { "type-name": "Opaque", "tsType": "string" } } ],
  "body": { "op": "seq", "stmts": [] },
  "result": { "op": "new",
              "type": { "type-name": "Struct", "name": "Maybe", "elements": [
                { "name": "is_some", "type": { "type-name": "Boolean" } },
                { "name": "value", "type": { "type-name": "Opaque", "tsType": "string" } } ] },
              "elements": [ { "op": "lit", "type": { "type-name": "Boolean" }, "value": "true" },
                            { "op": "var", "name": "value" } ] } }
```

The pure circuit `public_key` keeps its signature, with `pure` true and `proof` false: there is no proof to build for a pure call. Its body is a single `persistentHash` call. The parser folds `pad(32, "bboard:pk:")` to a `Bytes<32>` constant, so even the analyzed form carries the literal:

```json
{ "name": "public_key", "pure": true, "proof": false,
  "arguments": [ { "name": "sk", "type": { "type-name": "Bytes", "length": 32 } },
                 { "name": "instance", "type": { "type-name": "Bytes", "length": 32 } } ],
  "result-type": { "type-name": "Bytes", "length": 32 },
  "ir": {
    "body": {
      "op": "seq",
      "stmts": [
        { "op": "expr-stmt",
          "expr": {
            "op": "call-pure",
            "name": "persistentHash",
            "args": [
              { "op": "tuple",
                "elements": [
                  { "op": "lit", "type": { "type-name": "Bytes", "length": 32 },
                    "value": "62626F6172643A706B3A00000000000000000000000000000000000000000000" },
                  { "op": "var", "name": "instance" },
                  { "op": "var", "name": "sk" } ] } ],
            "result-type": { "type-name": "Bytes", "length": 32 } } } ]
    },
    "result": null
  }
}
```

The impure circuit `take_down` carries a body of three statements: two asserts and the main sequence. The first statement is `assert(state == STATE.occupied, ...)`. The read yields the enum type, and the comparison names the member:

```json
{ "op": "expr-stmt",
  "expr": { "op": "assert",
    "expr": { "op": "eq",
      "left": { "op": "ledger-query",
        "ops": [ { "op": "dup", "n": 0 },
                 { "op": "idx", "cached": false, "push-path": false,
                   "path": [ { "tag": "value", "value": "0",
                               "type": { "type-name": "Uint", "maxval": "255" } } ] },
                 { "op": "popeq", "cached": false } ],
        "result-type": { "type-name": "Enum", "name": "STATE",
                         "elements": ["vacant", "occupied"] } },
      "right": { "op": "enum-member",
                 "type": { "type-name": "Enum", "name": "STATE",
                           "elements": ["vacant", "occupied"] },
                 "member": "occupied" } },
    "message": "Attempted to take down post from an empty board" } }
```

Deeper in the same body sit the witness call, `local_secret_key()`:

```json
{ "op": "call-witness", "name": "local_secret_key", "args": [], "result-type": { "type-name": "Bytes", "length": 32 } }
```

and the write `state = STATE.vacant`, whose Impact VM ops push the named member into the cell:

```json
{ "op": "ledger-query",
  "ops": [ { "op": "push", "storage": false,
             "value": { "tag": "value", "value": "0",
                        "type": { "type-name": "Uint", "maxval": "255" } } },
           { "op": "push", "storage": true,
             "value": { "op": "enum-member",
                        "type": { "type-name": "Enum", "name": "STATE",
                                  "elements": ["vacant", "occupied"] },
                        "member": "vacant" } },
           { "op": "ins", "cached": false, "n": 1 } ],
  "result-type": { "type-name": "Tuple", "types": [] } }
```

An interpreter walks the body, runs each `ledger-query` against the contract state, resolves helper calls through `helpers`, calls the witness through the SDK's callback, and collects the public transcript and the witness inputs for proving.

## Rationale

Why not ZKIR. Both run off-chain. The difference is altitude, as the diagram in Motivation shows: this format produces the transcript and the preimage, and ZKIR consumes the preimage to prove. ZKIR is also flattened to field-level operations and untyped at the Compact level, so interpreting it to rebuild transcript-level semantics is strictly harder than interpreting the structured body. The two stay decoupled: the compiler takes the `ir` before the flattening passes that feed ZKIR, so a ZKIR release does not touch this format.

Why inside `contract-info.json`. The file already exists, and it already carries the signatures and the ledger layout an interpreter needs next to the body. A second artifact would force consumers to correlate two files and two version numbers.

Why the analyzed form (`Lnodisclose`). It is the compiler's existing branch point: `contract-info.json` is already written there, and the TypeScript backend generates from there. So the emitter change stays inside the `save-contract-info` pass, and the compilation pipeline does not change. One type encoding serves the whole file, and bodies stay near source size. The semantics an interpreter must implement (loops, helper calls, enums, casts) is the one the generated TypeScript already executes, so the canonical behavior is well defined, and a differential harness checks an interpreter against it. The alternative is the lowered form one stage down (`Lnovectorref`), which makes each interpreter smaller because the compiler has already unrolled loops, inlined helpers, and resolved enums. But exposing that form means the compiler restructures its circuit pipeline, and the unrolled bodies grow large. The reference implementation started there; this CoIP selects the analyzed form to keep the compiler ask minimal.

## Backwards Compatibility

The change is additive. The TypeScript pipeline does not read the new fields, and tools that ignore unknown keys see no change. One caveat: fields that never had a documented schema get one, so a consumer that keyed on an incidental spelling must move to the canonical one. Example: the witness return type is `result-type`, hyphenated, like every other result type in the file.

## Reference implementation

Reference emitter: the [`feat/contract-info-extensions`](https://github.com/RomarQ/compact/tree/feat/contract-info-extensions) branch of `RomarQ/compact`. Its analyzed mode serializes bodies from `Lnodisclose` with the diff confined to [`save-contract-info-passes.ss`](https://github.com/RomarQ/compact/blob/feat/contract-info-extensions/compiler/save-contract-info-passes.ss), as the design requires; the example above is its output. Its default mode still serializes the lowered form (`Lnovectorref`) that the current consumer executes.

Reference consumer: the `compact-codegen` (schema), `compact-runtime` (values, builtins, witnesses), and `compact-interpreter` (tree walk and ledger-op driver) crates in [`Moonsong-Labs/midnight-rs`](https://github.com/Moonsong-Labs/midnight-rs). A differential conformance harness runs the interpreter and the generated TypeScript on the same contracts and compares the resulting transcripts. Re-targeting adds loop, helper-call, and named-enum execution to the interpreter; its schema already carries the helper and enum definitions.

This consumer shows what the format buys an SDK. Its `contract!` macro reads `contract-info.json` and generates typed bindings, and the interpreter executes the bodies for deploys and circuit calls. The contract behind the quick start, [`counter.compact`](https://github.com/Moonsong-Labs/midnight-rs/blob/main/devnet/contracts/counter/counter.compact):

```compact
import CompactStandardLibrary;

export ledger round: Counter;

export circuit increment(): Uint<64> {
  round.increment(1);
  return disclose(1);
}

export circuit increment_by(amount: Uint<16>): Uint<16> {
  round.increment(disclose(amount));
  return disclose(amount);
}
```

And the [quick start](https://github.com/Moonsong-Labs/midnight-rs#quick-start), in full:

```rust
use midnight_provider::{MidnightProvider, Network, Seed};

mod counter {
    compact_bindgen::contract!("compiled/contract-info.json");
}

const NODE_URL: &str = "ws://localhost:9944";
const INDEXER_URL: &str = "http://localhost:8088";

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let seed = Seed::from_hex(
        "0000000000000000000000000000000000000000000000000000000000000001",
    )?;
    // The provider owns the URLs and drives the wallet sync (zswap + dust +
    // unshielded subscriptions against its own indexer).
    let provider = MidnightProvider::new(NODE_URL, INDEXER_URL)?
        .sync_wallet(seed, Network::Undeployed)
        .await?;

    // Deploy: the builder is awaitable directly via `IntoFuture`.
    // `.with_zk_config` points at the compiled contract's keys/zkir directory
    // (or any custom ZkConfigProvider).
    let contract = counter::Contract::deploy(&provider)
        .with_initial_state(counter::LedgerInitialState::default())
        .with_zk_config("compiled")
        .await?;

    println!("deployed at {}", contract.address());
    println!("round = {}", contract.ledger().await?.round()?);

    // Call a circuit on-chain. `circuits()` defaults to no witnesses; add
    // `.with_witnesses(&w)` for stateful witnesses. Circuits with typed return
    // values hand them back to the caller.
    let returned: u64 = contract.circuits().increment().await?;
    println!("increment returned {returned}");
    println!("round = {}", contract.ledger().await?.round()?);

    // Typed arguments are supported for on-chain calls.
    let returned: u16 = contract.circuits().increment_by(5).await?;
    println!("increment_by(5) returned {returned}");
    println!("round = {}", contract.ledger().await?.round()?);

    Ok(())
}
```

Remaining work before submission:

- Re-target the consumer and the conformance corpus to the analyzed bodies, then make the analyzed mode the emitter default.
- Emit `contract-info-version` and bump it per the Versioning rules.
- Rebase the emitter branch onto upstream `main`.
- Add golden tests in the compiler repo for representative contracts.
- Write the field-level schema appendix.

## References

- MPS-0022, Language-Agnostic Representation of Compiled Compact Contracts (the problem statement): [midnightntwrk/midnight-improvement-proposals#188](https://github.com/midnightntwrk/midnight-improvement-proposals/blob/main/mps/mps-0022-standard-contract-representation.md)
- Reference implementation: https://github.com/RomarQ/compact/tree/feat/contract-info-extensions
- Reference consumer: https://github.com/Moonsong-Labs/midnight-rs (`crates/compact/`)

## Copyright

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).
