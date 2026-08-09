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

The Compact compiler emits the off-chain half of a compiled contract only as generated TypeScript, so only TypeScript SDKs can use a contract. This CoIP adds a language-agnostic description of each circuit's body to `contract-info.json`, the machine-readable file the compiler already writes: a typed body per circuit and a format version. The bodies serialize from the compiler's analyzed form (`Lnodisclose`), so the whole compiler change stays inside the pass that already writes the file. With these, an SDK in any language can execute circuits locally with a small interpreter, instead of embedding a JavaScript engine. 

This draft describes the design, to start the discussion. The [appendix](#appendix-the-schema) states the exact schema.

## Motivation

The only first-class way to use a compiled contract today is the generated TypeScript plus `@midnight-ntwrk/compact-runtime`. An SDK in another language must embed a JavaScript engine.

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

This section describes the design. The appendix at the end states the schema field by field, and is normative.

An SDK that deploys a contract and calls its circuits needs five things:

1. The body of each exported circuit, with witness calls and ledger operations explicit.
2. The Compact types, because the byte encoding of a value depends on its type.
3. The ledger layout, to find each field in the contract state.
4. The constructor, for the writes a deployment applies over the default state.
5. A format version, to detect compatibility.

`contract-info.json` already carries the signatures and the ledger layout, but without a documented schema. This CoIP documents that schema and adds the missing parts:

```
{
  "contract-info-version": "0.1.0",   // NEW: version of this format
  "compiler-version": "0.31.104",     // provenance, not the compatibility contract
  "language-version": "0.23.104",
  "runtime-version": "0.16.101",      // the on-chain runtime the ledger ops target
  "circuits":  [ ... ],               // signatures, plus a NEW per-circuit "ir" body
  "helpers":   [ ... ],               // NEW: bodies of the circuits the exported bodies call
  "witnesses": [ ... ],               // signatures only; a witness stays a callback the SDK provides
  "contracts": [ ... ],               // imported contract names
  "ledger":    [ ... ],               // one entry per ledger field
  "constructor": { ... }              // NEW: the writes a deployment applies, or null
}
```

### The circuit body

Each exported circuit keeps its signature (`name`, `pure`, `proof`, `arguments`, `result-type`) and gains one field:

```
"ir": { "body": Stmt }
```

Every exported circuit carries a body, pure and impure alike. The compiler serializes it from the analyzed form (`Lnodisclose`), the stage where it already writes `contract-info.json` and generates the TypeScript. This is a design constraint of the CoIP: the whole compiler change stays inside the `save-contract-info` pass, and the compilation pipeline does not change. The circuit's return value is the value of the body's final expression statement.

The body is a tree of statements and expressions. Each node is a JSON object tagged by `op`. The vocabulary covers:

- values and bindings
- arithmetic and comparison
- control: conditionals, assertions, and the bounded loops (`map` and `fold`)
- data construction and access: structs, tuples, vectors, and slices
- casts
- effects: witness calls, helper-circuit calls, ledger operations, and cross-contract calls

Enum members and helper circuits stay by name; nothing is unrolled or inlined. The example below shows the node shapes (`var`, `lit`, `assert`, `eq`, `tuple`, `enum-member`, `call-pure`, `call-witness`, `ledger-query`, and so on). The appendix lists every one.

A `ledger-query` holds the ordered Impact VM ops (`idx`, `push`, `addi`, `ins`, `popeq`, and so on) that the compiler already expands for one ledger ADT operation. Their encoding tracks the on-chain runtime named by `runtime-version`. The appendix defines each operation and its operand kinds.

### Types

One encoding, keyed on `type-name`, serves the whole file: structs inline their fields, and enums list their members.

### The ledger layout

Each `ledger` entry describes one field of the contract state: its `name`, its `index` in the state, whether it is `exported`, its ledger ADT kind (`Cell`, `Counter`, `Map`, `Set`, `List`, `MerkleTree`, or `HistoricMerkleTree`), and the kind's element types.

### The constructor

A deployment starts from the default value of every ledger field, which a consumer derives from the layout above. `constructor` carries what the source writes on top of that: the statements, in the same tree the circuits use, and the deploy-time `arguments` the caller supplies. It is a set of writes, not the whole initial state, and it touches only the fields the source assigns. A consumer must apply both, in that order.

`constructor` is `null` when the source writes no constructor.

### Versioning

`contract-info-version` is a semantic version of this format, and it starts at `0.1.0`. An additive change (a new op, a new optional field) bumps minor. A change that removes or repurposes anything, or changes the meaning of an existing op, bumps major. A consumer refuses an unknown major and fails closed on an unknown `op`.

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

All JSON below is real output of the reference emitter.

The witness is a signature only, because the SDK provides the callback at run time:

```json
{ "name": "local_secret_key", "arguments": [], "result-type": { "type-name": "Bytes", "length": 32 } }
```

The `helpers` array carries the bodies of the called circuits: `public_key` here.

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
    }
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
                               "type": { "type-name": "Uint", "maxval": 255 } } ] },
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
                        "type": { "type-name": "Uint", "maxval": 255 } } },
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

