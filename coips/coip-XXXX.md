| |                               |
|---|-------------------------------|
| CoIP | XXXX                           |
| Title | Dynamic Cross-Contract Calls  |
| Authors | Joseph Denman, Kevin Millikan |
| Status | Draft                         |
| Category | Core                          |
| Created | 2026-01-27                    |
| Requires | N/A                           |
| Replaces | N/A                           |
| License | Apache-2.0                    |

## Abstract

This CoIP describes the software architecture needed to implement dynamic contract composability, which was proposed by Kevin Millikin [here](https://github.com/midnightntwrk/midnight-architecture/pull/176).

A cross-contract call lets one contract execute a circuit defined in a different, separately deployed contract. We cover the proving model, the ZKIR extensions needed to support it, and how the ZKIR interpreter would work. The key goal is supporting *dynamic* cross-contract calls, where the target contract isn't known until runtime.

## Motivation

A decentralized exchange illustrates why we need dynamic cross-contract calls. Consider:

1. Alice deploys `TokenA.compact`, a fungible token contract with a `transfer` circuit.
2. Bob deploys `TokenB.compact`, another fungible token contract.
3. Charlie deploys `DEX.compact`, a liquidity pool contract.
4. DEX users register `TokenA` and `TokenB` with the DEX after the DEX is deployed.

When Dave wants to swap `TokenA` for `TokenB`, the DEX must execute:

```
TokenA.transfer(Carol, DEX, amount)
TokenB.transfer(DEX, Carol, amount)
```

The DEX can't know at compile time which token contracts it will interact with—they might be deployed years after the DEX itself. This is exactly what dynamic contract calls are for.

## Specification

### Definitions

Terms used throughout this document:

| Term | Definition                                                                                                                |
|------|---------------------------------------------------------------------------------------------------------------------------|
| **Contract artifacts** | The circuit executables, prover keys, and verifier keys derived from a Compact source file.                               |
| **Contract interpreter** | The function that maps the state of a contract and a contract executable to a public transcript and private transcript.   |
| **Cross-contract call** | When one contract executes a circuit defined within a different, separately deployed contract on the Midnight blockchain. |
| **Call target** | The circuit that a caller contract executes during a cross-contract call.                                                 |
| **Static cross-contract call** | A cross-contract call where the executable of the call target is determined at compile time.                              |
| **Dynamic cross-contract call** | A cross-contract call where the executable of the call target is determined at runtime.                                   |
| **Communication commitment** | A cryptographic hash binding the inputs and outputs of a cross-contract call.                                             |
| **Rehearsal** | The process of executing a contract circuit off-chain to produce public and private transcripts.                                    |
| **Alignment** | Metadata describing how to interpret a sequence of field elements as a structured value.                                  |
| **AlignedValue** | A pair of an alignment and a sequence of field elements conforming to that alignment.                                     |
| **Effects** | The set of state changes, token flows, and claims produced by circuit execution.                                          |

### Background

#### Communication Commitment Model

Cross-contract calls use a *communication commitment* to bind the caller and callee together. This commitment is a hash of the callee's inputs, outputs, and some randomness. It's what lets us prove that a caller actually invoked a callee with specific arguments and received specific results.

During rehearsal, the caller generates randomness `rand` and receives the callee's output as a witness. It computes the commitment and claims it in its `Effects`:

 ```compact
 comm = transient_commit([input, output], rand)
 ```

The caller then executes:

```compact
kernel.claimContractCall(callee_address, entry_point_hash, comm)
```

to claim the contract call in its `Effects` record.

The callee receives the commitment as a public input (`comm_comm`), binding the callee's proof to those specific inputs/outputs. The callee's `PreTranscript` contains

```rust
PreTranscript {
  ...
  comm_comm: Some(cc),
}
```

and the callee's `ContractCallPrototype` contains

```rust
ContractCallPrototype {
  communication_commitment_rand: rand,  // The shared randomness
  ...
}
```

The ledger verifies that commitments match by checking that every `claimed_contract_call` in a caller's `Effects` corresponds to an actual `ContractCall` in the transaction with the same commitment.

Note that `transient_commit` requires alignment metadata for its arguments. This matters because the interpreter needs to  know the alignments of callee arguments and return values to compute the commitment correctly.

Consider the following callee contract `C.compact`:

```compact
import CompactStandardLibrary;

ledger value: Opaque<"string">;

constructor(param_v: Opaque<"string">) {
  value = param_v;
}

export circuit get(): Opaque<"string"> {
  return value;
}

export circuit set(v: Opaque<"string">): [] {
  value = v;
}
```

Contract `C.compact` is deployed independently and has its own ledger state. The following contract `D.compact` calls `C.compact`:

```compact
import CompactStandardLibrary;

ledger c: C;

contract C {
  circuit get(): Opaque<"string">;
  circuit set(v: Opaque<"string">): [];
}

constructor(param_c: C) {
  c = param_c;
}

export circuit update(v: Opaque<"string">): Opaque<"string"> {
  const r = c.get();
  c.set(v);
  return r;
}
```

The proof semantics for the contract above is essentially the following:

```compact
import CompactStandardLibrary;

ledger c: C;

contract C {
  circuit get(): Opaque<"string">;
  circuit set(v: Opaque<"string">): [];
}

// These are conceptual, to illustrate the communication commitment mechanism.
ledger c_address: ContractAddress
witness tmp_do_get_call(): Opaque<"string">;
witness tmp_do_set_call(v: Opaque<"string"): [];
witness tmp_call_rand(): Field;

export circuit update(v: Opaque<"string">): Opaque<"string"> {
  // const r = c.get();
  const r = tmp_do_get_call();

  // Compute communication commitment for the get() call
  const cc_get = transientCommit<Opaque<"string">>([r], tmp_call_rand());
  kernel.claimContractCall(c_address, "get", cc_get);

  // c.set(v);
  tmp_do_set_call(v);

  // Compute communication commitment for the set() call
  const cc_set = transientCommit<Opaque<"string">>([v], tmp_call_rand());
  kernel.claimContractCall(c_address, "set", cc_set);

  return r;
}
```

The private transcript contains entries as if `tmp_do_get_call`, `tmp_do_set_call`, and `tmp_call_rand` were user-defined witnesses. The interpreter handles all this plumbing internally—programs aren't directly compiled into the form above.

#### How Static Calls Work Today

Currently, all cross-contract calls are static. The caller declares which contracts it will call, and the compiler bundles the callee's executable at compile time.

The generated JavaScript for `D.compact` contains compile-time imports:

```javascript
import * as __compactRuntime from '@midnight-ntwrk/compact-runtime';
import * as __C from '../../C/contract/index.js';  // Bundled at compile time

function _update_0(context, witnessSets, partialProofData, v_0) {
  __compactRuntime.interContractCall(
    context,
    __C.executables(witnessSets),  // C's executable, bundled at compile time
    __C.contractId,
    'get',
    // ...
  );
  // ...
}
```

The contract address comes from ledger state at runtime, but the executable (JavaScript, ZKIR, and prover key) is bundled at compile time. This JavaScript implements the contract's logic and generates the transcripts fed to the proving system.

Currently, a contract's on-chain state only includes its Impact state and verifier keys. The prover keys and ZKIR bytecode live off-chain in the compiled JavaScript bundle. That's fine for verifying proofs, but not for generating them. For our DEX example, this means the DEX can't call `TokenA.transfer()` unless `TokenA` was bundled with the DEX at compile time.

### Proposed Solution: On-Chain ZKIR and Dynamic Interpretation

In the dynamic contract composability [proposal](https://github.com/midnightntwrk/midnight-architecture/pull/176), it was suggested to make ZKIR the executable instead of JavaScript. ZKIR has both a relational semantics (for proofs) and a computational semantics (for generating transcripts). The idea is to store ZKIR bytecode and prover keys on-chain alongside verifier keys, so any contract can call any other contract at runtime. Accomplishing this will require a few changes:

- Extend `ContractOperation` with optional `zkir` and `prover_key_hash` fields. Prover keys are stored off-chain and fetched using the hash.
- Add a `ContractCall` instruction to ZKIR that specifies the target address, circuit name, arguments, and where to store return values. It also includes alignment metadata needed for the communication commitment.
- Extend `IrSource` with `arg_alignment` and `return_val_alignment` fields describing the circuit's input/output structure. Having alignment in both `IrSource` and `ContractCall` lets the interpreter verify ABI compatibility.
- Make `impact` operations in ZKIR v3 symbolic rather than pre-encoded as field elements. This lets the interpreter execute Impact operations in ZKIR v3 directly.

When the interpreter hits a `ContractCall` during rehearsal, it fetches the target contract's state, ZKIR, and keys from the chain, executes the callee, and links everything together via the communication commitment.

#### Interpret Mode

The ZKIR interpreter currently has two modes: `preprocess` (verify witness consistency) and `circuit` (generate ZK constraints). These will be updated to handle `ContractCall` and symbolic Impact, but their core logic stays the same.

The main addition is a new **interpret mode** (rehearsal). This mode actually executes the circuit to compute witnesses, `Effects`, and proof pre-images:

1. Actually executes the callee circuit
2. Computes real output values
3. Generates commitment randomness
4. Computes communication commitments
5. Accumulates Effects (including `claimed_contract_calls`)
6. Stores data necessary for the proving phase

For the DEX example, interpret mode looks like this:

1. User calls `DEX.swap(tokenA_addr, tokenB_addr, amount)`
2. Interpreter loads `DEX.zkir` from chain
3. `DEX.zkir` contains `impact` instruction sequence to fetch `tokenA_addr` from `DEX` contract state
4. `DEX.zkir` contains: `ContractCall { address: tokenA_addr, ... }`
5. Interpreter fetches `TokenA.zkir` from the blockchain at runtime
6. Interpreter executes `TokenA.transfer`
7. Communication commitment between `DEX` and `TokenA` created for `swap` circuit
8. Public and private transcripts for both `DEX.swap` and `TokenA.transfer` are returned from interpreter

## Rationale

### Why Symbolic Impact Operations?

The current ZKIR v3 format encodes Impact operations as pre-computed field elements:

```json
{ "op": "impact", "inputs": ["0x10", "0x01", "0x01", ...] }
```

This works for static compilation where all values are known at compile time, but fails for dynamic calls. When a contract calls another contract whose address comes from ledger state, the interpreter must execute the Impact operation at runtime—it can't pre-encode values it doesn't know yet.

The symbolic format uses an atoms-with-sources representation:

```json
{ "op": "impact", "ops": [{ "push": { "value": { "atoms": [{ "tag": "bytes", "sources": ["%addr.0", "%addr.1"], "length": 32 }] }}}] }
```

Each atom declares its type (`bytes`, `field`, `compress`), its length, and exactly which field elements compose it. The interpreter resolves `%addr.0` at runtime, combines the field elements according to the atom's type, and constructs the Impact operation dynamically. The format is also human-readable, which simplifies debugging.

### Why Store Prover Key Hashes On-Chain?

Currently, contracts store only verifier keys on-chain (~2KB per circuit). This suffices for proof verification but not proof generation. For dynamic calls, the caller must generate proofs for contracts it didn't bundle at compile time. This requires access to both the ZKIR and the prover key.

**The prover key problem:** Prover keys are large and can easily exceed block size limits. This creates a storage challenge with three possible solutions:

1. **Store prover keys on-chain.** Split keys across multiple transactions during deployment, reassemble when needed. Rejected—adds significant complexity and storage costs.

2. **Derive prover keys on demand.** Store only ZKIR on-chain, derive prover keys at runtime. Rejected—key derivation is computationally expensive, taking seconds per circuit.

3. **Store prover key hashes on-chain.** Store ZKIR and a hash of the prover key on-chain. The actual prover key lives in content-addressed storage (IPFS, Arweave). DApps fetch the prover key using the hash and verify integrity before use.

**Recommendation:** Option 3. ZKIR and prover key hashes fit comfortably on-chain. Prover keys are fetched from content-addressed storage using the hash. This introduces a trust assumption that the on-chain hash corresponds to the correct prover key. However, this is reasonable for two reasons:

1. **Verified contracts.** Similar to Ethereum's verified contract model, we can provide a service that compiles Compact source code and verifies the resulting ZKIR and prover key hash against what's stored on-chain. This creates a public mapping from auditable source code to on-chain artifacts.

2. **Proof verification catches mismatches.** If a DApp fetches an incorrect prover key, the resulting proof will fail verification against the on-chain verifier key. A malicious prover key cannot produce valid proofs.

## Path to Active

### Acceptance Criteria

Acceptance criteria should be documented in the [Contract to Contract Calling](https://shielded.atlassian.net/browse/PM-19464) initiative.

### Implementation Plan

#### Phase 1: Alignment Fields

**Ledger:**
- Add `arg_alignment` and `return_val_alignment` fields to `IrSource`

**Compiler:**
- Emit `arg_alignment` and `return_val_alignment` in ZKIR output

**Testing:**
- Update `test.ss` expected outputs for alignment fields

#### Phase 2: Symbolic Impact

**Ledger:**
- Add `zkir-v3` → `onchain-runtime` dependency
- Define `SymbolicOp` type with atoms-with-sources format
- Update `Impact` instruction to use `Vec<SymbolicOp>` plus `field_count`
- Implement symbolic op resolution in `preprocess` and `circuit` modes

**Compiler:**
- Emit symbolic `Impact` ops instead of pre-encoded field elements

**Testing:**
- Update `test.ss` expected outputs for symbolic Impact format
- Unit tests for symbolic op resolution

#### Phase 3: Interpret Mode and Execute Function

**Ledger:**
- Add `ContractCall` instruction to `IrSource`
- Handle `ContractCall` in all three modes (preprocess, circuit, interpret)
- Port `CircuitContext`, `StackFrame`, `ProofDataFrame`, `ProofDataTrace` from [compact-export/runtime](https://github.com/midnightntwrk/compactc/blob/cc-ts/js-backend%2Brt/runtime/src/circuit-context.ts) to Rust
- Implement interpret mode (rehearsal) with `execute` function in `zkir-v3-wasm`

**Compiler:**
- Emit `ContractCall` instructions for cross-contract calls
- Rewrite JavaScript code generation to emit thin wrappers calling `execute`
- Keep `CompactType` descriptor generation for argument/return type conversion
- Keep `index.d.ts` will be updated to accept the contract artifact provider and have all circuits return promises.

**Testing:**
- Caller-callee proof generation and verification tests
- Communication commitment verification tests
- Compiler side tests comparing new interpreter output to old JavaScript execution

#### Phase 5: On-Chain Storage

**Ledger:**
- Extend `ContractOperation` with `zkir` and `prover_key_hash` fields
- Implement contract loader for on-chain retrieval
- Adjust storage fees

#### Phase 6: Integration with Midnight Toolkit

**Midnight Toolkit**
- Extend toolkit to work with asynchronous contract executables

**Testing**
- Toolkit based E2E tests

## Backwards Compatibility Assessment

### ZKIR Format Changes

The ZKIR format changes from v3.0 to v3.1 (minor version bump):

- `IrSource` adds `arg_alignment` and `return_val_alignment` fields (already present in current code, now required)
- `Impact` instruction changes from `inputs: Vec<Fr>` to `ops: Vec<SymbolicOp>` plus `field_count: u64`
- New `ContractCall` instruction added

Existing v3.0 ZKIR files will fail to parse with the v3.1 interpreter. This is acceptable because ZKIR is not stored on-chain today—it lives in the compiled JavaScript bundle. When users upgrade the compiler, they get new ZKIR. No migration needed.

### Contract Operation Changes

`ContractOperation` currently stores only `verifier_key`. The proposal adds optional `zkir` and `prover_key_hash` fields:

```rust
pub struct ContractOperation {
    pub verifier_key: Option<VerifierKey>,
    pub zkir: Option<IrSource>,              // New
    pub prover_key_hash: Option<[u8; 32]>,   // New
}
```

Prover keys are stored off-chain in content-addressed storage. The on-chain hash lets DApps verify integrity of fetched prover keys (see Rationale).
Contracts deployed before this change cannot be called dynamically (no on-chain ZKIR). They can still be called statically via bundled artifacts.

### Compiler TypeScript Output Changes

Because all contract executables are currently known statically, the TypeScript contract executables execute synchronously.
With dynamic contract calls, contract artifacts may be fetched dynamically, meaning that the TypeScript contract interfaces
will need to return promises. Although note complicated, many tools downstream of the compiler assume synchronous execution
and will need to be updated work with the new async contract interface.

## Security Considerations

* A malicious contract could implement an interface correctly but behave unexpectedly. Callers should only interact with trusted or audited contracts. Interfaces provide type safety, not behavioral safety.
* Reentrancy shouldn't be any more of a concern than it was when we planned on implementing only static contract calls.
* How are costs attributed across caller and callee? Who pays?
* What happens when the ZKIR format changes? How do old contracts interoperate with new ones?
* How do we handle maintenance updates for contracts? These can modify circuits and therefore ZKIR.

## Implementation

### ZKIR Extension

`IrSource` from `zkir-v3` package in `midnight-ledger` gets two new fields: `arg_alignment` and `return_val_alignment`. These describe the circuit's input/output structure so callers can construct `AlignedValue` instances for the communication commitment.

`ContractCall` instruction is added to the ZKIR v3 `Instruction` enum.

```rust
struct ContractCall {
  circuit_id: String,               // Identifier for callee's ZKIR/prover key
  address: Vec<Operand>,            // Operands encoding the callee contract address (need two fields to encode an address)
  inputs: Vec<Operand>,     // Operands to pass to callee
  inputs_alignment: Alignment,       // How to encode inputs for commitment
  outputs: Vec<Identifier>, // Where to store callee's outputs
  outputs_alignment: Alignment,      // How to decode outputs from commitment
}
```

It contains the target address (as operands), entry point name, argument operands, output identifiers, alignment metadata.

`ContractOperation` (currently just the verifier key) is extended with optional `zkir` and `prover_key_hash` fields. Prover keys are stored off-chain in content-addressed storage and fetched using the on-chain hash. This lets callers generate proofs for contracts they didn't bundle at compile time.

The current `Impact` instruction takes pre-encoded field elements. We change it to carry symbolic operations
(`Vec<SymbolicOp>`) plus a compiler-provided `field_count`. `SymbolicOp` wraps JSON matching the `Op` structure, with variable references like `%v_0` that get resolved at runtime. A new `resolve` module walks the JSON and replaces these with concrete values.

### WASM Interface

The goal is to internalize the TypeScript runtime from [compact-export/runtime](https://github.com/midnightntwrk/compactc/blob/cc-ts/js-backend%2Brt/runtime/src/circuit-context.ts) into `midnight-ledger`, converting from TypeScript to Rust. The key types:

```typescript
// Added to 'zkir-v3-wasm' package

interface ProofData {
  input: AlignedValue;
  output: AlignedValue;
  publicTranscript: Op<AlignedValue>[];
  privateTranscriptOutputs: AlignedValue[];
  communicationCommitmentRand: CommunicationCommitmentRand;
  communicationCommitment?: CommunicationCommitment;
}

interface ProofDataFrame extends ProofData {
  circuitId: CircuitId;
  contractAddress: ContractAddress;
  initialQueryContext: QueryContext;
  currentQueryContext: QueryContext;
}

type ProofDataTrace = ProofDataFrame[];

interface StackFrame {
  circuitId: CircuitId;
  contractAddress: ContractAddress;
  initialQueryContext: QueryContext;
  currentQueryContext: QueryContext;
}

interface CircuitContext extends StackFrame {
  ledgerStates: Record<ContractAddress, QueryContext>;
  proofDataTrace: ProofDataTrace;
}

interface CircuitResults {
  result: AlignedValue;
  context: CircuitContext;
}
```

The `zkir-v3-wasm` package currently exposes `prove` and `check` functions. We add the types defined above and an `execute` function for rehearsal:

```typescript
interface ContractArtifacts {
    zkir: IrSource;
    proverKey: ProverKey;      // Fetched from content-addressed storage, verified against on-chain hash
    verifierKey: VerifierKey;
    state: ContractState;
}

interface ContractArtifactProvider {
  getArtifacts(
    address: ContractAddress,
    entryPoint: string
  ): Promise<ContractArtifacts>;
}

function execute(
  address: ContractAddress,
  entryPoint: string,
  args: AlignedValue,
  provider: ContractArtifactProvider
): Promise<CircuitResults>;
```

The returned `CircuitContext` contains a `proofDataTrace` with one `ProofDataFrame` per circuit that executed and returned. Each frame has everything needed to construct a `ContractCall` for the transaction: contract address, circuit ID, input/output, transcripts, communication commitment, and initial/current query contexts. The `proofDataTrace` is in execution order – callee before caller. The `provider` abstraction lets callers plug in different backends – local storage for cached contracts, network fetches for on-chain data, or mocks for testing. It mirrors the pattern already used by `JsKeyProvider` in `zkir-v3-wasm`.

### Execution Flow

When the Rust interpreter hits a `ContractCall` instruction:

1. Save the current `StackFrame`
2. Fetch the callee's artifacts via the provider
3. Push new `StackFrame` to set up the callee's context
4. Execute the callee circuit
5. Finalize the callee's `ProofDataFrame`
6. Restore the caller's stack frame while preserving the updated heaps
7. Continue execution with the callee's output as the result

### Compiler Changes

#### Symbolic `impact` Operations
The compiler will need to emit symbolic `impact` blocks in ZKIR v3, as described in the ZKIR Extensions section above.
The compiler currently emits ZKIR v3 containing `impact` blocks where Impact instructions and their arguments are directly
encoded as fields.

```json
{ 
  "op": "impact", 
  "guard": "0x01", 
  "inputs": ["0x10", "0x01", "0x01", "0x01", "0x00", "0x11", "0x01", "0x01", "-0x02", "0x07", "0x91"] 
}
```

Each hex value in the `inputs` field describes either an operation of an argument to an Impact operation.

The new ZKIR interpreter needs to be able to _execute_ Impact instructions. We need a ZKIR format that allows us to convert the
`inputs` directly to the `Op` enum variant representing an Impact VM op in `midnight-ledger`. Since `Op` operates on
the structured `AlignedValue`, we'll have the compiler emit information that makes it easy to convert unstructured field
elements to `AlignedValue`. The symbolic equivalent of the `impact` block above will be

```json
{
  "op": "impact",
  "guard": "0x01",
  "ops": [
    {
      "push": {
        "storage": false,
        "value": {
          "tag": "cell",
          "content": {
            "atoms": [
              {
                "tag": "bytes",
                "sources": [
                  "0x00"
                ],
                "length": 1
              }
            ]
          }
        }
      }
    },
    {
      "push": {
        "storage": true,
        "value": {
          "tag": "cell",
          "content": {
            "atoms": [
              {
                "tag": "field",
                "sources": [
                  "0x07"
                ]
              }
            ]
          }
        }
      }
    },
    {
      "ins": {
        "cached": false,
        "n": 1
      }
    }
  ],
  "field_count": 11
}
```

The `sources` arrays contain identifiers where each identifier is the output of a previously executed ZKIR operation. They're useful when, e.g., multiple field values correspond to the same structured value, e.g. `Bytes<32>`.

#### New TypeScript and JavaScript Targets

The `compactc` compiler currently produces two "executable" files per contract:

- `index.d.ts` — TypeScript declarations for the contract's types, witnesses, and circuits.
- `index.js` — A JavaScript module containing the full circuit logic: type descriptors, witness invocation, ledger operations, circuit implementations, and proof data assembly.

With the new architecture, the circuit execution logic moves into the Rust interpreter exposed via `zkir-v3-wasm`. The compiler output becomes much simpler. TypeScript declarations `index.d.ts` remain unchanged. The dApp still gets typed interfaces for circuits, witnesses, and ledger state. The `index.js` executable becomes a thin wrapper around the `execute` function from `zkir-v3-wasm`. Its only job is type conversion:

```typescript
import { execute } from '@midnight-ntwrk/zkir-v3-wasm';

const _descriptor_0 = new CompactTypeBytes(32);
const _descriptor_1 = new CompactTypeUnsignedInteger(255n, 1);
const _descriptor_2 = ...;

const spendArgAlignment = _descriptor_0.alignment().concat(_descriptor_1.alignment());

export const circuits = (provider) => ({
  spend: async (context, dest_public_key, input_coin) => {
    const args = {
      value: _descriptor_0.toValue(dest_public_key)
              .concat(_descriptor_1.toValue(input_coin)),
      alignment: spendArgAlignment
    };

    const result = await execute(
      context.address,
      'spend',
      args,
      provider
    );

    return {
      result: _descriptor_2.fromValue(result.result),
      context: result.context
    };
  }
});
```

The compiler knows the types of all circuit arguments and return values, so it generates the appropriate `CompactType` descriptors and conversion code. Everything else—circuit execution, ledger operations, witness handling, transcript assembly, communication commitment computation—happens inside the Rust interpreter.

This dramatically simplifies the compiler's code generation and makes the JavaScript output much smaller (dozens of lines instead of hundreds).

## Testing

See [Implementation Plan](#implementation-plan).

## References

[Dynamic Contract Composability](https://github.com/midnightntwrk/midnight-architecture/pull/176)

## Acknowledgements

## Copyright Waiver

All contributions (code and text) submitted in this CoIP must be licensed under the Apache License, Version 2.0.
