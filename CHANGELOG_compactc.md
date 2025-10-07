# `Compactc` Changelog

# Compiler Version `0.26.105`, language Version `0.18.0`
- Addresses 16090
  adds an upper bound for vector size, tuple size, and bytes length by the parameter
  `max-bytes/vector-size`. It also adds bounds for MerkleTree and HistroicMerkleTree
  where 2 <= depth <= 32

# Compiler Version `0.26.104`, language Version `0.18.0`
- Addresses Github issue 1406
  fixes a bug in which disclosures affecting flow of control are not always
  caught for the second occurrence of a call to a given circuit

# Compiler Version `0.26.103`, language Version `0.18.0`
- addresses PM 19145
    - The compiler now generates '.js', '.d.ts', and '.js.map' files instead of '.cjs', '.d.cts', and '.cjs.map' files.
    - Migrated to ES Modules (ESM): The runtime package is now a pure ES module
        - Added "type": "module" to package.json
        - All imports now require ES module syntax (import/export)
        - CommonJS (require/module.exports) is no longer supported
        - TypeScript configuration updated to use "module": "NodeNext" and "moduleResolution": "NodeNext"

# Compiler Version `0.26.102`, language Version `0.18.0`
- Addresses PM 19230
  - Circuit generation is more robust and sometimes produces smaller circuits.
- internal notes:
  - the conditional-execution flag (test) has been removed from Lcircuit assignment
    statements and replaced with flags in those RHS (Lcircuit) and Single or Multiple
    (Lflattened) forms whose execution should actually be conditional.
  - resolve-indices/simplify no longer records a zero value for undefined variables
    but rather uniformly counts on the undefined flag to be set where relevant.
  - resolve-indices/simplify now treats the boolean value of a variable used as
    a predicate in a conditional as true along the "then" branch and false along
    the "else" branch, enabling more simplification.
  - resolve-indices/simplify and optimize-circuit do a better job folding and
    eliminating common subexpressions
  - the select-form bool? flag was checked in only one place and was unnecessary
    there, so it has been removed
  - the code generated to compute the test for an assert form has been simplified

# Compiler version `0.26.101`, language version `0.18.0`
- Addresses PM 18137

  Updates `typescript-passes.ss` and `test.ss` to use Compact runtime version `0.10.0`. This means making use of the new
  functions and conventions Compact runtime version `0.10.0` introduced such as:
    * `checkRuntimeVersion`
    * `createCircuitContext`
    * various renamings

# Compiler version `0.26.100`, language version `0.18.0`
- A partial refactoring of the (experimental, and not yet announced publicly) ZKIR v3
  backend.

# Compiler version `0.26.0`, language version `0.18.0`
- bumps versions for release of Compiler 0.26.0

# Compiler version `0.25.119`, language version `0.17.103`
- Address PM-19426
  fixes a bug that was causing the compiler to produce an internal error rather
  than an informative error with source information for certain erroneous casts
  from tuples or vectors to tuples, vectors, and Bytes values

# Compiler version `0.25.118`, language version `0.17.103`
- Addresses PM-19297
  fixes the generated JS code for when an impure circuit calls a pure circuit inside
  a map or fold.  Previously, the generated code for the mapper was calling the pure
  circuit with context and partialProofData whereas the definition of the pure circuit
  didn't take context and partialProofData.

# Compiler version `0.25.117`, language version `0.17.103`
- Addresses PM-19385
  fixed a bug in the zkir code generated for certain byte-reference operations that
  could result in failed proofs
- internal notes:
  - the root cause was an index scaling error in optimize-circuit's handling
    of bytes-ref forms with constant Bytes objects
  - also fixed some suboptimal handling of bytes-slice by resolve-indices/simplify
    and assert by discard-useless-code

# Compiler version `0.25.116`, language version `0.17.103`
- Addresses PM-19287
  fixed an internal error (identifier not bound) reported either by
  check-types/Lflattened or by print-zkir and occuring as a result of
  optimize-circuits not recreating its tables for each circuit. also
  fixed a deficiency in check-types/Lflattened that sometimes let
  this kind of bug slip past.

# Compiler version `0.25.115`, language version `0.17.103`
- An internal change to duplicate the ZKIR v2 tests to run in ZKIR v3 mode.

