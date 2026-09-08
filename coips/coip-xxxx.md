---
CoIP: X
Title: Explicit visibility modifiers for ledger fields and circuits
Authors:
  - Iskander Andrews (0xisk), OpenZeppelin
Status: Draft
Category: Language
Created: 2026-06-05
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

Compact uses a single `export` keyword to control two unrelated things: whether a
binding can be imported by another module, and whether a binding appears in the
contract's generated TypeScript API. The two meanings only line up at the top
level. A module's `export` makes a binding importable but never surfaces it in
the generated TypeScript, so a contract that wants to expose imported ledger
state or circuits must re-declare or re-export each one by hand
(`export { M_state };`). In a contract composed from several modules this
re-export list is long, easy to get wrong, and silently wrong when an item is
forgotten: the contract still compiles and runs, but the TypeScript surface is
incomplete.

This CoIP replaces the overloaded `export` with three explicit visibility
modifiers, mirroring Solidity: `private` (module-scoped), `internal`
(importable, not in the TypeScript API), and `public` (importable and emitted to
the TypeScript API). A `public` member of an imported module is surfaced in the
importing contract's generated TypeScript automatically, with no manual
re-export. Visibility becomes opt-in and self-documenting, and the generated
TypeScript can no longer drift from the source by omission.

## Motivation

Compact today has exactly two effective visibility levels, both spelled with the
same keyword:

- **Default (no keyword):** the binding is visible only inside its module. It
  cannot be imported elsewhere and is absent from the generated TypeScript.
- **`export`:** at module scope, the binding becomes *importable* into other
  modules and the top level (`import M prefix M_;`). At the top level, the
  binding becomes part of the contract's *generated TypeScript API* (ledger
  fields appear in the `Ledger` type and `ledger()`, circuits appear in
  `Circuits` / `ImpureCircuits`, types are emitted as TypeScript types).

The problem is that these are two different concerns wearing one keyword, and a
module's `export` only satisfies the first. The language reference is explicit:
"Exporting a binding from a module has no effect unless the module is imported,"
and top-level emission to TypeScript happens only for items "exported at the top
level of a contract (i.e., not merely exported from a module)."

So to expose a module's ledger field or circuit to the off-chain TypeScript
driver, the contract author must restate it at the top level:

```compact
// EXAMPLE 1 - inside module M
module M {
    ledger privateMState: boolean;     // module-private
    export ledger internalMState: boolean;   // importable, but NOT in generated TS

    circuit privateMCircuit(): [] { ... }
    export circuit internalMCircuit(): [] { ... }
}
```

```compact
// EXAMPLE 2 - top level: M's exports are invisible to TS until re-exported
import M prefix M_;

export ledger publicTopState: boolean;

export circuit useMInternalMState(): boolean {
    return M_internalMState;
}

// Required to surface M's items in the generated TypeScript:
export { M_internalMState, M_internalMCircuit };
```

This `export { M_... }` bridge has three failure modes:

- **Verbosity.** A contract composed from four or five modules accumulates a long
  re-export list that duplicates the modules' own intent.
- **Silent omission.** Forgetting an entry does not break compilation or contract
  logic. It only produces an incomplete TypeScript surface, which surfaces much
  later as a missing field or circuit in the dApp or simulator.
- **No middle level.** There is no clean way to say "importable across modules
  but deliberately not part of the public API." `export` always means both
  "importable" and (once re-exported at the top) "public", with nothing in
  between.

The motivation is not contract logic. Visibility never affects on-chain
behavior. It is developer ergonomics and the fidelity of the generated
TypeScript: the artifact most integrators actually program against.

## Specification

### Visibility modifiers

Replace the `export` keyword on ledger and circuit declarations with one of three
visibility modifiers:

| Modifier   | Importable by other modules | Emitted to generated TypeScript |
| ---------- | --------------------------- | ------------------------------- |
| `private`  | no                          | no                              |
| `internal` | yes                         | no                              |
| `public`   | yes                         | yes                             |

