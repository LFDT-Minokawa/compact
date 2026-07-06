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

test('Check fib 0', async () => {
  const [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    expect((await c.circuits.fib(Ctxt, 1n)).result).toEqual(0n)
});

test('Check fib 1', async () => {
    var [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    expect((await c.circuits.fib(Ctxt, 2n)).result).toEqual(1n)
});

test('Check fib 3', async () => {
    var [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 2n)).context;
    expect((await c.circuits.fib(Ctxt, 3n)).result).toEqual(2n)
});

test('Check fib 4', async () => {
    var [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 2n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 3n)).context;
    expect((await c.circuits.fib(Ctxt, 4n)).result).toEqual(3n)
});

test('Check fib 5', async () => {
    var [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 2n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 3n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 4n)).context;
    expect((await c.circuits.fib(Ctxt, 5n)).result).toEqual(5n)
});

test('Check fib 0', async () => {
    const [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    expect((await c.circuits.fib(Ctxt, 1n)).result).toEqual(0n)
});

test('Check fib 6', async () => {
    var [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 2n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 3n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 4n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 5n)).context;
    expect((await c.circuits.fib(Ctxt, 6n)).result).toEqual(8n)
});

test('Check fib reset to 1', async () => {
    var [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 2n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 3n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 4n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 5n)).context;
    expect((await c.circuits.fib(Ctxt, 1n)).result).toEqual(0n)
});

test('Check fib reset to 1', async () => {
    var [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 2n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 3n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 4n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 5n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    expect((await c.circuits.fib(Ctxt, 2n)).result).toEqual(1n)
});

test('Check c > counter + 1', async () => {
    var [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 2n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 3n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 4n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 5n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    await expect(c.circuits.fib(Ctxt, 3n)).rejects.toThrow(runtime.CompactError)
});

test('Check c > counter + 1', async () => {
    var [c, Ctxt] = await startContract(contractCode, witnesses, 0);
    Ctxt = (await c.circuits.fib(Ctxt, 1n)).context;
    Ctxt = (await c.circuits.fib(Ctxt, 2n)).context;
    await expect(c.circuits.fib(Ctxt, 4n)).rejects.toThrow('invalid fib num requested')
});
