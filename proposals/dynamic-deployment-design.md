# Dynamic contract deployment in Compact

*Design exploration, not a CoIP. Companion to `traits-design-space.md` and
`coherent-type-landscape.md`. Citations verified against the working trees on 2026-08-28;
anything I am inferring rather than reading is marked **INFERRED**.*

---

## 0. The short version

**The feature is admissible under the totality invariant, and the reason is worth stating
before anything else: the circuit should not compute the new contract's address. It should
*claim* it, exactly the way a cross-contract call claims its callee, and let the ledger
cross-check the claim against a `ContractDeploy` sitting in the same transaction.**

Four facts, established below, collapse most of the design space:

1. **Content-addressing does the cryptographic work for free.** The address is
   `SHA-256(tagged_serialize(ContractDeploy { initial_state, nonce }))`
   (`ledger/src/structure.rs:2776-2782`). So an address *is* a commitment to the child's
   code, its initial state, and the nonce, all at once. A circuit that pins the address has
   thereby pinned everything. It does not need to recompute the hash to get that.

2. **The ledger already has the machinery to check a claim of this shape.**
   `effects_check` (`ledger/src/verify.rs:1441`) does exactly one thing for cross-contract
   calls: it builds a multiset of *claimed* calls from every transcript, a multiset of
   *real* calls from every action, and asserts `real_calls.has_subset(&claimed_calls)`
   (`verify.rs:1656-1665`), plus a uniqueness check (`verify.rs:1632-1641`). A deploy claim
   is the same three lines against `ContractAction::Deploy`.

3. **In-circuit address derivation is not merely expensive — it is layout-coupled.** The
   serialization being hashed is not a field-order struct encoding. It is a
   topologically-sorted node list of a content-addressed DAG
   (`storage-core/src/arena.rs:1687-1778`), and the ledger's own code calls that encoding
   *unstable* in a comment (`verify.rs:1990`). Putting it inside a proving circuit welds
   the circuit to a storage-engine internal. §5.2 works through why the obvious
   optimisation almost works and should still be rejected.

4. **The constructor is not in the trusted computing base, and this is the fact most likely
   to be assumed away.** It has no entry point, so no verifier key, so no proof
   (`print-typescript.ss:1679-1697`); the chain never re-executes it, it just inserts the
   submitted state (`semantics.rs:1519`). A deploy is therefore closer to accepting a
   submitted state graph labelled with the code it claims to belong to than to running a
   constructor. Consequence: what the parent claims must pin the child's **initial state**,
   not merely its code — otherwise a prover ships authentic `BasicVault` code beside a
   forged state and the parent's registry records a vault that was never constructed. The
   fix is to deploy at the compile-time-constant default state the compiler already builds,
   and make `constructor` a proved circuit called in the same transaction (§5.1.1).

And one prerequisite, which is a language change rather than a ledger one:

5. **`deploy` is not expressible in today's surface syntax, and the missing piece is named
   in CoIP-0002's own rejected ideas.** `contract C { … }` declares an *existential*;
   packing one needs a concrete implementation, and a Compact implementation is an entire
   `.compact` file with no in-language name (`coip-0002.md:571-575`). §6 argues for the
   split CoIP-0002 deferred — `contract interface T` for the existential, `contract MyT { … }`
   for a named implementation — under which `deploy MyT(args) : MyT`, packing to `T` by
   subsumption. This also makes the implementation digest of fact 2 stop being a bolt-on
   security mechanism and become **the runtime representation of a nominal type** (§6.3).

What that buys, and what it costs:

| | Design A (claimed deploy) | Design B (in-circuit address) | Design C (derived address) |
|---|---|---|---|
| New crypto | none | SHA-256 over a DAG encoding | one new address scheme |
| Added proof width | ~10 public inputs | ~10⁵ constraints | ~1 hash |
| Consensus change | one `Effects` slot + one `effects_check` clause | none | address derivation (`contract-deploy[v7]`) |
| Address known before submission | no | no | **yes** |
| Front-running exposure | none | none | address squatting |

Design A is the one to build. Design C is the one to keep in view, because predictable
addresses unlock patterns A cannot express, and because the day you want them is the day
the address scheme has to change.

And one finding that reframes the whole feature: **a factory is transaction-byte-bound, not
gas-bound and not proof-bound.** The child's entire `ContractState` — including a verifier
key per entry point — is inlined into the transaction. With
`transaction_byte_limit = 1 MiB` (`structure.rs:1271`) and
`max_contract_metadata_size = 50_000` per entry point (`structure.rs:1282`), a factory
deploying a non-trivial child gets a handful of children per transaction at best, possibly
one. §7.3. That is an argument for deploy-by-reference (§5.4) long before it is an argument
for anything else.

---

## 1. What a deploy is today, end to end

### 1.1 Off-chain: the constructor runs on the deployer's machine

The Compact compiler never emits anything called a deploy. `grep -rn "ContractDeploy"
compiler/` returns nothing. What it emits is an `initialState` method on the generated
contract class (`compiler/typescript-passes/print-typescript.ss:1700-1764`):

```scheme
(format "async initialState(...~a) {" args)
...
2 (format "const ~a = new __compactRuntime.ContractState();" state)
...
  2 (format "const context = __compactRuntime.createCircuitContext({circuitId: 'constructor', contractAddress: __compactRuntime.dummyContractAddress(), ...});")
...
  2 (format "~a.data = new __compactRuntime.ChargedState(context.callContext.currentQueryContext.state.state);" state)
  2 "return {"
  4 (format "currentContractState: ~a," state)
  4 "currentPrivateState: context.callContext.currentPrivateState,"
  4 "currentZswapLocalState: context.callContext.currentZswapLocalState"
```

Note `dummyContractAddress()` at `print-typescript.ss:1746`. **At constructor time the
contract has no address**, and the compiler knows it. Address assignment is not a
compiler concern and never has been. This is the seam the feature has to target.

Two constructor restrictions already on the books, both relevant later:

- `analysis-passes/reject-constructor-emit.ss` — a constructor may not emit an event, and
  the check is transitive through called circuits.
- `analysis-passes/reject-constructor-cc-calls.ss:19-20` — a constructor may not make a
  cross-contract call. The pass carries a TODO: *"later we might want to allow constructors
  to call pure circuits from an external contract."*

### 1.2 Off-chain: the SDK wraps it

`ContractExecutable.initialize` (in the installed `@midnight-ntwrk/compact-js`,
`dist/esm/effect/ContractExecutable.js:81-131`) calls
`contract.initialState(createConstructorContext(...), ...args)`, then does two things to
the returned `ContractState`:

```js
const verifierKeys = yield* zkConfigReader.getVerifierKeys(Contract.getProvableCircuitIds(contract));
for (const [provableCircuitId, verifierKey] of verifierKeys) {
    const operation = contractState.operation(provableCircuitId);
    operation.verifierKey = verifierKey.value;
    contractState.setOperation(provableCircuitId, operation);
}
const [cma, signingKey] = yield* this.createMaintenanceAuthority(keyConfig.getSigningKey());
contractState.maintenanceAuthority = cma;
```

Verifier keys come from a `ZKConfigProvider` (`packages/types/src/zk-config-provider.ts:34-64`),
concretely from files on disk in the node case
(`packages/node-zk-config-provider/src/node-zk-config-provider.ts:140-150`, reading
`<dir>/keys/<circuitId>.verifier`). **They are build artifacts of the child contract, known
at the parent's compile time if the parent names the child at compile time.** That is the
single most useful fact in this section.

The `ContractDeploy` is then constructed at `packages/contracts/src/utils/ledger-utils.ts:72-88`:

```ts
const contractDeploy = new ContractDeploy(toLedgerContractState(contractState));
return [
  contractDeploy.address,
  fromLedgerContractState(contractDeploy.initialState),
  Transaction.fromParts(getNetworkId(), zswapStateToOffer(...), undefined,
                        Intent.new(ttlOneHour()).addDeploy(contractDeploy))
];
```

and the nonce is chosen inside that constructor, from the OS CSPRNG
(`ledger-wasm/src/contract.rs:20-40` → `ledger/src/construct.rs:291-297`):

```rust
pub fn new<R: Rng + CryptoRng + ?Sized>(rng: &mut R, initial_state: ContractState<D>) -> Self {
    ContractDeploy { initial_state, nonce: rng.r#gen() }
}
```

