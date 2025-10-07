// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';

export enum AccessControl_Role { Admin = 0, Lp = 1, Trader = 2, None = 3 }

export type Maybe<a> = { is_some: boolean; value: a };

export type MerkleTreePath<a> = { leaf: a;
    path: { sibling: { field: bigint },
        goes_left: boolean
    }[]
};

export type ZswapCoinPublicKey = { bytes: Uint8Array };

export type Witnesses<PS> = {
}

export type ImpureCircuits<PS> = {
}

export type PureCircuits = {
}

export type Circuits<PS> = {
}

export type Ledger = {
    AccessControl_roleCommits: {
        isFull(): boolean;
        checkRoot(rt_0: { field: bigint }): boolean;
        root(): __compactRuntime.MerkleTreeDigest;
        firstFree(): bigint;
        pathForLeaf(index_0: bigint, leaf_0: Uint8Array): __compactRuntime.MerkleTreePath<Uint8Array>;
        findPathForLeaf(leaf_0: Uint8Array): __compactRuntime.MerkleTreePath<Uint8Array> | undefined
    };
    AccessControl_hashUserRole: {
        isEmpty(): boolean;
        size(): bigint;
        member(elem_0: boolean): boolean;
        [Symbol.iterator](): Iterator<boolean>
    };
}

export type ContractReferenceLocations = any;

export declare const contractReferenceLocations : ContractReferenceLocations;

export declare class Contract<PS = any, W extends Witnesses<PS> = Witnesses<PS>> {
    witnesses: W;
    circuits: Circuits<PS>;
    impureCircuits: ImpureCircuits<PS>;
    constructor(witnesses: W);
    initialState(context: __compactRuntime.ConstructorContext<PS>): __compactRuntime.ConstructorResult<PS>;
}

export declare function ledger(state: __compactRuntime.StateValue): Ledger;
export declare const pureCircuits: PureCircuits;
