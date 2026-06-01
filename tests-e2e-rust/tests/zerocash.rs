// SPDX-License-Identifier: Apache-2.0
//
// zerocash.compact byte-parity test (F1.1 of the M3.5 plan).
//
// Drives the generated zerocash crate through initial_state() and asserts
// the serialized ContractState matches the TS reference fixture captured by
// fixtures/capture-zerocash.mjs.
//
// Exercises ADT seeding for three ledger fields:
//   - nullifiers: Set<nullifier>          (seeds as empty Map)
//   - commitments: HistoricMerkleTree<32> (seeds as 3-slot array)
//   - ciphertexts: Opaque<"Uint8Array">   (seeds as cell of Vec<u8>::new())

use compact_contract_zerocash::{
    coin_info, commitment, zk_public_key, zk_secret_key, Contract, Ledger, Witnesses,
};
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::ZerocashTsReferenceState;

/// Trivial Witnesses impl for zerocash. None of these are invoked during
/// initial_state() (the implicit constructor has no body), so we just need
/// type-correct stubs to satisfy the Contract<PS, W> bound.
struct ZerocashWitnesses;

impl Witnesses<()> for ZerocashWitnesses {
    fn private_zk_secret_key<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
    ) -> ((), zk_secret_key) {
        ((), zk_secret_key::default())
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
        ((), zk_public_key::default())
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
        ((), coin_info::default())
    }
    fn context_encrypt<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _pk: Vec<u8>,
        _coin: coin_info,
    ) -> ((), Vec<u8>) {
        ((), Vec::new())
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

#[test]
fn zerocash_init_byte_parity() {
    let ts_ref = fixture();
    let contract: Contract<(), ZerocashWitnesses> = Contract::new(ZerocashWitnesses);
    let result = contract.initial_state(ctor_ctx()).expect("initial_state");

    let envelope = make_envelope(result.current_contract_state.clone());
    let mut buf = Vec::new();
    tagged_serialize(&envelope, &mut buf).expect("tagged_serialize");

    let ts_bytes = ts_ref.after_init.state_bytes();
    assert_eq!(
        buf,
        ts_bytes,
        "Rust state bytes differ from TS reference\n\nRust ({} B): {}\n\nTS   ({} B): {}",
        buf.len(),
        hex::encode(&buf),
        ts_bytes.len(),
        hex::encode(&ts_bytes),
    );
}
