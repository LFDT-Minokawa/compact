---
CoIP: xxxx
Title: A language-agnostic representation of a compiled contract
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

The Compact compiler emits the off-chain half of a compiled contract only as generated TypeScript, so only TypeScript SDKs can use a contract. This CoIP adds a second compiler output behind a flag, `compiler/analyzed-ir.sexp`. The file holds the analyzed program in the compiler's own vocabulary. Every ledger operation and every `emit` carries its expanded Impact VM instructions. An SDK in any language can then execute circuits with a small interpreter, instead of embedding a JavaScript engine.

## Motivation

The only first-class way to use a compiled contract today is the generated TypeScript plus `@midnight-ntwrk/compact-runtime`. An SDK in another language must embed a JavaScript engine.

Off-chain execution is half of every contract call. Before an SDK can prove anything, it must run the circuit body locally. It applies the ledger operations to the contract state. It calls the witnesses, which are the application's private-state callbacks. It records the public transcript, which is the set of ledger reads and writes that the transaction declares. That run also produces the proof preimage, the input the prover feeds to ZKIR.

ZKIR is already versioned and language-neutral. It sits after this step, and it sits lower in the pipeline. By ZKIR the compiler has unrolled the loops and inlined the calls, so a small contract becomes a large program. That program no longer matches the shape of the source.

```
 Compact source
       |
       |  parse, type check, analyze
       v
 analyzed program  ---lower + flatten--->  ZKIR   (proving IR, already shared)
       |
       |  today: TypeScript codegen only
       |  this CoIP: also write compiler/analyzed-ir.sexp
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

[MPS-0022](https://github.com/midnightntwrk/midnight-improvement-proposals/blob/main/mps/mps-0022-standard-contract-representation.md) states the problem and argues for a standard representation, but it leaves the format open on purpose. This CoIP proposes the format. The compiler prints the analyzed program it already holds, in the vocabulary it already uses.

## Specification

The compiler writes `compiler/analyzed-ir.sexp` into the target directory when the user passes `--analyzed-ir`. The file holds one S-expression datum. The name is the compiler's own: `compiler/passes.ss` binds this value as `analyzed-ir` after the analysis passes run.

The vocabulary is the compiler's own. `compiler/langs.ss` is the grammar. Forms keep their names and their field order, and identifiers print as the compiler prints them. So this CoIP defines no schema of its own. There is no renaming layer to maintain, and there is no second description of the language to keep in step with the first.

The file carries no format version of its own. It opens with `compiler-version`, `language-version` and `runtime-version`, and those name the compiler that wrote it. The format follows the intermediate language, so it can change with the compiler. A consumer reads those three fields and accepts the versions it supports.

### What the pass adds

The pass prints the analyzed program. It adds three things that a plain unparse does not show.

First, the VM lowering. The nanopass unparse template for `tadt` in `langs.ss` renders the form as `(adt-name #f adt-arg* ...)`. That drops `vm-expr` and both op tables. So a plain dump shows the symbolic ledger operation and none of its instructions. This pass expands them. Each `public-ledger` and each `emit` carries an `(instructions ...)` block, in the ledger DSL notation of `compiler/midnight-ledger.ss`.

Second, the circuit flags. The compiler holds `exported`, `pure` and `proof` in the identifier record, not in the form. Each circuit carries them.

Third, the export table. The program carries the map from each exported name to the identifier it names.

### A worked example

This source:

```compact
import CompactStandardLibrary;

export ledger round: Counter;

export circuit increment(): [] {
  round.increment(1);
}
```

produces this file:

```scheme
(analyzed-ir (compiler-version "0.33.122") (language-version "0.25.107")
  (runtime-version "0.18.107")
  (exports (increment . %increment.0) (round . %round.1))
  (contract-types)
  (kernel-declaration (%kernel.3 () (exported #f) (Kernel)))
  (public-ledger-declaration
    (public-ledger-array (%round.1 (0) (exported #t) (Counter)))
    (constructor () (tuple)))
  (circuit %increment.0 (exported #t) (pure #f) (proof #t) () (ttuple)
    (seq (let* (((%tmp.2 (tunsigned 65535)) (safe-cast
                                              (tunsigned 65535)
                                              (tunsigned 1)
                                              '1)))
           (public-ledger %round.1 (0) increment (ttuple)
             (instructions
               (idx (cached #f) (pushPath #t) (path ((align 0 1))))
               (addi (immediate (value->int (var-ref %tmp.2))))
               (ins (cached #t) (n 1)))
             (var-ref %tmp.2)))
         (return (tuple)))))
```

An interpreter reads it as follows. `increment` is exported, it is not pure, and it needs a proof. It takes no arguments and returns the empty tuple. Its body binds `%tmp.2` to the literal `1`, cast to `Uint<0..65535>`, the declared width of the counter's argument. It then runs one ledger operation on the field `%round.1` at path `(0)`. The `(instructions ...)` block is what the interpreter replays against the contract state. It walks to field 0, adds the immediate, and writes the result back.

## Rationale

- **Why not ZKIR?**

  The difference is altitude. This format produces the transcript and the preimage. ZKIR consumes the preimage and proves it. By ZKIR the compiler has unrolled the loops and inlined the calls, so the program no longer matches the source.

- **Why a separate file, and not `contract-info.json`?**

  `contract-info.json` has other consumers, and they should not carry this. Keeping the artifact separate keeps the two concerns apart. The flag keeps it off by default, so a user who does not want the file does not get it.

- **Why the analyzed form (`Lloweredemit`)?**

  `prepare-for-typescript` generates from that same IR. So the artifact and the generated TypeScript come from one form at one point in the pipeline. This is not a second semantics. An interpreter that disagrees with the TypeScript runtime has a bug in one consumer.

- **Why an S-expression?**

  The compiler is written in Scheme, so it prints one with `pretty-print` and no serializer. The reader on the consumer side is small. One caution: the exact integers in this file reach 2^252, so a consumer needs arbitrary-precision integers. A reader that stores numbers as 64-bit values loses them.

## Backwards Compatibility

The flag is off by default. With the flag off, the compiler writes the same files with the same bytes.

## Reference implementation

Two compiler branches implement this, both against upstream `main`. They differ in who owns the emitter.

- [RomarQ/compact#16](https://github.com/RomarQ/compact/pull/16) adds `--analyzed-ir`. The emitter is a new pass in the compiler. It adds 391 lines and removes nothing. `save-contract-info-passes` stays untouched. This is what this CoIP proposes.
- [RomarQ/compact#13](https://github.com/RomarQ/compact/pull/13) adds `--run-hook`. A consumer loads its own Scheme pass and owns the emitter. It is the alternative. It needs the compiler's libraries visible, which grows the binary, and it asks every consumer to carry a Scheme pass.

The two write the same file.

## References

- MPS-0022, Language-Agnostic Representation of Compiled Compact Contracts (the problem statement): [midnightntwrk/midnight-improvement-proposals#188](https://github.com/midnightntwrk/midnight-improvement-proposals/blob/main/mps/mps-0022-standard-contract-representation.md)
- Reference implementation, in-tree flag: https://github.com/RomarQ/compact/pull/16
- Reference implementation, consumer-owned hook: https://github.com/RomarQ/compact/pull/13
- Reference consumer: https://github.com/Moonsong-Labs/midnight-rs (`crates/compact/`)

## Copyright

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).
