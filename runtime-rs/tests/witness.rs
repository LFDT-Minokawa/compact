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
// counter.compact has no witnesses, so we exercise NoWitnesses + the
// shape of WitnessContext (concrete type construction). Lifetime/HRTB
// exercise lands in M3 when tiny.compact is implemented.

use compact_runtime::*;

#[test]
fn no_witnesses_is_default_constructible() {
    #[allow(clippy::default_constructed_unit_structs)]
    let _ = NoWitnesses::default();
    let _ = NoWitnesses;
}

#[test]
fn witness_context_struct_resolves() {
    // For counter.compact-style contracts (no witnesses), the codegen
    // would never actually construct a WitnessContext. This test just
    // confirms the type is reachable for future contracts that need it.
    fn assert_type<T>() {}
    assert_type::<WitnessContext<(), ()>>();
}
