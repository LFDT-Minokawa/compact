// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

// vitest.config.ts loads this for every test-center test, so the runtime's inner-proof check is a
// no-op suite-wide: the staged JavaScript tests use placeholder proofs. Real proofs are checked
// only by Midnight's separate end-to-end test repository for now; a test here with real proofs
// must undo this mock, e.g. with vi.unmock. vitest.config.ts routes every import of zkir-v3,
// including compact-runtime's, to the one module mocked here.

import { vi } from 'vitest';

vi.mock('@midnightntwrk/zkir-v3', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@midnightntwrk/zkir-v3')>()),
  checkInnerProof: () => {},
}));