# Compiler version `0.25.114`, language version `0.17.103`
- Add a feature flag for ZKIR v3

  This is an **experimental** feature flag which enables a separate circuit backend that generates a
  new version of ZKIR.  We will not yet announce this feature (it won't even work for some time).

# Compiler version `0.25.113`, language version `0.17.103`
- Fixes PM-19229 and PM-19160.

  The first of these is a bug in proofs for `HistoricMerkleTree.insertIndexDefault`.  This was
  another bug caused by incorrectly "escaping" (by introducing a `load_imm` instruction) an
  immediate in a ZKIR instruction.  The result is that an unrelated output index was used instead of
  a literal default value.

  The second is an unrelated bug in the proof for `MerkleTree.insertIndexDefault` caused by a
  missing instruction in the Impact VM code for the operation.

# Compiler version `0.25.112`, language version `0.17.103`
- addresses PM 17427: Adds support for new casts:

  | from type:                       | to type:                         | where:                                     |
  |----------------------------------|----------------------------------|--------------------------------------------|
  | Boolean                          | Boolean                          |                                            |
  | Uint                             | Bytes                            |                                            |
  | Bytes                            | Uint                             |                                            |
  | Enum                             | Uint                             |                                            |
  | Field                            | Enum                             |                                            |
  | Uint                             | Enum                             |                                            |
  | Bytes<m>                         | Vector<n, U>                     | m = n, U = Field or Uint<0..k>, k ≥ 255    |
  | Bytes<m>                         | [U1, ..., Un]                    | m = n, ∀i.U = Field or Uint<0..k>, k ≥ 255 |
  | Vector<m, T>                     | Vector<n, U>                     | m = n, T ⊆ U                               |
  | [T1, ..., Tm]                    | [U1, ..., Un]                    | m = n, ∀i.Ti ⊆ Ui                          |
  | Vector<m, T>                     | [U1, ..., Un]                    | m = n, ∀i.T ⊆ Ui                           |
  | [T1, ..., Tm]                    | Vector<j, U>                     | m = j, ∀i.Ti ⊆ U                           |
  | Opaque<x>                        | Opaque<y>                        | x = y                                      |
  | Struct R {X1: T1, ..., Xm: Tm }  | Struct R {Y1: U1, ..., Ym: Um }  | R = S, n = M, ∀i.Ti = Ui                   |
  | Enum D {X1, ..., Xm}             | Enum E {Y1, ..., Yn}             | m = n, ∀i.Xi = Yi                          |
  | Contract C {F1: T1, ..., Fm: Tm} | Contract D {G1: U1, ..., Gm: Um} | C = D, m ≤ n, ∀i.Ti = Ui, i ≤ m            |

  Notes:
   - Generally, if T ⊆ U, casts from T to U are perimitted.
   - Casts from Bytes<m> to Vector<n, U> or [U1, ..., Un] were previously supported, but only for U = Uint<0..255>.
   - For contracts, circuit declarations are sorted by name before applying the constraints.

- internal notes:
  - Renamed runtime's convert_bigint_to_Uint8Array and convert_Uint8Array_to_bigint
    to convertFieldToBytes and convertBytesToField, added a source string, and
    modified the error message to include the source information.  added a new
    routine convertBytesToUint to handle casts from Bytes to Uints.  The runtime
    version has been bumped to 0.9.0.
  - add-witnessses now uses merge-witnesses rather than append to avoid violating
    the assumption that witness lists are sorted and have no duplicates.

# Compiler version `0.25.111`, language version `0.17.102`
- addresses PM-14398 (remaining Bytes operations but not String operations):
  - syntax for Bytes construction: Bytes[a1, ..., an]
    where each ai is either an expression e or a spread ...e
  - indexing Bytes: bv[expr]: Uint<8>
  - slicing Bytes: slice<size>(expr, start)
  - iteration over Bytes in for loops, map, and fold with element types Uint<8>
    (map result is still always a vector)
- internal notes
  - portions of PM-14398 were already done:
    - hexadecimal, octal, and binary integer literals
    - casts between Bytes and Vectors
  - support for a String type and the other string-related portions of
    PM-14398 are left for the future

# Compiler version `0.25.110`, language version `0.17.101`
- addresses PM 19205
  fixes transientCommit and persistentCommit to be implicitly disclosing as documented,

# Compiler version `0.25.109`, language version `0.17.101`
- addresses PM 19124
  (N.B. this regards a bug in an as-yet unreleased portion of the compiler and should
  not appear in the release notes for 0.26.0.)
  fixes a bug: mishandling of tuples and vectors containing non-atomic elements could
  result in (at least) an internal assertion violation in the compiler.

# Compiler version `0.25.108`, language version `0.17.101`
- addresses PM 19121
  (N.B. this regards a bug in an as-yet unreleased portion of the compiler and should
  not appear in the release notes for 0.26.0.)
  fixes a bug: casting a constant of type Bytes<0>, e.g., default<Bytes<0>>, to
  a Field was causing an internal compiler error; this now compiles and properly
  produces a Field with value 0.

# Compiler version `0.25.107`, language version `0.17.101`
- addresses PM 12891
  Modify the `stage-javascript` test runner to add a call to `checkProofData` to ensure that the transcripts
  and circuit input and outputs agree with the generated ZKIR.

  Reverses the order of `print-zkir` and `print-typescript` so that ZKIR is generated first.

  Reverses the order of `print-zkir` and `print-typescript` tests so that ZKIR tests are executed first.

# Compiler version `0.25.106`, language version `0.17.101`
- addresses PM 19055
  Fixes a zkir indexing bug for nested ledger ADTs that manifested as an incorrect ZKIR
  input index.

  Paths in ledger ADT operations contained a mix of ZKIR instruction output indexes and
  elements of the form `(ref . triv)` where `triv` was an (untranslated!) Lflattened triv (a
  nat or a variable name).  They were converted to a list of ZKIR instruction indexes, nat
  literals, and variable names.  The variable names were later translated by looking them up
  in the variable table, but the nat literals were not emitted as `load_imm` instructions
  (this is the bug).

  Because we can't tell the difference at that point between an ZKIR instruction index and
  an untranslated nat literal, we translate all the trivs and they now have the form
  `(ref . index)` where `index` is a ZKIR instruction's output.

# Compiler version `0.25.105`, language version `0.17.101`
- addresses PM 19017
  fixes the zkir code generated by the compiler for Bytes to Vector and Vector to Bytes conversions

# Compiler version `0.25.104`, language version `0.17.101`
- addresses PM 16625
  Ledger ADT operations that require a coin commitment now fail with a more informative error
  message that also includes the Compact source location of the offending operation.

# Compiler version `0.25.103`, language version `0.17.101`
- addresses PM 13684
  (fix to unreleased code)
  fixed an issue with the typechecking for tuple/vector spreads

# Compiler version `0.25.102`, language version `0.17.101`
- addresses remainder of PM 13684
  added support for tuple and vector spreads: previously, the subforms S of a tuple
  constructor `[S, ..., S]` were all expressions; now each subform S can be
  either an expression e or the spread prefix `...` followed by an expression e,
  e.g., `[e1, ...e2, e3]`.  The constructed tuple is formed from the unprefixed
  elements and the contents of the prefixed elements.  For example, if the value
  of e1 is 1, the value of e2 is the tuple `[3, 5, 7]`, and the value of e3 is 9,
  the constructed tuple is `[1, 3, 5, 7, 9]`.

  The length of a tuple subform S is
    - 1 if S is a plain (non-spread) expression e
    - k if S is a spread of expression e and the type of e is a vector type `Vector<k, T>`
    - k if S is a spread of expression e and the type of e is a tuple type `[T1, ..., Tk]`
  and the length N of the tuple or vector constructed from the tuple form `[S, ..., S]` is
  the sum of the lengths of S, ..., S.

  The type(s) of a tuple subform S is
    - T if S is a plain (non-spread) expression e and the type of e is T
    - T if S is a spread of expression e and the type of e is a vector type `Vector<k, T>`
    - T1, ..., Tk if S is a spread of expression e and the type of e is a tuple type `[T1, ..., Tk]`
  and the type of the tuple expression `[S, ..., S]` depends as follows on whether any of 
  S, ..., S are spreads of vector-typed expressions:
    - if not, the type of `[S, ..., S]` is the tuple type `[T1, ..., TN`], where
      T1, ..., TN is the concatenation of the type(s) of S, ..., S.
    - if so, the types of S, ..., S must be related by subtyping, and the type of
      `[S, ..., S]` is the vector type `Vector<N, T>`, where N is the length of the
      constructed vector as described above and T is the least upper bound of the
      types of S, ..., S.

  Examples:
    - if e1 has type `Uint<8>`, e2 has type `[Uint<16>, Boolean, Field]`, and e3
      has type `Uint<32>`, the length of `[e1, ...e2, e3]` is 5 and its type is
      `[Uint<8>, Uint<16>, Boolean, Field, Uint<32>]`.  It's okay that the types
      are unrelated (Boolean is unrelated to the others), because none of the tuple
      subforms are spreads of vector-typed expressions
    - if e1 has type `Uint<8>`, e2 has type `Vector<3, Uint<16>>`, and e3 has
      type `Uint<32>`, the length of `[e1, ..., e2, e3]` is 5 its type is
      `Vector<5, Uint<32>>`.
    - if e1 has type `Uint<8>`, e2 has type `Vector<1000, Uint<16>>`, and e3 has
      type `Boolean`, `[e1, ...e2, e3]` is undefined, a static type error, because
      a spread of the vector-typed expression e2 is present and the types of the
      tuple subforms have unrelated types.  (Again, Boolean is unrelated to the
      others.)  For spreads of small vectors, a tuple type could be used and would
      be practical, but for consistency with spreasd of large vectors, the compiler
      uniformly requires that the types all be related when spreads of vector-typed
      expressions are present.

# Compiler version `0.25.101`, language version `0.17.100`
- removes the pass `eliminate-redundant-upcasts`, the essential purpose of which
  was to push `upcast` forms into tuple forms to avoid rewriting the tuple to
  change the representations of its elements.  Since `upcast` forms don't currently
  require a change in representation, this pass was contributing unnecessarily
  to the complexity of the compiler.

# Compiler version `0.25.100`, language version `0.17.100`
- addresses PM 17201, and part of PM 13684, and part of PM 18328
  - adds vector slicing (but not vector spreads)
  - allows generic sizes (but not types) to appear in expression contexts
  - allows non-constant tuple/vector index expression that eventually fold to constants
- addresses a small part of PM 14398
  - adds binary, octal, and hexadecimal integer literals
