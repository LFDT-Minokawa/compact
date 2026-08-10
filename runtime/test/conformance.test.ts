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

// `signatureTypesEqual` and `checkConformance`: the port of `sametype?`
// (analysis-passes/infer-types.ss:165-233) onto the encoded signatures, and the two places it
// deviates. Why conformance is needed at all is in conformance.ts.

import { describe, expect, test } from 'vitest';
import {
  CircuitSignature,
  CircuitSignatures,
  CompactError,
  InterfaceCircuitDeclaration,
  InterfaceDescriptor,
  NamedSignatureType,
  SignatureType,
  checkConformance,
  signatureTypesEqual,
} from '../src/index.js';

const FIELD: SignatureType = { tag: 'Field' };
const BOOL: SignatureType = { tag: 'Boolean' };
const UNIT: SignatureType = { tag: 'Tuple', types: [] };

const uint = (maxval: string): SignatureType => ({ tag: 'Uint', maxval });
const bytes = (length: number): SignatureType => ({ tag: 'Bytes', length });
const opaque = (tsType: string): SignatureType => ({ tag: 'Opaque', tsType });
const vector = (length: number, type: SignatureType): SignatureType => ({ tag: 'Vector', length, type });
const tuple = (...types: readonly SignatureType[]): SignatureType => ({ tag: 'Tuple', types });
const struct = (name: string, ...elements: readonly NamedSignatureType[]): SignatureType => ({
  tag: 'Struct',
  name,
  elements,
});
const enumOf = (name: string, ...elements: readonly string[]): SignatureType => ({ tag: 'Enum', name, elements });
const alias = (name: string, type: SignatureType): SignatureType => ({ tag: 'Alias', name, type });
const contract = (name: string, circuits: InterfaceDescriptor): SignatureType => ({
  tag: 'Contract',
  name,
  circuits,
});

const decl = (
  pure: boolean,
  argumentTypes: readonly SignatureType[],
  resultType: SignatureType,
): InterfaceCircuitDeclaration => ({ pure, argumentTypes, resultType });

const sig = (
  pure: boolean,
  provable: boolean,
  argumentTypes: readonly SignatureType[],
  resultType: SignatureType,
): CircuitSignature => ({ pure, provable, argumentTypes, resultType });

// 2**128-1 and 2**128-2 round to the same double, so a `maxval` carried as a number would identify
// these two types.
const MAX_U128 = '340282366920938463463374607431768211455';
const MAX_U128_LESS_ONE = '340282366920938463463374607431768211454';

describe('signatureTypesEqual: scalars', () => {
  const scalars: readonly SignatureType[] = [
    { tag: 'Boolean' },
    { tag: 'Field' },
    { tag: 'JubjubScalar' },
    { tag: 'JubjubPoint' },
    { tag: 'Secp256k1Base' },
    { tag: 'Secp256k1Scalar' },
    { tag: 'Secp256k1Point' },
  ];

  test('every scalar equals itself', () => {
    for (const s of scalars) {
      expect(signatureTypesEqual(s, { ...s })).toEqual(true);
    }
  });

  test('no scalar equals a different scalar', () => {
    for (const a of scalars) {
      for (const b of scalars) {
        expect(signatureTypesEqual(a, b)).toEqual(a.tag === b.tag);
      }
    }
  });

  test('the curve-specific tags are kept apart', () => {
    // Standing in for the compiler's same-field-type? / same-curve-type?.
    expect(signatureTypesEqual({ tag: 'Field' }, { tag: 'Secp256k1Base' })).toEqual(false);
    expect(signatureTypesEqual({ tag: 'JubjubPoint' }, { tag: 'Secp256k1Point' })).toEqual(false);
    expect(signatureTypesEqual({ tag: 'JubjubScalar' }, { tag: 'Secp256k1Scalar' })).toEqual(false);
  });
});

