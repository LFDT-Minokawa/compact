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
// TS reference shape for map_fixture.compact's initial_state()
// byte-parity test (F3 of the M3.5 plan). The fixture has an
// implicit empty constructor, so only the post-init snapshot is
// captured. Exercises the `Map<K, V>` ADT — closing the M3.5 ADT
// matrix.

use serde::Deserialize;
use std::path::Path;

#[derive(Deserialize, Debug)]
pub struct MapFixtureTsReferenceState {
    #[serde(rename = "afterInit")]
    pub after_init: MapFixtureStepSnapshot,
}

#[derive(Deserialize, Debug)]
pub struct MapFixtureStepSnapshot {
    #[serde(rename = "stateHex")]
    pub state_hex: String,
}

impl MapFixtureStepSnapshot {
    pub fn state_bytes(&self) -> Vec<u8> {
        hex::decode(&self.state_hex).expect("decode hex")
    }
}

impl MapFixtureTsReferenceState {
    pub fn load(path: impl AsRef<Path>) -> Self {
        let raw = std::fs::read_to_string(path).expect("read fixture");
        serde_json::from_str(&raw).expect("parse fixture")
    }
}
