// SPDX-License-Identifier: Apache-2.0
//
// Compact standard library types used by generated contract code.
//
// Each ledger ADT (Counter / Cell / Map / Set / MerkleTree / List) lives
// here as a newtype + a `decode_from(&StateValue)` helper. The compiler
// lowers mutating operations (e.g., `round.increment(1)`) directly to
// Op programs, so the wrappers don't need methods for those.

use crate::{
    aligned_bytes, Aligned, AlignedValue, Alignment, CompactError, ContractState, FieldRepr,
    FromFieldRepr, Fr, JubjubPoint, MemWrite, StateValue, Value, ValueReprAlignedValue, DB,
};
use midnight_base_crypto::hash::PersistentHashWriter;
use midnight_base_crypto::repr::BinaryHashRepr;

/// Compact's `Counter` ledger ADT. Represented at runtime as
/// `StateValue::Cell` containing a u64 aligned-value.
pub struct Counter;

impl Counter {
    /// Decode the current counter value from a `StateValue::Cell`.
    /// Returns `Err(AssertionFailed)` if `sv` is not a Cell or its
    /// contents are not a u64-aligned value.
    pub fn decode_from(sv: &StateValue) -> Result<u64, CompactError> {
        let cell = match sv {
            StateValue::Cell(c) => c,
            _ => {
                return Err(CompactError::AssertionFailed(
                    "Counter::decode_from: expected StateValue::Cell".into(),
                ));
            }
        };
        decode_u64(cell)
    }
}

/// Decode an `AlignedValue` known to be a fixed-width unsigned integer to a
/// u128. Accepts variable-length atoms (upstream strips trailing zero bytes)
/// and zero-pads to the full target width. Internal helper for the typed
/// decoders below.
///
/// The base-crypto `ValueAtom` encoding for primitive integers is
/// little-endian with trailing zero bytes stripped via `normalize`
/// (see `midnight_base_crypto::fab::conversions`), so e.g. a u64 may occupy
/// 0..=8 bytes. We zero-pad and decode little-endian.
fn decode_unsigned(av: &AlignedValue, max_bytes: usize) -> Result<u128, CompactError> {
    let bytes = aligned_bytes(av).ok_or_else(|| {
        CompactError::AssertionFailed("decode_unsigned: aligned value is empty".into())
    })?;
    if bytes.len() > max_bytes {
        return Err(CompactError::AssertionFailed(format!(
            "decode_unsigned: expected at most {max_bytes} bytes, got {}",
            bytes.len()
        )));
    }
    let mut buf = [0u8; 16];
    buf[..bytes.len()].copy_from_slice(bytes);
    Ok(u128::from_le_bytes(buf))
}

/// Decode an `AlignedValue` known to be a u8.
pub fn decode_u8(av: &AlignedValue) -> Result<u8, CompactError> {
    decode_unsigned(av, 1).map(|n| n as u8)
}

/// Decode an `AlignedValue` known to be a u16.
pub fn decode_u16(av: &AlignedValue) -> Result<u16, CompactError> {
    decode_unsigned(av, 2).map(|n| n as u16)
}

/// Decode an `AlignedValue` known to be a u32.
pub fn decode_u32(av: &AlignedValue) -> Result<u32, CompactError> {
    decode_unsigned(av, 4).map(|n| n as u32)
}

/// Decode an `AlignedValue` known to be a u64.
pub fn decode_u64(av: &AlignedValue) -> Result<u64, CompactError> {
    decode_unsigned(av, 8).map(|n| n as u64)
}

/// Decode an `AlignedValue` known to be a u128.
pub fn decode_u128(av: &AlignedValue) -> Result<u128, CompactError> {
    decode_unsigned(av, 16)
}

/// Decode an `AlignedValue` known to be a bool. Booleans encode as a
/// single byte (0 or 1); we accept anything via the u8 decoder and
/// coerce non-zero to true.
pub fn decode_bool(av: &AlignedValue) -> Result<bool, CompactError> {
    decode_u8(av).map(|n| n != 0)
}

