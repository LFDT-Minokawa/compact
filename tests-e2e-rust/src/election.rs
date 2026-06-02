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
// TS reference shape for election.compact's byte-parity tests
// (F2.1 + F2.2 of the M3.5 plan).
//
// F2.1 captures only `after_init` (the implicit constructor with no
// body). F2.2 adds owner-driven impure circuits: `set_topic`,
// `advance`, `add_voter`, plus `vote$commit` and `vote$reveal`.
// Because election.compact's original revision lacked a source-level
// constructor, the implicit `initial_state` seeded `authority` to
// `[0u8; 32]` and every owner-driven step failed the
// `public_key(sk) == authority` assertion; that's why each post-init
// snapshot is optional with an `error` slot.
//
// Any field may be absent if the TS driver threw before producing it.

use crate::common::CapturedMerklePath;
use serde::Deserialize;
use std::path::Path;

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
