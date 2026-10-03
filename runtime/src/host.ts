// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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
import type { PartialProofData } from './proof-data.js';
import type { HostInterfaceProvider } from './providers.js';
import { CompactError } from './error.js';
import { createZswapInput, createZswapOutput, ownPublicKey } from './zswap.js';

/**
 * The implementation of one host function: the executing circuit's context, then the
 * contract's arguments as the generated code passes them.
 */
export type HostFunction = (context: CircuitContext, ...args: any[]) => any;

/**
 * The implementation of one host interface, keyed by the interface's function names.
 */
export type HostInterface = Readonly<Record<string, HostFunction>>;

/**
 * What a contract's `host` blocks require of its environment: the function names declared of
 * each interface id, as the generated module exports them (`hostInterfaces`) and contract-info
 * lists them. Only functions a circuit can reach are listed, so this is what a run can call, not
 * what the source mentions.
 */
export type HostInterfaceRequirements = Readonly<Record<string, readonly string[]>>;

/**
 * One required interface a provider does not satisfy: `missing` is every required function with
 * no implementation, which is all of them when the provider `resolved` nothing under the id.
 */
export type HostInterfaceGap = {
  readonly interfaceId: string;
  readonly resolved: boolean;
  readonly missing: readonly string[];
};

/**
 * The requirements a provider does not meet, in the requirements' order; with no provider, every
 * requirement. A module's requirements and the provider are both known before anything runs,
 * therefore a gap is a property of the (module, environment) pair and not of a call: a
 * cross-contract call checks this at resolution rather than failing at the first host call on
 * some path, a root circuit checks it at entry ({@link assertHostInterfaces}), and the lookup in
 * {@link callHostFunction} stays as the backstop for both.
 */
export const missingHostFunctions = (
  requirements: HostInterfaceRequirements,
  provider: HostInterfaceProvider | undefined,
): HostInterfaceGap[] => {
  const gaps: HostInterfaceGap[] = [];
  for (const [interfaceId, names] of Object.entries(requirements)) {
    const implementation = provider?.resolve(interfaceId);
    const missing = names.filter((name) => typeof implementation?.[name] !== 'function');
    if (missing.length !== 0) {
      gaps.push({ interfaceId, resolved: implementation !== undefined, missing });
    }
  }
  return gaps;
};

/** How a gap reads, for the root's entry check and the call-time backstop. */
const describeGap = (gap: HostInterfaceGap): string =>
  gap.resolved
    ? `the implementation the host interface provider resolves for '${gap.interfaceId}' has no function ${gap.missing.join(', ')}`
    : `the host interface provider resolves no '${gap.interfaceId}', of which ${gap.missing.join(', ')} ${gap.missing.length === 1 ? 'is' : 'are'} required`;

const NO_PROVIDER = 'the circuit context carries no host interface provider (pass hostInterfaceProvider to createCircuitContext)';

/**
 * The root's gate, run by the generated wrapper at the entry of every exported impure circuit of a
 * contract that declares host functions: the first point where the module's requirements and the
 * context's provider meet without the application's help, before the prologue and before anything
 * is recorded. A root has no resolution step, so this is a plain error rather than a
 * `ModuleResolutionError`; a callee reaching it has already passed the same check at resolution.
 */
export const assertHostInterfaces = (
  context: CircuitContext,
  requirements: HostInterfaceRequirements,
  circuitName: string,
): void => {
  if (Object.keys(requirements).length === 0) {
    return;
  }
  const provider = context.hostInterfaceProvider;
  if (provider === undefined) {
    throw new CompactError(`${circuitName}: the contract declares host functions but ${NO_PROVIDER}`);
  }
  const gap = missingHostFunctions(requirements, provider)[0];
  if (gap !== undefined) {
    throw new CompactError(`${circuitName}: ${describeGap(gap)}`);
  }
};

/**
 * Calls a host function on behalf of the generated code, resolving it through the context's
 * {@link HostInterfaceProvider}; the generated code type-checks the result against the contract's
 * declared type and records it with {@link recordHostOutput}. The gates above make a miss here
 * unreachable from generated code unless the provider's answers change between entry and call.
 */
export const callHostFunction = (context: CircuitContext, interfaceId: string, name: string, args: readonly any[]): any => {
  const provider = context.hostInterfaceProvider;
  if (provider === undefined) {
    throw new CompactError(`cannot call host function ${name} of ${interfaceId}: ${NO_PROVIDER}`);
  }
  const implementation = provider.resolve(interfaceId);
  const fn = implementation?.[name];
  if (typeof fn !== 'function') {
    throw new CompactError(
      `cannot call host function ${name} of ${interfaceId}: ${describeGap({ interfaceId, resolved: implementation !== undefined, missing: [name] })}`,
    );
  }
  return fn(context, ...args);
};

/**
 * Records a host function's result in the call's proof data. Every host result is pinned
 * nondeterminism the fold re-executes against (plan §4.2), whoever called the function; a
 * caller in a circuit additionally pushes the result as a private input at its call site.
 */
export const recordHostOutput = (partialProofData: PartialProofData, output: ocrt.AlignedValue): void => {
  (partialProofData.hostOutputs ??= []).push(output);
};

/** The id under which the standard library declares the wallet's coin operations. */
export const ZSWAP_HOST_INTERFACE_ID = 'midnight:capsule/zswap@1.0.0';

/**
 * An implementation of the standard library's coin operations, served from the context's Zswap
 * local state, which this package owns. An ordinary {@link HostInterface} for a provider to serve
 * under {@link ZSWAP_HOST_INTERFACE_ID}: the runtime resolves it no more than any other interface.
 */
export const zswapHostInterface: HostInterface = {
  ownPublicKey: (context) => ownPublicKey(context),
  createZswapInput: (context, coin) => createZswapInput(context, coin),
  createZswapOutput: (context, coin, recipient) => createZswapOutput(context, coin, recipient),
};
