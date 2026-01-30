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

  // With auto-receive fix, minting to self now also populates unshieldedInputs
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedUnshieldedSpends', 'unshieldedMints', 'unshieldedInputs']);

  const claimedUnshieldedSpends = context.currentQueryContext.effects.claimedUnshieldedSpends;
  const unshieldedMints = context.currentQueryContext.effects.unshieldedMints;
  const unshieldedInputs = context.currentQueryContext.effects.unshieldedInputs;

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

  // Verify auto-receive: unshieldedInputs should contain the minted amount
  const unshieldedInput = mapFindByKey(unshieldedInputs, tokenType);
  expect(unshieldedInput).toBe(amount);

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

  // With auto-receive fix, sending to self now also populates unshieldedInputs
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedUnshieldedSpends', 'unshieldedOutputs', 'unshieldedInputs']);

  const claimedUnshieldedSpends = context.currentQueryContext.effects.claimedUnshieldedSpends;
  const unshieldedOutputs = context.currentQueryContext.effects.unshieldedOutputs;
  const unshieldedInputs = context.currentQueryContext.effects.unshieldedInputs;

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

  // Verify auto-receive: unshieldedInputs should contain the sent amount
  const unshieldedInput = mapFindByKey(unshieldedInputs, tokenType);
  expect(unshieldedInput).toBe(amount);
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

// Shielded token tests

const sampleNonce = (): Buffer => {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Buffer.from(bytes);
};

const sampleZswapCoinPublicKey = () => ({
  bytes: sampleNonce(),
});

const sampleShieldedCoinInfo = (color: Buffer, value: bigint) => ({
  nonce: sampleNonce(),
  color: color,
  value: value,
});

const sampleQualifiedShieldedCoinInfo = (color: Buffer, value: bigint) => ({
  nonce: sampleNonce(),
  color: color,
  value: value,
  mt_index: 0n,
});

const shieldedTokenColor = (domainSep: Buffer, rawContractAddress: runtime.ContractAddress): Buffer => {
  return Buffer.from(runtime.encodeRawTokenType(runtime.rawTokenType(domainSep, rawContractAddress)));
};

test('mintShieldedToSelfTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const value = 100n;
  const domainSep = sampleDomainSep();
  const nonce = sampleNonce();

  const result = c.circuits.mintShieldedToSelfTest(context, domainSep, value, nonce);
  context = result.context;

  // With auto-receive fix, minting to self now also populates claimedShieldedReceives
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedShieldedSpends', 'claimedShieldedReceives', 'shieldedMints']);

  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const claimedShieldedReceives = context.currentQueryContext.effects.claimedShieldedReceives;
  const shieldedMints = context.currentQueryContext.effects.shieldedMints;

  // Verify shieldedMints has the minted amount
  const domainSepHex = toHex(domainSep);
  const shieldedMint = shieldedMints.get(domainSepHex);
  expect(shieldedMint).toBe(value);

  // Verify claimedShieldedSpends has an entry (the commitment)
  expect(claimedShieldedSpends.length).toBe(1);

  // Verify auto-receive: claimedShieldedReceives should have the same commitment
  expect(claimedShieldedReceives.length).toBe(1);
  expect(claimedShieldedReceives[0]).toEqual(claimedShieldedSpends[0]);
});

test('mintShieldedToContractTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const value = 100n;
  const domainSep = sampleDomainSep();
  const nonce = sampleNonce();
  const recipient = sampleContractRecipient();

  const result = c.circuits.mintShieldedToContractTest(context, domainSep, value, nonce, recipient);
  context = result.context;

  // Minting to another contract should NOT auto-receive
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedShieldedSpends', 'shieldedMints']);

  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const shieldedMints = context.currentQueryContext.effects.shieldedMints;

  // Verify shieldedMints has the minted amount
  const domainSepHex = toHex(domainSep);
  const shieldedMint = shieldedMints.get(domainSepHex);
  expect(shieldedMint).toBe(value);

  // Verify claimedShieldedSpends has an entry
  expect(claimedShieldedSpends.length).toBe(1);
});

test('mintShieldedToUserTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const value = 100n;
  const domainSep = sampleDomainSep();
  const nonce = sampleNonce();
  const recipient = sampleZswapCoinPublicKey();

  const result = c.circuits.mintShieldedToUserTest(context, domainSep, value, nonce, recipient);
  context = result.context;

  // Minting to a user should NOT auto-receive
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedShieldedSpends', 'shieldedMints']);

  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const shieldedMints = context.currentQueryContext.effects.shieldedMints;

  // Verify shieldedMints has the minted amount
  const domainSepHex = toHex(domainSep);
  const shieldedMint = shieldedMints.get(domainSepHex);
  expect(shieldedMint).toBe(value);

  // Verify claimedShieldedSpends has an entry
  expect(claimedShieldedSpends.length).toBe(1);
});

