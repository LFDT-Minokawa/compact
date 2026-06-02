// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
