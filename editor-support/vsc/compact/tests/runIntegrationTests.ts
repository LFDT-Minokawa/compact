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

import * as path from 'path';
import { runTests } from '@vscode/test-electron';
import * as os from 'node:os';

async function runTestsOnVSCode() {
  try {
    const extensionDevelopmentPath = path.resolve(__dirname, '../../');
    const extensionTestsPath = path.resolve(__dirname, './integration/');

    console.log('extensionDevelopmentPath:' + extensionDevelopmentPath);
    console.log('extensionTestsPath:' + extensionTestsPath);

    //with extensions
    await runTests({
      extensionDevelopmentPath,
      extensionTestsPath,
      launchArgs: ['--user-data-dir', `${os.tmpdir()}`],
    });

    //without extensions
    await runTests({
      extensionDevelopmentPath,
      extensionTestsPath,
      launchArgs: ['--disable-extensions', '--user-data-dir', `${os.tmpdir()}`],
    });

    //insiders
    await runTests({
      version: 'insiders',
      extensionDevelopmentPath,
      extensionTestsPath,
      launchArgs: ['--disable-extensions', '--user-data-dir', `${os.tmpdir()}`],
    });
  } catch (err) {
    console.error(err);
    console.error('Failed to run tests');
    process.exit(1);
  }
}

runTestsOnVSCode();
