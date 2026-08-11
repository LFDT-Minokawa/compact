---
CoIP: X
Title: Multi-environment support in Compact
Authors:
  - Parisa Ataei
Status: Draft
Category: see CoIP Categories in CoIP-1
Created: 2026-08-04
Requires: -
Replaces: -
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

Compact currently supports a single ledger (in reality zkir and onchain-runtime)
version. However, the instance has arised that different networks are using
different versions of ledger at a single point in time. E.g., mainnet uses
ledger-8 whereas preview has moved on to ledger-9.

Currently, this either requires maintaining multiple versions of Compact in parallel
or Compact has to support multiple backend ledgers. This Coip advocates for the latter.

## Motivation

A single version of Compact currently supports a single version of ledger
This limitation significantly increases effort in releasing (currently, Compact
uses a single release channel) and maintaining
multiple versions of Compact as multiple networks use different versions of
the ledger. Consequently, it transfers the burden of choosing the correct version
of Compact for each network to the user.

## Specification

Potentially Compact could support multiple backend ledgers and a flag can choose
the specific version of the ledger that must be used to compile a contract. Thus,
a single release branch would still suffice.
For example, `compact --ledger=9.0 <input.compact> <output-dir>`. In this example,
the Compact compiler should be able to pick the correct backend passes for 
ledger 9.0 and the generated TypeScript code must use functions from a version 
of compact runtime that are compatible with ledger 9.0. The detailed techenical
details are given in Implementation section.

Describe the proposed solution in sufficient technical detail that it could be
implemented.  The intended behavior should be clearly described and unambiguous.

## Rationale

A handfull of compiler passes rely on the ledger. Thus, these can be duplicated
in a subdirectory for each supported version of ledger. These files/subdirectories
are:
- `compiler/typescript-passes.ss` and `compiler/typescript-passes`
- `compiler/zkir-passes.ss` and `compiler/zkir-passes`
- `compiler/midnight-ledger.ss`
- `compiler/midnight-natives.ss`

These can be moved to `compiler/backends/ledger-9.0` and `compiler/backends/ledger-8.2`
to support ledger 9.0 and 8.2, respectively. These backend subdirectories live as long
as there exists a network that supports that specific version of ledger, that is, upon
the promotion of all networks (this is not at the same time and it will be over a span
of multiple weeks to months) from ledger 8.2 the `compiler/backend/ledger-8.2` is 
dropped. Similarly, a backend subdirectory is created when the Compact TSC has recieved
and approved a request for a backend support with a timeline of when a network will be
promoted to that specific version of ledger.

The Compact runtime also relies on the ledger. 
to be completed

The Compact developer tool is the main way for users to interact with Compact. Thus,
while the Compact compiler uses a flag for the backend ledger, the dev tool should
surface the network to the user through a flag and then use a compatibility matrix to
pass the correct corresponding ledger version to the Compact compiler to compile a
given contract. For example, `compact --network=mainnet compile ...` finds the ledger
that mainnet relies on at the moment and then runs `compactc --ledger=x.y ...`. 

This design modulates what the user needs to know, that is, the
average user doesn't need to know the underlying ledger version of the network
they plan to deploy their contract on it. At the same time, a more sophisticated
user can simply pass the ledger flag, e.g., `compact compile --ledger=x.y ...`.
In case both flags are passed (`compact --network=mainnet compile --ledger=x.y ...`)
the user will get an error if the two flags are incompatible, otherwise,
their contract will be compiled with `ledger x.y` backend of Compact compiler.

Explain the design decisions that were made and the reasons behind them.

## Backwards Compatibility

This is not a breaking change. When a user upgrades to a version of Compact
that supports multiple backend ledgers, they just need to pass the flag 
`--ledger=<version>` to Compact to compile their contract with a version of
Compact that uses version `<version>` of ledger.

## Security Implications

If a security vulnerability is found in passes that are duplicated, the fix must
be applied to all currently supported backends, making Compact more vulnerable.

## How to Teach This

Users simply need to add a feature flag to compile their contract. 
Generally, before they used to `compact <input.compact> <output-dir>` or
`compact compile <input.compact> <output-dir>` and
now they need to `compact --ledger=9.0 <input.compact> <output-dir` or
`compact --network=a compile <input.compact> <output-dir>`, respectively. 
If they're passing any other flags they can continue doing so as long as
the flags are compatible.

## Implementation

### Compiler

The Compact compiler duplicates the passes that rely on the ledger into and 
moves them to `compiler/backend/ledger-x.y` for each supported version `x.y`
of ledger. 

Percieved changes:
- `flake.nix` requires an input per version of supported `onchain-runtime`
  and `zkir`
- 


### Runtime

to be completed.

### Developer tool

to be completed.

Discuss how the proposed change could be implemented.  What parts of the Compact
toolchain or the blockchain environment will need to be modified?  What are the
dependencies, if any?

Provide a link to a reference implementation, if there is one, and describe any
limitations.

## Rejected Ideas

### Multiple release branches

Compact could potentially use a branch per network for its releases. 
However, this approach still puts the burden of choosing the correct version
of Compact on the user. Furthermore, it is burdonsome to maintain and release.
Consider a patch release for a bug. The Compact maintainers must then cut three
releases. 

### A single Compact runtime


## Open questions

- Will `onchain-runtime` always be released with a suffix of its major version?
- promotion timeline of networks
- STL might cut only release candidates 

## References

- https://github.com/midnightntwrk/midnight-architecture/pull/183: this provides 
  more details on Compact release process and Midnight networks and how they impact
  the ideas for this problem.

## Acknowledgements

- Kevin Millkin

## Copyright

All contributions submitted in this CoIP must be licenced under the Apache
License, version 2.0.  Include the paragraph below.

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Footnotes

If necessary, include footnotes in the CoIP text using GitHub's footnote
syntax[^1].  Keep the footnote heading at the bottom of the document.

[^1]: See the [GitHub Markdown guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#footnotes).

