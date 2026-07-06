# Contributing

We welcome contributions to Compact! This guide covers how to set up the repository for development, build each component, run tests, and submit changes.

## Prerequisites

The Compact project has several components with different tooling requirements:

| Component | Tools needed |
|-----------|-------------|
| Compiler (`compiler/`) | [Nix](https://nixos.org) >= 2.7 with [flakes enabled](https://nixos.wiki/wiki/Flakes) |
| CLI tool (`tools/compact/`) | [Rust](https://rustup.rs) >= 1.88.0 |
| VS Code extension (`editor-support/vsc/`) | Node.js, Yarn |
| Runtime (`runtime/`) | Nix |

Nix is the primary build system for the compiler and runtime. It manages all dependencies (Chez Scheme, Node.js, TypeScript, etc.) automatically via development shells, so you don't need to install them separately.

For the CLI tool, you only need a Rust toolchain -- Nix is not required.

## Getting Started

Clone the repository:

```sh
git clone https://github.com/LFDT-Minokawa/compact.git
cd compact
```

## Compiler

The Compact compiler is written in [Chez Scheme](https://cisco.github.io/ChezScheme/) and built with Nix. For detailed notes on compiler architecture, intermediate languages, and pass structure, see [`compiler.md`](./compiler.md). Please keep `compiler.md` up to date when making changes to the compiler's architecture or pass structure.

### Building

```sh
nix build
```

This produces the `compactc`, `format-compact`, and `fixup-compact` binaries in `result/bin/`.

To add them to your path:

```sh
export PATH=$(pwd)/result/bin:$PATH
compactc --version
```

### Development Shell

Enter the development shell for compiler work:

```sh
nix develop
```

This sets up environment variables and all required dependencies. The default shell includes Node.js, Yarn, and the runtime packages.

Other specialized shells are available:

| Shell | Purpose |
|-------|---------|
| `nix develop` | Default: compiler development with runtime |
| `nix develop .#compiler` | Pre-built compactc with zkir |
| `nix develop .#runtime` | Runtime development (Scheme + JS) |

### Running Tests

All compiler tests live in [`compiler/test.ss`](./compiler/test.ss). When you make changes to the compiler, add corresponding unit tests in this file following the existing formatting conventions. Tests are organized by pass name (e.g., `parse-file`, `report-unreachable`) and use check forms such as `(returns ...)`, `(oops ...)`, `(warning ...)`, and `(succeeds)`.

Run tests from inside the Nix development shell:

```sh
# enter development shell
nix develop

# run compiler tests
./compiler/go

# full recompilation (for coverage)
./compiler/go --rebuild
```

**`./compiler/go` must pass without failures or warnings before you commit your changes.** If it reports failures or warnings, fix them before submitting a pull request.

#### E2E Tests

```sh
sh ./run-e2e-tests.sh
```

#### Debug Tests

```sh
sh ./run-debug-test.sh
```

### Updating the Language Reference

If your change modifies the Compact language (new syntax, changed grammar, new keywords, etc.), you must update the language reference:

1. Edit [`compiler/compact-reference-proto.mdx`](./compiler/compact-reference-proto.mdx). This is the source file for the language reference (the generated output is `doc/compact-reference.mdx`).
2. Grammar productions are inserted using special macros -- they are **not** written as literal tables:
   - `@(anchor-here ...)` -- defines anchor points for terminal names
   - `@(request-snippet ...)` -- inserts grammar snippets for non-terminal productions
3. Run `./compiler/go` after editing. It will warn about unrequested terminal and non-terminal names, helping you catch missing or mismatched grammar entries. Fix any warnings before committing.

## CLI Tool

The `compact` CLI is a Rust project in `tools/compact/`. It does not require Nix.

### Building

```sh
cargo build
```

### Running Tests

Integration tests live in `tools/compact/tests/` as `test_*.rs` files with shared helpers in `tests/common/mod.rs`. When contributing to the CLI, add tests that cover your changes in the appropriate `test_*.rs` file (or create a new one if needed) and **run the full test suite before committing**.

The tests make real calls to the GitHub API, so we recommend using a GitHub token to avoid rate limiting:

```sh
GITHUB_TOKEN=$(gh auth token) cargo nextest run --no-fail-fast --test-threads=1
```

If you don't have [cargo-nextest](https://nexte.st/docs/installation/pre-built-binaries/), you can use `cargo test` instead, but nextest is recommended.

Tests must run with `--test-threads=1` because they share state through the GitHub API.

### Formatting and Linting

```sh
cargo fmt --all -- --check
cargo clippy --all-targets --all-features -- -D warnings
```

### Releases

The CLI uses [cargo-dist](https://axodotdev.github.io/cargo-dist/) for releases. To cut a release, update the version in the workspace `Cargo.toml` and push a tag matching `compact-v<VERSION>`.

## VS Code Extension

The VS Code extension is in `editor-support/vsc/compact/`.

### Building

```sh
cd editor-support/vsc/compact
yarn install
yarn build
```

### Testing

```sh
yarn test       # unit tests (Jest)
yarn test-it    # integration tests
```

### Packaging

```sh
yarn package    # creates .vsix file
```

### Linting and Formatting

```sh
yarn lint       # ESLint
yarn format     # Prettier
```

## Runtime

The TypeScript runtime libraries are in `runtime/` and use Nix for development.

### Development Shell

```sh
nix develop .#runtime
```

### Running Tests

Tests live in `runtime/test/` (e.g., `stdlib.test.ts`) and use [Vitest](https://vitest.dev/). When contributing to the runtime, add tests covering your changes and **run the test suite before committing**:

```sh
cd runtime
npm test
```

## Submitting Issues

Use one of the issue templates to submit a bug report, feature request, or documentation improvement. Check if a similar issue already exists before submitting.

**Issue Types:**

* **Bug Report:** Provide detailed information about the issue, including steps to reproduce it, expected behavior, and actual behavior, screenshots, or any other relevant information.
* **Documentation Improvement:** Clearly describe the improvement requested for existing content and/or raise missing areas of documentation and provide details for what should be included.
* **Feature Request:** Clearly describe your feature, its benefits, and most importantly, the expected outcome. This helps us analyze the proposed solution and develop alternatives.
* **Enhancement:** (WIP)

## Code Contribution Process

1. **Fork the Repository:** Create your own fork of the repository.
2. **Create a Branch:** Make your changes in a separate branch,
   prefixed with a short name moniker (e.g. `jill-my-feature`).
3. **Follow Coding Standards:** Adhere to the coding style guides for the component you're modifying.
4. **Write and Run Tests:** Include unit tests and integration tests to cover your changes.
   Add tests in the appropriate location for the component you're modifying
   (see the component sections above for details) and run the full test suite
   before committing. Pull requests without tests or with failing tests will not be merged.
5. **Commit Messages:** Write clear and concise commit messages.
6. **Submit Pull Request:** Submit your pull request to the appropriate branch in the main repository.
   Please do not `--force` push -- doing so means that reviewers will have to re-review all
   commits in the PR rather than commits since last review.
7. **Code Review:** All pull requests undergo code review by project maintainers.
   Be prepared to address feedback from reviewers.

## Requirements for Acceptable Contributions

* **Coding Standards:** Code must adhere to the coding style guides for the component you're modifying.
* **Testing:** New functionality must include corresponding unit tests and integration tests.
* **Documentation:** Code changes should be accompanied by proposed relevant documentation updates.
* **License:** All contributions must be compatible with the project's license.
  Where possible all files should have this license header:

### License Headers

All new source files must include the Apache-2.0 license header:

```
// This file is part of Compact.
// Copyright (C) 2026 contributors to Minokawa Compact
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// You may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
```

Adjust the comment syntax for the file type (e.g., `;;;` for Scheme, `#` for shell scripts, `--` for Agda).

## Code of Conduct

This project follows the [LFDT Code of Conduct](https://www.lfdecentralizedtrust.org/code-of-conduct). Please report any concerns to legal@midnight.foundation.

## Getting Help

Connect with us on [Discord](https://discord.com/invite/midnightnetwork), [Telegram](https://t.me/Midnight_Network_Official), and [X](https://x.com/MidnightNtwrk).
