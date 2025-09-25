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

import 'jest-expect-message';
import { getTestFileContent, getTestFilePath, keywordsJson } from './helpers/resources';

describe('Compiler keywords matches definitions should', () => {
  let testlib: string;

  beforeAll(() => {
    testlib = getTestFileContent();
  });

  test('have correct definitions for booleans', async () => {
    const keywords = keywordsJson.keywordBoolean.split('|');
    const missing = keywords.filter((x: string) => !anyFileHas(x));
    expect(missing.length === 0, `[${missing.join(', ')}] not found in file: ${getTestFilePath()}`).toBeTruthy();
  });

  test('have correct definitions for controls', async () => {
    const keywords = keywordsJson.keywordControl.split('|');
    const missing = keywords.filter((x: string) => !anyFileHas(x));
    console.log(`Missing=${missing}`);
    expect(missing.length === 0, `[${missing.join(', ')}] not found in file: ${getTestFilePath()}`).toBeTruthy();
  });

  test('have correct definitions for data types', async () => {
    const keywords = keywordsJson.keywordDataTypes.split('|');
    const missing = keywords.filter((x: string) => !anyFileHas(x));
    expect(missing.length === 0, `[${missing.join(', ')}] not found in file: ${getTestFilePath()}`).toBeTruthy();
  });

  test('have correct definitions for imports', async () => {
    const keywords = keywordsJson.keywordImport.split('|');
    const missing = keywords.filter((x: string) => !anyFileHas(x));
    expect(missing.length === 0, `[${missing.join(', ')}] not found in file: ${getTestFilePath()}`).toBeTruthy();
  });

  function anyFileHas(keyword: string): boolean {
    const isPresentInTestLib = testlib.match('\\b' + keyword + '\\b');
    return isPresentInTestLib !== null;
  }
});
