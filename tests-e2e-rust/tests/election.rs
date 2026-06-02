// SPDX-License-Identifier: Apache-2.0

// `passing a unit value to a function` fires throughout these tests
// because some fixtures have `PS = ()` (no private state), so the
// CircuitContext::new(state, ()) call deliberately threads a unit.
// The lint can't see that and the alternative (a phantom newtype) would
// be more confusing than the suppression.
#![allow(clippy::unit_arg)]
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

use compact_contract_election::{Contract, Ledger, PermissibleVotes, PrivateState, Witnesses};
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use std::cell::RefCell;
use tests_e2e_rust::{CapturedMerklePath, ElectionStepSnapshot, ElectionTsReferenceState};

/// Fixed deterministic witness payloads — must match capture-election.mjs.
const FIXED_SK: [u8; 32] = [7u8; 32];

/// Hardcoded `public_key(FIXED_SK)` — i.e. persistent_hash with the
/// "lares:election:pk:" domain separator of the all-7s secret key.
/// Must match the AUTHORITY computed by capture-election.mjs via
/// `contract._public_key_0(FIXED_SK)`. The constructor seeds this
/// into the `authority` ledger field so the owner-driven asserts
/// `public_key(sk) == authority.read()` are satisfied.
const AUTHORITY: [u8; 32] = [
    0x33, 0xef, 0xf3, 0xd5, 0x7e, 0x66, 0xfd, 0x14, 0x2b, 0xb4, 0x08, 0xe4, 0x89, 0x44, 0xa4, 0xd6,
    0xb8, 0xf2, 0xdb, 0xf5, 0xc1, 0x80, 0x96, 0xf8, 0x27, 0xb0, 0x28, 0x3d, 0xbf, 0x91, 0x11, 0xc8,
];

/// `vote$commit` derives `pk = public_key(FIXED_SK)`, which equals
/// AUTHORITY. So the only voter that can both be `add_voter`'d *and*
/// later have `vote$commit` succeed is AUTHORITY itself. The TS capture
/// does the same (registers AUTHORITY as VOTER_PK).
const VOTER_PK: [u8; 32] = AUTHORITY;

thread_local! {
    /// Path to return for the next `eligible_voters$path_of` invocation.
    /// Tests stash a captured path before calling vote$commit; the
    /// witness clones it out. None by default → returns is_some=false.
    static ELIGIBLE_PATH: RefCell<Option<CapturedMerklePath>> = const { RefCell::new(None) };
    /// Path to return for the next `committed_votes$path_of` invocation.
    static COMMITTED_PATH: RefCell<Option<CapturedMerklePath>> = const { RefCell::new(None) };
    /// Toggle for `private_state` — flips from `initial` → `committed`
    /// → `revealed` each time `private_state_advance` is called, just
    /// like the TS capture's `privateStateFsm`. Lets vote$commit pass
    /// the `private$state == initial` check and vote$reveal pass the
    /// `private$state == committed` check on the same fixture chain.
    static PRIVATE_STATE_FSM: RefCell<PrivateState> = const { RefCell::new(PrivateState::initial) };
}

fn reset_election_thread_local() {
    ELIGIBLE_PATH.with(|c| *c.borrow_mut() = None);
    COMMITTED_PATH.with(|c| *c.borrow_mut() = None);
    PRIVATE_STATE_FSM.with(|c| *c.borrow_mut() = PrivateState::initial);
}

/// Trivial Witnesses impl for election. None of these are invoked during
/// initial_state() (the implicit constructor has no body), so we just need
/// type-correct stubs to satisfy the Contract<PS, W> bound.
struct ElectionWitnesses;

