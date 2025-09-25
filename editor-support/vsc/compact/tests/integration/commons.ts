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

import vscode from 'vscode';
import path from 'path';
import fs from 'fs';

export const EXTENSION_ID = 'midnightnetwork.compact';
export const COMPLETION_COMMAND = 'vscode.executeCompletionItemProvider';
export const EXT = 'extension.createCompactcProjectFromTemplate';

export const TEST_FILE_URI = vscode.Uri.file(getTestFilePath());

export function getTestFilePath(): string {
  const testFilePath = process.env.TEST_COMPACT_PATH;
  if (testFilePath !== undefined) {
    console.log('Env defined file used:', testFilePath);
    return testFilePath;
  }
  const DEFAULT_TEST_FILE_PATH = path.join(
    getExtensionPath(),
    '..',
    '..',
    '..',
    'test-center',
    'compact',
    'test.compact'
  );
  console.log('Default file used:', DEFAULT_TEST_FILE_PATH);
  return DEFAULT_TEST_FILE_PATH;
}

export function getExtensionPath(): string {
  const extension = vscode.extensions.getExtension(EXTENSION_ID);
  if (!extension) {
    throw Error('Cannot find Extension');
  }
  return extension.extensionPath;
}

export async function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function getExpectedKeywords() {
  const jsonData = fs.readFileSync(path.join(__dirname, '../resources/keywords.json'), 'utf8');
  const keywordsJson: ExpectedKeywords = JSON.parse(jsonData);
  const expectedItems: string[] = [
    ...keywordsJson.keywordBoolean.split('|'),
    ...keywordsJson.keywordControl.split('|'),
    ...keywordsJson.keywordImport.split('|'),
    ...keywordsJson.keywordDataTypes.split('|'),
  ];
  return expectedItems;
}

export type ExpectedKeywords = {
  keywordBoolean: string;
  keywordImport: string;
  keywordControl: string;
  keywordDataTypes: string;
};