A declaration with no modifier defaults to `private`, matching today's default
(see [Rationale](#rationale) for the enforced-vs-default discussion).

```compact
// EXAMPLE 3 - inside module M
module M {
    private  ledger privateMState: boolean;
    internal ledger internalMState: boolean;
    public   ledger publicMState: boolean;

    private  circuit privateMCircuit(): [] { ... }
    internal circuit internalMCircuit(): [] { ... }
    public   circuit publicMCircuit(): [] { ... }
}
```

### Top-level semantics

At the top level of a contract, the modifiers carry the same meaning, with
`public` designating the contract's entry points and TypeScript-visible state:

```compact
// EXAMPLE 4 - top level
import M prefix M_;

private ledger privateTopState: boolean;
public  ledger publicTopState: boolean;

private circuit privateTopCircuit(): [] { ... }

// Public circuits that read internal module state:
public circuit useMInternalMState(): boolean {
    return M_internalMState;
}

public circuit useMInternalCircuit(): [] {
    return M_internalMCircuit();
}
```

`internal` at the top level is permitted but, since nothing imports the top
level, behaves like `private` for the purpose of TypeScript emission. The
existing top-level restrictions are preserved: only circuits, program-defined
types, and ledger fields may be `public`; a `public` circuit must not be generic;
and it is a static error to have two `public` circuits with the same name.

### Transitive public emission

The central behavioral change: a `public` ledger field or circuit declared in a
module is emitted into the generated TypeScript of any contract that (directly or
transitively) imports that module, **without** a manual re-export. Given
EXAMPLE 3 and EXAMPLE 4 above, the compiler emits:

```ts
export type Ledger = {
    publicTopState: boolean;
    M_publicMState: boolean;   // from module M, surfaced automatically
};

export type ImpureCircuits = {
    publicMCircuit: () => ...;        // from module M
    useMInternalMState: () => ...;
    useMInternalCircuit: () => ...;
};
```

Names of surfaced module members follow the import prefix already in scope
(`M_publicMState` under `import M prefix M_;`), so prefix rules are unchanged and
collisions remain a static error exactly as today.

This is **opt-in auto-export**: emission is triggered by the module author
choosing `public`, not by the compiler exporting everything. A module member that
should be reusable but not part of the public surface is marked `internal` and
never reaches the TypeScript API.

### Deprecation of `export`

`export` (both the prefix form and the `export { ... }` form) is deprecated. For
one major version it is accepted as a synonym to ease migration:

- `export` at the top level maps to `public`.
- `export` at module scope maps to `internal`.

This mapping is intentionally conservative: it preserves today's importability
and never silently widens a module member into the TypeScript API. Authors who
relied on the `export { M_... }` re-export bridge to surface module state should
change the module member to `public` and delete the bridge. A migration lint can
flag every `export { ... }` re-export whose sole purpose was TypeScript emission.

### Grammar

The `export`<sup>opt</sup> prefix on ledger and circuit declarations is replaced
by an optional *visibility* terminal (`private` | `internal` | `public`). The
standalone `export { id, ... }` *export-form* is deprecated and, during the
compatibility window, treated as marking the listed identifiers `public` at the
top level.

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

- [Discussion: Improving Visibility Semantics in Compact (OpenZeppelin/midnight-apps #272)](https://github.com/OpenZeppelin/midnight-apps/discussions/272)
- [PR #261 review thread on automatic export](https://github.com/OpenZeppelin/midnight-apps/pull/261#discussion_r2590386597)
- Compact language reference: "Exports", "Imports", and "Top-level exports" sections.
- [CoIP-1: Compact Improvement Proposal Process](coip-0001.md)
- [Solidity: state variable and function visibility](https://docs.soliditylang.org/en/latest/contracts.html#visibility-and-getters)

## Acknowledgements

Thanks to Andrew Fleming (andrew-fleming) for reviewing the proposal on this discussion: https://github.com/OpenZeppelin/midnight-apps/discussions/272

## Copyright

All contributions submitted in this CoIP must be licenced under the Apache
License, version 2.0.

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Footnotes

<!--
If necessary, include footnotes in the CoIP text using GitHub's footnote
syntax[^1].  Keep the footnote heading at the bottom of the document.

[^1]: See the [GitHub Markdown guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#footnotes).
-->