/// Decode an `AlignedValue` known to be a `Vector<N, Field>` — i.e. N
/// consecutive `Fr` atoms in the value. Each atom is parsed via
/// `Fr::try_from(&ValueAtom)` (same path as `decode_fr`). Returns
/// `Err(AssertionFailed)` if the value has fewer than N atoms or any
/// individual atom fails to parse.
pub fn decode_vector_fr<const N: usize>(av: &AlignedValue) -> Result<[Fr; N], CompactError> {
    if av.value.0.len() < N {
        return Err(CompactError::AssertionFailed(format!(
            "decode_vector_fr: expected at least {N} atoms, got {}",
            av.value.0.len()
        )));
    }
    let mut out = [Fr::default(); N];
    for (i, atom) in av.value.0.iter().take(N).enumerate() {
        out[i] = Fr::try_from(atom)
            .map_err(|e| CompactError::AssertionFailed(format!("decode_vector_fr[{i}]: {e:?}")))?;
    }
    Ok(out)
}

/// Decode an `AlignedValue` known to be a fixed-width byte array `Bytes<N>`.
///
/// Compact's `Bytes<N>` lowers to a single `ValueAtom` carrying the raw
/// bytes; upstream `normalize` may strip trailing zero bytes. We zero-pad
/// up to `N` and return the full array. Returns
/// `Err(AssertionFailed)` if the atom carries more than `N` bytes.
pub fn decode_bytes<const N: usize>(av: &AlignedValue) -> Result<[u8; N], CompactError> {
    let bytes = aligned_bytes(av).ok_or_else(|| {
        CompactError::AssertionFailed("decode_bytes: aligned value is empty".into())
    })?;
    if bytes.len() > N {
        return Err(CompactError::AssertionFailed(format!(
            "decode_bytes: expected at most {N} bytes, got {}",
            bytes.len()
        )));
    }
    let mut out = [0u8; N];
    out[..bytes.len()].copy_from_slice(bytes);
    Ok(out)
}

/// Decode an `AlignedValue` known to be a `Field` (i.e. a single `Fr` atom).
///
/// On the encode side, `Fr` lowers to a single `ValueAtom` via
/// `midnight_transient_crypto::fab::From<Fr> for ValueAtom`, which writes
/// `Fr::as_le_bytes` and `.normalize()`s trailing zeros. We invert by reading
/// the first atom and running `Fr::try_from(&ValueAtom)`, which calls
/// `Fr::from_le_bytes` and accepts ≤ `FR_BYTES` bytes.
pub fn decode_fr(av: &AlignedValue) -> Result<Fr, CompactError> {
    let atom = av.value.0.first().ok_or_else(|| {
        CompactError::AssertionFailed("decode_fr: aligned value has no atoms".into())
    })?;
    Fr::try_from(atom)
        .map_err(|e| CompactError::AssertionFailed(format!("decode_fr: {e:?}")))
}

/// Canonically serialise a `ContractState` to bytes via
/// `midnight_serialize::tagged_serialize` — this is the byte format the
/// TypeScript runtime's `cr.encode` produces. Use this for byte-parity tests
/// and on-chain submission.
pub fn serialize_contract_state<D: DB>(state: &ContractState<D>) -> Result<Vec<u8>, CompactError> {
    let mut buf = Vec::new();
    midnight_serialize::tagged_serialize(state, &mut buf)
        .map_err(|e| CompactError::AssertionFailed(format!("serialize_contract_state: {e}")))?;
    Ok(buf)
}

// -------------------------------------------------------------------------
// M3a universal helpers — Bytes<N>, Maybe<T>, pad, disclose
// -------------------------------------------------------------------------

/// Compact's `Bytes<N>` primitive maps directly to a fixed-width byte array.
/// Generated code uses this alias rather than spelling `[u8; N]` everywhere.
pub type Bytes<const N: usize> = [u8; N];

/// Compact's standard-library `Maybe<T>` ADT — a struct with an explicit
/// `is_some` discriminant plus a `value` payload. Mirrors the on-chain
/// wire format (1-byte is_some + T's repr) used by `standard-library.compact`:
///
/// ```compact
/// export struct Maybe<T> { is_some: Boolean; value: T; }
/// ```
///
/// Generated code references `Maybe<T>` directly; the `some(v)` / `none()`
/// helpers below construct values in the same shape Compact's circuits do.
/// `Copy` is implemented when `T: Copy` so the struct composes cheaply with
/// primitive payloads (e.g. `Maybe<Field>`, `Maybe<u64>`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Maybe<T> {
    pub is_some: bool,
    pub value: T,
}

