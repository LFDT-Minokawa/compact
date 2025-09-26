#!/usr/bin/env node

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

import { either } from 'fp-ts';
import fs from 'node:fs/promises';
import path from 'node:path';
import yargs from 'yargs';
import { fixPackageJson } from './fixPackageJson.mjs';
import { fixRelatives } from './fixRelatives.mjs';
import { arboristDryInstall, Deps, DepsCodec } from './with-arborist.mjs';
import { preparePublishPackageJson } from './preparePublishPackageJson.mjs';

const args = await yargs(process.argv)
  .option('to', {
    type: 'string',
    default: process.cwd(),
    description: 'Where to install dependency, defaults to current working directory',
  })
  .option('deps', {
    type: 'string',
    demandOption: true,
    description: 'path to json containing an array of dependencies, where each dep is dir and tar path',
  })
  .parse();

try {
  const deps: Deps = await fs
    .readFile(args.deps, 'utf-8')
    .then((str) => JSON.parse(str) as unknown)
    .then((parsed) => DepsCodec.decode(parsed))
    .then(
      either.foldW(
        (err): never => {
          console.error(err);
          throw err;
        },
        (decoded: Deps) => decoded,
      ),
    );
  const { tree, newDependencies } = await arboristDryInstall(
    {
      dir: args.to,
    },
    deps,
  );
  await tree.reify({
    save: true,
    prune: false,
  });
  await fixRelatives(path.resolve(args.to, 'package-lock.json'));
  await fixPackageJson(path.resolve(args.to, 'package.json'), newDependencies);
  await preparePublishPackageJson(path.resolve(args.to, 'package.json'), path.resolve(args.to, 'package-publish.json'), newDependencies);
} catch (e) {
  console.error(e);
  process.exit(1);
}
