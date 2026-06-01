// SPDX-License-Identifier: Apache-2.0
//
// zerocash.compact byte-parity tests (F1.1 + F1.2 of the M3.5 plan).
//
// F1.1: drives initial_state() and compares the serialized ContractState to
// the TS reference fixture.
// F1.2: extends with zerocash_mint() and (when supported) spend(), each
// asserted against the TS reference at the same step.
//
// Exercises ADT seeding for three ledger fields:
//   - nullifiers: Set<nullifier>          (seeds as empty Map)
//   - commitments: HistoricMerkleTree<32> (seeds as 3-slot array)
//   - ciphertexts: Opaque<"Uint8Array">   (seeds as cell of Vec<u8>::new())

use compact_contract_zerocash::{
    coin_info, commitment, zk_public_key, zk_secret_key, Contract, Ledger, Nonce, Witnesses,
    opening,
};
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use std::cell::RefCell;
use tests_e2e_rust::{CapturedMerklePath, ZerocashStepSnapshot, ZerocashTsReferenceState};

// Fixed deterministic witness payloads — must match capture-zerocash.mjs
// byte for byte, so that both drivers fold the same persistent_hash
// arguments and produce byte-identical ContractStates.
const FIXED_SK: [u8; 32] = [1u8; 32];
// FIXED_PK is derived as `persistentHash<Bytes<32>>(FIXED_SK)`, i.e.
// the same value `derive_zk_public_key(FIXED_SK)` would compute. This
// keeps mint and spend coherent: both fold the same commitment into
// the on-chain merkle tree. The TS capture and the Rust test both
// hardcode this — kept here as bytes rather than recomputing to avoid
// pulling in the field/hash plumbing at test time.
const FIXED_PK: [u8; 32] = [
    0x72, 0xcd, 0x6e, 0x84, 0x22, 0xc4, 0x07, 0xfb,
    0x6d, 0x09, 0x86, 0x90, 0xf1, 0x13, 0x0b, 0x7d,
    0xed, 0x7e, 0xc2, 0xf7, 0xf5, 0xe1, 0xd3, 0x0b,
    0xd9, 0xd5, 0x21, 0xf0, 0x15, 0x36, 0x37, 0x93,
];
const FIXED_NONCE: [u8; 32] = [3u8; 32];
const FIXED_OPENING: [u8; 32] = [4u8; 32];
const FIXED_CIPHERTEXT: [u8; 3] = [10u8, 11u8, 12u8];

thread_local! {
    /// The captured spend `path_of` reply. Set by the test before
    /// driving `spend()`; the witness consults it to return the same
    /// MerklePath bytes the TS driver did. None outside of spend.
    static SPEND_PATH: RefCell<Option<CapturedMerklePath>> = const { RefCell::new(None) };
}

fn fixed_coin_info() -> coin_info {
    coin_info {
        nonce: Nonce { bytes: FIXED_NONCE },
        opening: opening { bytes: FIXED_OPENING },
    }
}

/// Deterministic Witnesses impl matching the TS driver in
/// capture-zerocash.mjs. For the `path_of` stub we still hand back a
/// default (empty) path — spend() asserts the path's root matches the
/// historic merkle tree, which won't hold with a stub path, so the
/// spend step in the fixture records an `error` rather than a stateHex.
struct ZerocashWitnesses;

