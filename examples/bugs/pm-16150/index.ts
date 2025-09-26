import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';

export enum AccessControl_Role { Admin = 0, Lp = 1, Trader = 2, None = 3 }

export type Maybe<a> = { is_some: boolean; value: a };

export type MerkleTreePath<a> = { leaf: a;
    path: { sibling: { field: bigint },
        goes_left: boolean
    }[]
};

export type ZswapCoinPublicKey = { bytes: Uint8Array };

export type Witnesses<T> = {
}

export type ImpureCircuits<T> = {
}

export type PureCircuits = {
}

export type Circuits<T> = {
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

export declare class Contract<T, W extends Witnesses<T> = Witnesses<T>> {
    witnesses: W;
    circuits: Circuits<T>;
    impureCircuits: ImpureCircuits<T>;
    constructor(witnesses: W);
    initialState(context: __compactRuntime.ConstructorContext<T>): __compactRuntime.ConstructorResult<T>;
}

export declare function ledger(state: __compactRuntime.StateValue): Ledger;
export declare const pureCircuits: PureCircuits;
