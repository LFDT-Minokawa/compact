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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v1';
import { CircuitContext } from './circuit-context.js';
import { Bytes32Descriptor, ShieldedCoinInfoDescriptor, ShieldedCoinRecipientDescriptor, Recipient } from './compact-types.js';
import { toHex } from './utils.js';

/**
 * Tracks the coins consumed and produced throughout circuit execution.
 */
export interface ZswapLocalState {
  /**
   * The Zswap coin public key of the user executing the circuit.
   */
  coinPublicKey: ocrt.CoinPublicKey;
  /**
   * The Merkle tree index of the next coin produced.
   */
  currentIndex: bigint;
  /**
   * The coins consumed as inputs to the circuit.
   */
  inputs: ocrt.QualifiedShieldedCoinInfo[];
  /**
   * The coins produced as outputs from the circuit.
   */
  outputs: {
    coinInfo: ocrt.ShieldedCoinInfo;
    recipient: Recipient;
  }[];
}

/**
 * A {@link CoinPublicKey} encoded as a byte string. This representation is used internally by the contract executable.
 */
export interface EncodedCoinPublicKey {
  /**
   * The coin public key's bytes.
   */
  readonly bytes: Uint8Array;
}

/**
 * A {@link ContractAddress} encoded as a byte string. This representation is used internally by the contract executable.
 */
export interface EncodedContractAddress {
  /**
   * The contract address's bytes.
   */
  readonly bytes: Uint8Array;
}

/**
 * A {@link ShieldedCoinInfo} with its fields encoded as byte strings. This representation is used internally by
 * the contract executable.
 */
export interface EncodedShieldedCoinInfo {
  /**
   * The coin's randomness, preventing it from colliding with other coins.
   */
  readonly nonce: Uint8Array;
  /**
   * The coin's type, identifying the currency it represents.
   */
  readonly color: Uint8Array;
  /**
   * The coin's value, in atomic units dependent on the currency. Bounded to be a non-negative 64-bit integer.
   */
  readonly value: bigint;
}

/**
 * A {@link QualifiedCoinInfo} with its fields encoded as byte strings. This representation is used internally by
 * the contract executable.
 */
export interface EncodedQualifiedShieldedCoinInfo extends EncodedShieldedCoinInfo {
  /**
   * The coin's location in the chain's Merkle tree of coin commitments. Bounded to be a non-negative 64-bit integer.
   */
  readonly mt_index: bigint;
}

/**
 * A {@link Recipient} with its fields encoded as byte strings. This representation is used internally by the contract executable.
 */
export interface EncodedRecipient {
  /**
   * Whether the recipient is a user or a contract.
   */
  readonly is_left: boolean;
  /**
   * The recipient's public key, if the recipient is a user.
   */
  readonly left: EncodedCoinPublicKey;
  /**
   * The recipient's contract address, if the recipient is a contract.
   */
  readonly right: EncodedContractAddress;
}

/**
 * Tracks the coins consumed and produced throughout circuit execution.
 */
export interface EncodedZswapLocalState {
  /**
   * The Zswap coin public key of the user executing the circuit.
   */
  coinPublicKey: EncodedCoinPublicKey;
  /**
   * The Merkle tree index of the next coin produced.
   */
  currentIndex: bigint;
  /**
   * The coins consumed as inputs to the circuit.
   */
  inputs: EncodedQualifiedShieldedCoinInfo[];
  /**
   * The coins produced as outputs from the circuit.
   */
  outputs: {
    coinInfo: EncodedShieldedCoinInfo;
    recipient: EncodedRecipient;
  }[];
}

/**
 * Constructs a new {@link EncodedZswapLocalState} with the given coin public key. The result can be used to create a
 * {@link ConstructorContext}.
 *
 * @param coinPublicKey The Zswap coin public key of the user executing the circuit.
 */
export const emptyZswapLocalState = (coinPublicKey: ocrt.CoinPublicKey | EncodedCoinPublicKey): EncodedZswapLocalState => ({
  coinPublicKey: typeof coinPublicKey === 'string' ? { bytes: ocrt.encodeCoinPublicKey(coinPublicKey) } : coinPublicKey,
  currentIndex: 0n,
  inputs: [],
  outputs: [],
});

/**
 * Converts an {@link Recipient} to an {@link EncodedRecipient}. Useful for testing.
 */
export const encodeRecipient = ({ is_left, left, right }: Recipient): EncodedRecipient => ({
  is_left,
  left: { bytes: ocrt.encodeCoinPublicKey(left) },
  right: { bytes: ocrt.encodeContractAddress(right) },
});

/**
 * Converts an {@link EncodedRecipient} to a {@link Recipient}.
 */
export const decodeRecipient = ({ is_left, left, right }: EncodedRecipient): Recipient => ({
  is_left,
  left: ocrt.decodeCoinPublicKey(left.bytes),
  right: ocrt.decodeContractAddress(right.bytes),
});

