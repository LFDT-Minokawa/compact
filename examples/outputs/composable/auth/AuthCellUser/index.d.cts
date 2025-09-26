/**
 * Each contract declaration is mapped to a subdirectory in the compiler output containing an 'index.cjs' file and an 'index.d.cts' file.
 * The subdirectory name is the contract name used in the contract declaration in Compact - in this case, 'AuthCellUser'.
 * The 'index.cjs' file contains the contract's JavaScript executables. The 'index.d.cts' file contains the associated TypeScript
 * definitions. This file contains all TypeScript definitions for the 'AuthCellUser' contract.
 */

import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';
import type * as __shared from '../shared/index.cjs';
/**
 * @parisa - Notice we're no longer importing witnesses and contract ID types from contract dependencies. Instead, we
 *           just import the whole module and use a qualified reference into the module, e.g., instead of:
 *
 *              type AuthCellWitnesses<PS> = import (...).Witnesses<PS>
 *              type AuthCellContractId = import (...).ContractId
 *
 *           we just use, respectively, __AuthCell.Witnesses and __AuthCell.ContractId in-place when necessary.
 */
import type * as __AuthCell from '../AuthCell/index.cjs';

/**
 * Define the tag type for 'AuthCellUser'.
 */
export const contractId = 'AuthCellUser';
export type ContractId = typeof contractId;

/**
 * Only the ledger state for 'AuthCellUser'
 */
export type LedgerState = {
  readonly authCell: __compactRuntime.ContractAddress;
}

export type LedgerStateDecoder = (state: __compactRuntime.StateValue) => LedgerState;

export type PrivateStates = {
  [contractId]: unknown;
  [__AuthCell.contractId]: unknown;
}

export type Witnesses<PS> = {
  foo(context: __compactRuntime.WitnessContext<LedgerState, PS>): readonly [PS, Uint8Array];
}

export type WitnessSets<PSS extends PrivateStates = PrivateStates> = {
  [contractId]: Witnesses<PSS[ContractId]>;
  [__AuthCell.contractId]: __AuthCell.Witnesses<PSS[__AuthCell.ContractId]>;
}

export type ImpureCircuits = {
  use_auth_cell<PSS>(context: __compactRuntime.CircuitContext<PSS>, x: __shared.StructExample): __compactRuntime.CircuitResults<PSS, bigint>;
}

export type StateConstructor<PS> =
  (context: __compactRuntime.ConstructorContext<PS>, auth_cell_param: __compactRuntime.ContractAddress) => __compactRuntime.ConstructorResult<PS>;

export type Executables<PSS extends PrivateStates = PrivateStates> = {
  readonly contractId: ContractId;
  readonly witnessSets: WitnessSets<PSS>;
  readonly impureCircuits: ImpureCircuits;
  readonly pureCircuits: PureCircuits;
  readonly stateConstructor: StateConstructor<PSS[ContractId]>;
  readonly ledgerStateDecoder: LedgerStateDecoder;
}

export type InferredPrivateStates<W extends WitnessSets> = W extends WitnessSets<{
  [contractId]: infer AuthCellUserPS;
  [__AuthCell.contractId]: infer AuthCellPS;
}> ? {
  [contractId]: AuthCellUserPS;
  [__AuthCell.contractId]: AuthCellPS;
} : never;

export type ExecutablesBuilder = <W extends WitnessSets>(witnessSets: W) => Executables<InferredPrivateStates<W>>;

/**
 * Empty object since 'AuthCellUser' defines no pure circuits.
 */
export type PureCircuits = {}

/**
 * It makes sense to expose all the following as constants.
 */
export declare const contractReferenceLocations: __compactRuntime.ContractReferenceLocations;
export declare const pureCircuits: PureCircuits;
export declare const ledgerStateDecoder: LedgerStateDecoder;
export declare const executables: ExecutablesBuilder;
