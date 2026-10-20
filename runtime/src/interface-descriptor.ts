// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

/**
 * Machine-readable signatures, emitted by the compiler into every generated contract module: the
 * circuits, the constructor, both stores' exported fields, the exported local functions and the
 * host functions. A module resolved at call time is checked against the contract type its caller
 * declared through them, and a party holding no module, such as a DApp sending a wallet a call,
 * encodes values against them (`descriptorOf`).
 */

/**
 * A Compact type as it appears in a circuit signature: a static description, compared structurally.
 * `CompactType` in compact-types.ts is the codec for a *value* of one of these.
 */
export type SignatureType =
  | { readonly tag: 'Boolean' }
  | { readonly tag: 'Field' }
  | { readonly tag: 'JubjubScalar' }
  | { readonly tag: 'JubjubPoint' }
  | { readonly tag: 'Secp256k1Base' }
  | { readonly tag: 'Secp256k1Scalar' }
  | { readonly tag: 'Secp256k1Point' }
  | { readonly tag: 'Secp256r1Base' }
  | { readonly tag: 'Secp256r1Scalar' }
  | { readonly tag: 'Secp256r1Point' }
  | { readonly tag: 'Curve25519Base' }
  | { readonly tag: 'Curve25519Scalar' }
  | { readonly tag: 'Curve25519Point' }
  /** `maxval` is the maximum representable value as a decimal string, not a
   *  width. `Uint<128>` carries 2**128-1, which is not exactly representable
   *  as a JavaScript number. */
  | { readonly tag: 'Uint'; readonly maxval: string }
  | { readonly tag: 'Bytes'; readonly length: number }
  | { readonly tag: 'Opaque'; readonly tsType: string }
  | { readonly tag: 'Vector'; readonly length: number; readonly type: SignatureType }
  | { readonly tag: 'Tuple'; readonly types: readonly SignatureType[] }
  | { readonly tag: 'Enum'; readonly name: string; readonly elements: readonly string[] }
  | { readonly tag: 'Struct'; readonly name: string; readonly elements: readonly NamedSignatureType[] }
  /** Only a `new type` declaration produces this; a transparent alias is
   *  erased at emission, since it is not a distinct type. */
  | { readonly tag: 'Alias'; readonly name: string; readonly type: SignatureType }
  | { readonly tag: 'Contract'; readonly name: string; readonly circuits: InterfaceDescriptor };

export type NamedSignatureType = {
  readonly name: string;
  readonly type: SignatureType;
};

/** One circuit as *declared* in a `contract T { }` block. `pure` is the declared keyword, not inferred purity. */
export type InterfaceCircuitDeclaration = {
  readonly pure: boolean;
  readonly argumentTypes: readonly SignatureType[];
  readonly resultType: SignatureType;
};

/** External circuit name to declaration, for one contract type. */
export type InterfaceDescriptor = Readonly<Record<string, InterfaceCircuitDeclaration>>;

/** The parameter names, in `argumentTypes` order, for a reader showing a value by its name. They
 *  are documentation, never a key: calls are positional, and nothing may match or grant on a name.
 *  Absent from a module compiled before they were emitted. */
export type ArgumentNames = {
  readonly argumentNames?: readonly string[];
};

/** One circuit as *implemented*. `pure` is inferred purity; `provable` means a proof can be
 *  generated for it. Disjoint but not exhaustive: a circuit that only calls a host function is neither. */
export type CircuitSignature = InterfaceCircuitDeclaration &
  ArgumentNames & {
    readonly provable: boolean;
  };

/** The `circuitSignatures` export of a generated contract module. */
export type CircuitSignatures = Readonly<Record<string, CircuitSignature>>;

/** The `declaredInterfaces` export of a generated contract module, keyed by
 *  contract type name. Those names are local to the declaring contract. */
export type DeclaredInterfaces = Readonly<Record<string, InterfaceDescriptor>>;

/** The `constructorSignature` export: the ledger constructor's parameters in order, which is
 *  what a deploy's arguments are encoded against. Every contract has one; a contract without
 *  a `constructor` declaration takes no arguments. */
export type ConstructorSignature = ArgumentNames & {
  readonly argumentTypes: readonly SignatureType[];
};

/** A ledger or local field as declared: the ADT holding it and the ADT's type arguments. Only
 *  a `Map`'s value may itself be an ADT, since the language nests no other container. */
export type FieldSignature =
  | { readonly storage: 'Cell'; readonly type: SignatureType }
  | { readonly storage: 'Counter' }
  | { readonly storage: 'Set'; readonly type: SignatureType }
  | { readonly storage: 'List'; readonly type: SignatureType }
  | { readonly storage: 'Map'; readonly key: SignatureType; readonly value: SignatureType | FieldSignature }
  | { readonly storage: 'MerkleTree'; readonly depth: number; readonly type: SignatureType }
  | { readonly storage: 'HistoricMerkleTree'; readonly depth: number; readonly type: SignatureType };

/** The `ledgerSignatures` export: the exported ledger fields, by external name, which is what
 *  the `ledger()` accessor exposes. */
export type LedgerSignatures = {
  readonly fields: Readonly<Record<string, FieldSignature>>;
};

/** An exported local function as `localState()` exposes it. `readsLedger` means the accessor
 *  needs a ledger state to run it. */
export type LocalFunctionSignature = ArgumentNames & {
  readonly argumentTypes: readonly SignatureType[];
  readonly resultType: SignatureType;
  readonly readsLedger: boolean;
};

/** The `localStateSignatures` export: the exported local fields and exported local functions, by
 *  external name, which is what the `localState()` accessor exposes. Both empty for a contract
 *  without a local store. */
export type LocalStateSignatures = {
  readonly fields: Readonly<Record<string, FieldSignature>>;
  readonly functions: Readonly<Record<string, LocalFunctionSignature>>;
};

/** One host function as a `host` block declares it. */
export type HostFunctionSignature = ArgumentNames & {
  readonly argumentTypes: readonly SignatureType[];
  readonly resultType: SignatureType;
};

/** The `hostInterfaceSignatures` export: the host functions the circuits can reach, by interface
 *  id then function name. Its keys are exactly those of `hostInterfaces`, which keeps the names
 *  alone for the resolution gate. */
export type HostInterfaceSignatures = Readonly<Record<string, Readonly<Record<string, HostFunctionSignature>>>>;
