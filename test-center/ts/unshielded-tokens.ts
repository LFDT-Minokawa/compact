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

const sampleDomainSep = (): Buffer => {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Buffer.from(bytes);
};

const toHex = (bytes: Uint8Array) =>
  Buffer.from(bytes).toString('hex');

const expectEmptyEffectsExcept = (effects: runtime.Effects, fields: string[]): void =>
  Object.entries(effects).forEach(([key, value]) => {
    if (!fields.includes(key)) {
      if (value instanceof Array) {
        expect(value.length).toBe(0);
      }
      if (value instanceof Map) {
        expect(value.size).eq(0);
      }
    }
  });

const mapFindByKey = <K, V>(map: Map<K, V>, key: K): V | undefined => {
  let result;
  [...map.entries()].forEach(([k, v]) => {
    if (JSON.stringify(k) === JSON.stringify(key)) {
      result = v;
    }
  });
  return result;
};

test('mintUnshieldedToSelfTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const amount = 100n;
  const domainSep = sampleDomainSep();

  context = c.circuits.mintUnshieldedToSelfTest(context, domainSep, amount).context;

  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedUnshieldedSpends', 'unshieldedMints']);

  const claimedUnshieldedSpends = context.currentQueryContext.effects.claimedUnshieldedSpends;
  const unshieldedMints = context.currentQueryContext.effects.unshieldedMints;

  const rawSelfAddress = context.currentQueryContext.address;
  const rawTokenType = runtime.rawTokenType(domainSep, rawSelfAddress);
  const tokenType = {
    tag: 'unshielded',
    raw: rawTokenType,
  } as const;
  const publicAddress = {
    tag: 'contract',
    address: rawSelfAddress,
  } as const;

  const claimedUnshieldedSpend = mapFindByKey(claimedUnshieldedSpends, [tokenType, publicAddress]);
  expect(claimedUnshieldedSpend).toBe(amount);

  const domainSepHex = toHex(domainSep);
  const unshieldedMint = unshieldedMints.get(domainSepHex);
  expect(unshieldedMint).toBe(amount);

  const testPublicAddress = {
    tag: 'contract',
    address: 'hello',
  } as const;
  const testClaimedSpend = mapFindByKey(claimedUnshieldedSpends, [tokenType, testPublicAddress]);
  expect(testClaimedSpend).toBeUndefined();
});

const sampleContractRecipient = () => ({
  bytes: runtime.encodeContractAddress(runtime.sampleContractAddress()),
});

test('mintUnshieldedToContractTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const amount = 100n;
  const domainSep = sampleDomainSep();
  const recipient = sampleContractRecipient();

  context = c.circuits.mintUnshieldedToContractTest(context, domainSep, recipient, amount).context;

  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedUnshieldedSpends', 'unshieldedMints']);

  const claimedUnshieldedSpends = context.currentQueryContext.effects.claimedUnshieldedSpends;
  const unshieldedMints = context.currentQueryContext.effects.unshieldedMints;

  const rawSelfAddress = context.currentQueryContext.address;
  const rawTokenType = runtime.rawTokenType(domainSep, rawSelfAddress);
  const tokenType = {
    tag: 'unshielded',
    raw: rawTokenType,
  } as const;
  const rawRecipientAddress = runtime.decodeContractAddress(recipient.bytes);
  const publicAddress = {
    tag: 'contract',
    address: rawRecipientAddress,
  } as const;

  const claimedUnshieldedSpend = mapFindByKey(claimedUnshieldedSpends, [tokenType, publicAddress]);
  expect(claimedUnshieldedSpend).toBe(amount);

  const domainSepHex = toHex(domainSep);
  const unshieldedMint = unshieldedMints.get(domainSepHex);
  expect(unshieldedMint).toBe(amount);
});

const sampleUserRecipient = () => ({
  bytes: runtime.encodeUserAddress(runtime.sampleUserAddress()),
});

