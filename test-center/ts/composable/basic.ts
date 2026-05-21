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

/** Read the `v` field of the Inner ledger from a cached QueryContext. */
const innerV = (ctxt: any, address: any): bigint => {
  const qc = ctxt.queryContexts[address];
  if (qc === undefined) {
    throw new Error(`no QueryContext cached for inner at address ${address}`);
  }
  return innerCode.ledger(qc.state).v;
};

const bytesEqual = (a: Uint8Array, b: Uint8Array): boolean => {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
};

describe('Outer.add forwards to Inner.add', () => {
  test('single call: result equals Inner.v after the call', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [inner.encodedAddress],
      },
      [inner],
    );

    const { result, context: ctxt1 } = await outer.circuits.add(ctxt0, 7n);
    expect(result).toEqual(7n);
    expect(innerV(ctxt1, inner.address)).toEqual(7n);
  });

  test('chain of five Outer.add calls returns running totals', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [inner.encodedAddress],
      },
      [inner],
    );

    const adds = [3n, 5n, 7n, 11n, 13n];
    let ctxt = ctxt0;
    let running = 0n;
    for (const v of adds) {
      const r = await outer.circuits.add(ctxt, v);
      running += v;
      expect(r.result).toEqual(running);
      ctxt = r.context;
    }
    expect(innerV(ctxt, inner.address)).toEqual(
      adds.reduce((a, b) => a + b, 0n),
    );
  });
});

describe('setInner swaps which Inner is current', () => {
  test('setInner returns the previously-stored inner address', async () => {
    const innerA = await deployDependency({ module: innerCode, args: [] });
    const innerB = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [innerA.encodedAddress],
      },
      [innerA, innerB],
    );

    const { result } = await outer.circuits.setInner(
      ctxt0,
      innerB.encodedAddress,
    );
    expect(bytesEqual(result.bytes, innerA.encodedAddress.bytes)).toEqual(true);
  });

  test('setInner directs subsequent Outer.add to the new inner', async () => {
    const innerA = await deployDependency({ module: innerCode, args: [] });
    const innerB = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [innerA.encodedAddress],
      },
      [innerA, innerB],
    );

    // 1. add against A
    const { context: ctxtAfterA } = await outer.circuits.add(ctxt0, 3n);
    expect(innerV(ctxtAfterA, innerA.address)).toEqual(3n);
    // B has not been touched yet — no cache entry should exist for it.
    expect(ctxtAfterA.queryContexts[innerB.address]).toBeUndefined();

    // 2. swap to B
    const { context: ctxtAfterSwap } = await outer.circuits.setInner(
      ctxtAfterA,
      innerB.encodedAddress,
    );
    // A's cached state survives the swap.
    expect(innerV(ctxtAfterSwap, innerA.address)).toEqual(3n);

    // 3. add against B
    const { result, context: ctxtAfterB } = await outer.circuits.add(
      ctxtAfterSwap,
      5n,
    );
    expect(result).toEqual(5n);
    expect(innerV(ctxtAfterB, innerA.address)).toEqual(3n); // A unchanged
    expect(innerV(ctxtAfterB, innerB.address)).toEqual(5n);
  });

  test('setInner to the same inner is functionally a no-op', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [inner.encodedAddress],
      },
      [inner],
    );

    const ctxt1 = (await outer.circuits.add(ctxt0, 3n)).context;
    const ctxt2 = (await outer.circuits.setInner(ctxt1, inner.encodedAddress))
      .context;
    const r = await outer.circuits.add(ctxt2, 5n);
    expect(r.result).toEqual(8n);
    expect(innerV(r.context, inner.address)).toEqual(8n);
  });

  test('rotating through three inners keeps each independent', async () => {
    const innerA = await deployDependency({ module: innerCode, args: [] });
    const innerB = await deployDependency({ module: innerCode, args: [] });
    const innerC = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [innerA.encodedAddress],
      },
      [innerA, innerB, innerC],
    );

    let ctxt = ctxt0;
    ctxt = (await outer.circuits.add(ctxt, 1n)).context; // A.v = 1
    ctxt = (await outer.circuits.setInner(ctxt, innerB.encodedAddress)).context;
    ctxt = (await outer.circuits.add(ctxt, 2n)).context; // B.v = 2
    ctxt = (await outer.circuits.setInner(ctxt, innerC.encodedAddress)).context;
    ctxt = (await outer.circuits.add(ctxt, 3n)).context; // C.v = 3
    ctxt = (await outer.circuits.setInner(ctxt, innerA.encodedAddress)).context;
    ctxt = (await outer.circuits.add(ctxt, 10n)).context; // A.v = 11

    expect(innerV(ctxt, innerA.address)).toEqual(11n);
    expect(innerV(ctxt, innerB.address)).toEqual(2n);
    expect(innerV(ctxt, innerC.address)).toEqual(3n);
  });

  test('outer.inner ledger field reflects the most recent setInner', async () => {
    const innerA = await deployDependency({ module: innerCode, args: [] });
    const innerB = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [innerA.encodedAddress],
      },
      [innerA, innerB],
    );

    // Before the swap, Outer.inner = innerA.
    const outerLedger0 = outerCode.ledger(
      ctxt0.callContext.currentQueryContext.state,
    );
    expect(
      bytesEqual(outerLedger0.inner.bytes, innerA.encodedAddress.bytes),
    ).toEqual(true);

    const { context: ctxt1 } = await outer.circuits.setInner(
      ctxt0,
      innerB.encodedAddress,
    );
    const outerLedger1 = outerCode.ledger(
      ctxt1.callContext.currentQueryContext.state,
    );
    expect(
      bytesEqual(outerLedger1.inner.bytes, innerB.encodedAddress.bytes),
    ).toEqual(true);
  });
});

