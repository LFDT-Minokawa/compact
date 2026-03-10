## [Toolchain 0.30.0, language 0.22.0, runtime 0.15.0]

This release includes all changes for compiler versions in the range between
0.29.100 and 0.30.0; language versions in the range between 0.21.100 and 0.22.0;
and Compact runtime versions in the range between 0.14.100 and 0.15.0.

## [Unreleased toolchain 0.29.112, language 0.21.101, runtime 0.14.102]

### Changed

- It is now a compiler error to pass Compact values containing opaque JS values
  (`Opaque<'string'>` or `Opaque<'Uint8Array'>`) to the standard library
  circuits `persistentHash` and `persistentCommit`.  Hashing such values does
  not work in circuit due to the representation of these types.  Previously,
  such code would crash the `zkir` process if it tried to generate prover and
  verifier keys.  Now it is a compiler error instead.
  
  This also affects the standard library operation `merkleTreePathRoot` (because
  it calls `persistentHash` in its implementation), and ledger `MerkleTree`
  insertion operations, because they implicitly use `persistentHash`.
  
  This is a **breaking** change because the error is signaled early, and so it
  is now an error to use any of these circuits or ADT operations, even for
  circuits that don't need prover and verifier key generation which would
  compile successfully before.

## [Unreleased toolchain 0.29.112, language 0.21.101, runtime 0.14.102]

### Changed

- The fixup tool now replaces references to the old standard-library type names
  `CurvePoint` and `NativePoint` with `JubJubPoint`.  It also does a better job
  of renaming standard-library circuits when it is safe to do so and explaining
  why when it is not safe to do so.

### Internal notes

- The expand-modules-and-types code for function lookup is more modular and
  easier to read.

## [Unreleased toolchain 0.29.111, language 0.21.101, runtime 0.14.102]

### Fixed

- The `<=` and `>` operand evaluation order in the proof circuit is incorrect
  (right-to-left rather than left-to-right).  It also differs from the evaluation
  order in the generated JavaScript code, which can result in proof failures
  when the operands are non-trivial.  This fix modifies the common upstream path
  `infer-types` to enforce the correct evaluation order.

## [Unreleased toolchain 0.29.110, language 0.21.101, runtime 0.14.102]

### Fixed

- There was an unreleased bug in ZKIR circuits (not in JS) where the
  representation of the default `JubjubPoint` was wrong.  Fixing this entailed
  allowing `default` in compiler IR from `Lflattened` and downstream in both
  ZKIR v2 and v3 backends.

## [Unreleased toolchain 0.29.109, language 0.21.101, runtime 0.14.102]

### Changed

- The compiler binary can now report `--ledger-version` (and
  `--feature-zkir-v3 --ledger-version`).  This is the version of the ledger that
  is targeted by the generated code and used to produce the generated prover and
  verifier keys.

## [Unreleased toolchain 0.29.108, language 0.21.101, runtime 0.14.102]

### Fixed

- Type declarations of `Uint<n>` and `Uint<0..n>` where `n` is a free type variable
  are now accepted by the compiler.

## [Unreleased toolchain 0.29.107, language 0.21.101, runtime 0.14.102]

### Changed

- The ZKIR v3 format, behind the feature flag `--feature-zkir-v3`, has changed
  so that:
  - circuit inputs are correctly typed as either `Scalar<BLS12-381>` or
    `Point<Jubjub>` (before they were always scalars, with `encode` instructions
    for curve points), and
  - `private_input` and `public_input` instructions are typed (before they
    always read scalars, with `encode` instructions for curve points)

## [Unreleased toolchain 0.29.106, language 0.21.101, runtime 0.14.102]

### Changed

- The Compact compiler now targets `midnight-ledger` version 8.0.0.  The Compact
  runtime now imports `onchain-runtime-v3` (instead of `-v2`) at version
  compatible with 3.0.0-rc.2.

## [Unreleased toolchain 0.29.105, language 0.21.101, runtime 0.14.101]

### Fixed

- [Breaking Change] The search order for include and external module files
  specified with non-absolute paths has been fixed so that (a) the compiler looks
  first relative to the directory of the including or importing file, and (b)
  the compiler does not automatically look in the directory where the compiler
  was invoked.

### Added

