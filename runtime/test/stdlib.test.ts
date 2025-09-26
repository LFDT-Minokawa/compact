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
import * as runtime from '@midnight-ntwrk/compact-runtime';

describe('createCoinCommitment', () => {
  test('Check for success', () => {
    const contractAddress = runtime.sampleContractAddress();
    const contractStates = {
      [contractAddress]: runtime.StateValue.newNull(),
    };
    const privateStates = {
      [contractAddress]: 0n,
    };
    const context = runtime.createCircuitContext('', '', contractAddress, '0'.repeat(64), contractStates, privateStates);
    const coinInfo = {
      type: runtime.rawTokenType(new Uint8Array(32), contractAddress),
      nonce: '2ab78b2272ec3489da60e6af54a87bfa53a7fa727602a040df782ebae7f5ab59',
      value: 572290297060094569n,
    };
    const recipient = {
      is_left: false,
      left: { bytes: new Uint8Array(32) },
      right: { bytes: runtime.encodeContractAddress(contractAddress) },
    };
    runtime.createZswapOutput(context, runtime.encodeShieldedCoinInfo(coinInfo), recipient);
    expect(context.currentZswapLocalState!.outputs.length).toBe(1);
  });
});
describe('CompactError', () => {
  const msg = 'my message';

  const f = () => {
    throw new runtime.CompactError(msg);
  };

  test('Check for error type resolution', () => {
    expect(f).toThrow(runtime.CompactError);
  });

  test('Check for error message', () => {
    expect(f).toThrow(msg);
  });

});

describe('__compact.assert', () => {

  const msg = 'my message';

  const f = () => {
    runtime.assert(false, msg);
  };

  test('Check for success', () => {
    runtime.assert(true, msg);
  });

  test('Check for error type', () => {
    expect(f).toThrow(runtime.CompactError);
  });

  test('Check for error message', () => {
    expect(f).toThrow(msg);
  });

});

describe('__compact.type_error', () => {
  const f = () => {
    runtime.typeError('who', 'what', 'where', 'type', 'x');
  };

  test('Check for error type', () => {
    expect(f).toThrow(runtime.CompactError);
  });

  test('Check for error message', () => {
    expect(f).toThrow(/type error/);
  });
});

describe('__compact.convert_bigint_to_Uint8Array', () => {
  const x = 256n;

  test('Check for success', () => {
    const a = runtime.convert_bigint_to_Uint8Array(2, x);
    expect(a).toEqual(new Uint8Array([0, 1]));
  });

  const f = () => {
    runtime.convert_bigint_to_Uint8Array(1, x);
  };

  test('Check for error type', () => {
    expect(f).toThrow(runtime.CompactError);
  });

  test('Check for error message', () => {
    expect(f).toThrow(/range error/);
  });
});

describe('__compact.convert_Uint8Array_to_bigint', () => {

  test('Check for success', () => {
    const a = new Uint8Array([0, 1]);
    const x = runtime.convert_Uint8Array_to_bigint(a.length, a);
    expect(x).toBe(256n);
  });

  const f = () => {
    const a = new Uint8Array(57);
    a[56] = 1;
    runtime.convert_Uint8Array_to_bigint(57, a);
  };

  test('check for error type', () => {
    expect(f).toThrow(runtime.CompactError);
  });

  test('check for error message', () => {
    expect(f).toThrow(/range error/);
  });
});

describe('builtin hash functions', () => {
  test('transientHash', () => {
    expect(typeof runtime.transientHash(runtime.CompactTypeField, 5n)).toEqual('bigint');
  });

  test('persistentHash', () => {
    const res = runtime.persistentHash(runtime.CompactTypeField, 5n);
    expect(res).toBeInstanceOf(Uint8Array);
    expect(res.length).toBe(32);
  });

  test('transientCommit', () => {
    expect(typeof runtime.transientCommit(
      new runtime.CompactTypeVector(5, runtime.CompactTypeField),
      [1n, 2n, 3n, 4n, 5n],
      42n,
    )).toEqual('bigint');
  });

  test('persistentCommit', () => {
    const res = runtime.persistentCommit(
      new runtime.CompactTypeVector(5, runtime.CompactTypeField),
      [1n, 2n, 3n, 4n, 5n],
      new Uint8Array(32),
    );
    expect(res).toBeInstanceOf(Uint8Array);
    expect(res.length).toBe(32);
  });

  test('hashToCurve', () => {
    const res = runtime.hashToCurve(
      new runtime.CompactTypeVector(5, runtime.CompactTypeField),
      [1n, 2n, 3n, 4n, 5n],
    );
    expect(typeof res.x).toEqual('bigint');
    expect(typeof res.y).toEqual('bigint');
  });

  test('elliptic curve arithmetic', () => {
    // testing that x * g + y * (g + g) == (x + 2y) * g
    // for x = 42, y = 12
    const g = runtime.ecMulGenerator(1n);
    const lhs = runtime.ecAdd(
      runtime.ecMulGenerator(42n),
      runtime.ecMul(runtime.ecAdd(g, g), 12n));
    const rhs = runtime.ecMulGenerator(42n + 2n * 12n);
    expect(lhs).toEqual(rhs);
    expect(typeof lhs.x).toEqual('bigint');
    expect(typeof lhs.y).toEqual('bigint');
  });
});