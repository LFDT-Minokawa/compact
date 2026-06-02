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
// TS reference shapes for tiny.compact. Multi-step shape — the
// M2-era constructor-only fields stay at the top level so the
// original byte-parity test (`tests/tiny.rs`) keeps working, and
// the `after_*` slots cover the M2.1 per-step extensions
// (`afterInit` / `afterClear` / `afterSet99` / `getResult`).

use serde::Deserialize;
use std::path::Path;

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