describe('signatureTypesEqual: Uint, Bytes, Opaque', () => {
  test('Uint compares its maximum value exactly', () => {
    expect(signatureTypesEqual(uint('255'), uint('255'))).toEqual(true);
    expect(signatureTypesEqual(uint('255'), uint('256'))).toEqual(false);
  });

  test('Uint distinguishes bounds that a JS number would collapse', () => {
    expect(Number(MAX_U128)).toEqual(Number(MAX_U128_LESS_ONE));
    expect(signatureTypesEqual(uint(MAX_U128), uint(MAX_U128_LESS_ONE))).toEqual(false);
    expect(signatureTypesEqual(uint(MAX_U128), uint(MAX_U128))).toEqual(true);
  });

  test('Bytes compares its length', () => {
    expect(signatureTypesEqual(bytes(32), bytes(32))).toEqual(true);
    expect(signatureTypesEqual(bytes(32), bytes(31))).toEqual(false);
  });

  test('Opaque compares its TypeScript type', () => {
    expect(signatureTypesEqual(opaque('string'), opaque('string'))).toEqual(true);
    expect(signatureTypesEqual(opaque('string'), opaque('Uint8Array'))).toEqual(false);
  });

  test('a Uint is not a Field and a Bytes is not an Opaque', () => {
    expect(signatureTypesEqual(uint('255'), FIELD)).toEqual(false);
    expect(signatureTypesEqual(bytes(32), opaque('Uint8Array'))).toEqual(false);
  });
});

describe('signatureTypesEqual: sequences', () => {
  test('a Vector equals a Tuple over the same element types', () => {
    // The compiler identifies these — the tvector/ttuple cross-cases in sametype?.
    expect(signatureTypesEqual(vector(2, FIELD), tuple(FIELD, FIELD))).toEqual(true);
    expect(signatureTypesEqual(tuple(FIELD, FIELD), vector(2, FIELD))).toEqual(true);
  });

  test('a Vector does not equal a Tuple with a differing element', () => {
    expect(signatureTypesEqual(vector(2, FIELD), tuple(FIELD, BOOL))).toEqual(false);
  });

  test('length matters', () => {
    expect(signatureTypesEqual(vector(2, FIELD), vector(3, FIELD))).toEqual(false);
    expect(signatureTypesEqual(tuple(FIELD), tuple(FIELD, FIELD))).toEqual(false);
  });

  test('tuple element order matters', () => {
    expect(signatureTypesEqual(tuple(FIELD, BOOL), tuple(BOOL, FIELD))).toEqual(false);
  });

  test('the empty tuple is the unit type and equals itself', () => {
    expect(signatureTypesEqual(UNIT, tuple())).toEqual(true);
  });

  test('a zero-length Vector is the empty tuple', () => {
    // Vector<0, T> has no recoverable element type, so the encoder never emits one. More permissive
    // than sametype?, which isn't transitive on zero-length sequences.
    expect(signatureTypesEqual(vector(0, FIELD), UNIT)).toEqual(true);
    expect(signatureTypesEqual(vector(0, FIELD), vector(0, BOOL))).toEqual(true);
  });

  test('sequences nest', () => {
    expect(signatureTypesEqual(vector(2, tuple(FIELD, BOOL)), vector(2, tuple(FIELD, BOOL)))).toEqual(true);
    expect(signatureTypesEqual(vector(2, tuple(FIELD, BOOL)), vector(2, tuple(FIELD, FIELD)))).toEqual(false);
  });

  test('a sequence does not equal a scalar', () => {
    expect(signatureTypesEqual(vector(1, FIELD), FIELD)).toEqual(false);
    expect(signatureTypesEqual(UNIT, BOOL)).toEqual(false);
  });
});

