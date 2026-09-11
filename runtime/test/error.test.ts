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

import { describe, expect, test } from 'vitest';
import { CompactError, ModuleResolutionError } from '../src/index.js';

const CONTEXT = {
  calleeAddress: '00'.repeat(32),
  calleeCircuitId: 'transfer',
  interfaceName: 'Token',
  callerAddress: '11'.repeat(32),
};

describe('CompactError.is', () => {
  test('recognizes its own instances', () => {
    expect(CompactError.is(new CompactError('nope'))).toEqual(true);
  });

  test('recognizes a subclass', () => {
    expect(CompactError.is(new ModuleResolutionError(CONTEXT, { kind: 'OperationAbsent' }))).toEqual(true);
  });

  test('recognizes an instance from another copy of the package', () => {
    expect(CompactError.is({ isCompactError: true })).toEqual(true);
  });

  test('does not recognize other errors or non-objects', () => {
    expect(CompactError.is(new Error('nope'))).toEqual(false);
    expect(CompactError.is(new TypeError('nope'))).toEqual(false);
    expect(CompactError.is(null)).toEqual(false);
    expect(CompactError.is(undefined)).toEqual(false);
    expect(CompactError.is('CompactError')).toEqual(false);
    expect(CompactError.is({})).toEqual(false);
    expect(CompactError.is({ isCompactError: 'yes' })).toEqual(false);
  });

  test('narrows to CompactError', () => {
    const thrown: unknown = new CompactError('boom');
    if (!CompactError.is(thrown)) {
      throw new Error('expected a CompactError');
    }
    expect(thrown.message).toEqual('boom');
  });
});
