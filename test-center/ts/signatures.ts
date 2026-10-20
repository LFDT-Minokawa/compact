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

// The signature exports beyond `circuitSignatures`: a party holding no module encodes a deploy's
// arguments, a call's arguments and a host function's answers against them, and a host decodes
// what it receives with the same descriptors, therefore each export is checked against what the
// module itself exposes or encodes, not only against a pinned shape.

const CALLEE = { tag: 'Contract', name: 'Callee', circuits: {
  ping: { pure: false, argumentTypes: [{ tag: 'Uint', maxval: '255' }], resultType: { tag: 'Uint', maxval: '255' } },
} };
const COLOR = { tag: 'Enum', name: 'Color', elements: ['red', 'green', 'blue'] };
const INNER = { tag: 'Struct', name: 'Inner', elements: [{ name: 'f', type: { tag: 'Field' } }] };
const OUTER = { tag: 'Struct', name: 'Outer', elements: [{ name: 'i', type: INNER }, { name: 'b', type: { tag: 'Boolean' } }] };
const BYTES32 = { tag: 'Bytes', length: 32 };
const U64 = { tag: 'Uint', maxval: '18446744073709551615' };

const OWNER = new Uint8Array(32).fill(1);
const CALLEE_ADDRESS = { bytes: runtime.encodeContractAddress(runtime.sampleContractAddress()) };

const ORACLE = {
  'test:oracle/data@1.0.0': {
    credential: (_: unknown, subject: Uint8Array, nonce: bigint) => ({ i: { f: BigInt(subject[0]) + nonce }, b: true }),
    random: () => 11n,
  },
};

test('constructorSignature lists the constructor parameters in order', () => {
  expect(contractCode.constructorSignature).toEqual({ argumentTypes: [BYTES32, CALLEE, COLOR], argumentNames: ['o', 'c', 'color'] });
});

test('ledgerSignatures names exactly the fields ledger() exposes, with their storage and types', async () => {
  const [, context] = await startContract(contractCode, OWNER, CALLEE_ADDRESS, 1);
  expect(contractCode.ledgerSignatures).toEqual({
    fields: {
      owner: { storage: 'Cell', type: BYTES32 },
      callee: { storage: 'Cell', type: CALLEE },
      tally: { storage: 'Counter' },
      members: { storage: 'Set', type: BYTES32 },
      marks: { storage: 'Map', key: { tag: 'Bytes', length: 1 }, value: { storage: 'Counter' } },
      prices: { storage: 'Map', key: { tag: 'Uint', maxval: '255' }, value: U64 },
      queue: { storage: 'List', type: COLOR },
      tree: { storage: 'MerkleTree', depth: 4, type: { tag: 'Field' } },
      history: { storage: 'HistoricMerkleTree', depth: 3, type: BYTES32 },
    },
  });
  const view = contractCode.ledger(context.callContext.currentQueryContext.state);
  expect(Object.keys(view)).toEqual(Object.keys(contractCode.ledgerSignatures.fields));
  // what a signature says a field holds is what the accessor decodes
  expect(view.owner).toEqual(OWNER);
  expect(view.callee).toEqual(CALLEE_ADDRESS);
});

test('localStateSignatures names exactly the fields and functions localState() exposes', async () => {
  const [, context] = await startContract(contractCode, OWNER, CALLEE_ADDRESS, 1);
  expect(contractCode.localStateSignatures).toEqual({
    fields: {
      credits: { storage: 'Cell', type: { tag: 'Uint', maxval: '15' } },
      last: { storage: 'Cell', type: { tag: 'Struct', name: 'Maybe', elements: [
        { name: 'is_some', type: { tag: 'Boolean' } },
        { name: 'value', type: BYTES32 },
      ] } },
      seen: { storage: 'Set', type: BYTES32 },
    },
    functions: {
      remaining: { argumentTypes: [], argumentNames: [], resultType: { tag: 'Uint', maxval: '15' }, readsLedger: false },
      quote: { argumentTypes: [{ tag: 'Uint', maxval: '255' }, U64], argumentNames: ['k', 'fallback'], resultType: U64, readsLedger: true },
    },
  });
  const { fields, functions } = contractCode.localStateSignatures;
  const view = contractCode.localState(contractCode.initialLocalState(), context.callContext.currentQueryContext.state);
  expect(Object.keys(view).sort()).toEqual([...Object.keys(fields), ...Object.keys(functions)].sort());
  for (const name of Object.keys(functions)) {
    expect(typeof (view as unknown as Record<string, unknown>)[name]).toEqual('function');
  }
  // the declaration default, since the local constructor runs only at the first landed call
  expect(view.remaining()).toEqual(0n);
  expect(view.quote(9n, 42n)).toEqual(42n);
});