- internal notes
  - non-constant vector-ref and vector-slice index expressions are resolved by
    a new pass, resolve-indices/simplify that runs after loop unrolling and
    circuit inlining.  it performs copy propagation and constant folding which, when
    combined with the loop unrolling and inlining already performed, effectively
    allows indexes to be as close to arbitrary expressions as reasonably possible,
    given the requirement that they must reduce to constants at compile time.
  - type inference for non-constant vector-ref and vector-slice expressions in
    infer-types is intentionally weak.  infer-types requires only that they be
    unsigned integers of any size and leaves the task of doing the actual bounds
    check to resolve-indices/simplify.
  - upcast forms are dropped just after inlining. they weren't being used, and maintaining
    them through the simplifications done by resolve-indices/simplify would be complicated.
  - flushed print-Lflattened.  we never use it for anything, and updating it eats
    up time.  it will probably be less work to update it in one shot if we ever need
    to revive it.
  - removed progress messages from test.ss.  this was useful back when print-typescript
    ran each test in an individual node session, but it serves no purpose and just gets
    in the way now.
  - extended the third-party define-datatype feature with support for common fields,
    which we use for CTVs in the new pass resolve-indices/simplify

# Compiler version `0.25.0`, language version `0.17.0`
- Bump versions for release of compactc 0.25

# Compiler version `0.24.110`, language version `0.16.106`
- Address Pm-17347
  - the compiler no longer exits with an internal error when handed a source file containing
    Unicode numeric characters other than 0-9.

# Compiler version `0.24.109`, language version `0.16.106`
- Addresses PM-18013 (most of these are internal changes, user-facing changes are marked as such):
  - Pulls out changes in cc-ts/js-backend+rt that do not rely on composable contract changes to minimize the difference
    of the long running CC branch and main. These changes are solely in the compiler and not the runtime. Any changes 
    that requires updating the runtime and possibly MN.JS are not included in this.
  - In contract-info.json we store some additional fields that are needed for the generation of `index.cjs` and `d.cts` 
    files (*this is user-facing change but we don't explain the contract-info.json much so there's no need to expand 
    on this*):
    - contracts: is the contract types that the contract of this contract-info.json declares.
    - witnesses: is the *used* witnesses that the contract of this contract-info.json declares.
    - The order of these fields in the contract-info.json file is: circuits, witnesses, and contracts. Some tests rely
      on this ordering.
  - The `contract-info.json` file is no longer read in `infer-types`, instead it is read once in `generate-contract-ht` 
    pass and is stored in `contract-ht`. The later passes use the `contrac-ht` hashtable to access information they 
    need from `contract-info.json`
  - The witnesses stored in a contract's contract-info.json and in its callee contract-info.json files will be used in 
    `d.cts` file for the composable conract feature.
  - `source-file-name` is also added and it is used to get the name of a contract from the source file without its 
    extension if one exists for the `print-typescript` pass. This will also be used in `print-typescript` pass for the
    composable contract feature.
  - `replace-value-in-json` is documented in `json.ss` and it is used solely for testing the `contract-info.json`. Instances 
    of using it can be found in `test.ss`.
  - Two changes were carried out in IRs starting from `Ltypes`. Both of them were required for the `print-typescript` pass:
    - `contract-name*` has been added to `Program`.
    - `contract-call` now contains the expression of the public ledger that represents the contract being called.
      - For example, the expression `auth_cell.get()` written in Compact will look like the following in the `Ltypes` IR:
      `(contract-call get
         ((public-ledger %auth_cell.1 (0) read)
          (tcontract AuthCell
            (get #f () (tstruct StructExample (value (tfield))))
            (set #f ((tstruct StructExample (value (tfield))))
              (ttuple)))))`
      In this example, `(public-ledger %auth_cell.1 (0) read)` is the added expression to `contract-call`.
  - `null` is changed to `default` in error messages when `default` of a type isn't defined.
  - Changes to the `print-typescript` pass *these are user-facing changes but they do not break any code 
    that relies on the generated JS code*:
    - `#` has been dropped from helpers and private circuit definitions. This was needed for the next change.
    - The definition of pure circuits is now defined in `pureCircuits` constant in JavaScript.
    - The additional `context` and `partialProofData` have been dropped from pure circuits and helpers. Still
      one can access pure circuits through `circuits` object but they have to pass a `context` and `partialProofData`.
    - All `if` statements in generated JavaScript code use curly braces for their branches. 

# Compiler version `0.24.108`, language version `0.16.106`
- compactc now prints its own message saying that zkir failed in case the
  zkir process dies without printing anything to stderr, such as when it is killed
  for lack of memory.  the compactc exit code in cases where zkir fails is also
  now the same as for any other compilation error, i.e., 255 / -1.
- internal notes: these notes relate to unreleased functionality, so should
  not be included in the release notes.  though the change to typing rules
  for vector to Bytes casts should be reflected in the language reference.
  - the type inferencer required the type of a Vector to Bytes cast to be
    a Vector rather, i.e., did not support equivalent tuples
  - the witness-protection program did not produce the right abstract values
    for vector->bytes and bytes->vector
  - the zkir code generator was producing incorrect code for vector->bytes and
    bytes->vector (too many ctr increments)
  - loosened the typing rules for vector->bytes conversions to allow the input
    vector or tuple element types Uint<k> to allow k <= 8 rather than requiring
    k = 8.
  - fixed some endianness issues in the flatten-datatype and optimize-circuit
    implementations of vector->bytes and bytes->vector

# Compiler version `0.24.107`, language version `0.16.106`
- addresses PM 17200
    - Introduces two new kernel functions `blockTimeGreaterThan` and `blockTimeLessThan`.
    - Introduces four new standard library functions, `blockTimeGt`, `blockTimeGte`, `blockTimeLt`, and `blockTimeLte`.
    - Introduces a unit test in `test-center/ts/block-time.ts` for the new block time functions.

# Compiler version `0.24.106`, language version `0.16.105`
- Reverses changes for PM 14077
    - Removes four kernel operations, `mintUnshielded`, `claimUnshieldedCoinSpend`, `incUnshieldedOutputs`, and
      `incUnshieldedInputs`.
    - Removes eight standard library functions, `mintUnshieldedToken`, `sendUnshielded`, `receiveUnshielded`,
      `unshieldedBalance`, `unshieldedBalanceLt`, `unshieldedBalanceGte`, `unshieldedBalanceGt`, `unshieldedBalanceLte`.
    - Reverts names change like `QualifiedCoinInfo` and `CoinInfo` to be `QualifiedShieldedCoinInfo` and `ShieldedCoinInfo` to
      match the names in the old on-chain runtime.
    - Reverts renaming of standard library functions to distinguish between shielded and unshielded token utilities.
    - Reverts `@midnight-ntwrk/compact-runtime` to use `@midnight-ntwrk/onchain-runtime` version `^0.3.0`.

# Compiler version `0.24.105`, language version `0.16.104`
- addresses PM 15976
  The Compact compiler now accepts multi-variable const statements. Similar to TypeScript
  it rejects a multi-variable const statement that references an identifier before it is
  assigned. It also rejects a multi-variable const statement that has more than one binding for
  the same identifier. Similar to TypeScript it rejects trailing commas in a multi-variable
  const statement.

# Compiler version `0.24.104`, language version `0.16.103`
- addresses PM 14770
  The Compactc shell script runner can now accept input Compact files with spaces in their
  names

# Compiler version `0.24.103`, language version `0.16.103`
- addresses part of pm-15536
  The Compact compiler now supports casts from `Bytes<k>` to `Vector<k, Uint<8>>` and back.

# Compiler version `0.24.102`, language version `0.16.102`
- addresses PM 14079
  - Renames `burnAddressShielded` in the standard library to `shieldedBurnAddress`.
  - Updates standard library documentation to reflect name changes introduced in PM 14077.
  - Capitalized some generic parameters in the standard library.

