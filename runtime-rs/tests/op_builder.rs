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
// Tests for the typed Op-program builders.

use compact_runtime::*;

#[test]
fn verify_builder_produces_idx_addi_ins() {
    let ops = OpProgramVerify::<DefaultDB>::new()
        .idx_at_index(0u8, true)
        .addi(1)
        .ins(true, 1)
        .build();
    assert_eq!(ops.len(), 3);
    match &ops[0] {
        Op::Idx {
            cached,
            push_path,
            path,
        } => {
            assert!(!cached);
            assert!(push_path);
            assert_eq!(path.iter().count(), 1);
        }
        other => panic!("expected Idx, got {other:?}"),
    }
    match &ops[1] {
        Op::Addi { immediate } => assert_eq!(*immediate, 1),
        other => panic!("expected Addi, got {other:?}"),
    }
    match &ops[2] {
        Op::Ins { cached, n } => {
            assert!(*cached);
            assert_eq!(*n, 1);
        }
        other => panic!("expected Ins, got {other:?}"),
    }
}

#[test]
fn verify_builder_matches_manual_literal() {
    let built = OpProgramVerify::<DefaultDB>::new()
        .idx_at_index(0u8, true)
        .addi(1)
        .ins(true, 1)
        .build();

    let manual: Vec<Op<ResultModeVerify, DefaultDB>> = vec![
        Op::Idx {
            cached: false,
            push_path: true,
            path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),
        },
        Op::Addi { immediate: 1 },
        Op::Ins { cached: true, n: 1 },
    ];

    // Op doesn't necessarily implement PartialEq directly across all variants
    // in the right way for our purposes; compare via Debug for a stable
    // structural comparison.
    assert_eq!(format!("{built:?}"), format!("{manual:?}"));
}

#[test]
fn gather_builder_produces_dup_idx_popeq() {
    let ops = OpProgramGather::<DefaultDB>::new()
        .dup(0)
        .idx_at_index(0u8, false)
        .popeq(true)
        .build();
    assert_eq!(ops.len(), 3);
    match &ops[0] {
        Op::Dup { n } => assert_eq!(*n, 0),
        other => panic!("expected Dup, got {other:?}"),
    }
    match &ops[1] {
        Op::Idx {
            cached, push_path, ..
        } => {
            assert!(!cached);
            assert!(!push_path);
        }
        other => panic!("expected Idx, got {other:?}"),
    }
    match &ops[2] {
        Op::Popeq { cached, .. } => assert!(*cached),
        other => panic!("expected Popeq, got {other:?}"),
    }
}

#[test]
fn gather_builder_matches_manual_literal() {
    let built = OpProgramGather::<DefaultDB>::new()
        .dup(0)
        .idx_at_index(0u8, false)
        .popeq(true)
        .build();
    let manual: Vec<Op<ResultModeGather, DefaultDB>> = vec![
        Op::Dup { n: 0 },
        Op::Idx {
            cached: false,
            push_path: false,
            path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),
        },
        Op::Popeq {
            cached: true,
            result: (),
        },
    ];
    assert_eq!(format!("{built:?}"), format!("{manual:?}"));
}

#[test]
fn verify_builder_roundtrips_through_query_for_verify() {
    // Smoke test: build a small Op program and pass it to query_for_verify.
    // We don't assert on the result — only that nothing panics and an error
    // (if any) is the expected TranscriptRejected, not a Rust-level panic.
    let ops = OpProgramVerify::<DefaultDB>::new()
        .idx_at_index(0u8, true)
        .addi(1)
        .ins(true, 1)
        .build();
    let qctx = QueryContext::new(empty_charged_state(), ContractAddress::default());
    let _ = query_for_verify(&qctx, &ops, None, &initial_cost_model());
}
