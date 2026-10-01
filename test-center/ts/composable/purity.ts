// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/** Invoke a circuit on the Liar contract as a call transaction. */
const callLiar = (
  chain: TestChain,
  address: any,
  circuitId: string,
  ...args: readonly unknown[]
): Promise<{ result: any; context: any }> =>
  chain.call({
    module: liarCode,
    address,
    witnesses: {},
    privateState: 0,
    circuitId,
    args,
  }) as unknown as Promise<{ result: any; context: any }>;

describe('cross-contract conformance gate', () => {
  test('a callee that is not a provable circuit cannot satisfy an impure declaration', async () => {
    const chain = new TestChain();
    // `Honest.add` touches no ledger fields, so it is pure; `Liar`'s `contract Honest` declares `add`
    // without `pure`. A pure circuit cannot satisfy an impure declaration.
    const honest = await chain.deploy({ module: honestCode, args: [], initialPrivateState: 0 });
    const liar = await chain.deploy({
      module: liarCode,
      args: [honest.encodedAddress],
      initialPrivateState: 0,
    });

    const error = await callLiar(chain, liar.address, 'callAdd', 5n).then(
      () => undefined,
      (e: unknown) => e,
    );
    if (!runtime.ModuleResolutionError.is(error)) {
      throw new Error(`expected a ModuleResolutionError, got ${String(error)}`);
    }
    // The context says which call could not be bound, independently of why.
    expect(error.context.calleeCircuitId).toEqual('add');
    expect(error.context.interfaceName).toEqual('Honest');
    expect(error.context.calleeAddress).toEqual(honest.address);

    if (error.failure.kind !== 'NonconformantImplementation') {
      throw new Error(`expected NonconformantImplementation, got ${error.failure.kind}`);
    }
    expect(error.failure.check).toEqual('Provability');
    expect(error.failure.circuitId).toEqual('add');
  });
});
