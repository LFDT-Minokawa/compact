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

import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import { CircuitContext } from './circuit-context.js';
import { assertDefined, CompactError } from './error.js';

/**
 * The recipient of a coin produced by a circuit.
 */
export interface Recipient {
  /**
   * Whether the recipient is a user or a contract.
   */
  readonly is_left: boolean;
  /**
   * The recipient's public key, if the recipient is a user.
   */
  readonly left: ocrt.CoinPublicKey;
  /**
   * The recipient's contract address, if the recipient is a contract.
   */
  readonly right: ocrt.ContractAddress;
}

/**
 * Tracks the coins consumed and produced throughout circuit execution.
 */
export interface ZswapLocalState {
  /**
   * The Zswap coin public key of the user executing the circuit.
   */
  coinPublicKey: ocrt.CoinPublicKey;
  /**
   * The coins consumed as inputs to the circuit.
   */
  inputs: ocrt.ShieldedCoinInfo[];
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
   * The coins consumed as inputs to the circuit.
   */
  inputs: EncodedShieldedCoinInfo[];
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
  inputs: state.inputs.map(ocrt.encodeShieldedCoinInfo),
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
  inputs: state.inputs.map(ocrt.decodeShieldedCoinInfo),
  outputs: state.outputs.map(({ coinInfo, recipient }) => ({
    coinInfo: ocrt.decodeShieldedCoinInfo(coinInfo),
    recipient: decodeRecipient(recipient),
  })),
});

const assertHasCurrentZswapLocalState = (circuitContext: CircuitContext): void => {
  if (!circuitContext.callContext.currentZswapLocalState) {
    throw new CompactError(`Zswap local state is undefined for contract '${circuitContext.callContext.contractAddress}'`);
  }
};

/**
 * Records a mutated Zswap local state on both the live call context and the per-address map
 * threaded across the whole call tree, so a cross-contract callee's coin operations survive its
 * return. Mirrors the write-back {@link queryLedgerState} performs for `queryContexts`.
 *
 * Unlike that one, this needs no "real context" guard: the generated ledger read-accessors build
 * a minimal synthetic context with no address and no maps, but they never reach this function —
 * only circuit bodies create Zswap inputs and outputs. A missing address or map here means the
 * context was not built by {@link createCircuitContext}, which is a caller error worth surfacing.
 *
 * @internal
 */
const setCurrentZswapLocalState = (circuitContext: CircuitContext<unknown>, next: EncodedZswapLocalState): void => {
  const address = circuitContext.callContext.contractAddress;
  assertDefined(address, 'contract address on the executing call context');
  assertDefined(circuitContext.zswapLocalStates, 'per-contract Zswap local states on the circuit context');
  circuitContext.callContext.currentZswapLocalState = next;
  circuitContext.zswapLocalStates[address] = next;
};

/**
 * Adds a coin to the list of inputs consumed by the circuit. The coin's position in the commitment tree is not
 * recorded: a contract-owned coin's commitment is computable from the coin and the contract address, so the
 * transaction builder locates the leaf itself.
 *
 * @param circuitContext The current circuit context.
 * @param coinInfo The input to consume.
 */
export function createZswapInput(circuitContext: CircuitContext, coinInfo: EncodedShieldedCoinInfo): [] {
  assertHasCurrentZswapLocalState(circuitContext);
  setCurrentZswapLocalState(circuitContext, {
    ...circuitContext.callContext.currentZswapLocalState,
    inputs: circuitContext.callContext.currentZswapLocalState!.inputs.concat(coinInfo),
  } as EncodedZswapLocalState);
  return [];
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
): [] {
  assertHasCurrentZswapLocalState(circuitContext);
  setCurrentZswapLocalState(circuitContext, {
    ...circuitContext.callContext.currentZswapLocalState,
    outputs: circuitContext.callContext.currentZswapLocalState!.outputs.concat({
      coinInfo,
      recipient,
    }),
  } as EncodedZswapLocalState);
  return [];
}

/**
 * Retrieves the Zswap coin public key of the user executing the circuit.
 *
 * @param circuitContext The current circuit context.
 */
export function ownPublicKey(circuitContext: CircuitContext<unknown>): EncodedCoinPublicKey {
  assertHasCurrentZswapLocalState(circuitContext);
  return circuitContext.callContext.currentZswapLocalState!.coinPublicKey;
}