Then the ordinary three-step submission
(`packages/contracts/src/submit-tx.ts:81-91`): `proveTx` → `balanceTx` → `submitTx`.

### 1.3 On-chain: structure

```rust
// ledger/src/structure.rs:2758-2767
#[tag = "contract-deploy[v6]"]
pub struct ContractDeploy<D: DB> {
    pub initial_state: ContractState<D>,
    pub nonce: HashOutput,
}

// ledger/src/structure.rs:2776-2782
pub fn address(&self) -> ContractAddress {
    let mut writer = digest_io::IoWrapper(Sha256::new());
    tagged_serialize(self, &mut writer).expect("In-memory serialization should succeed");
    ContractAddress(HashOutput(writer.0.finalize().into()))
}
```

`ContractState` (`onchain-state/src/state.rs:748-756`, tag `contract-state[v8]`) is
`{ data: ChargedState, operations: HashMap<EntryPointBuf, ContractOperation>,
maintenance_authority: ContractMaintenanceAuthority, balance: HashMap<TokenType, u128> }`.

Three structural observations that matter:

- **`ContractDeploy` is not generic over `ProofKind`.** Contrast `ContractCall<P, D>`. A
  deploy has no proof, no transcript, no communication commitment.
- **The address is computed, never declared.** There is no field to check against. Nothing
  can be wrong about it; it is a function of the bytes.
- **The nonce is entirely unconstrained.** `ContractDeploy::well_formed` never reads
  `self.nonce`; a repo-wide grep finds no uniqueness or replay check on it. Its only effect
  is to perturb the hash.

### 1.4 On-chain: validation

```rust
// ledger/src/verify.rs:1764-1806 (abridged)
pub(crate) fn well_formed(&self, ref_state: &impl StateReference<D>) -> Result<(), MalformedTransaction<D>> {
    self.initial_state.well_formed(self.address())?;
    if self.initial_state.balance.iter().any(|bal| *bal.1 > 0) {
        return Err(... MalformedContractDeploy::NonZeroBalance ...);
    }
    let rechecked_state = ChargedState::new((*self.initial_state.data.get()).clone());
    if rechecked_state != self.initial_state.data {
        return Err(... MalformedContractDeploy::IncorrectChargedState);
    }
    ref_state.param_check(false, |params| {
        check_entry_point_metadata_sizes(&self.initial_state, params.limits.max_contract_metadata_size) ...
    })
}
```

Four checks, all local: every operation carries a verifier key
(`verify.rs:415-438`, `VerifierKeyNotSet`); `maintenance_authority.counter == 0`
(`verify.rs:401-412`); zero initial balance; charged-state consistency; metadata size.

**A deployed contract must start with a zero balance.** So "deploy and fund atomically" is
not expressible today even at the transaction level — funding is necessarily a second
action.

**And — this is the fact the rest of the document turns on — the constructor is not in the
trusted computing base.** Nothing above re-executes it. `apply` simply inserts the
submitted state: `res.contract = res.contract.insert(addr, deploy.initial_state.clone())`
(`semantics.rs:1519`). The charged-state check at `verify.rs:1774-1780` is an internal
consistency check on the submitted value, not a recomputation of it.

Nor is the constructor proved. `set-operations`
(`compiler/typescript-passes/print-typescript.ss:1679-1697`) emits a `ContractOperation`
only for exported circuits whose names are in `(proof-circuit-names)`:

```scheme
(if (memq (string->symbol external-name) (proof-circuit-names))
    (cons* 2 (format "~a.setOperation('~a', new __compactRuntime.ContractOperation());"
                     state external-name)
           q*)
    q*)
```

The constructor is emitted separately, as `initialState` (`print-typescript.ss:1723-1764`),
and never receives a `setOperation` call. **No entry point, therefore no verifier key,
therefore no proof.** `ContractDeploy` has no proof field either (§1.3), and contributes
nothing to proof-verification cost (`structure.rs:2007-2015`).

So the constructor is a *convenience for the honest deployer*, not a guarantee to anyone
else. A deploy is closer to accepting a submitted state graph, labelled with the code it
claims to belong to, than to running a constructor. Every design below has to earn back the
guarantee that a naïve reading assumes is already there.

### 1.5 On-chain: application

```rust
// ledger/src/semantics.rs:1509-1520
ContractAction::Deploy(deploy) => {
    let addr = deploy.address();
    if !whitelist_matches(&context.whitelist, &addr) || guaranteed {
        continue;
    } else {
        if res.contract.contains_key(&addr) {
            return Err(TransactionInvalid::ContractAlreadyDeployed(addr));
        }
        ...
        res.contract = res.contract.insert(addr, deploy.initial_state.clone());
```

That `|| guaranteed { continue; }` is the most load-bearing line in the whole feature.
**A deploy is skipped entirely during the guaranteed pass and only ever applied in the
fallible pass.** `ContractAction::Maintain` has the same guard (`semantics.rs:1552`);
`ContractAction::Call` does not (`semantics.rs:1434-1450`).

Consequences, and they are strict:

- A parent circuit that wants to *call into* the child it just deployed can only do so from
  its **fallible** transcript — i.e. after at least one `Op::Ckpt`
  (`onchain-vm/src/ops.rs:259`; the split is `PreTranscript::split_at`,
  `construct.rs:762-799`; the Compact surface is `Kernel.checkpoint`,
  `compiler/midnight-ledger.ss:212-215`).
- A deploy claim appearing in a *guaranteed* transcript would be a claim about something
  that has not happened yet and may never happen — the guaranteed section is never rolled
  back. §6.3 argues the claim must therefore be fallible-only.

There is precedent for exactly this kind of containment rule already:
`sequencing_context_check` (`verify.rs:1046+`) enforces *"If the call to `b` is in `a`'s
guaranteed section, it must contain only a guaranteed section."*

### 1.6 On-chain: cost, and what a deploy is *not* charged for

```rust
// ledger/src/structure.rs:2240-2245
ContractAction::Deploy(deploy) => {
    // Contract exists check
    f_cost += model.map_index(EXPECTED_CONTRACT_DEPTH);
    // Contract insert
    f_cost += model.map_insert(EXPECTED_CONTRACT_DEPTH, false)
        + model.tree_copy(Sp::new(deploy.initial_state.clone()));
}
```

`EXPECTED_CONTRACT_DEPTH = 32` (`structure.rs`). `tree_copy`
(`onchain-vm/src/cost_model.rs:252-267`) prices the whole serialized node list by byte
count. So the deploy is charged, on the fallible side, roughly proportional to the size of
the child's state — and there is **no deposit and no rent**; it is a one-time fee.

And it is charged nothing for proving, because it has nothing to prove
(`structure.rs:2007-2015`):

```rust
ContractAction::Call(call) => { cost += model.proof_verify(call.public_inputs(...).len()); }
ContractAction::Maintain(upd) => { ... }
_ => {}                      // ContractAction::Deploy: zero
```

### 1.7 Confirmed absences

Searched all three trees. There is today **no** mechanism at any layer for a contract to
deploy a contract:

| Layer | Absence | Evidence |
|---|---|---|
| Impact VM | no deploy opcode | full `Op` enum, `onchain-vm/src/ops.rs:156-259` |
| Effects | no deploy claim | 9 fields, `onchain-runtime/src/context.rs:640-656` |
| Ledger | no deploy↔call binding | `ContractDeploy` has no proof field; `construct.rs:624-643`'s `references()` returns `false` for every non-`Call` action |
| Compact | cannot create a contract value | `doc/compact-reference.mdx:784-789`; `coips/coip-0002.md:278-283` |
| Compact runtime | constructor unreachable from a cross-contract call | `compact/runtime/src/module.ts:37-40`: *"Only `provableCircuits` is reachable from a cross-contract call"* — `initialState` is not in `ContractInstance` |
| midnight-js | one deploy per `deployContract` | `ledger-utils.ts:77`, singular `new ContractDeploy(...)` |
| tests | none | `ledger/tests/contract_deployment.rs` is 138 lines, two tests, both standalone deploys with no calls |

`Intent` *can* structurally hold several deploys and several calls
(`construct.rs:331-357`), so the transaction format is not the obstacle. Nothing else is
in place.

---

