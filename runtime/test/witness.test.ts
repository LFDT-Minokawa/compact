// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import { describe, expect, test } from 'vitest';
import * as runtime from '@midnight-ntwrk/compact-runtime';

const witnessSetObject = {
  A: {
    1(context: runtime.WitnessContext<unknown, number>) {
      return [context.privateState + 1, 'A1'] as const;
    },
    2(context: runtime.WitnessContext<unknown, number>) {
      return [context.privateState + 2, 'A2'] as const;
    },
  },
  B: {
    1(context: runtime.WitnessContext<unknown, number>) {
      return [context.privateState - 1, 'B1'] as const;
    },
    2(context: runtime.WitnessContext<unknown, number>) {
      return [context.privateState - 2, 'B2'] as const;
    },
  },
};

describe('Runtime witness functions', () => {
  test("'readWitness' should return the correct witness", () => {
    const witnessContext = runtime.createWitnessContext(null, null, '');
    expect(runtime.readWitness(witnessSetObject, 'A', '1')(witnessContext)[1]).toEqual('A1');
    expect(runtime.readWitness(witnessSetObject, 'A', '2')(witnessContext)[1]).toEqual('A2');
    expect(runtime.readWitness(witnessSetObject, 'B', '1')(witnessContext)[1]).toEqual('B1');
    expect(runtime.readWitness(witnessSetObject, 'B', '2')(witnessContext)[1]).toEqual('B2');
  });
  test("'callWitness' should return the correct result", () => {
    const circuitContext = {
      currentPrivateState: 0,
    } as runtime.CircuitContext<number>;
    runtime.callWitness(circuitContext, null, witnessSetObject, 'A', '1');
    expect(circuitContext.currentPrivateState).toEqual(1);
    runtime.callWitness(circuitContext, null, witnessSetObject, 'A', '2');
    expect(circuitContext.currentPrivateState).toEqual(3);
    runtime.callWitness(circuitContext, null, witnessSetObject, 'B', '1');
    expect(circuitContext.currentPrivateState).toEqual(2);
    runtime.callWitness(circuitContext, null, witnessSetObject, 'B', '2');
    expect(circuitContext.currentPrivateState).toEqual(0);
  });
});
