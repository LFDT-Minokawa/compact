---
CoIP: X
Title: Dynamic Selection of Implementation for Cross-Contract Calls
Authors:
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
of each contract type..

Now suppose the program defines a ledger field of type `Vector<3, T>`.
Then, it populates the field with three different contract values:
`v1`, `v2`, and `v3`.  Each is a contract exporting a circuit `c` (and
any other circuits required by the definition of `T`), but each is
from a completely different Compact program, with different logic for
`c` in the different programs.  It is *impossible* for a circuit such
as `f` to call `c` on each of the values in this vector and run the
distinct logic of each implementation of `c`, even if the calling
application has access to the source code or compilation outputs for
all three programs.  The sole implementation of `c` that will be
executed is the one present in `../T/contract/index.js`.

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
means of resolving contract values to `Modules` values.  To that end,
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
that call's arguments match the signature of the declared contract
type and that the call's context handles the declared return type of
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
cross-contract calls or even this the nature of this proposal.  The
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

To be written.

## Backwards Compatibility

<!--
Describe how the proposed solution affects existing systems, applications, and
users.  Is it a breaking change?
-->

To be written.

## Security Implications

<!--
Analyze the potential security implications of the proposed change.  Are there
any new attack vectors or vulnerabilities introduced?  How will they be
mitigated.
-->

To be written.

## How to Teach This

<!--
Explain how to teach users, including both new and experienced ones, how to use
the CoIP in their own work.
-->

To be written.

## Implementation

<!--
Discuss how the proposed change could be implemented.  What parts of the Compact
toolchain or the blockchain environment will need to be modified?  What are the
dependencies, if any?

Provide a link to a reference implementation, if there is one, and describe any
limitations.
-->

To be written.

## Rejected Ideas

<!--
Describe other ideas that were considered and explain why they were ultimately
not adopted.
-->

To be written.

<!--
## References

Link to relevant related work, such as research papers or similar features in
other contexts.
-->

## Acknowledgments

<!--
Acknowledge non-authors who helped with the CoIP.
-->

To be written.

## Copyright

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Footnotes

<!--
If necessary, include footnotes in the CoIP text using GitHub's footnote
syntax[^1].  Keep the footnote heading at the bottom of the document.

[^1]: See the [GitHub Markdown guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#footnotes).
-->
