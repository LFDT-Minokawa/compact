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

/// Fixture shape for zerocash.compact's byte-parity tests (F1.1 + F1.2 of
/// the M3.5 plan). F1.1 captures only `after_init`. F1.2 adds `after_mint`
/// (post zerocash_mint) and optionally `after_spend`. Either step may be
/// absent if the TS driver threw before producing it; the Rust test gates
/// on presence.
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

/// One MerklePath captured from the TS driver. The structure mirrors
/// the in-circuit `MerkleTreePath<n, T>`: a leaf (here the user's
/// `commitment` struct as 32-byte hex) and a Vec of entries — each
/// `(sibling.field, goes_left)` — totalling `n` entries.
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
    pub fn into_entries(
        &self,
    ) -> Vec<midnight_transient_crypto::merkle_tree::MerklePathEntry> {
        use midnight_transient_crypto::curve::Fr;
        use midnight_transient_crypto::merkle_tree::{
            MerklePathEntry, MerkleTreeDigest,
        };
        self.path
            .iter()
            .map(|e| {
                let mut be = hex::decode(&e.sibling_hex).expect("decode sibling hex");
                // big-endian -> little-endian
                be.reverse();
                let fr =
                    Fr::from_le_bytes(&be).expect("sibling field bytes are not a valid Fr");
                MerklePathEntry {
                    sibling: MerkleTreeDigest(fr),
                    goes_left: e.goes_left,
                }
            })
            .collect()
    }
}

/// One step's snapshot. Either `state_hex` is present (driver succeeded) or
/// `error` is present (driver threw — useful for fixture diagnostics).
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

/// Fixture shape for election.compact's byte-parity tests (F2.1 + F2.2 of
/// the M3.5 plan).
///
/// F2.1 captures only `after_init` (the implicit constructor with no body).
/// F2.2 adds owner-driven impure circuits: `set_topic`, `advance`,
/// `add_voter`, plus `vote$commit` and `vote$reveal`. Because
/// election.compact lacks a source-level constructor, the implicit
/// `initial_state` seeds `authority` to `[0u8; 32]` and every
/// owner-driven step asserts `public_key(sk) == authority`, which the
/// witness's fixed `sk` cannot satisfy. Each post-init step therefore
/// records `error` rather than `state_hex`, and the Rust tests are
/// `#[ignore]`'d with diagnostic gating.
///
/// Either field may be absent if the TS driver threw before producing it.
#[derive(Deserialize, Debug)]
pub struct ElectionTsReferenceState {
    #[serde(rename = "afterInit")]
    pub after_init: ElectionStepSnapshot,
    #[serde(rename = "afterSetTopic", default)]
    pub after_set_topic: Option<ElectionStepSnapshot>,
    #[serde(rename = "afterAdvance", default)]
    pub after_advance: Option<ElectionStepSnapshot>,
    #[serde(rename = "afterAddVoter", default)]
    pub after_add_voter: Option<ElectionStepSnapshot>,
    #[serde(rename = "afterVoteCommit", default)]
    pub after_vote_commit: Option<ElectionStepSnapshot>,
    #[serde(rename = "afterVoteReveal", default)]
    pub after_vote_reveal: Option<ElectionStepSnapshot>,
    /// Captured `eligible_voters.path_of(VOTER_PK)` from the TS
    /// driver, used by vote$commit's witness.
    #[serde(rename = "votePathEligible", default)]
    pub vote_path_eligible: Option<CapturedMerklePath>,
    /// Captured `committed_votes.path_of(commit_cm)` from the TS
    /// driver, used by vote$reveal's witness.
    #[serde(rename = "votePathCommitted", default)]
    pub vote_path_committed: Option<CapturedMerklePath>,
}

#[derive(Deserialize, Debug)]
pub struct ElectionStepSnapshot {
    #[serde(rename = "stateHex", default)]
    pub state_hex: Option<String>,
    #[serde(default)]
    pub error: Option<String>,
}

impl ElectionStepSnapshot {
    pub fn state_bytes(&self) -> Vec<u8> {
        let hex = self
            .state_hex
            .as_ref()
            .expect("snapshot has no stateHex (driver errored)");
        hex::decode(hex).expect("decode hex")
    }
}

impl ElectionTsReferenceState {
    pub fn load(path: impl AsRef<Path>) -> Self {
        let raw = std::fs::read_to_string(path).expect("read fixture");
        serde_json::from_str(&raw).expect("parse fixture")
    }
}

/// Fixture shape for map_fixture.compact's initial_state() byte-parity test
/// (F3 of the M3.5 plan). map_fixture has an implicit empty constructor, so
/// the fixture only carries the post-init snapshot. Exercises the Map<K, V>
/// ADT — the last ledger ADT lacking byte-parity coverage in M3.5.
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

/// Generic loader for the small fixtures introduced in M3.5 F4–F7
/// (uints, aliases, witnesses, …). Each fixture has the identical
/// `{ "afterInit": { "stateHex": "…" } }` shape — one post-init snapshot
/// of `ContractState.serialize()` — so they all share one loader rather
/// than spawning a wave of one-off types.
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
