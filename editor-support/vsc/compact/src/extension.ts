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

// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
import * as vscode from 'vscode';

// import manager
import CompactcTemplatesPlugin from './compactcTemplatesPlugin';

// import commands
import * as CreateCompactcProjectFromTemplateCommand from './createFromTemplateCommand';
// import SaveProjectAsTemplateCommand = require('./commands/saveProjectAsTemplateCommand');
// import DeleteTemplateCommand = require('./commands/deleteTemplateCommand');
// import CreateProjectFromTemplateCommand = require('./commands/createProjectFromTemplateCommand');

/**
 * Main entry point for extension
 * @export
 * @param {vscode.ExtensionContext} context
 */
export function activate(context: vscode.ExtensionContext) {
  let compactcTemplatesPlugin = new CompactcTemplatesPlugin(context);

  // register commands

  // create project from template
  let createCompactcProjectFromTemplate = vscode.commands.registerCommand(
    'extension.createCompactcProjectFromTemplate',
    CreateCompactcProjectFromTemplateCommand.run.bind(undefined, compactcTemplatesPlugin)
  );

  context.subscriptions.push(createCompactcProjectFromTemplate);
}

// this method is called when your extension is deactivated
export function deactivate() {}
