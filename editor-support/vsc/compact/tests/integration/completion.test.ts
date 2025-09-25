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

import * as assert from 'assert';
import * as vscode from 'vscode';
import { COMPLETION_COMMAND, getExpectedKeywords, TEST_FILE_URI } from './commons';
import * as chai from 'chai';

function assertIncludesEveryElement(source: string[], destination: (string | vscode.CompletionItemLabel)[]) {
  for (const element of source) {
    chai.expect(destination).to.include(element, `Element '${element}' from ${source} is not in ${destination}`);
  }
}

suite('Compact Code Completion', () => {
  test('Code completion should give all Compact language keywords', async () => {
    await vscode.window.showTextDocument(TEST_FILE_URI);
    const completionItem = await vscode.commands.executeCommand<vscode.CompletionList>(
      COMPLETION_COMMAND,
      TEST_FILE_URI,
      new vscode.Position(0, 0)
    );
    assertIncludesEveryElement(
      getExpectedKeywords(),
      completionItem.items.map((x) => x.label)
    );
  });

  test('Code completion should give unique Compact language keywords', async () => {
    await vscode.window.showTextDocument(TEST_FILE_URI);
    const completionItem = await vscode.commands.executeCommand<vscode.CompletionList>(
      COMPLETION_COMMAND,
      TEST_FILE_URI,
      new vscode.Position(0, 0)
    );
    const regionCompletions = completionItem?.items?.filter((i) => i.label === 'MerkleTree') ?? [];
    assert.equal(regionCompletions.length, 1);
  });
});
