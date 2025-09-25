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

'use strict';

import * as vscode from 'vscode';

import CompactcTemplatesPlugin from './compactcTemplatesPlugin';

/**
 * Main command to create a new project from a template.
 * This command can be invoked by the Command Palette or in a folder context menu on the explorer view.
 * @export
 * @param {CompactcTemplatesPlugin} compactcPlugin
 * @param {*} args
 */
export async function run(compactcPlugin: CompactcTemplatesPlugin, args: any) {
  // get workspace folder
  let workspace = await compactcPlugin.selectWorkspace(args);
  if (!workspace) {
    vscode.window.showErrorMessage('No workspace selected');
    return;
  }

  // create project
  compactcPlugin.createFromTemplate(workspace).then(
    (template: string | undefined) => {
      if (template) {
        vscode.window.showInformationMessage("Created project from template '" + template + "'");
      }
    },
    (reason: any) => {
      vscode.window.showErrorMessage('Failed to create project from template: ' + reason);
    }
  );
}
