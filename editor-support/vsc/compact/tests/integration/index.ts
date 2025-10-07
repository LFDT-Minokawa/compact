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
import Mocha from 'mocha';
import { globSync } from 'glob';

export function run(testsRoot: string, cb: (error: unknown, failures?: number) => void): void {
  const mocha = new Mocha({
    ui: 'tdd',
    timeout: 180_000,
  });

  const files = globSync('**/**.test.js', { cwd: testsRoot });

  console.log('Tests root:', testsRoot);
  console.log('Test files:', files);

  files.forEach((f) => mocha.addFile(path.resolve(testsRoot, f)));

  try {
    mocha.run((failures) => {
      cb(null, failures);
    });
  } catch (err) {
    console.error(err);
    cb(err);
  }
}
