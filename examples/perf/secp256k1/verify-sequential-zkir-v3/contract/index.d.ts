import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';

export type Witnesses<PS> = {
  pk0(context: __compactRuntime.WitnessContext<Ledger, PS>): [PS, __compactRuntime.Secp256k1Point];
  sig0(context: __compactRuntime.WitnessContext<Ledger, PS>): [PS, { r: bigint,
                                                                     s: bigint
                                                                   }];
  pk1(context: __compactRuntime.WitnessContext<Ledger, PS>): [PS, __compactRuntime.Secp256k1Point];
  sig1(context: __compactRuntime.WitnessContext<Ledger, PS>): [PS, { r: bigint,
                                                                     s: bigint
                                                                   }];
  pk2(context: __compactRuntime.WitnessContext<Ledger, PS>): [PS, __compactRuntime.Secp256k1Point];
  sig2(context: __compactRuntime.WitnessContext<Ledger, PS>): [PS, { r: bigint,
                                                                     s: bigint
                                                                   }];
}

export type ImpureCircuits<PS> = {
  two(context: __compactRuntime.CircuitContext<PS>, d_0: Uint8Array): Promise<__compactRuntime.CircuitResults<PS, []>>;
  three(context: __compactRuntime.CircuitContext<PS>, d_0: Uint8Array): Promise<__compactRuntime.CircuitResults<PS, []>>;
}

export type ProvableCircuits<PS> = {
  two(context: __compactRuntime.CircuitContext<PS>, d_0: Uint8Array): Promise<__compactRuntime.CircuitResults<PS, []>>;
  three(context: __compactRuntime.CircuitContext<PS>, d_0: Uint8Array): Promise<__compactRuntime.CircuitResults<PS, []>>;
}

export type PureCircuits = {
}

export type Circuits<PS> = {
  two(context: __compactRuntime.CircuitContext<PS>, d_0: Uint8Array): Promise<__compactRuntime.CircuitResults<PS, []>>;
  three(context: __compactRuntime.CircuitContext<PS>, d_0: Uint8Array): Promise<__compactRuntime.CircuitResults<PS, []>>;
}

export type Ledger = {
  readonly n: bigint;
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
