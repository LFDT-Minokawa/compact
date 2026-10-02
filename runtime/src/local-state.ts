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
import type { CircuitContext } from './circuit-context.js';
import { LocalTranscriptEntry, PartialProofData } from './proof-data.js';
import { CompactError, assertDefined } from './error.js';

/**
 * Wraps a local `StateValue` in the `QueryContext` the VM runs against. The address is a dummy:
 * local state belongs to no contract address on chain, and the context's effects are unused.
 */
export const createLocalQueryContext = (localState: ocrt.StateValue): ocrt.QueryContext =>
  new ocrt.QueryContext(new ocrt.ChargedState(localState), ocrt.dummyContractAddress());

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
 * Pins a local container's entire value in the local transcript. Iteration observes all of
 * a container, therefore the fold must detect any difference in it, and value equality is
 * the exact pin: the fold re-compares the fold-time container against the rehearsal's
 * snapshot.
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
    value: container.encode(),
  });
};

/** The observed fate of a call's transaction, as the chain reports it. */
export type LocalFoldOutcome =
  | { readonly tag: 'success' }
  | {
      /**
       * The transaction landed with its guaranteed section applied and its fallible section rolled
       * back, therefore only local ops recorded before the checkpoint split apply.
       */
      readonly tag: 'partial';
      /** The length of the landed transaction's guaranteed transcript, which locates the split. */
      readonly guaranteedLength: number;
    };

/**
 * Tier-1 fold: replays a call's recorded local ops in verify mode against a prior local state. A
 * read mismatch means the prior state differs in a way the rehearsal observed; re-executing the
 * call (tier 2) is then the only correct account, and this function reports the divergence by
 * throwing rather than guessing.
 *
 * A transaction that did not land is discarded whole and never folded; `success` applies every
 * recorded batch and `partial` applies only the batches recorded before the checkpoint split.
 */
export const foldLocalTranscript = (
  localState: ocrt.StateValue,
  localTranscript: readonly LocalTranscriptEntry[],
  outcome: LocalFoldOutcome,
  costModel?: ocrt.CostModel,
): ocrt.StateValue => {
  // verify-mode replay wants a budget; local execution is unmetered, so it is nominal
  const gas: ocrt.RunningCost = {
    readTime: 10_000_000_000_000n,
    computeTime: 10_000_000_000_000n,
    bytesWritten: 1_000_000_000n,
    bytesDeleted: 1_000_000_000n,
  };
  const cost = costModel ?? ocrt.CostModel.initialCostModel();
  let ctx = createLocalQueryContext(localState);
  for (const entry of localTranscript) {
    // an entry's offset is the public-op count at record time and the fallible transcript
    // begins with Ckpt, therefore offset === guaranteedLength still precedes the checkpoint
    if (outcome.tag === 'partial' && entry.offset > outcome.guaranteedLength) {
      continue;
    }
    if (entry.tag === 'observe') {
      // the VM's `eq` compares cells only, therefore container pins are checked by the VM's
      // canonical rendering: the decoded snapshot and the fold-time value must print alike
      let matched = true;
      let live = ctx.state.state;
      for (const i of entry.path) {
        const elems = live.asArray();
        if (elems === undefined || i >= elems.length) {
          matched = false;
          break;
        }
        live = elems[i];
      }
      if (matched) {
        matched = live.toString() === ocrt.StateValue.decode(entry.value).toString();
      }
      if (!matched) {
        throw new CompactError(
          `local transcript observation failed at [${entry.path.join(', ')}]: the prior local state differs in a way this call observed, so the call must be re-executed`,
        );
      }
      continue;
    }
    try {
      // local ops never touch effects, therefore the declared effects are the context's own
      ctx = ctx.runTranscript({ gas, effects: ctx.effects, program: entry.ops }, cost);
    } catch (err) {
      if (err instanceof Error) {
        throw new CompactError(
          `local transcript replay failed: ${err.toString()}; the prior local state differs in a way this call observed, so the call must be re-executed`,
        );
      }
      throw err;
    }
  }
  return ctx.state.state;
};
