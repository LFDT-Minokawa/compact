// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import { sha256 } from '@noble/hashes/sha2.js';
import { bytesToHex } from '@noble/hashes/utils.js';
import type { CallProofDataTrace, CircuitContext, CircuitId } from './circuit-context.js';
import { CalleeReturn, HostOutput, LocalTranscriptEntry, PartialProofData } from './proof-data.js';
import { CompactError, assertDefined } from './error.js';

/**
 * Wraps a local `StateValue` in the `QueryContext` the VM runs against. The address is a dummy:
 * local state belongs to no contract address on chain, and the context's effects are unused.
 */
export const createLocalQueryContext = (localState: ocrt.StateValue): ocrt.QueryContext =>
  new ocrt.QueryContext(new ocrt.ChargedState(localState), ocrt.dummyContractAddress());

/**
 * The SHA-256 of a state value's canonical serialization, as lowercase hex: equal digests mean equal
 * contents, whatever history built them. The wasm `StateValue` exposes no equality, serialization or
 * hash, therefore the value is serialized as the data of an otherwise empty `ContractState`, whose
 * serialization is the ledger's own.
 */
export const stateValueDigest = (value: ocrt.StateValue): string => {
  const carrier = new ocrt.ContractState();
  carrier.data = new ocrt.ChargedState(value);
  return bytesToHex(sha256(carrier.serialize()));
};

/**
 * The local state of every contract in the call tree that keeps one, by address, as the
 * `StateValue`s an application compares a fold of the call's records against. A plain view of
 * {@link CircuitContext.localQueryContexts}, which holds the VM contexts the call ran against.
 */
export const localStates = (circuitContext: CircuitContext): Record<ocrt.ContractAddress, ocrt.StateValue> =>
  Object.fromEntries(
    Object.entries(circuitContext.localQueryContexts).map(([address, queryContext]) => [address, queryContext.state.state]),
  );

/**
 * Runs a program (query) against the current local state in the given circuit context. Records the
 * ops, `popeq` results filled and offset-tagged, in the given partial proof data's local
 * transcript.
 *
 * The mirror of {@link queryLedgerState} for the local store: same op vocabulary, same gather-mode
 * execution, but nothing here reaches the public transcript or the proof — a local read's result
 * enters the proof only if the caller pushes it as a private input.
 *
 * @param circuitContext The context for the currently executing circuit.
 * @param partialProofData The partial proof data to record the local transcript into.
 * @param program The query to run.
 */
export const queryLocalState = (
  circuitContext: CircuitContext,
  partialProofData: PartialProofData,
  program: ocrt.Op<null>[],
): ocrt.AlignedValue | undefined => {
  const localQueryContext = circuitContext.callContext.currentLocalQueryContext;
  assertDefined(
    localQueryContext,
    `local state for contract '${circuitContext.callContext.contractAddress}' (was 'localState' supplied to createCircuitContext?)`,
  );
  try {
    const res = localQueryContext.query(program, circuitContext.costModel);
    circuitContext.callContext.currentLocalQueryContext = res.context;
    // The query returns a fresh context, therefore the per-address cell is re-pointed with the live
    // one, as `queryLedgerState` does; a cross-contract return reads the callee's state from the
    // map. Only in a real circuit context: the `localState()` accessor and `initialLocalState()`
    // run against a synthetic one with no address and no maps.
    const liveAddress = circuitContext.callContext.contractAddress;
    if (liveAddress !== undefined && circuitContext.localQueryContexts !== undefined) {
      circuitContext.localQueryContexts[liveAddress] = res.context;
    }

    const reads = res.events.filter((e) => e.tag === 'read');
    let i = 0;
    const ops = program.map((op) =>
      typeof op === 'object' && 'popeq' in op ? { popeq: { ...op.popeq, result: reads[i++].content } } : op,
    ) as ocrt.Op<ocrt.AlignedValue>[];
    (partialProofData.localTranscript ??= []).push({
      tag: 'ops',
      offset: partialProofData.publicTranscript.length,
      ops,
    });

    if (res.events.length === 1 && res.events[0].tag === 'read') {
      return res.events[0].content;
    }
    return undefined;
  } catch (err) {
    if (err instanceof Error) {
      throw new CompactError(err.toString());
    }
    throw err;
  }
};

/**
 * Pins a local container's entire value in the local transcript, as its {@link stateValueDigest}.
 * Iteration observes all of a container, therefore the fold must detect any difference in it, and
 * equality of contents is the exact pin: the fold recomputes the digest of the fold-time container.
 *
 * @param circuitContext The context for the currently executing circuit.
 * @param partialProofData The partial proof data to record the pin into.
 * @param path The container's indices under the local state root.
 */
