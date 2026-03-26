# Compact devtools 0.5.0

- **Date**: 2026-03-17
- **Version:** 0.5.0
- **Environment**: Compact devtools is independent of the blockchain environment

## High-level summary

Version 0.5.0 of the devtools has a pair of usability improvements.  Subcommands can now be abbreviated, and the `update` subcommand will accept partial version numbers.

## Audience

These release notes are intended for Compact smart contract developers and for DApp developers who use the Compact runtime.

## What changed

There are a pair of usability improvements:

- Subcommands can be abbreviated
- The `update` subcommand can accept partial version numbers

## New features

### Subcommand abbreviations

The `compact` CLI tool now accepts abbrevaions for the subcommands.  For example, `compact up` for "update", `compact c` for "compile", and `compact fmt` for "format".

Most subcommands have "official" aliases, like `fmt` for "format" and `fx` for "fixup".  You can see these listed in the help text avaialable via `compact help` or `compact --help`.

In addition, most subcommands will also accept any prefix of the subcommand.  For example `compact c`, `compact co`, `compact com`, etc. all work for "compile".

We have had to make some choices when a prefix is ambiguous.  For example, `compact c` is used for "compile", not "clean".

These features were contributed by GitHub user `rvcas`.

### Partial version numbers

The `update` subcommand now accepts partial version numbers.  For example, `compact update 0.30` with a missing patch version number will update to the latest toolchain version 0.30.x with patch number x.  You do not need to know how many patch versions there have been to update to the latest.

Likewise, `compact update 0` will update to the latest minor and patch version 0.x.y.  This is less useful before version 1.0, when minor version updates possibly include breaking changes.  But after Compact 1.0 is released, you could use `compact up 1` to be on the latest patched version of Compact 1, no matter whether it was 1.4.x, 1.5.x, and so forth.

Parts of this feature were contributed by GitHub user `adamreynolds-io`.

## Improvements

There are no other improvements than the two features mentioned above.

## Deprecations

None.

## Breaking changes.

None.

## Known issues

- [Issue #220: zkir crashes with SIGILL on ARM Docker — no aarch64-linux release available (compact-v0.4.0)](https://github.com/LFDT-Minokawa/compact/issues/220)

This issue will be fixed in a bug fix release.