describe('signatureTypesEqual: nominal types', () => {
  test('a Struct compares its name, its field names and its field types', () => {
    const a = struct('Point', { name: 'x', type: FIELD }, { name: 'y', type: FIELD });
    expect(signatureTypesEqual(a, struct('Point', { name: 'x', type: FIELD }, { name: 'y', type: FIELD }))).toEqual(true);
    expect(signatureTypesEqual(a, struct('Coord', { name: 'x', type: FIELD }, { name: 'y', type: FIELD }))).toEqual(false);
    expect(signatureTypesEqual(a, struct('Point', { name: 'x', type: FIELD }, { name: 'z', type: FIELD }))).toEqual(false);
    expect(signatureTypesEqual(a, struct('Point', { name: 'x', type: FIELD }, { name: 'y', type: BOOL }))).toEqual(false);
    expect(signatureTypesEqual(a, struct('Point', { name: 'x', type: FIELD }))).toEqual(false);
  });

  test('Struct field order matters', () => {
    const a = struct('Pair', { name: 'x', type: FIELD }, { name: 'y', type: BOOL });
    const b = struct('Pair', { name: 'y', type: BOOL }, { name: 'x', type: FIELD });
    expect(signatureTypesEqual(a, b)).toEqual(false);
  });

  test('an Enum compares its name and its members in order', () => {
    const a = enumOf('Color', 'red', 'green');
    expect(signatureTypesEqual(a, enumOf('Color', 'red', 'green'))).toEqual(true);
    expect(signatureTypesEqual(a, enumOf('Bob', 'red', 'green'))).toEqual(false);
    expect(signatureTypesEqual(a, enumOf('Color', 'green', 'red'))).toEqual(false);
    expect(signatureTypesEqual(a, enumOf('Color', 'red', 'green', 'blue'))).toEqual(false);
  });

  test('an Alias compares its name and the type it names', () => {
    // Only a `new type` reaches here. a transparent alias is erased at emission.
    expect(signatureTypesEqual(alias('Age', uint('255')), alias('Age', uint('255')))).toEqual(true);
    expect(signatureTypesEqual(alias('Age', uint('255')), alias('Weight', uint('255')))).toEqual(false);
    expect(signatureTypesEqual(alias('Age', uint('255')), alias('Age', uint('65535')))).toEqual(false);
  });

  test('a nominal alias is not its underlying type', () => {
    expect(signatureTypesEqual(alias('Age', uint('255')), uint('255'))).toEqual(false);
  });

  test('a Struct is not a Tuple of the same field types', () => {
    expect(signatureTypesEqual(struct('P', { name: 'x', type: FIELD }), tuple(FIELD))).toEqual(false);
  });
});

describe('signatureTypesEqual: nested contract types', () => {
  const transfer: InterfaceDescriptor = { transfer: decl(false, [FIELD], UNIT) };

  test('two contract types with the same circuits are equal', () => {
    expect(signatureTypesEqual(contract('Token', transfer), contract('Token', transfer))).toEqual(true);
  });

  test('the contract type name is deliberately not compared', () => {
    // Two independently authored units need not have picked the same name for the same shape.
    expect(signatureTypesEqual(contract('Token', transfer), contract('Erc20', transfer))).toEqual(true);
  });

  test('purity is an equality between two contract types, not an implication', () => {
    // Two declarations being compared, not a declaration against an implementation.
    const pure: InterfaceDescriptor = { transfer: decl(true, [FIELD], UNIT) };
    expect(signatureTypesEqual(contract('T', transfer), contract('T', pure))).toEqual(false);
    expect(signatureTypesEqual(contract('T', pure), contract('T', transfer))).toEqual(false);
  });

  test('circuit names are matched nominally', () => {
    const renamed: InterfaceDescriptor = { send: decl(false, [FIELD], UNIT) };
    expect(signatureTypesEqual(contract('T', transfer), contract('T', renamed))).toEqual(false);
  });

  test('a contract type with extra circuits is a different type', () => {
    const more: InterfaceDescriptor = { ...transfer, balance: decl(true, [], FIELD) };
    expect(signatureTypesEqual(contract('T', transfer), contract('T', more))).toEqual(false);
    expect(signatureTypesEqual(contract('T', more), contract('T', transfer))).toEqual(false);
  });

  test('circuit declaration order does not matter', () => {
    const ab: InterfaceDescriptor = { a: decl(false, [], UNIT), b: decl(true, [], FIELD) };
    const ba: InterfaceDescriptor = { b: decl(true, [], FIELD), a: decl(false, [], UNIT) };
    expect(signatureTypesEqual(contract('T', ab), contract('T', ba))).toEqual(true);
  });

  test('argument and result types are compared', () => {
    expect(signatureTypesEqual(contract('T', transfer), contract('T', { transfer: decl(false, [BOOL], UNIT) }))).toEqual(false);
    expect(signatureTypesEqual(contract('T', transfer), contract('T', { transfer: decl(false, [FIELD], FIELD) }))).toEqual(false);
    expect(signatureTypesEqual(contract('T', transfer), contract('T', { transfer: decl(false, [FIELD, FIELD], UNIT) }))).toEqual(
      false,
    );
  });

  test('contract types nest', () => {
    const inner: InterfaceDescriptor = { balance: decl(true, [], FIELD) };
    const outer = (t: SignatureType): SignatureType => contract('Outer', { vault: decl(true, [], t) });
    expect(signatureTypesEqual(outer(contract('Vault', inner)), outer(contract('Safe', inner)))).toEqual(true);
    expect(
      signatureTypesEqual(outer(contract('Vault', inner)), outer(contract('Vault', { balance: decl(true, [], BOOL) }))),
    ).toEqual(false);
  });

  test('a circuit named for an Object.prototype member does not resolve through the prototype', () => {
    const named: InterfaceDescriptor = { constructor: decl(false, [], UNIT) };
    expect(signatureTypesEqual(contract('T', named), contract('T', { toString: decl(false, [], UNIT) }))).toEqual(false);
    expect(signatureTypesEqual(contract('T', named), contract('T', named))).toEqual(true);
  });
});

