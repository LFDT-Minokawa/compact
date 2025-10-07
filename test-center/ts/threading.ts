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

const contract = () => contractCode.executables<any>(
  {
    [contractCode.contractId]: {
      num({ privateState }: any, n: bigint): [any, bigint] {
        let a = 0, b = 1, c, i;
        if (n == 0n)
          return [privateState, BigInt(a)];
        for (i = 2; i <= n; i++) {
          c = a + b;
          a = b;
          b = c;
        }
        return [privateState, BigInt(b)];
      },
    },
  });

test('Check fib 0', () => {
  const [c, Ctxt] = startContract(contract, 0)();
  expect(c.impureCircuits.fib2(Ctxt, false).result).toEqual(1n);
});

test('Check fib 1', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(c.impureCircuits.fib2(Ctxt, false).result).toEqual(1n);
});

test('Check fib 2', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(c.impureCircuits.fib2(Ctxt, false).result).toEqual(2n);
});

test('Check fib 3', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(c.impureCircuits.fib2(Ctxt, false).result).toEqual(3n);
});

test('Check fib 4', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(c.impureCircuits.fib2(Ctxt, false).result).toEqual(5n);
});

test('Check fib 1', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(c.impureCircuits.fib2(Ctxt, false).result).toEqual(1n);
});

test('Check reset', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, true).context;
  expect(c.impureCircuits.fib2(Ctxt, false).result).toEqual(1n);
});

test('Check reset + fib 0', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(c.impureCircuits.fib2(Ctxt, true).result).toEqual(0n);
});

test('Check reset + fib 1', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, true).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(c.impureCircuits.fib2(Ctxt, false).result).toEqual(1n);
});

test('Check reset + fib 2', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, true).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(c.impureCircuits.fib2(Ctxt, false).result).toEqual(2n);
});

test('check access counter differently', () => {
  const [c, Ctxt] = startContract(contract, 0)();
  const ps = contractCode.ledgerStateDecoder(Ctxt.currentQueryContext.state);
  expect(ps.counter).toEqual(0n);
});

test('check fib2 again', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  const ps = contractCode.ledgerStateDecoder(Ctxt.currentQueryContext.state);
  expect(ps.counter).toEqual(1n);
});

test('check entire current private state', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(contractCode.ledgerStateDecoder(Ctxt.currentQueryContext.state).counter).toEqual(1n);
});

test('check private state', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(Ctxt.currentPrivateState).toEqual(0);
});

test('check private state', () => {
  let [c, Ctxt] = startContract(contract, 1)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(Ctxt.currentPrivateState).toEqual(1);
});

test('check contract address', () => {
  let [c, Ctxt] = startContract(contract, 0)();
  Ctxt = c.impureCircuits.fib2(Ctxt, false).context;
  expect(Ctxt.currentQueryContext.address).toEqual('02000000000000000000000000000000000000000000000000000000000000000000');
});
