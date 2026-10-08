---
CoIP: 4
Title: Dynamic Selection of Implementation for Cross-Contract Calls
Authors:
  - Joseph Denman (JosephDenman)
  - Jonathan Sobel (jonathan-sobel)
Status: Draft
Category: Language
Created: 2026-07-17
Requires: CoIP 2
Replaces: None, but updates CoIP 2, removing a limitation
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

One of the major limitations of [CoIP 2](./coip-0002.md) is that,
for each contract type defined in a Compact program, the application
running the program is able to provide only a single file containing
the circuit definitions for the type.

This proposal removes that limitation, enabling Compact programs to
execute different circuit code for each *contract value*, rather than
fixing a single implementation for each *contract type*.

## Motivation

<!--
Clearly explain the problem and why the existing Compact language and tooling is
inadequate to address the problem.
-->

[CoIP 2](./coip-0002.md) proposed the addition of contract types and
values to Compact, as well as the ability for one contract to call
circuits in another contract.  For example, suppose
1. A Compact program defines a contract type `T` which includes a
 circuit `c`.
2. A circuit `f` in the program has access to a value `v` of type `T`,
   either as a circuit parameter or in a ledger field.
3. The code in `f` calls `v.c(...)` with appropriate arguments.

Here is a Compact fragment that illustrates this scenario:
```compact
contract T {
  circuit c(n: Uint<64>): [];
}

export circuit f(v: T, arg:Uint<64>): [] {
  v.c(arg);
}
```

Calling `c` from `f` is described as a *cross-contract call*.

As part of the execution of `f`, it is necessary to execute code for
`c`, but what code?  The definition of `T` in the program declares the
existence of a circuit `c`, but different contracts satisfying `T` can
have different implementations of `c`.  When `f` makes the call to
`c`, where does it find the code for `c`?

[CoIP 2](./coip-0002.md) proposed an initial answer: the application
that uses the contract and calls `f` must also provide the code for
`c`.  In fact, as of this writing, when the Compact compiler generates
code for `f`, the generated code imports `../T/contract/index.js` to
find the code for `T`'s circuits.  This is a file that would be
produced by compiling a Compact program `T.compact` and placing the
outputs alongside those of the application calling `f`.

That initial design limits an application to a single implementation
of each contract type.

Now suppose the program defines a ledger field of type `Vector<3, T>`.
Then, it populates the field with three different contract values:
`v1`, `v2`, and `v3`.  Each is a contract exporting a circuit `c` (and
any other circuits required by the definition of `T`), but each is
from a completely different Compact program, with different logic for
`c` in the different programs.  Under the limitations of CoIP 2, it is
*impossible* for a circuit such as `f` to call `c` on each of the
values in this vector and run the distinct logic of each
implementation of `c`, even if the calling application has access to
the source code or compilation outputs for all three programs.  The
sole implementation of `c` that will be executed is the one present in
`../T/contract/index.js`.

