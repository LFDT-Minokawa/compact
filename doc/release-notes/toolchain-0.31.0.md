# Compact toolchain 0.31.0

This is a first draft of the release notes for Compact toolchain 0.31.0,
assembled from the raw CHANGELOG entries that fall within the 0.30.100–0.31.0
compiler range (language 0.22.100–0.23.0, runtime 0.15.100–0.16.0). Polished
release notes will be added on the release branch.

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

## Known issues

- `zkir-v3` crashes on Apple silicon macOS. See
  [#280](https://github.com/LFDT-Minokawa/compact/issues/280).
- The real fix for unguarded conditional ZKIR operators is still pending
  in zkir. The compiler workarounds described under 0.30.107 above ship in
  0.31.0, but may increase circuit sizes as noted. See
  [#226](https://github.com/LFDT-Minokawa/compact/issues/226).