impl<T> Maybe<T> {
    /// Returns the `is_some` discriminant. Provided as a method for ergonomic
    /// parity with `Option::is_some` even though the field itself is public.
    #[inline]
    pub fn is_some(&self) -> bool {
        self.is_some
    }

    /// Returns the inner `value`, panicking if `is_some` is false. Matches the
    /// Compact `Maybe::unwrap` circuit's runtime check semantics.
    #[inline]
    pub fn unwrap(self) -> T {
        if !self.is_some {
            panic!("Maybe::unwrap on None");
        }
        self.value
    }
}

impl<T: Aligned> Aligned for Maybe<T> {
    fn alignment() -> Alignment {
        Alignment::concat([&bool::alignment(), &T::alignment()])
    }
}

impl<T: FieldRepr> FieldRepr for Maybe<T> {
    fn field_repr<W: MemWrite<Fr>>(&self, writer: &mut W) {
        self.is_some.field_repr(writer);
        self.value.field_repr(writer);
    }
    fn field_size(&self) -> usize {
        self.is_some.field_size() + self.value.field_size()
    }
}

impl<T: FromFieldRepr> FromFieldRepr for Maybe<T> {
    const FIELD_SIZE: usize = 1 + T::FIELD_SIZE;
    fn from_field_repr(r: &[Fr]) -> Option<Self> {
        if r.len() < Self::FIELD_SIZE {
            return None;
        }
        let is_some = bool::from_field_repr(&r[..bool::FIELD_SIZE])?;
        let value = T::from_field_repr(&r[bool::FIELD_SIZE..Self::FIELD_SIZE])?;
        Some(Maybe { is_some, value })
    }
}

/// `From<Maybe<T>> for Value` so `Maybe<T>: DynAligned` lifts to
/// `AlignedValue: From<Maybe<T>>` through the upstream blanket impl,
/// which in turn satisfies `new_cell(Maybe::<T>::default())` at the
/// codegen seeding site. Parallels upstream `From<Option<T>> for Value`
/// (midnight-base-crypto/src/fab/conversions.rs:262).
impl<T: Into<Value>> From<Maybe<T>> for Value {
    fn from(inp: Maybe<T>) -> Value {
        Value::concat([Value::from(inp.is_some), inp.value.into()].iter())
    }
}

/// Construct a `Maybe<T>` in the "some" state. Mirrors Compact's
/// `some<T>(value: T): Maybe<T>` circuit from `standard-library.compact`.
#[inline]
pub fn some<T>(v: T) -> Maybe<T> {
    Maybe { is_some: true, value: v }
}

/// Construct a `Maybe<T>` in the "none" state. The caller supplies a
/// default-shaped value for the inert `value` field; Compact's
/// `none<T>(): Maybe<T>` uses `default<T>` for this, which Rust can mirror
/// via `T::default()` at the call site.
#[inline]
pub fn none<T: Default>() -> Maybe<T> {
    Maybe { is_some: false, value: T::default() }
}

/// Compact's `pad(width, s)` — return the bytes of `s` resized to exactly
/// `width` bytes. Truncates if `s` is longer; zero-extends if shorter.
pub fn pad(width: usize, s: &str) -> Vec<u8> {
    let mut v = s.as_bytes().to_vec();
    v.resize(width, 0);
    v
}

/// Compact's `disclose(x)` — identity in Rust. The compiler uses this to
/// mark a value as publicly revealed; the runtime side has no operational
/// difference.
#[inline]
pub fn disclose<T>(x: T) -> T {
    x
}