impl Witnesses<()> for ElectionWitnesses {
    fn private_secret_key<'a>(&self, _ctx: &WitnessContext<Ledger<'a>, ()>) -> ((), [u8; 32]) {
        ((), FIXED_SK)
    }
    fn private_state<'a>(&self, _ctx: &WitnessContext<Ledger<'a>, ()>) -> ((), PrivateState) {
        let s = PRIVATE_STATE_FSM.with(|c| *c.borrow());
        ((), s)
    }
    fn private_state_advance<'a>(&self, _ctx: &WitnessContext<Ledger<'a>, ()>) -> ((), ()) {
        // initial → committed → revealed (saturating). Mirrors the
        // capture-election.mjs `bumpPrivateState` toggle.
        PRIVATE_STATE_FSM.with(|c| {
            let mut g = c.borrow_mut();
            *g = match *g {
                PrivateState::initial => PrivateState::committed,
                PrivateState::committed => PrivateState::revealed,
                PrivateState::revealed => PrivateState::revealed,
            };
        });
        ((), ())
    }
    fn private_vote_record<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _ballot: PermissibleVotes,
    ) -> ((), ()) {
        ((), ())
    }
    fn private_vote<'a>(&self, _ctx: &WitnessContext<Ledger<'a>, ()>) -> ((), PermissibleVotes) {
        ((), PermissibleVotes::yes)
    }
    fn context_eligible_voters_path_of<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _pk: [u8; 32],
    ) -> ((), Maybe<compact_runtime::MerklePath<[u8; 32]>>) {
        match ELIGIBLE_PATH.with(|c| c.borrow().clone()) {
            Some(p) => (
                (),
                Maybe {
                    is_some: true,
                    value: compact_runtime::MerklePath {
                        leaf: p.leaf_bytes(),
                        path: p.into_entries(),
                    },
                },
            ),
            None => (
                (),
                Maybe {
                    is_some: false,
                    value: compact_runtime::default_merkle_path::<[u8; 32]>(),
                },
            ),
        }
    }
    fn context_committed_votes_path_of<'a>(
        &self,
        _ctx: &WitnessContext<Ledger<'a>, ()>,
        _cm: [u8; 32],
    ) -> ((), Maybe<compact_runtime::MerklePath<[u8; 32]>>) {
        match COMMITTED_PATH.with(|c| c.borrow().clone()) {
            Some(p) => (
                (),
                Maybe {
                    is_some: true,
                    value: compact_runtime::MerklePath {
                        leaf: p.leaf_bytes(),
                        path: p.into_entries(),
                    },
                },
            ),
            None => (
                (),
                Maybe {
                    is_some: false,
                    value: compact_runtime::default_merkle_path::<[u8; 32]>(),
                },
            ),
        }
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
fn require_state_hex<'a>(
    label: &str,
    snap: Option<&'a ElectionStepSnapshot>,
) -> &'a ElectionStepSnapshot {
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
    reset_election_thread_local();
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
    reset_election_thread_local();
    let ts_ref = fixture();
    let after = require_state_hex("after_set_topic", ts_ref.after_set_topic.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let out = contract
        .set_topic(
            circ_ctx,
            compact_runtime::std_lib::OpaqueString::from("hello"),
        )
        .expect("set_topic");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("set_topic", &envelope, after);
}

#[test]
fn election_init_then_advance_byte_parity() {
    // advance() asserts `topic.read().is_some`; therefore the only
    // legal prefix from initial_state is set_topic → advance.
    reset_election_thread_local();
    let ts_ref = fixture();
    let after = require_state_hex("after_advance", ts_ref.after_advance.as_ref());
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let after_set_topic = contract
        .set_topic(
            circ_ctx,
            compact_runtime::std_lib::OpaqueString::from("hello"),
        )
        .expect("set_topic");
    let out = contract.advance(after_set_topic.context).expect("advance");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("advance", &envelope, after);
}

