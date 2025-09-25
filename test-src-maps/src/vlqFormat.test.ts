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

import { describe, expect, test } from 'vitest';
import * as vlq from "vlq";
import * as decoded from '../resources/neg.js.map.decoded.json';
import * as encoded from '../resources/neg.js.map.fmt.json';

describe('VLQ converter', () => {

   // convenient tests to check concrete source mappings from file
   test('should decode VLQ from file', () => {
      const result = encoded.mappings.map(all => all.map(everyLine => vlq.decode(everyLine)));
      const expected = decoded.mappings;
      expect(result).toEqual(expected);
   });

   test('should encode VLQ from file', () => {
      const result = decoded.mappings.map(all => all.map(everyLine => vlq.encode(everyLine)));
      const expected = encoded.mappings;
      expect(result).toEqual(expected);
   });

   // convenient way to convert numerical values with sourceMappings
   // to source mappings
   // useful when manually crafting source mapps
   test('should encode VLQ', () => {
      const mappings = [
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [ [] ],
         [
           [ 0, 0, 1, -50 ],
           [ 9, 0, 0, 16 ],
           [ 5, 0, 0, 5 ],
           [ 1, 0, 0, 1 ],
           [ 3, 0, 0, 12 ]
         ],
         [
           [ 4, 0, 2, -32 ],
           [ 4, 0, 0, 4 ],
           [ 1, 0, 0, 1 ],
           [ 1, 0, 0, 1 ],
           [ 7, 0, 0, 6 ],
           [ 1, 0, 0, 1 ],
           [ 3, 0, 0, 3 ],
           [ 1, 0, 0, 1 ],
           [ 5, 0, 0, 5 ],
           [ 9, 0, 0, 9 ],
           [ 1, 0, 0, 1 ]
         ],
         [
           [ 8, 0, 1, -29 ], [ 8, 0, 0, 8 ],
           [ 1, 0, 0, 1 ],   [ 10, 0, 0, 10 ],
           [ 1, 0, 0, 1 ],   [ 7, 0, 0, 7 ],
           [ 2, 0, 0, 2 ],   [ 12, 0, 0, 12 ],
           [ 2, 0, 0, 2 ],   [ 44, 0, 0, 44 ],
           [ 2, 0, 0, 2 ],   [ 9, 0, 0, 9 ],
           [ 2, 0, 0, 2 ],   [ 3, 0, 0, 3 ],
           [ 1, 0, 0, 1 ],   [ 1, 0, 0, 1 ]
         ],
         [
           [ 4, 0, 1, -108 ],
           [ 7, 0, 0, 7 ],
           [ 8, 0, 0, 8 ],
           [ 1, 0, 0, 1 ],
           [ 3, 0, 0, 3 ],
           [ 1, 0, 0, 1 ],
           [ 1, 0, 0, 1 ]
         ],
         [ [ 0, 0, 1, -23 ], [ 1, 0, 0, 1 ] ],
         [ [ 0, 0, -5, -1 ], [ 22, 0, 5, 1 ] ],
         [
           [ 0, 0, 1, -1 ],
           [ 9, 0, 0, 15 ],
           [ 8, 0, 0, 5 ],
           [ 1, 0, 0, 1 ],
           [ 3, 0, 0, 12 ]
         ],
         [
           [ 4, 0, 2, -31 ],
           [ 6, 0, 0, 6 ],
           [ 3, 0, 0, 3 ],
           [ 3, 0, 0, 12 ],
           [ 1, 0, 0, 1 ],
           [ 3, 0, 0, 3 ],
           [ 1, 0, 0, 1 ]
         ],
         [ [ 4, 0, 1, -26 ], [ 7, 0, 0, 7 ], [ 3, 0, 0, 3 ], [ 1, 0, 0, 1 ] ],
         [ [ 0, 0, 1, -13 ], [ 1, 0, 0, 1 ] ]
       ]

      const expected = [
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ '' ],
         [ 'AAClD', 'SAAgB', 'KAAK', 'CAAC', 'GAAY' ],
         [
           'IAEhC', 'IAAI',
           'CAAC',  'CAAC',
           'OAAM',  'CAAC',
           'GAAG',  'CAAC',
           'KAAK',  'SAAS',
           'CAAC'
         ],
         [
           'QAC7B',  'QAAQ', 'CAAC',
           'UAAU',   'CAAC', 'OAAO',
           'EAAE',   'YAAY', 'EAAE',
           '4CAA4C', 'EAAE', 'SAAS',
           'EAAE',   'GAAG', 'CAAC',
           'CAAC'
         ],
         [
           'IAC5G', 'OAAO',
           'QAAQ',  'CAAC',
           'GAAG',  'CAAC',
           'CAAC'
         ],
         [ 'AACvB', 'CAAC' ],
         [ 'AALD', 'sBAKC' ],
         [ 'AACD', 'SAAe', 'QAAK', 'CAAC', 'GAAY' ],
         [
           'IAE/B', 'MAAM',
           'GAAG',  'GAAY',
           'CAAC',  'GAAG',
           'CAAC'
         ],
         [ 'IAC1B', 'OAAO', 'GAAG', 'CAAC' ],
         [ 'AACb', 'CAAC' ]
       ];

      const result = mappings.map(all => all.map(everyLine => vlq.encode(everyLine)));
      expect(result).toEqual(expected);
   });
});