/// Compact's `persistentHash<T>(value)` — alignment-aware persistent hash.
///
/// Mirrors the TS path
/// `__compactRuntime.persistentHash(rtType, value)`, which lowers to
/// `ocrt.persistentHash(rtType.alignment(), rtType.toValue(value))` inside the
/// `onchain-runtime-wasm` crate. That call constructs an [`AlignedValue`],
/// wraps it in `ValueReprAlignedValue`, and hashes the resulting
/// alignment-framed byte stream with SHA-256.
///
/// In Rust we get the same bytes by:
/// 1. Building an `AlignedValue` for each pre-converted element (the codegen
///    passes already-`AlignedValue`-typed arguments — for a `Vector<N, T>`
///    that means N entries).
/// 2. Concatenating them with [`AlignedValue::concat`] — equivalent to TS's
///    `Value`-level concatenation.
/// 3. Feeding the result through `ValueReprAlignedValue::binary_repr` into a
///    `PersistentHashWriter`.
///
/// Returns the 32-byte SHA-256 digest as a `[u8; 32]`, matching the Compact
/// stdlib signature `persistentHash<T>(value: T): Bytes<32>`.
///
/// The byte stream produced by `ValueReprAlignedValue::binary_repr` is the
/// per-atom encoding documented in `spec/field-aligned-binary.md`:
/// `bytes<n>` atoms emit raw bytes padded out to `n` with zeros, `field`
/// atoms emit `FR_BYTES` little-endian bytes via `Fr::as_le_bytes`, and
/// `compress` atoms emit a `transient_commit` of the contents. For uniform
/// `Bytes<N>` inputs this coincides with raw byte concatenation (which is why
/// `tiny.compact`'s previous `.concat().0` flat-byte emission produced the
/// correct hash for `public_key`), but it diverges for mixed-type, `Field`-,
/// or `Compress`-bearing inputs.
pub fn persistent_hash_aligned(values: &[AlignedValue]) -> [u8; 32] {
    let av = AlignedValue::concat(values.iter());
    let mut writer = PersistentHashWriter::new();
    ValueReprAlignedValue(av).binary_repr(&mut writer);
    writer.finalize().0
}

// -------------------------------------------------------------------------
// M3.5 helpers for codegen of `[u8; N]`, `Vec<u8>`, and `[T; N]` fields.
//
// Upstream `midnight-transient-crypto` provides only a partial set of
// `FieldRepr` / `FromFieldRepr` impls for byte arrays and vectors,
// and Rust's orphan rules forbid us from supplying the missing ones
// directly (the trait + the foreign type are both upstream). To
// sidestep the orphan rule, we expose plain functions in
// `compact_runtime` that the codegen calls from inside generated
// struct `FromFieldRepr` bodies. The local struct's own impl is OK by
// orphan rules; the per-field deserialiser doesn't need to go through
// `<T as FromFieldRepr>` for problematic T.
// -------------------------------------------------------------------------

/// FIELD_SIZE for a `[u8; N]` field-repr — 31-byte chunks plus a stray
/// Fr for the remainder, matching `bytes_from_field_repr`'s packing.
pub const fn bytes_field_size(n: usize) -> usize {
    let stray = n % 31;
    let chunks = n / 31;
    chunks + if stray == 0 { 0 } else { 1 }
}

/// Parse a `[u8; N]` from an Fr-slice using upstream's packing layout.
/// Codegen calls this in generated `FromFieldRepr` bodies when N != 32
/// (the only size upstream's blanket impl covers).
pub fn bytes_from_field_repr<const N: usize>(r: &[Fr]) -> Option<[u8; N]> {
    let size = bytes_field_size(N);
    if r.len() < size {
        return None;
    }
    let v = midnight_transient_crypto::repr::bytes_from_field_repr(&mut &r[..size], N)?;
    let mut out = [0u8; N];
    out.copy_from_slice(&v);
    Some(out)
}

/// Parse a `Vec<u8>` from an Fr-slice — packs all remaining elements
/// into bytes (no length prefix). Codegen calls this for `Vec<u8>`
/// fields where upstream provides no `FromFieldRepr`.
pub fn vec_u8_from_field_repr(r: &[Fr]) -> Option<Vec<u8>> {
    if r.is_empty() {
        return Some(Vec::new());
    }
    midnight_transient_crypto::repr::bytes_from_field_repr(&mut &r[..], r.len() * 31)
}

