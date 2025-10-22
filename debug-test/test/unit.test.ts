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

import { beforeAll, afterAll, beforeEach, afterEach, test, expect } from 'vitest';
import { runSmartContract } from '../src/contract.js';

beforeAll(() => {
  console.log('Add something to beforeAll');
});

afterAll(() => {
  runSmartContract(false);
});

beforeEach(() => {
  console.log('Running test');
});

afterEach(() => {
  console.log('Finished!');
});

test('example jest debugging', async () => {
  const result = runSmartContract(true);
  expect(result.nested.is_some).toBe(true);
  expect(result.priv.is_some).toBe(false);
  expect(result.stdLib.is_some === true).toBeTruthy();
});
