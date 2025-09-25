# `compact` the compact tool

Compact is a tool made for installing the compact toolchain and keeping it
up-to-date. It is also possible to use it to install specific versions
of the toolchain.

## Installation

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/midnightntwrk/compact/releases/latest/download/compact-installer.sh | sh
```

## Update

To keep `compact` up to date, simply run:

```
compact self update
```

## Usage

```
Commands:
  check   Check for updates with the remote server
  update  Update to the latest or a specific version of the Compact toolchain
  list    List available compact versions
  clean   Remove all compact versions
  help    Print this message or the help of the given subcommand(s)

Additional Commands:

* `compile [+VERSION] [ARGS...]': call the compiler for the given `VERSION'.

Usage examples:

  `compact compile source/path target/path`

  `compact compile +0.21.0 --help`

```

## Development

### To build it yourself

We have a standard rust monorepo setup with a workspace `Cargo.toml`
at the root of the repository. All cargo commands can be run from the
repository root.

1. install the rust toolchain: [rustup.rs](https://rustup.rs)
2. build with `cargo build`

#### Examples

```
# list available versions
cargo run -- list

# install the a specific compiler version
cargo run -- update 0.20.0

# check for new compact compiler version
cargo run -- check

# install the latest compiler version
cargo run -- update

# invoke compiler
cargo run -- compile --version
cargo run -- compile +0.21.0 --version

# clean up
cargo run -- clean
```

### Testing

We recommend running tests with [cargo-nextest](https://nexte.st/docs/installation/pre-built-binaries/).

```sh
GITHUB_TOKEN=$(gh auth token) cargo nextest run --no-fail-fast --test-threads=1
```

> We recommend using a github token to avoid getting rate limited when
  running tests. Many of the tests invoke the tool directly and make real
  calls to GitHub's API. We recommend using [gh](https://cli.github.com/) to
  easy set a token.

### Release

The `compact` toolsuite uses `cargo-dist` for releases and updates.
In order to cut a release simply update the version of the crate and
add the appropriate git tag.

## License

This project is licensed under the [Apache-2.0] license.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in compact by you, shall be licensed as [Apache-2.0], without
any additional terms or conditions.

[Apache-2.0]: http://www.apache.org/licenses/LICENSE-2.0
[cargo-dist]: https://opensource.axo.dev/cargo-dist/