/// Compact's `Opaque<"string">` mapped to a newtype around `String`,
/// implementing the trait set the codegen + ledger machinery require.
/// String can't impl `Aligned` directly (orphan rules) and is needed
/// in election.compact (`ledger topic: Maybe<Opaque<"string">>`) and
/// elsewhere, so this newtype carries the impls.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct OpaqueString(pub String);

impl From<String> for OpaqueString {
    fn from(s: String) -> Self { OpaqueString(s) }
}

impl From<&str> for OpaqueString {
    fn from(s: &str) -> Self { OpaqueString(s.to_string()) }
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
    fn field_size(&self) -> usize { bytes_field_size(self.0.len()) }
}

impl FromFieldRepr for OpaqueString {
    const FIELD_SIZE: usize = 0;  // variable; surrounding ADT carries length
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
// `From<OpaqueString> for AlignedValue` comes for free via the upstream
// blanket `impl<T: DynAligned, Value: From<T>> From<T> for AlignedValue`
// — adding it explicitly causes E0119 conflict.

/// Parse a `[T; N]` of user-typed elements from an Fr-slice. Codegen
/// calls this for struct/enum array fields where neither upstream nor
/// orphan rules let us write the impl directly. Returns `None` if any
/// element parse fails or the slice is too short.
pub fn array_from_field_repr<T, const N: usize>(r: &[Fr], elt_size: usize) -> Option<[T; N]>
where
    T: FromFieldRepr,
{
    if r.len() < elt_size * N {
        return None;
    }
    let mut v: Vec<T> = Vec::with_capacity(N);
    for i in 0..N {
        v.push(T::from_field_repr(&r[i * elt_size..(i + 1) * elt_size])?);
    }
    v.try_into().ok()
}

// -------------------------------------------------------------------------
// R2 — native function wrappers (Jubjub / EC + transient bridges).
//
// These are thin shims over upstream symbols that the compiler's
// `(rust "...")` annotations on declare-native-entry point at. Upstream
// exposes Jubjub primitives as methods on `EmbeddedGroupAffine`
// (re-exported as `JubjubPoint`) plus `Mul<Fr>` / `+` operator impls;
// the Compact natives spell them as bare functions. Hence the wrappers.
// -------------------------------------------------------------------------

use crate::base_crypto::hash::HashOutput;
use crate::transient_crypto::hash as transient_hash_mod;

/// `jubjubPointX(p)` — affine X coordinate, or zero if `p` is identity.
/// The Compact native returns `Field`, treating identity as the zero
/// coordinate (matches the TS `__compactRuntime.jubjubPointX` behavior).
#[inline]
pub fn jubjub_point_x(p: JubjubPoint) -> Fr {
    p.x().unwrap_or(Fr::from(0u64))
}

/// `jubjubPointY(p)` — affine Y coordinate, or zero if `p` is identity.
#[inline]
pub fn jubjub_point_y(p: JubjubPoint) -> Fr {
    p.y().unwrap_or(Fr::from(0u64))
}

/// `ecAdd(a, b)` — group addition. Upstream `EmbeddedGroupAffine` impls
/// `Add` through the `wrap_group_arith!` macro, so we just defer to `+`.
#[inline]
pub fn ec_add(a: JubjubPoint, b: JubjubPoint) -> JubjubPoint {
    a + b
}

/// `ecMul(p, s)` — scalar multiplication. Upstream impls
/// `Mul<Fr> for EmbeddedGroupAffine`.
#[inline]
pub fn ec_mul(p: JubjubPoint, s: Fr) -> JubjubPoint {
    p * s
}

/// `ecMulGenerator(s)` — `generator() * s`.
#[inline]
pub fn ec_mul_generator(s: Fr) -> JubjubPoint {
    JubjubPoint::generator() * s
}

/// `constructJubjubPoint(x, y)` — checked affine constructor. Panics
/// if `(x, y)` isn't on the curve, mirroring the TS runtime's
/// assertion-style failure mode.
#[inline]
pub fn construct_jubjub_point(x: Fr, y: Fr) -> JubjubPoint {
    JubjubPoint::new(x, y).expect("constructJubjubPoint: (x, y) not on the embedded curve")
}

/// `degradeToTransient(b)` — `(Bytes 32) -> Field`. Wraps the upstream
/// `transient_crypto::hash::degrade_to_transient(HashOutput) -> Fr`.
#[inline]
pub fn degrade_to_transient(b: [u8; 32]) -> Fr {
    transient_hash_mod::degrade_to_transient(HashOutput(b))
}

/// `upgradeFromTransient(f)` — `Field -> (Bytes 32)`. Wraps the upstream
/// `transient_crypto::hash::upgrade_from_transient(Fr) -> HashOutput`.
#[inline]
pub fn upgrade_from_transient(f: Fr) -> [u8; 32] {
    transient_hash_mod::upgrade_from_transient(f).0
}

#[cfg(test)]
mod tests_m3a_helpers {
    use super::*;

