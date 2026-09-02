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

//! Places where this crate and the TypeScript runtime have to compute the
//! same thing, pinned by tests.
//!
//! TypeScript is normative: it is what the deployed contracts and the chain
//! already agree on. So every test here asserts a Rust result against a
//! TypeScript rule, and where the two once disagreed the test says which
//! way the disagreement went.
//!
//! What makes this class of bug hard to see is that both sides look
//! reasonable in isolation. Each function here was written against a real
//! upstream primitive with the right-sounding name; it was the wrong one.
//! Nothing but a side-by-side reading finds that, which is why it gets its
//! own file rather than being scattered through the unit tests.

use midnight_compact_runtime::std_lib::OpaqueString;
use midnight_compact_runtime::*;

/// `hashToCurve` hashes the **field-aligned** representation:
///
/// ```ts
/// ocrt.hashToCurve(rtType.alignment(), rtType.toValue(x))
/// ```
///
/// which on the Rust side of that binding is
/// `hash_to_curve(&ValueReprAlignedValue(av))`. This asserts our wrapper
/// computes exactly that, for a `Compress`-aligned argument — the case
/// where it is not the same function as hashing the Rust `FieldRepr`.
#[test]
fn hash_to_curve_hashes_the_field_aligned_representation() {
    let s = OpaqueString::from("review-probe");

    let expected: JubjubPoint = transient_crypto::hash::hash_to_curve(&ValueReprAlignedValue(
        AlignedValue::from(s.clone()),
    ))
    .into();

    assert_eq!(hash_to_curve(s), expected);
}

/// The divergence itself, kept as a test so the fix cannot be undone by
/// someone "simplifying" the wrapper back to `hash_to_curve(&value)`.
///
/// Upstream expands a `Compress` atom as a single
/// `transient_commit(bytes, len)` field element. `<[u8] as FieldRepr>`
/// packs the raw bytes into 31-byte chunks instead. Two different
/// preimages, so two different curve points, for the same Compact value.
#[test]
fn the_field_repr_path_is_a_different_function_for_compress_aligned_types() {
    let s = OpaqueString::from("review-probe");

    let aligned = hash_to_curve(s.clone());
    let via_field_repr: JubjubPoint = transient_crypto::hash::hash_to_curve(&s).into();

    assert_ne!(
        aligned, via_field_repr,
        "if these ever coincide, the `Compress` expansion has changed and \
         the reason this wrapper exists needs re-checking"
    );
}

/// …and the corresponding negative result: for `Field`- and
/// `Bytes<N>`-aligned types the two paths agree, which is why the bug
/// survived. Everything the emitter passes to the hash builtins today is
/// one of these.
#[test]
fn the_two_paths_agree_for_field_and_bytes_aligned_types() {
    let bytes = [7u8; 32];
    assert_eq!(
        hash_to_curve(bytes),
        JubjubPoint::from(transient_crypto::hash::hash_to_curve(&bytes)),
        "Bytes<32>"
    );

    let f = Fr::from(123_456_789u64);
    assert_eq!(
        hash_to_curve(f),
        JubjubPoint::from(transient_crypto::hash::hash_to_curve(&f)),
        "Field"
    );
}

/// The empty string is the `Compress` special case upstream calls out
/// ("to make defaults work well"): it expands to a single zero field
/// element rather than a commitment. Worth pinning separately, because it
/// is the value an unwritten cell holds.
#[test]
fn hash_to_curve_handles_the_empty_opaque_string() {
    let empty = OpaqueString::from("");
    let expected: JubjubPoint = transient_crypto::hash::hash_to_curve(&ValueReprAlignedValue(
        AlignedValue::from(empty.clone()),
    ))
    .into();
    assert_eq!(hash_to_curve(empty), expected);
}

/// `new_cell_bounded_uint` writes a `Uint<L..U>` at the declared
/// byte-width. A value that does not fit is a domain violation in the
/// value, so it comes back as an error the caller can propagate — it used
/// to abort the process with `.expect`.
#[test]
fn writing_an_out_of_range_bounded_uint_is_an_error_not_a_panic() {
    // Uint<0..70000> — 17 bits, so 3 bytes on state.
    let ok: StateValue<DefaultDB> =
        new_cell_bounded_uint(70_000, 3, 70_000).expect("70000 fits three bytes");
    assert!(matches!(ok, StateValue::Cell(_)));

    let err = new_cell_bounded_uint::<DefaultDB>(1 << 25, 3, u32::MAX as u128)
        .expect_err("2^25 needs four bytes and must not be written as three");
    assert!(
        err.to_string()
            .contains("does not fit the declared 3-byte width"),
        "message should say what did not fit, got: {err}"
    );
}

