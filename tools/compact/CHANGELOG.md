# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The toolchain archive is now unpacked by `compact` itself rather than by
  running `unzip`. `unzip` is not installed by default on many systems -- the
  machine in issue #739 had `curl`, `tar`, `xz`, `zstd` and `gzip` but not
  `unzip`, so the toolchain could not be installed at all until a package was
  added. There is no longer an external program to install.

- An archive that cannot be unpacked is now discarded and fetched again. The
  archive was only downloaded when it was not already on disk, so a complete
  but unreadable one -- a bad checksum, a resume stitched across a changed
  artifact -- failed every retry identically, with deleting it by hand the only
  way forward. Only the archive's own faults are retried: a full disk or a
  permission error is reported as it happens, since fetching the file again
  would not help.

- `--help` output now wraps to the width of the terminal in the installed
  binary, not only under `cargo test`. `clap`'s `wrap_help` feature was
  never requested by this crate: it arrived through Cargo feature
  unification with the `cargo-nextest` dev-dependency, so wrapped help
  appeared in test builds while the binary users install printed one long
  line. The expected-output files recorded the wrapped form, so the help
  tests asserted output no user had ever seen. The feature is now
  requested explicitly.

### Fixed

- `compact update <version>` no longer treats a version as installed when only
  the version directory is present. An extraction that fails leaves that
  directory behind holding nothing but `artifact.zip`, and the previous check
  looked no further: it reported "already installed", skipped re-extraction, and
  then failed with `Expecting a file: '.../compactc'`. Installing the missing
  dependency and re-running now repairs the installation rather than reporting
  the same error again.

  Because the default-compiler symlink was written before it was validated, a
  failed retry also left a dangling `~/.compact/bin/compactc`, which made every
  later `compact check`, `compact list --installed` and `compact compile` fail
  the same way. `compact` now refuses to link a compiler binary that is not
  there, so one incomplete install can no longer break the others.

  Fixes issue #739.

- The error raised when the archive extraction command is missing now names it.
  A machine without `unzip` previously reported only `Failed to spawn artifact
  extraction command` followed by `No such file or directory (os error 2)`,
  identifying neither the command that was missing nor what to do about it.

- Archive extraction now passes `-o`. Standard input is closed for the
  extraction command, so an archive left partially extracted by an interrupted
  run produced an overwrite prompt that failed the retry instead of repairing
  it.

## [Compact tools 0.5.2]

### Fixed

- Compact dev tool used to have its own help for the compiler. Now it uses the 
  compiler help when one runs `compact compile --help`. If there's no compiler
  installed it gives an error that the user needs to install a compiler first.

## [Compact tools 0.5.1]

### Fixed

- A bug that prevented ARM Linux builds from being installed.  There was already
  a toolchain release `.zip` file for this platform (since toolchain version
  0.29.0), but the platform was not recognized by the command-line tools.
  
  Fixes issue #222.

## [Compact tools 0.5.0]

### Added

- The `compact` CLI tool now supports abbreviations for the subcommands.  For
  example, `compact up` for "update", `compact c` for "compile", `compact fmt`
  for "format".  Subcommands have "official" aliases like `fmt` for "format" and
  `fx` for "fixup" that you can see listed with the commands by using `compact
  help` or `compact --help`.  Also, for most subcommands, any prefix of the
  subcommand will work.  We have however had to make choices when a prefix is
  ambigous.  For example, `compact c` is "compile", not "clean".
  
  This change was contributed by GitHub user `rvcas`.

- `compact update` now understands partial version numbers.  For example,
  `compact update 0.30` (with no patch version number) will update to the
  **latest** toolchain patch version 0.30.x.  Likewise, `compact update 0` will
  update to the latest minor and patch version 0.x.y.
  
  This change was contributed (partially) by GitHub user `adamreynolds-io`.

## [Compact tools 0.4.0]

### Fixed

- A bug that caused a difference between `compact format` and `compact
  fixup`. Running `fixup` on a single file both overwrote the file and dumped
  the new file to `stdout` while `format` overwrote the file without output.

- A bug in which `compact fixup --language-version` did not print the correct
  language version.
