# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Compact tools 0.4.0]

### Fixed

- A bug that caused a difference between `compact format` and `compact fixup`. Running `fixup` on a single file both
  overwrote the file and dumped the new file to `stdout` while `format` overwrote the file without output.
- A bug in which `compact fixup --language-version` did not print the correct language version.