export const pinLocalContainer = (
  circuitContext: CircuitContext,
  partialProofData: PartialProofData,
  path: readonly number[],
): void => {
  const localQueryContext = circuitContext.callContext.currentLocalQueryContext;
  assertDefined(
    localQueryContext,
    `local state for contract '${circuitContext.callContext.contractAddress}' (was 'localState' supplied to createCircuitContext?)`,
  );
  let container = localQueryContext.state.state;
  for (const i of path) {
    const elems = container.asArray();
    assertDefined(elems, `an addressable local state at [${path.join(', ')}]`);
    container = elems[i];
  }
  (partialProofData.localTranscript ??= []).push({
    tag: 'observe',
    offset: partialProofData.publicTranscript.length,
    path,
    digest: stateValueDigest(container),
  });
};

/**
 * What a call read besides its inputs and the local state, therefore what a re-execution must be
 * given again: the ledger it ran against and the block it ran in.
 */
export interface LocalRecordBasis {
  /**
   * The VM call context the call started with: the parent block hash, the block time and its
   * error bound, the last block time, the caller, the balance and the commitment indices.
   */
  readonly callContext: ocrt.CallContext;
  /**
   * The {@link stateValueDigest} of the contract's public state the call started from. A block hash
   * alone does not name it, because a callee's second call in a transaction starts from the state
   * the first call left.
   */
  readonly stateDigest: string;
}

/**
 * One call's account of its effect on its contract's local state, as a fold consumes it: projected
 * from the call's proof data, with the basis made explicit and the proof's own data left behind.
 * It has no byte encoding yet, because the binding serializes neither ops nor state values.
 */
export interface LocalRecord {
  readonly contractAddress: ocrt.ContractAddress;
  readonly circuitId: CircuitId;
  readonly input: ocrt.AlignedValue;
  readonly basis: LocalRecordBasis;
  readonly localTranscript: readonly LocalTranscriptEntry[];
  readonly hostOutputs: readonly HostOutput[];
  readonly calleeReturns: readonly CalleeReturn[];
  /** Every value that crossed into the proof, in order, local results among them. */
  readonly privateTranscriptOutputs: readonly ocrt.AlignedValue[];
}

/**
 * The records a fold needs from a call's trace, in trace order: one for each call that left a local
 * transcript. A call that left none read no local state, therefore it takes the same path from any
 * prior and has nothing to fold. The basis digest is computed here rather than during the call, so
 * a call that never touches local state does not pay for it.
 */
export const localRecordsOf = (trace: CallProofDataTrace): LocalRecord[] =>
  trace.flatMap((callProofData) =>
    callProofData.localTranscript === undefined
      ? []
      : [
          {
            contractAddress: callProofData.contractAddress,
            circuitId: callProofData.circuitId,
            input: callProofData.input,
            basis: {
              callContext: callProofData.initialQueryContext.block,
              stateDigest: stateValueDigest(callProofData.initialQueryContext.state.state),
            },
            localTranscript: callProofData.localTranscript,
            hostOutputs: callProofData.hostOutputs ?? [],
            calleeReturns: callProofData.calleeReturns ?? [],
            privateTranscriptOutputs: callProofData.privateTranscriptOutputs,
          },
        ],
  );

/** The observed fate of a call's transaction, as the chain reports it. */
export type LocalFoldOutcome =
  | { readonly tag: 'success' }
  | {
      /**
       * The transaction landed with its guaranteed section applied and its fallible section rolled
       * back, therefore only local ops recorded before the checkpoint split apply.
       */
      readonly tag: 'partial';
      /** The length of the call's guaranteed transcript as the landed transaction carries it, which locates the split. */
      readonly guaranteedLength: number;
    }
  /** The transaction did not land, therefore its record folds nothing. */
  | { readonly tag: 'failure' };

/** One step of a fold: a record, and the fate of the transaction it belongs to. */
export interface LocalFoldStep {
  readonly record: LocalRecord;
  readonly outcome: LocalFoldOutcome;
}

/**
 * Why a step's record did not replay: the prior local state differs in a way the call observed, so
 * only re-executing the call (tier 2) accounts for it. `entryIndex` is the failing entry of the
 * record's local transcript.
 */
export type LocalFoldDivergence =
  /** An `observe` entry's digest differs from the folding state's value at `path`, or nothing is there. */
  | { readonly kind: 'ObservationMismatch'; readonly entryIndex: number; readonly path: readonly number[] }
  /** An `ops` entry did not replay in verify mode, a read seeing another value or an op faulting; `message` is the VM's. */
  | { readonly kind: 'ReplayFailed'; readonly entryIndex: number; readonly message: string };

/** What a fold reached. */
export type LocalFoldResult =
  | { readonly tag: 'folded'; readonly state: ocrt.StateValue }
  | {
      readonly tag: 'diverged';
      /** The step whose record did not replay. */
      readonly stepIndex: number;
      /** The state the steps before it reached: where a re-execution of that step starts, and the fold resumes. */
      readonly prior: ocrt.StateValue;
      readonly divergence: LocalFoldDivergence;
    };

