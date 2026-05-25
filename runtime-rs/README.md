# compact-runtime

Native Rust runtime for contracts emitted by `compactc --rust`.

This crate is the Rust counterpart to the TypeScript package
`@midnight-ntwrk/compact-runtime`. Generated contract code (`contract/lib.rs`)
depends on it; users typically do not consume it directly.

See [Compact docs](../doc/) for the language reference and
[Rust codegen design spec](../docs/superpowers/specs/2026-05-25-rust-codegen-design.md)
for runtime API details.
