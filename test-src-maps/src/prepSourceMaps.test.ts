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

import { expect, test } from 'vitest';
import * as encoded from '../resources/neg.js.map.fmt.json';
import * as fs from 'fs';

// xyz.map.js file is a bit inconvenient to work with
// it is a JSON containing sourcemaps
test('extract source mappings from xyz.map.js file and formats them', () => {
  const result = readSourceMaps(`./resources/neg.js.map`);
  const expected = encoded.mappings;
  expect(result).toEqual(expected);
});

function readSourceMaps(filePath : string): string [] [] {
  const rawdata = fs.readFileSync(filePath);
  const sourceMapContent = JSON.parse(rawdata.toString());
  const mappings = sourceMapContent.mappings as string;

  return mappings.split(';').map(line => line.split(','));
}