// verify-mode replay wants a budget; local execution is unmetered, so it is nominal
const NOMINAL_GAS: ocrt.RunningCost = {
  readTime: 10_000_000_000_000n,
  computeTime: 10_000_000_000_000n,
  bytesWritten: 1_000_000_000n,
  bytesDeleted: 1_000_000_000n,
};

// one record's replay: the state it reached, or why it did not replay
type LocalReplay =
  | { readonly tag: 'replayed'; readonly state: ocrt.StateValue }
  | { readonly tag: 'diverged'; readonly divergence: LocalFoldDivergence };

const replayLocalTranscript = (
  localState: ocrt.StateValue,
  localTranscript: readonly LocalTranscriptEntry[],
  outcome: Exclude<LocalFoldOutcome, { tag: 'failure' }>,
  cost: ocrt.CostModel,
): LocalReplay => {
  let ctx = createLocalQueryContext(localState);
  for (const [entryIndex, entry] of localTranscript.entries()) {
    // an entry's offset is the public-op count at record time and the fallible transcript
    // begins with Ckpt, therefore offset === guaranteedLength still precedes the checkpoint
    if (outcome.tag === 'partial' && entry.offset > outcome.guaranteedLength) {
      continue;
    }
    if (entry.tag === 'observe') {
      let live: ocrt.StateValue | undefined = ctx.state.state;
      for (const i of entry.path) {
        const elems: ocrt.StateValue[] | undefined = live?.asArray();
        live = elems !== undefined && i < elems.length ? elems[i] : undefined;
      }
      if (live === undefined || stateValueDigest(live) !== entry.digest) {
        return { tag: 'diverged', divergence: { kind: 'ObservationMismatch', entryIndex, path: entry.path } };
      }
      continue;
    }
    try {
      // local ops never touch effects, therefore the declared effects are the context's own
      ctx = ctx.runTranscript({ gas: NOMINAL_GAS, effects: ctx.effects, program: entry.ops }, cost);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      return { tag: 'diverged', divergence: { kind: 'ReplayFailed', entryIndex, message } };
    }
  }
  return { tag: 'replayed', state: ctx.state.state };
};

// what is wrong with an outcome a JavaScript caller built, if anything
const outcomeDefect = (outcome: LocalFoldOutcome): string | undefined => {
  switch (outcome.tag) {
    case 'success':
    case 'failure':
      return undefined;
    case 'partial':
      return Number.isSafeInteger(outcome.guaranteedLength) && outcome.guaranteedLength >= 0
        ? undefined
        : `a partial outcome's guaranteed length is a transcript length, not ${String(outcome.guaranteedLength)}`;
    default:
      return `an outcome is 'success', 'partial' or 'failure', not '${String((outcome as { tag: unknown }).tag)}'`;
  }
};

/**
 * Tier-1 fold of one capsule's records in chain order: each step's record replays in verify mode
 * against the state the steps before it reached. `success` applies every recorded entry, `partial`
 * only those recorded before the checkpoint split, and `failure` nothing. A record that does not
 * replay means the prior differs in a way its call observed, which concurrency makes an expected
 * event rather than a defect, therefore it is returned, with what a re-execution of that step
 * needs to take over, rather than thrown. Steps naming different contracts, or a malformed outcome
 * (an unknown tag, or a `partial` length that is not a transcript length), are defects and throw,
 * before any step folds.
 */
export const foldLocalState = (
  prior: ocrt.StateValue,
  steps: readonly LocalFoldStep[],
  costModel?: ocrt.CostModel,
): LocalFoldResult => {
  for (const [stepIndex, { record, outcome }] of steps.entries()) {
    if (record.contractAddress !== steps[0].record.contractAddress) {
      throw new CompactError(
        `foldLocalState folds one contract's local state, but step ${stepIndex} is a record of ${record.contractAddress} and step 0 one of ${steps[0].record.contractAddress}`,
      );
    }
    const defect = outcomeDefect(outcome);
    if (defect !== undefined) {
      throw new CompactError(`foldLocalState: step ${stepIndex}: ${defect}`);
    }
  }
  const cost = costModel ?? ocrt.CostModel.initialCostModel();
  let state = prior;
  for (const [stepIndex, { record, outcome }] of steps.entries()) {
    if (outcome.tag === 'failure') {
      continue;
    }
    const replay = replayLocalTranscript(state, record.localTranscript, outcome, cost);
    if (replay.tag === 'diverged') {
      return { tag: 'diverged', stepIndex, prior: state, divergence: replay.divergence };
    }
    state = replay.state;
  }
  return { tag: 'folded', state };
};