impl Witnesses<()> for ZerocashWitnesses {
    fn private_zk_secret_key<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
    ) -> ((), zk_secret_key) {
        ((), zk_secret_key { bytes: FIXED_SK })
    }
    fn private_remove_coin<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _coin: coin_info,
    ) -> ((), ()) {
        ((), ())
    }
    fn private_zk_public_key<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
    ) -> ((), zk_public_key) {
        ((), zk_public_key { bytes: FIXED_PK })
    }
    fn private_add_coin<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _coin: coin_info,
    ) -> ((), ()) {
        ((), ())
    }
    fn context_path_of<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        cm: commitment,
    ) -> ((), compact_runtime::MerklePath<commitment>) {
        // If the test has stashed a captured path (spend-only), replay
        // it. Otherwise return a default empty path. The Rust spend
        // body unwraps this into the same byte-for-byte MerklePath the
        // TS driver pushed into its private transcript.
        let path = SPEND_PATH.with(|cell| cell.borrow().clone());
        match path {
            Some(p) => (
                (),
                compact_runtime::MerklePath {
                    leaf: commitment { bytes: p.leaf_bytes() },
                    path: p.into_entries(),
                },
            ),
            None => {
                let _ = cm; // suppress unused warning
                ((), compact_runtime::default_merkle_path::<commitment>())
            }
        }
    }
    fn context_new_coin_info<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
    ) -> ((), coin_info) {
        ((), fixed_coin_info())
    }
    fn context_encrypt<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _pk: Vec<u8>,
        _coin: coin_info,
    ) -> ((), Vec<u8>) {
        ((), FIXED_CIPHERTEXT.to_vec())
    }
}

fn fixture() -> ZerocashTsReferenceState {
    ZerocashTsReferenceState::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/zerocash-ts-state.json"
    ))
}

fn ctor_ctx() -> ConstructorContext<()> {
    ConstructorContext {
        initial_private_state: (),
        empty_zswap_local_state: ZswapLocalState::default(),
        cost_model: INITIAL_COST_MODEL.clone(),
        gas_limit: None,
    }
}

/// Build a ContractState envelope around a freshly minted ChargedState,
/// matching the operations / authority / balance that the TS initialState()
/// path produces. zerocash exports two circuits: `spend` and `zerocash_mint`.
fn make_envelope(
    data: ChargedState<midnight_storage::DefaultDB>,
) -> ContractState<midnight_storage::DefaultDB> {
    let mut operations: HashMap<EntryPointBuf, ContractOperation, midnight_storage::DefaultDB> =
        HashMap::new();
    operations = operations.insert(
        EntryPointBuf(b"zerocash_mint".to_vec()),
        ContractOperation::new(None),
    );
    operations = operations.insert(
        EntryPointBuf(b"spend".to_vec()),
        ContractOperation::new(None),
    );
    ContractState {
        data,
        operations,
        maintenance_authority: ContractMaintenanceAuthority::default(),
        balance: Default::default(),
    }
}

fn assert_step_bytes_eq(
    label: &str,
    state: &ContractState<midnight_storage::DefaultDB>,
    expected: &ZerocashStepSnapshot,
) {
    let mut buf = Vec::new();
    tagged_serialize(state, &mut buf).expect("tagged_serialize");
    let ts_bytes = expected.state_bytes();
    assert_eq!(
        buf,
        ts_bytes,
        "[{label}] Rust state bytes differ from TS reference\n\nRust ({} B): {}\n\nTS   ({} B): {}",
        buf.len(),
        hex::encode(&buf),
        ts_bytes.len(),
        hex::encode(&ts_bytes),
    );
}

#[test]
fn zerocash_init_byte_parity() {
    let ts_ref = fixture();
    let contract: Contract<(), ZerocashWitnesses> = Contract::new(ZerocashWitnesses);
    let result = contract.initial_state(ctor_ctx()).expect("initial_state");

    let envelope = make_envelope(result.current_contract_state.clone());
    assert_step_bytes_eq("init", &envelope, &ts_ref.after_init);
}

#[test]
fn zerocash_init_then_mint_byte_parity() {
    let ts_ref = fixture();
    let after_mint = ts_ref
        .after_mint
        .as_ref()
        .expect("TS fixture missing afterMint snapshot");
    if after_mint.state_hex.is_none() {
        panic!(
            "TS driver errored on zerocash_mint: {:?}",
            after_mint.error.as_deref().unwrap_or("(no error message)")
        );
    }
    let contract: Contract<(), ZerocashWitnesses> = Contract::new(ZerocashWitnesses);
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let mint = contract.zerocash_mint(circ_ctx).expect("zerocash_mint");
    let envelope = make_envelope(mint.context.current_query_context.state.clone());
    assert_step_bytes_eq("mint", &envelope, after_mint);
}

