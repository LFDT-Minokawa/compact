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
 * Whether a dynamically resolved module implements the contract type its caller declared.
 *
 * Key agreement relates a module to the chain; this relates it to what the caller declared. Skip it
 * and a Vault address passed where a Token was expected resolves to the Vault module, whose keys
 * agree with the chain perfectly and whose `transfer` means something else.
 *
 * The comparison ports `sametype?`/`circuit-superset?` (analysis-passes/infer-types.ss:131-233) onto
 * the encoded signatures, deviating only where noted.
 */

import { CircuitId } from './circuit-context.js';
import { CompactError } from './error.js';
import { CircuitSignatures, InterfaceDescriptor, SignatureType } from './interface-descriptor.js';

/** Which rule a module failed. Ordered as they are applied, per circuit. */
export type ConformanceCheck =
  /** The declaration names a circuit the module does not implement. */
  | 'Existence'
  /** The declaration says `pure` and the implementation is not pure. */
  | 'Purity'
  /** The declaration says impure and the implementation is not among the module's provable circuits. */
  | 'Provability'
  /** The two disagree on how many parameters the circuit takes. */
  | 'Arity'
  /** A positional parameter type differs. `argumentIndex` says which. */
  | 'ArgumentType'
  /** The return types differ. */
  | 'ResultType';

/** The first rule a module failed, and where. */
export type ConformanceViolation = {
  readonly circuitId: CircuitId;
  readonly check: ConformanceCheck;
  readonly argumentIndex?: number;
};

/**
 * A type constructor this build doesn't know, found in a module's signatures. Distinct from a
 * violation: a violation says something different from what was asked for, this says something we
 * can't read.
 */
export type UnreadableSignature = {
  readonly circuitId: CircuitId;
  readonly unreadableTag: string;
  readonly argumentIndex?: number;
};

/** The outcome of checking a module against a contract type. Tagged, so a call site has to handle
 *  all three. */
export type ConformanceResult =
  | { readonly outcome: 'Conformant' }
  | ({ readonly outcome: 'Violation' } & ConformanceViolation)
  | ({ readonly outcome: 'Unreadable' } & UnreadableSignature);

/**
 * Every tag {@link signatureTypesEqual} compares. Mapped over the union, so a new variant fails to
 * compile until it is listed here.
 */
const KNOWN_SIGNATURE_TAGS: { readonly [K in SignatureType['tag']]: true } = {
  Boolean: true,
  Field: true,
  JubjubScalar: true,
  JubjubPoint: true,
  Secp256k1Base: true,
  Secp256k1Scalar: true,
  Secp256k1Point: true,
  Uint: true,
  Bytes: true,
  Opaque: true,
  Vector: true,
  Tuple: true,
  Enum: true,
  Struct: true,
  Alias: true,
  Contract: true,
};

/**
 * The first tag in `t` this build doesn't recognize, or `undefined` if the whole type is readable.
 * The tag is read as `string` rather than trusted: these signatures come from a module we didn't
 * compile.
 */
const firstUnreadableTag = (t: SignatureType): string | undefined => {
  const tag = (t as { readonly tag: string }).tag;
  if (!Object.hasOwn(KNOWN_SIGNATURE_TAGS, tag)) {
    return tag;
  }
  switch (t.tag) {
    case 'Boolean':
    case 'Field':
    case 'JubjubScalar':
    case 'JubjubPoint':
    case 'Secp256k1Base':
    case 'Secp256k1Scalar':
    case 'Secp256k1Point':
    case 'Uint':
    case 'Bytes':
    case 'Opaque':
    case 'Enum':
      return undefined;
    case 'Vector':
    case 'Alias':
      return firstUnreadableTag(t.type);
    case 'Tuple':
      return firstUnreadable(t.types);
    case 'Struct':
      return firstUnreadable(t.elements.map((e) => e.type));
    case 'Contract':
      return firstUnreadableInDescriptor(t.circuits);
    default: {
      // Unreachable: unknown tags returned above, known ones all have a case. A new variant lands
      // here until it gets one.
      const exhaustive: never = t;
      throw new CompactError(`unhandled signature type ${JSON.stringify(exhaustive)}`);
    }
  }
};

const firstUnreadable = (types: readonly SignatureType[]): string | undefined => {
  for (const t of types) {
    const tag = firstUnreadableTag(t);
    if (tag !== undefined) {
      return tag;
    }
  }
  return undefined;
};

const firstUnreadableInDescriptor = (descriptor: InterfaceDescriptor): string | undefined => {
  for (const name of Object.keys(descriptor)) {
    const declaration = descriptor[name];
    const tag = firstUnreadable([...declaration.argumentTypes, declaration.resultType]);
    if (tag !== undefined) {
      return tag;
    }
  }
  return undefined;
};

/**
 * A sequence type's element types, or `undefined` if this is not a sequence.
 *
 * The compiler identifies `Vector<n, T>` with an n-tuple of `T` (the `tvector`/`ttuple` cross-cases
 * in `sametype?`), so compare element lists rather than tags. The encoder canonicalizes both before
 * emission, so the cross-case should not arise.
 */
const sequenceElements = (t: SignatureType): readonly SignatureType[] | undefined => {
  switch (t.tag) {
    case 'Vector':
      return new Array<SignatureType>(t.length).fill(t.type);
    case 'Tuple':
      return t.types;
    default:
      return undefined;
  }
};

/**
 * Structural equality of two encoded contract-type circuit sets.
 *
 * Purity is an equality here, not the top-level implication: this compares two declarations of the
 * same contract type, not a declaration against an implementation.
 *
 * Unlike `sametype?`, the contract type's name is not compared: the two sides come from different
 * compilation units, and the name is local to whichever one declared it.
 */
