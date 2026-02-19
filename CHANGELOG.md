# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased toolchain 0.29.104, language 0.21.102, runtime 0.14.101]

### Added

- Schnorr signature verification over the JubJub embedded curve, via the new
  `JubjubSchnorrSignature` struct and `jubjubSchnorrVerify` circuit in the
  standard library.


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