test('hostInterfaceSignatures carries the declared types of exactly the functions hostInterfaces names', () => {
  const requirements = contractCode.hostInterfaces;
  const signatures = contractCode.hostInterfaceSignatures;
  expect(Object.keys(signatures)).toEqual(Object.keys(requirements));
  for (const id of Object.keys(requirements)) {
    expect(Object.keys(signatures[id])).toEqual(requirements[id]);
  }
  // the unused block is in neither
  expect(signatures).toEqual({
    'test:oracle/data@1.0.0': {
      credential: { argumentTypes: [BYTES32, U64], argumentNames: ['subject', 'nonce'], resultType: OUTER },
      random: { argumentTypes: [], argumentNames: [], resultType: { tag: 'Field' } },
    },
  });
});

test('descriptorOf encodes every value crossing a circuit boundary as the module does', async () => {
  const [contract, deployed] = await startContract(contractCode, OWNER, CALLEE_ADDRESS, 1);
  const context = withHostInterfaces(deployed, ORACLE);
  const subject = new Uint8Array(32).fill(5);
  const args = [{ i: { f: 5n }, b: true }, 2, new Uint8Array(8).fill(9), 7n, [1n, 2n], [3n, false], subject, 4n];
  const r = await contract.circuits.act(context, ...args);
  expect(r.result).toEqual({ f: 11n + 5n + 4n });
  const entry = r.context.callProofDataTrace.at(-1)!;
  const { argumentTypes, resultType } = contractCode.circuitSignatures.act;
  // the input the proof commits to is the arguments encoded by the module's own descriptors
  const descriptors = argumentTypes.map(runtime.descriptorOf);
  expect(entry.input).toEqual({
    value: descriptors.flatMap((d, i) => d.toValue(args[i])),
    alignment: descriptors.flatMap((d) => d.alignment()),
  });
  const result = runtime.descriptorOf(resultType);
  expect(entry.output).toEqual({ value: result.toValue(r.result), alignment: result.alignment() });
  // and the same descriptors decode it back, consuming exactly the input
  const stream = [...entry.input.value];
  expect(descriptors.map((d) => d.fromValue(stream))).toEqual(args);
  expect(stream).toHaveLength(0);
  // a host call's question and answer are encoded the same way
  const host = contractCode.hostInterfaceSignatures['test:oracle/data@1.0.0'];
  const credentialArgs = host.credential.argumentTypes.map(runtime.descriptorOf);
  const credentialResult = runtime.descriptorOf(host.credential.resultType);
  expect(entry.hostOutputs).toEqual([
    {
      interfaceId: 'test:oracle/data@1.0.0',
      name: 'credential',
      args: { value: credentialArgs.flatMap((d, i) => d.toValue([subject, 4n][i])), alignment: credentialArgs.flatMap((d) => d.alignment()) },
      result: { value: credentialResult.toValue({ i: { f: 9n }, b: true }), alignment: credentialResult.alignment() },
    },
    {
      interfaceId: 'test:oracle/data@1.0.0',
      name: 'random',
      args: { value: [], alignment: [] },
      result: { value: runtime.CompactTypeField.toValue(11n), alignment: runtime.CompactTypeField.alignment() },
    },
  ]);
});