- **Why not ZKIR? Both run off-chain.**

  The difference is altitude, as the diagram in Motivation shows: this format produces the transcript and the preimage, and ZKIR consumes the preimage to prove.

- **Why inside `contract-info.json`?**

  The file already exists, and it already carries the signatures and the ledger layout an interpreter needs next to the body. A second artifact would force consumers to correlate two files and two version numbers.

- **Why the analyzed form (`Lnodisclose`)?**
  
  It is the compiler's existing branch point: `contract-info.json` is already written there, and the TypeScript backend generates from there. So the emitter change stays inside the `save-contract-info` pass, and the compilation pipeline does not change.

## Backwards Compatibility

The change is additive. Every field this CoIP adds is new, no existing field changes its name, its shape or its meaning, and the TypeScript pipeline reads none of them.

## Reference implementation

Reference emitter: the [`rp/coip-003`](https://github.com/RomarQ/compact/tree/rp/coip-003) branch of `RomarQ/compact`, whose output the example above is. The change is one rewritten pass, [`save-contract-info-passes.ss`](https://github.com/RomarQ/compact/blob/rp/coip-003/compiler/save-contract-info-passes.ss), and nothing else: the pass list and every other file in the compiler are byte-identical to the commit it branches from.

Reference consumer: [`Moonsong-Labs/midnight-rs`](https://github.com/Moonsong-Labs/midnight-rs) provides crates for consuming the `contract-info.json` artifact and allow Rust applications to deploy and call Compact contracts.

- `compact-codegen` (schema);
- `compact-runtime` (values, builtins, witnesses)
- `compact-interpreter` (tree walk and ledger-op driver)

The quick start contract, [`counter.compact`](https://github.com/Moonsong-Labs/midnight-rs/blob/main/devnet/contracts/counter/counter.compact):

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

## Open Questions

**Key naming.** The file mixes three conventions: `type-name` and `result-type` in kebab-case and `tsType` in camelCase. Five of the eight kebab-case keys predate this proposal, the compiler itself reads them when one contract imports another, and its own tests assert on them, so renaming them is a breaking change to a published format rather than a matter of style. This CoIP therefore follows the existing spelling and stays additive. Should every key use `snake_case` or `camelCase` instead, since it is a better JSON format?

## References

- MPS-0022, Language-Agnostic Representation of Compiled Compact Contracts (the problem statement): [midnightntwrk/midnight-improvement-proposals#188](https://github.com/midnightntwrk/midnight-improvement-proposals/blob/main/mps/mps-0022-standard-contract-representation.md)
- Reference implementation: https://github.com/RomarQ/compact/tree/rp/coip-003
- Reference consumer: https://github.com/Moonsong-Labs/midnight-rs (`crates/compact/`)

## Appendix: the schema

This appendix is normative. Every shape below is what the reference emitter produces; the example above is one instance of it.

A consumer must reject a document whose `contract-info-version` has a major it does not implement, and must reject an `op`, a `type-name` or a `tag` it does not recognize, rather than guess. The ledger operation names are the exception: that set is open, and the rule for an unrecognized one is given with them.

### The file

| Field | Type | Meaning |
|---|---|---|
| `contract-info-version` | string | Semantic version of this format. The compatibility contract. |
| `compiler-version` | string | Provenance. Not a compatibility contract. |
| `language-version` | string | Provenance. |
| `runtime-version` | string | The on-chain runtime the ledger operations target. |
| `circuits` | array | One entry per exported circuit. |
| `helpers` | array | One entry per circuit an exported body calls. |
| `witnesses` | array | Signature only. The SDK supplies the callback. |
| `contracts` | array of string | Names of imported contracts. |
| `ledger` | array | One entry per ledger field. |
| `constructor` | object or null | The writes a deployment applies. Null when the source writes no constructor. |

A circuit is `{ name, pure, proof, arguments, result-type, ir }`. `arguments` is an array of `{ name, type }`. `ir` is `{ body }`, where `body` is a statement.

A helper is `{ name, params, body }`. `params` matches `arguments`, and `body` matches a circuit's. A consumer evaluates a helper's body for its effects as well as its value, because a called circuit can write the ledger.

A witness is `{ name, arguments, result-type }`.

The constructor is `{ arguments, body }`.

### Statements

| `op` | Fields | Meaning |
|---|---|---|
| `seq` | `stmts`: array | Execute in order. |
| `expr-stmt` | `expr` | Evaluate and discard. The value of a body's last one is the circuit's return value. |

### Expressions

Every node is an object whose `op` names it. `expr`, `left`, `right`, `cond`, `then`, `else`, `body`, `init`, `value` and `index` hold expressions unless stated otherwise.

Values and bindings:

| `op` | Fields | Meaning |
|---|---|---|
| `var` | `name`: string | Read a binding. |
| `lit` | `type`, `value`: string | Literal. `value` is decimal for a number, `true`/`false` for a Boolean, uppercase hex without a prefix for Bytes. |
| `default` | `type` | That type's default value. |
| `enum-member` | `type`, `member`: string | The member's index in the variant list its type carries. |
| `let-expr` | `bindings`: array of `let`, `body` | Bind in order, then evaluate the body. |
| `let` | `name`: string, `value` | A binding. Appears in `bindings` and as a statement. |

Arithmetic and comparison, each taking `left` and `right`: `add`, `sub`, `mul`, `eq`, `neq`, `lt`, `le`, `gt`, `ge`.

Control:

| `op` | Fields | Meaning |
|---|---|---|
| `if-expr` | `cond`, `then`, `else` | Evaluate the condition, then only the branch taken. |
| `assert` | `expr`, `message`: string | Abort with the message when the value is false. |
| `map` | `length`: number, `fun`, `args`: array | Evaluate each argument once, then build a tuple of `length` applications of `fun` to element `i` of each. |
| `fold` | `length`: number, `fun`, `init`, `args`: array | As `map`, threading an accumulator that starts at `init` and is `fun`'s first argument. Iterates from element 0. |

A `fun` is `{ call: string }`, naming an entry in `helpers`, or `{ params, body }`, an inline function whose parameters shadow the enclosing bindings rather than replacing them.

Data:

| `op` | Fields | Meaning |
|---|---|---|
| `new` | `type`, `elements`: array | Struct literal, in declaration order. |
| `tuple` | `elements`: array | Tuple or vector literal. Empty is the unit value. |
| `spread` | `length`: number, `expr` | Splice `length` elements into the surrounding `tuple`. Valid only there. |
| `field` | `expr`, `name`: string | Struct field. |
| `index` | `expr`, `index`: number | Tuple or vector element at a constant position. |
| `vector-index` | `expr`, `index` | Vector element at a computed position. |
| `bytes-index` | `expr`, `index` | One byte. |
| `tuple-slice` | `expr`, `index`: number, `length`: number, `type` | `length` elements from a constant offset. `type` is the operand's type, so the offset and length apply to it. |
| `vector-slice` | `expr`, `index`, `length`: number, `type` | As `tuple-slice`, with a computed offset. The operand is evaluated first. |
| `bytes-slice` | `expr`, `index`, `length`: number | `length` bytes. The result is `Bytes<length>`. |

Casts, each carrying `expr`:

| `op` | Fields | Meaning |
|---|---|---|
| `cast` | `from`, `to` | Reinterpret between numeric types and enums. The value is unchanged; the types give the encoding widths. |
| `field-to-bytes` | `length`: number | A field element as `Bytes<length>`. |
| `bytes-to-vector` | `length`: number | Bytes as a vector of bytes. |
| `vector-to-bytes` | `length`: number | The inverse. |

Effects:

| `op` | Fields | Meaning |
|---|---|---|
| `call-pure` | `name`: string, `args`: array, `result-type` | A circuit in `helpers`, or a native builtin. A name in `helpers` wins, so a circuit that shadows a builtin resolves to the circuit. |
| `call-witness` | `name`: string, `args`: array, `result-type` | The application's private-state callback. |
| `ledger-query` | `ops`: array, `result-type` | Run the operations below against the contract state. |
| `contract-call` | `circuit`: string, `contract`, `contract-type`, `args`: array | Invoke a circuit on another contract. |

### Types

One encoding, tagged `type-name`, used everywhere a type appears.

| `type-name` | Fields | Meaning |
|---|---|---|
| `Boolean` | | |
| `Field` | | A field element. |
| `Uint` | `maxval`: number | Inclusive upper bound. Reaches 2^248-1, so parse with arbitrary precision. |
| `Bytes` | `length`: number | |
| `Opaque` | `tsType`: string | A value the contract does not interpret. |
| `Vector` | `length`: number, `type` | |
| `Tuple` | `types`: array | The empty tuple is the unit type. |
| `Struct` | `name`: string, `elements`: array of `{ name, type }` | Carries its own layout: a name does not determine one, because two instantiations of a generic struct share a name and differ in shape. |
| `Enum` | `name`: string, `elements`: array of string | Variants in declaration order. The value is the index. |
| `Alias` | `name`: string, `type` | A nominal alias. Transparent ones are already resolved. |
| `Contract` | `name`: string | A handle to another contract. |

A ledger field's type is its storage kind, `Cell`, `Counter`, `Map`, `Set`, `List`, `MerkleTree` or `HistoricMerkleTree`, under `type-name` when it appears as a type and under `storage` in a `ledger` entry. `Cell`, `Set` and `List` carry `type`; `Map` carries `key` and `value`; the trees carry `depth` and `type`; `Counter` carries nothing.

### Ledger operations

The entries of a `ledger-query`'s `ops`, in order, as the compiler expands one ledger operation. Their encoding tracks `runtime-version`.

| `op` | Fields |
|---|---|
| `idx` | `cached`: bool, `push-path`: bool, `path`: array of path element |
| `ins` | `cached`: bool, `n`: number |
| `rem` | `cached`: bool |
| `popeq` | `cached`: bool |
| `push` | `storage`: bool, `value`: operand |
| `addi` | `immediate`: operand |
| `dup` | `n`: number |
| `noop` | `n`: number |
| `member`, `root`, `eq`, `ckpt` | none |

This set is open. Any other operation of the on-chain runtime appears under its own name with its arguments as given, so a consumer that does not recognize one must refuse the document rather than skip the operation: an omitted operation is a different program.

A path element is one of:

| `tag` | Fields | Meaning |
|---|---|---|
| `value` | `value`: string, `type` | A constant. |
| `var` | `name`: string | The value of a binding. |
| `expr` | `expr` | A computed index. |
| `stack` | | The value already on the stack. |

An operand of `push` or `addi` is one of four kinds, each with its own key so a consumer can tell them apart without context: a path element (`tag`), an expression to evaluate (`op`), a structured state value (`state`, which is what resetting a field to its default pushes), or a value to compute (`vm`).

| Key | Values |
|---|---|
| `state` | `array` with `values`; `map` with `entries` of `{ key, value }`; `merkle-tree` with `depth` and `entries` |
| `vm` | `add` with `left` and `right`; `aligned-concat` with `values`; `null`, `max-sizeof`, `leaf-hash` each with `value`; `coin-commit` with `coin` and `recipient` |

## Copyright

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).
