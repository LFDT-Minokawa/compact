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

import * as sm from 'source-map';
import * as fs from 'fs';
import { expect, test } from 'vitest';

// test setup
const mappingContent = readFileContent(`./resources/neg.js.map`)
const files = readSrcAndTarget(`./resources/neg.compact`, `./resources/neg.js`);

// source-maps library used in tests performs 2 conversions:
// VLQ => numbers
// relative numbers (e.g. negative) => absolute numbers

// print all mappings and corresponding start of code that is matching
// line and colum numbers: [source-line:source-column] => [target-code:target-code]
// and matching start of code:      [source-code] => [target-code]
test('extract all source mappings from xyz.map.js file and formats them', async () => {
  console.log(mappingContent);
  console.log(files.srcLines);
  console.log(" => ");
  console.log(files.targetLines);

  await sm.SourceMapConsumer.with(mappingContent, null, consumer => {
    consumer.eachMapping( (mapping) => {
      const match = getMatchFromFileContent(files, fromSmMapping(mapping));
      printMappings(mapping, match);
    });
  });
});

function printMappings(mapping: sm.MappingItem, match: CodeMatch): void {
  console.log(
    `[${mapping.originalLine}:${mapping.originalColumn}] => [${mapping.generatedLine}:${mapping.generatedColumn}]\n` +
    `[${match.srcCode}] => [${match.targetCode}]`
    );
}

test('extract single code fragment in original compact corresponding to JS code', async () => {
  // [16:21] => [19:15]
  // [arg: Boolean): Boolean {] => [arg) {]
  const mapping: Mapping = { srcLine: 16, srcColumn: 21, targetLine: 19, targetColumn: 15 }

  await sm.SourceMapConsumer.with(mappingContent, null, consumer => {
    const matchedPosition = consumer.originalPositionFor({ line: mapping.targetLine, column: mapping.targetColumn });
    expectOriginalPosition(matchedPosition, mapping);

    getMatchAndVerify(files, mapping, {
      srcCode:    "arg: Boolean): Boolean {",
      targetCode: "arg) {"
    });
  });
});

test('extract 2 code fragments in generated JS from single compact code', async () => {
  // [16:0] => [19:0]
  // [export circuit myNeg(arg: Boolean): Boolean {] => [function myNeg(arg) {]

  // [16:0] => [23:0]
  // [export circuit myNeg(arg: Boolean): Boolean {] => [exports.myNeg = myNeg;]
  await sm.SourceMapConsumer.with(mappingContent, null, consumer => {
    const result = consumer.allGeneratedPositionsFor({ line: 16, column: 0, source: "../neg.compact" });

    // verify 2 lines were generated for this single compact code
    expect(result).toContainEqual({ line: 19, column: 0, lastColumn: 8 });
    expect(result).toContainEqual({ line: 23, column: 0, lastColumn: 21 });

    // extract content corresponding to this matches
    const mapping1: Mapping = { targetLine: 19, targetColumn: 0, srcLine: 16,  srcColumn: 0 }
    getMatchAndVerify(files, mapping1, {
      srcCode:    "export circuit myNeg(arg: Boolean): Boolean {",
      targetCode: "function myNeg(arg) {"
    });

    const mapping2: Mapping = {targetLine: 23, targetColumn: 0, srcLine: 16,  srcColumn: 0 }
    getMatchAndVerify(files, mapping2, {
      srcCode:    "export circuit myNeg(arg: Boolean): Boolean {",
      targetCode: "exports.myNeg = myNeg;"
    });
  });
});

function getMatchAndVerify(files: Files, mapping: Mapping, expectedCodeMatch: CodeMatch) {
  const codeMatch = getMatchFromFileContent(files, mapping);
  expectCodeMatch(codeMatch, expectedCodeMatch);
}

// custom asserts
function expectOriginalPosition(resultPos: sm.NullableMappedPosition, mapping: Mapping): void {
  expect(resultPos.line).toBe(mapping.srcLine);
  expect(resultPos.column).toBe(mapping.srcColumn);
}

function expectCodeMatch(given: CodeMatch, expected: CodeMatch): void {
  expect(given.srcCode).toBe(expected.srcCode);
  expect(given.targetCode).toBe(expected.targetCode);
}

// retrieve file content
function getMatchFromFileContent(files: Files, mapping: Mapping): CodeMatch {
  const srcLine = files.srcLines[mapping.srcLine - 1];
  const targetLine = files.targetLines[mapping.targetLine - 1];
  return {
    srcCode: srcLine.slice(mapping.srcColumn),
    targetCode: targetLine.slice(mapping.targetColumn)
  }
}

// IO utils
function readSrcAndTarget(srcPath: string, targetPath: string): Files {
  const srcLines = readFileLines(srcPath);
  const targetLines = readFileLines(targetPath);
  return {srcLines: srcLines, targetLines: targetLines};
}

function readFileContent(path: string): string {
  const fileBuffer = fs.readFileSync(path);
  return fileBuffer.toString();
}

function readFileLines(path: string): string[] {
  const content = readFileContent(path);
  return content.split("\n");
}

// model & conversion
type Files = {
  srcLines: string[]
  targetLines: string[]
};

type CodeMatch = {
  srcCode: string
  targetCode: string
};

type Mapping = {
  srcLine: number,
  srcColumn: number,
  targetLine: number,
  targetColumn: number
}

function fromSmMapping(mapping: sm.MappingItem): Mapping {
  return {
    srcLine: mapping.originalLine,
    srcColumn: mapping.originalColumn,
    targetLine: mapping.generatedLine,
    targetColumn: mapping.generatedColumn
  };
}
