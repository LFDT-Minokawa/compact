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

/** Read the callee's `v` ledger field from the chain's persisted state. */
const calleeV = (chain: TestChain, address: any): bigint =>
  calleeCode.ledger(chain.getContractStateOrThrow(address).data).v;

// The callee declares the `secret` witness, so it can only be *constructed* with a
// witnesses object that supplies it (used when deploying it standalone). Cross-contract
// calls construct the callee with a guard proxy instead, which is why a witness-free
// callee circuit still runs while a witness-invoking one throws.
const calleeWitnesses = {
  secret: ({ privateState }: any): [any, any] => [privateState, 7n],
};

const deployPair = async (chain: TestChain) => {
  const callee = await chain.deploy({
    module: calleeCode,
    args: [],
    initialPrivateState: 0,
    witnesses: calleeWitnesses,
  });
  const caller = await chain.deploy({
    module: callerCode,
    args: [callee.encodedAddress],
    initialPrivateState: 0,
  });
  return { callee, caller };
};

describe('cross-contract calls into a witness-defining callee', () => {
  test('a witness-free callee circuit executes even though the contract declares a witness', async () => {
    const chain = new TestChain();
    const { callee, caller } = await deployPair(chain);

    // callBump -> callee.bump: writes the callee's ledger and never touches `secret`,
    // so the guard proxy is never invoked and the call succeeds.
    const { result } = (await chain.call({
      module: callerCode,
      address: caller.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'callBump',
      args: [5n],
    })) as { result: bigint };

    expect(result).toEqual(5n);
    expect(calleeV(chain, callee.address)).toEqual(5n);
  });

  test('a callee circuit that invokes a witness fails with an informative error', async () => {
    const chain = new TestChain();
    const { callee, caller } = await deployPair(chain);

    // callLeak -> callee.leak invokes the `secret` witness. Witnesses are available only
    // to the entry (root) contract, so the guard proxy throws an error naming both the
    // callee and the witness.
    await expect(
      chain.call({
        module: callerCode,
        address: caller.address,
        witnesses: {},
        privateState: 0,
        circuitId: 'callLeak',
        args: [],
      }),
    ).rejects.toThrow(`Cross-contract callee '${callee.address}' invoked witness 'secret'`);
  });
});
