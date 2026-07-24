---
CoIP: X
Title: Dynamic Selection of Implementation for Cross-Contract Calls
Authors:
  - Jonathan Sobel (jonathan-sobel)
Status: Draft
Category: Language
Created: 2026-07-17
Requires: [2](./coip-0002.md)
Replaces: None, but updates [2](./coip-0002.md), removing a limitation
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

Calling `c` from `f` is described as a *cross-contract call*.

As part of the execution of `f`, it is necessary to execute code for
`c`, but what code?  The definition of `T` in the program declares the
existence of a circuit `c` in any value of type `T`, but different
contracts satisfying `T` can have different implementations of `c`.
When `f` makes the call to `c`, where does it find the code for `c`?

[CoIP 2](./coip-0002.md) proposed an initial answer: the application
that executes the program and runs the code for `f` must also provide
the code for `c`.  In fact, as of this writing, the Compact compiler
generates code for `f` that, when it makes a cross-contract call to
any circuit declared in the definition of `T`, refers to
`../T/contract/index.js`.  This is a file that would be produced by
compiling a Compact program `T.compact` and placing the outputs
alongside those of the calling program.

That initial design limits a Compact program to a single
implementation of each contract type, the implementation provided by
the calling application context.

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

To be written.

## Rationale

<!--
Explain the design decisions that were made and the reasons behind them.
-->

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
