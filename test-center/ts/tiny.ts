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

const contract = () => new contractCode.Contract({ private$secret_key: ({ privateState }: any) => [privateState, new Uint8Array(32)] });

test('Check for initial get', () => {
  const [c, Ctxt] = startContract(contract, 0, 64n);
  expect(c.circuits.get(Ctxt).result).toEqual({ is_some: true, value: 64n })
});

test('Check for clear, set, get', () => {
  var [c, Ctxt] = startContract(contract, 0, 64n);
  Ctxt = c.circuits.clear(Ctxt).context;
  Ctxt = c.circuits.set(Ctxt, 5n).context;
  var q = c.circuits.get(Ctxt).result;
  expect(q).toEqual({ is_some: true, value: 5n })
});

test('Check for clear, set, set', () => {
  var [c, Ctxt] = startContract(contract, 0, 64n);
  Ctxt = c.circuits.clear(Ctxt).context;
  Ctxt = c.circuits.set(Ctxt, 5n).context;
  expect(() => c.circuits.set(Ctxt, 7n)).toThrow(runtime.CompactError);
});

test('Check for clear, get', () => {
  var [c, Ctxt] = startContract(contract, 0, 64n);
  Ctxt = c.circuits.clear(Ctxt).context;
  expect(c.circuits.get(Ctxt).result).toEqual({ is_some: false, value: 0n })
});

test('Check with actually big int', () => {
  var [c, Ctxt] = startContract(contract, 0, 64n);
  Ctxt = c.circuits.clear(Ctxt).context;
  const n = 1000000000000000000000000n
  Ctxt = c.circuits.set(Ctxt, n).context;
  expect(c.circuits.get(Ctxt).result).toEqual({ is_some: true, value: n });
});

test('Check resulting proofData', () => {
  var [c, Ctxt] = startContract(contract, 0, 64n);
  expect(c.circuits.get(Ctxt).proofData).toEqual(
    {
      "input":
        {
          "alignment": [],
          "value": []
        },
      "output":
        {
          "alignment": [{"tag": "atom", "value": {"length": 1, "tag": "bytes"}},
                        {"tag": "atom", "value": {"tag": "field"}}],
           "value": [new Uint8Array([1]),
                     new Uint8Array([64])]
        },
      "privateTranscriptOutputs": [],
      "publicTranscript": [
        { dup: { n: 0 } },
        { idx: { cached: false, pushPath: false, path: [
          { tag: 'value', value: {
            alignment: [ { tag: 'atom', value: { tag: 'bytes', length: 1 } } ],
            value: [ new Uint8Array([2]) ],
          } },
        ] } },
        { popeq: { cached: false, result: {
          alignment: [ { tag: 'atom', value: { tag: 'bytes', length: 1 } } ],
          value: [new Uint8Array([1])],
        } } },
        { dup: { n: 0 } },
        { idx: { cached: false, pushPath: false, path: [
          { tag: 'value', value: {
            alignment: [ { tag: 'atom', value: { tag: 'bytes', length: 1 } } ],
            value: [ new Uint8Array([1]) ],
          } },
        ] } },
        { popeq: { cached: false, result: {
          alignment: [ { tag: 'atom', value: { tag: 'field' } } ],
          value: [new Uint8Array([64])],
        } } }
      ]
    }
  )
});

test('Check ledger inspection', () => {
  var [c, Ctxt] = startContract(contract, 0, 64n);
  const L = contractCode.ledger(Ctxt.transactionContext.state);
  expect(L.value).toEqual(64n);
});
