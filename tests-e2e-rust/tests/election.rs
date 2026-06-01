// SPDX-License-Identifier: Apache-2.0
//
// election.compact byte-parity tests (F2.1 + F2.2 of the M3.5 plan).
//
// F2.1 drives initial_state() and asserts the serialized ContractState
// matches the TS reference fixture captured by capture-election.mjs.
//
// F2.2/2 extends to the owner-driven impure circuits (set_topic,
// advance, add_voter). election.compact now has a source-level
// constructor `constructor(authority_init: Bytes<32>) { authority =
// authority_init; }` — initial_state() takes the authority bytes
// directly, and the owner-driven asserts `public_key(sk) ==
// authority.read()` are satisfied by passing AUTHORITY = the
// pre-computed `public_key(FIXED_SK)`.
//
// vote$commit / vote$reveal remain `#[ignore]`'d: they additionally
// need a MerklePath rooted in eligible_voters / committed_votes that
// our stub witness does not synthesize.
//
// Exercises ADT seeding for the broadest type matrix of M3.5:
//   - authority: Bytes<32>                       (cell of AUTHORITY)
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

/// Hardcoded `public_key(FIXED_SK)` — i.e. persistent_hash with the
/// "lares:election:pk:" domain separator of the all-7s secret key.
/// Must match the AUTHORITY computed by capture-election.mjs via
/// `contract._public_key_0(FIXED_SK)`. The constructor seeds this
/// into the `authority` ledger field so the owner-driven asserts
/// `public_key(sk) == authority.read()` are satisfied.
const AUTHORITY: [u8; 32] = [
    0x33, 0xef, 0xf3, 0xd5, 0x7e, 0x66, 0xfd, 0x14,
    0x2b, 0xb4, 0x08, 0xe4, 0x89, 0x44, 0xa4, 0xd6,
    0xb8, 0xf2, 0xdb, 0xf5, 0xc1, 0x80, 0x96, 0xf8,
    0x27, 0xb0, 0x28, 0x3d, 0xbf, 0x91, 0x11, 0xc8,
];

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
    let result = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");

    let envelope = make_envelope(result.current_contract_state.clone());
    assert_step_bytes_eq("init", &envelope, &ts_ref.after_init);
}

// --------------------------------------------------------------------
// F2.2/2: owner-driven and voting circuits.
//
// With the source-level constructor now seeding `authority` to
// `public_key(FIXED_SK)`, the asserts `public_key(sk) ==
// authority.read()` in set_topic / advance / add_voter succeed.
//
// vote$commit / vote$reveal remain `#[ignore]`'d: they additionally
// require a MerklePath rooted in the on-chain MerkleTree, which our
// stub witness does not synthesize.
//
// Each test gates on `require_state_hex` so a divergence between the
// TS capture and the Rust driver shows up as a clear diagnostic.
// --------------------------------------------------------------------

#[test]
fn election_init_then_set_topic_byte_parity() {
    let ts_ref = fixture();
    let after = require_state_hex("after_set_topic", ts_ref.after_set_topic.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract
        .set_topic(circ_ctx, compact_runtime::std_lib::OpaqueString::from("hello"))
        .expect("set_topic");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("set_topic", &envelope, after);
}

#[test]
fn election_init_then_advance_byte_parity() {
    // advance() asserts `topic.read().is_some`; therefore the only
    // legal prefix from initial_state is set_topic → advance.
    let ts_ref = fixture();
    let after = require_state_hex("after_advance", ts_ref.after_advance.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let after_set_topic = contract
        .set_topic(circ_ctx, compact_runtime::std_lib::OpaqueString::from("hello"))
        .expect("set_topic");
    let out = contract.advance(after_set_topic.context).expect("advance");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("advance", &envelope, after);
}

#[test]
fn election_init_then_add_voter_byte_parity() {
    let ts_ref = fixture();
    let after = require_state_hex("after_add_voter", ts_ref.after_add_voter.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract.add_voter(circ_ctx, VOTER_PK).expect("add_voter");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("add_voter", &envelope, after);
}

#[test]
#[ignore = "vote$commit asserts a MerklePath rooted in eligible_voters; the stub witness path does not satisfy checkRoot. Drop once MerklePath harness lands."]
fn election_vote_commit_byte_parity() {
    let ts_ref = fixture();
    let after = require_state_hex("after_vote_commit", ts_ref.after_vote_commit.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract
        .vote_commit(circ_ctx, PermissibleVotes::yes)
        .expect("vote_commit");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("vote_commit", &envelope, after);
}

#[test]
#[ignore = "vote$reveal asserts a MerklePath rooted in committed_votes; blocked by stub merkle path. Drop once MerklePath harness lands."]
fn election_vote_reveal_byte_parity() {
    let ts_ref = fixture();
    let after = require_state_hex("after_vote_reveal", ts_ref.after_vote_reveal.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract.vote_reveal(circ_ctx).expect("vote_reveal");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("vote_reveal", &envelope, after);
}
