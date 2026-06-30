# Compact toolchain 0.32.0 (unreleased)

- **Date**: 2026-06-30
- **Language version:** 0.24.0
- **Compact runtime version:** 0.17.0
- **Environment**: _[TODO]_ For the full compatibility matrix, see the [release notes overview](https://docs.midnight.network/relnotes/overview)

## High-level summary

Version 0.32.0 of the Compact toolchain is unreleased.  The version number was incremented in the Compact repository in preparation for switching from Midnight ledger version 8 to Midnight ledger version 9.  Ledger 9 releases of the Compact toolchain will be version 0.33 or later, so the version number 0.32.0 is being "reserved" (and skipped for now) to be used if it becomes necessary to make another ledger 8 release.

Features described in these release notes will also be part of the first ledger 9 release, which is likely toolchain version 0.33.0.

## Audience

These release notes are intended for Compact smart contract developers and for DApp developers who use the Compact runtime.

## What changed

The standard library has new built in support for Schnorr signature verification and Jubjub point negation.

There is new built in support for Keccak-256 hashing, but it requires enabling the experimental "ZKIR version 3" feature and using a dedicated proof server that is not yet released.

The compiler now writes a contract manifest JSON file containing file sizes and SHA-256 hashes of file contents for the compiler-generated outputs.

There are some breaking changes to the compiler's command-line API and to the rules for Compact identifiers and reserved words.

## New features

### Schnorr signature verification over the Jubjub curve

The standard library has new built in support for Compact verification of Schnorr signatures over the Jubjub curve.

There is a new standard library circuit `jubjubSchnorrVerify<N>`.

```compact
circuit jubjubSchnorrVerify<#N>(msg: Vector<N, Field>,
                                signature: JubjubSchnorrSignature,
                                pk: JubjubPoint): Boolean
```

It is parameterized over `N`, the length of the message.  It takes (1) the unhashed message as `Vector<N, Field>`, (2) the signature (with standard library structure type `JubjubSchnorrSignature`) containing a `JujubPoint` announcement and a `Field` response, and (3) the public key as a `JubjubPoint`.  It returns a boolean value that indicates whether the signature is valid or not.

Note that if you want to ensure that a signature is valid, you should `assert` that the result of this circuit is true in Compact.

### Keccak-256 hashing

The standard library has a new built in circuit for Keccak-256 hashing.  There is a new circuit `keccak256` with the same signature as the existing `persistentHash` (SHA-256) hashing circuit:

```compact
circuit keccak256<A>(value: A): Bytes<32>
```

It is generic over the value type `A`.  It takes a value of type `A` and produces the 32-byte hash.

**NOTE:** This is **only** available using the experimental ZKIR version 3 compiler feature.  This is because there is no implementation of Keccak-256 in ZKIR version 2, and emulating it in circuit is expensive.  The ZKIR version 3 feature is selected a compile time by passing the flag `--feature-zkir-v3` flag to the compiler.  Without the flag, calling `keccak256` in a circuit that needs ZKIR output will be a compiler error.

With the flag `--feature-zkir-v3`, the compiler will produce ZKIR version 3 files in the `zkir` subdirectory of the output directory.  You will need a proof server that can understand these files, and because this compiler version is not (yet) released, there is also not (yet) a ZKIR v3 proof server release.

### `JubjubPoint` negation

The standard library has a new circuit `ecNeg` that negates a `JubjubPoint`.  It takes a `JubjubPoint` argument `a` and returns a `JubjubPoint` result `b` such that `ecAdd(a,ecNeg(b))` is the additive identity point (the same value as `default<JubjubPoint>` and `constructJubjubPoint(0,1)`).

This feature was contributed by GitHub user `adamreynolds-io`.

### Contract manifest files

The compiler now writes a contract manifest file, a JSON file containing file sizes and SHA-256 checksums of file contents for all the compiler's output artifacts (except for the contract manifest itself).  This file is written to `contract-manifest.json` in the `compiler` subdirectory of the output directory.

The contract manifest includes a JSON object with properties containing the manifest format version (currently version 1) and the compiler, language, and runtime versions:

```json
"manifest-version": "1",
"compiler-version": "0.32.0",
"language-version": "0.24.0",
"runtime-version": "0.17.0",
```

It has a property for each directory and file written by the compiler, with the property name being the directory or file name.  They each have a `"type"` property which is either `"directory"` or `"file"`.  Directories have their contents and files have their size in bytes and the SHA-256 hash of their contents, for example:

```json
"contract": {
  "type": "directory",
  "index.d.ts": {
    "type": "file",
    "size": 1698,
    "hash": "09d1c4cb38d98af92a10e36e0f48d2e0abc95be9848ec9be2780924f525d9a33"
  },
  "index.js": {
    "type": "file",
    "size": 12830,
    "hash": "3583b5a9ad30dbbbf4b3314ae54a98cd0c09e296bf5a37e2d1ce627253b778cd"
  },
  "index.js.map": {
    "type": "file",
    "size": 1538,
    "hash": "cbe18511ba707bd0169c630cf6acdd206ef31e6632741202e2f968701d477877"
  }
}
```

## Breaking changes

### The compiler removes and recreates the `contract` subdirectory

Before, the compiler would delete and recreate the `compiler`, `zkir`, and `keys` subdirectories.  However, it would leave the `contract` subdirectory and its contents in place and simply replace the compiler outputs `index.d.ts`, `index.js`, and `index.js.map`.

Now the compiler also deletes and recreates the `contract` subdirectory.  This is a **breaking change** to the compiler command-line API.  If you were previously placing other files in this directory alongside the compiler-generated ones, you should move them elsewhere.

### New reserved words: `arguments`, `eval`, `event`, and `log`

`arguments` and `eval` have been added as "future reserved words".  These are reserved in JavaScript.  Previously they would be accepted as identifiers in Compact, but the generated JavaScript code would be invalid.

`event` and `log` have also been added as future reserved words.  There are plans to use these as keywords for a new event logging facility in Compact.

These are **breaking changes**.  Programs that used these words as identifiers will no longer compile.  You can fix your code by renaming these identifiers.

### Identifier syntax matches JavaScript's

The rules for Compact identifiers have been changed to match those of [JavaScript](https://tc39.es/ecma262/#sec-names-and-keywords) and [Unicode UAX #31](https://www.unicode.org/reports/tr31/#Table_Lexical_Classes_for_Identifiers).  The rules have been tightened to allow Unicode `ID_Start` plus underscore `_` and dollar sign (`$`).  Previously, all alphabetic characters were allowed, which included non-`ID_Start` characters.  These were not valid JavaScript identifiers and the compiler-generated JavaScript code would be invalid.

Similarly, subsequent characters after the first now follow Unicode's `ID_Continue`.  Previously these included some non-`ID_Continue` characters.

This is a **breaking change**.  Programs that used these identifiers will no longer compile.  You can fix your code by renaming these identifiers.
