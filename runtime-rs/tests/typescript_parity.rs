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

    let expected = transient_crypto::hash::hash_to_curve(&ValueReprAlignedValue(
        AlignedValue::from(s.clone()),
    ));

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
    let via_field_repr = transient_crypto::hash::hash_to_curve(&s);

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
        transient_crypto::hash::hash_to_curve(&bytes),
        "Bytes<32>"
    );

    let f = Fr::from(123_456_789u64);
    assert_eq!(
        hash_to_curve(f),
        transient_crypto::hash::hash_to_curve(&f),
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
    let expected = transient_crypto::hash::hash_to_curve(&ValueReprAlignedValue(
        AlignedValue::from(empty.clone()),
    ));
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
        new_cell_bounded_uint(70_000, 3).expect("70000 fits three bytes");
    assert!(matches!(ok, StateValue::Cell(_)));

    let err = new_cell_bounded_uint::<DefaultDB>(1 << 25, 3)
        .expect_err("2^25 needs four bytes and must not be written as three");
    assert!(
        err.to_string()
            .contains("does not fit the declared 3-byte width"),
        "message should say what did not fit, got: {err}"
    );
}

/// The round trip the two halves owe each other: what
/// `new_cell_bounded_uint` writes at a declared width,
/// `decode_bounded_uint` reads back at the same width and bound.
#[test]
fn bounded_uints_round_trip_through_the_ledger_encoding() {
    for value in [0u128, 1, 255, 256, 70_000] {
        let sv: StateValue<DefaultDB> =
            new_cell_bounded_uint(value, 3).expect("all fit three bytes");
        let StateValue::Cell(ref cell) = sv else {
            panic!("new_cell_bounded_uint must build a Cell");
        };
        assert_eq!(
            std_lib::decode_bounded_uint(cell, 3, 70_000).unwrap(),
            value
        );
    }
}
