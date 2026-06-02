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
// End-to-end smoke test exercising the public API as generated code does.
// Constructs a counter, runs the `increment` Op sequence, decodes the new
// value. If this passes, the runtime is ready for codegen.

use compact_runtime::std_lib::Counter;
use compact_runtime::*;

#[test]
fn increment_counter_end_to_end() {
    // Seed contract state: array with one Cell(u64=0) at index 0.
    let initial = StateValue::Array(
        Array::<StateValue, _>::new().push(StateValue::from(AlignedValue::from(0u64))),
    );
    let state = ChargedState::new(initial);
    let qctx = QueryContext::new(state, ContractAddress::default());

    // Op program for `round.increment(1)`:
    //   idx [cached:false, push_path:true, path:[Key::Value(0u8)]]
    //   addi [immediate:1]
    //   ins  [cached:true, n:1]
    let ops: Vec<Op<ResultModeVerify>> = vec![
        Op::Idx {
            cached: false,
            push_path: true,
            path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),
        },
        Op::Addi { immediate: 1 },
        Op::Ins { cached: true, n: 1 },
    ];

    let results = qctx.query(&ops, None, &INITIAL_COST_MODEL).expect("query");

    // Decode the counter at path [0] from the resulting state.
    let new_state = results.context.state.get_ref();
    let cell = match new_state {
        StateValue::Array(arr) => arr.get(0).expect("first element"),
        _ => panic!("expected StateValue::Array"),
    };
    let counter_value = Counter::decode_from(cell).expect("decode counter");
    assert_eq!(counter_value, 1);
}