/// spend() asserts that the supplied MerklePath's root matches a root
/// recorded in the HistoricMerkleTree. We replay the same path the TS
/// driver computed (capture-zerocash.mjs extracts it from the
/// post-mint BoundedMerkleTree via `pathForLeaf`) by stashing it into
/// the thread-local SPEND_PATH before calling `spend()` — the
/// `context_path_of` witness then returns it instead of the default
/// empty placeholder.
///
/// FIXED_PK is also tweaked from the original `[2u8; 32]` placeholder
/// to `persistentHash<Bytes<32>>(FIXED_SK)`. That way mint inserts a
/// commitment under the same pk that `derive_zk_public_key(source_sk)`
/// produces during spend — so the lookup hits the inserted leaf.
#[test]
fn zerocash_init_mint_spend_byte_parity() {
    let ts_ref = fixture();
    let after_spend = ts_ref
        .after_spend
        .as_ref()
        .expect("TS fixture missing afterSpend snapshot");
    if after_spend.state_hex.is_none() {
        panic!(
            "TS driver errored on spend: {:?}",
            after_spend.error.as_deref().unwrap_or("(no error message)")
        );
    }
    let spend_path = ts_ref
        .spend_path
        .as_ref()
        .expect("TS fixture missing spendPath — capture-zerocash.mjs must emit it");

    let contract: Contract<(), ZerocashWitnesses> = Contract::new(ZerocashWitnesses);
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let mint = contract.zerocash_mint(circ_ctx).expect("zerocash_mint");

    let dest_pk = compact_contract_zerocash::public_key {
        zk: zk_public_key { bytes: [5u8; 32] },
        encryption: vec![6u8; 32],
    };
    let input_coin = fixed_coin_info();

    // Stash the captured path for the witness; clear it after spend
    // so other tests aren't accidentally affected.
    SPEND_PATH.with(|cell| *cell.borrow_mut() = Some(spend_path.clone()));
    let spend_result = contract.spend(mint.context, dest_pk, input_coin);
    SPEND_PATH.with(|cell| *cell.borrow_mut() = None);

    let spend = spend_result.expect("spend");
    let envelope = make_envelope(spend.context.current_query_context.state.clone());
    assert_step_bytes_eq("spend", &envelope, after_spend);
}

/// Drift detector for the hardcoded FIXED_PK constant.
///
/// FIXED_PK is the byte image of `persistentHash<Bytes<32>>(FIXED_SK)`
/// computed by the TS capture driver and pasted into this file. The
/// byte-parity tests rely on it matching what the Rust contract folds
/// into the commitment tree via `pure_circuits::derive_zk_public_key`.
///
/// If anyone tweaks `FIXED_SK` (or the underlying persistent_hash
/// semantics shift), the hardcoded constant becomes stale and the
/// byte-parity tests would fail with an opaque hex mismatch deep
/// inside a ContractState dump. This test re-derives the value via
/// the same Rust hash primitive the contract uses
/// (`persistent_hash_aligned` with a single `AlignedValue::from(sk)`
/// argument — see `pure_circuits::derive_zk_public_key` in
/// `tests-e2e-rust/contracts/zerocash/lib.rs`) and asserts equality
/// with a clear "constant drift" error message.
#[test]
fn fixed_pk_matches_pure_circuit_derivation() {
    let derived = compact_runtime::std_lib::persistent_hash_aligned(&[
        AlignedValue::from(FIXED_SK),
    ]);
    assert_eq!(
        derived,
        FIXED_PK,
        "FIXED_PK drift: persistent_hash_aligned(FIXED_SK) = {} but hardcoded FIXED_PK = {}. \
         FIXED_SK or the Rust persistent_hash semantics changed — regenerate the constant by \
         re-running tools/capture-zerocash.mjs and update FIXED_PK in this file.",
        hex::encode(derived),
        hex::encode(FIXED_PK),
    );
}
