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

import { describe, expect, test } from 'vitest';
import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import {
  HostInterface,
  HostInterfaceProvider,
  PartialProofData,
  ZSWAP_HOST_INTERFACE_ID,
  assertHostInterfaces,
  callHostFunction,
  createCircuitContext,
  missingHostFunctions,
  recordHostOutput,
  zswapHostInterface,
} from '../src/index.js';

const COIN_PUBLIC_KEY = '0'.repeat(64);

/** A provider serving exactly the given interfaces. */
const providerOf = (interfaces: Record<string, HostInterface>): HostInterfaceProvider => ({
  resolve: (id) => interfaces[id],
});

const context = (provider?: HostInterfaceProvider) =>
  createCircuitContext({
    circuitId: 'test',
    contractAddress: ocrt.dummyContractAddress(),
    coinPublicKeyOrZswapState: COIN_PUBLIC_KEY,
    contractState: new ocrt.ContractState(),
    privateState: undefined,
    hostInterfaceProvider: provider,
  });

const emptyProofData = (): PartialProofData => ({
  input: { value: [], alignment: [] },
  publicTranscript: [],
  privateTranscriptOutputs: [],
});

describe('host interfaces', () => {
  test("a call resolves through the context's provider", () => {
    const key = new Uint8Array(32).fill(3);
    const ctx = context(providerOf({ 'midnight:capsule/keys@1.0.0': { secretKey: () => key } }));
    expect(callHostFunction(ctx, 'midnight:capsule/keys@1.0.0', 'secretKey', [])).toBe(key);
  });

  test('the zswap implementation is served like any other interface, and not without a provider', () => {
    const served = context(providerOf({ [ZSWAP_HOST_INTERFACE_ID]: zswapHostInterface }));
    expect(callHostFunction(served, ZSWAP_HOST_INTERFACE_ID, 'ownPublicKey', [])).toEqual({ bytes: new Uint8Array(32) });
    expect(() => callHostFunction(context(), ZSWAP_HOST_INTERFACE_ID, 'ownPublicKey', [])).toThrow(
      /carries no host interface provider/,
    );
    expect(() => callHostFunction(context(providerOf({})), ZSWAP_HOST_INTERFACE_ID, 'ownPublicKey', [])).toThrow(
      /resolves no 'midnight:capsule\/zswap@1.0.0'/,
    );
  });

  test('a missing function of a resolved interface is named', () => {
    const ctx = context(providerOf({ 'midnight:capsule/keys@1.0.0': { secretKey: () => new Uint8Array(32) } }));
    expect(() => callHostFunction(ctx, 'midnight:capsule/keys@1.0.0', 'publicKey', [])).toThrow(
      /resolves for 'midnight:capsule\/keys@1.0.0' has no function publicKey/,
    );
  });

  test('a requirement is checked against a provider before anything runs', () => {
    const provider = providerOf({
      [ZSWAP_HOST_INTERFACE_ID]: zswapHostInterface,
      'vendor:thing/partial@1.0.0': { f: () => 1n, h: 'not a function' as never },
    });
    // Satisfied: any subset of a served interface's functions.
    expect(missingHostFunctions({ [ZSWAP_HOST_INTERFACE_ID]: ['ownPublicKey', 'createZswapOutput'] }, provider)).toEqual([]);
    expect(missingHostFunctions({}, provider)).toEqual([]);
    expect(missingHostFunctions({}, undefined)).toEqual([]);
    // Unresolved: every declared function is missing, and the gap says nothing was resolved.
    expect(missingHostFunctions({ 'vendor:thing/api@2.0.0': ['f', 'g'] }, provider)).toEqual([
      { interfaceId: 'vendor:thing/api@2.0.0', resolved: false, missing: ['f', 'g'] },
    ]);
    // Resolved but incomplete: only the functions the implementation lacks, in declaration order.
    expect(
      missingHostFunctions(
        { 'vendor:thing/partial@1.0.0': ['f', 'g', 'h'], [ZSWAP_HOST_INTERFACE_ID]: ['ownPublicKey'] },
        provider,
      ),
    ).toEqual([{ interfaceId: 'vendor:thing/partial@1.0.0', resolved: true, missing: ['g', 'h'] }]);
    // No provider: everything is missing.
    expect(missingHostFunctions({ [ZSWAP_HOST_INTERFACE_ID]: ['ownPublicKey'] }, undefined)).toEqual([
      { interfaceId: ZSWAP_HOST_INTERFACE_ID, resolved: false, missing: ['ownPublicKey'] },
    ]);
  });

  test("the root's entry check names the circuit and the gap, and passes a contract declaring nothing", () => {
    expect(() => assertHostInterfaces(context(), {}, 'claim')).not.toThrow();
    expect(() => assertHostInterfaces(context(), { [ZSWAP_HOST_INTERFACE_ID]: ['ownPublicKey'] }, 'claim')).toThrow(
      /^claim: the contract declares host functions but the circuit context carries no host interface provider/,
    );
    const partial = context(providerOf({ 'vendor:thing/partial@1.0.0': { f: () => 1n } }));
    expect(() => assertHostInterfaces(partial, { 'vendor:thing/partial@1.0.0': ['f', 'g'] }, 'claim')).toThrow(
      /^claim: the implementation the host interface provider resolves for 'vendor:thing\/partial@1.0.0' has no function g/,
    );
    expect(() => assertHostInterfaces(partial, { 'vendor:thing/other@1.0.0': ['f'] }, 'claim')).toThrow(
      /^claim: the host interface provider resolves no 'vendor:thing\/other@1.0.0', of which f is required/,
    );
    expect(() => assertHostInterfaces(partial, { 'vendor:thing/partial@1.0.0': ['f'] }, 'claim')).not.toThrow();
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