test('receiveShieldedTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawSelfAddress = context.currentQueryContext.address;
  const domainSep = sampleDomainSep();
  const color = shieldedTokenColor(domainSep, rawSelfAddress);
  const value = 100n;
  const coin = sampleShieldedCoinInfo(color, value);

  context = c.circuits.receiveShieldedTest(context, coin).context;

  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedShieldedReceives']);

  const claimedShieldedReceives = context.currentQueryContext.effects.claimedShieldedReceives;

  // Verify claimedShieldedReceives has an entry (the commitment)
  expect(claimedShieldedReceives.length).toBe(1);
});

test('sendShieldedToSelfTestWithChange', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawSelfAddress = context.currentQueryContext.address;
  const domainSep = sampleDomainSep();
  const color = shieldedTokenColor(domainSep, rawSelfAddress);
  const inputValue = 100n;
  const sendValue = 60n;
  const input = sampleQualifiedShieldedCoinInfo(color, inputValue);

  const result = c.circuits.sendShieldedToSelfTest(context, input, sendValue);
  context = result.context;

  // When sending to self with change, we have:
  // - claimedNullifiers (from spending the input)
  // - claimedShieldedSpends (from output + change coins)
  // - claimedShieldedReceives (from change coin going back to self)
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedNullifiers', 'claimedShieldedSpends', 'claimedShieldedReceives']);

  const claimedNullifiers = context.currentQueryContext.effects.claimedNullifiers;
  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const claimedShieldedReceives = context.currentQueryContext.effects.claimedShieldedReceives;

  // Verify nullifier claimed for input
  expect(claimedNullifiers.length).toBe(1);

  // Verify 2 spends: output coin + change coin
  expect(claimedShieldedSpends.length).toBe(2);

  // Verify 2 receives: output coin (going to self) + change coin (going back to self)
  expect(claimedShieldedReceives.length).toBe(2);
});

test('sendShieldedToSelfTestNoChange', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawSelfAddress = context.currentQueryContext.address;
  const domainSep = sampleDomainSep();
  const color = shieldedTokenColor(domainSep, rawSelfAddress);
  const inputValue = 100n;
  const sendValue = 100n; // Same as input, so no change
  const input = sampleQualifiedShieldedCoinInfo(color, inputValue);

  const result = c.circuits.sendShieldedToSelfTest(context, input, sendValue);
  context = result.context;

  // With auto-receive fix, sending full amount to self (no change) also populates claimedShieldedReceives
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedNullifiers', 'claimedShieldedSpends', 'claimedShieldedReceives']);

  const claimedNullifiers = context.currentQueryContext.effects.claimedNullifiers;
  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const claimedShieldedReceives = context.currentQueryContext.effects.claimedShieldedReceives;

  // Verify nullifier claimed for input
  expect(claimedNullifiers.length).toBe(1);

  // Verify 1 spend: output coin (no change coin)
  expect(claimedShieldedSpends.length).toBe(1);

  // Verify 1 receive for output coin (auto-receive when sending to self with no change)
  expect(claimedShieldedReceives.length).toBe(1);
  expect(claimedShieldedReceives[0]).toEqual(claimedShieldedSpends[0]);
});

test('sendShieldedToContractTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawSelfAddress = context.currentQueryContext.address;
  const domainSep = sampleDomainSep();
  const color = shieldedTokenColor(domainSep, rawSelfAddress);
  const inputValue = 100n;
  const sendValue = 60n;
  const input = sampleQualifiedShieldedCoinInfo(color, inputValue);
  const recipient = sampleContractRecipient();

  const result = c.circuits.sendShieldedToContractTest(context, input, recipient, sendValue);
  context = result.context;

  // Sending to another contract with change:
  // - claimedNullifiers (from spending the input)
  // - claimedShieldedSpends (from output + change coins)
  // - claimedShieldedReceives (from change coin going back to self)
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedNullifiers', 'claimedShieldedSpends', 'claimedShieldedReceives']);

  const claimedNullifiers = context.currentQueryContext.effects.claimedNullifiers;
  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const claimedShieldedReceives = context.currentQueryContext.effects.claimedShieldedReceives;

  // Verify nullifier claimed for input
  expect(claimedNullifiers.length).toBe(1);

  // Verify 2 spends: output coin + change coin
  expect(claimedShieldedSpends.length).toBe(2);

  // Verify 1 receive for change coin (going back to self)
  expect(claimedShieldedReceives.length).toBe(1);
});

