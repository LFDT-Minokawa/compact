# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Toolchain 0.33.101, language 0.25.100, runtime 0.18.0]

### Changed

- The compiler now tries sha256sum first, then shasum -a 256 when looking
  for a program to compute a sha256 hash.

## [Toolchain 0.33.100, language 0.25.100, runtime 0.18.0]

### Fixed

- The `ShieldedReceive` standard event now serializes its fields in the order
  specified by CoIP-442 and MIP-0002: `commitment`, `ciphertext`,
  `contractAddress` (previously `contractAddress` preceded `ciphertext`).
  Serialized size is unchanged (578). Fixes #590.

### Changed

- The standard library ECDSA circuits `secp256k1EcdsaVerify` and
  `secp256k1EcdsaRecover` deserialize the message hash as a big endian
  secp256k1 scalar `z` internally, following the ECDSA convention (RFC 6979).

## [Toolchain 0.33.0, language 0.25.0, runtime 0.18.0]

This release includes all changes for compiler versions in the range between
0.32.100 and 0.33.0; language versions in the range between 0.24.100 and 0.25.0;
and Compact runtime versions in the range between 0.17.100 and 0.18.0.

## [Toolchain 0.32.111, language 0.24.103, runtime 0.17.106]

### Changed

- `zkir` and `onchain-runtime-v4` use `ledger-9-rc.2`.

## [Toolchain 0.32.110, language 0.24.103, runtime 0.17.105]

### Added

- New Compact types for Jubjub and secp256k1 curves: builtin field types
  `JubjubScalar`, `Secp256k1Base`, and `Secp256k1Scalar` (the Jubjub base field
  is the native BLS12-381 Compact `Field` type), and the point type
  `Secp256k1Point`.
- The secp256k1 fields and curve points are **ONLY** supported by using the new
  ZKIR v3 backend at compile time.  This is enabled by passing the flag
  `--feature-zkir-v3` to the Compiler.  Using them with the default ZKIR v2
  backend is a compile-time error.
- The standard library has new circuits for verifying ECDSA signatures in
  Compact.

#### `JubjubScalar`
- There is a cast from `Field` to `JubjubScalar` and from `JubjubScalar` to
  `Field`.  The cast from `Field` to `JubjubScalar` will reduce the `Field`
  value modulo the Jubjub scalar modulus.  It will not fail, but do note that
  round tripping from `Field` to `JubjubScalar` and back will possibly give a
  different `Field` value.  The cast from `JubjubScalar` to `Field` will always
  succeed and give the same value (as a `Field`), because the maximum
  `JubjubScalar` value is less than the maximum `Field` value.
- There is a cast from all `Uint` types to `JubjubScalar`.  This cast behaves
  the same as the cast from `Field` to `JubjubScalar`, namely never failing but
  reducing values larger than the maximum Jubjub scalar by the Jubjub scalar
  modulus.  There is also a cast from `JubjubScalar` to all `Uint` types.  This
  cast will fail at runtime if the actual Jubjub scalar value is too large for
  the target `Uint` type.
- `default<JubjubScalar>` is zero.
- Arithmetic is not supported for the `JubjubScalar` type.  Equals and
  not-equals comparisons are supported, but other relational comparisons are not
  supported.
- The Compact runtime exports new `bigint` constants `JUBJUB_SCALAR_MODULUS` and
  `MAX_JUBJUB_SCALAR`.

