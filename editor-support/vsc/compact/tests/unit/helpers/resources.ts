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

import fs from 'fs';
import path from 'path';
export const keywordsFilePath = '../../resources/keywords.json';

// eslint-disable-next-line @typescript-eslint/no-var-requires
export const keywordsJson = require(keywordsFilePath);
console.log(`Keywords.json path: ${path.resolve(keywordsFilePath)}`);

export const DEFAULT_TEST_FILE_PATH = path.join(__dirname, '..', '..', '..', 'test-center', 'compact', 'test.compact');

export function getTestFilePath(): string {
  const testFilePath = process.env.TEST_COMPACT_PATH;
  if (testFilePath !== undefined) {
    return testFilePath;
  }
  return DEFAULT_TEST_FILE_PATH;
}

export function getTestFileContent(): string {
  const testFilePath = getTestFilePath();
  console.log(`Test file path: ${testFilePath}`);
  return fs.readFileSync(testFilePath, 'utf-8');
}