describe('checkConformance', () => {
  const declaration: InterfaceDescriptor = {
    transfer: decl(false, [FIELD, uint('255')], BOOL),
    balance: decl(true, [], FIELD),
  };

  const conforming: CircuitSignatures = {
    transfer: sig(false, true, [FIELD, uint('255')], BOOL),
    balance: sig(true, false, [], FIELD),
  };

  test('a module that implements the declaration conforms', () => {
    expect(checkConformance(declaration, conforming)).toEqual({ outcome: 'Conformant' });
  });

  test('an empty declaration conforms against anything', () => {
    expect(checkConformance({}, conforming)).toEqual({ outcome: 'Conformant' });
    expect(checkConformance({}, {})).toEqual({ outcome: 'Conformant' });
  });

  test('a module may implement more than the declaration asks for', () => {
    const extra: CircuitSignatures = { ...conforming, mint: sig(false, true, [FIELD], UNIT) };
    expect(checkConformance(declaration, extra)).toEqual({ outcome: 'Conformant' });
  });

  test('a missing circuit is an existence failure naming that circuit', () => {
    const missing: CircuitSignatures = { balance: conforming.balance };
    expect(checkConformance(declaration, missing)).toEqual({ outcome: 'Violation', circuitId: 'transfer', check: 'Existence' });
  });

  test('a circuit named for an Object.prototype member is not found on the prototype', () => {
    // Without the own-property guard, `implementation['constructor']` resolves to Object and gets
    // read as a CircuitSignature.
    const declared: InterfaceDescriptor = { constructor: decl(false, [], UNIT) };
    expect(checkConformance(declared, {})).toEqual({ outcome: 'Violation', circuitId: 'constructor', check: 'Existence' });
    expect(checkConformance({ toString: decl(false, [], UNIT) }, {})).toEqual({
      outcome: 'Violation',
      circuitId: 'toString',
      check: 'Existence',
    });
  });

  test('a declared-pure circuit must be implemented pure', () => {
    const impure: CircuitSignatures = { ...conforming, balance: sig(false, true, [], FIELD) };
    expect(checkConformance(declaration, impure)).toEqual({ outcome: 'Violation', circuitId: 'balance', check: 'Purity' });
  });

  test('a declared-impure circuit may be implemented pure', () => {
    // Declaring `pure` is a promise the caller relies on; declaring nothing isn't.
    const declaredImpure: InterfaceDescriptor = { balance: decl(false, [], FIELD) };
    const implementedPureAndProvable: CircuitSignatures = { balance: sig(true, true, [], FIELD) };
    expect(checkConformance(declaredImpure, implementedPureAndProvable)).toEqual({ outcome: 'Conformant' });
  });

  test('a declared-impure circuit must be provable', () => {
    const notProvable: CircuitSignatures = { ...conforming, transfer: sig(false, false, [FIELD, uint('255')], BOOL) };
    expect(checkConformance(declaration, notProvable)).toEqual({ outcome: 'Violation', circuitId: 'transfer', check: 'Provability' });
  });

  test('a declared-pure circuit need not be provable', () => {
    expect(checkConformance({ balance: decl(true, [], FIELD) }, { balance: sig(true, false, [], FIELD) })).toEqual({ outcome: 'Conformant' });
  });

  test('arity must match exactly', () => {
    const wrongArity: CircuitSignatures = { ...conforming, transfer: sig(false, true, [FIELD], BOOL) };
    expect(checkConformance(declaration, wrongArity)).toEqual({ outcome: 'Violation', circuitId: 'transfer', check: 'Arity' });
  });

  test('a differing argument type reports its index', () => {
    const wrongArg: CircuitSignatures = { ...conforming, transfer: sig(false, true, [FIELD, uint('65535')], BOOL) };
    expect(checkConformance(declaration, wrongArg)).toEqual({
      outcome: 'Violation',
      circuitId: 'transfer',
      check: 'ArgumentType',
      argumentIndex: 1,
    });
  });

  test('the first differing argument is the one reported', () => {
    const wrongArgs: CircuitSignatures = { ...conforming, transfer: sig(false, true, [BOOL, BOOL], BOOL) };
    expect(checkConformance(declaration, wrongArgs)).toEqual({
      outcome: 'Violation',
      circuitId: 'transfer',
      check: 'ArgumentType',
      argumentIndex: 0,
    });
  });

  test('argument types are invariant, not merely compatible', () => {
    // A narrower Uint is not a stand-in for a wider one.
    const narrower: CircuitSignatures = { ...conforming, transfer: sig(false, true, [FIELD, uint('127')], BOOL) };
    expect(checkConformance(declaration, narrower)).toMatchObject({ outcome: 'Violation', check: 'ArgumentType' });
  });

  test('a differing result type is reported', () => {
    const wrongResult: CircuitSignatures = { ...conforming, transfer: sig(false, true, [FIELD, uint('255')], FIELD) };
    expect(checkConformance(declaration, wrongResult)).toEqual({ outcome: 'Violation', circuitId: 'transfer', check: 'ResultType' });
  });

  test('rules apply in order, so the earliest failure is the one reported', () => {
    // Absent, and would also fail every later rule.
    const absentAndWrong: CircuitSignatures = { balance: sig(false, false, [BOOL], BOOL) };
    expect(checkConformance(declaration, absentAndWrong)).toEqual({ outcome: 'Violation', circuitId: 'transfer', check: 'Existence' });
    // Present, but breaks purity before it breaks arity.
    const impureAndWrongArity: CircuitSignatures = { ...conforming, balance: sig(false, true, [BOOL], FIELD) };
    expect(checkConformance(declaration, impureAndWrongArity)).toEqual({ outcome: 'Violation', circuitId: 'balance', check: 'Purity' });
  });

  test('a nested contract-typed argument is compared structurally', () => {
    const inner: InterfaceDescriptor = { balance: decl(true, [], FIELD) };
    const declared: InterfaceDescriptor = { hold: decl(false, [contract('Vault', inner)], UNIT) };
    const sameShapeDifferentName: CircuitSignatures = {
      hold: sig(false, true, [contract('Safe', inner)], UNIT),
    };
    const differentShape: CircuitSignatures = {
      hold: sig(false, true, [contract('Vault', { balance: decl(true, [], BOOL) })], UNIT),
    };
    expect(checkConformance(declared, sameShapeDifferentName)).toEqual({ outcome: 'Conformant' });
    expect(checkConformance(declared, differentShape)).toEqual({
      outcome: 'Violation',
      circuitId: 'hold',
      check: 'ArgumentType',
      argumentIndex: 0,
    });
  });
});

