import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';

export type Witnesses<PS> = {
}

export type ImpureCircuits<PS> = {
  spend(context: __compactRuntime.CircuitContext<PS>,
        sk_0: { is_left: boolean,
                left: { bytes: Uint8Array },
                right: { bytes: Uint8Array }
              },
        path_0: { leaf: Uint8Array,
                  path: { sibling: { field: bigint }, goes_left: boolean }[]
                },
        coin_0: { nonce: Uint8Array, color: Uint8Array, value: bigint },
        rc_0: bigint): Promise<__compactRuntime.CircuitResults<PS, []>>;
  output(context: __compactRuntime.CircuitContext<PS>,
         pk_0: { is_left: boolean,
                 left: { bytes: Uint8Array },
                 right: { bytes: Uint8Array }
               },
         coin_0: { nonce: Uint8Array, color: Uint8Array, value: bigint },
         rc_0: bigint): Promise<__compactRuntime.CircuitResults<PS, []>>;
  sign(context: __compactRuntime.CircuitContext<PS>,
       secretKey_0: { bytes: Uint8Array }): Promise<__compactRuntime.CircuitResults<PS, []>>;
}

export type ProvableCircuits<PS> = {
  spend(context: __compactRuntime.CircuitContext<PS>,
        sk_0: { is_left: boolean,
                left: { bytes: Uint8Array },
                right: { bytes: Uint8Array }
              },
        path_0: { leaf: Uint8Array,
                  path: { sibling: { field: bigint }, goes_left: boolean }[]
                },
        coin_0: { nonce: Uint8Array, color: Uint8Array, value: bigint },
        rc_0: bigint): Promise<__compactRuntime.CircuitResults<PS, []>>;
  output(context: __compactRuntime.CircuitContext<PS>,
         pk_0: { is_left: boolean,
                 left: { bytes: Uint8Array },
                 right: { bytes: Uint8Array }
               },
         coin_0: { nonce: Uint8Array, color: Uint8Array, value: bigint },
         rc_0: bigint): Promise<__compactRuntime.CircuitResults<PS, []>>;
  sign(context: __compactRuntime.CircuitContext<PS>,
       secretKey_0: { bytes: Uint8Array }): Promise<__compactRuntime.CircuitResults<PS, []>>;
}

export type PureCircuits = {
}

export type Circuits<PS> = {
  spend(context: __compactRuntime.CircuitContext<PS>,
        sk_0: { is_left: boolean,
                left: { bytes: Uint8Array },
                right: { bytes: Uint8Array }
              },
        path_0: { leaf: Uint8Array,
                  path: { sibling: { field: bigint }, goes_left: boolean }[]
                },
        coin_0: { nonce: Uint8Array, color: Uint8Array, value: bigint },
        rc_0: bigint): Promise<__compactRuntime.CircuitResults<PS, []>>;
  output(context: __compactRuntime.CircuitContext<PS>,
         pk_0: { is_left: boolean,
                 left: { bytes: Uint8Array },
                 right: { bytes: Uint8Array }
               },
         coin_0: { nonce: Uint8Array, color: Uint8Array, value: bigint },
         rc_0: bigint): Promise<__compactRuntime.CircuitResults<PS, []>>;
  sign(context: __compactRuntime.CircuitContext<PS>,
       secretKey_0: { bytes: Uint8Array }): Promise<__compactRuntime.CircuitResults<PS, []>>;
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