#[test]
fn election_init_then_add_voter_byte_parity() {
    reset_election_thread_local();
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

/// Drives the same chain capture-election.mjs uses for vote$commit:
///   init → set_topic → add_voter(AUTHORITY) → advance → vote$commit(yes)
/// Then byte-compares the post-step ContractState against the TS
/// fixture. The eligibleness MerklePath returned by the witness is the
/// one captured in `votePathEligible` (replayed via ELIGIBLE_PATH).
#[test]
fn election_vote_commit_byte_parity() {
    reset_election_thread_local();
    let ts_ref = fixture();
    let after = require_state_hex("after_vote_commit", ts_ref.after_vote_commit.as_ref());
    let vote_path = ts_ref
        .vote_path_eligible
        .as_ref()
        .expect("TS fixture missing votePathEligible");
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");
    let ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let after_set_topic = contract
        .set_topic(ctx, compact_runtime::std_lib::OpaqueString::from("hello"))
        .expect("set_topic");
    let after_add_voter = contract
        .add_voter(after_set_topic.context, VOTER_PK)
        .expect("add_voter");
    let after_advance = contract.advance(after_add_voter.context).expect("advance");
    // Stash the captured eligibleness path; the witness clones it
    // out for this single vote$commit invocation. Cleared afterwards.
    ELIGIBLE_PATH.with(|c| *c.borrow_mut() = Some(vote_path.clone()));
    let result = contract.vote_commit(after_advance.context, PermissibleVotes::yes);
    ELIGIBLE_PATH.with(|c| *c.borrow_mut() = None);
    let out = result.expect("vote_commit");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("vote_commit", &envelope, after);
}

/// Drives the full chain that ends in vote$reveal:
///   init → set_topic → add_voter → advance → vote$commit
///        → advance → vote$reveal
/// Both eligibleness and committed_votes paths are needed: the former
/// for vote$commit, the latter for vote$reveal. Each is stashed
/// immediately before the relevant circuit call.
#[test]
fn election_vote_reveal_byte_parity() {
    reset_election_thread_local();
    let ts_ref = fixture();
    let after = require_state_hex("after_vote_reveal", ts_ref.after_vote_reveal.as_ref());
    let eligible_path = ts_ref
        .vote_path_eligible
        .as_ref()
        .expect("TS fixture missing votePathEligible");
    let committed_path = ts_ref
        .vote_path_committed
        .as_ref()
        .expect("TS fixture missing votePathCommitted");
    let contract: Contract<(), ElectionWitnesses> = Contract::new(ElectionWitnesses);
    let init = contract
        .initial_state(ctor_ctx(), AUTHORITY)
        .expect("initial_state");
    let ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let after_set_topic = contract
        .set_topic(ctx, compact_runtime::std_lib::OpaqueString::from("hello"))
        .expect("set_topic");
    let after_add_voter = contract
        .add_voter(after_set_topic.context, VOTER_PK)
        .expect("add_voter");
    let after_advance = contract.advance(after_add_voter.context).expect("advance");
    ELIGIBLE_PATH.with(|c| *c.borrow_mut() = Some(eligible_path.clone()));
    let after_vote_commit = contract
        .vote_commit(after_advance.context, PermissibleVotes::yes)
        .expect("vote_commit");
    ELIGIBLE_PATH.with(|c| *c.borrow_mut() = None);
    let after_advance2 = contract
        .advance(after_vote_commit.context)
        .expect("advance");
    COMMITTED_PATH.with(|c| *c.borrow_mut() = Some(committed_path.clone()));
    let result = contract.vote_reveal(after_advance2.context);
    COMMITTED_PATH.with(|c| *c.borrow_mut() = None);
    let out = result.expect("vote_reveal");
    let envelope = make_envelope(out.context.current_query_context.state.clone());
    assert_step_bytes_eq("vote_reveal", &envelope, after);
}

/// Drift detector for the hardcoded AUTHORITY constant.
///
/// AUTHORITY is the byte image of `public_key(FIXED_SK)` computed by
/// the TS capture driver. Owner-driven circuits (`set_topic`, `advance`,
/// `add_voter`) assert `public_key(sk) == authority.read()`, so the
/// constructor must seed `authority` with exactly this value or every
/// owner-action e2e test fails with an opaque ContractState hex mismatch.
///
/// Re-derive via the same Rust hash primitive
/// (`persistent_hash_aligned` with the `"lares:election:pk:"` domain
/// separator padded to 32 bytes — see `pure_circuits::public_key` in
/// `tests-e2e-rust/contracts/election/lib.rs`) and assert equality.
/// If `FIXED_SK` changes (or the persistent_hash semantics shift), this
/// test fails with a clear "constant drift" message before the
/// byte-parity tests fail.
#[test]
fn authority_matches_pure_circuit_derivation() {
    // "lares:election:pk:" (18 bytes) padded with NUL to 32 bytes —
    // the exact domain separator used by election's pure_circuits::public_key.
    const DOMAIN_SEP: [u8; 32] = [
        108u8, 97, 114, 101, 115, 58, 101, 108, 101, 99, 116, 105, 111, 110, 58, 112, 107, 58, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    ];
    let derived = compact_runtime::std_lib::persistent_hash_aligned(&[
        AlignedValue::from(DOMAIN_SEP),
        AlignedValue::from(FIXED_SK),
    ]);
    assert_eq!(
        derived,
        AUTHORITY,
        "AUTHORITY drift: persistent_hash_aligned(\"lares:election:pk:\", FIXED_SK) = {} but \
         hardcoded AUTHORITY = {}. FIXED_SK, the domain separator, or the Rust persistent_hash \
         semantics changed — regenerate the constant by re-running tools/capture-election.mjs \
         and update AUTHORITY in this file.",
        hex::encode(derived),
        hex::encode(AUTHORITY),
    );
}
