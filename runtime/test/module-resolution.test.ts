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

// Pins how each failure kind reads, and how the recognizer behaves.

import { describe, expect, test } from 'vitest';
import {
  CompactError,
  ModuleResolutionContext,
  ModuleResolutionError,
  ModuleResolutionFailure,
  asVerifierKeyHash,
} from '../src/index.js';

const CALLER = `0200${'11'.repeat(30)}`;
const CALLEE = `0200${'22'.repeat(30)}`;

const CONTEXT: ModuleResolutionContext = {
  calleeAddress: CALLEE,
  calleeCircuitId: 'transfer',
  interfaceName: 'Token',
  callerAddress: CALLER,
};

const VK_A = asVerifierKeyHash('a'.repeat(64));
const VK_B = asVerifierKeyHash('b'.repeat(64));

/** One value per kind, keyed by it, so adding a kind without a sample here does not compile. */
const ALL_FAILURES: { [K in ModuleResolutionFailure['kind']]: Extract<ModuleResolutionFailure, { kind: K }> } = {
  ModuleProviderAbsent: { kind: 'ModuleProviderAbsent' },
  PureInterfaceCircuit: { kind: 'PureInterfaceCircuit' },
  OperationAbsent: { kind: 'OperationAbsent' },
  UnsupportedImplementation: { kind: 'UnsupportedImplementation' },
  ProviderThrew: { kind: 'ProviderThrew', cause: new Error('boom') },
  NonconformantImplementation: { kind: 'NonconformantImplementation', circuitId: 'transfer', check: 'Existence' },
  UnreadableModule: { kind: 'UnreadableModule', circuitId: 'transfer', unreadableTag: 'BagTag' },
  MalformedVerifierKeyHash: { kind: 'MalformedVerifierKeyHash', circuitId: 'transfer', recorded: 'not-a-hash' },
  ImplementationMismatch: { kind: 'ImplementationMismatch', circuitId: 'transfer', expected: VK_A, actual: VK_B },
  ModuleLoadRejected: { kind: 'ModuleLoadRejected', cause: new Error('boom') },
  IncompleteModule: { kind: 'IncompleteModule', missing: ['circuitSignatures', 'expectedVk'] },
};

describe('ModuleResolutionError message', () => {
  test('names the call it could not bind', () => {
    const err = new ModuleResolutionError(CONTEXT, { kind: 'UnsupportedImplementation' });
    expect(err.message).toContain(CALLER);
    expect(err.message).toContain(CALLEE);
    expect(err.message).toContain('transfer');
    expect(err.message).toContain('Token');
  });

  test('every kind produces a non-empty, kind-specific explanation', () => {
    const failures = Object.values(ALL_FAILURES);
    const explanations = new Set<string>();
    for (const failure of failures) {
      const message = new ModuleResolutionError(CONTEXT, failure).message;
      const tail = message.slice(message.indexOf('implementation: '));
      expect(tail.length).toBeGreaterThan('implementation: '.length + 1);
      explanations.add(tail);
    }
    expect(explanations.size).toEqual(failures.length);
  });

  test('a key mismatch reports both digests', () => {
    const err = new ModuleResolutionError(CONTEXT, {
      kind: 'ImplementationMismatch',
      circuitId: 'transfer',
      expected: VK_A,
      actual: VK_B,
    });
    expect(err.message).toContain(VK_A);
    expect(err.message).toContain(VK_B);
  });

  test('a key mismatch with no fingerprint on the module says so', () => {
    const err = new ModuleResolutionError(CONTEXT, {
      kind: 'ImplementationMismatch',
      circuitId: 'transfer',
      actual: VK_B,
    });
    expect(err.message).toContain('no verifier key fingerprint');
    expect(err.message).toContain(VK_B);
  });

  test('an unreadable module names the tag and where it was, not a type mismatch', () => {
    const inResult = new ModuleResolutionError(CONTEXT, {
      kind: 'UnreadableModule',
      circuitId: 'transfer',
      unreadableTag: 'BagTag',
    });
    expect(inResult.message).toContain('BagTag');
    expect(inResult.message).toContain('result type');
    expect(inResult.message).not.toContain('does not implement');

    const inArgument = new ModuleResolutionError(CONTEXT, {
      kind: 'UnreadableModule',
      circuitId: 'transfer',
      unreadableTag: 'BagTag',
      argumentIndex: 1,
    });
    expect(inArgument.message).toContain('argument 1');
  });

  test('a malformed fingerprint is reported as such, not as a mismatch', () => {
    const err = new ModuleResolutionError(CONTEXT, {
      kind: 'MalformedVerifierKeyHash',
      circuitId: 'transfer',
      recorded: 'NOTAHASH',
    });
    expect(err.message).toContain('NOTAHASH');
    expect(err.message).toContain('64 lowercase hex digits');
    expect(err.message).not.toContain('on chain');
  });

  test('an incomplete module names the exports it lacks, not a mismatch', () => {
    const err = new ModuleResolutionError(CONTEXT, {
      kind: 'IncompleteModule',
      missing: ['circuitSignatures', 'expectedVk'],
    });
    expect(err.message).toContain('circuitSignatures, expectedVk');
    expect(err.message).toContain('before dynamic resolution');
    expect(err.message).not.toContain('on chain');
  });

  test('a conformance failure names the rule and, for arguments, the index', () => {
    const err = new ModuleResolutionError(CONTEXT, {
      kind: 'NonconformantImplementation',
      circuitId: 'transfer',
      check: 'ArgumentType',
      argumentIndex: 2,
    });
    expect(err.message).toContain('argument 2');
  });
});