# Compiler version `0.24.101`, language version `0.16.101`
- addresses PM 14077
  - Introduces four new kernel operations, `mintUnshielded`, `claimUnshieldedCoinSpend`, `incUnshieldedOutputs`, and
    `incUnshieldedInputs`.
  - Introduces eight new standard library functions, `mintUnshieldedToken`, `sendUnshielded`, `receiveUnshielded`,
    `unshieldedBalance`, `unshieldedBalanceLt`, `unshieldedBalanceGte`, `unshieldedBalanceGt`, `unshieldedBalanceLte`.
  - Changes names like `QualifiedCoinInfo` and `CoinInfo` to be `QualifiedShieldedCoinInfo` and `ShieldedCoinInfo` to
    match the names in the new on-chain runtime.
  - Renames standard library functions to distinguish between shielded and unshielded token utilities.
  - Updates `@midnight-ntwrk/compact-runtime` to use the draft on-chain runtime API. Exports new functions and data types.
  - Changes `analysis-passes.ss` and `typescript-passes.ss` to use the same type hashing logic for vectors of length `k`
    and tuples of length `k` of all the same element type, up to a hard-coded maximum length `k`.

# Compiler version `0.24.0`, language version `0.16.0`
- bumps compiler and language version after the release of compactc 0.24.0

# Compiler version `0.23.118`, language version `0.15.110`
- internal notes:
  - contains the Intel Mac binary release
  - disables the formatter and fixup tools tests in the release CI
  
# Compiler version `0.23.117`, language version `0.15.110`
- addresses PM 16999
  the compiler now prints an error when the names of two exported impure
  circuits are the same modulo case to avoid filename clashes on case-insensitive
  filesystems.

# Compiler version `0.23.116`, language version `0.15.110`
- addresses PM 15527
  - Assert statements, which took the form `assert expr message`, have been removed from
    Compact, and assert expressions, which take the form `assert(expr, message)` have been
    added in their place.  In addition to the change in syntax, this allows asserts to be
    used in more contexts.  For example, what was written:
      `(() => { assert(x != 0, 'oops'); })()`
    can now be written more simply as:
      `(() => assert(x != 0, 'oops'))()`.
    Similarly, it is now possible to include asserts in expression sequences, e.g.:
      return assert(x > y, "underflow"), x - y;
- The grammar in doc/Compact.html has been restructured slightly to improve
  readability: a new expr9 group between expr8 and term contains the non-atomic
  items previously contained in term, like procedure call and structure allocation
  expressions, and term contains the atomic elements like identifier references.
  term now also contains the expressions formerly appearing in the lit group,
  which has been eliminated.

# Compiler version `0.23.115`, language version `0.15.108`
- addresses PM 16181 (second example)
  - The Compact compiler now produces a descriptive error message when the type of either
    operand of an equality operator (== or !=) is a public-ledger ADT rather than an
    ordinary Compact type.  Previously, this resulted in an internal error.

# Compiler version `0.23.114`, language version `0.15.108`
- addresses PM 16893
  - The compact compiler no longer experiences an internal error when a for over an empty
    range or tuple, a map over an empty tuple, or a fold over an empty tuple results in
    a type issue that it cannot resolve due to not knowing the (unspecified) types of the
    (nonexistent) tuple elements.  Where possible, it assumes the type, if known, would be
    appropriate, which does not cause any issues because the code in the body of the for
    and the function being called by the map or fold is never executed.
- addresses PM 14564
  - The compact compiler no longer generates any code for upcasts.  Previously it could
    produce code to recreate a vector or structure to handle upcasting of the atomic
    elements of such structures, but with Compact's current datatype
    representations, atomic elements do not require any conversions on upcast.
- internal notes
  - Rather than introduce specific forms of upcasts (unsigned->field, upcast-unsigned, and
    upcast-contract), the compiler retains the upcast form introduced by infer-types for as
    long as it is needed to allow typechecking of downstream intermediate languages.

# Compiler version `0.23.113`, language version `0.15.109`
- address PM 15798 and PM 16349
  - The Compact grammar for version expressions mistakenly allowed the ! (not) operator to be
    followed by a version term rather than a version atom, but actually not following it with a
    version atom caused an internal error.  This has been fixed.
- addresses PM 16064 and PM 16075
  - The compiler no longer produces syntactically invalid JavaScript code (an unparenthesized
    expression sequence between the ? and : of an expression conditional) for certain conditional
    expressions.
- addresses PM 16181
  - The Compact compiler now produces a descriptive error message when the type of any subexpression
    of a tuple-construction expression  [e1, ..., en] is a public-ledger ADT rather than an
    ordinary Compact type.  Previously, this resulted in an internal error.
- addresses PM 16183
  - The Compact compiler now reports unreachable statements in the constructor and anonymous
    circuits as well as in top-level circuit bodies.

# Compiler version `0.23.112`, language version `0.15.108`
- addresses PM 16853
  - fixed a bug in which optimize-circuit detected the downstream use of a variable whose
    assignment was supposed to be eliminated.
- internal notes
  - FWD is now responsible for discarding any assignment whose conditional (test)
    is or optimizes to 0.  When it does so, it also sets the var's entry in the
    var->triv table to 0, so there should be no downstream references.  For assert,
    the sense of the condition is effectively backward, so FWD discards asserts
    if the condition is or optimizes to 1.  This isn't quite sufficient, however:
    it might optimize to 0 due to a discarded assigment, which can happen only
    if the assert should also be discarded.  So when FWD discards an assignment,
    it also sets an undefined flag on the var, and when FWD processes an assert,
    it discards it not only if the condition is or optimizes to 1 but also if the
    test is a var that is marked undefined.  This somewhat twisted logic could
    be avoided if assert were replaced in Lcircuit and beyond by a conditional
    "fail", where failure occurs if the test value is 1 rather than 0.
  - BWD is now a bit less complicated due to the shifting of the responsibility
    for discarding statements from it to FWD.
  - also fixed a potential (as yet unreported) bug with the handling of nested
    Maps by optimize-circuits and check-types/Lflattened: the public-ledger
    path-elts were not being processed, which in the presence of certain
    optimization opportunities could result in unbound variables in the
    optimize-circuit output.  these were not being caught by check-types/Lflattened,
    which was also ignoring the path-elts.

# Compiler version `0.23.111`, language version `0.15.108`
- addresses PM 9232
  - The Compact compiler no longer converts exported ledger-field names to camel-case in the
    generated TypeScript output for the ledger object.  If a TypeScript program accesses ledger
    fields that are not already camel-cased in the Compact source code, either (a) the ledger
    field must be renamed in the Compact source code or (b) the TypeScript code must be adjusted
    to use the unconverted Compact name of the ledger field.

# Compiler version `0.23.110`, language version `0.15.107`
- addresses PM 16774
  - the ledger assignment, increment, and decrement forms are now expressions of type [] rather
    than statements.  This is a non-breaking change.  It simply allows these forms to be used in
    expression contexts in addition to statement contexts.
- adds a suggestion to try import CompactStandardLibrary upon failure to find include file
  std.compact.

# Compiler version `0.23.109`, language version `0.15.106`
- addresses PM 16723
  - modifies the witness protection to treat ledger reads and removals the same as ledger writes
    and updates since every ledger operation is reflected in the transcript
- modifies the witness-protection program to produces an error when the return value of a witness
  function might determine the point at which an external circuit returns, if this potential
  disclosure is not declared.
- modifies the error message produced in cases where witness values are exposed simply
  via the conditional execution of ledger operations and cross-contract calls to make
  the situation more clear

# Compiler version `0.23.108`, language version `0.15.105`
- addresses PM 16341
  - eliminates std.compact, which contained only the single line "import CompactStandardLibrary;"
  - programs requiring access to the standard library must now use "import CompactStandardLibrary;"
  - COMPACT_PATH is no longer set in compactc.bin

# Compiler version `0.23.107`, language version `0.15.104`
- addresses PM 13340
  - fixes fixup-compact support for --vscode
  - modifies format-compact and fixup-compact to produce better (non-internal)
    error messages for filesystem errors

