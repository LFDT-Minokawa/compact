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

The Compact compiler emits the off-chain half of a compiled contract only as generated TypeScript. An SDK for another language must embed a JavaScript engine. This CoIP adds a second compiler output behind a flag, `compiler/analyzed-ir.sexp`. The file contains the analyzed program and the metadata required for circuit execution. Each ledger operation and each `emit` includes its expanded Impact VM instructions.

## Motivation

The generated TypeScript and `@midnight-ntwrk/compact-runtime` provide the only first-class way to use a compiled contract.

An SDK must run the circuit body locally before it can prove a transaction. This run applies ledger operations and calls the application witnesses. It also produces the public transcript and the proof preimage.

ZKIR starts after this step and operates at a lower level. The compiler has unrolled loops and inlined calls by that point. The resulting program no longer follows the source structure.

```
 Compact source
       |
       |  parse, type check, analyze
       v
 analyzed program  ---lower + flatten--->  ZKIR
       |
       |  TypeScript code generation
       |  or compiler/analyzed-ir.sexp
       v
 executable circuit body
       |
       |  apply ledger operations and call witnesses
       v
 public transcript + proof preimage
       |
       |  run ZKIR over the preimage
       v
     proof
```

[MPS-0022](https://github.com/midnightntwrk/midnight-improvement-proposals/blob/main/mps/mps-0022-standard-contract-representation.md) describes the need for a standard representation. It leaves the format open. This CoIP proposes a format based on the analyzed program already held by the compiler.

## Specification

The compiler writes `compiler/analyzed-ir.sexp` into the target directory when the user passes `--analyzed-ir`. The file contains one S-expression datum.

The artifact uses the compiler's intermediate-language vocabulary. `compiler/langs.ss` defines that vocabulary. The extraction pass removes source locations and preserves form names where practical. It also adds the metadata required for execution.

The extraction pass must change when a relevant intermediate-language form changes. The compiler fails if the pass cannot serialize a required form.

The artifact has no independent format version. It starts with `compiler-version`, `language-version`, and `runtime-version`. A consumer uses these values to select the versions that it supports.

### What the artifact carries

The artifact contains information that a plain Nanopass unparse does not provide.

First, it contains the expanded Impact VM instructions. Each `public-ledger` and each `emit` includes an `(instructions ...)` block. The block uses the ledger DSL notation from `compiler/midnight-ledger.ss`.

Second, each ledger operation includes its operation class. Some runtime behavior is not present in the instruction list. This includes the coin checks used by operations such as `writeCoin`.

Third, each native declaration includes its runtime function, class, and concrete type arguments. A consumer needs this metadata to call generic native functions.

Fourth, each circuit includes its `exported`, `pure`, and `proof` flags. Public ledger bindings also include their `exported` flag.

Fifth, the program includes the map from each exported name to its internal identifier.

### A worked example

This source:

```compact
import CompactStandardLibrary;

export ledger round: Counter;

export circuit increment(): [] {
  round.increment(1);
}
```

produces an artifact with this shape. The version values depend on the compiler release.

```scheme
(analyzed-ir
  (compiler-version "<compiler-version>")
  (language-version "<language-version>")
  (runtime-version "<runtime-version>")
  (exports (increment . %increment.0) (round . %round.1))
  (contract-types)
  (kernel-declaration (%kernel.3 () (exported #f) (Kernel)))
  (public-ledger-declaration
    (public-ledger-array (%round.1 (0) (exported #t) (Counter)))
    (constructor () (tuple)))
  (circuit %increment.0 (exported #t) (pure #f) (proof #t) () (ttuple)
    (seq
      (let* (((%tmp.2 (tunsigned 65535))
              (safe-cast (tunsigned 65535) (tunsigned 1) '1)))
        (public-ledger %round.1 update (0) increment (ttuple)
          (instructions
            (idx (cached #f) (pushPath #t) (path ((align 0 1))))
            (addi (immediate (value->int (var-ref %tmp.2))))
            (ins (cached #t) (n 1)))
          (var-ref %tmp.2)))
      (return (tuple)))))
```

The `increment` circuit is exported, is not pure, and requires a proof. It takes no arguments and returns the empty tuple.

The body casts `1` to the declared counter argument type. It then applies an `update` operation to `%round.1` at path `(0)`. The interpreter replays the instruction block against the contract state.

## Rationale

- **Why not ZKIR?**

  This format produces the transcript and proof preimage. ZKIR consumes the preimage and proves it. ZKIR no longer follows the source structure.

- **Why use a separate file instead of `contract-info.json`?**

  `contract-info.json` has other consumers that do not need executable circuit bodies. The separate file keeps the two concerns independent. The flag keeps the artifact disabled by default.

- **Why use the analyzed form (`Lloweredemit`)?**

  `prepare-for-typescript` uses the same intermediate language. The artifact and generated TypeScript therefore start from the same analyzed program. Consumers must produce the same execution semantics.

- **Why use an S-expression?**

  The compiler and its intermediate languages use Scheme data. `pretty-print` handles the final encoding. The extraction pass converts compiler records and hidden metadata into portable S-expression data.

  Exact integers can reach 2^252. A consumer must support arbitrary-precision integers. A reader that uses 64-bit integers will lose information.

## Backwards Compatibility

The flag is disabled by default. Without the flag, the compiler writes the same files with the same contents.

The artifact follows the compiler's intermediate language. Its structure can change between compiler versions. Consumers must check the version fields before reading the remaining data.

## Reference implementation

[LFDT-Minokawa/compact#722](https://github.com/LFDT-Minokawa/compact/pull/722) implements the in-tree `--analyzed-ir` output described by this CoIP. The compiler owns the extraction pass and writes `compiler/analyzed-ir.sexp` when the flag is present.

[RomarQ/compact#13](https://github.com/RomarQ/compact/pull/13) is an earlier alternative prototype. It lets a consumer load a Scheme pass and own the emitter.

## References

- MPS-0022, Language-Agnostic Representation of Compiled Compact Contracts: [midnightntwrk/midnight-improvement-proposals#188](https://github.com/midnightntwrk/midnight-improvement-proposals/blob/main/mps/mps-0022-standard-contract-representation.md)
- Reference implementation: [LFDT-Minokawa/compact#722](https://github.com/LFDT-Minokawa/compact/pull/722)
- Alternative prototype: [RomarQ/compact#13](https://github.com/RomarQ/compact/pull/13)
- Reference consumer: [Moonsong-Labs/midnight-rs](https://github.com/Moonsong-Labs/midnight-rs), in `crates/compact/`

## Copyright

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).
