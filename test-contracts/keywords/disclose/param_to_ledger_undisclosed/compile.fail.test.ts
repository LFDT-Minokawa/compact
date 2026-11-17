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

import { defineCompileTest } from '@test/compact-test';

export default defineCompileTest(import.meta.url, {
    expectedError:
        /line 20 char 5:\s+potential witness-value disclosure must be declared but is not:[\s\S]*the value of parameter a[\s\S]*ledger operation might disclose the witness value/,
});