This shortcoming is the first of
[the enumerated limitations of CoIP 2](./coip-0002.md#limitations).
The current proposal calls for removing that first limitation, eliminating
this deficiency in the flexibility of cross-contract calls.

## Specification

<!--
Describe the proposed solution in sufficient technical detail that it could be
implemented.  The intended behavior should be clearly described and unambiguous.
-->

All contract values of a certain contract type `T` are expected to
export circuits with certain signatures, but each individual contract
value of type `T` may have its own implementation of those circuits.
This proposal does not call for a common or standardized registry of
implementations.  Rather, it requires the existence of a framework
allowing each application to supply its own registry, mapping contract
values to implementations.  What the application supplies could be as
simple as a static map or as complex as a dynamic resolution system
that reaches out across the network to a public registry of contract
implementations.

### The Module Type

The TypeScript type at the heart of this proposal is `Module`.  A
`Module` object represents the loaded code for a contract.  It holds
functions and values that enable a caller to construct all the state
necessary for invoking a contract's circuits.

For example, the Motivation section pointed out that the
generated code for a cross-contract call to one of `T`'s circuits
directly imports `../T/contract/index.js` to gain access to the
code for `T`.  (That is, it does so prior to this improvement
proposal.)  It is now proposed that importing the same file should
yield a `Module` for `T`.  More precisely, it yields a `Promise` for a
`Module` for `T`:
```typescript
const tModule: Promise<Module> = import('../T/contract/index.js');
```

`Module` is the fundamental type needed to separate cross-contract
calls from directly loaded code.  If this proposal is accepted, the
code that the Compact compiler generates for cross-contract calls must
use the values in a `Module` to set up and execute that call, and the
`Module` type must be defined so that it provides everything necessary
to execute the call.

### Resolving Contract Values: The Module Provider

What remains is to make it possible for an application to supply a
means of resolving contract values to `Module` values.  To that end,
the Compact runtime must define an interface for the resolver:
`ContractModuleProvider`.  This is a simple interface, supplying a
single function `resolve`:
```typescript
type ModuleThunk = () => Promise<Module>;

interface ContractModuleProvider {
  resolve(calleeAddress: ocrt.ContractAddress): ModuleThunk | undefined;
}
```
where the `ContractAddress` type is defined by the Midnight on-chain
runtime libraries.

The generated code for a cross-contract call relies on the
availability of a `ContractModuleProvider` (along with other providers
already required, such as the one that provides access to contract
state).  The call handler uses the provider's implementation of
`resolve` to get a `Module` for the callee's address, and the call is
executed using the contents of the `Module`.  The semantics and
implementation of the call's execution, after resolution and error
checking, should be the same as what was provided by CoIP 2.

While it is beyond the scope of this proposal to require additions to
application frameworks, it is expected that existing libraries which
support Midnight application development will make simple
implementations of `ContractModuleProvider` available.  For example, a
developer might expect to be able to create a module provider by
supplying a static map from `ContractAddress` to `ModuleThunk`.  On
the other hand, `resolve` could also be implemented in a more
sophisticated way, using a combination of static information about
Compact programs and dynamic information—perhaps even derived from
Midnight on-chain state—about which addresses represent deployments
of which contracts.

### Error Checking

The Compact compiler already checks cross-contract calls to verify
that a call's arguments match the signature of the declared contract
type and that the call's context is able to handle the declared return type of
the circuit.  It is generally impossible to know statically, though,
whether any particular contract *value* satisfies a contract type.

Fortunately, much of the dynamic checking already performed by the
Compact runtime when an application uses a contract address to *join*
an existing contract (that is, it begins to use an already-deployed
contract) should be reusable for checking aspects of
a cross-contract call's validity.  For example, *every* circuit call
requires the verifier key associated with the callee's code to match
the one registered on-chain with the deployed contract.  By including
the verifier keys for each circuit in a loaded `Module`, the same
checking can be accomplished for cross-contract calls.

In addition, some kinds of dynamic failures are specific to
cross-contract calls or even the nature of this proposal.  The
Compact runtime implementation should check and report the following
kinds of failures:
- `ModuleProviderAbsent`: The application failed to make a
  `ContractModuleProvider` available to the call context.
- `OperationAbsent`: The deployed contract has no circuit with the
  required name (or none exported, or none with a verifier key).
- `UnsupportedImplementation`: The `ContractModuleProvider` is unable
  to provide an implementation for the given contract value.
- `ProviderThrew`: The `ContractModuleProvider` threw an exception
  while trying to resolve the address to an implementation.  Note that
  this is different from having no mapping for the address (which is
  `UnsupportedImplementation`).
- `NonconformantImplementation`: `resolve` returned a module that
  does not implement the required contract type.
- `UnreadableModule`: The module (most likely, its circuit
  signatures) depend on types that are not available in the runtime or
  application, so the it cannot be loaded.
- `MalformedVerifierKeyHash`: The supposed verifier key hash, included
  in the loaded module, is not really a verifier key hash.  This is
  likely a problem with the module's build.
- `ImplementationMismatch`: The verifier key hash loaded from the
  module does not match the deployed one for the called circuit.
- `ModuleLoadRejected`: `resolve` returned a `ModuleThunk` that, when
  invoked, produced a promise that was rejected.
- `IncompleteModule`: The code represented by the resolved module was
  generated prior to the updates associated with this proposal, and it
  is missing some of the necessary content.
  
It is recommended that all these kinds of failures carry payloads that
will be useful to application developers.  The
`NonconformantImplementation` error, in particular, should be able to
report what kind of mismatch it represents: incorrect argument count,
parameter type mismatch, different return type, etc.

## Rationale

<!-- Explain the design decisions that were made and the reasons
behind them.  -->

The major design question for this proposal has been how to balance
the need for dynamism with the desire to limit the scope of the design
change.  The goal has been to provide a mechanism that is able to
support code of the sort that appears in the Motivation section,
without requiring any changes to Midnight systems other than the
Compact compiler.  Specifically, it has been a non-goal to *require*
any kind of external registry for contract code at this point.  Given
this constraint, the application initiating a call into a contract
must be the actor to provide the mapping from contract values (assumed
to be distinguished by their deployment addresses on chain) to
executable code.

On the other hand, saying that an application must "provide" the
mapping should not limit the application in a way that prevents it
from using an external contract code registry.  Thus, the `resolve`
pathway is quite flexible and could be implemented to perform
arbitrary amounts of computation and network access to produce the
`Module` for a contract value.

While such complex deployments should be possible, we do not want to
require them.  A simple application that uses a closed, statically
known set of contract values for all its cross-contract calls should
still be able to produce a static map from values to code easily.  By
requiring the Compact compiler to produce for each Compact program a
file that yields a `Module` when imported, the values in such a static
map (i.e., the "right-hand sides") can be produced by a sequence of
`import` expressions in TypeScript.

## Backwards Compatibility

<!--
Describe how the proposed solution affects existing systems, applications, and
users.  Is it a breaking change?
-->

Compact programs without cross-contract calls will be unaffected by
the acceptance of this proposal.  Existing compiled Compact programs,
as long as they are not recompiled, should also be unaffected.

If a Compact program containing cross-contract calls is recompiled,
some changes to the calling application will be necessary.  To yield
behavior equivalent to that of CoIP 2, an application must supply a
`ContractModuleProvider` that resolves all contract values of type `T`
to the `Module` produced by importing `../T/contract/index.js` and
likewise for every contract type.

It is expected, though, that most Compact applications would choose to
avail themselves of the benefits of this new proposal and supply a
`ContractModuleProvider` that resolves each contract value to an
implementation associated with that specific value, no longer
collapsing all the values to the same implementation.

## Security Implications

<!--
Analyze the potential security implications of the proposed change.  Are there
any new attack vectors or vulnerabilities introduced?  How will they be
mitigated.
-->

Because the implementation of `resolve` is left to the application,
each application can be as closed or open as it desires.  If an
application chooses to use external sources for the implementations of
some contract values, it would be running JavaScript code supplied by
those sources.  In such a scenario, it would likely be desirable to
impose some kind of "sandboxing," but the details of such limited
execution spaces are currently beyond the scope of this improvement
proposal.

## How to Teach This

<!--
Explain how to teach users, including both new and experienced ones, how to use
the CoIP in their own work.
-->

We assume that Compact application frameworks will supply simple
map-backed implementations of `ContractModuleProvider`.  The most
direct way to teach programmers how to use the new dynamic dispatch
capabilities would be to begin with the sort of simple code that
appears in the Motivation section, along with two or three
concrete implementations of `T`.  Then, demonstrate the fact that
calling `f` with different contract values produces different
behaviors.

## Implementation

<!--
Discuss how the proposed change could be implemented.  What parts of the Compact
toolchain or the blockchain environment will need to be modified?  What are the
dependencies, if any?

Provide a link to a reference implementation, if there is one, and describe any
limitations.
-->

As of this writing, an initial implementation of this proposal has
already been incorporated in the latest version of the Compact
compiler.

## Rejected Ideas

<!--
Describe other ideas that were considered and explain why they were ultimately
not adopted.
-->

Solutions with a larger scope of change have been rejected.  For
example, it has been proposed that a canonical implementation for each
contract could be stored in the Midnight blockchain when the contract
is deployed.  Then, when a cross-contract call is made to some circuit
in the contract, its code could be loaded from the blockchain and
executed locally.

Two main problems arise from this idea.
1. In the absence of some new standardized representation of compiled
   contracts, the code to be stored and downloaded would be
   JavaScript.  Requiring the code to be signed would guarantee that
   it had not been tampered with, but it would not guarantee that the
   code is safe.  Running downloaded JavaScript in the same execution
   environment as the calling application, with full access to the
   application's secrets, would be unacceptable.
2. In order to isolate each downloaded contract implementation from
   the others, some kind of per-contract execution environment could
   be developed.  Several "sandboxed JavaScript" projects do exist,
   but was beyond the scope of this proposal to require integration
   with one.  Furthermore, a more complete solution to the problem of
   isolating contracting execution will be required in order to
   provide cross-contract calls to contracts with private state, a
   limitation not eliminated by the current proposal.  It seems
   premature to require some kind of isolation for this proposal, when
   the chosen mechanisms might still be inadequate for the needs of a
   successor proposal.
   
For these reasons, the idea of requiring blockchain-integrated storage
for contract implementations has been rejected as a solution to the
needs articulated in the Motivation section.

<!--
## References

Link to relevant related work, such as research papers or similar features in
other contexts.
-->

## Acknowledgments

<!--
Acknowledge non-authors who helped with the CoIP.
-->

Joseph Denman has been the lead programmer implementing the ideas
described in this proposal, which means that the proposal is largely
documenting his ideas and implementation.  The whole Compact compiler
team has been active in the ongoing conversations about cross-contract
calls, especially Kent Dybvig and Kevin Millikin.  Thanks also to
Karmel Elshinnawi at the Midnight Foundation for facilitating
conversations with potential users of this new feature; their feedback
has been valuable in guiding the design.

## Copyright

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Footnotes

<!--
If necessary, include footnotes in the CoIP text using GitHub's footnote
syntax[^1].  Keep the footnote heading at the bottom of the document.

[^1]: See the [GitHub Markdown guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#footnotes).
-->
