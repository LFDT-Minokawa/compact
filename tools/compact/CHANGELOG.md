# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