## 2. Admissibility under the totality invariant

> **Totality invariant.** Every type has a size that is a closed term in the size algebra
> at the point of use, and every elimination is a fold over a finite index. Therefore every
> program unrolls to a straight-line instruction sequence whose length is a closed term.
> — `coherent-type-landscape.md` §0

**Verdict: admissible, under one condition that the invariant itself supplies.**

Take the three faces of the invariant in turn.

*A finite proving circuit exists.* A `deploy` expression emits a fixed number of opcodes —
under Design A, one `Kernel` update sequence of nine instructions (§5.1). It contains no
loop, no backward jump, no indirection. Deploys inside `for` are unrolled by
`unroll-loops` like everything else, so "how many deploys" is a closed term. ✅

*Declared gas is meaningful.* The claim's opcodes are counted like any others; the deploy's
own cost is already modeled off-VM (§1.6) and does not enter `transcript.gas`. ✅

*The opcode stream is a valid ZK public input.* Unchanged — the claim is ordinary
`idx`/`ins` traffic against a new array slot. ✅

**The condition the invariant forces:** *which* contract is being deployed must be a
compile-time choice. This answers design question 2 with a reason rather than a preference.
A runtime-selected implementation would mean the initial state's shape, the verifier key
set, and therefore the expected implementation digest are not closed terms — and under
Design A the circuit's only real obligation is to compare a claimed digest against a
literal (§5.1). If the literal is not a literal, there is nothing to compare against, and
the feature degenerates into "the prover may deploy anything and call it a Foo."

So: `deploy Foo(args)` where `Foo` is a compile-time contract name, monomorphized by
`expand-modules-and-types` like any other generic parameter. Not `deploy c(args)` for a
runtime `c`. This is the same conclusion `traits-design-space.md` §2.1 reaches about
dispatch — *everything must monomorphize* — arriving from a different direction, which is
mild evidence it is the right one.

---

## 3. The template: what `claimContractCall` actually does

This is the pattern to copy, and it is worth being precise about it, because the
interesting property is that **the circuit proves almost nothing**.

### 3.1 Compiler side

`desugar-contract-calls` (`compiler/circuit-passes/desugar-contract-calls.ss`, 152 lines,
last pass in `circuit-passes.ss:62-77`) rewrites one statement into three
(`desugar-contract-calls.ss:18-29`):

```scheme
;; A statement
;;   (= test (V* ...) (contract-call ... ((recv* ...) tcontract) triv* ...))
;; becomes three statements:
;;   (= test (V* ... cc-rand ep-mod ep-div) (contract-call ... tcontract'))
;;   (= test (comm) (call <transientCommit> triv* ... V* ... cc-rand))
;;   (= test () (public-ledger ... claimContractCall recv* ... ep-mod ep-div comm)).
```

`ep-mod`/`ep-div` are a 256-bit entry-point hash split base-256 into `Field<2^8>` and
`Field<2^248>` limbs, because the scalar field is 254 bits
(`extend-ret-type`, `:93-101`). `cc-rand` is a blinding nonce.

And the crucial part — `compiler/zkir-passes/print-zkir.ss:679-688` emits, for the extended
`contract-call`, nothing but `private_input` gates:

```scheme
(for-each
  (lambda (type var)
    (if (equal? test-idx (hashtable-ref literal-ht 1 #f))
        (print-gate "private_input" '[guard null])
        (print-gate "private_input" `[guard ,test-idx]))
    (let ([index (new-var! var)]) (constrain-type type index) index))
  prim-type* var-name*)
