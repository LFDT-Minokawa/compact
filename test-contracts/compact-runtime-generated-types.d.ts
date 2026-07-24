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

import '@midnight-ntwrk/compact-runtime';

declare module '@midnight-ntwrk/compact-runtime' {
    export interface CircuitContext<PrivateState = any> {
        currentPrivateState: PrivateState;
        currentZswapLocalState: any;
        currentQueryContext: any;
        costModel: any;
        gasLimit?: any;
    }

    export interface CircuitResults<PrivateState = any, Result = any> {
        result: Result;
        context: CircuitContext<PrivateState>;
        proofData: any;
        gasCost: any;
    }

    export interface ConstructorContext<PrivateState = any> {
        initialPrivateState: PrivateState;
        initialZswapLocalState: any;
    }

    export interface ConstructorResult<PrivateState = any> {
        currentContractState: any;
        currentPrivateState: PrivateState;
        currentZswapLocalState: any;
    }

    export type ChargedState = any;
    export type StateValue = any;
}
