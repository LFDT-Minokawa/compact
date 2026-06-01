// SPDX-License-Identifier: Apache-2.0
//
// election.compact byte-parity tests (F2.1 + F2.2 of the M3.5 plan).
//
// F2.1 drives initial_state() and asserts the serialized ContractState
// matches the TS reference fixture captured by capture-election.mjs.
//
// F2.2 attempts to extend to the owner-driven impure circuits
// (set_topic, advance, add_voter) and the vote circuits (vote$commit,
// vote$reveal). election.compact has no source-level constructor, so the
// implicit initial_state() seeds `authority` to `[0u8; 32]` and every
// owner-driven circuit asserts `public_key(sk) == authority.read()` —
// which the witness's fixed `sk` cannot satisfy (the assertion would
// require a hash preimage of `[0u8; 32]` under the contract's
// "lares:election:pk:" domain separator). The TS driver's capture
// records `error` rather than `state_hex` for every post-init step,
// and the Rust tests are `#[ignore]`'d with a gating check so the
// captured TS error is shown when run with `--include-ignored`.
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
use tests_e2e_rust::{ElectionStepSnapshot, ElectionTsReferenceState};

/// Fixed deterministic witness payloads — must match capture-election.mjs.
const FIXED_SK: [u8; 32] = [7u8; 32];
const VOTER_PK: [u8; 32] = [0x11u8; 32];

/// Trivial Witnesses impl for election. None of these are invoked during
/// initial_state() (the implicit constructor has no body), so we just need
/// type-correct stubs to satisfy the Contract<PS, W> bound.
struct ElectionWitnesses;

impl Witnesses<()> for ElectionWitnesses {
    fn private_secret_key<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
    ) -> ((), [u8; 32]) {
        ((), FIXED_SK)
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

fn assert_step_bytes_eq(
    label: &str,
    state: &ContractState<midnight_storage::DefaultDB>,
    expected: &ElectionStepSnapshot,
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

/// Require the named step's snapshot to carry a captured `stateHex`. If
/// the TS driver instead recorded an `error`, panic with the message so
/// the test diagnostic is meaningful.
fn require_state_hex<'a>(label: &str, snap: Option<&'a ElectionStepSnapshot>) -> &'a ElectionStepSnapshot {
    let snap = snap.unwrap_or_else(|| panic!("TS fixture missing {label} snapshot"));
    if snap.state_hex.is_none() {
        panic!(
            "TS driver errored on {label}: {:?}",
            snap.error.as_deref().unwrap_or("(no error message)")
        );
    }
    snap
}

#[test]
fn election_init_byte_parity() {
    let ts_ref = fixture();
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let result = contract.initial_state(ctor_ctx()).expect("initial_state");

    let envelope = make_envelope(result.current_contract_state.clone());
    assert_step_bytes_eq("init", &envelope, &ts_ref.after_init);
}

// --------------------------------------------------------------------
// F2.2: owner-driven and voting circuits.
//
// All five of these are gated by `#[ignore]`. election.compact lacks a
// source-level constructor, so `authority` is seeded to `[0u8; 32]` and
// the asserts `public_key(sk) == authority.read()` in set_topic /
// advance / add_voter cannot succeed (the witness's `FIXED_SK` does not
// hash to all-zero bytes, and the contract's domain-separated
// persistent-hash is preimage-resistant). The vote$commit / vote$reveal
// circuits are doubly blocked: they additionally require a MerklePath
// recognised by the on-chain MerkleTree.
//
// Each test gates on `require_state_hex` so that, if a future
// constructor or path-extraction helper lands and the TS driver
// captures the post-step state, the test fails loudly until the
// `#[ignore]` is removed.
// --------------------------------------------------------------------

#[test]
#[ignore = "election.compact has no source-level constructor; authority defaults to [0u8;32] which the witness sk cannot hash to. Drop ignore once a constructor lands."]
fn election_init_then_set_topic_byte_parity() {
    let ts_ref = fixture();
    let after = require_state_hex("after_set_topic", ts_ref.after_set_topic.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract
        .set_topic(circ_ctx, compact_runtime::std_lib::OpaqueString::from("hello"))
        .expect("set_topic");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("set_topic", &envelope, after);
}

#[test]
#[ignore = "election.compact has no source-level constructor; authority defaults to [0u8;32] which the witness sk cannot hash to. Drop ignore once a constructor lands."]
fn election_init_then_advance_byte_parity() {
    let ts_ref = fixture();
    let after = require_state_hex("after_advance", ts_ref.after_advance.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract.advance(circ_ctx).expect("advance");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("advance", &envelope, after);
}

#[test]
#[ignore = "election.compact has no source-level constructor; authority defaults to [0u8;32] which the witness sk cannot hash to. Drop ignore once a constructor lands."]
fn election_init_then_add_voter_byte_parity() {
    let ts_ref = fixture();
    let after = require_state_hex("after_add_voter", ts_ref.after_add_voter.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract.add_voter(circ_ctx, VOTER_PK).expect("add_voter");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("add_voter", &envelope, after);
}

#[test]
#[ignore = "vote$commit asserts state==commit AND a MerklePath rooted in eligible_voters; blocked by missing constructor + stub merkle path."]
fn election_vote_commit_byte_parity() {
    let ts_ref = fixture();
    let after = require_state_hex("after_vote_commit", ts_ref.after_vote_commit.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract
        .vote_commit(circ_ctx, PermissibleVotes::yes)
        .expect("vote_commit");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("vote_commit", &envelope, after);
}

#[test]
#[ignore = "vote$reveal asserts state==reveal AND a MerklePath rooted in committed_votes; blocked by missing constructor + stub merkle path."]
fn election_vote_reveal_byte_parity() {
    let ts_ref = fixture();
    let after = require_state_hex("after_vote_reveal", ts_ref.after_vote_reveal.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract.vote_reveal(circ_ctx).expect("vote_reveal");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("vote_reveal", &envelope, after);
}
