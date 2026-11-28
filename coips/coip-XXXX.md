---
CoIP: X
Title: Contract-defined Ledger-state Types
Authors:
  - Kevin Millikin (kmillikin)
Status: Draft
Category: Language
Created: 2026-11-04
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

The Compact standard library provides a small fixed set of **ledger-state types**
which are used by Compact contracts to represent their public state on the Midnight Network blockchain.
Each ledger-state type supports **operations** that are represented in the
**public transcript** that is part of a Midnight Network transaction.

There is currently no way for a contract or a library to define its own custom ledger-state types.
Custom ledger-state types are necessary to provide missing data structures needed by a contract.
They can also be used (sometimes) to avoid unwanted **read/write contention** between transactions
(see [MPS 46: Non-contentive Message Numbering](https://github.com/midnightntwrk/midnight-improvement-proposals/blob/main/mps/mps-0046-non-contentive-message-numbering.md)).

This CoIP proposes a simple and flexible way for a Compact contract or library to define its own ledger-state types.

## Motivation

The Compact ledger-state types are defined in the Compact standard library.
They are specified in the
[Compact reference](https://docs.midnight.network/compact/reference/compact-reference#ledger-state-types)
and their operations are described in the
[Ledger data types](https://docs.midnight.network/compact/reference/ledger-adt) documentation.
The term **"ledger ADT"** is used interchangeably for ledger-state type.
As of Compact language 0.28, there are just eight ledger-state types:
`Cell`, `Counter`, `HistoricMerkleTree`, `Kernel`, `List`, `Map`, `MerkleTree`, and `Set`.

The implementations of the ledger-state types are written in a domain-specific language,
and the implementations are built in to the Compact compiler itself.
Currently, the only way then to add a new ledger-state type or extend an existing one is to modify the Compact compiler.
If a contract[footnote about libraries] needs to use a custom ledger-state type, there are two ways to achieve that.

**Convince the Minokawa project maintainers to accept a contract-specific modification to the standard library.**
This is highly undesirable for the Minokawa maintainers.

By accepting an implementation into the standard library, the maintainers are agreeing that they will assume all the maintenance burdens and all the risks, indefinitely.
The maintainers should then have some standard for the "usefulness" and "quality" of an implementation,
which will lead to them having to make contract-specific decisions about which implementations to accept.
The standard library will grow to include a number of contract-specific ledger-state types which
will create a confusing situation for users to know what is available, how to use it, and exactly how it behaves.
There is no good way for the maintainers to know if any contract is still using a standard library feature, so there's no good way to ever remove contract-specific ledger-state types.

**Fork the compiler, or at least the standard library.**
This is highly undesirable for **both** the Minokawa maintainers and contract developers.

The contract developer is accepting the burden of maintaining a fork of all or part of the Compact compiler,
which they will have to keep in sync with official implementation.
The number of forks will proliferate and the quality of compiler forks will be inconsistent.
This will still create a confusing situation for users to know what is already available, how to use it, and exactly how it behaves.

**The Next 700 Ledger-state Types.**
Neither of these approaches is satisfying.
This CoIP proposes a way for a contract or library to define its own custom ledger-state types.(footnote the next 700 programming languages somehow)

### Public Transcripts and the Impact Virtual Machine

Midnight Network transactions contain a public transcript describing the contract public-state updates for the transaction.
More specifically, the transaction contains a **zero-knowledge (ZK) proof** and a vector of **public inputs**.
The public inputs represent the public transcript.
If the ZK proof and the public inputs are verified by the blockchain, then the blockchain can apply the public transcript to the public state to perform the public state updates.

The public transcript is represented as a program in a restricted domain-specific language called
[**Impact**](https://github.com/midnightntwrk/midnight-ledger/blob/ledger-10/spec/impact-opcodes.md).
Impact programs are executed by the **Impact Virtual Machine (VM)**, a stack-based VM for performing function (non-destructive) public state updates.
Impact programs are therefore a form of a "diff" between public states, and executing the program has the effect of "applying" the diff.
One of the goals of Impact is to minimize read/write contention between transactions.
The Impact `popeq` ("pop equal") instruction pops a value from the Impact stack and will fail during execution if the value is different from the expected one contained in the Impact program.
In this way, Impact execution can detect public-state mismatches.
Impact programs do not otherwise fail due to contention between transactions,
specifically intermediate computed values are not required to match exactly.(Can we rephrase this so it doesn't mention popeq specifically?)

### Standard Library Ledger-state Type Implementations

Compact ledger-state types are defined in the Compact standard library.
They are implemented by hand-written Impact code in
[compiler/midnight-ledger.ss](https://github.com/LFDT-Minokawa/compact/blob/main/compiler/midnight-ledger.ss).
This code is written in an embedded domain-specific language (DSL) defined by Scheme macros.

Importantly, the Compact compiler **does not** generate Impact code from a higher-level representation.
Impact code is simply hand-written in the standard library implementation which is built into the compiler.
For the compiler's JavaScript (JS) target, this Impact code is "assembled" JS calls to the so-called on-chain runtime,
which contains an embedded (off-chain) implementation of the Impact VM.
For the compiler's ZKIR target, this Impact code appears in the ZKIR circuit as public inputs.

### Custom Ledger-state Types

This CoIP proposes to add custom ledger-state types to Compact.
A contract or a library can include its own implementation of a ledger-state type.
To illustrate the idea, we show how a custom ledger-state type could be used to replace the built-in implementation of the `Counter` ledger-state type.

#### Ledger Cells

A [`Cell`](https://docs.midnight.network/compact/reference/ledger-adt#cellvalue_type)
in the ledger contains a Compact value.
Cells are implicit, the declaration `ledger c: T`, where `T` is a Compact type, implicitly introduces a cell containing a Compact value of type `T`.
Cells are initiliazed to the default value of their type, and they support `read`, `resetToDefault`, `write`, and `writeCoin` operations.
(`writeCoin` is **only** available when the Compact type `T` is `QualifiedShieldedCoinInfo`).

A cell storing a numeric value could be used as a counter.  For instance, a contract could declare:

```compact
ledger count: Cell<Uint<64>>;

export circuit incrementCount(amount: Uint<16>): [] {
  count.write(disclose(count.read() + amount as Uint<64>));
}
```

There is dedicated shorthand Compact syntax for the cell's `read` and `write` operations, but they are written out here for clarity.

This implementation contains a read/write contention hazard.
A transaction that calls `incrementCount` will call the read `read` on the cell, and this `read` requires the exact same value to be observed on-chain as was observed off-chain and placed into the proof's public input vector.
Therefore, if a pair of transactions each try to increment the counter starting from the same current public state, the first transaction to be accepted by the blockchain will succeed and write to the cell, while the second transaction will fail due to a public state mismatch on chain.

The standard library contains a `Counter` type that implements this `Uint<64>` cell type with non-contentive increment and decrement operations.
We show how this type could be replaced by a custom ledger-state type declaration.

#### Ledger-state Type Declarations

A contract can define a custom ledger-state type based on a ledger cell.
The keywords `ledger struct` are used to declare such a type
(both `ledger` and `struct` are already reserved words in Compact).
Compact code can be used to expose operations on the underlying cell:

```compact
ledger struct Counter {
  ledger c: Uint<64>;
  
  function read(): Uint<64> {
    return c.read();
  }
  
  function resetToDefault(): [] {
    c.resetToDefault();
  }
}
```

A `ledger struct` declaration is like a Compact `struct` declaration,
except that it introduces a new ledger-state type instead of a Compact structure type.

The body of a `ledger struct` declaration can declare ledger fields via `ledger` declarations.
For example, `Counter` above contains a single ledger cell.
Every `Counter` declared in the ledger introduces a fresh cell for that `Counter`.
The name `c` is in scope in the body of the `ledger struct` definition, but not outside of it.
A `Counter` does not give direct access to the underlying ledger cell.
Instead, operations on `Counter`, like `read` and `resetToDefault`, can have Compact code that redirects to the underlying ledger cell.
Operations are declared with the keyword `function`, which is already a reserved word in Compact.

### Inline Impact Code

The standard library's builtin `Counter` type has an `increment` operation that adds an
unsigned integer to the counter without observing (and thus committing) to the value off chain.
The hand-written Impact implementation in the standard library is this:

```scheme
(function update increment ([amount Uint16]) Void
  "Increments the counter by the given amount."
  ((idx [cached f-cached] [pushPath #t] [path f])
   (addi [immediate (rt-value->int amount)])
   (ins [cached #t] [n (length f)])))
```

Ever ledger operation is executed on the Impact VM with the VM's stack containing 
a **context** object, an **effects** object, and a **state** object.
The ledger operation can return a value (`increment` returns no value)
by ending with a `popeq` instruction, the returned value is the one popped from the VM's stack.
The operation should end with only three elements on the VM's stack: the context
(which is ignored after the operation, it is an input-only parameter to the operation),
a possibly new effects object, and a possibly new state object which are used as outputs
from the operation.

In the implementation above, the first instruction is `idxp` (`p` is the "push path" variant of `idx`).
This operation has an operand which is a **path** in the ledger giving the location of a `Counter`.
It consumes the top of stack value (the state in this case) and leaves a path and a value on the stack.
The path is aleft on the stack because this is `idxp` instead of `idx`.
The path is a sequence of stack elements which can be used to update the state.
After the `idxp` instruction, the stack contains the context, effects, the path to the counter in the ledger state, and the counter's value.
The second instruction `addi` has an operand that is an immediate unsigned integer value.
It consumes the value on top of the stack, and adds the operand to it, leaving the result on top of the stack.
After the `addi` instruction, the stack contains the context, effects, the path to the counter in the ledger state, and the incremented value.
The third instruction `insc` (`c` is the "cached" variant of `ins`) will insert the top of stack value
into the path under the top of stack.
It has an operand `n` which is the length of the path.
It will consume `n` plus one values from the stack, and produce a new updated state value.
After the `insc` instruction, the stack contains context, effects, and an updated state value.

Writing Impact code by hand is **hard**, due to its nature as a stack machine.
Programmers need to keep track of which values are on the stack in which order.
Comments showing the stack can help, but they are not checked for correctness.
It is easy to introduce errors due to extra values on the stack,
missing values on the stack, or the order of values on the stack.

#### Register Impact

This CoIP proposes a way that programmers can write inline **register Impact** code for a
virtual register machine
with an instruction set derived from Impact's in a systematic way.
The Compact compiler will tranform register Impact into (stack) Impact in a straightforward and
predictable way.

Inline (register) Impact code is written in `impact` block expressions.
An `impact` block has a body in braces.
The body is a comma separated sequence of strings with an optional trailing comma.
They are strings to signal that they are not Compact code and that they are parsed by their own parser according to their own grammar.

To support references to Compact expressions in scope, we introduce **template (string) literals**
a la JavaScript, along with **string interpolation** for Compact expressions in template literals.
Template literals are enclosed in backticks.
String interpolation expressions are introduced with a dollar sign and enclosed in braces.
The interpretation of Compact expressions appearing in interpolation expressions is defined below.

Template literals can **only** appear in Impact block expressions, they are not Compact expressions.

Register Impact has most of the same instructions as Impact, with the following changes (because there is no stack):

1. There is an unbounded number of named registers, programmers can freely introduce new register names.
2. Registers can contain Impact values or ledger paths.
3. There are builtin reserved registers `context`, `effects`, and `state`.
4. Input operands are always explicit, either a register name or an interpolated Compact expression.
5. Output operands are always explicit named registers, instructions can have multiple outputs.
6. There are no stack manipulation instructions like `pop`, `popeq`, `push`, `dup`, or `swap`.  They are unnecessary.
7. There is a `ret` ("return") instruction that can give a value for the inline Impact expression.  This actus like (stack) Impact's `popeq` instruction.  An inline Impact block with a `ret` instruction evaluates to the empty tuple value `[]`.

Without going into more explicit detail, we can write this in our `ledger strct` declaration:

```compact
ledger struct Counter {
  ledger c: Uint<64>;
  
  function increment(amount: Uint<16>): [] {
    impact {
      `val, path* := idxp state ${c}`,
      `newVal := addi val ${amount}`,
      `insc path* newVal`,
    }
  }
```

## Specification

`ledger struct` declarations

`ledger` fields

`function` operations with Compact signatures

`impact` block expressions

- contain a comma-separated sequence of strings
- string interpolation (what is the JS term for it?) for Compact values

Register impact:
- register assignments
- special registers for state, context, and effects
- instructions are the non-administrative Impact instructions
- inputs and results are named
- labels or explicit if/then?
- ret (for "popeq")

- Translation to stack Impact
- Type-directed translation of Compact expressions.  They cannot refer to registers so
  they can all be evaluated before the Impact code (unless they are conditional?).

Describe the proposed solution in sufficient technical detail that it could be
implemented.  The intended behavior should be clearly described and unambiguous.

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

