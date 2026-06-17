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

test('Contract can invoke self', async () => {
    const [c, context0] = await startContract(contractCode, {}, 0);
    const selfAddress = {
        bytes: runtime.encodeContractAddress(context0.callContext.contractAddress),
    }
    const context1 = (await c.circuits.set(context0, selfAddress)).context;
    expect((await c.circuits.foo(context1, 1n)).result).toEqual(2n);
})

// TODO: Add another test that interleaves modification to a ledger state with a call to self. Should result in a consistent
//       final ledger state.
