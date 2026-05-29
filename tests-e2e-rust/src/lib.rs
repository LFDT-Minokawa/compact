// SPDX-License-Identifier: Apache-2.0
//
// Helpers for cross-language byte-parity tests. Each test loads a TS
// reference state (captured to JSON under fixtures/), drives the
// equivalent Rust path, and asserts byte equality.

use serde::Deserialize;
use std::path::Path;

#[derive(Deserialize, Debug)]
pub struct TsReferenceState {
    #[serde(rename = "stateHex")]
    pub state_hex: String,
    #[serde(rename = "counterValue")]
    pub counter_value: String, // BigInt comes back as a string
}

impl TsReferenceState {
    pub fn load(path: impl AsRef<Path>) -> Self {
        let raw = std::fs::read_to_string(path).expect("read fixture");
        serde_json::from_str(&raw).expect("parse fixture")
    }

    pub fn state_bytes(&self) -> Vec<u8> {
        hex::decode(&self.state_hex).expect("decode hex")
    }
}

/// Fixture shape used by tiny.compact (and any other contract whose
/// ledger view only exposes a single scalar `value` field). The
/// stateHex field is the hex of `ContractState.serialize()` after
/// driving the contract through its TS reference path.
///
/// The top-level `stateHex` / `ledger` mirror the M2-era constructor-only
/// fixture so the original byte-parity test keeps working. The
/// `after_*` slots are the M2.1 per-step extensions.
#[derive(Deserialize, Debug)]
pub struct TinyTsReferenceState {
    #[serde(rename = "stateHex")]
    pub state_hex: String,
    pub ledger: TinyLedgerSnapshot,

    #[serde(rename = "afterInit")]
    pub after_init: TinyStepSnapshot,
    #[serde(rename = "afterClear")]
    pub after_clear: TinyStepSnapshot,
    #[serde(rename = "afterSet99")]
    pub after_set_99: TinyStepSnapshot,
    #[serde(rename = "getResult")]
    pub get_result: TinyGetResult,
}

#[derive(Deserialize, Debug)]
pub struct TinyLedgerSnapshot {
    pub value: String,
}

#[derive(Deserialize, Debug)]
pub struct TinyStepSnapshot {
    #[serde(rename = "stateHex")]
    pub state_hex: String,
    pub ledger: TinyLedgerSnapshot,
}

impl TinyStepSnapshot {
    pub fn state_bytes(&self) -> Vec<u8> {
        hex::decode(&self.state_hex).expect("decode hex")
    }
}

#[derive(Deserialize, Debug)]
pub struct TinyGetResult {
    #[serde(rename = "isSome")]
    pub is_some: bool,
    pub value: String,
}

impl TinyTsReferenceState {
    pub fn load(path: impl AsRef<Path>) -> Self {
        let raw = std::fs::read_to_string(path).expect("read fixture");
        serde_json::from_str(&raw).expect("parse fixture")
    }

    pub fn state_bytes(&self) -> Vec<u8> {
        hex::decode(&self.state_hex).expect("decode hex")
    }
}
