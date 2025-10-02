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

test('Check gas tracking works as expected', () => {
  const [c, context] = startContract(contractCode, {}, 0);
  const gasCost = c.circuits.testGasCost(context).gasCost;
  expect(gasCost).toBeDefined();
  expect(gasCost.computeTime > 0n).toBe(true);
  expect(gasCost.readTime > 0n).toBe(true);
  expect(gasCost.bytesWritten > 0n).toBe(true);
  expect(gasCost.bytesDeleted > 0n).toBe(true);
})

test('Gas bound works as expected', () => {
  const [c, context] = startContract(contractCode, {}, 0);
  context.gasLimit = runtime.emptyRunningCost();
  expect(() => c.circuits.testGasCost(context)).toThrowError();
})

