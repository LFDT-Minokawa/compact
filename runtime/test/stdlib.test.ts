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

import { describe, expect, test } from 'vitest';
import * as compactRuntime from '../src/index.js';
import * as ocrt from '@midnight-ntwrk/onchain-runtime-v1';

describe('createCoinCommitment', () => {
  test('Check for success', () => {
    const context = compactRuntime.createCircuitContext(
      ocrt.sampleContractAddress(),
      '0'.repeat(64),
      new ocrt.ContractState(),
      undefined,
    );
    const coinInfo = {
      tag: 'shielded',
      type: ocrt.sampleRawTokenType(),
      nonce: '2ab78b2272ec3489da60e6af54a87bfa53a7fa727602a040df782ebae7f5ab59',
      value: 572290297060094569n,
    };
    const recipient = {
      is_left: false,
      left: { bytes: new Uint8Array(32) },
      right: { bytes: ocrt.encodeContractAddress(ocrt.sampleContractAddress()) },
    };
    compactRuntime.createZswapOutput(context, ocrt.encodeShieldedCoinInfo(coinInfo), recipient);
    expect(context.currentZswapLocalState.outputs.length).toBe(1);
  });
});

describe('CompactError', () => {
  const msg = 'my message';

  const f = () => {
    throw new compactRuntime.CompactError(msg);
  };

  test('Check for error type resolution', () => {
    expect(f).toThrow(compactRuntime.CompactError);
  });

  test('Check for error message', () => {
    expect(f).toThrow(msg);
  });
});

describe('__compact.assert', () => {
  const msg = 'my message';

  const f = () => {
    compactRuntime.assert(false, msg);
  };

  test('Check for success', () => {
    compactRuntime.assert(true, msg);
  });

  test('Check for error type', () => {
    expect(f).toThrow(compactRuntime.CompactError);
  });

  test('Check for error message', () => {
    expect(f).toThrow(msg);
  });
});

describe('__compact.typeError', () => {
  const f = () => {
    compactRuntime.typeError('who', 'what', 'where', 'type', 'x');
  };

  test('Check for error type', () => {
    expect(f).toThrow(compactRuntime.CompactError);
  });

  test('Check for error message', () => {
    expect(f).toThrow(/type error/);
  });
});

describe('__compact.convertFieldToBytes', () => {
  const x = 256n;

  test('Check for success', () => {
    const a = compactRuntime.convertFieldToBytes(2, x, 'source');
    expect(a).toEqual(new Uint8Array([0, 1]));
  });

  const f = () => {
    compactRuntime.convertFieldToBytes(1, x, 'source');
  };

  test('Check for error type', () => {
    expect(f).toThrow(compactRuntime.CompactError);
  });

  test('Check for error message', () => {
    expect(f).toThrow(/range error/);
  });
});

describe('__compact.convertBytesToField', () => {
  test('Check for success', () => {
    const a = new Uint8Array([0, 1]);
    const x = compactRuntime.convertBytesToField(a.length, a, 'source');
    expect(x).toBe(256n);
  });

  const f = () => {
    const a = new Uint8Array(57);
    a[56] = 1;
    compactRuntime.convertBytesToField(57, a, 'source');
  };

  test('check for error type', () => {
    expect(f).toThrow(compactRuntime.CompactError);
  });

  test('check for error message', () => {
    expect(f).toThrow(/range error/);
  });
});

describe('__compact.convertBytesToUint', () => {
  test('Check for success', () => {
    const a = new Uint8Array([0xff, 0]);
    const x = compactRuntime.convertBytesToUint(255, a.length, a, 'source');
    expect(x).toBe(255n);
  });

  const f = () => {
    const a = new Uint8Array([0, 1]);
    compactRuntime.convertBytesToUint(255, a.length, a, 'source');
  };

  test('check for error type', () => {
    expect(f).toThrow(compactRuntime.CompactError);
  });

  test('check for error message', () => {
    expect(f).toThrow(/range error/);
  });
});

describe('builtin hash functions', () => {
  test('transientHash', () => {
    expect(typeof compactRuntime.transientHash(compactRuntime.CompactTypeField, 5n)).toEqual('bigint');
  });

  test('persistentHash', () => {
    const res = compactRuntime.persistentHash(compactRuntime.CompactTypeField, 5n);
    expect(res).toBeInstanceOf(Uint8Array);
    expect(res.length).toBe(32);
  });

  test('transientCommit', () => {
    expect(
      typeof compactRuntime.transientCommit(
        new compactRuntime.CompactTypeVector(5, compactRuntime.CompactTypeField),
        [1n, 2n, 3n, 4n, 5n],
        42n,
      ),
    ).toEqual('bigint');
  });

  test('persistentCommit', () => {
    const res = compactRuntime.persistentCommit(
      new compactRuntime.CompactTypeVector(5, compactRuntime.CompactTypeField),
      [1n, 2n, 3n, 4n, 5n],
      new Uint8Array(32),
    );
    expect(res).toBeInstanceOf(Uint8Array);
    expect(res.length).toBe(32);
  });

  test('hashToCurve', () => {
    const res = compactRuntime.hashToCurve(new compactRuntime.CompactTypeVector(5, compactRuntime.CompactTypeField), [
      1n,
      2n,
      3n,
      4n,
      5n,
    ]);
    expect(typeof res.x).toEqual('bigint');
    expect(typeof res.y).toEqual('bigint');
  });

  test('elliptic curve arithmetic', () => {
    // testing that x * g + y * (g + g) == (x + 2y) * g
    // for x = 42, y = 12
    const g = compactRuntime.ecMulGenerator(1n);
    const lhs = compactRuntime.ecAdd(compactRuntime.ecMulGenerator(42n), compactRuntime.ecMul(compactRuntime.ecAdd(g, g), 12n));
    const rhs = compactRuntime.ecMulGenerator(42n + 2n * 12n);
    expect(lhs).toEqual(rhs);
    expect(typeof lhs.x).toEqual('bigint');
    expect(typeof lhs.y).toEqual('bigint');
  });
});

test('sanity check for contract address utilities', () => {
  const address = ocrt.sampleContractAddress();
  expect(compactRuntime.fromHex(address).length).toEqual(compactRuntime.CONTRACT_ADDRESS_BYTE_LENGTH);
  expect(compactRuntime.isContractAddress(address)).toBe(true);
  const encodedAddress = { bytes: compactRuntime.fromHex(address) };
  expect(compactRuntime.isEncodedContractAddress(encodedAddress)).toBe(true);

  const bogusAddress = '098230498';
  expect(compactRuntime.isContractAddress(bogusAddress)).toBe(false);
  const encodedBogusAddress = { bytes: compactRuntime.fromHex(bogusAddress) };
  expect(compactRuntime.isEncodedContractAddress(encodedBogusAddress)).toBe(false);
});
