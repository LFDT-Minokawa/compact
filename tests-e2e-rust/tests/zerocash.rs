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
use tests_e2e_rust::{ZerocashStepSnapshot, ZerocashTsReferenceState};

// Fixed deterministic witness payloads — must match capture-zerocash.mjs
// byte for byte, so that both drivers fold the same persistent_hash
// arguments and produce byte-identical ContractStates.
const FIXED_SK: [u8; 32] = [1u8; 32];
const FIXED_PK: [u8; 32] = [2u8; 32];
const FIXED_NONCE: [u8; 32] = [3u8; 32];
const FIXED_OPENING: [u8; 32] = [4u8; 32];
const FIXED_CIPHERTEXT: [u8; 3] = [10u8, 11u8, 12u8];

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
        _cm: commitment,
    ) -> ((), compact_runtime::MerklePath<commitment>) {
        ((), compact_runtime::default_merkle_path::<commitment>())
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
/// recorded in the HistoricMerkleTree. The deterministic witness we
/// share with the TS driver returns a stub path (all-zero siblings,
/// leaf = the requested commitment) which won't claim a real position
/// in the tree — so the TS driver fails the in-circuit assertion
/// `commitments.checkRoot(merkleTreePathRoot(path))` and reports
/// "spend: Illegal state: merkle path not recognized by public state".
///
/// To close this test we'd need either:
///   1. A path-extraction helper exposed in TS that pulls the actual
///      MerklePath of an inserted commitment out of the on-chain
///      HistoricMerkleTree (so context$path_of can return a real path
///      rooted in the post-mint tree state), or
///   2. An off-chain HMT mirror in the test driver that tracks
///      insertions and produces the matching path on demand.
///
/// Until one of those is in place, the multi-step driver captures
/// `afterSpend.error` instead of `afterSpend.stateHex`, and this test
/// is ignored.
#[test]
#[ignore = "spend requires a real MerklePath for the just-minted commitment; stub witness paths fail commitments.checkRoot. See test doc-comment."]
fn zerocash_init_mint_spend_byte_parity() {
    let ts_ref = fixture();
    let after_spend = ts_ref
        .after_spend
        .as_ref()
        .expect("TS fixture missing afterSpend snapshot");
    let contract: Contract<(), ZerocashWitnesses> = Contract::new(ZerocashWitnesses);
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let mint = contract.zerocash_mint(circ_ctx).expect("zerocash_mint");

    let dest_pk = compact_contract_zerocash::public_key {
        zk: zk_public_key { bytes: [5u8; 32] },
        encryption: vec![6u8; 32],
    };
    let input_coin = fixed_coin_info();
    let spend = contract
        .spend(mint.context, dest_pk, input_coin)
        .expect("spend");
    let envelope = make_envelope(spend.context.current_query_context.state.clone());
    assert_step_bytes_eq("spend", &envelope, after_spend);
}
