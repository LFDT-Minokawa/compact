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

import * as fs from 'node:fs/promises';
import { NewDependencies } from './with-arborist.mjs';

// TODO: refactor to a more type-safe version
export async function fixPackageJson(packageJsonPath: string, newDependencies: NewDependencies) {
  console.log('Adding new dependencies to package.json');
  // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-return
  const contents: any = await fs.readFile(packageJsonPath, 'utf8').then((contents) => JSON.parse(contents));
  Object.entries(newDependencies).forEach(([name, spec]) => {
    const targetDeps = spec.type === 'dev' ? 'devDependencies' : 'dependencies';
    // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
    if (!contents[targetDeps]) {
      // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
      contents[targetDeps] = {};
    }
    // eslint-disable-next-line @typescript-eslint/no-unsafe-member-access
    contents[targetDeps][name] = spec.tar;
  });
  return await fs.writeFile(packageJsonPath, JSON.stringify(contents, null, 2), 'utf8');
}
