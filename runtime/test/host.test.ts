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
import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import {
  callHostFunction,
  createCircuitContext,
  hostFunction,
  PartialProofData,
  recordHostOutput,
  registerHostInterface,
} from '../src/index.js';

const COIN_PUBLIC_KEY = '0'.repeat(64);

const context = () =>
  createCircuitContext({
    circuitId: 'test',
    contractAddress: ocrt.dummyContractAddress(),
    coinPublicKeyOrZswapState: COIN_PUBLIC_KEY,
    contractState: new ocrt.ContractState(),
    privateState: undefined,
  });

const emptyProofData = (): PartialProofData => ({
  input: { value: [], alignment: [] },
  publicTranscript: [],
  privateTranscriptOutputs: [],
});

describe('host interfaces', () => {
  test('the zswap interface is built in and served from the context', () => {
    const ctx = context();
    expect(callHostFunction(ctx, 'midnight:capsule/zswap@1.0.0', 'ownPublicKey', [])).toEqual({
      bytes: new Uint8Array(32),
    });
  });

  test('the keys interface is declared but not implemented until something registers it', () => {
    expect(() => hostFunction('midnight:capsule/keys@1.0.0', 'secretKey')).toThrow(
      /no implementation of host interface midnight:capsule\/keys@1.0.0 is registered/,
    );
    const key = new Uint8Array(32).fill(3);
    registerHostInterface('midnight:capsule/keys@1.0.0', { secretKey: () => key });
    expect(callHostFunction(context(), 'midnight:capsule/keys@1.0.0', 'secretKey', [])).toBe(key);
    expect(() => hostFunction('midnight:capsule/keys@1.0.0', 'publicKey')).toThrow(
      /implementation of host interface midnight:capsule\/keys@1.0.0 has no function publicKey/,
    );
  });

  test('an unknown interface names the seam', () => {
    expect(() => hostFunction('vendor:thing/api@2.0.0', 'f')).toThrow(/registerHostInterface supplies one/);
  });

  test('host outputs are recorded in call order, created on the first', () => {
    const pd = emptyProofData();
    expect(pd.hostOutputs).toBeUndefined();
    const a: ocrt.AlignedValue = {
      value: [new Uint8Array([1])],
      alignment: [{ tag: 'atom', value: { tag: 'bytes', length: 1 } }],
    };
    const b: ocrt.AlignedValue = { value: [], alignment: [] };
    recordHostOutput(pd, a);
    recordHostOutput(pd, b);
    expect(pd.hostOutputs).toEqual([a, b]);
    expect(pd.privateTranscriptOutputs).toHaveLength(0);
  });
});