/// The storage width is not the Compact domain. `Uint<0..100>` and
/// `Uint<0..255>` are both one byte, but `200` is a value of only the
/// second, and the normative `CompactTypeUnsignedInteger.toValue` rejects
/// it:
///
/// ```ts
/// if (value < 0n || value > this.maxValue) {
///   throw new CompactError(`expected UnsignedInteger[<=${this.maxValue}]`);
/// }
/// ```
///
/// The writer used to take only the width, so it accepted `200` for a
/// `Uint<0..100>` field — writing a cell that `decode_bounded_uint` would
/// then refuse to read back.
#[test]
fn writing_a_value_above_the_declared_maximum_is_rejected() {
    let err = new_cell_bounded_uint::<DefaultDB>(200, 1, 100)
        .expect_err("200 is outside Uint<0..100> however many bytes it needs");
    assert!(
        err.to_string().contains("expected UnsignedInteger[<=100]"),
        "message should name the declared bound, got: {err}"
    );

    // …and the same value at the same width is fine when the type admits it.
    assert!(new_cell_bounded_uint::<DefaultDB>(200, 1, 255).is_ok());
}

/// The round trip the two halves owe each other: what
/// `new_cell_bounded_uint` writes at a declared width and bound,
/// `decode_bounded_uint` reads back at the same width and bound.
#[test]
fn bounded_uints_round_trip_through_the_ledger_encoding() {
    for value in [0u128, 1, 255, 256, 70_000] {
        let sv: StateValue<DefaultDB> =
            new_cell_bounded_uint(value, 3, 70_000).expect("all fit Uint<0..70000>");
        let StateValue::Cell(ref cell) = sv else {
            panic!("new_cell_bounded_uint must build a Cell");
        };
        assert_eq!(
            std_lib::decode_bounded_uint(cell, 3, 70_000).unwrap(),
            value
        );
    }
}

/// The parity the second review asked for by name: `constructJubjubPoint(1, 1)`
/// is a value in TypeScript, so it must be a value here.
///
/// ```ts
/// // NOTE that it does not check that the coordinates represent a
/// // valid point on the Jubjub curve.
/// export function constructJubjubPoint(x: bigint, y: bigint): JubjubPoint {
///   return { x, y };
/// }
/// ```
#[test]
fn construct_jubjub_point_preserves_an_arbitrary_pair() {
    let p = std_lib::construct_jubjub_point(Fr::from(1u64), Fr::from(1u64));
    assert_eq!(std_lib::jubjub_point_x(p), Fr::from(1u64));
    assert_eq!(std_lib::jubjub_point_y(p), Fr::from(1u64));
}

/// The same for the read path. `CompactTypeJubjubPoint.fromValue` reads two
/// `field` atoms and returns them; a ledger cell holding an off-curve pair is
/// readable in TypeScript and must be readable here.
///
/// The old implementation did worse than reject such a cell. Upstream's
/// `EmbeddedGroupAffine::new` returns `None` only for a pair off the curve
/// entirely; for one *on* the curve but outside the prime-order subgroup —
/// `(1, 0)`, `(2, 3)` — it panics. Ledger state is untrusted input, so that
/// was a reachable abort, not just a divergence.
#[test]
fn decoding_a_jubjub_point_preserves_arbitrary_coordinates() {
    for (x, y) in [(0u64, 0u64), (1, 1), (1, 0), (2, 3)] {
        let av: AlignedValue = (Fr::from(x), Fr::from(y)).into();
        let p = std_lib::decode_jubjub_point(&av)
            .unwrap_or_else(|e| panic!("({x}, {y}) must decode, got {e}"));
        assert_eq!(std_lib::jubjub_point_x(p), Fr::from(x));
        assert_eq!(std_lib::jubjub_point_y(p), Fr::from(y));
    }
}

/// A `JubjubPoint` round-trips through the ledger encoding unchanged, on and
/// off the curve alike.
#[test]
fn jubjub_points_round_trip_through_a_ledger_cell() {
    for (x, y) in [(0u64, 1u64), (1, 1), (2, 3)] {
        let p = std_lib::construct_jubjub_point(Fr::from(x), Fr::from(y));
        let sv: StateValue<DefaultDB> = new_cell(p);
        let StateValue::Cell(ref cell) = sv else {
            panic!("new_cell must build a Cell");
        };
        assert_eq!(std_lib::decode_jubjub_point(cell).unwrap(), p);
    }
}