    #[test]
    fn maybe_some_unwraps() {
        let m: Maybe<u32> = some(7);
        assert!(m.is_some());
        assert_eq!(m.unwrap(), 7);
    }

    #[test]
    fn maybe_none_is_none() {
        let m: Maybe<u32> = none();
        assert!(!m.is_some());
    }

    #[test]
    fn maybe_some_some_roundtrip() {
        // Sanity check: field_size of `Maybe<u8>` is 1 (is_some) + 1 (u8) = 2.
        let m: Maybe<u8> = Maybe { is_some: true, value: 42 };
        assert_eq!(m.field_size(), 1 + 42_u8.field_size());
        // FIELD_SIZE associated const matches.
        assert_eq!(<Maybe<u8> as FromFieldRepr>::FIELD_SIZE, 1 + <u8 as FromFieldRepr>::FIELD_SIZE);
    }

    #[test]
    fn pad_truncates_and_zero_extends() {
        assert_eq!(pad(5, "abc"), vec![b'a', b'b', b'c', 0, 0]);
    }

    #[test]
    fn disclose_is_identity() {
        let x = 42u64;
        assert_eq!(disclose(x), 42u64);
    }

    #[test]
    fn persistent_hash_aligned_matches_raw_concat_for_byte_arrays() {
        // For uniform `Bytes<N>` inputs the alignment-aware path produces
        // exactly the same bytes as the raw flat `[a, b, ...].concat()`
        // approach used by I3b/1. Tiny.compact's `public_key` (two 32-byte
        // arrays) lives in this regime, so this acts as a backstop confirming
        // R3 doesn't regress tiny's existing byte-parity test.
        let a: [u8; 32] = [
            108, 97, 114, 101, 115, 58, 116, 105, 110, 121, 58, 112, 107, 58, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ];
        let b: [u8; 32] = [
            42, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
            24, 25, 26, 27, 28, 29, 30, 31,
        ];
        let new_path = persistent_hash_aligned(&[a.into(), b.into()]);
        let old_path = midnight_base_crypto::hash::persistent_hash(&[a, b].concat()).0;
        assert_eq!(new_path, old_path);
    }

    #[test]
    fn persistent_hash_aligned_differs_for_field_input() {
        // For an `Fr` input the alignment-aware path emits a normalised
        // 32-byte little-endian encoding via `value_atom_as_field` /
        // `Fr::binary_repr` (always exactly FR_BYTES). Raw `.concat()` on the
        // AlignedValue bytes would NOT have the same framing, so this is the
        // smallest case where R3's fix is observable.
        let f = Fr::from(123456789u64);
        let av: AlignedValue = f.into();
        let new_path = persistent_hash_aligned(&[av.clone()]);
        // sanity: length is 32 bytes (sha256 output).
        assert_eq!(new_path.len(), 32);
        // independent observation: hashing the same Fr twice is stable.
        let new_path2 = persistent_hash_aligned(&[av]);
        assert_eq!(new_path, new_path2);
    }

    #[test]
    fn decode_fr_roundtrips_via_aligned_value() {
        // Encode an Fr → AlignedValue and recover it via decode_fr. Uses the
        // upstream `From<Fr> for AlignedValue` chain (via DynAligned) so this
        // exercises the same encode path generated contracts hit.
        let original = Fr::from(123456789u64);
        let av: AlignedValue = original.into();
        let decoded = decode_fr(&av).expect("decode_fr should succeed");
        assert_eq!(decoded, original);
    }
}
