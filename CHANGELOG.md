# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
