import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';

/**
 * One struct definition in 'shared' contract.
 */
export type StructExample = {
  readonly value: bigint;
}

/**
 * One pure circuit in 'shared' contract.
 */
export type PureCircuits = {
  public_key(sk: Uint8Array): Uint8Array;
}

/**
 * It makes sense to expose all the following as constants.
 */
export declare const pureCircuits: PureCircuits;
/**
 * @parisa - since 'shared' contract has no public state, it makes sense to remove the following three exports entirely while
 *           keeping the `pureCircuits` export above.
 */
// export declare const contractReferenceLocations: __compactRuntime.ContractReferenceLocations;
// export declare const ledger: LedgerStateDecoder;
// export declare const executables: ExecutablesBuilder;