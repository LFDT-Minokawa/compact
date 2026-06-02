// SPDX-License-Identifier: Apache-2.0
//
// Cross-language byte-parity test helpers.
//
// Each test loads a TS reference state (captured to JSON under
// fixtures/), drives the equivalent Rust path, and asserts byte
// equality. The reference-state shapes are split per-contract so a
// fixture author can find the structure relevant to their contract
// without skimming the others.
//
// See README.md for the full "add a new fixture" walkthrough.

mod common;
mod election;
mod map_fixture;
mod tiny;
mod zerocash;

// Flat re-exports keep the public API stable: existing tests written
// against `tests_e2e_rust::FooTsReferenceState` keep compiling.
pub use common::{
    CapturedMerklePath, CapturedMerklePathEntry, SmallFixtureStepSnapshot, SmallFixtureTsReference,
    TsReferenceState,
};
pub use election::{ElectionStepSnapshot, ElectionTsReferenceState};
pub use map_fixture::{MapFixtureStepSnapshot, MapFixtureTsReferenceState};
pub use tiny::{TinyGetResult, TinyLedgerSnapshot, TinyStepSnapshot, TinyTsReferenceState};
pub use zerocash::{ZerocashStepSnapshot, ZerocashTsReferenceState};
