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
import * as fs from 'fs';
import { Definitions, Pattern } from './helpers/definitions';
import 'jest-expect-message';
import { getTestFileContent, keywordsFilePath, keywordsJson } from './helpers/resources';

function missingKeywords(patterns: Pattern[], patternName: string, exportedKeywords: string) {
  const keywordsArray = exportedKeywords.split('|');
  const pluginKeywords = patterns.find((x) => x.name === patternName)?.match ?? '';
  const missing = keywordsArray.filter((keyword) => {
    const exportedKeywordRegexp = '\\b' + keyword + '\\b';
    return pluginKeywords.match(exportedKeywordRegexp) === null;
  });

  const actualKeywords = pluginKeywords.replace(/\\b\(/g, '').replace(/\)/g, '').split('|');
  const excess = actualKeywords.filter((keyword) => {
    const keywordRegexp = '\\b' + keyword + '\\b';
    return exportedKeywords.match(keywordRegexp) === null;
  });

  return [missing, excess] as const;
}

describe('Semantic highlight definitions should', () => {
  let config: Definitions;
  const languageFilePath = path.join(__dirname, '..', '..', 'syntaxes', 'compact.tmLanguage.json');

  beforeAll(() => {
    config = JSON.parse(fs.readFileSync(languageFilePath, 'utf-8'));
    console.log(`Language file path: ${languageFilePath}`);
    console.log(`Keywords.json path: ${keywordsFilePath}`);
    console.log(`Keywords.json: ${JSON.stringify(keywordsJson)}`);
  });

  test('have correct definitions for booleans', async () => {
    const [missing, excess] = missingKeywords(
      config.repository.keywords.patterns,
      'constant.language.boolean.compact',
      keywordsJson.keywordBoolean
    );
    expect(missing, `Missing keyword in ${languageFilePath}`).toHaveLength(0);
    expect(excess, `Excess keyword in ${languageFilePath}`).toHaveLength(0);
  });

  test('have correct definitions for imports', async () => {
    const [missing, excess] = missingKeywords(
      config.repository.keywords.patterns,
      'keyword.control.import.compact',
      keywordsJson.keywordImport
    );
    expect(missing, `Missing keyword in ${languageFilePath}`).toHaveLength(0);
    expect(excess, `Excess keyword in ${languageFilePath}`).toHaveLength(0);
  });

  test('have correct definitions for controls', async () => {
    const [missing, excess] = missingKeywords(
      config.repository.keywords.patterns,
      'keyword.control.compact',
      keywordsJson.keywordControl
    );
    expect(missing, `Missing keyword in ${languageFilePath}`).toHaveLength(0);
    expect(excess, `Excess keyword in ${languageFilePath}`).toHaveLength(0);
  });

  test('have correct definitions for data types', async () => {
    const [missing, excess] = missingKeywords(
      config.repository.support.patterns,
      'support.class.compact',
      `${keywordsJson.keywordDataTypes}`
    );
    expect(missing, `Missing keyword in ${languageFilePath}`).toHaveLength(0);
    expect(excess, `Excess keyword in ${languageFilePath}`).toHaveLength(0);
  });

  test('have included patterns defined', async () => {
    const expected = ['#keywords', '#strings', '#numbers', '#comments', '#support'];
    const actual = config.patterns.flatMap((x) => x.include);
    expect(actual.indexOf(expected[0])).toBeGreaterThanOrEqual(0);
    expect(actual.indexOf(expected[1])).toBeGreaterThanOrEqual(0);
    expect(actual.indexOf(expected[2])).toBeGreaterThanOrEqual(0);
    expect(actual.indexOf(expected[3])).toBeGreaterThanOrEqual(0);
    expect(actual.indexOf(expected[4])).toBeGreaterThanOrEqual(0);
  });

  test('have correct definitions for quotes', async () => {
    const actual = config.repository.strings;
    expect(actual.begin).toBe('"');
    expect(actual.end).toBe('"');
    expect(actual.name).toBe('string.quoted.double.compact');
    expect(actual.patterns[0].name).toBe('constant.character.escape.compact');
    expect(actual.patterns[0].match).toBe('\\\\.');
  });

  test('have correct definitions for periods', async () => {
    const expected = 6;
    const actual = filterByName(
      config.repository.numbers.patterns.find((x) => x.captures).captures,
      'meta.delimiter.decimal.period.compact'
    );
    expect(actual.length).toBe(expected);
    expect(actual.some((x) => x[0] === '0')).toBeFalsy();
    expect(actual.some((x) => x[0] === '7')).toBeFalsy();
    expect(actual.some((x) => x[0] === '1')).toBeTruthy();
    expect(actual.some((x) => x[0] === '6')).toBeTruthy();
  });

  test('have correct definitions for decimals', async () => {
    const expected =
      '(?x)\n(?<!\\$)(?:\n  (?:\\b[0-9]+(\\.)[0-9]+[eE][+-]?[0-9]+\\b)| # 1.1E+3\n  (?:\\b[0-9]+(\\.)[eE][+-]?[0-9]+\\b)|       # 1.E+3\n  (?:\\B(\\.)[0-9]+[eE][+-]?[0-9]+\\b)|       # .1E+3\n  (?:\\b[0-9]+[eE][+-]?[0-9]+\\b)|            # 1E+3\n  (?:\\b[0-9]+(\\.)[0-9]+\\b)|                # 1.1\n  (?:\\b[0-9]+(\\.)\\B)|                      # 1.\n  (?:\\B(\\.)[0-9]+\\b)|                      # .1\n  (?:\\b[0-9]+\\b(?!\\.))                     # 1\n)(?!\\$)';
    const actual = config.repository.numbers.patterns.filter(
      (x) => x.captures && someByName(x.captures, 'constant.numeric.decimal.compact')
    );
    expect(actual.length).toBe(1);
    const namesOfActual = actual[0].captures;
    expect(someByNumber(namesOfActual, '0')).toBeTruthy();
    expect(actual.some((x) => x.match === expected)).toBeTruthy();
  });

  test('have correct definitions for empty comment blocks', async () => {
    const expected = '(/\\*)(\\*/)';
    const actual = config.repository.comments.patterns.find((x) => x.name === 'comment.block.empty.compact');
    expect(actual.match).toBe(expected);
    expect(Object.keys(actual.captures)).toHaveLength(2);
    expect(actual.captures['1'].name).toBe('punctuation.definition.comment.begin.compact');
    expect(actual.captures['2'].name).toBe('punctuation.definition.comment.end.compact');
  });

  test('have correct definitions for comment blocks', async () => {
    const expectedBegin = '/\\*';
    const expectedEnd = '\\*/';
    const actual = config.repository.comments.patterns.find((x) => x.name === 'comment.block.compact');
    expect(actual.begin).toBe(expectedBegin);
    expect(actual.end).toBe(expectedEnd);
    const beginCapture = findByName(actual.beginCaptures, 'punctuation.definition.comment.begin.compact');
    expect(beginCapture).toBeTruthy();
    const endCapture = someByName(actual.endCaptures, 'punctuation.definition.comment.end.compact');
    expect(endCapture).toBeTruthy();
  });

  test('have correct definitions for comment blocks', async () => {
    const expectedBegin = '//';
    const expectedEnd = '$';
    const actual = config.repository.comments.patterns.find((x) => x.name === 'comment.line.double-slash.compact');
    expect(actual.begin).toBe(expectedBegin);
    expect(actual.end).toBe(expectedEnd);
    const beginCapture = actual.beginCaptures;
    expect(beginCapture).toBeTruthy();
  });

  test('highlight keywords in the editor', async () => {
    const sections = [
      'constant.language.boolean.compact',
      'keyword.control.import.compact',
      'keyword.control.compact',
      'support.class.compact',
    ];
    const testLib = getTestFileContent();
    const notMatched = new Array<string>();
    const notPresent = new Array<string>();
    for (const section of sections) {
      const sectionInDefinitions =
        config.repository.keywords.patterns.find((x) => x.name === section) ??
        config.repository.support.patterns.find((x) => x.name === section);
      if (!sectionInDefinitions) {
        notPresent.push(section);
        continue;
      }
      const regexp = sectionInDefinitions.match!;
      if (testLib.match(regexp) === null) {
        notMatched.push(section);
      }
    }
    expect(notMatched.length, 'Sections with no matches: ' + notMatched.join(', ')).toBe(0);
    expect(notPresent.length, 'Sections not present in definitions: ' + notPresent.join(', ')).toBe(0);
  });

  function findByName(dict: Record<string, { name: string }>, name: string) {
    return Object.values(dict).find((el) => el.name === name);
  }

  function filterByName(dict: Record<string, { name: string }>, name: string) {
    const out = new Array<[string, string]>();
    for (const o of Object.keys(dict)) {
      if (dict[o].name === name) {
        out.push([o, name]);
      }
    }
    return out;
  }

  function someByName(dict: Record<string, { name: string }>, name: string): boolean {
    return Object.values(dict).some((el) => el.name === name);
  }

  function someByNumber(dict: Record<string, { name: string }>, number: string): boolean {
    return Object.keys(dict).some((el) => el === number);
  }
});
