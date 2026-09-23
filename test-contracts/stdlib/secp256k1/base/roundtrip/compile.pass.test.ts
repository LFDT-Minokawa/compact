// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

// `Secp256k1Base` is only bound in the standard library when the v3 IR
// feature is enabled, so this fixture compiles with `--feature-zkir-v3`.
export default defineCompileTest(import.meta.url, {
    compilerArgs: ['--feature-zkir-v3'],
});
