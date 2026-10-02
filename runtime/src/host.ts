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
import type { PartialProofData } from './proof-data.js';
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
 * A contract's `host` blocks name the runtime-provided functions it requires, and the DApp
 * supplies none of them: the runtime resolves each interface by id when a function is called,
 * so the compiler accepts any well-formed id. This registry is that resolution. It starts with
 * the interfaces compact-runtime implements itself, and {@link registerHostInterface} is the
 * seam through which a capsule runtime - or a test - supplies or replaces one.
 */
const hostInterfaces = new Map<string, HostInterface>();

/**
 * Registers (or replaces) the implementation of a host interface.
 *
 * @param interfaceId The interface id as a contract writes it, e.g. `midnight:capsule/keys@1.0.0`.
 * @param implementation Its functions, keyed by name.
 */
export const registerHostInterface = (interfaceId: string, implementation: HostInterface): void => {
  hostInterfaces.set(interfaceId, implementation);
};

/**
 * The registered implementation of a host function, or a {@link CompactError} naming what is
 * missing when there is none.
 */
export const hostFunction = (interfaceId: string, name: string): HostFunction => {
  const implementation = hostInterfaces.get(interfaceId);
  if (implementation === undefined) {
    throw new CompactError(
      `no implementation of host interface ${interfaceId} is registered (registerHostInterface supplies one)`,
    );
  }
  const fn = implementation[name];
  if (typeof fn !== 'function') {
    throw new CompactError(`the implementation of host interface ${interfaceId} has no function ${name}`);
  }
  return fn;
};

/**
 * Calls a host function on behalf of the generated code, which type-checks the result against
 * the contract's declared type and records it with {@link recordHostOutput}.
 */
export const callHostFunction = (context: CircuitContext, interfaceId: string, name: string, args: readonly any[]): any =>
  hostFunction(interfaceId, name)(context, ...args);

/**
 * Records a host function's result in the call's proof data. Every host result is pinned
 * nondeterminism the fold re-executes against (plan §4.2), whoever called the function; a
 * caller in a circuit additionally pushes the result as a private input at its call site.
 */
export const recordHostOutput = (partialProofData: PartialProofData, output: ocrt.AlignedValue): void => {
  (partialProofData.hostOutputs ??= []).push(output);
};

// The interfaces compact-runtime implements. The zswap functions are the wallet's coin
// operations, which the standard library declares as a host block and which are served from
// the context's Zswap local state. The capsule secret (`midnight:capsule/keys@1.0.0`,
// `secretKey(): Bytes<32>`) has no source in compact-runtime and its derivation is open
// (plan §6.12), therefore nothing implements it here: a call fails until a capsule runtime
// registers it.
registerHostInterface('midnight:capsule/zswap@1.0.0', {
  ownPublicKey: (context) => ownPublicKey(context),
  createZswapInput: (context, coin) => createZswapInput(context, coin),
  createZswapOutput: (context, coin, recipient) => createZswapOutput(context, coin, recipient),
});
