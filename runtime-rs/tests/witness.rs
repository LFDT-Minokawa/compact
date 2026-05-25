// SPDX-License-Identifier: Apache-2.0
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