const contractCircuitsEqual = (a: InterfaceDescriptor, b: InterfaceDescriptor): boolean => {
  const aNames = Object.keys(a);
  if (aNames.length !== Object.keys(b).length) {
    return false;
  }
  return aNames.every((name) => {
    if (!Object.hasOwn(b, name)) {
      return false;
    }
    const x = a[name];
    const y = b[name];
    return (
      x.pure === y.pure &&
      x.argumentTypes.length === y.argumentTypes.length &&
      x.argumentTypes.every((t, i) => signatureTypesEqual(t, y.argumentTypes[i])) &&
      signatureTypesEqual(x.resultType, y.resultType)
    );
  });
};

/**
 * Whether two encoded Compact types are the same type.
 *
 * Nominal for structs, enums and `new type` aliases, matching the compiler: those names are shared
 * across compilation units through the module declaring them. Structural for contract types, per
 * {@link contractCircuitsEqual}.
 */
export function signatureTypesEqual(a: SignatureType, b: SignatureType): boolean {
  const aSeq = sequenceElements(a);
  if (aSeq !== undefined) {
    const bSeq = sequenceElements(b);
    return bSeq !== undefined && aSeq.length === bSeq.length && aSeq.every((t, i) => signatureTypesEqual(t, bSeq[i]));
  }
  switch (a.tag) {
    case 'Boolean':
    case 'Field':
    case 'JubjubScalar':
    case 'JubjubPoint':
    case 'Secp256k1Base':
    case 'Secp256k1Scalar':
    case 'Secp256k1Point':
      return b.tag === a.tag;
    case 'Uint':
      return b.tag === 'Uint' && a.maxval === b.maxval;
    case 'Bytes':
      return b.tag === 'Bytes' && a.length === b.length;
    case 'Opaque':
      return b.tag === 'Opaque' && a.tsType === b.tsType;
    case 'Enum':
      return (
        b.tag === 'Enum' &&
        a.name === b.name &&
        a.elements.length === b.elements.length &&
        a.elements.every((e, i) => e === b.elements[i])
      );
    case 'Struct':
      return (
        b.tag === 'Struct' &&
        a.name === b.name &&
        a.elements.length === b.elements.length &&
        a.elements.every((e, i) => e.name === b.elements[i].name && signatureTypesEqual(e.type, b.elements[i].type))
      );
    case 'Alias':
      return b.tag === 'Alias' && a.name === b.name && signatureTypesEqual(a.type, b.type);
    case 'Contract':
      return b.tag === 'Contract' && contractCircuitsEqual(a.circuits, b.circuits);
    case 'Vector':
    case 'Tuple':
      // Unreachable: sequences are compared above, where a Vector and a Tuple
      // over the same element types are identified as the compiler does.
      return false;
    default: {
      // Only reachable with a tag outside the union, which `checkConformance` screens for first.
      // Throw rather than return `false`, which would read as "these types differ".
      const exhaustive: never = a;
      throw new CompactError(`unreadable signature type ${JSON.stringify(exhaustive)}`);
    }
  }
}

/**
 * Check a resolved module against the contract type its caller declared, returning the first thing
 * that went wrong, or `Conformant`.
 *
 * A module may implement more circuits than the declaration names, but not fewer and not
 * differently. A declared-`pure` circuit must be implemented pure, and a declared-impure one must be
 * provable — which a pure circuit is not.
 *
 * Only the implementation is screened for readability; the declaration comes from the caller's own
 * module, which is version-locked to this runtime.
 *
 * @param declaration The caller's `declaredInterfaces[T]` for the contract type being called through.
 * @param implementation The resolved module's `circuitSignatures`.
 */
export function checkConformance(
  declaration: InterfaceDescriptor,
  implementation: CircuitSignatures,
): ConformanceResult {
  for (const circuitId of Object.keys(declaration)) {
    const declared = declaration[circuitId];
    // Own-property, not `in` or a bare index: `constructor` and `toString` are legal circuit names,
    // and `Object.prototype`'s members would otherwise read as implementations.
    if (!Object.hasOwn(implementation, circuitId)) {
      return { outcome: 'Violation', circuitId, check: 'Existence' };
    }
    const implemented = implementation[circuitId];
    if (declared.pure && !implemented.pure) {
      return { outcome: 'Violation', circuitId, check: 'Purity' };
    }
    if (!declared.pure && !implemented.provable) {
      return { outcome: 'Violation', circuitId, check: 'Provability' };
    }
    if (declared.argumentTypes.length !== implemented.argumentTypes.length) {
      return { outcome: 'Violation', circuitId, check: 'Arity' };
    }
    for (let i = 0; i < declared.argumentTypes.length; i += 1) {
      // Per position, so the report can name the argument rather than just the circuit.
      const unreadableTag = firstUnreadableTag(implemented.argumentTypes[i]);
      if (unreadableTag !== undefined) {
        return { outcome: 'Unreadable', circuitId, unreadableTag, argumentIndex: i };
      }
      if (!signatureTypesEqual(declared.argumentTypes[i], implemented.argumentTypes[i])) {
        return { outcome: 'Violation', circuitId, check: 'ArgumentType', argumentIndex: i };
      }
    }
    const unreadableTag = firstUnreadableTag(implemented.resultType);
    if (unreadableTag !== undefined) {
      return { outcome: 'Unreadable', circuitId, unreadableTag };
    }
    if (!signatureTypesEqual(declared.resultType, implemented.resultType)) {
      return { outcome: 'Violation', circuitId, check: 'ResultType' };
    }
  }
  return { outcome: 'Conformant' };
}