/**
 * Converts a {@link ZswapLocalState} to an {@link EncodedZswapLocalState}. Useful for testing.
 *
 * @param state The decoded Zswap local state.
 */
export const encodeZswapLocalState = (state: ZswapLocalState): EncodedZswapLocalState => ({
  coinPublicKey: { bytes: ocrt.encodeCoinPublicKey(state.coinPublicKey) },
  currentIndex: state.currentIndex,
  inputs: state.inputs.map(ocrt.encodeQualifiedShieldedCoinInfo),
  outputs: state.outputs.map(({ coinInfo, recipient }) => ({
    coinInfo: ocrt.encodeShieldedCoinInfo(coinInfo),
    recipient: encodeRecipient(recipient),
  })),
});

/**
 * Converts an {@link EncodedZswapLocalState} to a {@link ZswapLocalState}. Used when we need to use data from contract
 * execution to construct transactions.
 *
 * @param state The encoded Zswap local state.
 */
export const decodeZswapLocalState = (state: EncodedZswapLocalState): ZswapLocalState => ({
  coinPublicKey: ocrt.decodeCoinPublicKey(state.coinPublicKey.bytes),
  currentIndex: state.currentIndex,
  inputs: state.inputs.map(ocrt.decodeQualifiedShieldedCoinInfo),
  outputs: state.outputs.map(({ coinInfo, recipient }) => ({
    coinInfo: ocrt.decodeShieldedCoinInfo(coinInfo),
    recipient: decodeRecipient(recipient),
  })),
});

/**
 * Adds a coin to the list of inputs consumed by the circuit.
 *
 * @param circuitContext The current circuit context.
 * @param qualifiedShieldedCoinInfo The input to consume.
 */
export function createZswapInput(
  circuitContext: CircuitContext,
  qualifiedShieldedCoinInfo: EncodedQualifiedShieldedCoinInfo,
): void {
  circuitContext.currentZswapLocalState = {
    ...circuitContext.currentZswapLocalState,
    inputs: circuitContext.currentZswapLocalState.inputs.concat(qualifiedShieldedCoinInfo),
  };
}

/**
 * Creates a coin commitment from the given coin information and recipient represented as an Impact value.
 *
 * @param coinInfo The coin.
 * @param recipient The coin recipient.
 *
 * @internal
 */
function createCoinCommitment(coinInfo: EncodedShieldedCoinInfo, recipient: EncodedRecipient): ocrt.AlignedValue {
  return ocrt.runtimeCoinCommitment(
    {
      value: ShieldedCoinInfoDescriptor.toValue(coinInfo),
      alignment: ShieldedCoinInfoDescriptor.alignment(),
    },
    {
      value: ShieldedCoinRecipientDescriptor.toValue(recipient),
      alignment: ShieldedCoinRecipientDescriptor.alignment(),
    },
  );
}

/**
 * Adds a coin to the list of outputs produced by the circuit.
 *
 * @param circuitContext The current circuit context.
 * @param coinInfo The coin to produce.
 * @param recipient The coin recipient - either a coin public key representing an end user or a contract address
 *                  representing a contract.
 */
export function createZswapOutput(
  circuitContext: CircuitContext<unknown>,
  coinInfo: EncodedShieldedCoinInfo,
  recipient: EncodedRecipient,
): void {
  circuitContext.currentQueryContext = circuitContext.currentQueryContext.insertCommitment(
    Buffer.from(Bytes32Descriptor.fromValue(createCoinCommitment(coinInfo, recipient).value)).toString('hex'),
    circuitContext.currentZswapLocalState.currentIndex,
  );
  circuitContext.currentZswapLocalState = {
    ...circuitContext.currentZswapLocalState,
    currentIndex: circuitContext.currentZswapLocalState.currentIndex + 1n,
    outputs: circuitContext.currentZswapLocalState.outputs.concat({
      coinInfo,
      recipient,
    }),
  };
}

/**
 * Retrieves the Zswap coin public key of the user executing the circuit.
 *
 * @param circuitContext The current circuit context.
 */
export function ownPublicKey(circuitContext: CircuitContext<unknown>): EncodedCoinPublicKey {
  return circuitContext.currentZswapLocalState.coinPublicKey;
}

/**
 * Checks whether a coin commitment has already been added to the current query context.
 *
 * @param context The current circuit context.
 * @param coinInfo The coin information to check.
 * @param recipient The coin recipient to check.
 */
export const hasCoinCommitment = (
  context: CircuitContext,
  coinInfo: EncodedShieldedCoinInfo,
  recipient: EncodedRecipient,
): boolean =>
  context.currentQueryContext.comIndices.has(toHex(Bytes32Descriptor.fromValue(createCoinCommitment(coinInfo, recipient).value)));
