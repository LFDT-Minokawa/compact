// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

// Enums cross a call between contracts as the unions host code sees: the caller hands the
// callee's circuit what host code would, and takes back what host code would get.

const B32 = (n: number) => new Uint8Array(32).fill(n);

const deployBoth = async (chain: TestChain) => {
  const callee = await chain.deploy({ module: calleeCode, args: [], initialPrivateState: 0 });
  const caller = await chain.deploy({
    module: callerCode,
    args: [callee.encodedAddress],
    initialPrivateState: 0,
  });
  return { callee, caller };
};

const relay = (chain: TestChain, address: any, ...args: any[]) =>
  chain.call({ module: callerCode, address, witnesses: {}, privateState: 0, circuitId: 'relay', args });

describe('enums across a call between contracts', () => {
  test('arguments and results keep their variants, and the proofs check', async () => {
    const chain = new TestChain();
    const { callee, caller } = await deployBoth(chain);
    const filled = { tag: 'Filled', values: [B32(1), 5n] };

    let { result } = await relay(chain, caller.address, filled, { tag: 'Some', value: 9n });
    await flushProofChecks();
    expect(result).toEqual({ tag: 'Right', value: 9n });
    expect(calleeCode.ledger(chain.getContractStateOrThrow(callee.address).data).last).toEqual(filled);
    expect(calleeCode.ledger(chain.getContractStateOrThrow(callee.address).data).note).toEqual({ tag: 'Some', value: 9n });
    expect(callerCode.ledger(chain.getContractStateOrThrow(caller.address).data).seen).toEqual({ tag: 'Right', value: 9n });

    ({ result } = await relay(chain, caller.address, { tag: 'Cancelled', value: B32(2) }, { tag: 'None' }));
    await flushProofChecks();
    expect(result).toEqual({ tag: 'Left', value: { tag: 'Cancelled', value: B32(2) } });
    expect(callerCode.ledger(chain.getContractStateOrThrow(caller.address).data).seen).toEqual(result);
  });
});
