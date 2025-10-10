/**
 * Each contract declaration is mapped to a subdirectory in the compiler output containing an 'index.cjs' file and an 'index.d.cts' file.
 * The subdirectory name is the contract name used in the contract declaration in Compact - in this case, 'AuthCell'.
 * The 'index.cjs' file contains the contract's JavaScript executables. The 'index.d.cts' file contains the associated TypeScript
 * definitions. This file contains all TypeScript definitions for the 'AuthCell' contract.
 */

import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';
import type * as __shared from '../shared/index.cjs';

/**
 * Each generated contract module contains a tag type for the contract. This will be useful in the future if we want, e.g.,
 * to use 'unique symbol' types in Typescript to ensure that we don't accidentally mix up different contracts.
 *
 * @parisa - The value of 'contractId' must uniquely identify the contract described by this file. IOW, if there are two 'AuthCell'
 *           contracts in the compiler input, their generated `contractId` values must be non-equal.
 */
export const contractId = 'AuthCell';
export type ContractId = typeof contractId;

/**
 * @parisa - The ledger state specific to 'AuthCell' - formerly known as 'Ledger' in DevNet
 */
export type LedgerState = {
  readonly value: __shared.StructExample;
  readonly authorizedPk: Uint8Array;
}

/**
 * A function that computes the 'Ledger' state for the contract defined in this module.
 */
export type LedgerStateDecoder = (state: __compactRuntime.StateValue) => LedgerState;

/**
 * Defines the shape of the states of all witness sets on which this contract depends.
 */
export type PrivateStates = {
  /**
   * Since this contract is 'AuthCell', and 'AuthCell' has witnesses, we know we need a witness state for 'AuthCell'.
   * '[contractId]' evaluates to 'AuthCell'.
   */
  [contractId]: unknown;
  /**
   * If 'AuthCell' called contract 'Foo', there would be another entry here, also type 'unknown', where
   * 'Foo' is the imported `index.d.cts` module for the compiler output for `Foo`.
   *
   * [Foo.contractId]: unknown;
   */
}

/**
 * The witnesses specific to 'AuthCell'. Notice witnesses are not parameterized over the global witness state. Each witness
 * set should only see the witness state for the contract in which it is defined.
 */
export type Witnesses<PS> = {
  sk(context: __compactRuntime.WitnessContext<LedgerState, PS>): readonly [PS, Uint8Array];
}

/**
 * A type representing the witnesses of all contracts (with witnesses) on which 'AuthCell' depends. The keys are the
 * names of the contracts. The values are the witness types defined in the TS modules generated for the contracts. The
 * type parameters for the witnesses are computed by indexing into 'PrivateStates'. If 'AuthCell' depended on no
 * witness sets (only contracts with ledger effects), then 'WitnessSets' would be an empty object.
 */
export type WitnessSets<PSS extends PrivateStates = PrivateStates> = {
  [contractId]: Witnesses<PSS[ContractId]>;
  /**
   * If 'AuthCell' called 'Foo', there would be another entry here:
   *
   * [Foo.contractId]: Foo.Witnesses<PSS[Foo.ContractId]>;
   */
}

/**
 * The impure circuits specific to 'AuthCell'.
 */
export type ImpureCircuits = {
  get<PSS>(context: __compactRuntime.CircuitContext<PSS>): __compactRuntime.CircuitResults<PSS, __shared.StructExample>;
  set<PSS>(context: __compactRuntime.CircuitContext<PSS>, value: __shared.StructExample): __compactRuntime.CircuitResults<PSS, void>;
}

/**
 * Type of the `initialState` function.
 */
export type StateConstructor<PS> =
  (context: __compactRuntime.ConstructorContext<PS>, value: __shared.StructExample) => __compactRuntime.ConstructorResult<PS>;

/**
 * Similar to 'Contract' from DevNet. Renamed because 'Contract' is an overloaded term, and we want to avoid having
 * to rename on every 'Contract' import.
 */
export type Executables<PSS extends PrivateStates = PrivateStates> = {
  readonly contractId: ContractId;
  readonly witnessSets: WitnessSets<PSS>;
  readonly impureCircuits: ImpureCircuits;
  readonly pureCircuits: PureCircuits;
  /**
   * @parisa - The 'initialState' function only needs the private state for 'AuthCell', so we project 'PSS' to the
   *           'AuthCell' specific portion. If 'AuthCell' defined no witnesses the type of `initialState` would be
   *           `StateConstructor<undefined>.`
   */
  readonly initialState: StateConstructor<PSS[ContractId]>;
  readonly ledger: LedgerStateDecoder;
}

export type InferredPrivateStates<W extends WitnessSets> = W extends WitnessSets<
  {
    /**
     * @parisa - like contract IDs, the inferred types ('AuthCellPS') will need to be unique.
     *           You'll have to manually compute the string X in (infer $X) entries below. X should be the value of
     *           the [contractId] property key below with 'PS' appended. For example, since '[contractId]' evaluates
     *           to 'AuthCell', X = 'AuthCell'. So, the property is typed as "infer 'AuthCellPS'". You have to use the
     *           corresponding types in the object after the '?' symbol. It's the same string you computed in the first
     *           object, just without the 'infer' prefix.
     *
     *
     */
    [contractId]: infer AuthCellPS;
  }> ? {
  [contractId]: AuthCellPS;
} : never;

/**
 * A function that creates an 'Executable' instance. Analogous to the 'constructor' from 'Contract' in DevNet.
 */
export type ExecutablesBuilder = <W extends WitnessSets>(witnessSets: W) => Executables<InferredPrivateStates<W>>;

/**
 * One pure circuit in 'AuthCell' contract.
 */
export type PureCircuits = {
  my_pure_circuit(x: bigint): bigint;
}

/**
 * It makes sense to expose all the following as constants.
 */
export declare const contractReferenceLocations: __compactRuntime.ContractReferenceLocations;
export declare const pureCircuits: PureCircuits;
export declare const ledger: LedgerStateDecoder;
export declare const executables: ExecutablesBuilder;