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
// TS reference shape for zerocash.compact's byte-parity tests
// (F1.1 + F1.2 of the M3.5 plan). F1.1 captures only `after_init`.
// F1.2 adds `after_mint` and optionally `after_spend`. Either step
// may be absent if the TS driver threw before producing it; the
// Rust test gates on presence.

use crate::common::CapturedMerklePath;
use serde::Deserialize;
use std::path::Path;

#[derive(Deserialize, Debug)]
pub struct ZerocashTsReferenceState {
    #[serde(rename = "afterInit")]
    pub after_init: ZerocashStepSnapshot,
    #[serde(rename = "afterMint", default)]
    pub after_mint: Option<ZerocashStepSnapshot>,
    #[serde(rename = "afterSpend", default)]
    pub after_spend: Option<ZerocashStepSnapshot>,
    /// Captured MerklePath for the spend's `old_commitment` lookup,
    /// emitted by capture-zerocash.mjs so the Rust witness can replay
    /// the same bytes. `None` when the TS driver did not reach spend.
    #[serde(rename = "spendPath", default)]
    pub spend_path: Option<CapturedMerklePath>,
}

/// One step's snapshot. Either `state_hex` is present (driver
/// succeeded) or `error` is present (driver threw — useful for
/// fixture diagnostics).
#[derive(Deserialize, Debug)]
pub struct ZerocashStepSnapshot {
    #[serde(rename = "stateHex", default)]
    pub state_hex: Option<String>,
    #[serde(default)]
    pub error: Option<String>,
}

impl ZerocashStepSnapshot {
    pub fn state_bytes(&self) -> Vec<u8> {
        let hex = self
            .state_hex
            .as_ref()
            .expect("snapshot has no stateHex (driver errored)");
        hex::decode(hex).expect("decode hex")
    }
}

impl ZerocashTsReferenceState {
    pub fn load(path: impl AsRef<Path>) -> Self {
        let raw = std::fs::read_to_string(path).expect("read fixture");
        serde_json::from_str(&raw).expect("parse fixture")
    }
}
