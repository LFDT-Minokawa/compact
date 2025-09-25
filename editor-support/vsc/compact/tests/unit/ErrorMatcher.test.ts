// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
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

describe('problemMatchers regexps should', () => {
  const re = /^Exception: (.*?) line (\d+), char (\d+): (.*)$/;
  const reInternal = /^(Exception in (.*?): \(internal error\) (.*?))$/;
  const reNotFound = /^((.*?) command not found: (.*?))$/;

  test('catch command not found', async () => {
    const errMsg = 'zsh:1: command not found: compactc';

    const expectedParts = ['zsh:1: command not found: compactc'];
    assertProblemMatcherSplitsInto(errMsg, expectedParts, reNotFound);
  });

  test('catch internal errors', async () => {
    const errMsg = 'Exception in datum-type: (internal error) unexpected datum #vu8(108 97 114 101 115 58 ...)';

    const expectedParts = [
      'Exception in datum-type: (internal error) unexpected datum #vu8(108 97 114 101 115 58 ...)',
    ];
    assertProblemMatcherSplitsInto(errMsg, expectedParts, reInternal);
  });

  test('mismatch between actual number of type parameters', async () => {
    const errMsg =
      'Exception: /Users/johndoe/compactc/examples/errors/typeParams.compact line 10, char 10: mismatch between actual number of type parameters 0 for none and declared number 1 at /nix/store/agxizvlvhhbmxhyf61gwihqqhpmszn1h-compactc/lib/std.compact line 10, char 3';
    const expectedParts = [
      'Exception: /Users/johndoe/compactc/examples/errors/typeParams.compact line 10, char 10: mismatch between actual number of type parameters 0 for none and declared number 1 at /nix/store/agxizvlvhhbmxhyf61gwihqqhpmszn1h-compactc/lib/std.compact line 10, char 3',
      '/Users/johndoe/compactc/examples/errors/typeParams.compact',
      '10',
      '10',
      'mismatch between actual number of type parameters 0 for none and declared number 1 at /nix/store/agxizvlvhhbmxhyf61gwihqqhpmszn1h-compactc/lib/std.compact line 10, char 3',
    ];
    assertProblemMatcherSplitsInto(errMsg, expectedParts);
  });

  test('match unbound identifier', async () => {
    const errMsg =
      'Exception: /Users/johndoe/compactc/test-center/compact/test.compact line 17, char 24: unbound identifier Booleann';
    const expectedParts = [
      'Exception: /Users/johndoe/compactc/test-center/compact/test.compact line 17, char 24: unbound identifier Booleann',
      '/Users/johndoe/compactc/test-center/compact/test.compact',
      '17',
      '24',
      'unbound identifier Booleann',
    ];
    assertProblemMatcherSplitsInto(errMsg, expectedParts);
  });

  test('match incompatible arguments for call', async () => {
    const errMsg =
      'Exception: ./examples/multiSource.compact line 12, char 10: incompatible arguments for call: supplied argument types: (Field, Field) declared argument types for visible functions: ./examples/multiSource.compact line 3, char 1: (Boolean, Field)';
    const expectedParts = [
      'Exception: ./examples/multiSource.compact line 12, char 10: incompatible arguments for call: supplied argument types: (Field, Field) declared argument types for visible functions: ./examples/multiSource.compact line 3, char 1: (Boolean, Field)',
      './examples/multiSource.compact',
      '12',
      '10',
      'incompatible arguments for call: supplied argument types: (Field, Field) declared argument types for visible functions: ./examples/multiSource.compact line 3, char 1: (Boolean, Field)',
    ];
    assertProblemMatcherSplitsInto(errMsg, expectedParts);
  });

  test('match call site ambiguity (multiple compatible functions)', async () => {
    const errMsg =
      'Exception: ./examples/errors/multiSource2.compact line 5, char 47: call site ambiguity (multiple compatible functions) supplied argument types: () compatible functions: ./examples/errors/multiSource2.compact line 1, char 12 ./examples/errors/multiSource2.compact line 3, char 1 ./examples/errors/multiSource2.compact line 4, char 1';
    const expectedParts = [
      'Exception: ./examples/errors/multiSource2.compact line 5, char 47: call site ambiguity (multiple compatible functions) supplied argument types: () compatible functions: ./examples/errors/multiSource2.compact line 1, char 12 ./examples/errors/multiSource2.compact line 3, char 1 ./examples/errors/multiSource2.compact line 4, char 1',
      './examples/errors/multiSource2.compact',
      '5',
      '47',
      'call site ambiguity (multiple compatible functions) supplied argument types: () compatible functions: ./examples/errors/multiSource2.compact line 1, char 12 ./examples/errors/multiSource2.compact line 3, char 1 ./examples/errors/multiSource2.compact line 4, char 1',
    ];
    assertProblemMatcherSplitsInto(errMsg, expectedParts);
  });

  test('match call site ambiguity (multiple compatible functions)', async () => {
    const errMsg =
      'Exception: ./examples/errors/multiSource4.compact line 2, char 10: incompatible arguments for call declared argument types: (Field, Field, Field) received: (Field, Field)';
    const expectedParts = [
      'Exception: ./examples/errors/multiSource4.compact line 2, char 10: incompatible arguments for call declared argument types: (Field, Field, Field) received: (Field, Field)',
      './examples/errors/multiSource4.compact',
      '2',
      '10',
      'incompatible arguments for call declared argument types: (Field, Field, Field) received: (Field, Field)',
    ];
    assertProblemMatcherSplitsInto(errMsg, expectedParts);
  });

  function assertProblemMatcherSplitsInto(errMsg: string, expectedParts: Array<string>, reg: RegExp = re): void {
    // when
    const actualParts = errMsg.match(reg);

    // then
    expect(actualParts).not.toBeNull();
    expectedParts.forEach((val, indx, arr) => {
      expect(actualParts.includes(val)).toBe(true);
    });
  }
});
