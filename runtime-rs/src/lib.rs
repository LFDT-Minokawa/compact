// SPDX-License-Identifier: Apache-2.0
//
// compact-runtime — native Rust facade matching @midnight-ntwrk/compact-runtime.
//
// Generated code emitted by `compactc --rust` depends on this crate. It exposes:
//   - a curated set of re-exports from the published `midnight-*` Rust crates
//     (state, VM, crypto, storage, zswap)
//   - a handful of facade aggregates (CircuitContext, WitnessContext, etc.)
//     that don't exist upstream
//   - the `check_runtime_version!` macro
//   - a thin `std_lib` module covering Compact stdlib types this codegen depth
//     needs (Counter ledger ADT, etc.)
//
// See docs/superpowers/specs/2026-05-25-rust-codegen-design.md §4 for the full
// API contract.

#![forbid(unsafe_code)]