- compactc and fixup-compact support two new options: --compact-path to
  set the compact path and --trace-search to cause the compiler to say where
  it looks for include and external module files.  If the `--compact-path`
  command-line option is present, the environment variable `COMPACT_PATH`
  is ignored.

## [Unreleased toolchain 0.29.104, language 0.21.101, runtime 0.14.101]

### Added

- The generated TypeScript now includes a `ProvableCircuits<PS>` type and a
  `provableCircuits` field on the `Contract` class.  `ProvableCircuits` contains
  only the circuits that have verifier keys (i.e., circuits that appear in the
  flattened circuit IR and produce ZKIR files).  This distinguishes them from
  impure circuits that only call witnesses without touching the ledger.

### Fixed

- `setOperation` is now emitted only for provable circuits (those in
  `proof-circuit-name*`) rather than for all impure circuits.  Previously,
  witness-only impure circuits caused the runtime to look
  for a verifier key that does not exist.

## [Unreleased toolchain 0.29.103, language 0.21.101, runtime 0.14.101]

### Changed

- The standard library type `NativePoint` has been removed.  The standard
  library type `JubjubPoint` is now a `new type` alias for
  `Opaque<'JubjubPoint'>`.  This way `Opaque<'JubjubPoint'>` isn't really
  hidden, but it's not shown in error messages.
- `NativePoint` circuits in the standard library and the corresponding
  same-named functions in the Compact runtime have been renamed, and they now
  take or produce `JubjubPoint` values.
  - `nativePointX` -> `jubjubPointX`
  - `nativePointY` -> `jubjubPointY`
  - `constructNativePoint` -> `constructJubjubPoint`
- Signatures of elliptic curve operations in the standard library now use
  `JubjubPoint` in place of `NativePoint`.

### Internal notes

- The `compact fixup` tool can do these renamings except it cannot currently
  rename types (e.g. `NativePoint` to `JubjubPoint`).

## [Unreleased toolchain 0.29.102, language 0.21.100, runtime 0.14.100]

### Added

- There is a new builtin type `Opaque<'JubjubPoint'>`.  Unlike the other opaque
  types, this is intended to be a crypto backend (ZKIR) native type (not a JS
  type).  The standard library exports the type `JubjubPoint` which is a
  (transparent) `type` alias for the opaque type.

### Changed

- The standard library's (opaque) `new type` alias `NativePoint` now has
  underlying type `Opaque<'JubjubPoint'>`.
- The Compact runtime's types `CompactTypeNativePoint` and `NativePoint` are
  renamed to `CompactTypeJubjubPoint` and `JubjubPoint`.
- The runtime has TS (instead of Compact) implementations of the now-builtin
  `NativePointX` and `NativePointY` circuits.
- The feature flag `--zkir-v3` is changed to `--feature-zkir-v3` to fit a
  proposed standard naming convention, and to make crystal clear that it is
  still an experimental feature.

### Internal notes

- When the flag `--feature-zkir-v3` is enabled, `Opaque<'JubjubPoint'>` is
  represented natively in ZKIR v3.  Without the flag, it is still represented as
  a pair of field elements in ZKIR v2.
- This is implemented as a "pseudo"-alignment tag after flattening.  The tag
  looks like `(anative "JubjubPoint")` and it's interpreted as a `midnight-zk`
  JubjubPoint for ZKIR operations, converted to a pair of field values for
  the Impact code embedded in the ZKIR circuit.
- ZKIR v3 has new `encode` and `decode` gates for converting from ZKIR
  representations to Impact representations and back.
- ZKIR v3's `ec_add` has been eliminated; regular `add` is polymorphic,
  operating on either a pair of scalars or a pair of Jubjub curve points.
- ZKIR v3 has type annotations on circuit inputs and on `decode` instructions.
- ZKIR v3 has two types: `Scalar<BLS12-381>` and `Point<Jubjub>`.
- For both ZKIR v3 and ZKIR v2 modes, the JS representation of is still as a pair
  of field elements.

## [Unreleased toolchain version 0.29.101, language version 0.21.0]

### Changed

- In the formal grammar, the `stmt0` grammar production for one-armed
  `if` expressions has been removed.  It was unnecessary and made the grammar
  ambiguous.

## [Unreleased toolchain 0.29.100, language 0.21.0]

### Changed

The compiler binary can now report `--runtime-version`, the version of the
Compact runtime JS package that it will import in generated contract code.
