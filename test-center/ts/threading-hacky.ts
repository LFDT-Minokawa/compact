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
        const fibs = [0, 0, 1, 1, 2, 3, 5, 8, 13];
        return [privateState, BigInt(fibs[Number(n)])]
    }
};

test('Check fib 0', () => {
  const [c, Ctxt] = startContract(contractCode, witnesses, 0);
    expect(c.circuits.fib(Ctxt, 1n).result).toEqual(0n)
});

test('Check fib 1', () => {
    var [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    expect(c.circuits.fib(Ctxt, 2n).result).toEqual(1n)
});

test('Check fib 3', () => {
    var [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    Ctxt = c.circuits.fib(Ctxt, 2n).context;
    expect(c.circuits.fib(Ctxt, 3n).result).toEqual(2n)
});

test('Check fib 4', () => {
    var [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    Ctxt = c.circuits.fib(Ctxt, 2n).context;
    Ctxt = c.circuits.fib(Ctxt, 3n).context;
    expect(c.circuits.fib(Ctxt, 4n).result).toEqual(3n)
});

test('Check fib 5', () => {
    var [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    Ctxt = c.circuits.fib(Ctxt, 2n).context;
    Ctxt = c.circuits.fib(Ctxt, 3n).context;
    Ctxt = c.circuits.fib(Ctxt, 4n).context;
    expect(c.circuits.fib(Ctxt, 5n).result).toEqual(5n)
});

test('Check fib 0', () => {
    const [c, Ctxt] = startContract(contractCode, witnesses, 0);
    expect(c.circuits.fib(Ctxt, 1n).result).toEqual(0n)
});

test('Check fib 6', () => {
    var [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    Ctxt = c.circuits.fib(Ctxt, 2n).context;
    Ctxt = c.circuits.fib(Ctxt, 3n).context;
    Ctxt = c.circuits.fib(Ctxt, 4n).context;
    Ctxt = c.circuits.fib(Ctxt, 5n).context;
    expect(c.circuits.fib(Ctxt, 6n).result).toEqual(8n)
});

test('Check fib reset to 1', () => {
    var [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    Ctxt = c.circuits.fib(Ctxt, 2n).context;
    Ctxt = c.circuits.fib(Ctxt, 3n).context;
    Ctxt = c.circuits.fib(Ctxt, 4n).context;
    Ctxt = c.circuits.fib(Ctxt, 5n).context;
    expect(c.circuits.fib(Ctxt, 1n).result).toEqual(0n)
});

test('Check fib reset to 1', () => {
    var [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    Ctxt = c.circuits.fib(Ctxt, 2n).context;
    Ctxt = c.circuits.fib(Ctxt, 3n).context;
    Ctxt = c.circuits.fib(Ctxt, 4n).context;
    Ctxt = c.circuits.fib(Ctxt, 5n).context;
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    expect(c.circuits.fib(Ctxt, 2n).result).toEqual(1n)
});

test('Check c > counter + 1', () => {
    var [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    Ctxt = c.circuits.fib(Ctxt, 2n).context;
    Ctxt = c.circuits.fib(Ctxt, 3n).context;
    Ctxt = c.circuits.fib(Ctxt, 4n).context;
    Ctxt = c.circuits.fib(Ctxt, 5n).context;
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    expect(() => c.circuits.fib(Ctxt, 3n).result).toThrow(runtime.CompactError)
});

test('Check c > counter + 1', () => {
    var [c, Ctxt] = startContract(contractCode, witnesses, 0);
    Ctxt = c.circuits.fib(Ctxt, 1n).context;
    Ctxt = c.circuits.fib(Ctxt, 2n).context;
    expect(() => c.circuits.fib(Ctxt, 4n).result).toThrow('invalid fib num requested')
});


