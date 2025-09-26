# `compact` the compact tool

Compact is a tool made for installing the compact toolchain and keeping it
up-to-date. It is also possible to use it to install specific versions
of the toolchain.

# Installation

TODO

# Usage

```
compact check
compact update
compact compile -- --version
```

## update

To keep `compact` up to date, simply run:

```
compact self-update
```

# Development

## To build it yourself

1. install the rust toolchain: [rustup.rs](https://rustup.rs)
2. build with `cargo build`

Learn more about Rust [here](https://www.rust-lang.org/learn).

usage example

```
# install the a specific compiler version
cargo run -- update 0.20.0
# check for new compact compiler version
cargo run -- check
# install the latest compiler version
cargo run -- update
# invoke compiler
cargo run -- compile --version
cargo run -- compile +0.21.0 --version
```

## Release

The `compact` toolsuite uses `cargo-dist` for releases and updates.
In order to cut a release simply update the version of the crate and
add the appropriate git tag.

# License

This project is licensed under the [Apache-2.0] license.

## Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in compact by you, shall be licensed as [Apache-2.0], without
any additional terms or conditions.

[Apache-2.0]: http://www.apache.org/licenses/LICENSE-2.0
[cargo-dist]: https://opensource.axo.dev/cargo-dist/
