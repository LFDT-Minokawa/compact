# Handoff prompts for two Compact design inquiries

Paste **Part 0** first, then **Part 1** *or* **Part 2**, into a fresh instance. Part 0 is
identical for both.

Before you start either: `midnight-js` is not currently a connected folder and does not
exist under `~/IdeaProjects`. Clone it and add it via the "Add folder" button in the
desktop app, or the agents will silently skip a third of their assignment.

---
---

# PART 0 — Shared briefing (paste verbatim into both)

## How to read these repos — read this first, it will save you an hour

The source lives on the **user's machine**, not in your container. Use
`mcp__remote-devices__device_bash` to run shell commands (`cat`, `grep`, `rg`, `find`,
`sed -n 'A,Bp'`, `wc`) against:

- `$HOME/mnt/compact` — the Compact compiler (Chez Scheme + nanopass, `.ss` files) plus an
  Agda specification under `specification/`
- `$HOME/mnt/midnight-ledger` — the Rust ledger, Impact VM, on-chain runtime, ZK IR
- `$HOME/mnt/midnight-js` — the TypeScript SDK (**verify this is connected before
  planning around it**; if `ls $HOME/mnt/` doesn't show it, tell the user and proceed with
  the other two)

**Do not use Read / Grep / Glob** — they search your container and will find nothing. Each
`device_bash` call is a fresh shell with a ~45s limit, so keep commands scoped and page
through large files with `sed -n`.

Two design documents from a prior session are already on disk and are the best possible
starting point. **Read both before doing anything else:**

- `$HOME/mnt/compact/proposals/traits-design-space.md`
- `$HOME/mnt/compact/proposals/coherent-type-landscape.md`

Then fan out with **parallel `Explore` subagents** (send them in one message so they run
concurrently). Give every subagent the `device_bash` instruction above verbatim — they
will otherwise default to Read/Grep and come back empty. Ask each for file paths, line
numbers, and quoted code; do not accept prose summaries.

## The Midnight programming model, in one page

