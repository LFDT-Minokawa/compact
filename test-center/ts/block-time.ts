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

test('Check block time functions', () => {
  const [c, context] = startContract(contractCode, {}, 0);
  context.currentQueryContext.block = {
    ...context.currentQueryContext.block,
    secondsSinceEpoch: 1n,
    secondsSinceEpochErr: 0
  };
  expect(c.circuits.testBlockTimeGt(context, 5n).result).toEqual(false);
  expect(c.circuits.testBlockTimeGt(context, 0n).result).toEqual(true);
  expect(c.circuits.testBlockTimeGt(context, 1n).result).toEqual(false);

  expect(c.circuits.testBlockTimeGte(context, 5n).result).toEqual(false);
  expect(c.circuits.testBlockTimeGte(context, 0n).result).toEqual(true);
  expect(c.circuits.testBlockTimeGte(context, 1n).result).toEqual(true);

  expect(c.circuits.testBlockTimeLt(context, 5n).result).toEqual(true);
  expect(c.circuits.testBlockTimeLt(context, 0n).result).toEqual(false);
  expect(c.circuits.testBlockTimeLt(context, 1n).result).toEqual(false);

  expect(c.circuits.testBlockTimeLte(context, 5n).result).toEqual(true);
  expect(c.circuits.testBlockTimeLte(context, 0n).result).toEqual(false);
  expect(c.circuits.testBlockTimeLte(context, 1n).result).toEqual(true);
})

