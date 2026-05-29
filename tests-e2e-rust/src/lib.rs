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
#[derive(Deserialize, Debug)]
pub struct TinyTsReferenceState {
    #[serde(rename = "stateHex")]
    pub state_hex: String,
    pub ledger: TinyLedgerSnapshot,
}

#[derive(Deserialize, Debug)]
pub struct TinyLedgerSnapshot {
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
