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
import path from 'node:path';

// Reify does change paths to relative, so we need to adjust them back to absolute ones
export async function fixRelatives(lockFilePath: string) {
  console.log(`Adjusting relative paths in ${lockFilePath} to be absolute`);
  const contents = await fs
    .readFile(lockFilePath, 'utf8')
    .then((contents) => JSON.parse(contents) as { packages: Record<string, unknown> });
  Object.values(contents.packages)
    .filter((pkg: unknown): pkg is { resolved: string } => {
      return !!pkg && typeof pkg === 'object' && 'resolved' in pkg && typeof pkg.resolved === 'string';
    })
    .map((pkg) => {
      const resolvedURL = new URL(pkg.resolved);
      return [pkg, resolvedURL] as const;
    })
    .filter(([pkg, url]) => url.protocol === 'file:')
    .map(([pkg, url]) => {
      const pkgPath = url.pathname;
      const madeAbsolute = path.resolve(lockFilePath, pkgPath);
      return [pkg, `file://${madeAbsolute}`] as const;
    })
    .forEach(([pkg, absolutePath]) => {
      pkg.resolved = absolutePath;
    });

  const newContents = JSON.stringify(contents, null, 2);
  return await fs.writeFile(lockFilePath, newContents, 'utf8');
}