# Compiler version `0.23.106`, language version `0.15.104`
- addresses PM 16624:
  - trailing commas are now properly permitted to appear at the end of argument
    lists for calls, ledger-operator calls, cross-contract calls, maps, and folds.

# Compiler version `0.23.105`, language version `0.15.103`
- addresses PM 16146:
  - A bug that caused an internal compiler error (assertion violation) has
    been fixed.  The bug occurred in some cases (a) when a conditional returned
    the value of a side-effecting ledger operator call along one branch and either
    `[]` or nothing along the other, or (b) when a conditional returned a value
    of a vector type along one branch and a value of an equivalent tuple type
    along the other.

# Compiler version `0.23.104`, language version `0.15.103`
- addresses PM 15538:
  - The names of standard-library circuits and ledger operators have been
    switched from snake_case to camelCase, e.g., hash_to_curve is now hashToCurve,
    and is_empty is now isEmpty. the names of standard-library struct fields
    have been left, for now, in snake_case because renaming them depends on a
    corresponding change to the onchain runtime.
- addresses PM 13340
  - The new program compiler/fixup-compact attempts to replace references to
    the old snake_case names with the new camelCase names.  It also replaces
    includes of std with imports of CompactStandardLibrary.
- The formatter now preserves single blank lines outside of block comments, while
  converting multiple consecutive blank lines into a single blank line.  (It already
  preserved all blank lines within block comments.)  The lexer no longer consumes the
  trailing newline when reading a line comment so if the following line is a blank
  line it is recognized as such.
- Error messages relating to invalid exports in an export form now point
  directly to the source location of the problematic identifier in the
  export set rather than to the start of the export form.
- internal notes
  - expand-modules-and-types and infer-types have been retooled to either record
    (when run from fixup-compact) or complain about (when run from compactc)
    standard library and ledger names that should be renamed and to proceed with
    compilation using with the updated names.  fixup-compact uses the recorded
    renamings (keyed by src objects) to rewrite the Lparser form of the program
    accordingly, which it then formats just as format-compact.ss would do.
  - fixup-compact was used to update the CI e2e and debugger tests.  it also needs
    to be tested in CI.
  - the test infrastructure now uniformly directs the generated typescript code
    to a "contract" subdirectory of javascript-code/testNNN and places all of the
    visited source code in a parallel "src" directory, and it sets the sourcemap
    root accordingly so that we should no longer get sourcemap file not found errors
    when run-javascript tests fail.  if we do, it indicates a bug either in the
    generation of the sourcemap file or in the test infrastructure.  Another benefit
    of this change is that, while debugging, we can see all of the source and
    object code together in one place and don't have to hunt for the source in
    test.ss snippets or source files elsewhere.

# Compiler version `0.23.103`, language version `0.15.102`
- addresses PM-15585: extend witness protection program
  - Extends the witness-protection program (WPP) to treat constructor and exported
    circuit arguments as witness data
  - Also extends WPP so that returns/writes/updates that are conditioned on witness values
    are now considered to disclose those witness values.
      if (disclose(vote.value)) {
        yes.increment(1);
      } else {
        no.increment(1);
      }
    the increments are considered to disclose the value of vote.
  - WPP no longer halts after finding the first undeclared potential disclosure but
    rather reports all that it can find.
  - WPP now also produces much more elaborate error messages identifying the
    nature of each potential undeclared disclosure and the path the witness value
    takes through the program
  - Undeclared disclosures that occur within standard library code are now
    reported at the site of entry into the standard library, but still with
    the full explanation of the nature of the exposure
- addresses PM-15406:
  - Some errors involving the ledger assignment syntactic sugar field = expr,
    field += expr, and field -= expr that were being reported as errors involving
    the write, increment, and decrement operators are now properly reported as
    errors involving the =, +=, or -= operators.
- addresses PM-16603:
  - save-contract-info now properly lists each circuit under its export name(s)
    instead of the original name, if different.  this is not a reportable bug
    fix because the info is used only for cross-contract calls, which are not
    yet fully supported.
- Each type error involving a mismatch between the declared and actual return
  type of a circuit are now reported at the point of a specific return statement 
  rather than generally for the circuit, which should help programmers pinpoint
  the source of the mismatch
- Path names in error messages produced by compactc are now abbreviated to just
  the final component of the pathname if the compiler has not (yet) seen two paths
  with the same final component.
- Error messages produced by compactc w/o the --vscode option are now
  line-wrapped to 100 columns
- internal notes
  - When a module is imported via a filesystem pathname, the name recorded in the
    environment within the (name . pathname) key is now a symbol representing the
    last component of the path rather than a string.  this is consistent with the
    key used when a module imported by name is found within the filesystem and so
    can eliminate redundant loads of the same module.
  - The relational and equality operators !=, <=, >, and >= are now preserved until
    Lposttypescript to allow for the production of better error messages and
    JavaScript code that more closely matches the input Compact program.
  - The pass infrastructure, compiler driver, and test infrastructure all cooperate
    to make sure that errors recorded by the witness protection program are
    reported. this treatment can be extended easily to some other error reporting
    and with more difficultly, universally with all recoverable compiler errors.
    the term "leak" in the code now specifically refers only to detected leaks,
    and the term "witness" refers generally to witness return values, constructor
    arguments, and exported circuit arguments.
  - When converting from the accessor form to the path-element form of ledger
    operator calls, we were dropping the source objects for the accessors,
    which represent the original nested operator calls.  we now retain all but
    the last accessor's source objects in the corresponding path elements and
    the last accessor's source object directly in the public-ledger form as
    src^. the last accessor's source is used by track-witness-data to properly
    identify the source location for undeclared disclosure via ledger write/udpate
    operations. the information is also now available for print-typescript to
    include source locations when exceptions occur during ledger operations.
  - For each witness value that enters a contract (via a witness function, a constructor
    argument, or a circuit argument), the WPP now tracks certain points along the
    path between the entry point and every place the witness value reaches along the
    flow of control. These points include calls passing the witness value
    in an argument, const bindings whose RHS is computed based on the witness value,
    conditionals (if/and/or expression), and comparisons (<, ==, etc.).  It's easy
    to add more if we want.
  - When a witness value is disclosed without a disclose declaration, the error message
    reports the nature of the disclosure and the points along each path from the witness
    value's entry point to the disclosure point to help the programmer understand
    and isolate the cause of the disclosure as well as identify likely points
    where disclose wrappers should be added.
  - So that we don't report bindings of introduced temporaries as if they are
    source-code const bindings, identifier (id) records now contain a "temp" flag
    that is true for introduced identifiers and false for source identifiers.
    To help ensure proper marking of introduced identifiers, make-id has been
    replaced by make-source-id and make-temp-id.  To reduce the number of fields
    in an id record, despite the addition of a temp? field, I combined the four
    boolean fields exported?, sealed?, pure?, and temp? into a single flag field.
    This change is transparent outside the code that defines the id record.
  - Adapted the unit tests to the structure of midnightntwrk-contracts and updated
    flake.nix to pull from that repo rather than the depreciated
    midnight-ntwrk-contracts repo.  currently instead of pulling from
    compactc-main, flake.nix pulls from the pm-15585-extend-WPP of the repo,
    which has been updated to account for the changes in WPP.
  - getting the correct src^ for the Lwithpaths public-ledger form for the
    =, +=, and -= operators required changing src in (= src expr1 expr2),
    (+= src expr1 expr2), and (-= src expr1 expr2) to be the location of the
    operator rather than the location of the entire expression, ala src in
    elt-ref and elt-call. this led to a rather awkward source location being
    shown for these statements by report-unreachable.  the simple solution was
    to make these statements expressions, though for now only in the output of
    the parser.  they are still statements in the Compact source language.
    For consistency, removed the dot-src from Lparser elt-ref and elt-call, since
    it can be gotten from the dot token.

