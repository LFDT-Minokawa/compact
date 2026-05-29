---
CoIP: X
Title: Contract Interfaces, References, and Calls
Authors:
  - Jonathan Sobel (jonathan-sobel)
Status: Draft
Category: Language
Created: 2026-05-27
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

<!--
The abstract is a short (about 200 word) description of the issue being
addressed and the proposed solution.
-->

In order to support the creation of multiple smart contracts that work
together as a system, along with decentralized applications that use
them, three major new features are added to Compact:
1. contract interface types
2. contract references in circuit parameters and ledger state fields
3. calls within a circuit to another contract's circuits

This set of changes is intended as the first in a sequence of
improvements that lead towards rich support for multi-contract
systems.  Later proposals will address dynamic discovery of contract
implementation code and management of private state across contracts.

## Motivation

<!--
Clearly explain the problem and why the existing Compact language and tooling is
inadequate to address the problem.
-->

Smart contracts are an integral part of the Midnight blockchain.
Midnight provides the Compact language for defining contracts, and it
uses zero-knowledge proofs to enable parts of a contract's execution
to remain undisclosed.

At the launch of Midnight's mainnet, it was already possible to write
smart contracts in Compact and to create one or more decentralized
applications (DApps) for any contract.  It was not possible, however,
to create *multiple contracts that work together as a system*, with
contracts holding references to other contracts in their ledger state
and with circuits in one contract calling the circuits of other
contracts.

This proposal describes new functionality to be added to Compact,
enabling such multi-contract systems.  The main new features are:

1. contract interface types: a collection of circuit signatures (that
   is, their names, parameter types, and return types) on which some
   other contract may depend,
2. contract references in the public ledger state: contracts may hold
   references to other contracts, and
3. cross-contract calls: circuits in one contract can invoke the
   circuits of another contract.

These features work together.  The contract references in the ledger
are described by contract interface types, and the cross-contract
calls are to circuits named in those interfaces.

One may imagine a future version of Compact having quite rich support
for multi-contract systems, with dynamic discovery of the actual
circuit code that implements an interface and with support for witness
functions and private state in called circuits.  This proposal
describes only the first step in that direction.

Specifically, two major limitations are incorporated into this first
proposal for multi-contract system support:

1. An interface named `T` can be implemented only by a contract
   defined in the file `T.compact`.  That is, the code for a contract
   that implements interface `T` may be dynamically loaded, but it
   will be found by assuming that the code for concrete contract `T`
   is already made available by the DApp.
2. Contracts to be called by other contracts must not define witness
   functions.  That is, cross-contract calls can be made only to
   contracts with no private state.

It is hoped that a future Compact improvement proposal might lift
these restrictions by introducing a means for discovering circuit code
dynamically and some system for multi-contract private state
management.  Even this first stage of delivery, though, will enable
the creation of useful multi-contract systems.

## Specification

<!--
Describe the proposed solution in sufficient technical detail that it could be
implemented.  The intended behavior should be clearly described and unambiguous.
-->

### Contract Interfaces

A new form is added to Compact's program elements: the contract
interface declaration.  Here is an example.

```compact
interface Adder {
  circuit setAddAmount(n: Uint<64>): [];
  circuit addTo(n: Uint<64>): Uint<64>;
}
```

The Compact grammar already includes a production for "external
contract declaration."  This is replaced by a production for
"interface declaration."  The only syntactic change is the use of the
keyword `interface` in place of `contract`.  For clarity in the
grammar, the production's nonterminal should be renamed from
_contract-declaration_ to _interface-declaration_, and the identifier
for the interface should be renamed from _contract-name_ to
_interface-name_.  Also, _interface-name_ should be added as an alias

Thus, the production _interface-declaration_ looks like

> `export`^opt `interface` _interface-name_ `{` _circuit-declaration_ `;` ... `;` _circuit-declaration_  `;`^opt `}` `;`^opt

and likewise for the comma-separated version.  Note that
_circuit-declaration_ is defined to require a "simple" parameter
list.  The circuits in contract interfaces must not have generic
parameters.

Any contract whose set of exported circuits is a superset of the
circuits declared in an interface is said to **implement** that
interface.  For example, any contract that exports `setAddAmount` and
`addTo` methods with the signatures above implements the `Adder`
interface.  This is true regardless of whether the contract declares
any intention to implement the interface.  In other words, interface
implementation is structural, not nominal.

On the other hand, when a contract is intended to implement some
interface, it is useful to assert that expectation.  This is
accomplished with a new program element to assert that the current
contract implements a specific interface.  Here is an example.

```
contract implements Adder;
```

This declaration applies to the contract being defined in the current
scope.  A contract may be declared to implement several different
interfaces by including multiple `contract implements` declarations.

The addition of the `contract implements` form requires a new
program-element production in the Compact grammar:

> _implements-assertion_ &rarr; `contract implements` _interface-name_ `;`

To reiterate what was previously stated, a contract implements an
interface by exporting definitions for all the interface's declared
circuits, no matter whether a `contract implements` declaration
appears in the code.  If such a declaration _is_ present, though, then
the compiler will verify it and reject the program with a compile-time
error if the contract fails to export the circuits required by the
interface.

