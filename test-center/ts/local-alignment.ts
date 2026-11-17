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

// Private-input alignment, path by path. The proof check after each call reads the private inputs
// the JavaScript pushed as one flat run of field elements, a guarded `private_input` consuming its
// width only when its guard holds, and fails on any element left over or missing; therefore each
// construct runs on each of its branches, and a misaligned path fails its call's check.

const ECHO = { 'test:oracle/echo@1.0.0': { echo: (_: unknown, x: bigint) => (x * 3n) % 256n } };

test('every way a local or host result reaches a circuit pushes exactly what the circuit consumes', async () => {
  const [contract, deployed] = await startContract(contractCode);
  let context = withHostInterfaces(deployed, ECHO);
  const call = async (name: string, ...args: unknown[]): Promise<unknown> => {
    const r = await contract.circuits[name](context, ...args);
    context = r.context;
    return r.result;
  };
  // n = 0: the right operands of `&&` and `||`, and the counter's reads, see an empty counter
  expect(await call('shortCircuit', false)).toEqual([false, false]);
  expect(await call('shortCircuit', true)).toEqual([false, true]);
  expect(await call('branch', false, false)).toEqual(0n);
  expect(await call('branch', true, false)).toEqual(1n);
  expect(await call('branch', true, true)).toEqual(2n);
  // two bumps from the range loop and two from the guarded one: n = 6
  expect(await call('loops')).toEqual([12n, [8n, 10n, 12n]]);
  expect(await call('shortCircuit', true)).toEqual([true, true]);
  expect(await call('choose', true)).toEqual(6n);
  expect(await call('choose', false)).toEqual(7n);
  expect(await call('viaInner')).toEqual(12n);
  expect(await call('nest', 2n)).toEqual([12n, 18n]);
  expect(await call('direct', false, 3n)).toEqual(false);
  expect(await call('direct', true, 3n)).toEqual(true);
  expect(await call('hosts', false, 5n)).toEqual([0n, 15n]);
  expect(await call('hosts', true, 5n)).toEqual([15n, 15n]);
  expect(await call('maybe', 4n, false)).toEqual({ is_some: false, value: 0n });
  expect(await call('maybe', 4n, true)).toEqual({ is_some: true, value: 9n });
  await call('check');
  const leaf = new Uint8Array([7, 0, 0, 1]);
  expect(await call('member', leaf, false)).toEqual(false);
  expect(await call('member', leaf, true)).toEqual(true);
  expect(await call('shapes', leaf)).toEqual([{ kind: 1, tag: leaf, amount: 6n }, [2n, 4n]]);
});
