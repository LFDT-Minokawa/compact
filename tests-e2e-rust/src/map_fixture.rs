// SPDX-License-Identifier: Apache-2.0
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