#### secp256k1 fields
- There are casts to and from both `secp256k1` field types and `Bytes<32>`.  The
  `Bytes<32>` representation is little-endian.  The casts targeting `Bytes<32>`
  cannot fail (both fields' maximum values fit in 32 bytes).  The casts from
  `Bytes<32>` will fail if the resulting value would exceed the respective
  target type's maximum value.  Therefore, round tripping through `Bytes<32>`
  always succeeds and gives the same value; round-tripping through a secp256k1
  field type will only work if the original `Bytes<32>` is a valid value for
  that field.
- There are **NO** other casts to or from the secp256k1 field type from any
  other type.  Specifically, because there are no `Uint` casts and literals have
  `Uint` type, there is no way to use a literal as a secp256k1 field value (you
  can obtain one from a witness, though).
- `default<Secp256k1Base>` and `default<Secp256k1Scalar>` are zero.
- Arithmetic is supported via standard library circuits: `add` takes a pair of
  secp256k1 field values of the same type and returns a value of that type,
  `mul` takes a pair of secp256k1 field values of the same type and returns a
  value of that type, `neg` negates a secp256k1 field value and returns a value
  of the same type, `inv` returns the multiplicative inverse (for a value `x`,
  this is the value `y` such that `mul(x, y) == 1`).  All of these operations
  are performed modulo the respective field's modulus.
- Equals and not equals comparisons are supported for these same-typed values of
  these types, but other relational comparisons are not supported.
- The Compact runtime exports new functions to perform arithmetic operations in
  the respective field.  It exports constants for the field modulus and the
  maximum value.

#### secp256k1 points
- The standard library has circuits `secp256k1PointX` and `secp256k1PointY` to
  extract the affine X- and Y-coordinates of a value of type `Secp256k1Point`.
  These coordinates both have type `Secp256k1Base`.  There is no way in Compact
  to explicitly construct `Secp256k1Point`s from their coordinates (but note
  that they can be obtained from witnesses).
- `default<Secp256k1Point>` is the additive identity point (a point `y` such
  that `ecAdd(x, y) == x` for any point `x`.
- The elliptic curve operations `ecAdd`, `ecMul`, and `ecMulGenerator` are
  overloaded to work for secp256k1 types.  If `ecAdd` is given a pair of
  `Secp256k1Point`s it will return a `Secp256k1Point`.  If `ecMul` is given a
  `Secp256k1Point` and a `Secp256k1Scalar` it will return a `Secp256k1Point`.
  If `ecMulGenerator` is given a `Secp256k1Scalar` it will return a
  `Secp256k1Point`.
- Equals and not-equals comparisons between these points do not work reliably.
- The compact runtime exports new functions to perform these operations.  In the
  Compact runtime, `Secp256k1Point` is represented as an object with affine X-
  and Y-coordinates.  The additive identity point (this is the value of
  `default<Secp256k1Point>` is not representable with `x` and `y` coordinates;
  there is a property `identity` on the Compact runtime representation.  If
  `pt.identity` is true then the point is the identity point and the X- and
  Y-coordinates should be ignored.

#### ECDSA verification in Compact

- The standard library has a new circuit `secp256k1EcdsaVerify` that attempts to
  verify an ECDSA signature and returns a boolean value telling whether the
  verification succeeded.  If you want to ensure a signature verifies in
  Compact, you should `assert` that the value of `secp256k1EcdsaVerify` is true.
  This circuit takes (1) a message hash as Compact `Bytes<32>`, which must be
  produced by either `persistentHash` (SHA-256) or `keccak256` **in Compact**,
  (2) a signature as a value of a new standard library structure type
  `Secp256k1EcdsaSignature` containing a pair of `Secp256k1Scalar` values, and
  (3) the public key as a `Secp256k1Point`.
- The standard library has a new circuit `secp256k1EcdsaRecover` that recovers
  the public key from an ECDSA signature.  It returns the public key as a
  `Secp256k1Point`.  This circuit takes (1) a message hash as Compact
  `Bytes<32>`, which must be produced by either `persistentHash` (SHA-256) or
  `keccak256` **in Compact**, and (2) a signature value of a new standard
  library structure type `Secp256k1EcdsaSignatureWithRecovery`.  This has a pair
  of `Secp256k1Scalar` values (the signature) and the signing nonce point as a
  `Secp256k1Point` computed outside of Compact (e.g. as a witness return value
  or a circuit argument).  This is computed outside Compact to avoid an
  expensive square root computation in the secp256k1 base field,
  `secp256k1EcdsaRecover` asserts in circuit that the X-coordinate of this point
  matches the signature's `r` (when cast to Compact `Bytes<32>`, that is as
  32-byte little-endian representations).
- **NOTE:** these circuits use the secp256k1 curve and field types, and
  consequently they are unavailabe with the default ZKIR v2 backend.  Pass the
  flag `--feature-zkir-v3` at compile time to enable them.

### Changed

- The standard library circuit `ecMul` now requires the second argument to have
  type `JubjubScalar` when the first argument has type `JubjubPoint`.
  Previously this type was `Field`.  The standard library circuit
  `ecMulGenerator` requires its argument to have type `JubjubScalar`.
  Previously this type was `Field`.
- `Field` is no longer a supertype of `Uint` types.  This is a major **BREAKING
  CHANGE**.  `Uint` values will no longer be implicitly cast to `Field` types in
  many contexts, and an explicit `as Field` cast will be required.  This
  **specifically** affects numeric literals.  The literal `n` has exact type
  `Uint<0..n+1>`, which is no longer implicitly cast to `Field` type.
  Effectively, there are no longer any `Field` literals in Compact, and you must
  write, e.g., `7 as Field`.  **NOTE:** we might later change this behavior by
  allowing `Field` literals in some way.
- An exception is in arithmetic.  The rules for binary arithmetic operations
  (addition, subtraction, multiplication) are **unchanged**: if one operand has
  type `Field` and the other has a `Uint` type, then the `Uint` value is cast to
  a `Field` value and `Field` arithmetic is used.  Where formerly this inserted
  cast was an upcast (from a subtype to a supertype), it is no longer an upcast
  (`Field` and `Uint` types are unrelated by subtyping), but it is still
  implicit.  **NOTE:** we might later change this behavior.

## [Toolchain 0.32.109, language 0.24.102, runtime 0.17.104]

### Added

- The compiler usage page now introduces `--feature-zkir-v3`.

## [Toolchain 0.32.108, language 0.24.102, runtime 0.17.104]

### Fixed

- a bug that prevented `contract-manifest.json` from including some file hashes

## [Toolchain 0.32.107, language 0.24.102, runtime 0.17.104]

### Changed

- The generated zkir reverted back to having separate impact instructions.

## [Toolchain 0.32.106, language 0.24.102, runtime 0.17.104]

### Changed

- Adds `domainSep` to `UnshieldedSpend` and `UnshieldedReceive` events.
- Renames event fields to follow camelCase.

## [Toolchain 0.32.105, language 0.24.102, runtime 0.17.104]

### Added

- Multi-contract systems: contract types, contract references, and
  cross-contract calls (see [CoIP-2](coips/coip-0002.md)). This is the first
  stage of support for multiple contracts that work together as a system. The
  new language constructs are:
  - `contract` type declarations, naming a collection of circuit
    signatures (parameter types, return type, and purity) that another
    contract may depend on.
  - The `contract implements C;` assertion. A contract implements a contract type
    whenever it exports a matching circuit for each one the contract type declares
    -- but when the assertion is present the compiler verifies it and rejects
    the contract at compile time if any required circuit is missing or has a
    non-matching signature.
  - Contract references: a contract type is an ordinary
    program-defined type and may be used as a circuit or witness parameter, a
    struct field, or the element/value type of a ledger collection (e.g.
    `List<C>`, `Map<Field, C>`). A reference is introduced
    from application code by passing a deployed contract's address where a
    value of the contract type is expected.
  - Cross-contract calls: `reference.circuit(args...)` invokes a circuit
    named in the reference's type.
- Adds runtime support for cross-contract calls (CCC), the execution machinery
  behind contract interfaces, contract references, and one contract's circuit
  calling another's (see CoIP-2). Two new modules are added and re-exported from
  the package index:
  * `contract.ts`, exporting `crossContractCall` — invokes a circuit on
    another contract from within the executing circuit, threading the callee's
    ledger state, gas, and proof data back into the caller's context and
    emitting the `Kernel.claimContractCall` transcript that links the two.
  * `providers.ts`, exporting the `ContractStateProvider` interface — a
    user-supplied `getContractState(blockHash, address)` used to fetch a
    cross-contract callee's deployed public state at runtime. The
    `parentBlockHash` recorded on the context is passed as the `blockHash`.
- **Breaking:** `CircuitContext` is restructured to model a whole call tree
  rather than a single contract execution.
  * Per-call state moves into a new `callContext: CallContext<PS>` member
    (`circuitId`, `contractAddress`, `initialQueryContext`,
    `currentQueryContext`, `currentGasCost`, `currentPrivateState`,
    `currentZswapLocalState`, `parentBlockHash`, `time`). Fields previously at
    the top level — `currentPrivateState`, `currentZswapLocalState`, and
    `currentQueryContext` — are now reached through `callContext`.
  * New top-level members: `queryContexts` and `gasCosts` (per-contract-address
    maps spanning the call tree), `contractStates` (retained deployed states of
    resolved callees, so the verifier-key guard can run on every call),
    `callProofDataTrace` (depth-first sequence of `CallProofData` for the root
    circuit and every sub-call), `stateProvider`, `reentrancyGuard`, and
    `activeContracts`.
- **Breaking:** `createCircuitContext` gains a leading `circuitId` argument and
  new trailing `stateProvider`, `parentBlockHash`, and `reentrancyGuard`
  arguments. Its full signature is now `(circuitId, contractAddress,
  coinPublicKeyOrZswapState, contractState, privateState, stateProvider?,
  gasLimit?, costModel?, time?, parentBlockHash?, reentrancyGuard?)`. The
  `stateProvider`, `parentBlockHash`, and `reentrancyGuard` arguments are only
  needed by circuits that make cross-contract calls.
- **Breaking:** `CircuitResults` no longer carries a `proofData` field. The
  proof data for each circuit run (root and sub-calls) is now collected in
  `callProofDataTrace` on the context.
- Adds dynamic safety guards on every cross-contract call:
  * Re-entrancy guard — entering a contract already executing on the call
    stack (`A -> A`, or `A -> B -> A`) throws a `CompactError`. Enabled by
    default; pass `reentrancyGuard: false` to `createCircuitContext` to opt
    out (e.g. tests that deliberately exercise recursion).
  * Implementation-binding guard — hashes the deployed verifier key for the
    called circuit (SHA-256) and compares it to the `expectedVk` fingerprint
    the compiler emits onto the contract module; a mismatch throws the new
    `ContractInterfaceMismatchError`, rejecting a call whose target address
    points at a different contract than the interface resolves to.
  * Purity guard — a callee whose actual purity disagrees with the interface's
    `pure` declaration is rejected.
  * Witness guard — a cross-contract callee that invokes a witness throws a
    `CompactError`; called contracts must have no private state.
  * Calling the default (dummy) contract address throws a `CompactError`.
- Error module (`error.ts`):
  * `CompactError` now carries a readonly `isCompactError` brand so consumers
    can reliably distinguish compiler-originated errors from other failures.
  * Adds `ContractInterfaceMismatchError` (extends `CompactError`).
  * Adds internal `assertDefined` / `assertUndefined` assertion helpers.
- Utilities (`utils.ts`): adds `assertIsContractAddress`, which throws a
  `CompactError` for values that are not contract addresses.
- Zswap (`zswap.ts`): `createZswapInput`, `createZswapOutput`, `ownPublicKey`,
  and `hasCoinCommitment` now read and write Zswap local state and the query
  context through `circuitContext.callContext`, following the context
  restructure. A new `assertHasCurrentZswapLocalState` check makes these
  operations throw a `CompactError` when there is no Zswap local state — for
  example inside a cross-contract callee, which has none.
- Adds new exported types and helpers used by the above: `CircuitId`,
  `CallContext`, `CallProofData`, `CallProofDataTrace`,
  `CommunicationCommitmentData`, `createCallContext`, `copyCircuitContext`,
  `finalizeCallProofData`, and a now-exported `createInitialQueryContext` (which
  gains `parentBlockHash` and `caller` parameters and a required `time`).

## [Toolchain 0.32.104, language 0.24.101, runtime 0.17.103]

### Added

- The new language form `emit(expr)` emits a an event.  `expr` must have a
  standard event type.  Constructors cannot emit an event, either directly
  or indirectly via calls to circuits that use `emit`.  Calling `emit` makes
  a circuit impure.
- The onchain-runtime requires the argument passed to `emit` to be serialized.
  Compact's standard library provides a generic `serialize<T,n>` and
  `deserialize<T,n>`.  The end user cannot see their definition,
  but they can see their type signature in Compact's standard library. 

### Changed

- The generic `serialize` and `deserialize` are defined in `midnight-inlines.ss`
  and the macro expansion is defined in `inlines.ss` and they are inserted during
  `expand-modules-and-types`.
- The TypeScript wrapper for each impure exported circuit now exposes an
  `events` field on the wrapped return value, and a corresponding `events`
  field on `CircuitContext`.  Both refer to the same array; events emitted
  by `emit` expressions during the circuit's execution are appended in order
  of evaluation.  Pure circuits' wrapped return values are unaffected.
- Updates the compact-runtime: adds the required `events` field
  to `CircuitContext` and `CircuitResults`.  This is a **breaking** change
  for TypeScript code that constructs these types by hand; code that uses
  the runtime's `createCircuitContext` helper is unaffected.

### Internal notes

- The standard event types are defined in `compiler/midnight-events.ss` in
  a DSL that is defined in `compiler/events.ss`.  Events are injected into
  CompactStandardLibrary during `expand-modules-and-types`.
- Some of the downstream type checkers did not handle `let*` forms with
  multiple bindings properly but now do.  This was not previously a problem
  because the upstream passes did not produce such `let*` forms.

## [Toolchain 0.32.103, language 0.24.0, runtime 0.17.102]

### Changed

- Pulls in ledger-9.1.0.0-rc.3

## [Toolchain 0.32.102, language 0.24.0, runtime 0.17.101]

### Fixed

- Code generation for certain casts.

## [Toolchain 0.32.101, language 0.24.0, runtime 0.17.101]

### Changed

- Pulls in ledger-9.1.0.0-rc.2. Note for pulling in alpha versions of the ledger:
  in `runtime/package.json` remove the onchain-runtime dependency and update the
  onchain-runtime nixDependency, in `runtime` run
  `npm install --package-lock-only --ignore-scripts`, in `compact` run `nix build`
- The runtime pulls in onchain-runtime-v4.

## [Toolchain 0.32.0, language 0.24.0, runtime 0.17.0]

This release includes all changes for compiler versions in the range between
0.31.100 and 0.32.0; language versions in the range between 0.23.100 and 0.24.0;
and Compact runtime versions in the range between 0.16.100 and 0.17.0.

## [Toolchain 0.31.108, language 0.23.105, runtime 0.16.101]

### Added

- Add `ecNeg` to the standard library for JubJub point negation.

## [Toolchain 0.31.107, language 0.23.104, runtime 0.16.101]

### Fixed

- Fix [issue #456](https://github.com/LFDT-Minokawa/compact/issues/456), a ZKIR
  v2 bug in Schnorr signature verification.  This change also fixes a bug in
  Schnorr signature verification for the experimental ZKIR v3 backend.

### Internal notes

- The Schnorr signature verification feature is unreleased (added in toolchain
  0.31.104).

## [Toolchain 0.31.106, language 0.23.104, runtime 0.16.101]

### Added

- The compiler now writes a manifest to the file `contract-manifest.json` in the
  `compiler` subdirectory of the target directory.  The manifest contains sizes
  and sha256 sums for each of the generated files except `contract-manifest.json`
  itself.

### Changed

- The compiler now removes and recreates the `contract` subdirectory of target
  directory.  While previous versions removed and recreated the `compiler`, `zkir`,
  and `keys` directory they left the `contract` subdirectory _and its contents_
  in place and instead replaced only the target files `index.dts`, `index.js`,
  and `index.js.map`.

- The compiler now always creates the `keys` subdirectory of the target
  directory.  The `keys` directory will be empty, however, if the --skip-zk
  flag is used, the zkir binary isn't found, or none of the contracts circuits
  require proofs.

## [Toolchain 0.31.105, language 0.23.104, runtime 0.16.101]

- The ZKIR v3 format, behind the feature flag `--feature-zkir-v3`, has changed
  so that:
    - it contains an `outputs` field that is a list containing the type of each
      output of the circuit
    - it contains a single `output` instruction that specifies a list of output
      operands and is the last instruction

## [Toolchain 0.31.104, language 0.23.104, runtime 0.16.101]

### Added

- Schnorr signature verification over the JubJub embedded curve, via the new
  `JubjubSchnorrSignature` struct and `jubjubSchnorrVerify` circuit in the
  standard library.

## [Toolchain 0.31.103, language 0.23.103, runtime 0.16.100]

### Added

- Adds `keccak256` to the standard library, with the same signature as
  `persistentHash`.  Adds `keccak256` to the Compact runtime with the same
  signature as `persistentHash`.  `keccak256` requires the experimental feature
  flag `--feature-zkir-v3` to work in a circuit that directly or indirectly uses
  the public ledger state.  It is a compiler error to use it in a such a circuit
  using the ZKIR v2 backend.

## [Toolchain 0.31.102, language 0.23.102, runtime 0.16.0]

### Added

- `eval` and `arguments` which are reserved words in strict mode of JavaScript are now
  added as future reserved words in Compact. Previously Compact accepted a contract using
  these as an identifier, resulting in producing an invalid JavaScript output.

### Fixed

- Lexer matches the convention used by
  ECMAScript (https://tc39.es/ecma262/#sec-names-and-keywords) and
  UAX #31 (https://www.unicode.org/reports/tr31/#Table_Lexical_Classes_for_Identifiers):
  the lexer accepts Unicode `ID_Start` (`Lu Ll Lt Lm Lo Nl`) plus `_` and `$`.
  Previously it accepted all alphabetic charactes which includes some non-`ID-Start`
  characters which are invalid in JavaScript.
  `identifier-subsequent?` now follows Unicode `ID_Continue` (`Lu Ll Lt Lm Lo Nl Mn Mc Nd Pc`).
  Previously it included som non-`ID-Continue` characters.

## [Toolchain 0.31.101, language 0.23.101, runtime 0.16.0]

### Added

Adds `event` and `log` as future keywords that are reserved.

## [Toolchain 0.31.0, language 0.23.0, runtime 0.16.0]

This release includes all changes for compiler versions in the range between
0.30.100 and 0.31.0; language versions in the range between 0.22.100 and 0.23.0;
and Compact runtime versions in the range between 0.15.100 and 0.16.0.

## [Toolchain 0.30.107, language 0.22.101, runtime 0.15.101]

### Fixed

Various zkir operators that can result in assertion failures and thus should
be executed conditionally do not have guards are thus actually executed
unconditionally.  This can result in proof failures for correct transactions.
For example, casting an unsigned integer value to a smaller unsigned type will
always cause the proof to fail when the value is too big for that type, even if
the cast occurs in a branch that is not taken in the Compact code.

The intent is to add guards to these operators in the next version of zkir.
In the meantime, the compiler implements workarounds that arrange to invoke
these operators with inputs that cannot cause assertion failures when the
guard would be false.

The downside of these workarounds is that they can increase the size of the
generated circuit.
The size increase arises from conditional use (i.e., use in the `then` or
`else` part of an `if` statement or expression) of:

- downcasts from Uint types to smaller Uint types,
- downcasts of Field to Uint types,
- conversions of byte vectors to and from fields or unsigned integers,
- conversions of vectors to byte vectors, and
- uses of relational comparison expressions (<, <=, >=, and >) with inputs
  that might be unknown.

If the increase in circuit size is problematic for a particular contract, developers
should consider moving downcasts, conversions, and relational comparisons outside
of `if` expressions where possible until zkir supports the required guards and the
compiler workarounds have been removed.

## [Toolchain 0.30.106, language 0.22.101, runtime 0.15.101]

### Added

- Adds a `ledger` key to `contract-info.json` listing the contract's
  ledger fields. Each entry contains the field name, path index,
  export status, storage kind (Cell, Counter, Map, Set, List,
  MerkleTree, HistoricMerkleTree), and fully-resolved type tree.
  This enables language-agnostic tooling to discover a contract's
  ledger layout from the compiler output alone. Both exported and
  non-exported fields are included since the full layout is required
  to navigate the on-chain state tree and construct initial states.

## [Toolchain 0.30.105, language 0.22.101, runtime 0.15.101]

### Added

- Adds `--line-length` flag to fixup.

### Fixed

- JubjubPoint equality is now component-wise; it previously was reference
  equality.

## [Toolchain 0.30.104, language 0.22.101, runtime 0.15.101]

### Changed

- Renames `doc/lang-ref.mdx` and `compiler/lang-ref-proto.mdx` to
  `doc/compact-reference.mdx` and `compiler/compact-reference-proto.mdx`,
  respectively.  It also adopts some changes from midnight-docs PR changes
  for lang-ref 1.0.

## [Toolchain 0.30.103, language 0.22.101, runtime 0.15.101]

### Changed

- The language reference `doc/lang-ref.mdx` is now been fully revised and
  is completely up-to-date with the Compact Version 1.0 language.  Grammar
  snippets are automatically inserted into the document directly from parser.ss,
  and several changes have been made to the presentation of the grammar to
  make it more readable.

## [Toolchain 0.30.102, language 0.22.101, runtime 0.15.101]

### Changed

- Extends the `for (const i of start..end) stmt` syntax to allow `start` and
  `end` to be references to generic parameters.

## [Toolchain 0.30.101, language 0.22.0, runtime 0.15.101]

- Changes the format of the first argument passed to `convertBytesToUint` in `print-typescript` 
- Improves format of error messages for `convertBytesToUint` and `convertBytesToField`
- Changes the type of `maxval` to `bigint` to avoid JavaScript silently losing precision
  when comparing `x > maxval` for larg `Uint`s

## [Toolchain 0.30.0, language 0.22.0, runtime 0.15.0]

This release includes all changes for compiler versions in the range between
0.29.100 and 0.30.0; language versions in the range between 0.21.100 and 0.22.0;
and Compact runtime versions in the range between 0.14.100 and 0.15.0.

## [Unreleased toolchain 0.29.114, language 0.21.101, runtime 0.14.102]

### Changed

- The language reference `doc/lang-ref.mdx` is now largely up-to-date with
  the Compact 0.21.0 language.
- The HTML version of the formal grammar in `doc/Compact.html` has been
  replaced with a markdown (mdx) version in `doc/compact-grammar.mdx`.

### Added

- A list of Compact's keywords and reserved words, including those reserved
  for future use, is given in `doc/compact-keywords.mdx`.

## [Unreleased toolchain 0.29.113, language 0.21.101, runtime 0.14.102]

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

## [Toolchain version 0.29.0, language version 0.21.0]

This release includes all changes for compiler versions in the range
0.28.100 and 0.29.0; and language versions in the range 0.20.100 and
0.21.0.  It uses Compact runtime 0.14.0 and on-chain runtime
compatible with 2.0.0.

## [Unreleased compiler 0.28.109, language 0.20.102]

### Fixed

- The fixup tool fixup-compact.ss failed to look for include files and modules
  relative to the directory of the source pathname.

## [Unreleased compiler 0.28.108, language 0.20.102]

### Removed

- The syntax for external circuits, i.e., circuit definitions with no body,
  has been removed.  This syntax was used exclusively for declaring built-in
  natives and was not useful outside of the compiler.

### Internal notes

- The compiler now injects natives directly into the standard library module.
  This is simpler and gives us a single source of truth for natives.

## [Unreleased compiler 0.28.107, language 0.20.101]

### Fixed

- An issue that caused transactions involving `mintShieldedToken`, `sendShielded`, `mintUnshieldedToken`, or
  `sendUnshielded` to fail validation with `RealUnshieldedSpendsSubsetCheckFailure` when the caller was also the 
  recipient of the newly minted token.

## [Unreleased compiler 0.28.106, language 0.20.100]

### Fixed

- An issue that caused the compiler to take an excessive amount of time to compile
  certain `for` loops, `fold` expression, and `map` expressions.

- An bug that caused the compiler to miss some of certain repeated disclosures
  of a witness value and to overstate the nature of certain other disclosures.

### Changed

- Messages about undeclared witness-value disclosures are now produced in an order
  that attempts, for each disclosure point and witness value, to put the most severe
  disclosures along the shortest paths first, since understanding these is easier
  and properly declaring them often addresses the others.

### Internal notes

- The underlying issue was the representation and maintenance of paths in the
  witness-protection program, and this has been replaced by a simpler mechanism
  with some careful crafting of the code to reduce computational complexity and
  generally make the compiler more efficient.

## [Unreleased compiler 0.28.105, language 0.20.100]

### Added

- The file compiler/contract-info.json that compactc generates in the output
  directory now includes some extra information: (1) version strings for the
  compiler, language, and runtime, and (2) for each circuit, a flag saying whether
  the circuit requires a proof (and therefore whether compactc has produced zkir
  code and prooving keys for it in the zkir and keys subdirectories of the output
  directory).

- ARM Linux artifact is added.

### Internal notes

- Adding the proof flag involved moving the pass that saves the contract-info file
  later in the compiler.  This in turn uncovered a couple of bugs in the preliminary
  handling of (as yet unsupported) cross-contract calls.  These have been fixed,
  though the code remains largely untested.  The zkir passes now recognize
  cross-contract calls and explicitly reject them as unsupported.

## [Unreleased compiler 0.28.104, language 0.20.100]

### Fixed

- A bug reported in issue [#34](https://github.com/LFDT-Minokawa/compact/issues/34) in which 
  `ChargedState` was not properly copied resulting in junk metadata being passed to contract deployments.

## [Unreleased compiler 0.28.103, language 0.20.100]

### Fixed

- A bug in the experimental `--zkir-v3` feature.  The on-chain representation of
  coin commitments changed between ledger version 6.1 and 6.2.  The domain
  separator string is changed, and the inputs to `persistentHash` are in a
  different order.

  This was already implemented for the default ZKIR v2, but the corresponding
  change was not implemented in the ZKIR v3 compiler passes.

## [Unreleased compiler 0.28.102, language 0.20.100]

### Changed

- For any circuit that returns something other than `[]` and for which some path through
  the circuit does not end in `return` form or ends in a `return` form without
  a return-value expression, the resulting error message now clearly states that
  this is the problem.

## [Unreleased compiler 0.28.101, language 0.20.100]

### Added

- Added a constructor, `constructNativePoint`, for `NativePoint` values

### Changed

- Renamed the existing accessors `NativePointX` and `NativePointY` to `nativePointX`
  and `nativePointY` for consistency with our conventions for circuit names.

## [Unreleased compiler 0.28.100, language 0.20.0]

There are no user-visible changes.

### Internal notes

- Instead of pulling test contracts from the separate (private) repository
  `midnight-contracts`, they are added to this repository under
  `test-center/test-contracts`.
  
## [Unreleased compiler 0.28.100, language 0.20.0]

### Changed

- The informal parser rule that "else" clauses belong to the innermost "if"
  expression is now explicit in the grammar.  Previously, we were relying on a
  shaky assumption about how the parser generator treats grammar ambiguities.
  This change is reflected in the formal grammar specification in doc/Compact.html
  but has no impact on how programs are compiled.

## [Compiler version 0.28.0, language version 0.20.0]

This release includes all changes for compiler versions in the range 0.27.100
(inclusive) and 0.28.0 (exclusive); and language versions in the range 0.19.100
(inclusive) and 0.20.0.  It uses compact-runtime 0.14.0-rc.0 and 
on-chain runtime 2.0.0-alpha.1.

## [Unreleased compiler version 0.27.113, language version 0.19.103]

### Changed

- The formatter's handling of several forms has been improved:
  - When the signature of a function needs to be broken up into multiple lines,
    the parameter list is also broken up into multiple lines (even if it would itself
    fit on one line), and the return-type declaration appears on a line following
    the last parameter declaration. This change applies to circuit definitions,
    external declarations, witness declarations, the constructor, and anonymous
    circuit definitions.
  - When a call expression needs to be broken up into multiple lines, the argument
    list is also broken up into multiple lines (even if it would itself
    fit on one line), and the closing parenthesis of the call appears on a line
    following the last argument expression.
  - When an anonymous circuit needs to be broken up into multiple lines, the body
    of the circuit is indented a few spaces in from the start of the parameter
    list rather than all the way out beyond the circuit's signature.
  - When the "else" expression of an "if" expression is itself an "if" expression,
    the inner "if" expression begins on the same line as the "else" and appears at
    at the same level of indentation as the outer "if" expression, in a case-like
    structure.  This special treatment is inhibited by end-of-line comments between
    the outer "else" keyword and the inner "if" keyword.

- The formatter now accepts a --line-length <n> parameter that sets the target line
  length to <n>.  The default line length currently defaults to 100.  The target line
  length can be exceeded in cases where the formatter considers the portion of input
  to be fit on a line to be unbreakable.

### Internal notes

- Configuration parameters have been collected into a single new library, (config-params)

- The formatter line length is now a configuration parameter, set to 100 by default.

- compiler/go now catches keyboard interrupts while running the tests and aborts the tests.

- compiler.md now more accurately describes the composition of the token stream.

- The formatter improvements are supported by the following changes:
  - add-block (appropriately renamed make-Qblock, since it returns a block)
    has been simplified to take a header rather than a proc that produces a header
  - make-Qsep has been split into two routines, one that expects a closer and one
    that doesn't.
  - make-Qsep and make-Qconcat now take an inherit-break? flag whose value is
    recorded in the resulting Qconcat record.  Processing a Qconcat with this
    flag set in the context in which lines are being broken causes the contents
    of the Qconcat itself to be broken into multiple lines.  The contents of a
    Qconcat q with this flag set are still indented relative to q.
  - The code for handling function signatures is now commonized into a single
    constructor make-Qsignature.

## [Unreleased compiler version 0.27.112, language version 0.19.103]

### Changed

- The Compact standard library structure type NativePoint (nee CurvePoint)
  is now a nominal type alias for an unexported internal type.  The standard
  library also now exports two new circuits, NativePointX and NativePointY,
  that can be used to access the x and y coordinates of a native point as Fields.
  This is a breaking change because the internal representation of NativePoint
  is no longer exposed.

- In type errors produced by the Compact compiler, Nominal type aliases are
  now shown simply as TypeName rather than as TypeName=Type.

## [Unreleased compiler version 0.27.111, language version 0.19.102]

### Changed

- Changes `CurvePoint` to `NativePoint`

## [Unreleased compiler version 0.27.110, language version 0.19.101]

### Changed

- Fixes PM-19299 by having `createZswapInput` and `createZswapOutput` return
  an empty array to represent the `[]` type in Compact.

## [Unreleased compiler version 0.27.109, language version 0.19.101]

### Changed

- The compiler now targets ledger version 7.0 instead of 6.2.  There are no API
  changes between 6.2 and 7.0 so it is only necessary to pull in a new
  implementation of the on-chain runtime and bump version numbers.  This is
  **not** a breaking change.

## [Unreleased compiler version 0.27.108, language version 0.19.101]

### Added

- The reserved words from TypeScript and JavaScript are now included in our
  future reserved words.

## [Unreleased compiler version 0.27.107, language version 0.19.100]

### Changed

- The compiler now targets ledger version 6.2 instead of 6.1.  This ledger
  version has changes to Zswap hashing made in response to ledger audit
  feedback.

- There are standard library changes to **non-exported** structs and circuits,
  so this is **not** a breaking change.

## [Unreleased compiler version 0.27.106, language version 0.19.100]

### Fixed

- Bugs in unreleased code preventing proper behavior of type aliases for certain
  uses of ADT types, including ledger operations that treat parameters of type
  QualifiedCoinInfo differently and the += and -= operators for incrementing
  Counters.

## [Unreleased compiler version 0.27.105, language version 0.19.100]

### Changed

- The compiler no longer generates zkir code or proving keys for circuits that
  do not directly touch the ledger.  Previously, it generated zkir code and
  proving keys for all impure circuits, so merely calling a witness or invoking
  one of the witness-like external circuits (`ownPublicKey`, `createZswapInput`,
  `createZswapOutput`) would also trigger zkir and proving-key generation.

## [Unreleased compiler version 0.27.104, language version 0.19.100]

### Fixed

- The compiler now rejects programs whose constructors contain array-reference,
  and bytes-reference, and slice expressions with out-of-bounds indices.
  Previously, such errors could lead to these expressions producing undefined
  values at run time.

## [Unreleased compiler version 0.27.103 language version 0.19.100]

### Added

- Compact now supports the definition of type aliases:
  Structually typed aliases:
    `type Name = Type;` defines `Name` to be an alias for `Type`.  For example,
    `type U32 = Uint<32>` defines `U32` to be the equivalent of and interchangeable
    with `Uint<32>`.

  Nominally typed aliases:
    `new type Name = Type;` is similar, but `Name` is defined as a distinct type
    compatible with `Type` but neither a subtype of nor a supertype of `Type` or
    any other type.  It is compatible in the senses that (a) values of type `Name`
    can be used by primitive operations that require a value of type `Type`, and
    (b) values of type `Name` can be explicitly cast to and from type `Type`.
    For example, within the scope of `type V3U16 = Vector<3, Uint<16>>`, a value
    of type `V3U16` can be referenced or sliced just like a vector of type
    `Vector<3, Uint<16>>`, but it cannot, for example, be passed to a function
    that expects a value of type `Vector<3, Uint<16>>` without an explicit cast.

    When one operand of an arithmetic operations (e.g., `+`) receives a value
    of some nominally typed alias T, the other operand must also be of type T,
    and the result is cast to type T, which might cause a run-time error if the
    result cannot be represented by type T.

    Values of some nominally typed alias T cannot be directly compared (using,
    e.g., `<`, or `==`) with values of any other type without an explicit cast.

  Both types of aliases can take type parameters, e.g.:
  `type V3<T> = Vector<3, T>`
  `new type VField<#N> = Vector<N, Field>`

  This is a breaking change due to the reservation of the `new` and `type` keywords.

### Changed

- Out-of-range constant Bytes value indices are now detected earlier in the
  compiler, which means that additional such errors might be caught, specifically
  those in code that is later discarded.  This is a breaking change.

- Upward casts no longer prevent tuple references and slices from recognizing
  constant indices, which allows more programs with references to non-vector tuple
  types to pass type checking.

### Fixed

- A bug that caused a misleading source location to be reported for some type
  errors, e.g., for invalid arguments to some calls to `map` and `fold`.

### Internal notes

- The Public-ledger ADT (`public-adt`) form, which describes the type of a
  public-ledger ADT, has been replaced by a new Type `tadt` throughout the compiler.
  This simplifies and regularizes the representation of types and allows type
  aliases to be used for ADT types as well as for non-ADT types.

- Equality testing in the unit-test framework has been tightened up to avoid
  false positives when the expected output uses different symbols to represent
  what turns out to be the same id or gensym in the actual output.  This can
  occur when the expected output is wrong or the compiler actually generates
  code that uses the same id or gensym for different purposes.  Several instances
  of the first have been fixed in the unit tests.

- A new checker, `pass-returns`, as been added to the unit-test framework.  It
  is like `returns` but checks the output of a specific pass.  This is intended
  to allow us to move toward having a single occurrence with checks for multiple
  passes rather than having to put multiple copies of the same test in different
  test groups.

- A new form `(assertf expr format-string arg ...)` has been added to utils.ss.
  Like `(assert expr)`, it returns the value of `expr` if `expr` evaluates to a
  true value and raises an exception if `expr` evaluates to #f.  Its error message
  includes the source location of the `assertf` form, as with `assert`, and also
  the result of applying `format` to `format-string` and `arg ...`.  `assertf`
  is useful in preference to `assert` when the assertion expression does not
  already indicate the problem and the problem is not otherwise obvious from the
  context.

- internal-errorf now also includes the source location in the error message.

## [Unreleased compiler version 0.27.102, language version 0.19.0]

### Changed

- The unique variable names in the ZKIR v3 output are now produced in such a way
  that they are stable in the face of changes in the order or set of circuits
  generated.  That is, if the generated zkir for a circuit doesn't otherwise
  change, the variable names should also be identical.

### Internal notes

- Running the unit tests in test.ss now produces the file replacement-results.ss
  containing one entry for each result that differs from the expected result,
  e.g., each returns form when the returned result is different, each oops
  form when the condition is different, each output-file result with the
  output is different, etc.  No entry is included for unexpected exceptions,
  e.g., no entry is included for a return form if an exception occurs instead.
  If replacement-results.ss would be empty, it is deleted and not created.
  The new program compiler/update-test.ss takes as input the pathname of the
  test file (usually compiler/test.ss), the pathname of the replacements file
  (usually replacement-results.ss), and the pathname of an output file (e.g.,
  /tmp/test.ss).  Bad things will happen if the output pathname identifies that
  same file as the input pathname.  update-test.ss applies the replacements in
  the replacements file to the input file and puts the result in the output file.
  The output file can then be manually copied over the input file.  This is useful
  primarily when making cosmetic changes that affect a large number of tests and
  only after spot-checking to make sure that the cosmetic change is doing no harm.

## [Unreleased compiler version 0.27.101, language version 0.19.0]

### Changed

- The ZKIR v3 format (behind the feature flag --zkir-v3) is changed to coalesce
  an Impact instructions encoding into a guarded array.  Previously they were
  multiple unguarded instructions followed by a guarded "skip" instruction.

## [Unreleased compiler version 0.27.100, language version 0.19.0]

### Fixed

- Use of `return` statements among the statements comprising the body of a `for`
  loop are not supported.  Previously, such uses resulted in strange run-time
  behavior or confusing compile-time error messages.  The compiler now explicitly
  flags such uses as static errors with an appropriate error message.

## [Compiler version 0.27.0, language version 0.19.0] - Branched 2025-11-19

This release includes all changes for compiler versions in the range 0.26.100
(inclusive) and 0.27.0 (exclusive); and language versions in the range 0.18.100
(inclusive) and 0.19.0.

## [Unreleased compiler version 0.26.121 language version 0.18.103]

### Changed

- Changed the intermediate languages leading up to Lexpr to reflect that circuit
  and constructor bodies must be blocks rather than arbitrary statements.  reworked
  hoist-local-variables to avoid a dependency on a fluid variable.  These are not
  user-visible changes.

## [Unreleased compiler version 0.26.120 language version 0.18.103]

### Changed

- Changed the (experimental, not yet announced) ZKIR v3 format to use symbolic
  names instead of indexes for instruction inputs and ouputs.

## [Unreleased compiler version 0.26.119 language version 0.18.103]

### Fixed

- The type checker was not raising an exception for casts from Bytes<0> values
  to Field or Uint values and vice versa, which led to confusing downstream errors
  in some cases.

## [Unreleased compiler version 0.26.118 language version 0.18.103]

### Added

- Four new kernel operations, `mintUnshielded`, `claimUnshieldedCoinSpend`, `incUnshieldedOutputs`, and
  `incUnshieldedInputs`.
- Eight new standard library functions, `mintUnshieldedToken`, `sendUnshielded`, `receiveUnshielded`,
  `unshieldedBalance`, `unshieldedBalanceLt`, `unshieldedBalanceGte`, `unshieldedBalanceGt`, `unshieldedBalanceLte`.

### Changed

- Updates the repository to use ledger `6.1.0-alpha.5`, i.e., `@midnight-ntwrk/onchain-runtime-v1` version `1.0.0-alpha.5`.
- Changes names like `QualifiedCoinInfo` and `CoinInfo` to be `QualifiedShieldedCoinInfo` and `ShieldedCoinInfo` to
  match the names in the new on-chain runtime.
- Renames standard library functions to distinguish between shielded and unshielded token utilities.

## [Unreleased compiler version 0.26.117 language version 0.18.102]

### Fixed

- A bug in which types other than tuple, vector, and bytes do not result in an internal
  error when checking the bounds of an index.  This was an unreleased bug, that is,
  the bug was created in an unreleased version of the compiler.

## [Unreleased compiler version 0.26.116 language version 0.18.102]

### Fixed

- A bug in which unimported modules enclosed in unimported modules are not processed
  to detect and report certain errors, including type errors.  While it is
  essentially harmless not to process unimported modules since code in unimported
  modules is never run, this fix potentially allows some issues to be detected
  earlier in the application development process.

## [Unreleased compiler version 0.26.115 language version 0.18.102]

### Fixed

- A bug in which the compiler sometimes mentioned the same incompatible function
  more than once in the error message produced when no function with compatible
  generic or run-time parameters is found at a call site.

## [Unreleased compiler version 0.26.114 language version 0.18.102]

### Changed

- The maximum representable unsigned integer has been reduced from the maximum value
  that fits in the number of _bits_ in a field to the maximum value that fits in the
  number of _bytes_ in a field.  This change is necessary because values that do not
  fit in the number of bytes in a field do not have a valid representation in the
  ledger.  Given that the maximum field value at present is between 2^254 and 2^255,
  the number of whole bytes representable by a field is 31, and the maximum unsigned
  value is (2^8)^31-1 = 2^248-1.

  This is a breaking change because programs that used unsigned integers between
  2^248 (inclusive) and 2^254 (exclusive) will no longer compile.  Though while they
  would previously have compiled, they would not necessarily have worked properly.

## [Unreleased compiler version 0.26.113 language version 0.18.101]

### Fixed

- A bug in which some obviously unreachable statements were not being reported as such.
  This should be considered a breaking change since some programs that previously compiled
  will no longer compile due to this fix.

## [Unreleased compiler version 0.26.112 language version 0.18.101]

### Changed

- `Uint` range end points are now exclusive rather than inclusive to match the
  range syntax for `for` ranges.  That is, `Uint<0..n>` is now interpreted as the
  set of all unsigned integers in the range 0 through `n-1`, e.g., `Uint<0..3>`
  represents the set {0, 1, 2} rather than the set {0, 1, 2, 3}.

- The runtime version has been bumped to 0.10.2.

- when passed the `--update-Uint-ranges` flag, `fixup-compact` now adjusts the
  end point of each Uint whose size is given by a range with a constant end point
  and issues a warning for each Uint whose size is given by a range when the end
  point is a generic-variable reference.

## [Unreleased compiler version 0.26.111 language version 0.18.100]

### Fixed
- A bug in which Compact enums were generated as CJS enums instead of ESM enums. Previously, `index.js` might contain:

  ```javascript
  var Status;
  (function (Status) {
  Status[Status['Pending'] = 0] = 'Pending';
  // ...
  })(Status = exports.Status || (exports.Status = {}));
  ```

  for an enum `Status`. Now, `index.js` contains:

  ```javascript
  export var Status;
  (function (Status) {
    Status[Status['Pending'] = 0] = 'Pending';
    // ...
  })(Status || (Status = {}));
  ```

## [Unreleased compiler version 0.26.110 language version 0.18.100]

### Fixed
- An unreleased bug that was created during putting bounds on vectors/tuples/bytes

## [Unreleased compiler version 0.26.109 language version 0.18.100]

### Fixed

- A bug that could cause ledger operations or witness calls occurring
  in the test part of an `if` expresssion not to be reflected in the
  generated zkir circuit.

## [Unreleased compiler version 0.26.108 language version 0.18.100]

### Fixed

- A bug in unreleased code that caused an internal error message
  about an invalid source object.
- Internal language version is now properly bumped to 0.18.100.

## [Unreleased compiler version 0.26.107 language version 0.18.1]

### Fixed

- A bug that allowed const statements binding patterns or multiple variables
  to appear in a single-statement context, e.g., the consequent or alternative
  of an `if` statement.

## [Unreleased compiler version 0.26.106 language version 0.18.1]

### Added

- Selective module import and renaming, e.g.:
    `import { getMatch, putMatch as $putMatch } from Matching;`
      imports `getMatch` as `getMatch`, `putMatch` as `$putMatch`
    `import { getMatch, putMatch as originalPutMatch } from Matching prefix M$;`
      imports `getMatch` as `M$getMatch`, `putMatch` as `M$originalPutMatch`
  The original form of import is still supported:
    `import Matching;`
      imports everything from `Matching` under their unchanged export names
    `import Matching prefix M$;`
      imports everything from `Matching` with prefix M$

### Fixed

- A bug that sometimes caused impure circuits to be identified as pure