```

**The callee's execution is not proved inside the caller's circuit at all.** Its results,
and the three extra limbs, are unconstrained private inputs. The one piece of real circuit
work is `transientCommit`, a Poseidon fold (`zkir-passes/print-zkir.ss:201-208`, emitting a
single `transient_hash` gate) over `[cc-rand, args…, results…]`, producing `comm`.

### 3.2 Ledger side

`claimContractCall` (`compiler/midnight-ledger.ss:195-211`) writes the triple
`(addr, entry_point, comm)` into effects slot 3:

```scheme
((swap [n 0])
 (idx [cached #t] [pushPath #t] [path (list (align 3 1))])
 (dup [n 0]) (size)
 (push [storage #f] [value (state-value 'cell (rt-aligned-concat addr entry_point comm))])
 (concat [cached #t] [n 160])
 (push [storage #f] [value (state-value 'null)])
 (ins [cached #t] [n 2])
 (swap [n 0]))
```

and `effects_check` (`ledger/src/verify.rs:1441`) turns that data into a guarantee:

```rust
// verify.rs:1620-1641 — collect claims, reject duplicates
let claimed_calls: MultiSet<(u16, (ContractAddress, HashOutput, Fr))> = transcripts.iter()
    .flat_map(|(segment, _, t, _)| t.effects.claimed_contract_calls.iter().map(|call| {
        let (_seq, addr, hash, fr) = &call.into_inner(); (**segment, (*addr, *hash, *fr)) }))
    .collect();
...
if !(duplicate_claimed_calls.is_empty()) {
    return Err(... EffectsCheckError::ClaimedCallsUniquenessFailure(duplicate_claimed_calls));
}

// verify.rs:1642-1665 — collect reality, assert containment
let real_calls: MultiSet<(u16, (ContractAddress, HashOutput, Fr))> = calls.iter()
    .map(|(segment, call)| (*segment,
        (call.address, call.entry_point.ep_hash(), call.communication_commitment)))
    .collect();
// Any claimed call must also exist within the same segment
if !(real_calls.has_subset(&claimed_calls)) {
    return Err(... EffectsCheckError::RealCallsSubsetCheckFailure(...));
}
```

plus `sequencing_check` (`verify.rs:1292`), whose `call_sequencing_check`
(`verify.rs:980-1018`) enforces that a claimed callee sits at a strictly greater position
in the intent's action list than its caller.

### 3.3 The lesson

> **A "claim" is a cheap, unconstrained assertion in the circuit that the ledger promotes
> into a hard guarantee by cross-checking it against the transaction's own contents.**

The circuit is not a verifier of the other party. It is a *declarer of intent*, and
`effects_check` is what makes intent binding. The proof commits to the claim only because
the claim lives in the transcript, and the transcript is field-repr'd into
`public_inputs` (`verify.rs:1946-1970`).

That is the entire mechanism a deploy needs. It is already built, twice over — once for
calls, once each for nullifiers, shielded spends and receives, and unshielded spends. A
deploy is the sixth instance of a pattern with five existing instances.

---

## 4. The concrete gaps

| # | Layer | Gap | Site |
|---|---|---|---|
| 1 | Impact VM | none — no VM change is required | `onchain-vm/src/*.rs` contains zero occurrences of `effects`; slots are a runtime convention (`context.rs:975-981`) |
| 2 | Effects | no slot for deploy claims | `onchain-runtime/src/context.rs:640-656` |
| 3 | Effects decode | hard-coded `arr.len() == 9` | `onchain-runtime/src/context.rs:810` |
| 4 | Effects encode | 9-element `vec![…]` | `onchain-runtime/src/context.rs:699-774` |
| 5 | Effects serde mirror | hand-written 9-field `SerdeEffects` | `onchain-runtime/src/context.rs:351-363`, `:365-429`, `:431-507` |
| 6 | Effects TS mirror | hand-written `.d.ts` | `onchain-runtime-wasm/onchain-runtime-v4.d.ts:356+` |
| 7 | Binding input | `vec![0u8; 20]` — the serialized length of `Effects::default()`, hard-coded | `ledger/src/verify.rs:1987-1991` |
| 8 | Cost model | `stack_setup_cost_for_effects` enumerates all 9 maps and their key lengths | `ledger/src/structure.rs:1194-1230` |
| 9 | Compact | 9 hand-written `(align N 1)` literals, no named constants | `compiler/midnight-ledger.ss:168,179,190,204,225,270,311,350,389` |
| 10 | `effects_check` | no `real_deploys` clause | `ledger/src/verify.rs:1441-1730` |
| 11 | `sequencing_check` | `references()` returns `false` for `Deploy` | `ledger/src/construct.rs:624-643` |
| 12 | Transcript version | bump, and it is currently only *checked* for legacy contracts | `onchain-runtime/src/transcript.rs:65-67` (`{major:2, minor:3}`); `ledger/src/verify.rs:1911-1930` |
| 13 | Compiler | no `deploy` surface form, no desugaring pass | new pass after `desugar-contract-calls`, `circuit-passes.ss:62-77` |
| 14 | Compiler (TS) | `contract-call` is lowered *twice*, independently | `print-typescript.ss:3057-3096` vs `desugar-contract-calls.ss` — a deploy needs both |
| 15 | Compact runtime | `initialState` unreachable from a call | `compact/runtime/src/module.ts:37-40` |
| 16 | midnight-js | no deploy+call assembly | `ledger-utils.ts:72-88` uses `Transaction.fromParts`; calls use `fromPartsRandomized` (`:205-210`) |
| 17 | midnight-js | `Intent::new` always puts deploys *after* calls | `ledger/src/construct.rs:331-357` |

Gaps 3–9 are the "10th effects slot" tax, and they deserve their own paragraph, because
**three of them fail silently**:

- **#7 is the dangerous one.** `vec![0u8; 20]` is the byte length of a default `Effects`
  under the current 9-empty-collections shape, used as a placeholder when there is no
  guaranteed transcript. A 10th field changes that length. If the literal is not updated in
  lockstep, `binding_input` diverges between the has-transcript and no-transcript paths —
  a consensus bug with no compiler error. The comment above it even flags the encoding as
  *"unstable"*.
- **#5, #6, #9** are hand-maintained mirrors with no build-time link to the Rust struct. #9
  is cross-repo *and* cross-language: `grep -rln "Kernel" midnight-ledger/**/*.rs` returns
  nothing, so the Rust side has no symbolic knowledge that the Compact `Kernel` ADT exists.
  The only thing synchronising the two is convention.

Only #3 and the struct-literal call sites fail loudly.

**This is the strongest argument for Design A′ (§5.3), which avoids all of #3–#9.**

---

## 5. Candidate designs

### 5.1 Design A — a claimed deploy

**Surface.** The syntax below presumes the interface/implementation split argued for in §6
— `contract interface T` for today's contract types, `contract MyT { … }` for a *named*
implementation. That split is a precondition, not a garnish: without a name for a concrete
implementation there is no well-typed thing for `deploy` to take as an argument (§6.1).

```compact
contract interface Vault {
  circuit deposit(amount: Uint<64>): [];
}

contract BasicVault implements Vault {
  export ledger balance: Counter;
  constructor(owner: Bytes<32>) { … }              // a proved circuit; see §5.1.1
  export circuit deposit(amount: Uint<64>): [] { … }
}

contract VaultFactory {
  export ledger vaults: Set<Vault>;                // stores the ∃, not the impl

  export circuit createVault(owner: Bytes<32>): BasicVault {
    const v = deploy BasicVault(owner);            // : BasicVault  — ∃-introduction, §6.2
    vaults.insert(v);                              // packs to Vault by subsumption
    return v;                                      // caller keeps the concrete type
  }
}
```

**Kernel op.** A new `update`-class operation, in the shape of its five siblings:

```scheme
(function update claimContractDeploy
          ([addr Bytes32 (discloses "the address of a contract being deployed given by")]
           [impl_digest Bytes32 (discloses "the implementation digest of the contract being deployed")])
          Void
  "Require the presence of a contract deployment in the containing transaction, \
   with a matching address and implementation digest, not claimed by any other call."
  ((swap [n 0])
   (idx [cached #t] [pushPath #t] [path (list (align 9 1))])
   (dup [n 0]) (size)
   (push [storage #f] [value (state-value 'cell (rt-aligned-concat addr impl_digest))])
   (concat [cached #t] [n 128])
   (push [storage #f] [value (state-value 'null)])
   (ins [cached #t] [n 2])
   (swap [n 0])))
```

Nine opcodes, structurally identical to `claimContractCall`. Note the arguments are
necessarily public — `coherent-type-landscape.md` §3.3 establishes that every ledger-op
argument is inlined into the opcode stream and the opcode stream is a public input, so
`discloses` here is forced, not chosen. A deployment is a public act; that is correct.

**Effects.** Slot 9: `claimed_contract_deploys: HashSet<(u64, ContractAddress, HashOutput), D>`
— sequence number, address, implementation digest — mirroring
`ClaimedContractCallsValue = (u64, ContractAddress, HashOutput, Fr)` (`context.rs:578`).

**Ledger check.** One new clause in `effects_check`, after the calls clause at
`verify.rs:1665`:

```rust
let real_deploys: MultiSet<(u16, (ContractAddress, HashOutput))> = deploys.iter()
    .map(|(segment, d)| (*segment, (d.address(), impl_digest(&d.initial_state))))
    .collect();
if !(real_deploys.has_subset(&claimed_deploys)) {
    return Err(... EffectsCheckError::RealDeploysSubsetCheckFailure(...));
}
```

plus the duplicate check, verbatim from `verify.rs:1632-1641`.

**What `impl_digest` is, and why it is the whole design.** A hash over the child's
`operations` map — its entry-point names and verifier keys, i.e. its *code identity*. There
is precedent for hashing a verifier key already: midnight-js's `encodeContractKeyLocation`
uses `hashVerifierKey(op.verifierKey)` (`packages/contracts/src/utils/ledger-utils.ts:127-211`).

Why it is essential: content-addressing means the address alone pins everything — but the
*circuit does not know what address to expect*, so an address alone is an unconstrained
witness, and a malicious prover could claim any address and deploy anything under it. The
parent's state would then record a "Vault" that is not a Vault. The implementation digest
closes that hole for the price of **one equality against a compile-time literal**, because
the child's verifier keys are build artifacts known at the parent's compile time (§1.2).

So the circuit's total obligation is: witness `addr`; assert
`impl_digest == <literal>`; claim. That is why this design costs nothing.

**Initial state — and why a digest over `operations` alone is not enough.** The digest as
described binds *code*, not *state*. It is tempting to stop there, on the reasoning that
the child's constructor will establish its own invariants. §1.4 shows that reasoning is
wrong: the constructor is unproved, is never re-executed on chain, and is therefore no part
of the trusted computing base.

Spell out the attack, because it is easy to miss. A prover deploys **genuine** `Vault`
code — the verifier keys are authentic, `impl_digest` matches the literal, every check in
`ContractDeploy::well_formed` passes — alongside a hand-forged `data` that no run of
`Vault`'s constructor could ever have produced: balances pre-credited, an ownership cell
naming the attacker, a one-shot guard already flipped. The claim succeeds, the parent
records the address in `vaults`, and every later user who trusts the parent's registry is
trusting a Vault that was never constructed.

`deploy MyT(args)` must therefore mean *"a `MyT` whose starting state I have pinned"*, not
*"a `MyT`"*. §5.1.1 is how.

#### 5.1.1 Deploy at the default state; make the constructor a proved circuit

The pinnable state already exists, and the compiler already builds it — independently of
the constructor. `ledger-initializers` (`print-typescript.ss:1036-1061`) emits
`StateValue.newArray()` with a `newNull()` slot per top-level ledger field, and
`ledger-reset-to-default` (`:1063-1081`) then invokes each field's `resetToDefault` ADT op:

```scheme
(cons* 2 (construct-query src path-index* adt-formal* adt-arg*
                          (find-adt-op 'resetToDefault adt-op*) '()) ";" q*)
```

Only then does the constructor body run (`:1723-1764`). So **every contract has a
pre-constructor state that is a closed term in its ledger declarations alone**, with no
constructor involvement and therefore no untrusted computation in it.

That gives the whole design in one move:

> **Deploy is always at the default state. The constructor is an ordinary provable circuit,
> sequenced as a normal cross-contract call in the same transaction.**

Consequences, all of which simplify what came before:

- **The digest is always a compile-time literal.** The deployed `ContractState` is the
  default state plus `MyT`'s verifier keys — both closed terms — so `impl_digest` covers
  the *entire* state, not just `operations`, and the circuit's obligation is still one
  equality. The earlier split into a restrictive "zero-argument only" variant and a
  permissive "initialize" variant collapses: there is one form, and it has no restriction.
- **The parameterized part becomes proved.** §1.4's hole closes not by adding a check but
  by moving the constructor from an unproved off-chain computation into a circuit with a
  verifier key, executed under the ordinary transcript/replay discipline. This is a
  *security* argument, not an ergonomic one.
- **No new sequencing mechanism.** The constructor call is an ordinary `claimContractCall`;
  its uniqueness check and `call_sequencing_check` (`verify.rs:980-1018`) already exist and
  already enforce the required order.
- **`Kernel.self()` starts working in constructors.** Today it reads context slot 0
  (`compiler/midnight-ledger.ss:256-260`) while the constructor runs against
  `dummyContractAddress()` (`print-typescript.ss:1746`). As a circuit it runs against the
  real address.
- **The one-shot guard becomes derivable rather than hand-written.** `constructor` is
  already a distinguished declaration form — its own nanopass node, `Ledger-Constructor`,
  which is why `reject-constructor-emit.ss` can pattern-match on it — so the compiler owns
  it and can emit the flag cell and its check. And because the deploy claim pins the
  default state, in which that flag is `false` by construction, the guard is sound rather
  than merely conventional.

The atomicity is better than it first looks. Deploy and constructor-call land in the same
segment's fallible section, and nothing interleaves within a segment, so no third party can
reach the constructor first; the address is unpredictable until the deploy applies, because
the nonce is random (`construct.rs:291-297`). The derived guard is therefore defending only
against *later* transactions, which is exactly what it is good at.

Two costs, stated plainly. **It adds a proof to every deployment** — the constructor is free
today precisely because it is unproved — and proving is the expensive stage of the
pipeline. And **it raises a scope question the rest of this document cannot settle**: does
the *ordinary*, non-factory deploy path change too? §9.2.

**INFERRED:** I found no test exercising deploy-then-call in one intent;
`ledger/tests/contract_deployment.rs` has no such case.

**Private state.** An earlier draft flagged CoIP-0002's limitation 3 — *"circuits called
from other contracts must not rely on witness functions"* (`coip-0002.md:100-104`) — as a
blocker, since a constructor is exactly where private state is initialized. The witness
sublanguage now in design removes it. `local constructor` takes no arguments and every
party derives its own private state from the contract alone, so **a child's private state
is not a deployment artifact at all** — nothing about it has to be produced by whoever
deployed it, and joining a deployed contract requires nothing but its address
(`product/capsule-runtime/witness-language-for-multi-contract-systems.md`). That is a
better answer than the one this document could have reached on its own: the question does
not need resolving here, it dissolves.

**Ordering.** The deploy must precede the calling action in the intent's `actions` array,
because `apply_actions` threads one mutable `LedgerState` through a single ordered loop
(`semantics.rs:1421-1433`) and a call to a not-yet-inserted address fails with
`ContractNotPresent` (`semantics.rs:1502-1506`). `Intent::new` gets this wrong — it folds
calls first, then updates, then deploys (`construct.rs:331-357`) — so the SDK must use
`intent.add_deploy(d).add_call(c)` directly (`construct.rs:668-682`, `:599-650`). This is
construction-order convention, enforced nowhere. It should become an assertion.

**Guaranteed/fallible.** The claim must be fallible-only. §6.3.

### 5.2 Design B — compute the address in-circuit, and why not

The obvious idea: have the circuit derive `addr = SHA-256(tagged_serialize(deploy))` so no
ledger change is needed at all. SHA-256 *is* available in-circuit — it is exactly what
`persistentHash` compiles to (`compiler/zkir-v3-passes/reduce-to-zkir.ss:195-203`, emitting
a ZKIR `persistent_hash` instruction; `midnight-ledger/spec/zkir.md:380-381` describes it
as *"much more expensive in-circuit than `TransientHash` (SHA-256 vs Poseidon)"*), and
`sha256` is one of three chips enabled by default in the proving stack
(`midnight-zk/zk_stdlib/README.md:33`).

It still does not work, for a reason better than cost.

**The encoding is not a struct encoding.** `#[derive(Storable)]` does not generate a
field-order `Serializable`; it delegates to `Sp<T, D>`
(`storage-macros/src/lib.rs:144-152`), which serializes a **topologically-sorted node list
of a content-addressed DAG**, built with Kahn's algorithm
(`storage-core/src/arena.rs:1687-1778`), where each node is
`{ child_indices: Vec<u64>, data: Vec<u8> }` (`arena.rs:1853-1859`).

So what gets hashed is
`"midnight:" ++ "contract-deploy[v6]" ++ ":" ++ <u32 count> ++ node₀ ++ … ++ nodeₙ₋₁`,
and the node layout depends on the *shape of the child's state DAG*.

**The near-miss.** There is a real optimisation lurking here, and it is worth writing down
so that nobody rediscovers it and thinks it settles the question. The node list is emitted
leaves-first:

```rust
// storage-core/src/arena.rs:1767-1775
// We flip the index ordering, as it a) makes deserialization easier, and b) makes leaf
// nodes have smaller indexes, which is usually more sensible.
list.nodes[len - 1 - *idx as usize] = TopoSortedNode { ... };
```

The root is therefore **last**, and `ContractDeploy`'s root node carries the `nonce` at the
end of its `data` (the nonce is a `#[storable(base)]` inline field declared after
`initial_state`). Since SHA-256 is Merkle–Damgård, everything before the final block or two
is a *constant prefix* whose compression midstate could be precomputed at compile time —
reducing an in-circuit hash of hundreds of blocks to one or two compressions.

**Reject it anyway.** The precondition is that the constant prefix has a fixed length and a
fixed layout, and that means the circuit is welded to: the topological sort order, the
`u64` child-index encoding, the `Vec` length-prefix convention, the arena's node
granularity, and the exact tag string `contract-deploy[v6]`. The ledger does not treat any
of that as stable — `verify.rs:1990` says so in a comment about a *different* structure's
serialization: *"Backwards-compatible with `Effects::default` serialization, as this may be
unstable."* A storage-engine refactor that changes node granularity would silently
invalidate every deployed factory's verifier key.

> A circuit may depend on consensus rules. It must not depend on storage-layout internals.

Design B trades a small, explicit, versioned ledger change (one effects slot) for a large,
implicit, unversioned coupling. That is the wrong trade.

### 5.3 Design A′ — reuse the contract-call claim

The §4 table shows the 10th-slot tax is 7 sites, 3 of them silent. There is a way to avoid
all of it: **model a deploy as a claimed call to a reserved entry point.**

`ClaimedContractCallsValue` is already `(u64 seq, ContractAddress, HashOutput ep_hash,
Fr comm)`. Set `ep_hash = EntryPointBuf::from("<deploy>").ep_hash()`
(`onchain-state/src/state.rs:669-674`, a domain-separated `persistent_commit`), and
`comm = impl_digest` as a field element. Then:

- No `Effects` shape change. No transcript version bump. No `vec![0u8; 20]` hazard. No
  serde/`.d.ts`/Scheme mirrors to update. Gaps #3–#9 all vanish.
- `effects_check` needs one change: `real_calls` gains deploy-derived entries. The
  uniqueness check already covers them.
- Compact gets a new `Kernel` op that writes slot 3 with a constant `ep_hash` — no new
  `(align N 1)` literal.

**The cost is honesty.** A deploy is not a call. Concretely: `ContractCall::calls_with_seq`
(`structure.rs:2721-2745`) would report a deploy claim as a call to a contract that has no
such entry point; `construct.rs:624-643`'s `references()` would have to learn to match
`Deploy` against a slot-3 entry, which is exactly the special-casing the reuse was meant to
avoid; and the cost model's key-length assumption for that map
(`structure.rs:1209-1211`, `PERSISTENT_HASH_BYTES * 2 + FR_BYTES + 8`) happens to still fit
but for the wrong reason. `sequencing_check` would need to skip deploys, which have no
transcript and no position semantics of the kind it assumes.

**My read:** A′ is the right *first implementation* if the goal is to get the feature onto
a testnet without a coordinated multi-repo wire-format change, and A is the right *final*
shape. They are not mutually exclusive — A′ is a strictly smaller diff that can be
migrated to A at the next transcript version bump, since both are claim-set membership
checks and the surface language is identical in either case. Worth deciding deliberately
rather than drifting into A′ and never leaving.

### 5.4 Design C/D — derived addresses, and deploy-by-reference

Two things Design A cannot do, both worth naming even though neither belongs in a first
version.

**C — predictable addresses.** Under A, the address is only knowable once the
`ContractDeploy` bytes exist, which is after the child's initial state is fixed. A
CREATE2-style scheme —
`address = persistentCommit(impl_digest ++ salt, "midnight:contract-derived")` — makes the
address a cheap in-circuit computation over a small fixed-shape input (one hash, not a DAG
walk), and knowable *before* deployment. That unlocks counterfactual instantiation: a
parent can record and reason about a child's address in a transaction that does not deploy
it.

It is a consensus change to address derivation, requiring a `ContractDeploy` variant
(`contract-deploy[v7]`) and a second branch in `address()`. And it imports Ethereum's
squatting problem: `ContractAlreadyDeployed` (`semantics.rs:1513`) becomes adversarially
reachable, because a predictable address is a front-runnable one. Today the nonce is
random (`construct.rs:291-297`), which makes squatting a non-issue by accident.

**D — deploy-by-reference, which is the one that actually matters.** §7.3 shows the binding
constraint on factories is transaction bytes: the child's verifier keys go into the
transaction, every time, for every child. A deploy that *references* an
already-on-chain implementation by digest, rather than inlining it, turns an ~N-kilobyte
action into a ~32-byte one, and makes a factory that mints thousands of identical children
economically sensible instead of impossible.

This is precisely the door CoIP-0003 leaves open in its Rejected Ideas
(`coips/coip-0003.md:1206-1212`):

> *"Storing Implementation Code on the Ledger … remains the most direct long-term answer,
> since it would make the callee's code as authoritative as its verifier key. It is far
> outside what this proposal can carry, and the mechanism here does not preclude it: a
> ledger-backed source would appear as one more provider."*

It is also far outside what *this* proposal can carry. But it is the same door, and Design
A should be built so as not to close it: the implementation digest in §5.1 is exactly the
handle a later deploy-by-reference would key on.

---

## 6. Typing: this is the ∃-introduction form

### 6.1 The framing

`coherent-type-landscape.md` §5 argues that a `contract` type is an existential:

> `contract C { circuit f(A): B }` as a type means "*some* deployed contract that has an
> `f : A → B`." … **You cannot create one in Compact** — packing an existential requires a
> concrete implementation.

Dynamic deployment is the missing introduction rule. The elimination rule already exists:
`find-contract-circuit` (`compiler/analysis-passes/infer-types.ss:850-877`) resolves
`c.f(x)` entirely from `c`'s static `tcontract` type, never from the value.

**But there is nothing in today's syntax for the introduction rule to take as an argument,
and this is a hard blocker rather than an inconvenience.** `contract C { … }` declares the
*existential*. Writing `deploy C()` would be "deploy some contract satisfying `C`" — a
request to pack an existential with no witness to pack. Packing needs a concrete
implementation, and **a Compact implementation is an entire `.compact` file with no
in-language name.** CoIP-0002 says so in as many words when rejecting concrete contract
types (`coip-0002.md:571-575`):

> *"A major problem with this direction is that contracts do not have explicit names in the
> current language. The 'name' of a contract is implicit in the name of the file defining
> it. Any design relying on contract names would probably require the explicit
> contract-defining form of the preceding section."*

So the feature is not merely awkward to write down today; it is **not expressible**, and
the missing piece is named in CoIP-0002's own rejected-ideas section.

### 6.2 The interface/implementation split

The preceding section CoIP-0002 refers to is *"Multiple Contracts in the Same File"*
(`coip-0002.md:522-550`), which proposed exactly this:

> *"it was proposed that a `contract` form be added to the language, creating a scope in
> place of the top level for contract elements, such as circuit definitions and witness
> function declarations. It would look much like a class definition in object-oriented
> languages. … Furthermore, the intent to implement an interface could be incorporated
> directly into the `contract` form."*

and set it aside (`:547-550`) for a reason that has since expired:

> *"It may still be useful to take Compact in this direction, but it would be a large
> change, and it would not address the real need for more dynamic composition of contracts,
> so it was set aside for now."*

Dynamic composition arrived separately, in CoIP-0003. The two were weighed as alternatives;
they are orthogonal. So the proposal here is to take up the deferred thread, with the
existential/universal distinction made syntactic:

| Today | Proposed | Kind | Satisfaction |
|---|---|---|---|
| `contract T { … }` | `contract interface T { … }` | `Iface` — the existential | **structural** (unchanged) |
| *(a whole `.compact` file)* | `contract MyT { … }` | a named implementation | **nominal** — by verifier keys |

Both, not either. CoIP-0002's own caution against concrete types is a caution about
*displacing* interfaces (`:577-584`: *"many of the multi-contract systems that people want
to build … are better described using pure contract types as interfaces"*), and it is
right — "here is what I require of any participant" is exactly what an interface is for.
Naming implementations does not weaken that; it supplies the other half.

### 6.3 The typing rule

```
  MyT is a named contract implementation in scope
  Γ ⊢ args : ArgTypes(MyT.constructor)
  ─────────────────────────────────────────────────
  Γ ⊢ deploy MyT(args) : MyT

  MyT's natural contract type <: T        (existing structural check,
                                           analysis-passes/infer-types.ss:268-273,
                                           via circuit-superset?)
  ─────────────────────────────────────────────────
  Γ ⊢ MyT <: T
```

`deploy` yields the **concrete** type, and packing to an interface happens by subsumption
at the use site — `vaults: Set<Vault>` forces the pack, `return v` keeps it concrete. That
is the ordinary existential discipline: introduction gives you the witness; packing is a
coercion, not an obligation discharged at birth. It is also strictly more informative than
returning `T` (which discards a fact the compiler knows) or `ContractAddress` (which
discards the type altogether and was the error in an earlier draft of §5.1).

**What inhabits `MyT`, and why the digest is the answer.** A nominal implementation type
needs a membership condition, and the structural reading gives nothing — two unrelated
implementations can share an interface exactly. The nominal reading is:

> `MyT` is the type of addresses whose deployed `operations` map matches `MyT`'s verifier
> keys.

Which is precisely `impl_digest` from §5.1. So the digest stops being an ad-hoc security
mechanism bolted onto the claim and becomes **the runtime representation of a type**:
`deploy` establishes membership by construction, and an address arriving from TypeScript
can be *checked into* `MyT` by CoIP-0003's existing verifier-key-agreement check
(`compact/runtime/src/contract.ts:552-636`). One mechanism, two entry paths — which is a
good sign the shape is right.

**A new hazard this creates: deployment must be acyclic.** Once implementations are
nameable, `contract A { … deploy A() … }` is syntactically expressible, and it is
*unsatisfiable*, not merely awkward: `digest(A)` is a hash of `A`'s verifier keys, `A`'s
verifier keys derive from `A`'s circuits, and one of those circuits would have to contain
the literal `digest(A)`. A fixpoint no compiler can solve. The same holds mutually — `A`
deploys `B`, `B` deploys `A`. So the deployment graph needs a compile-time acyclicity
check, a direct analogue of `reject-recursive-circuits.ss`.

Worth noting what breaks the cycle: deploy-by-reference (§5.4 D), where code identity is
runtime data read from state rather than a compile-time literal. Self-deploying contracts
are exactly the case that requires it — one more entry on that design's ledger.

### 6.4 Should factory-made and TypeScript-supplied contract values be distinguishable?

**Not by provenance — and §6.3 explains why the instinct to say yes is picking up on
something real but misidentifying it.**

The apparent asymmetry: a factory-created child's implementation is verified *at deploy
time* by the implementation digest (§5.1); a TypeScript-supplied address's implementation
is verified *at call time*, by CoIP-0003's conformance and verifier-key-agreement checks
(`coip-0003.md`, `compact/runtime/src/contract.ts:552-636`). Different times, different
mechanisms.

But both end up checked, and the check that matters for any *later* call is the call-time
one, which runs identically on both. A distinct type would buy the ability to say "this
came from my own factory" — which is a *provenance* fact, not a *typing* fact, and the
right way to record provenance is the way Solidity factories already do: the parent keeps

### 6.2 Should factory-made and TypeScript-supplied contract values be distinguishable?

**No, and it is worth saying why, because the instinct is to say yes.**

The apparent asymmetry: a factory-created child's implementation is verified *at deploy
time* by the implementation digest (§5.1); a TypeScript-supplied address's implementation
is verified *at call time*, by CoIP-0003's conformance and verifier-key-agreement checks
(`coip-0003.md`, `compact/runtime/src/contract.ts:552-636`). Different times, different
mechanisms.

But both end up checked, and the check that matters for any *later* call is the call-time
one, which runs identically on both. A distinct type would buy the ability to say "this
came from my own factory" — which is a *provenance* fact, not a *typing* fact, and the
right way to record provenance is the way Solidity factories already do: the parent keeps
a `Set<Vault>` of children it created. That set is authoritative, is on-chain, is already
expressible, and survives the value being passed around, which a type would not.

So: **provenance is data, but code identity is a type.** The distinction people reach for
when they ask this question is usually the second one, and §6.3 gives it to them —
`BasicVault` is a finer type than `Vault`, and it means "this code", not "my child". An
address from TypeScript can be `BasicVault` too, on the same terms.

### 6.5 Why the claim must be fallible-only

A deploy is applied only in the fallible pass (§1.5). The guaranteed section is never rolled
back (`semantics.rs:85-91`, `PartialSuccess`). So a claim of a deploy in a *guaranteed*
transcript would be a claim, committed to by a proof and paid for with fees, about a state
change that may never occur.

There is a precedent for exactly this containment discipline. `sequencing_context_check`
(`verify.rs:1046+`) already enforces:

> *"If a calls `b`, `b` must be contained within the 'lifetime' of the call instruction in
> `a`. Concretely: if the call to `b` is in `a`'s guaranteed section, it must contain only
> a guaranteed section."*

The deploy analogue is stricter and simpler, because a deploy has no guaranteed side at
all: **a `claimContractDeploy` may appear only in a fallible transcript.** In surface
terms, `deploy` implies a preceding `Kernel.checkpoint`
(`compiler/midnight-ledger.ss:212-215`), and the compiler should insert it or require it.

This is a nice example of the totality/staging discipline paying off in a place it was not
designed for: the guaranteed/fallible split is a *staging* boundary, and `deploy` is an
operation that only exists on one side of it. Making that a typing rule rather than a
runtime failure is the same move §1 of `coherent-type-landscape.md` makes for `Val`/`Store`.

---

## 7. What it costs

### 7.1 Gas

The claim is nine opcodes of ordinary `idx`/`ins` traffic (§5.1), priced by the existing
per-opcode model — `ins_map_constant + ins_map_coeff_key_size·|k| +
ins_map_coeff_container_log_size·log₂(n)` (`onchain-vm/src/cost_model.rs:59-202`;
formula documented at `:27-58`). Same order as `claimContractCall`.

Plus one term nobody would think to look for: `stack_setup_cost_for_effects`
(`ledger/src/structure.rs:1194-1230`) charges every call for building all nine effects maps,
whether used or not. A 10th slot adds a fixed increment to **every contract call in the
system**, not just deploying ones. Small, but it is a global regression and should be
measured. Design A′ (§5.3) avoids it entirely.

The deploy's own cost is unchanged and already modeled:
`map_index(32) + map_insert(32, false) + tree_copy(initial_state)`
(`structure.rs:2240-2245`), on the fallible side.

### 7.2 Proof width

The claim's opcodes are field-repr'd into `public_inputs` (`verify.rs:1946-1970`), so
~9 opcodes' worth of public inputs, plus the address as two witnessed limbs (like
`ep-mod`/`ep-div`, `desugar-contract-calls.ss:93-101`). The implementation digest is a
comparison against a literal, so it is a handful of constraints.

**Order of magnitude: ~10 additional public inputs, negligible constraint count.** Design B
would be ~10⁵ constraints for a full in-circuit SHA-256 over a multi-kilobyte encoding.
This is the single largest gap between the designs and it is three orders of magnitude wide.

Note also that a deploy adds nothing to proof *verification* cost, since
`ContractAction::Deploy` falls through `structure.rs:2007-2015`'s `_ => {}`.

### 7.3 Transaction bytes — the binding constraint

This is where a factory actually dies, and it is worth stating bluntly.

The child's full `ContractState` is inlined in the transaction: the initial `StateValue`
tree, the maintenance authority, and — dominating everything — one `ContractOperation` per
entry point, each carrying a verifier key.

- `max_contract_metadata_size = 50_000` bytes per entry point (`structure.rs:1282`),
  checked by `check_entry_point_metadata_sizes` (`verify.rs:379-397`).
- `transaction_byte_limit = 1 << 20` = 1 MiB (`structure.rs:1271`).

So the arithmetic is unforgiving. A child with a handful of circuits is a substantial
fraction of a transaction; a factory emitting several children per call may not fit at all.

**Three consequences:**

1. Factories in the Design A sense are for *small* children, or for one child per
   transaction. That should be documented as a limitation, not discovered.
2. The cost is paid *per deployment*, even when a thousand children share byte-identical
   code — which is the common case for a factory, and the case where the waste is total.
3. **This is the argument for deploy-by-reference (§5.4), and it is a much stronger
   argument than any of the ergonomic ones.**

There is no rent and no deposit (§1.6), so the fee is one-time — which makes state growth
from cheap factory deploys a thing to think about, though the byte limit above is currently
a far tighter constraint.

---

## 8. What it would break

**Consensus / wire format.** Design A changes the `Effects` shape and therefore
`contract-effects[v3]` → `[v4]`, requires a `TranscriptVersion` bump
(`transcript.rs:65-67`, currently `{major: 2, minor: 3}`), and is a hard fork of transcript
execution: `context.rs:810`'s `arr.len() == 9` means a 10-slot effects array is rejected by
every un-upgraded node. There is no soft path. The array has grown before —
`CHANGELOG_onchain-runtime.md:54` records *"Also extended `Effects` to contain unshielded
token information"* — so this is a known operation, but it is a coordinated one.

Interesting wrinkle: **the transcript version is currently only *checked* for contracts
carrying a legacy `.v2` verifier key** (`verify.rs:1911-1930`). For modern `.v3`-only
contracts nothing anywhere validates `transcript.version`. So the bump is real but its
enforcement would have to be added, not merely incremented — which is itself worth
fixing regardless of this feature.

Design A′ breaks none of this.

**Existing contracts.** Neither design changes the meaning of any existing opcode,
transcript, or contract. A contract that never deploys emits no claim, its effects
serialize with one more empty collection, and its gas rises by the
`stack_setup_cost_for_effects` increment (§7.1). Verifier keys of existing contracts are
unaffected, since the claim adds opcodes only to circuits that use `deploy`.

**Compiler.** Additive: a new surface form, a new `Kernel` op, a new desugaring pass after
`desugar-contract-calls` in `circuit-passes.ss:62-77`, and — easy to miss — a **second,
independent lowering in `print-typescript.ss`**. The TypeScript passes consume
`analyzed-ir`, *before* `circuit-passes` runs, which is why `contract-call` is lowered
twice today (`print-typescript.ss:3057-3096` for execution,
`desugar-contract-calls.ss` + `print-zkir.ss` for the proof). A deploy needs both halves,
and the two must agree.

**midnight-js.** The largest practical change. `createUnprovenLedgerDeployTx` builds its
transaction with `Transaction.fromParts` (`ledger-utils.ts:81-86`) while
`createUnprovenLedgerCallTx` uses `fromPartsRandomized` (`:205-210`) *specifically* to
randomize the segment ID for mergeability. Merging today's deploy-shaped transaction with a
call-shaped one risks `IntentSegmentIdCollision` (`structure.rs:1495-1510`). A new
combined-assembly path is needed, not a reuse of the existing helpers. It must also emit
`add_deploy` before `add_call` (§5.1), which `Intent::new` will not do
(`construct.rs:331-357`).

The runtime also has to make the child's `initialState` reachable during the parent's
circuit execution, which it currently is not by explicit design
(`compact/runtime/src/module.ts:37-40`).

**Constructor restrictions.** `reject-constructor-cc-calls.ss` and
`reject-constructor-emit.ss` apply to the *child's* constructor, running off-chain on the
deployer's machine during the parent's rehearsal. They remain correct and remain necessary.
CoIP-0002's inherited limitations (`coip-0003.md:890-898`) — no witnesses in
cross-contract-called circuits, undefined behaviour for recursive cross-contract calls —
bite immediately in the A-two-phase pattern, since `Foo.initialize(params)` is an ordinary
cross-contract call and inherits all of them.

---

## 9. Open questions

1. **A or A′?** §5.3. A′ is a much smaller diff that avoids a hard fork, at the cost of
   overloading `claimed_contract_calls` with something that is not a call. If the answer is
   "A′ now, A at the next version bump", that should be written down at the time, not
   assumed.

2. **Does the *ordinary* deploy path become two-phase too?** §5.1.1 makes the constructor a
   proved circuit called at the default state. The question it cannot settle is whether that
   applies to every deployment or only to factory-initiated ones, and neither answer is
   comfortable:

   - **Uniformly.** `deployContract` in midnight-js becomes deploy+call for everyone. One
     semantics, a breaking change to the whole SDK flow, and a proof added to every
     deployment.
   - **Factory-only.** `constructor` means one thing when you deploy directly and another
     when a factory deploys you. Two semantics for one keyword, which is worse.

   I would argue uniform, and the reason is §1.4 generalized: **the TCB hole was never a
   factory problem.** No third party can verify today that *any* contract was properly
   constructed — they must read the state and judge. Factories only make the gap visible, by
   putting a contract's registry entry in front of strangers who did not deploy it. On that
   reading "constructors are proved circuits" is a soundness fix that stands on its own, and
   dynamic deployment is its forcing function rather than its beneficiary.

   That is a real escalation in scope — from "add a clause to `effects_check`" to "change
   what a constructor is" — and it should be decided as such rather than arrived at.

3. **What is the digest, exactly — and is it one value or two?** A hash over `operations`
   needs a canonical encoding of a `HashMap<EntryPointBuf, ContractOperation>`, and the same
   node-list-layout concern from §5.2 applies in miniature — with the crucial difference
   that here the *ledger* computes it and only the *comparison target* is a compile-time
   literal in the circuit. So the encoding must be stable across releases (otherwise
   deployed factories break on a storage refactor) but need not be circuit-friendly. That is
   a much weaker requirement, but it is not free, and it wants an explicitly versioned
   digest function rather than a reuse of `state_hash()`.

   Separately: since §5.1 requires the claim to pin initial state as well as code, is that
   one digest or two? A single total digest over the whole `ContractState` is simplest, but
   it conflates "is this Foo's code" with "is this Foo's starting state", and only the first
   is stable over a child's lifetime. Two digests would let a parent express *"some Foo, any
   starting state"* where that is genuinely what it wants, and would give deploy-by-reference
   (§5.4 D) a code-only handle to key on. Probably two, but I have not thought it through.

4. **Address collisions.** Under A the nonce stays random and collisions are a non-issue.
   But the nonce arrives from a witness, so it is a private choice with a public
   consequence: two transactions in one block deploying identical content with the same
   witnessed nonce collide, and the second fails with `ContractAlreadyDeployed`
   (`semantics.rs:1513`) — killing the whole fallible section, not just the deploy. Should
   the nonce be derived from something guaranteed-unique (the parent's address plus a
   counter in its own state) rather than witnessed? That makes it deterministic and
   collision-free, at the cost of a state read and of making addresses semi-predictable.

5. **Who is the child's maintenance authority?** `ContractMaintenanceAuthority`
   (`onchain-state/src/state.rs:699-703`) is `{ committee, threshold, counter }` of Schnorr
   or ECDSA keys. The deployer's SDK sets it today from a local signing key
   (`ContractExecutable.js`, `createMaintenanceAuthority`). For a factory child, whose key?
   The parent contract has no key — it is not a signer. An empty committee means the child
   can never be upgraded. That may be correct (immutable children are a feature), but it is
   a decision, and it must be visible in the surface syntax rather than defaulted silently.

6. **Can the parent fund the child?** No, today: `NonZeroBalance` (`verify.rs:1770-1780`)
   forbids a non-zero initial balance. So deploy-and-fund needs a third action. Does the
   constructor call of §5.1.1 carry the funding, and does that interact correctly with the
   unshielded-token effects slots (6, 7, 8)?

6b. **What is a compilation unit, once a file holds several contracts?** The
   interface/implementation split (§6.2) means one `.compact` file can define several named
   implementations, and two whole-program assumptions have to be revisited. First,
   `combine-ledger-declarations` (`compiler/analysis-passes/combine-ledger-declarations.ss`)
   partitions `Ledger-Declaration`s out of the *Program*'s element list and folds them into a
   single ledger — it is a whole-program pass, and contract scoping makes it per-contract.
   Second, the build artifact layout is one contract per output directory, which
   `zkConfigProvider` (`packages/types/src/zk-config-provider.ts:34-64`) and CoIP-0003's
   `expectedVk` / module resolution both assume.

   This is also where the win lands, so it is worth the disruption: a factory and its
   children in one compilation unit means the child's verifier keys are build artifacts of
   the *same* build, which is what makes `impl_digest` a genuine compile-time literal rather
   than something requiring a cross-build manifest.

7. **How is the deployment graph checked for acyclicity?** §6.3 shows `contract A { … deploy
   A() … }` is unsatisfiable rather than merely odd — `digest(A)` would have to appear as a
   literal inside a circuit whose verifier key feeds `digest(A)`. The check itself is a
   straightforward analogue of `reject-recursive-circuits.ss`, but two details need settling:
   does it run over named implementations only, or does an interface-typed indirection
   (`deploy` inside a circuit reachable from a cross-contract call) need to be conservative
   about cycles it cannot see? And is the error message able to say anything useful, given
   the cause is a hash fixpoint rather than a syntactic loop?

8. **Does `deploy` need to be an expression at all?** The alternative is a declaration-level
   `factory` form that names the deployable children up front, which would make the
   compile-time-identity requirement (§2) syntactically evident rather than a rule the
   type checker enforces after the fact. §6.2's `contract MyT { … }` form weakens the case
   for this — the implementations a unit can deploy are already enumerable from its
   declarations — but it does not settle it. Worth a sketch before committing to expression
   syntax.

---

## 10. Recommendation

Build **Design A′, deploying at the default state with the constructor as a proved
circuit**:

- **Claim** (§5.3): a reserved entry point inside the *existing* `claimed_contract_calls`
  set — no new `Effects` slot, no transcript version bump, none of the seven
  silent-failure sites in §4. Cross-checked by one new clause in `effects_check`.
- **Deploy** (§5.1.1): always at the compile-time-constant default state that
  `ledger-reset-to-default` already builds, so the claim's digest pins the entire
  `ContractState` and the circuit's obligation is one equality against a literal.
- **Construct** (§5.1.1): `constructor` becomes an ordinary provable circuit, called in the
  same transaction through the existing `claimContractCall` machinery. This is what closes
  §1.4's hole — the parameterized half of deployment moves from an unproved off-chain
  computation into a proved on-chain one.
- **Type** (§6): `contract interface T` / `contract MyT { … }`, with `deploy MyT(args) : MyT`
  and packing to `T` by subsumption. This is a **precondition**, not a companion feature:
  without a name for a concrete implementation there is nothing well-typed for `deploy` to
  take.

Cost: ~10 extra public inputs and a literal comparison in the circuit; one new
`effects_check` clause; one new `Kernel` op; one new compiler pass (×2, per §8); one new SDK
assembly path; a new acyclicity check (§9.7); and a proof added to every deployment.

Two of those four pieces are larger than "dynamic deployment" and are worth building on
their own terms — proved constructors are a soundness fix for *all* contracts (§9.2), and
named implementations take up a thread CoIP-0002 explicitly deferred for a reason CoIP-0003
has since retired (§6.2). Dynamic deployment is their forcing function more than it is their
beneficiary, and that is the honest way to scope the work.

Then reassess. The two things that would change the picture are **deploy-by-reference**
(§5.4 D), which is what makes factories economically real rather than merely expressible —
and which is also the only way a self-deploying contract can escape §6.3's fixpoint — and
**derived addresses** (§5.4 C), which is what makes counterfactual patterns possible. Both
are larger than this, both are already anticipated in CoIP-0003's rejected ideas, and
neither is foreclosed by starting here.

The one thing worth resisting is Design B. In-circuit address derivation looks like the
design that needs no permission from the ledger, and it very nearly works — but the thing
it would hash is a storage-engine artifact, and a proving circuit is the wrong place to
depend on one.