describe('ModuleResolutionError shape', () => {
  test('is a CompactError and carries context and failure', () => {
    const failure: ModuleResolutionFailure = { kind: 'OperationAbsent' };
    const err = new ModuleResolutionError(CONTEXT, failure);
    expect(err).toBeInstanceOf(CompactError);
    expect(err.name).toEqual('ModuleResolutionError');
    expect(err.context).toEqual(CONTEXT);
    expect(err.failure).toEqual(failure);
  });

  test('the failure narrows on kind', () => {
    const err = new ModuleResolutionError(CONTEXT, {
      kind: 'ImplementationMismatch',
      circuitId: 'transfer',
      expected: VK_A,
      actual: VK_B,
    });
    // The throw is what makes this a type guard. Without narrowing, `actual` isn't on the union.
    if (err.failure.kind !== 'ImplementationMismatch') {
      throw new Error(`expected ImplementationMismatch, got ${err.failure.kind}`);
    }
    expect(err.failure.actual).toEqual(VK_B);
    expect(err.failure.circuitId).toEqual('transfer');
  });

  test('the causes that carry one are preserved', () => {
    const cause = new Error('chunk 42 failed');
    const err = new ModuleResolutionError(CONTEXT, { kind: 'ModuleLoadRejected', cause });
    if (err.failure.kind !== 'ModuleLoadRejected') {
      throw new Error(`expected ModuleLoadRejected, got ${err.failure.kind}`);
    }
    expect(err.failure.cause).toBe(cause);
  });
});

describe('ModuleResolutionError.is', () => {
  test('recognizes its own instances', () => {
    expect(ModuleResolutionError.is(new ModuleResolutionError(CONTEXT, { kind: 'OperationAbsent' }))).toEqual(
      true,
    );
  });

  test('does not recognize other errors or non-objects', () => {
    expect(ModuleResolutionError.is(new CompactError('nope'))).toEqual(false);
    expect(ModuleResolutionError.is(new Error('nope'))).toEqual(false);
    expect(ModuleResolutionError.is(null)).toEqual(false);
    expect(ModuleResolutionError.is(undefined)).toEqual(false);
    expect(ModuleResolutionError.is('ModuleResolutionError')).toEqual(false);
    expect(ModuleResolutionError.is({})).toEqual(false);
  });

  test('recognizes an instance from another copy of the package', () => {
    // `instanceof` fails across realms and duplicate installs, so the check is structural.
    expect(ModuleResolutionError.is({ isModuleResolutionError: true })).toEqual(true);
  });
});