Midnight is a privacy blockchain. A contract has a **public state** (on chain, visible to
everyone) and **private state** (on the user's machine). Compact is the DSL for writing
contracts; a single Compact `circuit` compiles to **two artifacts**:

1. a **ZK circuit** (via ZKIR) proving the private computation was done correctly, and
2. an **Impact VM program** — the public transcript of what the contract did to its
   on-chain state.

**The transaction lifecycle** is the thing to internalize:

1. **Rehearse (construct).** On the user's machine, against a *snapshot* of on-chain state.
   The Impact program is generated here, with concrete immediates and path keys, and every
   state read is *gathered*.
2. **Prove.** A ZK proof is produced. Critically, **the entire Impact opcode sequence is a
   public input to that proof** (`ledger/src/verify.rs:1946-1990` field-reprs every opcode).
   The program is a constant the proof commits to.
3. **Submit & replay.** The chain re-runs the *fixed* opcode stream against real current
   state. Every recorded read must still match
   (`onchain-vm/src/result_mode.rs:44-58`, `ResultModeVerify::process_read` →
   `ReadMismatch`). Declared gas and declared effects must match what actually happens.

This rehearse/replay design is how Midnight minimizes cross-contract race conditions: a
transaction is rejected rather than silently reinterpreted if the state moved underneath it.

**The Impact VM** (`midnight-ledger/onchain-vm`, `onchain-state`, `onchain-runtime`) is a
32-opcode stack machine over exactly **five** value shapes
(`onchain-state/src/state.rs:69-96`): `Null`, `Cell(AlignedValue)`, `Map`, `Array` (≤16),
`BoundedMerkleTree` (height ≤32). Facts that constrain every design here:

- **No loops.** `Branch`/`Jmp` take `u32` immediates and `skip >= 1`; the program only ever
  shrinks (`onchain-vm/src/vm.rs:1056-1071`). Straight-line, forward-only.
- **No indirect jump, no call, no return, no code-in-data.** A vtable is not representable.
- **The VM has never heard of a "ledger ADT."** `Cell`, `Counter`, `Map`, `Set`, `List`,
  `MerkleTree`, `HistoricMerkleTree` are compile-time macros in the *Compact compiler*
  (`compact/compiler/ledger.ss` + `compact/compiler/midnight-ledger.ss`) that expand to
  opcode sequences. `List` and `HistoricMerkleTree` are already pure user-space
  constructions.
- **Cost is per-emitted-opcode**, affine in runtime data sizes, and opcode count is *also*
  proof width and transaction bytes. Compile-time abstraction is genuinely free; runtime
  dispatch is not.
- **`popeq` is the only channel from state into the circuit**, and its result is
  simultaneously a ZK public input, the replay checker's comparison target, and the
  transaction's read-set.
- **`Effects`** is a *fixed 9-element array* of maps, decoded structurally
  (`onchain-runtime/src/context.rs:776-841`); a mismatch between declared and computed
  effects rejects the transaction (`ledger/src/semantics.rs:1452-1461`). Slots:
  0 nullifiers, 1 shielded receives, 2 shielded spends, 3 contract calls, 4 shielded mints,
  5 unshielded mints, 6 unshielded inputs, 7 unshielded outputs, 8 unshielded spends.

**The Compact compiler** erases all abstraction before either backend:
`expand-modules-and-types` monomorphizes every generic; `unroll-loops` fully unrolls
`map`/`fold`/`for`; `inline-circuits` inlines *every* circuit; recursion is rejected;
`flatten-datatypes` explodes structured values into vectors of field-element variables.
Nothing polymorphic survives to runtime. Pass pipeline is in `compiler/passes.ss`.

## Type-system context you must design against

The prior sessions produced an end-state design for Compact's type system. Your proposal
has to fit it, or argue explicitly why it shouldn't. The load-bearing pieces:

**(a) The totality invariant.** Every type's size is a closed term at the point of use;
every elimination is a fold over a finite index; therefore every program unrolls to a
straight-line sequence of statically-known length. This one property is simultaneously why
a finite proving circuit exists, why declared gas is meaningful, and why the opcode stream
is a valid ZK public input. **Test every feature you propose against it.** The user's
stated end-goal is "a surface language for Impact — nothing requiring a backward jump."

**(b) The `Val` / `Store` kind split.** The proposed reform introduces kinds:
`Nat` (indices), `Val` (statically-sized values — the circuit world), `Store` (places in
the state tree, unbounded extent but statically-known access cost — the ledger world),
`Extern` (`Opaque<s>`, no on-chain representation), `Iface` (`contract` types). Roughly a
dozen ad-hoc restrictions in `infer-types.ss` — including the `Non-ADT-Type` predicate at
`infer-types.ss:305-320`, applied at eight sites — become kinding rules. The slogan:
*`Val` types have static **size**; `Store` types have static **access cost** but unbounded
extent.*

**(c) A `Store` "self" is a place, not a value.** Every ledger ADT operation is already a
function from a *compile-time path* (`f`, plus `f-cached`) to an opcode sequence. There are
no first-class ADT values today, and nesting is lens composition.

**(d) Observation is disclosure is the read-set.** Verified: **all 23 `read`-class ledger
ops end in `popeq`; no `update`/`write`/`remove` op contains one.** So `op-class`, the
disclosure analysis (`track-witness-data.ss`), and rehearse/replay determinism are one
distinction. Corollary: `Counter.increment` discloses nothing, while
`read(); +1; write()` discloses the counter's value. Also: **every argument to a ledger
operation is inlined into the opcode stream, which is a public input** — so ledger-op
arguments are *necessarily* public. That is why the disclosure default for ledger ops is
"discloses"; it's forced, not lazy.

**(e) `contract` types are existentials (∃); traits are bounded universals (∀).**
`contract C {...}` means "*some* deployed contract with this interface." That's why
satisfaction is structural, why it has width subtyping, why it's the only dynamic thing in
the language, and — importantly — **why Compact currently cannot create a value of contract
type** (`doc/compact-reference.mdx:784-789`). Packing an existential requires a concrete
implementation.

**(f) Compact's `Val` algebra is products and nothing else.** Verified: the alignment atom
set is `{acompress, abytes n, afield, aadt, anative}` and `tstruct`/`ttuple` both lower via
`fold-right` — concatenation. There are **no sum types**, even though the runtime encoding
has them (`base-crypto/src/fab/encoding.rs:265-277`, `AlignmentSegment::Option`, sized
`max`-of-branches). `Maybe<T>` and `Either<A,B>` are faked as products that pay for every
branch. A reform to real sums (unifying `struct` / `enum` / `new type` as one nominal
declaration at different arities) is on the table.

**(g) Resource budgets that compose and nothing tracks.** `Array` length ≤ 16, `Idx` path
depth ≤ 16, `Ins` levels ≤ 15, `Dup`/`Swap` reach ≤ 15, `maximum-ledger-segment-length` = 15
(`compact/compiler/langs.ss:850-855`). There is already a comment at
`compact/compiler/midnight-ledger.ss:577` warning that coin-writing ops break when the
access path exceeds length 5.

## House style for the output

Language changes go through a **CoIP** (see `$HOME/mnt/compact/coips/README.md`,
`coip-0001.md` for the process, `coip-template.md` for structure, and `coip-0002.md` for a
good stylistic model). You are **not** writing the CoIP yet — you are writing the design
exploration that precedes it. Ground every claim in file paths and line numbers. Where you
are inferring rather than reading, say so. Where a design is blocked by a real constraint,
name the constraint and cite it.

---
---

# PART 1 — Dynamic contract deployment

**The goal:** let a Compact circuit instantiate a contract during execution and have the
resulting deployment added to the same transaction. Contract factories, in other words.

## Head start — three things already established, don't re-derive them

**1. The transaction structure already supports deploys.**
`midnight-ledger/ledger/src/structure.rs:3027`:

```rust
pub enum ContractAction<P: ProofKind<D>, D: DB> {
    Call(Sp<ContractCall<P, D>, D>),
    Deploy(Sp<ContractDeploy<D>, D>),
    Maintain(MaintenanceUpdate<D>),
}
```

with `deploys()` iterators at `:1586` and `:1690`. A deploy is already a first-class
transaction action alongside a call.

**2. Contract addresses are content-addressed and fully deterministic.**
`structure.rs:2763-2782`:

```rust
pub struct ContractDeploy<D: DB> {
    pub initial_state: ContractState<D>,
    pub nonce: HashOutput,
}

impl<D: DB> ContractDeploy<D> {
    pub fn address(&self) -> ContractAddress {
        let mut writer = digest_io::IoWrapper(Sha256::new());
        tagged_serialize(self, &mut writer).expect("...");
        ContractAddress(HashOutput(writer.0.finalize().into()))
    }
}
```

The address is `SHA-256(tagged_serialize(initial_state, nonce))`. No transaction position,
no deployer identity, no sequence number. This is *very* good news — the address is a pure
function of data the deploying transaction already contains. It also raises immediate
questions you should chase: `ContractState` includes the operation→verifier-key map, so the
address commits to the deployed contract's *code*; the `nonce` is deployer-chosen, so think
about collision and front-running; and SHA-256 over a full serialized `ContractState`
in-circuit would be brutally expensive, so the interesting design question is what the
circuit must *prove* about the address rather than *compute*.

**3. There is no deploy claim in `Effects`.** The effects array is exactly 9 slots
(listed in Part 0) and slot 3 is `claimed_contract_calls`. There is a
`Kernel.claimContractCall` ledger op (`compact/compiler/midnight-ledger.ss:195-211`,
writing effects[3]) and **nothing analogous for deploys**. Since `Effects` is decoded
structurally as a fixed 9-element array (`onchain-runtime/src/context.rs:776-841`) and
compared for equality on replay (`ledger/src/semantics.rs:1452-1461`), adding a deploy
claim is a wire-format change plus a `TranscriptVersion` bump
(`onchain-runtime/src/transcript.rs:41-65`). Confirm this and scope it.

## What to investigate

**In `midnight-js`:** the current deploy path end to end. How is `ContractState` built, how
is the initial ledger state produced from the Compact `constructor`, how are verifier keys
attached, what does `deployContract` do, and what is the provider/wallet split? Understand
what a deploy *is* off-chain before proposing to move part of it on-chain.

**In `midnight-ledger`:** how a `ContractDeploy` is validated (`ledger/src/verify.rs`,
`semantics.rs` around `:2240`); the binding-commitment scheme
(`ContractCall::public_inputs`, `binding_input`, `verify.rs:1946-1990`) and how a deploy
would join it; whether one segment's call and deploy can reference each other; how
`ContractCallPrototype` / `construct.rs` assembles a transaction and where a
circuit-initiated deploy would slot in; the `ckpt` guaranteed/fallible split
(`construct.rs:724-799`) and which side a deploy must land on.

**In `compact`:** how cross-contract calls work today — `desugar-contract-calls`
(`compiler/circuit-passes/`, pass #46 in `passes.ss`), which expands a call into a
`contract-call` witnessing `cc-rand`/`ep-mod`/`ep-div`, a `transientCommit`, and a
`kernel.claimContractCall`. That is the closest existing analogue to what you want and it
is the template. Also read `coips/coip-0002.md` (contract types) and `coips/coip-0003.md`
(dynamic discovery of contract implementation code) — 0003 in particular is adjacent and
may already answer part of this.

## The design questions I'd want answered

1. **What does the circuit have to prove about the new address?** It cannot cheaply compute
   SHA-256 over a serialized `ContractState`. Options: the address arrives as a witness and
   the ledger cross-checks it against the deploy in the same transaction (an *effects*-style
   claim); or a commitment scheme like the one `claimContractCall` already uses. Work out
   which, and what it costs.
2. **Where does the deployed contract's identity come from?** A Compact circuit deploying
   "an instance of contract `Foo`" needs a compile-time reference to `Foo`'s
   verifier keys and initial ledger layout. Is `Foo` a *compile-time* argument (a
   monomorphized parameter) or a runtime value? The totality invariant strongly suggests
   compile-time — say so explicitly if you agree.
3. **How is the initial state produced?** Today the `constructor` runs off-chain in
   TypeScript. For in-circuit deployment, the initial state must be either computed
   in-circuit, or fixed at compile time and parameterized by a small number of values.
   Which, and what's the cost curve?
4. **This is the ∃-introduction form.** Compact today can *use* values of `contract` type
   but cannot *create* them. Dynamic deployment is precisely "let Compact pack an
   existential" — a concrete implementation plus an interface, yielding a value of contract
   type. Frame the feature that way and check what falls out: what's the typing rule, what
   is the resulting value's type, and does it need to be distinguishable from an address
   that came in from TypeScript?
5. **Replay and determinism.** If a deploy nonce comes from a witness, the address is a
   private choice with a public consequence. What must be pinned so replay is
   deterministic, and what happens if two transactions in a block deploy the same content?
6. **Storage and cost.** Who pays for the new contract's state? How does the cost model
   account for a deploy initiated inside a call?

## Deliverable

A design document, written to
`$HOME/mnt/compact/proposals/dynamic-deployment-design.md` (also send it to the user with
`SendUserFile`, then `device_commit_files` it to that path). Sections: what a deploy is
today, end to end; the concrete gaps (VM, effects, transcript version, binding, compiler,
SDK) each with file:line; two or three candidate designs with honest trade-offs; what it
costs in gas, proof width, and transaction bytes; what it would break; and the open
questions you couldn't settle. Say explicitly whether the feature is admissible under the
totality invariant.

---
---

# PART 2 — First-class ADTs

**The goal:** be able to pass ledger ADTs around as values in circuit — e.g.
`circuit transfer(from: Cell<Uint<64>>, to: Cell<Uint<64>>, amount: Uint<64>)`.

## Head start — the shape of the problem

Today there are **zero** first-class ADT values. The prohibition is the `Non-ADT-Type`
predicate (`compact/compiler/analysis-passes/infer-types.ss:305-320`) enforced at eight
sites: circuit arguments (`:1033`), return types (`:1036`), vector elements (`:1046`),
tuple elements (`:1064`), struct fields (`:1070`), contract-circuit arg/return types
(`:1053-1058`), plus "cannot export alias for ADT types" (`:1026`) and "type is not
serializable" (`expand-serialize.ss:205`).

The TypeScript backend contains two explicit FIXMEs anticipating exactly your change:

- `typescript-passes/print-typescript.ss:281-284`: *"at present, we can assume that whenever
  we pass a value of some public-adt as a query argument, it must be the result of
  `default<public-adt>`… **if we generalize to allow first-class public-adt values, this
  code will no longer be valid**."*
- `print-typescript.ss:2571-2574`: *"this should not appear in the output at present, but
  might if we implement first-class ADT values."*

**The single most important thing this inquiry must do is disambiguate what "first-class"
means**, because there are three readings with radically different feasibility:

| Reading | What it means | Feasibility |
|---|---|---|
| **(a) Compile-time reference** | Passing an ADT means passing a *path* (a lens), resolved by monomorphization. Circuits become parameterized over paths. | **Admissible.** Preserves the totality invariant. This is almost certainly what users actually want. |
| **(b) Runtime reference** | A dynamic path. | Needs VM changes. `Op::Idx { path: Array<Key> }` bakes the path *length* and the literal-vs-`Key::Stack` pattern into the opcode nibble (`ops.rs:509-522`). `Key::Stack` makes a *key* dynamic; it does not make a *path shape* dynamic. |
| **(c) Copied value** | Materialize the ADT's contents into the circuit. | **Impossible in general** — a `Map` is unbounded, so it has no static size and no `Val` kind. Possible only for bounded stores, and then it's a different feature (a "snapshot" operation). |

Establish this taxonomy early and hold the line on it; a lot of confused design in this area
comes from sliding between the three.

## What to investigate

**In `compact`:** how paths are assigned and propagated —
`analysis-passes/determine-ledger-paths.ss:18-51` (packs ledger fields into a ≤15-ary
B-tree of static indices) and `analysis-passes/propagate-ledger-paths.ss` (folds an
accessor chain into path indices + dynamic key expressions + one terminal `adt-op`; enforces
`Map`-only nesting at `:44` and asserts nesting is always exactly `lookup(key)` at
`:159-165`). Then the ADT machinery: `compiler/ledger.ss:44-222` (the DSL),
`compiler/midnight-ledger.ss` (the table), `compiler/vm.ss` (the VM expression
sub-language). Then how `tadt` carries its op table inside the type
(`compiler/langs.ss:803-804`) and how ops are found (`find-adt-op`,
`infer-types.ss:790-833`). Note that `expand-modules-and-types.ss:685-687` renames `Cell` to
`__compact_Cell` specifically so users cannot write it, and `:1158-1171` wraps plain ledger
field types in `Cell` implicitly.

**In `midnight-ledger`:** the `Idx`/`Ins` opcode encoding (`onchain-vm/src/ops.rs:156-260`,
`:460-524`) and semantics (`vm.rs:182-239`, `:1002-1046`) — specifically what is static and
what can be dynamic; the cache machinery (`vm.rs:34-107`, `CacheKey`) since path sharing
interacts with the `*c` cached opcode variants and therefore with cost; and the `Dup`/`Swap`
nibble reach, which is what breaks when paths get long.

**In `midnight-js`:** how `queryLedgerState` is invoked and what the generated
`contract/index.js` passes it (a *literal* array of ops — see any
`test-contracts/*/.build/contract/index.js` for a worked example). The JS side also assumes
static paths; find out how hard that assumption is.

## The design questions I'd want answered

1. **Nail the taxonomy above**, with evidence, and pick a target.
2. **If (a): what is the type of a path?** Under the proposed kind system a `Store` self is
   a compile-time lens. So `Cell<Uint<64>>` as a circuit parameter is a *`Store`-kinded
   parameter*, monomorphized per call site exactly like a generic type argument is today.
   Does that mean ADT parameters are simply a new kind of generic parameter — and is the
   existing frob/instance-table machinery (`make/register-frob`,
   `expand-modules-and-types.ss:418-432`) enough to implement it? I suspect yes; check.
3. **Depth budgets compose.** If a circuit takes a `Cell<T>` parameter and the caller passes
   `m.lookup(k).inner`, the callee's emitted `idx`/`ins`/`dup` counts depend on the caller's
   path length. Today `(ins [cached #t] [n (length f)])` is computed at expansion. With
   parameters, the budget check has to happen after specialization — or, better, `Store`
   types get **depth indices** so it's checkable at declaration. Work out which.
4. **Aliasing.** `transfer(from, to, amount)` with `from == to` is a real hazard: the two
   paths may denote the same place, and the emitted read/modify/write sequences will
   interleave incorrectly. Does the design need a distinctness obligation, a linear/affine
   discipline, or a documented "last write wins"? This is the question I'd expect to be
   hardest and most easily overlooked.
5. **Disclosure.** A path is inlined into the opcode stream and therefore public. If a path
   contains a dynamic key (`Map.lookup(k)`), passing the ADT passes `k` — which is public.
   Confirm and state the typing rule.
6. **Return types and storage.** Can a circuit *return* a path? Can a path be stored in
   ledger state (an ADT holding a reference to another ADT)? Both are almost certainly no
   under the totality invariant — but say why, precisely.
7. **How much of this is subsumed by user-defined stores?** The prior design work proposes
   letting users define their own ledger ADTs over five primitive store formers. Many
   motivating examples for "first-class ADTs" may actually be requests for *composition*
   rather than for *values*. Test a handful of real user requests against both framings and
   report which ones each solves.

## Deliverable

A design document, written to `$HOME/mnt/compact/proposals/first-class-adts-design.md` (also
`SendUserFile` it, then `device_commit_files` to that path). Sections: what is prohibited
today and where (with file:line for all eight sites); the three-way taxonomy with a
recommendation; the proposed typing rules; the aliasing story; the depth-budget story; what
changes in the compiler, the generated JS, and the VM (if anything); worked examples of the
motivating use cases; and what you'd rule out and why. Be explicit about which parts require
the `Val`/`Store` kind reform as a prerequisite and which stand alone.
