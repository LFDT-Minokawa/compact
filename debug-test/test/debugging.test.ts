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

import * as ts from '@vscode/debugadapter-testsupport';
import { DebugProtocol } from '@vscode/debugprotocol';
import { beforeAll, afterAll, test } from 'vitest';

let dc: ts.DebugClient;

const testOptions = { timeout: 180_000 };

function log(e: DebugProtocol.OutputEvent): void {
  console.log(e);
}

beforeAll(async () => {
  dc = new ts.DebugClient('node', '../vscode-js-debug/out/src/extension.js', 'node-terminal');
  dc.addListener('output', log);
  await dc.start();
}, testOptions.timeout);

afterAll(async () => {
  console.log('stopping...');
  dc.removeAllListeners();
  await dc.stop();
}, testOptions.timeout);

// skipped because I was not able to automate it for now
// I can't pass 'initialization' phase
// keeping for future reference, as of now
test.skip('should run program to the end', async () => {
  await dc.configurationSequence();
  await dc.launch({ program: './out/test.js', stopOnEntry: true });
  await dc.assertStoppedLocation('entry', { line: 1 });
});