describe('Multiple Outer instances stay isolated', () => {
  test('two Outers each wrapping their own Inner do not interfere', async () => {
    const inner1 = await deployDependency({ module: innerCode, args: [] });
    const inner2 = await deployDependency({ module: innerCode, args: [] });

    const [outer1, ctxt0_1] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [inner1.encodedAddress],
      },
      [inner1],
    );
    const [outer2, ctxt0_2] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [inner2.encodedAddress],
      },
      [inner2],
    );

    const { context: c1 } = await outer1.circuits.add(ctxt0_1, 4n);
    const { context: c2 } = await outer2.circuits.add(ctxt0_2, 9n);

    expect(innerV(c1, inner1.address)).toEqual(4n);
    expect(innerV(c2, inner2.address)).toEqual(9n);

    // Each context only knows about its own inner.
    expect(c1.queryContexts[inner2.address]).toBeUndefined();
    expect(c2.queryContexts[inner1.address]).toBeUndefined();
  });
});

describe('Contract values are first-class: const assignment', () => {
  test('echoStored threads the stored contract value through const bindings', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [inner.encodedAddress],
      },
      [inner],
    );

    const { result } = await outer.circuits.echoStored(ctxt0);
    expect(bytesEqual(result.bytes, inner.encodedAddress.bytes)).toEqual(true);
  });

  test('echoInner round-trips a contract value passed as a parameter', async () => {
    const stored = await deployDependency({ module: innerCode, args: [] });
    const other = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [stored.encodedAddress],
      },
      [stored, other],
    );

    // The value returned is the argument, independent of the stored ledger field.
    const { result } = await outer.circuits.echoInner(
      ctxt0,
      other.encodedAddress,
    );
    expect(bytesEqual(result.bytes, other.encodedAddress.bytes)).toEqual(true);
    expect(bytesEqual(result.bytes, stored.encodedAddress.bytes)).toEqual(
      false,
    );
  });

  test('a const-bound contract value can be the receiver of a call', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {},
        initialPrivateState: 0,
        args: [inner.encodedAddress],
      },
      [inner],
    );

    const { result, context } = await outer.circuits.addViaConst(ctxt0, 6n);
    expect(result).toEqual(6n);
    expect(innerV(context, inner.address)).toEqual(6n);
  });
});
