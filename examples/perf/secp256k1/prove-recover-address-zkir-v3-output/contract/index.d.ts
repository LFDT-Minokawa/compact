import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';

export type Secp256k1EcdsaSignatureWithRecovery = { r: bigint;
                                                    s: bigint;
                                                    R: __compactRuntime.Secp256k1Point
                                                  };

export type Witnesses<PS> = {
}

export type ImpureCircuits<PS> = {
  recoverAddr(context: __compactRuntime.CircuitContext<PS>,
              msgHash_0: Uint8Array,
              sig_0: Secp256k1EcdsaSignatureWithRecovery): Promise<__compactRuntime.CircuitResults<PS, Uint8Array>>;
}

export type ProvableCircuits<PS> = {
  recoverAddr(context: __compactRuntime.CircuitContext<PS>,
              msgHash_0: Uint8Array,
              sig_0: Secp256k1EcdsaSignatureWithRecovery): Promise<__compactRuntime.CircuitResults<PS, Uint8Array>>;
}

export type PureCircuits = {
}

export type Circuits<PS> = {
  recoverAddr(context: __compactRuntime.CircuitContext<PS>,
              msgHash_0: Uint8Array,
              sig_0: Secp256k1EcdsaSignatureWithRecovery): Promise<__compactRuntime.CircuitResults<PS, Uint8Array>>;
}

export type Ledger = {
  readonly lastAddr: Uint8Array;
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