test('sendShieldedToUserTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawSelfAddress = context.currentQueryContext.address;
  const domainSep = sampleDomainSep();
  const color = shieldedTokenColor(domainSep, rawSelfAddress);
  const inputValue = 100n;
  const sendValue = 60n;
  const input = sampleQualifiedShieldedCoinInfo(color, inputValue);
  const recipient = sampleZswapCoinPublicKey();

  const result = c.circuits.sendShieldedToUserTest(context, input, recipient, sendValue);
  context = result.context;

  // Sending to user with change:
  // - claimedNullifiers (from spending the input)
  // - claimedShieldedSpends (from output + change coins)
  // - claimedShieldedReceives (from change coin going back to self)
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedNullifiers', 'claimedShieldedSpends', 'claimedShieldedReceives']);

  const claimedNullifiers = context.currentQueryContext.effects.claimedNullifiers;
  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const claimedShieldedReceives = context.currentQueryContext.effects.claimedShieldedReceives;

  // Verify nullifier claimed for input
  expect(claimedNullifiers.length).toBe(1);

  // Verify 2 spends: output coin + change coin
  expect(claimedShieldedSpends.length).toBe(2);

  // Verify 1 receive for change coin (going back to self)
  expect(claimedShieldedReceives.length).toBe(1);
});

test('sendImmediateShieldedToSelfTestNoChange', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawSelfAddress = context.currentQueryContext.address;
  const domainSep = sampleDomainSep();
  const color = shieldedTokenColor(domainSep, rawSelfAddress);
  const inputValue = 100n;
  const sendValue = 100n; // Full amount, no change
  const input = sampleShieldedCoinInfo(color, inputValue);

  const result = c.circuits.sendImmediateShieldedToSelfTest(context, input, sendValue);
  context = result.context;

  // With auto-receive fix, sending full amount to self also populates claimedShieldedReceives
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedNullifiers', 'claimedShieldedSpends', 'claimedShieldedReceives']);

  const claimedNullifiers = context.currentQueryContext.effects.claimedNullifiers;
  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const claimedShieldedReceives = context.currentQueryContext.effects.claimedShieldedReceives;

  // Verify nullifier claimed for input
  expect(claimedNullifiers.length).toBe(1);

  // Verify 1 spend: output coin (no change)
  expect(claimedShieldedSpends.length).toBe(1);

  // Verify 1 receive for output coin (auto-receive when sending to self with no change)
  expect(claimedShieldedReceives.length).toBe(1);
  expect(claimedShieldedReceives[0]).toEqual(claimedShieldedSpends[0]);
});

test('sendImmediateShieldedToContractTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawSelfAddress = context.currentQueryContext.address;
  const domainSep = sampleDomainSep();
  const color = shieldedTokenColor(domainSep, rawSelfAddress);
  const inputValue = 100n;
  const sendValue = 60n;
  const input = sampleShieldedCoinInfo(color, inputValue);
  const recipient = sampleContractRecipient();

  const result = c.circuits.sendImmediateShieldedToContractTest(context, input, recipient, sendValue);
  context = result.context;

  // Sending to another contract with change
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedNullifiers', 'claimedShieldedSpends', 'claimedShieldedReceives']);

  const claimedNullifiers = context.currentQueryContext.effects.claimedNullifiers;
  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const claimedShieldedReceives = context.currentQueryContext.effects.claimedShieldedReceives;

  // Verify nullifier claimed for input
  expect(claimedNullifiers.length).toBe(1);

  // Verify 2 spends: output coin + change coin
  expect(claimedShieldedSpends.length).toBe(2);

  // Verify 1 receive for change coin
  expect(claimedShieldedReceives.length).toBe(1);
});

test('sendImmediateShieldedToUserTest', () => {

  let [c, context] = startContract(contractCode, {}, 0);

  const rawSelfAddress = context.currentQueryContext.address;
  const domainSep = sampleDomainSep();
  const color = shieldedTokenColor(domainSep, rawSelfAddress);
  const inputValue = 100n;
  const sendValue = 60n;
  const input = sampleShieldedCoinInfo(color, inputValue);
  const recipient = sampleZswapCoinPublicKey();

  const result = c.circuits.sendImmediateShieldedToUserTest(context, input, recipient, sendValue);
  context = result.context;

  // Sending to user with change
  expectEmptyEffectsExcept(context.currentQueryContext.effects, ['claimedNullifiers', 'claimedShieldedSpends', 'claimedShieldedReceives']);

  const claimedNullifiers = context.currentQueryContext.effects.claimedNullifiers;
  const claimedShieldedSpends = context.currentQueryContext.effects.claimedShieldedSpends;
  const claimedShieldedReceives = context.currentQueryContext.effects.claimedShieldedReceives;

  // Verify nullifier claimed for input
  expect(claimedNullifiers.length).toBe(1);

  // Verify 2 spends: output coin + change coin
  expect(claimedShieldedSpends.length).toBe(2);

  // Verify 1 receive for change coin
  expect(claimedShieldedReceives.length).toBe(1);
});