### Contract References

An `interface` declaration introduces a new contract type into its
scope.  A contract type is a regular program-defined Compact type,
just like a structure type or enumeration type.  For example, it can
be used as the type of a circuit or witness function parameter, the
type of a structure element, or the specializing argument of a
ledger-state type such as `List` or `Map`.  Here is an example of a
ledger declaration using the `Adder` interface and a constructor that
initializes it.

```compact
export ledger adders: List<Adder>;

constructor(a: Adder) {
  adders.pushFront(disclose(a));
}
```

A contract type represents the set of deployed contracts that satisfy
the corresponding contract interface.  This induces a subtype
relationship on contract types.  If the circuits declared in interface
`B` are a superset of those declared in interface `A`, then contract
type `B` is a subtype of contract type `A`.  A contract type can
therefore be a subtype of many disjoint supertypes.  The least upper
bound of a pair of contract types is the intersection of their
declared circuits, which may be empty.  (The empty interface is
useless, but valid.)  Also, any pair of contract types has a greatest
lower bound: the union of their declared circuits.

No mechanism is provided by this proposal to *create* values with
contract types.  Instead, the surrounding context (that is, the
application code) introduces a contract reference by calling a circuit
or constructor with the address of a deployed contract or by returning
a the address of a deployed contract from a witness function.

Because a contract reference is implemented by a contract address,
whose value comes from outside the safe realm of Compact's type
system, dynamic checks are necessary to guarantee that the denoted
value truly implements the contract type's interface.  This proposal
does not specify exactly where these dynamic checks must occur; it
only requires that type safety be preserved by the system.

No new grammar productions are necessary to support contract types and
references to contract values, because they occupy the same
grammatical classes other program-defined types and references to
their values.

### Cross-Contract Calls

The main use for holding a reference to a contract with a known
interface is to call the circuits named in that interface.  Here is an
example of a circuit calling one of the `Adder` interface's circuits.

```compact
export circuit setUpDoubleAdd(a: Adder, n: Uint<64>): [] {
  a.setAddAmount(n + n);
}
```

Semantically, a call to another contract's circuit is in the same
category as a call to one of the contract's own circuits.  In the
Compact grammar, however, a cross-contract call is parsed more like a
ledger state operation: the contract reference, followed by a dot
(i.e., a period or full stop), followed by the name of a circuit
declared in the interface of the contract reference's type, followed
by the arguments to the circuit call.

### Limitations

Implementing these improvements, without additional constraints,
would require solutions to several hard problems, such as dynamic
discovery of the circuit code for other contracts.  To make it
possible for this proposal to be implemented prior to such solutions
being available, the following additional limitations are imposed.

1. In order to implement an interface `T`, a contract must be defined
   in the file `T.compact`, and its compilation artifacts must be
   present alongside those of any callers of `T`'s circuits.  More
   precisely, if the Compact implementation defines a search path for
   finding compiler outputs in the code it generates, then the outputs
   of compiling `T.compact` must be able to be found on that search
   path when executing any circuits that make cross-contract calls
   using references of type `T`.  This effectively limits any DApp to
   a single implementation of each interface.
2. A contract that declares witnesses is unable to implement any
   interface.  This implies that every contract reference is to a
   contract with no private state, and every cross-contract call
   produces an empty private-state transcript.

Taken together, these limit Compact's current multi-contract systems
to those in which a "root" contract may declare witnesses and hold
private state, but no others do.  Furthermore, the concrete
implementations of all contracts in the system are known to any DApp
operating over the system.

Many interesting decentralized systems can be created under the
preceding constraints, but the authors hope that future improvement
proposals will supersede this one and reduce or eliminate the need for
these limitations.

## Rationale

<!--
Explain the design decisions that were made and the reasons behind them.
-->

## Backwards Compatibility

<!--
Describe how the proposed solution affects existing systems, applications, and
users.  Is it a breaking change?
-->

## Security Implications

<!--
Analyze the potential security implications of the proposed change.  Are there
any new attack vectors or vulnerabilities introduced?  How will they be
mitigated.
-->

## How to Teach This

<!--
Explain how to teach users, including both new and experienced ones, how to use
the CoIP in their own work.
-->

## Implementation

<!--
Discuss how the proposed change could be implemented.  What parts of the Compact
toolchain or the blockchain environment will need to be modified?  What are the
dependencies, if any?

Provide a link to a reference implementation, if there is one, and describe any
limitations.
-->

## Rejected Ideas

<!--
Describe other ideas that were considered and explain why they were ultimately
not adopted.
-->

## References

<!--
Link to relevant related work, such as research papers or similar features in
other contexts.
-->

## Acknowledgements

<!--
Acknowledge non-authors who helped with the CoIP.
-->

## Copyright

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Footnotes

<!--
If necessary, include footnotes in the CoIP text using GitHub's footnote
syntax[^1].  Keep the footnote heading at the bottom of the document.

[^1]: See the [GitHub Markdown guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#footnotes).
-->

