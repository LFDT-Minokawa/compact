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

/* eslint-disable @typescript-eslint/naming-convention */
import { describe, expect } from '@jest/globals';
import { NetworkId, setNetworkId } from '@midnight-ntwrk/compact-runtime';
import { SimpleWallet } from '../src/setup';
import { networkId, setNetworkId } from '@midnight-ntwrk/midnight-js-network-id';

setNetworkId(networkId.undeployed);

describe('Counter smart contract', () => {
  it('generates initial state deterministically', () => {
    const wallet1 = new SimpleWallet();
    const wallet2 = new SimpleWallet();

    expect(wallet1.getLedger()).toEqual(wallet2.getLedger());
  });

  it('properly initialize rounds', () => {
    const wallet = new SimpleWallet();
    const initialState = wallet.getLedger();

    expect(initialState.round).toEqual(0n);
  });

  it('increments rounds correctly', () => {
    const wallet = new SimpleWallet();
    const finalState = wallet.increment();

    expect(finalState.round).toEqual(1n);
  });
});
