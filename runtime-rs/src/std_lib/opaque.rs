// SPDX-License-Identifier: Apache-2.0
//
// `OpaqueString` — newtype around `String` carrying the trait impls
// the codegen + ledger machinery require.
//
// `String` itself can't impl `Aligned`, `FieldRepr`, etc. directly
// because Rust's orphan rules forbid it (the trait and the type are
// both upstream). election.compact's
// `ledger topic: Maybe<Opaque<"string">>` and similar fields need
// these impls, so we carry them on this newtype instead.

use super::field_repr::{bytes_field_size, vec_u8_from_field_repr};
use crate::{Aligned, Alignment, FieldRepr, FromFieldRepr, Fr, MemWrite, Value};

#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct OpaqueString(pub String);

impl From<String> for OpaqueString {
    fn from(s: String) -> Self {
        OpaqueString(s)
    }
}

impl From<&str> for OpaqueString {
    fn from(s: &str) -> Self {
        OpaqueString(s.to_string())
    }
}

impl Aligned for OpaqueString {
    fn alignment() -> Alignment {
        // Same shape as Vec<u8>: variable-length byte buffer (Compress atom).
        <Vec<u8> as Aligned>::alignment()
    }
}

impl FieldRepr for OpaqueString {
    fn field_repr<W: MemWrite<Fr>>(&self, writer: &mut W) {
        // UTF-8 byte serialisation; on-chain repr matches the byte stream
        // the TS path produces via Buffer.from(string).
        self.0.as_bytes().to_vec().field_repr(writer);
    }
    fn field_size(&self) -> usize {
        bytes_field_size(self.0.len())
    }
}

impl FromFieldRepr for OpaqueString {
    const FIELD_SIZE: usize = 0; // variable; surrounding ADT carries length
    fn from_field_repr(r: &[Fr]) -> Option<Self> {
        let bytes = vec_u8_from_field_repr(r)?;
        // Best-effort UTF-8 conversion; non-UTF-8 bytes round-trip as
        // replacement characters. For strict round-tripping users should
        // hold OpaqueString::from_lossless when we add it.
        Some(OpaqueString(String::from_utf8_lossy(&bytes).into_owned()))
    }
}

impl From<OpaqueString> for Value {
    fn from(s: OpaqueString) -> Value {
        Value::from(s.0.into_bytes())
    }
}
// `From<OpaqueString> for AlignedValue` comes for free via the
// upstream blanket `impl<T: DynAligned, Value: From<T>> From<T> for
// AlignedValue` — adding it explicitly causes an E0119 conflict.