describe('checkConformance: an unreadable module', () => {
  // A tag from a compiler this build doesn't know; the cast is what external data looks like here.
  const FUTURE = { tag: 'Summer', modulus: '7' } as unknown as SignatureType;

  const declaration: InterfaceDescriptor = { transfer: decl(false, [FIELD], BOOL) };

  test('an unknown tag in an argument is Unreadable, not a type mismatch', () => {
    // Reporting this as ArgumentType would send the reader comparing two types when the problem is
    // the build.
    const impl: CircuitSignatures = { transfer: sig(false, true, [FUTURE], BOOL) };
    expect(checkConformance(declaration, impl)).toEqual({
      outcome: 'Unreadable',
      circuitId: 'transfer',
      unreadableTag: 'Summer',
      argumentIndex: 0,
    });
  });

  test('an unknown tag in the result type reports no argument index', () => {
    const impl: CircuitSignatures = { transfer: sig(false, true, [FIELD], FUTURE) };
    expect(checkConformance(declaration, impl)).toEqual({
      outcome: 'Unreadable',
      circuitId: 'transfer',
      unreadableTag: 'Summer',
    });
  });

  test('an unknown tag nested inside a composite type is still found', () => {
    const nested: readonly [string, SignatureType][] = [
      ['Vector', vector(2, FUTURE)],
      ['Tuple', tuple(FIELD, FUTURE)],
      ['Struct', struct('S', { name: 'a', type: FUTURE })],
      ['Alias', alias('A', FUTURE)],
      ['Contract', contract('T', { c: decl(true, [FUTURE], UNIT) })],
      ['Contract result', contract('T', { c: decl(true, [], FUTURE) })],
      ['deeply nested', vector(2, struct('S', { name: 'a', type: tuple(BOOL, alias('A', FUTURE)) }))],
    ];
    for (const [label, type] of nested) {
      const impl: CircuitSignatures = { transfer: sig(false, true, [type], BOOL) };
      expect({ label, ...checkConformance(declaration, impl) }).toEqual({
        label,
        outcome: 'Unreadable',
        circuitId: 'transfer',
        unreadableTag: 'Summer',
        argumentIndex: 0,
      });
    }
  });

  test('readability is decided before the comparison at that position', () => {
    // Argument 0 differs and argument 1 is unreadable. Position 0 comes first, so unreadability
    // doesn't preempt a violation we can actually explain.
    const twoArgs: InterfaceDescriptor = { transfer: decl(false, [FIELD, FIELD], BOOL) };
    const impl: CircuitSignatures = { transfer: sig(false, true, [BOOL, FUTURE], BOOL) };
    expect(checkConformance(twoArgs, impl)).toEqual({
      outcome: 'Violation',
      circuitId: 'transfer',
      check: 'ArgumentType',
      argumentIndex: 0,
    });
  });

  test('the earlier rules still win over readability', () => {
    // Existence, purity, provability and arity need no types, so they are decided first.
    const impl: CircuitSignatures = { transfer: sig(false, true, [FUTURE, FUTURE], BOOL) };
    expect(checkConformance(declaration, impl)).toEqual({
      outcome: 'Violation',
      circuitId: 'transfer',
      check: 'Arity',
    });
  });

  test('a circuit the declaration does not name is never read', () => {
    // Rejecting a module over a feature the caller never touches would be wrong.
    const impl: CircuitSignatures = {
      transfer: sig(false, true, [FIELD], BOOL),
      mint: sig(false, true, [FUTURE], FUTURE),
    };
    expect(checkConformance(declaration, impl)).toEqual({ outcome: 'Conformant' });
  });

  test('signatureTypesEqual throws rather than answering false', () => {
    // `false` would read as "these types differ", which we're not in a position to claim.
    expect(() => signatureTypesEqual(FUTURE, FIELD)).toThrow(CompactError);
    expect(() => signatureTypesEqual(FUTURE, FIELD)).toThrow(/unreadable signature type/);
  });

  test('an unknown tag on the right-hand side is caught too', () => {
    // `a.tag === b.tag` already fails, so it is the screen over the implementation that catches it.
    expect(() => signatureTypesEqual(FIELD, FUTURE)).not.toThrow();
    expect(signatureTypesEqual(FIELD, FUTURE)).toEqual(false);
    const impl: CircuitSignatures = { transfer: sig(false, true, [FUTURE], BOOL) };
    expect(checkConformance(declaration, impl)).toMatchObject({ outcome: 'Unreadable' });
  });
});
