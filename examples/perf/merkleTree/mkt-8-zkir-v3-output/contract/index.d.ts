import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';

export type Witnesses<PS> = {
  findPath(context: __compactRuntime.WitnessContext<Ledger, PS>, leaf_0: bigint): [PS, { leaf: bigint,
                                                                                         path: { sibling: { field: bigint
                                                                                                          },
                                                                                                 goes_left: boolean
                                                                                               }[]
                                                                                       }];
}

export type ImpureCircuits<PS> = {
  verifyMembership(context: __compactRuntime.CircuitContext<PS>, leaf_0: bigint): Promise<__compactRuntime.CircuitResults<PS, []>>;
}

export type ProvableCircuits<PS> = {
  verifyMembership(context: __compactRuntime.CircuitContext<PS>, leaf_0: bigint): Promise<__compactRuntime.CircuitResults<PS, []>>;
}

export type PureCircuits = {
  pathRootOnly(path_0: { leaf: Uint8Array,
                         path: { sibling: { field: bigint }, goes_left: boolean
                               }[]
                       }): { field: bigint };
}

export type Circuits<PS> = {
  verifyMembership(context: __compactRuntime.CircuitContext<PS>, leaf_0: bigint): Promise<__compactRuntime.CircuitResults<PS, []>>;
  pathRootOnly(context: __compactRuntime.CircuitContext<PS>,
               path_0: { leaf: Uint8Array,
                         path: { sibling: { field: bigint }, goes_left: boolean
                               }[]
                       }): Promise<__compactRuntime.CircuitResults<PS, { field: bigint
                                                                       }>>;
}

export type Ledger = {
}

export type ContractReferenceLocations = any;

export declare const contractReferenceLocations : ContractReferenceLocations;

export declare class Contract<PS = any, W extends Witnesses<PS> = Witnesses<PS>> {
  witnesses: W;
  circuits: Circuits<PS>;
  impureCircuits: ImpureCircuits<PS>;
  provableCircuits: ProvableCircuits<PS>;
  constructor(witnesses: W);
  initialState(context: __compactRuntime.ConstructorContext<PS>): Promise<__compactRuntime.ConstructorResult<PS>>;
}

export declare function ledger(state: __compactRuntime.StateValue | __compactRuntime.ChargedState): Ledger;
export declare const pureCircuits: PureCircuits;
export declare const expectedVk: Record<string, string>;
