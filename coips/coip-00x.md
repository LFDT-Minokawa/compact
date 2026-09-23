---
CoIP: X
Title: Multi-environment support in Compact
Authors:
  - Parisa Ataei
Status: Draft
Category: Tooling
Created: 2026-08-04
Requires: -
Replaces: -
---

todo!

- Retire `--ledger-version` for `--list-ledger-versions`.
- list-ledger-versions shows the default or selected.
- add ledger version to native and ledger macros

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
ledger-8.0 whereas preview has moved on to ledger-9.1.

Currently, this either requires maintaining multiple versions of Compact in parallel
or Compact has to support multiple backend ledgers. This CoIP advocates for the latter.

## Motivation

A single version of Compact currently supports a single version of ledger
This limitation significantly increases effort in releasing (currently, Compact
uses a single release channel) and maintaining
multiple versions of Compact as multiple networks use different versions of
the ledger. Consequently, it transfers the burden of choosing the correct version
of Compact for each network onto the user.

## Specification

Potentially Compact could support multiple backend ledgers and a flag can choose
the specific version of the ledger that must be used to compile a contract. Thus,
a single release branch would still suffice.
For example, `compact --ledger=9.1 <input.compact> <output-dir>`. In this example,
the Compact compiler should be able to pick the correct backend passes for 
ledger 9.1 and the generated TypeScript code must use functions from a version 
of compact runtime that are compatible with ledger 9.1. The techenical
details are given in [Implementation](#implementation) section.

## Rationale

### Compiler

A handfull of compiler passes rely on the ledger. Thus, these can be duplicated
in a subdirectory for each supported version of ledger. These files/subdirectories
are:
- `compiler/typescript-passes.ss` and `compiler/typescript-passes`
- `compiler/zkir-passes.ss` and `compiler/zkir-passes`
- `compiler/midnight-ledger.ss`
- `compiler/midnight-natives.ss`

These can be moved to `compiler/backends/ledger-9.1` and `compiler/backends/ledger-8.0`
to support ledger 9.1 and 8.0, respectively. These backend subdirectories live as long
as there exists a network that supports that specific version of ledger, that is, upon
the promotion of all networks (this is not at the same time and it will be over a span
of multiple weeks to months) from ledger 8.0 the `compiler/backend/ledger-8.0` is 
dropped. Similarly, a backend subdirectory is created when the Compact TSC has recieved
and approved a request for a backend support with a timeline of when a network will be
promoted to that specific version of ledger.

The compiler is only concerned with which ledger to use. It is not concerned with
which network supports which ledger. So it introduces a new flag `--ledger=<version>`
and the user can run `compactc --ledger=<version> <input-contract> <ouput-dir>`.

The default ledger (when `--ledger` is absent) is always pinned to the oldest
supported ledger. Thus, deprecating a ledger version is a **breaking change**. 
However, adding support for a new ledger is not a breaking change.

`ledger.ss` and `natives.ss` should not be ledger-dependent. However, 
midnight-natives and midnight-ledger are. So if midnight-ledger and midnight-natives
start diverging in their structure from one ledger to another, the 
`declare-native-entry` and `declare-ledger-<something>` have to carry the backend information
within them. This is a design decision as opposed to duplicating these two files.
Thus, including `midnight-ledger` and `midnight-natives` in `ledger.ss` and
`natives.ss`, respectively, should be based on the picked ledger backend.

### Runtime

The Compact runtime relies on onchain runtime which is part of a ledger release. 
For simplicity, a single version of Compact runtime should not support multiple
ledger versions. For example `compact-runtime 0.16.0` supports `ledger 8.0` while
`compact-runtime 0.19.0` supports `ledger 9.1` and this will be the ongoing convention.
Compact runtime is published on npm. However, with a single version of Compact compiler
supporting multiple versions of the ledger, the internal runtime subdirectory inside
Compact repo needs to be duplicated for each ledger version as well. So instead of a
single `compact/runtime`, there should be `compact/runtime/ledger-8.0` and
`compact/runtime/ledger-9.1`. Again, similar to creating and deprecating backends
subdirectories for the compiler, the same happens for the runtime. The difference is that
the runtime does not need to refactor the parts of the runtime that are shared and
the parts that rely on onchain runtime. The trade off here is simplicity at the cost
of duplication. `flake.nix` needs to be updated to build the runtime for each
Compact runtime.

### Developer tool

The Compact developer tool is the main (and recommended) way for users to interact 
with Compact. Thus, while the Compact compiler uses `--ledger` flag for the backend ledger, 
the devtool should surface the network to the user through `--network=<some-network>` flag
and then use a compatibility matrix to pass the correct corresponding ledger version to the 
Compact compiler to compile a given contract. That is, the developer tool must maintain
the compatibility matrix:

| network | ledger |
| ------- | ------ |
| mainnet | 8.0    |
| preprod | 9.1    |
| preview | 9.2    |

For example, `compact --network=mainnet compile ...` finds that mainnet uses ledger-8.0
and thus, runs the command `compactc --ledger=8.0 ...`. 

This design modulates what the user needs to know, that is, the
average user doesn't need to know the underlying ledger version of the network
used to deploy their contract. At the same time, a more sophisticated
user can simply pass the ledger flag to the compiler through the devtool, 
e.g., `compact compile --ledger=x.y ...` (note that the devtool does not need to have
a `--ledger` flag, this is just passed directly from the devtool to the compiler).

The devtool should not silently choose a ledger version when conflict arises.
In case both flags are passed (e.g., `compact --network=mainnet compile --ledger=7.0 ...`)
the devtool throws an error:

```
error: mainnet network is on ledger 8.0, but you're requesting ledger 7.0
       if you need to compile your contract for the mainnet network, drop the --ledger flag
       if you need to compile your contract for ledger 7.0, drop the --network flag
```

## Backwards Compatibility

If the default ledger is set to the oldest supported version of ledger (at the
moment `ledger-8.0`) this will be a breaking change. However, if no default
ledger is chosen this will not be a breaking change. 
When a user upgrades to a version of Compact
that supports multiple backend ledgers, they just need to pass the flag 
`--ledger=<version>` to Compact to compile their contract with a version of
Compact that uses version `<version>` of ledger.

## Security Implications

If a security vulnerability is found in passes that are duplicated, the fix must
be applied to all currently supported backends, making Compact more vulnerable.

A CI check is required to diff the ledger-independent files across the runtime
directories. It must fail on unexplained divergence. This turns "a fix must be
applied to all supported runtimes" from a thing maintainers must remember into a
thing CI enforces.

## How to Teach This

Users simply need to add a feature flag to compile their contract. 
Generally, before they used to `compact <input.compact> <output-dir>` or
`compact compile <input.compact> <output-dir>` and
now they need to `compact --ledger=9.1 <input.compact> <output-dir` or
`compact --network=mainnet compile <input.compact> <output-dir>`, respectively. 
If they're passing any other flags they can continue doing so as long as
the flags are compatible.

## Implementation

There is no reference implementation yet. The work below is broken into steps
that are individually reviewable and, for the whole of phases 0 and 1,
individually *mergeable*: they preserve observable behavior, so they can land on
`main` before this CoIP is accepted and de-risk the parts that come after.

**Phase 0 — compiler restructure, one backend, and `ledger` and `list-ledgers` flags added.** 
Every step here keeps `compiler/go` green as its acceptance criterion.

1. Move `compiler/midnight-ledger.ss`, `compiler/midnight-natives.ss`, and
   the pass libraries into `compiler/backends/ledger-9.1/`. Renamine the libraries
   to `(backends ledger-9.1 …)`. Fix the path to `midnight-ledger.ss` and 
   `midnight-natives.ss` in `ledger.ss` and `natives.ss`. 
   Extend `CHEZSCHEMELIBDIRS` in `flake.nix` and `compiler/go`.
2. Add `compiler/backend-record.ss` (it defines the backend record structure) and
   `compiler/backend-ledger.ss` (it defines registery and selection of a backend).
   Add `compiler/backends/ledger-9.1/backend.ss` which instantiates 
   the backend record for ledger 9.1. Convert `passes.ss` to look the record up rather 
   than importing pass libraries directly.
   The record is still selected from a hardcoded constant, that is,
   `backend-record.ss` defines `(define (current-backend) ledger-9.0:the-backend)`.
3. Add the `backend-ledger` parameter, `--ledger`, `--list-ledgers`, and
   `default-backend-ledger` with exactly one valid value. Validation and error
   text are testable with a single backend. `current-backed` no longer is hardcoded.
   Refactor `compiler/ledger.ss` and `compiler/natives.ss` to pick a
   `midnight-ledger.ss` and `midnight-natives.ss` based on the picked backend.
   `ledger.ss` also loads `midnight-ledger.ss` for documentation in
   `emit-documentation`. `emit-documentation` should now output a
   `doc/ledger-<ledger-version>-adt.mdx` per ledger version supported by the compiler.
   Thus, for this phase, it should output `doc/ledger-9.1-adt.mdx` and change the title
   to `title: Ledger 9.1 data types`. 
4. Update `generate-docs.yml` and `check-docs-sync.yml`. The former now copies
   all ledger adt files to midnight-docs and the latter now checks all ledger
   adt files are synced between midnight-docs and compact.

*Acceptance criteria for phase 0.* The phase claims to preserve behavior, so the
criteria have to be strong enough to make that claim checkable:

- `compiler/go` is green, with no edits to `compiler/test.ss` beyond pass-name
  renames.
- `nix build .#compactc` is green.
- For every contract in `examples/` and `test-contracts/`, the compiler output
  is **byte-identical** to a pre-phase build: `contract/index.js`,
  `contract/index.d.ts`, `contract/index.js.map`, `zkir/*.zkir`,
  `compiler/contract-info.json`, and `compiler/contract-manifest.json`. Run this
  as a scripted before/after diff against a build of the parent commit; it is
  the only criterion that actually proves the refactor changed nothing, and it
  is what catches a pass list wired into the wrong record field.
- `compactc --version`, `--language-version`, and `--runtime-version` are
  unchanged, and `--ledger-version` is unchanged for the default backend.
- `--ledger=9.1` is accepted; `--ledger=8.0` is rejected with a message naming
  the supported set; `--list-ledgers` prints exactly `9.1`.
- `doc/ledger-9.1-adt.mdx` is generated and `check-docs-sync.yml` is green.

**Phase 1 — runtime restructure, one ledger.**

4. Move the contents of `runtime/` down into `runtime/ledger-9.1/`, leaving
   the shared `extract-version.ss` and `export-version.ss` at `runtime/`;
   update `flake.nix` and `runtime-shell-hook` based on 
   [Runtime implementation](#runtime-implementation) section.
   Make `runtime-version.ss` per-backend and reach it through the backend
   record.
   todo! drop 7
7. Parameterize `packages.runtime` on the ledger version (still one
   instantiation) and switch to the per-backend `node_modules` / `NODE_PATH`
   scheme.
5. Update `generate-docs.yml`, `check-docs-sync.yml`, and `typedoc.json`.
6. Add the CI drift check.

*Acceptance criteria for phase 1.*

- `nix build .#runtime-ledger-9.1` is green, and the published tarball is
  identical to the pre-rename tarball except for paths and the name/version
  fields.
- The `checkPhase` of `packages.compactc` is green against the relocated
  `node_modules`, and the `runtime/ledger-9.1` unit suite passes.
- Generated documentation lands at the new versioned path and
  `check-docs-sync.yml` is green.
- The drift check runs, passes trivially with one runtime, **and has been shown
  to fail** on a deliberately injected divergence in a scratch branch. A check
  that has never failed is not known to work, and this one will sit idle until
  phase 2 gives it a second runtime to compare against.

**Phase 2 — second backend.** This is the first phase that changes behavior.

11. Add the ledger-8.0 flake inputs and its zkir binaries under distinct names;
    generalize the key scheme in `ledger-version.ss`. The last ledger-8 support
    on compact compiler is accessible [here](https://github.com/LFDT-Minokawa/compact/tree/ledger-8).
12. Add `compiler/backends/ledger-8.0/`.
13. Add `runtime/ledger-8.0/`. There's no need to publish as this is 
    `compact-runtime 0.16.0` and it has been published.
14. Extend `compiler/test.ss` to a backend matrix and matrix the runtime,
    test-center, and e2e workflows for example by adding a 
    parameterized test to test.ss for ledger-8.0 and ledger-9.1 and
    checking the version of ledger in generated `contract-info.json`.
15. Record the selected ledger in `contract-manifest.json`. 
16. Flip `default-backend-ledger` to the oldest supported ledger.
17. If possible, test a circuit supported in standard library for one ledger
    but not the other.

Step 16 is a **breaking change** since it changes the default ledger from
9.1 to 8.0.

*Acceptance criteria for phase 2.*

- The backend matrix in `compiler/test.ss` is green for both ledgers.
- The matched-pair test passes for both ledgers, and the mismatched-pair test
  fails *inside* `checkRuntimeVersion`.
- `--list-ledgers` prints `8.0` and `9.1`.
- The CI drift check is now comparing two real runtimes and passing.

**Phase 3 — developer tool.**

18. Publish the compatibility-matrix document and add fetching, caching, and
    schema validation to the tool.
19. Add `--network` resolution, `--ledger` conflict detection, and
    `--list-ledgers` querying and caching, with the error messages explained
    in [developer tool implementation](#developer-tool-implementation).
20. Tests and user-facing documentation.

*Acceptance criteria for phase 3.*

- `compact --network=<network> compile` resolves to the matrix's ledger for
  `mainnet`, `preprod`, and `preview`.
- The conflict, unknown-network, misplaced-`--network`, and stale-compiler
  errors match golden files under `tools/compact/output/`.
- The e2e suite is green per network, using the ledger the matrix resolves to.

### Compiler implementation

#### Flag and configuration parameter

`--ledger=<version>` is parsed in `compiler/compactc.ss` and bound to a new
`backend-ledger` parameter in `compiler/config-params.ss`. The compiler already
has exactly this shape for `--feature-zkir-v3`/`feature-zkir-v3`.
`compactc.ss` must reject a value that does not name a compiled-in
backend and print the supported set in the error message.

The compiler also needs a machine-readable way to report what it supports, for
the developer tool's benefit: `compactc --list-ledgers` printing one version per
line. `--ledger-version` (currently `print-ledger-version` in
`compiler/program-common.ss`) should report the *selected* backend's ledger
version rather than a fixed one.

There should be an explicit `default-backend-ledger` constant, initialised
to the oldest supported ledger.

#### Backend registry

Chez library names are global, so the duplicated pass libraries cannot all be
named `(typescript-passes)`. Each backend directory gets a namespaced library
name, e.g. `compiler/backends/ledger-9.1/typescript-passes.ss` has the library name
`(backends ledger-9.1 typescript-passes)`, and `CHEZSCHEMELIBDIRS` is extended
in `flake.nix` (`packages.compactc`) and in `compiler/go`.

Importing such passes requires adding a prefix:

```
(import (prefix (backends ledger-9.1 typescript-passes) ledger-9.1:)
        (prefix (backends ledger-8.0 typescript-passes) ledger-8.0:))

```

Rather than scattering `(if (eq? (backend-ledger) ...) ...)` through
`compiler/passes.ss`, each backend should instantiate and export a single record from a
`compiler/backends/ledger-X.Y/backend.ss`.

The backend record is roughly:

```
  (define-record-type backend
    (nongenerative)
    (fields
      ledger-version           ; string; the --ledger value, e.g. "9.1"
      runtime-version          ; string; embedded in checkRuntimeVersion(...)
      zkir-executable          ; string; invoked from passes.ss, e.g. "zkir-9.1"
      zkir-v3-executable
      typescript-passes        ; passrec list
      zkir-passes
      zkir-v3-passes)))
```

And `compiler/backends/ledger-9.1/backend.ss` instantiates this:

```
  (define (ledger-version-for key)
    (cond
      [(assoc key ledger-version-strings) => cdr]
      [else (error 'the-backend "no ledger version string for ~a" key)]))

  (define the-backend
    (make-backend
      "9.1"                                    ; ledger-version
      runtime-version-string                   ; from runtime/ledger-9.1/package.json
      "zkir-9.1"                               ; zkir-executable
      "zkir-v3-9.1"                            ; zkir-v3-executable
      typescript-passes
      zkir-passes
      zkir-v3-passes)))
```

Finally `backend-ledger.ss` carries out the registery and selection of a backend:

```
#!chezscheme

(library (backend-ledger)
  (export supported-backends supported-ledger-versions default-backend-ledger
          lookup-backend check-backend-ledger! current-backend)
  (import (except (chezscheme) errorf)
          (utils)
          (config-params)
          (backend-record)
          (prefix (backends ledger-8.0 backend) ledger-8.0:)
          (prefix (backends ledger-9.1 backend) ledger-9.1:))

  ;; Ordered oldest first.  The default is the oldest supported ledger, so
  ;; adding a newer backend never moves it; dropping the oldest does, and is a
  ;; breaking change.  Adding a backend means one import above and one line here.
  (define supported-backends
    (list ledger-8.0:the-backend
          ledger-9.1:the-backend))

  (define supported-ledger-versions
    (map backend-ledger-version supported-backends))

  (define default-backend-ledger
    (backend-ledger-version (car supported-backends)))

  (define (lookup-backend version-string)
    (let loop ([b* supported-backends])
      (cond
        [(null? b*) #f]
        [(string=? (backend-ledger-version (car b*)) version-string) (car b*)]
        [else (loop (cdr b*))])))

  (define (check-backend-ledger! version-string)
    (unless (lookup-backend version-string)
      (external-errorf "unsupported ledger version ~a; this compiler supports ~{~a~^, ~}"
                       version-string supported-ledger-versions)))

  ;; The backend selected for this compilation.  (backend-ledger) is #f when
  ;; --ledger was absent, which is what lets the compiler tell "user asked for
  ;; the default" apart from "user did not ask".
  (define (current-backend)
    (let ([version-string (or (backend-ledger) default-backend-ledger)])
      (or (lookup-backend version-string)
          (internal-errorf 'current-backend
            "no backend registered for ledger ~a" version-string)))))
```

`generate-everything` then looks the
record up once from `(backend-ledger)` and stays backend-agnostic:
`(run-passes (backend-typescript-passes b) analyzed-ir)`.

#### What actually has to be duplicated

The Rationale lists the ledger-dependent files.

`compiler/standard-library.compact` should stay shared. When a program uses a
native the selected backend does not provide, the compiler should emit a
targeted diagnostic naming the flag, mirroring the existing message
`secp256k1 is not supported in ZKIR v2: try recompiling with the flag
--feature-zkir-v3`.

#### zkir binaries

Assuming that each ledger backend can support multiple `zkir`s,
the backend record must supply the
executable name and the names must be distinct across backends — the release zip
is built with `zip --junk-paths`
(`.github/workflows/release-build.yml:85,91`), which flattens `bin/` and `lib/`
into a single directory, so `lib/ledger-8.0/zkir` and `lib/ledger-9.1/zkir` would
collide. Names like `zkir-8.0` and `zkir-v3-9.1` avoid this.
`flake.nix` needs one input per supported ledger (today `zkir`, `zkir-v3`,
`zkir-wasm`, `zkir-v3-wasm` and `onchain-runtime-v4` all point at
`ledger-9.1.0.0-rc.3`), and `packages.compactc-binary` must copy each into
`$out/lib` under its distinct name.

`compiler/ledger-version.ss` derives version strings by grepping `flake.nix` for
end-of-line markers (`# zkir-v2`, `# zkir-v3`). This will need to change. This change
relies on the open question of the relationship between zkir and ledger.

#### Generated code and metadata

`compiler/typescript-passes/print-typescript.ss:941` emits
`__compactRuntime.checkRuntimeVersion('<runtime-version-string>')` using
`compiler/runtime-version.ss`, which reads `runtime/package.json` at compiler
build time. That becomes one library per backend reading its own runtime's
`package.json`.

The selected ledger version should also be recorded in
`compiler/contract-manifest.json` (produced by `manifest-passes`) so that
downstream tooling, the test center, and anyone auditing a deployed contract can
tell which ledger a set of artifacts was built for.

#### Testing and build cost

`compiler/test.ss` already runs a parameter matrix — `with-parameter-values
([feature-zkir-v3 #f #t])` — so adding a backend axis
is mechanical. Local testing should add a new parameter matrix when a contract's 
behavior is expected to be different from one ledger to another, especially
during development of the compiler to add a specific version of the ledger.
However, the CI must run the full matrix.

Because `flake.nix` builds `compactc` with `compile-whole-program`, every
backend is linked into one binary; compiler build time, binary size, and the
`compiler/go` unit-test run all grow roughly linearly in the number of supported
backends. This is a concrete argument for the deprecation policy in the
Rationale: the number of concurrently supported backends must be bounded, and
dropping a backend when the last network is promoted off it is not optional
housekeeping.

### Runtime implementation

#### Directory split and publishing

Each supported ledger gets a subdirectory of `runtime/` — `runtime/ledger-8.0/`
and `runtime/ledger-9.1/` — mirroring `compiler/backends/ledger-X.Y/` on the
compiler side, with `runtime/` itself holding the files shared between them.
Each subdirectory carries its own `package.json` pinning the matching onchain
runtime and declaring it in `nixDependencies`.

Every runtime subdirectory publishes the *same* npm package name,
`@midnight-ntwrk/compact-runtime`, distinguished only by version number
(e.g., `0.16.0` for ledger 8.0, `0.19.0` for ledger 9.1, etc). npm has no
way to express "the ledger 8.0 line" in a version range, so the convention alone
puts the burden back on the user. Publishing npm dist-tags alongside the
versions (`npm install @midnight-ntwrk/compact-runtime@ledger-8.0`) removes
that. The generated `checkRuntimeVersion(...)` call still catches a mismatch at 
run time, but a dist-tag catches it at install time.

#### Version plumbing

Currently, `compiler/runtime-version.ss` hardcodes the path `"runtime/package.json"`
and inlines the version at compiler build time via `#%$require-include`. It becomes
one library per backend (e.g., `compiler/backends/ledger-9.1/runtime-version.ss`),
each reading its own runtime's `package.json`, reached
through the backend record. Correspondingly, the `inclusive` source list for
`packages.compactc` in `flake.nix:234-235` (`./runtime/extract-version.ss`,
`./runtime/package.json`) must list each runtime directory's pair.

`runtime/extract-version.ss` and `runtime/export-version.ss` are
ledger-independent and should stay in a single shared location.

One thing to verify at every ledger bump: `export-version.ss` bakes
`(max-field)` from `compiler/field.ss` into `src/version.ts` and cross-checks it
against `OCRT_MAX_FIELD` from the onchain runtime. If two supported ledgers ever
disagree on the field modulus, `compiler/field.ss` becomes backend-specific too.
In such a case, `max-field` should be added to the backend record.

#### Nix

`packages.runtime` in `flake.nix` becomes a function of the ledger version,
producing `packages.runtime-ledger-8.0`, `packages.runtime-ledger-9.1`, and so
on — each with its own `inclusive-src` and its own `nixDependenciesMap` entry
pointing at that ledger's `onchain-runtime-vN` flake input. Note that the
*attribute* names keep the hyphen while the *paths* nest: a nix attribute path
cannot contain an unquoted `/`, so `packages.runtime-ledger-9.1` builds from
`runtime/ledger-9.1/`.

The awkward part is `node_modules`. Both `runtime-shell-hook`
and the `checkPhase` of `packages.compactc` install the
built runtime at the single path
`node_modules/@midnight-ntwrk/compact-runtime`, and `NODE_PATH` points at one
`node-modules` derivation. Only one runtime can occupy that path. The compiler's
own tests, which type-check generated TypeScript against the runtime, therefore
need one `node_modules` tree per backend (`node_modules-ledger-9.1/`, …) with
`NODE_PATH` selected according to the backend under test. This is the main
mechanical cost of the split on the build side.

The restructuring uses a single source-of-truth ledgers `attrset` indexed by
version, since flake inputs must be literal and cannot be generated from lists.
Each ledger version requires a fixed block of inputs (`zkir`, `zkir-v3`, `zkir-wasm`,
`onchain-runtime`) — adding or dropping a backend is a manual edit in exactly two
places: the inputs block and the ledgers attrset. Per system, three things
become functions of the ledger: (1) one `mkRuntime` function produces a package
per ledger, kept under `packages.runtime-ledger-${version}` with
`packages.runtime` aliased to the default ledger; (2) zkir binaries are renamed
distinctly (`zkir-${ver}`, `zkir-v3-${ver}`) so they share a flat release
directory; (3) `packages.compactc` gains every backend and copies one
`node_modules` tree per ledger during `checkPhase`, with `NODE_PATH` selected
per invocation from an environment variable. `packages.compactc-binary` copies
every zkir under its distinct name and iterates Darwin fixups over the same
list. `runtime-shell-hook` becomes a function of the ledger, with
`devShells.default` using the default ledger and one shell per ledger for
targeted work. CI workflows for release and testing are matrixed over runtime
directories, and runtime changes move to `CHANGELOG.md` instead of a separate
file.

#### Containing the duplication

`runtime/src` is sixteen modules, and thirteen of them import
`@midnightntwrk/onchain-runtime-v4` — every one except `casts.ts`, `error.ts`,
and the generated `version.ts`. The onchain runtime is not confined to a few
modules, so "duplicate only the ledger-dependent files" is not an available
option. How much of that duplication is *real* divergence rather than a
changed import specifier is what [CI drift check](#ci-drift-check) checks.

#### Shared tooling configuration

Ledger-specific `runtime/package.json` entries are the compact-runtime version,
onchain-runtime dependency, and `nixDependencies` entry; everything else should
be identical across runtimes and verified by CI.

Configuration files present a tradeoff between hoisting and build-sandbox
constraints. `tsconfig.json` and `eslint.config.mjs` can be hoisted in principle
(TypeScript resolves relative paths relative to the config file; ESLint
flat-config globs are relative to config location), but the sandbox constraint
is decisive: `src` is set to a per-runtime directory, so `../` references to
shared files don't resolve in the build. Workarounds (merging source as a
derivation or rewriting paths at build time) cost more than duplication, so the
recommendation is to duplicate these two files per runtime and use CI equality
checks to prevent drift. Prettier is already duplicated with no inheritance
mechanism; this covers it too.

The actual shared infrastructure (`extract-version.ss` and `export-version.ss`)
are Scheme files read by multiple parts of the build and already referenced by
compactc's source list; these merit a merge derivation to avoid correctness
hazards from per-runtime copies.

`devDependencies` cannot be hoisted without npm workspaces (which would require
reworking the build architecture). Keep per-directory lockfiles and assert via
CI that `devDependencies` blocks are identical across all runtimes.

Documentation (`typedoc.json`) must be keyed on ledger version, not runtime
version, to provide stable documentation trees across patch releases. Output
paths become `doc/api/runtime-ledger-X.Y/`, display names become
`@midnight-ntwrk/compact-runtime (ledger X.Y)`, and a landing page maps ledgers
to trees. CI workflows iterate over discovered runtime directories rather than
hardcoding paths, so stale directories cannot be silently republished.

Two notes on the version keyed on. Keying the path on the full runtime semver
(`runtime-0.19.0`) creates a new documentation directory on every patch release
of the runtime and breaks every inbound link each time; the ledger version is
stable across those releases. This is unfortunate as it requires the reader to
know the ledger version. And `name` is typedoc's display title, not a package
identifier — spelling it `@midnight-ntwrk/compact-runtime-0.19.0` invents a
package name that does not exist on npm, which is why the form above keeps the
real package name and puts the ledger in parentheses.

### CI drift check 

Concretely, the CI check is then: for each pair of runtime directories, diff the
ledger-independent source files and every configuration file, and diff
`package.json` with `version`, the onchain-runtime dependency, and
`nixDependencies` masked out — failing on any difference not covered by an
explicit allowlist.

That check should cover the runtimes' build and lint configuration, not only
their source. If `tsconfig.json`, `eslint.config.mjs`, or `.prettierrc.json`
drift apart, the same source file is compiled and linted under different rules
in each runtime, so a fix verified in one is not automatically equivalent in the
other. Divergent `devDependencies` are the sharper form of the same problem: a
runtime whose lockfile freezes an older TypeScript can emit different
declarations from identical source, which is exactly the kind of difference a
reviewer comparing two patches will not notice. Where a configuration can be
hoisted to a shared base it should be; where it cannot, CI should assert that
the copies are byte-identical. The [Runtime implementation](#runtime-implementation)
section covers which of these can actually be hoisted, and what it costs in
the nix packaging.

**Must be identical across every `runtime/ledger-*/`:**

- `tsconfig.json`, `tsconfig.test.json`, `eslint.config.mjs`,
  `.prettierrc.json`, `.prettierignore`, `README.md`
- `package.json` with the three keys below masked out

**Allowed to diverge. This list is exhaustive; anything else is a failure:**

| What | Why it differs |
| --- | --- |
| `package.json` → `version` | each runtime has its own npm version line |
| `package.json` → `dependencies["@midnightntwrk/onchain-runtime-v<N>"]` | the pin being varied |
| `package.json` → `nixDependencies` | must name the same package as above |
| `typedoc.json` → `name`, `out` | per-runtime documentation |
| `src/version.ts` | generated by `export-version.ss` |
| `package-lock.json` | generated; covered by its own rule below |
| `dist/`, `node_modules/`, `tsconfig.tsbuildinfo` | build output |
| files named in `runtime/drift-allow.json` | genuine ledger adaptation |

`package-lock.json` gets its own rule rather than a byte diff, which would fail
constantly for uninteresting reasons: assert that the **resolved version string
of every package reachable from `devDependencies` is the same in all
lockfiles**. That is what actually catches the failure the paragraph above is
about — one runtime freezing an older TypeScript and emitting different
declarations from identical source. Resolved versions of `dependencies` are
expected to differ, since the onchain runtime differs.

`runtime/drift-allow.json` is the escape hatch for real divergence in
source files of runtime. Each entry names the file, the ledger
versions it applies to, and one line of justification. Two things follow from
that file being the only way a difference becomes permanent: it needs a
CODEOWNERS entry, and every entry should be re-examined when a backend is
dropped, or the list only ever grows. A check whose allowlist can be extended
without review is not a check.

The check runs on every pull request, not only on release. Its whole purpose is
to catch a fix applied to one runtime and forgotten in another, and that
mistake is made in the pull request that applies the fix.

#### Testing

@pat todo: review, consider e2e test

Today `runtime/package.json:20` defines `test` as `npm run build && vitest run`,
covering the three suites in `runtime/test`, and
`.github/workflows/build-runtime-test.yml` builds `.#runtime.forPublish` and
runs that script in `./runtime`. After the split that workflow becomes a matrix
over the runtime directories, and each directory keeps its own `test/`.

The tests that actually justify the split are the cross-version ones, and none
of them exist today:

- **Matched pair.** Compile a contract with `--ledger=X`, then type-check and
  run the generated code against `runtime/ledger-X`. `test-center` already does
  exactly this — `test-center/run-test` feeds a generated `test.ts` to
  `generatedJavascript.test.ts` and `generatedDeclaration.test.ts` — so this is
  a matrix over backends with `NODE_PATH` pointed at the matching runtime.
- **Mismatched pair.** The same generated code run against the *wrong* runtime
  must fail, and must fail inside `checkRuntimeVersion` with the version
  mismatch message rather than somewhere arbitrary downstream. The check
  emitted by `runtime/export-version.ss` throws when the majors differ or when
  the major is 0 and the minors differ, so code emitted for `0.19.x` against
  runtime `0.16.x` does trip it. Without this test the guard that makes the
  whole scheme safe is itself untested.
- **Field modulus.** `export-version.ss` also emits a
  `MAX_FIELD !== OCRT_MAX_FIELD` check. Assert it holds for every
  (runtime, onchain-runtime) pair, since that is the cross-check that would
  catch a ledger changing the field modulus — see the open question about
  `compiler/field.ss`.

End-to-end, `run-e2e-tests.sh` and `tests-e2e` are the only place the
compatibility matrix gets validated against reality, so they should run per
network using the ledger the matrix resolves to, rather than a hardcoded one.

The cost is important: the runtime suite multiplies by the number of
supported runtimes and the test-center suite by the number of backends, on top
of the compiler matrix in
[Testing and build cost](#testing-and-build-cost). This is the same argument for
bounding how many backends are supported at once. Carefully evaluating which
test is required to run for which PR will save resources. 
E.g., if there are no changes in a PR to a runtime, there is no
need to run the test for that runtime in that PR. However, for releases it is
important to ensure that the entire matrix has been tested and the release
must be gated on all test successfully passing.

### Developer tool implementation

The developer tool is the Rust crate in `tools/compact`, built on `clap`.
Two existing properties of `compact compile` shape the design:

- It is a transparent passthrough. `CompileCommand`
  (`tools/compact/src/command_line_arguments.rs:301-305`) collects everything
  into `args: Vec<String>` with `trailing_var_arg` and `allow_hyphen_values`,
  and the subcommand disables clap's own `--help`/`--version` so that
  `compact compile --help` is exactly `compactc --help`. That property must be
  preserved.
- `compile()` in `tools/compact/src/bin/compact.rs:137-165` already walks `args`
  once to strip a leading-`+` version selector before handing the rest to
  `Compiler::invoke`. The network logic belongs in that same loop.

#### The `--network` flag

@pat todo: review

`--network` is accepted only before the subcommand, so it must *not* be a clap
global argument — `global = true` is precisely the setting that also allows an
argument to appear after the subcommand. A plain field on
`CommandLineArguments` gives the required behavior:

```rust
/// Network to compile for
///
/// Resolved to a ledger version through the compatibility matrix and passed
/// to the compiler as `--ledger`.
#[arg(long, env = "COMPACT_NETWORK", value_name = "NETWORK")]
pub network: Option<String>,
```

`env` still works on a non-global argument, so `COMPACT_NETWORK=mainnet` keeps
the ergonomics reasonable for repeated use. This also differs deliberately from
`directory`, which *is* global because it applies to every subcommand; a global
`--network` would be silently accepted by `compact list --network=…`, where it
means nothing.

Rejecting the misplaced form needs an explicit check. Because `CompileCommand`
is declared with `trailing_var_arg` and `allow_hyphen_values`, clap does not
reject `compact compile --network=mainnet …` — it collects the flag into `args`
and forwards it to `compactc`, which fails with its own unrecognized-flag usage
error and no hint about what the user did wrong. The same loop in `compile()`
that strips `+VERSION` and inspects `--ledger` should therefore also look for
`--network` and report:

```
error: `--network` must appear before the subcommand
       use `compact --network=mainnet compile ...`
```

When `--network` is used, the tool should print the resolved ledger version to
stderr, so build logs record what a contract was actually compiled against.

#### The compatibility matrix

@pat todo: review

This is the largest genuinely new piece of behavior and deserves its own
reference implementation. Networks are promoted independently, over weeks to
months, so a table compiled into the binary goes stale between
`compact self update` runs — and a stale table is worse than no table, because
it silently compiles against the wrong ledger.

The recommendation is a small JSON document mapping network to ledger version
(with a validity date, so an upcoming promotion can be published ahead of time),
fetched and cached under `$COMPACT_DIRECTORY`. The tool already has the pieces:
`src/http.rs` and `src/fetch.rs` for retrieval, and a cache directory that
`compact clean --cache` knows how to clear
(`command_line_arguments.rs:288`). A copy compiled into the binary serves as the
offline fallback. `compact check` and `compact update` refresh it; `compact list`
displays it.

The document itself is small. Each network carries a *schedule* rather than a
single ledger, so an upcoming promotion can be published before it happens:

```json
{
  "schema": 1,
  "updated": "2026-09-10",
  "networks": {
    "mainnet": [
      { "ledger": "8.0", "valid_from": "2026-04-14" }
    ],
    "preprod": [
      { "ledger": "9.1", "valid_from": "2026-07-01" }
    ],
    "preview": [
      { "ledger": "9.1", "valid_from": "2026-07-01" },
      { "ledger": "9.2", "valid_from": "2026-10-06",
        "notice": "preview moves to ledger 9.2 on 2026-10-06" }
    ]
  }
}
```

Resolution is one rule: for the named network, take the entry with the latest
`valid_from` that is not in the future. Entries dated ahead are announcements —
`--network=preview` resolves to 9.1 today and to 9.2 on 6 October with no tool
update and no new fetch. `notice` is free text the tool prints verbatim when an
entry within some window applies, which is the one piece of user-facing
information that cannot be derived from the schedule.

`schema` matters more than it looks: it lets an older tool refuse a format it
does not understand instead of misreading it and compiling against the wrong
ledger. The tool should also reject an unknown network outright rather than
falling back to a default, and should report how stale its cached copy is
whenever it warns or errors. Since this document decides what code gets
compiled for mainnet, it should be served from the same trusted origin as the
releases themselves.

**On tracking a deprecation date: not as a separate field.** A ledger's
deprecation is already implied by the schedule — a ledger is dead when no
network's current or future entry names it, which is exactly the condition the
Rationale gives for dropping `compiler/backends/ledger-X.Y` and its runtime.
Deriving it keeps one source of truth. Adding an explicit
`"deprecated": "2026-11-01"` alongside the schedule creates a second, which is
a forecast rather than a fact, and which will eventually disagree with the
schedule that actually drives the behavior — and a stale cached copy makes a
confidently wrong deprecation warning worse than no warning. What *is* worth
recording, in the repository rather than in this document, is the reverse
mapping: which backend directories exist and which network keeps each one
alive, so that a maintainer can see at a glance what a promotion allows them to
delete.

#### Validating against the installed compiler

The matrix says which ledger a network needs; it does not say which ledgers the
*installed* compiler supports. A user can pin an older compiler with
`compact --network=preview compile +0.35.0 ...`, and that compiler may not
support the version of the ledger required for a network.
The tool should therefore query `compactc --list-ledgers` (see
[Compiler](#compiler-implementation)) for each installed version, cache the
answer alongside the installed toolchain, and fail before invoking the compiler:

```
error: network `preview` requires ledger 9.2, but compiler 0.35.0 supports 8.0, 9.1
       run `compact update` to install a newer compiler
```

For older compiler versions that support a single version of ledger, the
developer tool should state so when compiling a contract asking for a
specific version of ledger (e.g., `compact --network=preview compile +0.31.1 ...`):

```
error: compiler 0.31.1 supports a single network
       run `compact update` to install a newer compiler that allows you to choose a network
```

#### Conflicting flags

The developer tool does not have a `--ledger` flag. However, the compiler does.
This means that the `--ledger` flag can be exposed to the devtool through the compiler.

```
compactc --ledger=9.1 ... //calling compiler directly with ledger 9.1
compact --network=mainnet compile ... //calling the devtool for mainnet network to call the compiler with a compatible ledger with mainnet
compact --network=mainnet compile --ledger=9.1 ...//calling the devtool for mainnet network but insisting on using ledger 9.1
```

So in the last case the devtool must check the compatibility matrix for `mainnet`,
if it relies on ledger 9.1, it would proceed with compiling the contract with a
version of Compact compiler that supports ledger 9.1. If it relies on a different
version of the ledger, it throws an error stating:

```
error: mainnet network is on ledger 8.0, but you're requesting ledger 9.1
       if you need to compile your contract for the mainnet network, drop the ledger flag
       if you need to compile your contract for ledger 9.1, drop the network flag
```

If neither `--network` nor `--ledger` is given, the Compact devtool behaves
the same as the default case described in rationale of [Comiler](#compiler).

#### Tests

`tools/compact/tests/test_compile.rs` and the golden files under
`tools/compact/output/` should gain cases for: 
- default behavior where no `--ledger` or `--network` is provided
- every successful case of `--network` (which is `preview`, `preprod`, and `mainnet`)
- an unknown network that is not a supported network
- a successful case of providing both `--network` and `--ledger`, for this
  the test must grab the ledger version from the compatibility matrix and it 
  must not hardcode this value in test
- a conflicting case of providing both `--network` and `--ledger`, this can be
  hardcoded, use `--network=mainnet` and `--ledger=5.0`
- a case where the compiler does not support the ledger version required by `--network`,
  this can be hardcoded, use `--network=preview` with compiler `0.31.0`.

## Rejected Ideas

### Multiple release branches

Compact could potentially use a branch per network for its releases. 
However, this approach still puts the burden of choosing the correct version
of Compact on the user. Furthermore, it is burdonsome to maintain and release.
Consider a patch release for a bug. The Compact maintainers must then cut three
releases. 

### A Compact runtime that supports multiple ledgers

Complicated and requires lots of refactoring and design effort.

## Open questions

Some of the proposed design decisions thus far in the proposal are questioned.
The answer to such questions supersedes the design proposed above.

- Will `onchain-runtime` always be released with a suffix of its major version?
- What should be the default backend? Does it make sense to have a default ledger?
  Not having a default ledger, forces the user to have a `ledger` or `network` flag,
  and is less user friendly.
- Should `compact-standard-library` be ledger-dependent?
- Should `contract-manifest.json` also record the ledger version?
- What's the relationship between zkir and ledger? Does one rely on
  encodings/functions/libraries/executables from another?
- Does the ledger team perceive a change in `max-field` allowed in the future? If so, 
  `compiler/field.ss` also becomes ledger dependent.
- Documentation is relying on ledger versions. This should instead be a network.
  However, Compact compiler should not know which ledger is used in which network.
  How does the docs expose the network for `ledger-adt.mdx` without breaking the
  separation concern?
- Currently `compiler/midnight-inlines.ss` and `compiler/midnight-events.ss` are
  not ledger dependent. However, changes to the ledger and expansion of 
  `midnight-inlines` might at some point make these files ledger dependent.
- Can `format` and `fixup` become ledger-dependent?
- Is there a timeline for promotion of networks? This helps decide the maintanence
  burden of multiple backend and runtime subdirectories.
- STL might cut only release candidates. Does that matter?
- What are the implications on upstream components like compact.js, midnight.js? 
  From initial discussions, one would expect the upstream components to adopt the same design
  of supporting multiple ledgers, otherwise, the benefit added is only when a user
  is compiling a contract.

## References

- https://github.com/midnightntwrk/midnight-architecture/pull/183: this provides 
  more details on Compact release process and Midnight networks and how they impact
  the ideas for this problem.

## Acknowledgements

- Kevin Millkin
- Kent Dybvig
- Vanessa Cristobal

## Copyright

All contributions submitted in this CoIP must be licenced under the Apache
License, version 2.0.  Include the paragraph below.

This CoIP is licensed under [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Footnotes