# Compiler version `0.23.102`, language version `0.15.101`
- address PM-16611
  - The on-chain runtime always requires that the amount of a token that is minted is <= the maximum value for a 64-bit
    integer. But, the "mint" function accepted a "Uint<128>" instead of a "Uint<64>". The "mint" function now accepts a
    "Uint<64>" for the mint value so compilation prevents users from attempting to mint too many tokens.
  - Also had to change the "mint" function in "midnight-ledger.ss" to use "Uint64" instead of "Uint128".

# Compiler version `0.23.101`, language version `0.15.0`
- address PM-16336
  - Changed the "second binding found" error message produced during binding
    analysis to include the source location of the other binding found.
  - define-adt now uses the standard-library sfd for the source object attached to
    ledger definitions and types so that ledger features are properly identified
    as originating in the standard library.
  - Source locations in the standard library are now rendered simply as
    "<standard library>" to avoid giving both a useless pathname and useless
    file position informations to most consumers of the compiler.
- internal notes:
  - Standard-library circuits can now be recognized post expand-modules-and-types
    by applying the utils.ss predicate stdlib-src? to the id-src of the function name.
  - source-errorf now defers to format-source-object to print the source location,
    so we have a common path for formatting source locations
  - providing the source location of the other binding found required a change
    in the expand-modules-and-types environment, which instead of mapping
    sym -> Info now maps sym -> (src, Info).

# Compiler version `0.23.0`, language version `0.15.0`
- bumps compiler and language version after the internal release of compactc 0.23.0

# Compiler version `0.22.108`, language version `0.14.101`
- addresses PM-16447, PM-16040
  - adds a check to Lparser->Lsrc to complain when Tsize is bigger than max-field
- reproduces PM-15826, PM-16059 which resulted in them having been fixed from when 
  they were reported
  
# Compiler version `0.22.107`, language version `0.14.101`
- address PM-16582
  - drops files that already exist in the output directory
  - adds the example programs used to report this ticket in `exmaples/bug` for
    regression testing
- fixes the dev shell for `.#compiler`

# Compiler version `0.22.106`, language version `0.14.101`
- address MFG-413
  - fixed internal error in optimize circuits that could happen when a common
    subexpression occurs in both unreachable and reachable parts of a program

# Compiler version `0.22.105`, language version `0.14.101`
- more work on PM-13344
  - tweaked print-Q to print Qstrings that follow multiline Qstrings, saving the
    forced newline for after the entire sequence.  for well-formed programs, this
    should include only punctuation like semicolons, commas, and close parens and
    cause those elements to appear at the end of the multiline string rather than on
    a separate line.
- updated flake.nix packages.compactc to build format-compact as well as compactc.

