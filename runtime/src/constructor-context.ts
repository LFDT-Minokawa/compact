<<<<<<< HEAD
import type * as ocrt from '@midnight-ntwrk/onchain-runtime';
import { assertIsEncodedZswapLocalState, assertIsObject, EncodedZswapLocalState } from './zswap';
import { freshZswapLocalState } from './zswap';
import { CompactError } from './error';
=======
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

import * as ocrt from '@midnight-ntwrk/onchain-runtime';
import { emptyZswapLocalState, EncodedCoinPublicKey, EncodedZswapLocalState } from './zswap.js';
>>>>>>> main

/**
 * Passed to the constructor of a contract. Used to compute the contract's initial ledger state.
 */
<<<<<<< HEAD
export interface ConstructorContext<T = any> {
  /**
   * The private state we would like to use to execute the contract's constructor.
   */
  readonly initialPrivateState: T | undefined;
  /**
   * An initial (usually fresh) Zswap local state to use to execute the contract's constructor.
   */
  readonly initialZswapLocalState: EncodedZswapLocalState;
=======
export interface ConstructorContext<PS = any> {
  /**
   * The private state we would like to use to execute the contract's constructor.
   */
  initialPrivateState: PS;
  /**
   * An initial (usually empty) Zswap local state to use to execute the contract's constructor.
   */
  initialZswapLocalState: EncodedZswapLocalState;
>>>>>>> main
}

/**
 * Creates a new {@link ConstructorContext} with the given initial private state and an empty Zswap local state.
 *
 * @param initialPrivateState The private state to use to execute the contract's constructor.
 * @param coinPublicKey The Zswap coin public key of the user executing the contract.
 */
<<<<<<< HEAD
export const createConstructorContext = <T>(
  coinPublicKey: ocrt.CoinPublicKey,
  initialPrivateState?: T,
): ConstructorContext<T> => ({
  initialPrivateState,
  initialZswapLocalState: freshZswapLocalState(coinPublicKey),
});

/**
 * Predicate asserting that an arbitrary value is a valid constructor context.
 *
 * @param v A possible {@link ConstructorContext}.
 */
export function assertIsConstructorContext(v: any): asserts v is ConstructorContext {
  assertIsObject(v);
  if (!('initialPrivateState' in v)) {
    throw new CompactError("Missing 'initialPrivateState' in constructor context");
  }
  if (!('initialZswapLocalState' in v)) {
    throw new CompactError("Missing 'initialZswapLocalState' in constructor context");
  }
  assertIsEncodedZswapLocalState(v.initialZswapLocalState);
}

/**
 * The result of executing a contract constructor.
 */
export interface ConstructorResult<T = any> {
  /**
   * The contract's initial ledger (public state).
   */
  readonly currentContractState: ocrt.ContractState;
  /**
   * The contract's initial private state. Potentially different from the private state passed in {@link ConstructorContext}.
   */
  readonly currentPrivateState?: T;
  /**
   * The contract's initial Zswap local state. Potentially includes outputs created in the contract's constructor.
   */
  readonly currentZswapLocalState: EncodedZswapLocalState;
=======
export const createConstructorContext = <PS>(
  initialPrivateState: PS,
  coinPublicKey: ocrt.CoinPublicKey | EncodedCoinPublicKey,
): ConstructorContext<PS> => ({
  initialPrivateState,
  initialZswapLocalState: emptyZswapLocalState(coinPublicKey),
});

/**
 * The result of executing a contract constructor.
 */
export interface ConstructorResult<PS = any> {
  /**
   * The contract's initial ledger (public state).
   */
  currentContractState: ocrt.ContractState;
  /**
   * The contract's initial private state. Potentially different from the private state passed in {@link ConstructorContext}.
   */
  currentPrivateState: PS;
  /**
   * The contract's initial Zswap local state. Potentially includes outputs created in the contract's constructor.
   */
  currentZswapLocalState: EncodedZswapLocalState;
>>>>>>> main
}