test('mintUnshieldedToUserTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const amount = 100n;
  const domainSep = sampleDomainSep();
  const recipient = sampleUserRecipient();

  context = c.circuits.mintUnshieldedToUserTest(context, domainSep, recipient, amount).context;

  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedUnshieldedSpends', 'unshieldedMints']);

  const claimedUnshieldedSpends = context.currentQueryContext.effects.claimedUnshieldedSpends;
  const unshieldedMints = context.currentQueryContext.effects.unshieldedMints;

  const rawSelfAddress = context.currentQueryContext.address;
  const rawTokenType = runtime.rawTokenType(domainSep, rawSelfAddress);
  const tokenType = {
    tag: 'unshielded',
    raw: rawTokenType,
  } as const;
  const rawRecipientAddress = runtime.decodeUserAddress(recipient.bytes);
  const publicAddress = {
    tag: 'user',
    address: rawRecipientAddress,
  } as const;

  const claimedUnshieldedSpend = mapFindByKey(claimedUnshieldedSpends, [tokenType, publicAddress]);
  expect(claimedUnshieldedSpend).toBe(amount);

  const domainSepHex = toHex(domainSep);
  const unshieldedMint = unshieldedMints.get(domainSepHex);
  expect(unshieldedMint).toBe(amount);
});

const sampleCompactUnshieldedCoinInfo = (rawTokenMinterAddress: runtime.ContractAddress, amount: bigint) => ({
  color: runtime.encodeRawTokenType(runtime.rawTokenType(sampleDomainSep(), rawTokenMinterAddress)),
  value: amount,
});

test('sendUnshieldedToSelfTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawTokenMinterAddress = runtime.sampleContractAddress();
  const amount = 100n;
  const unshieldedCoinInfo = sampleCompactUnshieldedCoinInfo(rawTokenMinterAddress, amount);

  context = c.circuits.sendUnshieldedToSelfTest(context, unshieldedCoinInfo.color, unshieldedCoinInfo.value).context;

  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedUnshieldedSpends', 'unshieldedOutputs']);

  const claimedUnshieldedSpends = context.currentQueryContext.effects.claimedUnshieldedSpends;
  const unshieldedOutputs = context.currentQueryContext.effects.unshieldedOutputs;

  const rawTokenType = runtime.decodeRawTokenType(unshieldedCoinInfo.color);
  const tokenType = {
    tag: 'unshielded',
    raw: rawTokenType,
  } as const;
  const rawSelfAddress = context.currentQueryContext.address;
  const publicAddress = {
    tag: 'contract',
    address: rawSelfAddress,
  } as const;

  const claimedUnshieldedSpend = mapFindByKey(claimedUnshieldedSpends, [tokenType, publicAddress]);
  expect(claimedUnshieldedSpend).toBe(amount);

  const unshieldedMint = mapFindByKey(unshieldedOutputs, tokenType);
  expect(unshieldedMint).toBe(amount);
});

test('sendUnshieldedToContractTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawTokenMinterAddress = runtime.sampleContractAddress();
  const amount = 100n;
  const unshieldedCoinInfo = sampleCompactUnshieldedCoinInfo(rawTokenMinterAddress, amount);
  const recipient = sampleContractRecipient();

  context = c.circuits.sendUnshieldedToContractTest(context, unshieldedCoinInfo.color, unshieldedCoinInfo.value, recipient).context;

  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedUnshieldedSpends', 'unshieldedOutputs']);

  const claimedUnshieldedSpends = context.currentQueryContext.effects.claimedUnshieldedSpends;
  const unshieldedOutputs = context.currentQueryContext.effects.unshieldedOutputs;

  const rawTokenType = runtime.decodeRawTokenType(unshieldedCoinInfo.color);
  const tokenType = {
    tag: 'unshielded',
    raw: rawTokenType,
  } as const;
  const rawRecipientAddress = runtime.decodeContractAddress(recipient.bytes);
  const publicAddress = {
    tag: 'contract',
    address: rawRecipientAddress,
  } as const;

  const claimedUnshieldedSpend = mapFindByKey(claimedUnshieldedSpends, [tokenType, publicAddress]);
  expect(claimedUnshieldedSpend).toBe(amount);

  const unshieldedMint = mapFindByKey(unshieldedOutputs, tokenType);
  expect(unshieldedMint).toBe(amount);
});

