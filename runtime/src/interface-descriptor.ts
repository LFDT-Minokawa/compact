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
 * Machine-readable circuit signatures, emitted by the compiler into every generated contract
 * module, so a module resolved at call time can be checked against the contract type its caller
 * declared.
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

/** One circuit as *implemented*. `pure` is inferred purity; `provable` means a proof can be
 *  generated for it. Disjoint but not exhaustive: a circuit that only calls a witness is neither. */
export type CircuitSignature = InterfaceCircuitDeclaration & {
  readonly provable: boolean;
};

/** The `circuitSignatures` export of a generated contract module. */
export type CircuitSignatures = Readonly<Record<string, CircuitSignature>>;

/** The `declaredInterfaces` export of a generated contract module, keyed by
 *  contract type name. Those names are local to the declaring contract. */
export type DeclaredInterfaces = Readonly<Record<string, InterfaceDescriptor>>;
