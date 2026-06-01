// SPDX-License-Identifier: Apache-2.0
//
// election.compact byte-parity test (F2.1 of the M3.5 plan).
//
// Drives the generated election crate through initial_state() and asserts
// the serialized ContractState matches the TS reference fixture captured by
// fixtures/capture-election.mjs.
//
// Exercises ADT seeding for the broadest type matrix of M3.5:
//   - authority: Bytes<32>                       (cell of [0u8; 32])
//   - state: PublicState (enum)                  (cell of 0u8)
//   - topic: Maybe<Opaque<"string">>             (cell of Maybe<OpaqueString>::default())
//   - tally_yes / tally_no: Counter              (cell of 0u64)
//   - committed_votes / eligible_voters: MerkleTree<10, Bytes<32>>
//   - committed / revealed: Set<Bytes<32>>       (empty Map)

use compact_contract_election::{
    Contract, Ledger, PermissibleVotes, PrivateState, Witnesses,
};
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::ElectionTsReferenceState;

/// Trivial Witnesses impl for election. None of these are invoked during
/// initial_state() (the implicit constructor has no body), so we just need
/// type-correct stubs to satisfy the Contract<PS, W> bound.
struct ElectionWitnesses;

impl Witnesses<()> for ElectionWitnesses {
    fn private_secret_key<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
    ) -> ((), [u8; 32]) {
        ((), [0u8; 32])
    }
    fn private_state<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
    ) -> ((), PrivateState) {
        ((), PrivateState::initial)
    }
    fn private_state_advance<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
    ) -> ((), ()) {
        ((), ())
    }
    fn private_vote_record<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _ballot: PermissibleVotes,
    ) -> ((), ()) {
        ((), ())
    }
    fn private_vote<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
    ) -> ((), PermissibleVotes) {
        ((), PermissibleVotes::yes)
    }
    fn context_eligible_voters_path_of<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _pk: [u8; 32],
    ) -> ((), Maybe<compact_runtime::MerklePath<[u8; 32]>>) {
        // Upstream MerklePath<T> doesn't impl Default, so hand-construct a
        // placeholder via `default_merkle_path`. This witness is never invoked
        // by initial_state(), so the value is unused — what matters is the
        // type-correct signature.
        (
            (),
            Maybe {
                is_some: false,
                value: compact_runtime::default_merkle_path::<[u8; 32]>(),
            },
        )
    }
    fn context_committed_votes_path_of<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _cm: [u8; 32],
    ) -> ((), Maybe<compact_runtime::MerklePath<[u8; 32]>>) {
        (
            (),
            Maybe {
                is_some: false,
                value: compact_runtime::default_merkle_path::<[u8; 32]>(),
            },
        )
    }
}

fn fixture() -> ElectionTsReferenceState {
    ElectionTsReferenceState::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/election-ts-state.json"
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
/// path produces. election exports five circuits:
///   advance, vote$reveal, add_voter, vote$commit, set_topic
/// (insertion order matches the TS-side fixture).
fn make_envelope(
    data: ChargedState<midnight_storage::DefaultDB>,
) -> ContractState<midnight_storage::DefaultDB> {
    let mut operations: HashMap<EntryPointBuf, ContractOperation, midnight_storage::DefaultDB> =
        HashMap::new();
    operations = operations.insert(
        EntryPointBuf(b"advance".to_vec()),
        ContractOperation::new(None),
    );
    operations = operations.insert(
        EntryPointBuf(b"vote$reveal".to_vec()),
        ContractOperation::new(None),
    );
    operations = operations.insert(
        EntryPointBuf(b"add_voter".to_vec()),
        ContractOperation::new(None),
    );
    operations = operations.insert(
        EntryPointBuf(b"vote$commit".to_vec()),
        ContractOperation::new(None),
    );
    operations = operations.insert(
        EntryPointBuf(b"set_topic".to_vec()),
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
fn election_init_byte_parity() {
    let ts_ref = fixture();
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
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