test('sendUnshieldedToUserTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawTokenMinterAddress = runtime.sampleContractAddress();
  const amount = 100n;
  const unshieldedCoinInfo = sampleCompactUnshieldedCoinInfo(rawTokenMinterAddress, amount);
  const recipient = sampleUserRecipient();

  context = c.circuits.sendUnshieldedToUserTest(context, unshieldedCoinInfo.color, unshieldedCoinInfo.value, recipient).context;

  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedUnshieldedSpends', 'unshieldedOutputs']);

  const claimedUnshieldedSpends = context.currentQueryContext.effects.claimedUnshieldedSpends;
  const unshieldedOutputs = context.currentQueryContext.effects.unshieldedOutputs;

  const rawTokenType = runtime.decodeRawTokenType(unshieldedCoinInfo.color);
  const tokenType = {
    tag: 'unshielded',
    raw: rawTokenType,
  } as const;
  const rawRecipientAddress = runtime.decodeUserAddress(recipient.bytes);
  const publicAddress = {
    tag: 'user',
    address: rawRecipientAddress,
  } as const;

  const claimedUnshieldedSpend = mapFindByKey(claimedUnshieldedSpends, [tokenType, publicAddress]);
  expect(claimedUnshieldedSpend).toBe(amount);

  const unshieldedMint = mapFindByKey(unshieldedOutputs, tokenType);
  expect(unshieldedMint).toBe(amount);
});

test('receiveUnshieldedTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawTokenMinterAddress = runtime.sampleContractAddress();
  const amount = 100n;
  const unshieldedCoinInfo = sampleCompactUnshieldedCoinInfo(rawTokenMinterAddress, amount);

  context = c.circuits.receiveUnshieldedTest(context, unshieldedCoinInfo.color, unshieldedCoinInfo.value).context;

  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['unshieldedInputs']);

  const unshieldedInputs = context.currentQueryContext.effects.unshieldedInputs;

  const rawTokenType = runtime.decodeRawTokenType(unshieldedCoinInfo.color);
  const tokenType = {
    tag: 'unshielded',
    raw: rawTokenType,
  } as const;

  const unshieldedInput = mapFindByKey(unshieldedInputs, tokenType);
  expect(unshieldedInput).toBe(amount);
});

test('getUnshieldedBalanceTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawTokenMinterAddress = runtime.sampleContractAddress();

  const initialBalance = 100n;
  const unshieldedCoinInfo0 = sampleCompactUnshieldedCoinInfo(rawTokenMinterAddress, initialBalance);

  const rawTokenType = runtime.decodeRawTokenType(unshieldedCoinInfo0.color);
  const tokenType = {
    tag: 'unshielded',
    raw: rawTokenType,
  } as const;

  context.currentQueryContext.block = {
    ownAddress: context.currentQueryContext.address,
    secondsSinceEpoch: 0n,
    secondsSinceEpochErr: 0,
    parentBlockHash: '0'.repeat(64),
    balance: new Map([[tokenType, initialBalance]]),
    comIndices: new Map(),
  };

  expect(c.circuits.getUnshieldedBalanceTest(context, unshieldedCoinInfo0.color).result).toBe(initialBalance);

  const unshieldedCoinInfo1 = sampleCompactUnshieldedCoinInfo(rawTokenMinterAddress, initialBalance);
  expect(c.circuits.getUnshieldedBalanceTest(context, unshieldedCoinInfo1.color).result).toBe(0n);

  const testAmount0 = 50n;
  const testAmount1 = 150n;
  expect(c.circuits.getUnshieldedBalanceGtTest(context, unshieldedCoinInfo0.color, testAmount0).result).toBe(true);
  expect(c.circuits.getUnshieldedBalanceGtTest(context, unshieldedCoinInfo0.color, testAmount1).result).toBe(false);

  const ltTestAmount0 = 50n;
  const ltTestAmount1 = 150n;
  expect(c.circuits.getUnshieldedBalanceLtTest(context, unshieldedCoinInfo0.color, ltTestAmount0).result).toBe(false);
  expect(c.circuits.getUnshieldedBalanceLtTest(context, unshieldedCoinInfo0.color, ltTestAmount1).result).toBe(true);
});
