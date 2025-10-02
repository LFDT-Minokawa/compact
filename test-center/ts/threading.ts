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

const witnesses = {
    num({ privateState }: any, n: bigint): [any, bigint] {
        let a = 0, b = 1, c, i;
        if (n == 0n)
            return [privateState, BigInt(a)];
        for (i = 2; i <= n; i++) {
            c = a + b;
            a = b;
            b = c;
        }
        return [privateState, BigInt(b)]
    }
};

test('Check fib 0', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    expect(c.circuits.fib2(Ctxt, false).result).toEqual(1n)
});

test('Check fib 1', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(c.circuits.fib2(Ctxt, false).result).toEqual(1n)
});

test('Check fib 2', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(c.circuits.fib2(Ctxt, false).result).toEqual(2n)
});

test('Check fib 3', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(c.circuits.fib2(Ctxt, false).result).toEqual(3n)
});

test('Check fib 4', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(c.circuits.fib2(Ctxt, false).result).toEqual(5n)
});

test('Check fib 1', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(c.circuits.fib2(Ctxt, false).result).toEqual(1n)
});

test('Check reset', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, true).context;
    expect(c.circuits.fib2(Ctxt, false).result).toEqual(1n)
});

test('Check reset + fib 0', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(c.circuits.fib2(Ctxt, true).result).toEqual(0n)
});

test('Check reset + fib 1', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, true).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(c.circuits.fib2(Ctxt, false).result).toEqual(1n)
});

test('Check reset + fib 2', () => {
    var [c, Ctxt] =  startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, true).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(c.circuits.fib2(Ctxt, false).result).toEqual(2n)
});

test('check access counter differently', () => {
    var  [c, Ctxt] = startContract(contractCode, witnesses, 0);
    const ps = contractCode.ledger(Ctxt.currentQueryContext.state);
    expect(ps.counter).toEqual(0n)
});

test('check fib2 again', () => {
    var  [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    const ps = contractCode.ledger(Ctxt.currentQueryContext.state);
    expect(ps.counter).toEqual(1n)
});

test('check entire current private state', () => {
    var  [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(contractCode.ledger(Ctxt.currentQueryContext.state).counter).toEqual(1n)
});

test('check private state', () => {
    var  [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(Ctxt.currentPrivateState).toEqual(0)
});

test('check private state', () => {
    var  [c, Ctxt] = startContract(contractCode, witnesses, 1);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(Ctxt.currentPrivateState).toEqual(1)
});

test('check contract address', () => {
    var  [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib2(Ctxt, false).context;
    expect(Ctxt.currentQueryContext.address).toEqual("0000000000000000000000000000000000000000000000000000000000000000")
});


