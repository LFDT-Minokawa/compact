// SPDX-License-Identifier: Apache-2.0
//
// Generic TS reference shapes shared across fixtures. Specifically:
//
// - `TsReferenceState`        — the counter-era single-step fixture
//                                with an auxiliary `counterValue` field.
// - `SmallFixtureTsReference` — the F4–F7+ post-init-only shape used
//                                by every "single ledger field, no
//                                source-level constructor" fixture
//                                introduced from M3.5 onwards.
// - `CapturedMerklePath`      — a serialised `MerklePath<T>` captured
//                                from a TS driver, used by both
//                                zerocash and election to replay
//                                witness paths from TS into Rust.

use serde::Deserialize;
use std::path::Path;

/// Original M2-era reference shape. One serialised `ContractState` plus
/// a stringified BigInt for the counter contract's single Counter
/// field. Kept here because `tests/counter.rs` still uses it.
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

/// Generic loader for the post-init-only fixtures introduced from
/// M3.5 onwards (uints / aliases / witnesses / set / map / list / …).
/// Each carries the identical `{ "afterInit": { "stateHex": "…" } }`
/// shape — one snapshot of `ContractState.serialize()` after the
/// implicit constructor.
#[derive(Deserialize, Debug)]
pub struct SmallFixtureTsReference {
    #[serde(rename = "afterInit")]
    pub after_init: SmallFixtureStepSnapshot,
}

#[derive(Deserialize, Debug)]
pub struct SmallFixtureStepSnapshot {
    #[serde(rename = "stateHex")]
    pub state_hex: String,
}

impl SmallFixtureStepSnapshot {
    pub fn state_bytes(&self) -> Vec<u8> {
        hex::decode(&self.state_hex).expect("decode hex")
    }
}

impl SmallFixtureTsReference {
    pub fn load(path: impl AsRef<Path>) -> Self {
        let raw = std::fs::read_to_string(path).expect("read fixture");
        serde_json::from_str(&raw).expect("parse fixture")
    }
}

// ---------------------------------------------------------------------------
// CapturedMerklePath — TS-side MerklePath replay for Rust witnesses.
// ---------------------------------------------------------------------------

/// One MerklePath captured from a TS driver. Mirrors the in-circuit
/// `MerkleTreePath<n, T>` shape: a leaf (the user's struct as 32-byte
/// hex) and a Vec of entries — each `(sibling.field, goes_left)`,
/// totalling `n` entries.
#[derive(Deserialize, Debug, Clone)]
pub struct CapturedMerklePath {
    /// Hex of the leaf bytes (the user struct's `bytes` field).
    #[serde(rename = "leafHex")]
    pub leaf_hex: String,
    pub path: Vec<CapturedMerklePathEntry>,
}

#[derive(Deserialize, Debug, Clone)]
pub struct CapturedMerklePathEntry {
    /// Hex of the sibling field element, big-endian, 32 bytes.
    #[serde(rename = "siblingHex")]
    pub sibling_hex: String,
    #[serde(rename = "goesLeft")]
    pub goes_left: bool,
}

impl CapturedMerklePath {
    /// Decode the leaf as a `[u8; 32]`.
    pub fn leaf_bytes(&self) -> [u8; 32] {
        let bytes = hex::decode(&self.leaf_hex).expect("decode leaf hex");
        let mut out = [0u8; 32];
        out.copy_from_slice(&bytes);
        out
    }

    /// Decode the path entries into upstream `MerklePathEntry` form.
    /// Each `siblingHex` is big-endian 32 bytes; `Fr::from_le_bytes`
    /// expects little-endian, so we reverse before passing.
    pub fn into_entries(&self) -> Vec<midnight_transient_crypto::merkle_tree::MerklePathEntry> {
        use midnight_transient_crypto::curve::Fr;
        use midnight_transient_crypto::merkle_tree::{MerklePathEntry, MerkleTreeDigest};
        self.path
            .iter()
            .map(|e| {
                let mut be = hex::decode(&e.sibling_hex).expect("decode sibling hex");
                // big-endian -> little-endian
                be.reverse();
                let fr = Fr::from_le_bytes(&be).expect("sibling field bytes are not a valid Fr");
                MerklePathEntry {
                    sibling: MerkleTreeDigest(fr),
                    goes_left: e.goes_left,
                }
            })
            .collect()
    }
}
