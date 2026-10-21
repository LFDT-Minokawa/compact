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

// GHSA-7v3r-pgmw-h29c: the caller's proof must bind the callee circuit named at the call site.
// The caller's generated module names it once, as a string handed to the runtime, so an attacker
// who edits that string (and nothing else: same ZKIR, same keys) redirects the call to a sibling
// circuit of the same shape. The claim in the caller's transcript then carries the sibling's entry
// point, and the proof check has to refuse it.

/** The callee's persisted ledger. */
const calleeLedger = (chain: TestChain, address: any): { balance: bigint; decoys: bigint } =>
  calleeCode.ledger(chain.getContractStateOrThrow(address).data);

/** The caller's persisted payment count. */
const payments = (chain: TestChain, address: any): bigint =>
  callerCode.ledger(chain.getContractStateOrThrow(address).data).payments;

/**
 * The caller's module with its call site edited to name `decoy`: the attack from the advisory,
 * applied to the generated JavaScript rather than by hand.
 */
const substitutedCallerCode = async (): Promise<typeof callerCode> => {
  const fs = await import('node:fs');
  const path = await import('node:path');
  const { pathToFileURL } = await import('node:url');
  const contractDir = callerCode.contractDir;
  const source = fs.readFileSync(path.join(contractDir, 'contract', 'index.js'), 'utf-8');
  const callSite = "calleeCircuitId: 'transfer'";
  expect(source.split(callSite).length).toEqual(2);
  const edited = source.replace(callSite, "calleeCircuitId: 'decoy'");
  const editedPath = path.join(contractDir, 'contract', 'index.decoy.js');
  fs.writeFileSync(editedPath, edited);
  const module = await import(/* @vite-ignore */ pathToFileURL(path.resolve(editedPath)).href);
  return { ...module, contractDir };
};

const deployBoth = async (chain: TestChain) => {
  const callee = await chain.deploy({ module: calleeCode, args: [1000n], initialPrivateState: 0 });
  const caller = await chain.deploy({
    module: callerCode,
    args: [callee.encodedAddress],
    initialPrivateState: 0,
  });
  return { callee, caller };
};

describe('cross-contract entry point binding', () => {
  test('an honest call to transfer proves and moves the balance', async () => {
    const chain = new TestChain();
    const { callee, caller } = await deployBoth(chain);

    const { result } = await chain.call({
      module: callerCode,
      address: caller.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'pay',
      args: [10n],
    });
    await flushProofChecks();

    expect(result).toEqual(990n);
    expect(calleeLedger(chain, callee.address)).toEqual({ balance: 990n, decoys: 0n });
    expect(payments(chain, caller.address)).toEqual(1n);
  });

  test('a call redirected to decoy runs, but its proof is refused', async () => {
    const chain = new TestChain();
    const { callee, caller } = await deployBoth(chain);
    const substituted = await substitutedCallerCode();

    // The runtime cannot tell: `decoy` conforms to the declaration and carries a deployed key, so
    // the call succeeds and the caller records a payment that moved nothing.
    const { result } = await chain.call({
      module: substituted,
      address: caller.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'pay',
      args: [10n],
    });
    expect(result).toEqual(10n);
    expect(calleeLedger(chain, callee.address)).toEqual({ balance: 1000n, decoys: 1n });
    expect(payments(chain, caller.address)).toEqual(1n);

    // The caller's circuit claims a call to `transfer`; the transcript records one to `decoy`.
    await expect(flushProofChecks()).rejects.toThrow(/transcript/i);
  });
});
