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
// `OpaqueString` — newtype around `String` carrying the trait impls
// the codegen + ledger machinery require.
//
// `String` itself can't impl `Aligned`, `FieldRepr`, etc. directly
// because Rust's orphan rules forbid it (the trait and the type are
// both upstream). election.compact's
// `ledger topic: Maybe<Opaque<"string">>` and similar fields need
// these impls, so we carry them on this newtype instead.

use super::field_repr::{bytes_field_size, vec_u8_from_field_repr};
use crate::{Aligned, Alignment, BinaryHashRepr, FieldRepr, Fr, FromFieldRepr, MemWrite, Value};

/// Newtype around `String` carrying the [`Aligned`], [`FieldRepr`],
/// [`FromFieldRepr`] and `From<_> for Value` impls that the codegen
/// requires. Wrap any user-defined `String` field in this type before
/// passing it through generated contract code.
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

impl BinaryHashRepr for OpaqueString {
    fn binary_repr<W: MemWrite<u8>>(&self, writer: &mut W) {
        // Raw UTF-8 bytes — same shape upstream `BinaryHashRepr for [u8]`
        // uses, which `Vec<u8>::binary_repr` invokes through `Deref`.
        self.0.as_bytes().binary_repr(writer);
    }
    fn binary_len(&self) -> usize {
        self.0.as_bytes().len()
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