# Compiler version `0.22.104`, language version `0.14.101`
- address PM-16148
  - / is now recognized as a binop token, which causes the parser to produce a
    better error message that should better hint at the absense of a division
    operator.  (rather than seeing a report that the character eof following
    / is unexpected, the programmer will see that the parser was looking for,
    among other things, '+', '-', or '*', and should be able to conclude from
    this that "/" is not supported.  We can make a better fix later if we
    decide not to actually support division.

# Compiler version `0.22.103`, language version `0.14.101`
- address PM-13344
  - Added a compact formatter.  This is available as a pass in the compiler for
    testing and also as a stand-alone program format-compact.ss.
- address PM-15104
  - The parser now uniformally allows trailing commas and trailing semicolons
    on all comma-separated and semicolon-separated lists, except for
    expression-sequences, where a trailing comma could lead to confusion.
    A trailing comma or semicolon is permitted only if the list of items to
    separate is nonempty; that is a "trailing" separator is not permitted to
    appear by itself.
- fixed a minor unreported lexer bug
  The character string x.y.z.w where x, y, z, and w are strings of digits was being
  interpreted as the version string x.y.w.  This now results in a parser error.
- Extended the parser to allow commas instead of semicolons between
  external-contract-circuit declarations and not to require a semicolon (or comma)
  to follow the last declaration.
- internal notes
  In broad strokes, implementing the formatter required:
  * modifying the lexer to include comment and whitespace tokens in the token
    stream it produces
  * adding a new intermediate language, Lparser, with additional information
    required for the formatter
  * retargeting the parser to generate Lparser records and provide the additional
    information required for the formatter
  * extending ez-grammar.ss to support features required so that the parser
    can produce the additional information required by the formatter
  * implementing the formatter itself
  * adding a new pass, lparser-to-lsrc that converts programs in the Lparser
    language into programs in the Lsrc language

  The additional information required by the formatter is:
  (a) the source location and original text of every token in the input stream,
      whether that be something like an identifier or natural number that is
      represented in Lsrc by a symbol or integer with no associated source
      information or something that was not represented at all in Lsrc, like
      parentheses, commas, or colons.
  (b) differentiated original syntax for any Lsrc records that can have more
      than one input representation, such as the pattern struct-element (x x),
      which can be represented as just x or as x : x in the program text.

  (a) is needed to associate comments with the forms and tokens they belong with,
  and (b) is needed to faithfully render the output using the original syntax.
  (We could skate by without (b) and possibly some of (a), but a guiding principle
  of this work is that implementation restrictions should not dictate policy.
  So the implementation should be capable of producing a faithful rerendering of
  the input program, with all comments in their right places, even if by policy we
  decide that some things should be rendered in a canonical syntax and some comments
  should be rejected for being placed in inappropriate spots.)

  Lparser is thus more elaborate than Lsrc, having both more productions and
  with nearly every production having more elements.  For example, there are two
  productions for return, one with an expression and one without, and in both
  cases the "return" keyword and ending semicolon are explicitly represented in
  the production.  At the same time, Lparser's terminals no longer have a mix of
  representations but are instead all tokens of one type or another.

  Tokens themselves have changed a bit.  Previously, a token contained an "extended"
  bfp and an efp in addition to a type and value; token's now contain a source object
  (src) in place of the bfp and efp and a new field, string, containing the exact
  text of the token in the input file.

  The interface between the parser and the rest of the compiler hasn't changed;
  the parser pass still accepts a filename and produces an Lsrc language, but it
  does so by first producing an Lparser record and converting that into an Lsrc
  record by way of the new lparser-to-lsrc pass.

  On the other hand, the formatter uses a different parser entry point that obtains
  two things: an Lparser record for the input program and token stream containing
  all of the tokens in the input program, including the new comment and whitespace
  tokens.

  The (indirect) interface between the lexer and ez-grammar has changed in that
  tokens in the token-stream now contain source objects rather than beginning and
  ending file positions, so that ez-grammar doesn't have to mess with the "extended"
  beginning file positions previously appearing in tokens.

  For the most part, despite producing radically different output, the parser
  actually has the same set of productions and renders the same in HTML.  Some
  exceptions:
    - the parser now uniformally allows trailing commas and trailing semicolons
      on all comma-separated and semicolon-separated lists, except for
      expression-sequences
    - a new note has been added to the top of the generated HTML file regarding
      these trailing commas and semicolons.
    - some of the grammar definitions have been reordered for clarity
    - a few grammar symbols have been renamed for clarity
    - some optional features, like the optional export prefix, are handled directly
      using the "OPT" syntax rather than via separate nonterminals with epsilon
      productions

# Compiler version `0.22.102`, language version `0.14.100`
- address PM-15733, PM-16129
  - field arithmetic underflow (to negative) and overflow (to greater than FIELD_MAX)
    now properly wraps

# Compiler version `0.22.101`, language version `0.14.100`
- address PM-15889
  - Use of a ledger ADT type in an invalid context now results in an proper error
    message rather than an internal error

# Compiler version `0.22.100`, language version `0.14.100`
- bumps compiler and language version after the internal release of compactc 0.22.0

# Compiler version `0.21.106`, language version `0.14.100`
- address PM-15405
  - Fixed an internal error in unget-char that occurred rarely while
    reading certain range syntaxes near file-buffer boundaries

# Compiler version `0.21.105`, language version `0.14.100`
- address PM-15412
  - fix a ZKIR generation issue with allocating indexes for circuit arguments when
    their type constraints had the side effect of also allocating indexes.
  - This was reported via Discord.  They have an (awkward) workaround in place.

# Compiler version `0.21.104`, language version `0.14.100`
- address PM-15053
  - Fixed the internal error in infer-types: no matching clause for input ...
-internal notes
  - infer-types wasn't checking the output of the Type processor in various places
    when it was expecting an ordinary Compact type.  It now does so and prints a
    useful error message when it receives an ADT type instead.

# Compiler version `0.21.103`, language version `0.14.100`
- address PM-14807
  - the compiler no longer reports an internal error when the `MerkleTree` operator
    `insert_index_default` is used.
- internal notes
  - made compiler/go more resistant to vagaries of the host O/S by replacing
    /bin/sh with /usr/bin/env bash on the #! line
  - modified it enable printing of extended identifiers in Scheme, which helps
    when looking at certain test output and traces.
- added a couple of tests that are independent of the bug fix

# Compiler version `0.21.102`, language version `0.14.100`
- address PM-14841
  - Fixed the internal error "failed assertion (Ltypescript-Type? type)" that occurred
    when using the `insert_default` operator on a Map whose value type is a ledger ADT
    rather than a regular Compact type.
- internal notes
  - Taught VMnull how to handle ADT types
  - Added a new VMop, VMstate-value-ADT that adds a Cell wrapper if the
    type of it's argument is a regular Compact type and not if the type of its
    argument is an ADT type.
  - Removed the check for ADT types from VMstate-value-cell.
  - Replaced uses of VMstate-value-cell with VMstate-value-ADT in the Map operators
    where they were allocating a Map value.

# Compiler version `0.21.101`, language version `0.14.100`
- moves onchain-runtime out of compactc

# Compiler version `0.21.100`, language version `0.14.100`
- bumps compiler and language version after the internal release of compactc 0.21.0
- adds the counter and welcome dapps to unit tests

# Compiler version `0.20.6`, language version `0.13.4`
- address PM-8462
  - The Compact compiler now produces more feedback when a parse error occurs, namely
    the set of things the compiler expected to find but didn't at the point where the
    parse failed.
- cleaner, more accurate doc/Compact.html
  - doc/Compact.html was inaccurate in its treatment of some binary-operator clauses,
    incorrectly implying, for example, that "+" could not have an unparenthesized
    multiplication expression as its right-hand operand.  It was also inconsistent in
    its treatment of binary operators versus other forms, and grammar also exposed the
    result of manual left-recursion elimination in a couple of other places (resulting
    in the "tail" clauses).  these issues have all been resolved, and the grammar is
    now correct, clearer, and more consistent.
- internal notes
  - the parser created by an ez-grammar define-grammar form now records failed attempts
    at handling the last token in the token stream and reports this information back to
    the caller, allowing the caller to produce more informative error messages.  to
    support this, ez-grammar also now provides a new "sat/what" variant of "sat" to
    allow programmers to provide human-readable information about what the "sat" form
    is looking for
  - ez-grammar now performs (direct) left-recursion elimination, allowing more natural
    source grammars.  left-recursion elimination provides most of the benefits of
    ez-grammar BINOP productions without requiring the use of a different production
    syntax.  ez-grammar also produces cleaner and clearer html renderings of grammars
    that are written without BINOP or manual left-recursion elimination.
    Furthermore, the latest iteration of BINOP support actually produced incorrect
    HTML output for some BINOP productions, resulting in the problem noted for
    doc/Compact.html above.  So the BINOP support has been dropped.
  - the order of parser.ss define-grammar clauses has also been changed in an attempt
    to effect a more logical ordering in doc/Compact.html.
  - previously, parser.ss leveraged the manual left-recursion elimination in one of the
    clauses to obtain the source position of the "." in element references and calls
    and attached this source position to the resulting elt-ref and elt-call expressions
    in lieu of the starting position of the "." LHS.  With automatic left-recursion
    elimination, this was no longer possible, so ez-grammar now supports a new (SRC k)
    form that is like the constant k but instead causes the the source position of the
    matched constant to the consumer (rather than nothing, as for plain constants).
    this allows the parser to use (SRC ".") to obtain the source position of the dot.
  - a long comment has been added to the front of the the left-factor definition
    in ez-grammar.ss explaining that and why left factoring can change the order of
    the sets of possible parses produced when a grammar is ambiguous, and a cross
    reference has been added to parser.ss to indicate the reason why the "if" clauses
    appear in the order that they do.
  - constant->parser is now a meta definition called at compile time, allowing it to
    format the "what" argument to "sat/what" at compile time rather than at run time.
  - a Compact program is now explicitly terminated by an eof token.  this simplified
    the handling of unexpected end-of-file errors and the recording of last-token
    errors generally.  if we don't like it appearing in the grammar, we can arrange
    to make it implicit.
  - print-typescript's precedence table now puts < higher than ==.  this can result
    in fewer unnecessary parentheses in the generated JavaScript output.

# Compiler version `0.20.5`, language version `0.13.4`
- address PM-13375, PM-14599
  - The Compact language now provides a TypeScript-compatible tuple type 
    and TypeScript-compatible destructuring for (possibly nested) tuples, vectors,
    and structs.  The Void return type has been removed.  Instead, functions
    (witnesses and circuits) that return no useful value should now have return type
    [], signifying the empty tuple.  The spread syntax allowed in TypeScript
    destructuring patterns are not presently supported.
- internal notes
  - There is no longer a difference in the set of types allowed for arguments and
    the set allowed for return types.  Previously, Void could be used only as
    a return type; its replacement [] can be used as either.
  - The type checkers now handle let* in CareNot as well as in Care so that the body
    is properly processed as effect only (in CareNot).
  - The translation of for into fold now uses (ttuple) rather than (tboolean) as the first
    argument and return types and [] rather than false as the first argument value so
    that its return value is properly [].
  - print-typescript now generates descriptor.fromValue() calls only for class "read" ADT
    operations; they are not needed, added to the code size, and caused TypeScript to
    report a type error with the new Void descriptor.
  - print-typescript's local variable name generation no longer uses the name as is when
    possible but always adds a `_0`, `_1`, etc., suffix.  This results in uglier generated
    code but avoids problems with names that aren't reserved in Compact but are in
    TypeScript and/or JavaScript, like void.  An alternative would be to special-case
    names that are reserved in TypeScript and/or JavaScript, but a definitive list of
    such names doesn't seem to exist.
  - The parser now handles the reservation of the name "this" in a more transparent
    fashion and in a way that supports the easy addition of words reserved for future
    use.

# Compiler version `0.20.4`, language version `0.13.3`
- Fixes a bug in compiler version 0.20.3 tracking of witness data.

# Compiler version `0.20.3`, language version `0.13.3`
- address PM-13382
  - The compiler now complains if the return value of a witness is disclosed outside
    of the contract, i.e., finds its way to a ledger write/update, the return value
    of an exported circuit, or the argument of a cross-contract call.  To eliminate
    the complaint, when appropriate, the programmer can acknowledge the disclosure
    with the new `disclose(expr)` wrapper somewhere along the path from the witness
    call to the point of disclosure.
- other changes
  - The error message produced when the right-hand side of a ledger write, increment,
    or decrement expressed using the =, +=, or -= syntactic sugar now properly
    reports the error in terms of the syntactic sugar rather than the expansion.
- internal notes
  - The analysis to detect whether witness return values are disclosed is structured
    as a polyvariant abstract interpreter, where the abstract values are structs
    whose fields are abstract values, vectors whose elements are abstracted by a
    single abstract value, boolean constants, and other atomic values.  The abstract
    value for each atomic value contains a list of witnesses whose return values
    are contained in the actual value.  It's pretty good about avoiding false
    complaints, so programmers should rarely have to insert a `disclose` wrapper
    where it isn't inherently required.

# Compiler version `0.20.2`, language version `0.13.2`
- address PM-13381
  - Replaced old for syntax with:
    for (const id of nat1..nat2) stmt
    for (const id of expr) stmt

# Compiler version `0.20.1`, language version `0.13.1`
- address PM-13374
  - The Cell wrapper in ledger declarations is now optional; that is,
    a ledger field declaration of the form ledger fld: T, where T
    is an ordinary Compact type, is equivalent to ledger fld: Cell<T>.
- address PM-13755
  - Ledger ADT bindings are now part of the standard library and so
    are visible only within the scope of an import of the standard library.
    In the surface syntax, a ledger ADT type syntax is identical to the
    syntax for other types and type references; an ordinary type used as
    an implicit Cell ADT type is identified as such only by its position
    in a ledger declaration, and an explicitly named ADT type is
    recognized as such only if it resolves to an ADT type binding
    exported from the standard library.
- address PM-13600
  - For each module defined by or imported into a Compact program,
    the compiler now creates one instance of the module for each
    type-parameterization of the module.  Similarly, for each
    ledger field or function defined in a program or module instance,
    the compiler now creates just one copy for each type-parameterization
    of the ledger field or function.  This yields a predicatable model
    for when multiple instantiations of a function or ledger field appear in
    the generated output and when these instantiations result in
    multiply-defined identifier errors.
- other changes
  - The compiler no longer complains when an exported circuit has the
    same name as a witness or external circuit in a program's top
    level, since this name duplication actually causes no issues
    and is otherwise simply permissible function name overloading.
  - Improved some error messages.
- internal notes:
  - midnight-ledger.ss has been abstracted completely away from the
    types defined by any Compact compiler intermediate language.
  - the parser is no longer publishing ADT names, and the vsc support
    code no looks for find them.  if we want vsc to know about
    these, we should have the compiler publish a complete list of
    standard-library names, categorized by kind, e.g., type name
    or circuit name.

# Compiler version `0.20.0`, Language Version `0.13.0`
- bumping of versions due to release
- changes source of example applications to `compactc-main` branch

# Compiler version `0.19.7`, Language Version `0.12.3`
- fixes PM-13618
  - Conditionally executing a ledger operation on a nested Map can
    result in an internal error.

# Compiler version `0.19.7`, Language Version `0.12.3`
- address PM-10444
  - The Compact standard library is now a built-in module called
    CompactStandardLibrary.  The include file lib/std.compact is
    still present for backward compatibility and contains just the
    single line `import CompactStandardLibrary;`.
- address PM-9060
  - The compiler now looks for imported modules in the file system
    if no visible definition already exists. The import syntax
    has been generalized to allow the module to be identified
    by a string pathname.  In this case, the compiler always looks
    for the module in the file system.  The compiler looks first
    for imported modules relative to the path of the importing
    file, then in the directories identified by `COMPACT_PATH`.  It
    is possible to import two modules with the same name if they
    are imported from different paths.
- address PM-7007
  - The compiler now looks first for include files relative to
    the path of the including file, then in the directories
    identified by `COMPACT_PATH`.
- other changes:
  - The ordering of exported circuit definitions in the generated
    TypeScript now fully follows the source-file ordering.
- internal notes:
  - The (passes) library in passes.ss has been split into several
    separate files, each containing one set of passes.  passes.ss
    now contains just the driver code that runs the passes.

# Compiler version `0.19.6`, Language Version `0.12.2`
- fixes PM-13365
  - Nested one-armed if statements of the form if (e1) if (e2) s3
    where s3 is a for loop or an expression whose type is not Void
    can result in an internal error, as can various similar forms
    of nested if statements and if expressions used as statements.

# Compiler version `0.19.5`, Language Version `0.12.2`
- address PM-13336 / PM-13350
  - The anonymous circuit form has been replaced with arrow syntax, e.g.,
    circuit (x: T, ...): T^ { body } can now be written as
    (x: T, ...): T^ => { body }, where the type annotations are optional.
    If body can be expressed as a single return statement return
    e, this can be shortened to (x: T, ...): T^ => e.  Inferring undeclared
    types is generally straightforward, but it gets a bit tricky for fold
    as described in an extensive comment within the anonymous circuit case
    of infer-type's do-call helper.
- address PM-13337
  - Expression sequences of the form expr, ..., expr are now allowed
    outside of parentheses, in places where TypeScript/JavaScript would
    allow them.
- address PM-12226
  - Now producing a better error message when the left-hand-side of an
    assignment operator is something other than an ADT type (was complaining
    about the left-hand-side of ".", now complains about the left-hand-side
    of "=", "+=", or "-=" as appropriate).
- address PM-13319
  - Preferences reporting of errors in ledger ADT type arguments to errors
    regarding missing types required by the ledger operators brought in
    scope by the ledger binding, and produces a better error message for
    the latter.

# Compiler version `0.19.4`, Language Version `0.12.1`
- address PM-13258
  - Added the new structure-creation "spread" syntax.
  - Removed the `new` syntax and added the spread syntax described in
    https://github.com/input-output-hk/midnight-architecture/blob/main/proposals/0015-spread-syntax.md
  - Added extension whereby the element names can be omitted if no
    struct to spread is supplied, in which case the elements are
    positional, ala the 'new' syntax.
  - Modified flake.nix to download a parallel branch of the
    midnight-example-application repo in which the example applications
    have been updated to use the revised syntax.
- address PM-13321
  - Removed redundant source-file paths from error messages that include
    secondary source locations with the same source-file paths as the
    primary source location.

# Compiler version `0.19.3`, Language Version `0.12.0`
- address PM-11094
  - Function overloading no longer fails due to a failing generic
    parameterization for one of the candidates if another candidate
    succeeds and has compatible argument types.
- improves the quality of error overloading messages 
  - clarifies the wording of the messages
  - treats generic parameter and parameter failures similarly
  - uses the same indentation for expected and actual types,
    simplifying comparison by eye
  - provides a separate message for failure to meet `fold`'s
    additional requirement that the function's declared return
    and first-argument types be the same
  - removes unnecessary punctuation on line endings, counting
    instead of --vscode's new behavior described below
- the --vscode option now inserts a semicolon before each
  deleted newline if the line does not already end in a comma,
  colon, or semicolon so multiline error messages need not
  include superfluous line-ending punctuation marks

# Compiler version `0.19.2`
- fixes PM-12561 (https://input-output.atlassian.net/browse/PM-12561):
  - an update to a ledger field on one branch of a conditional but not the
    other can result in an internal error.
- fixes PM-12617 (https://input-output.atlassian.net/browse/PM-12617):
  - the implicit upcasting of a vector-valued expression to a declared return
    type of Void triggers an internal error.
- fixes PM-12623 (https://input-output.atlassian.net/browse/PM-12623):
  - effects of a return-value expression whose actual type is not Void are
    lost if the declared return-type is Void.
- Removes install scripts that are shipped with compactc
