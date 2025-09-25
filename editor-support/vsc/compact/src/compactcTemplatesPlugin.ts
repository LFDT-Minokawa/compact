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

import { WorkspaceConfiguration } from 'vscode';
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as path from 'path';
import * as child_process from 'child_process';

export default class CompactcTemplatesPlugin {
  /**
   * local copy of workspace configuration to maintain consistency between calls
   */
  econtext: vscode.ExtensionContext;
  outChannel: vscode.OutputChannel;

  constructor(econtext: vscode.ExtensionContext) {
    this.econtext = econtext;
    this.outChannel = vscode.window.createOutputChannel('Compactc');
  }

  public async selectWorkspace(args: any): Promise<string> {
    let workspace: string = '';

    // check arguments
    if (args && args.fsPath) {
      workspace = args.fsPath;
    } else if (vscode.workspace.workspaceFolders) {
      // single or multi-root
      if (vscode.workspace.workspaceFolders.length === 1) {
        workspace = vscode.workspace.workspaceFolders[0].uri.fsPath;
      } else if (vscode.workspace.workspaceFolders.length > 1) {
        // choose workspace
        let ws = await vscode.window.showWorkspaceFolderPick();
        if (ws) {
          workspace = ws.uri.fsPath;
        }
      }
    }
    return workspace;
  }

  /**
   * Populates a workspace folder with the contents of a template
   * @param workspace current workspace folder to populate
   */
  public async createFromTemplate(workspace: string) {
    // choose a template
    let template = await this.chooseTemplate();
    if (!template) {
      return;
    }

    // get template folder
    let templateRoot = this.getTemplatesDir();
    let templateDir = path.join(templateRoot, template);

    if (!fs.existsSync(templateDir) || !fs.lstatSync(templateDir).isDirectory()) {
      vscode.window.showErrorMessage("Template '" + template + "' does not exist.");
      return undefined;
    }

    // update placeholder configuration
    let usePlaceholders = true;

    // such placeholder is chosen not to mess with comments
    let placeholderRegExp = '\\$\\${(\\w+?)}';
    let placeholders: { [placeholder: string]: string | undefined } = {};

    // re-read configuration, merge with current list of placeholders
    let newplaceholders: { [placeholder: string]: string } = {};
    for (let key in newplaceholders) {
      placeholders[key] = newplaceholders[key];
    }

    // recursively copy files, replacing placeholders as necessary
    let copyFunc = async (src: string, dest: string) => {
      // maybe replace placeholders in filename
      if (usePlaceholders) {
        dest = (await this.resolvePlaceholders(dest, placeholderRegExp, placeholders)) as string;
      }

      if (fs.lstatSync(src).isDirectory()) {
        // create directory if doesn't exist
        if (!fs.existsSync(dest)) {
          fs.mkdirSync(dest);
        } else if (!fs.lstatSync(dest).isDirectory()) {
          // fail if file exists
          throw new Error("Failed to create directory '" + dest + "': file with same name exists.");
        }
      } else {
        // ask before overwriting existing file
        while (fs.existsSync(dest)) {
          // if it is not a file, cannot overwrite
          if (!fs.lstatSync(dest).isFile()) {
            let reldest = path.relative(workspace, dest);

            let variableInput = <vscode.InputBoxOptions>{
              prompt: `Cannot overwrite "${reldest}".  Please enter a new filename"`,
              value: reldest,
            };

            // get user's input
            dest = await vscode.window.showInputBox(variableInput).then((value) => {
              if (!value) {
                return dest;
              }
              return value;
            });

            // if not absolute path, make workspace-relative
            if (!path.isAbsolute(dest)) {
              dest = path.join(workspace, dest);
            }
          } else {
            // ask if user wants to replace, otherwise prompt for new filename
            let reldest = path.relative(workspace, dest);
            let choice = await vscode.window.showQuickPick(['Overwrite', 'Rename', 'Skip', 'Abort'], {
              placeHolder: `Destination file "${reldest}" already exists.  What would you like to do?`,
            });

            if (choice === 'Overwrite') {
              // delete existing file
              fs.unlinkSync(dest);
            } else if (choice === 'Rename') {
              // prompt user for new filename
              let variableInput = <vscode.InputBoxOptions>{
                prompt: 'Please enter a new filename',
                value: reldest,
              };

              // get user's input
              dest = await vscode.window.showInputBox(variableInput).then((value) => {
                if (!value) {
                  return dest;
                }
                return value;
              });

              // if not absolute path, make workspace-relative
              if (!path.isAbsolute(dest)) {
                dest = path.join(workspace, dest);
              }
            } else if (choice === 'Skip') {
              // skip
              return true;
            } else {
              // abort
              return false;
            } // overwrite or rename
          } // if file
        } // while file exists

        // get src file contents
        let fileContents: Buffer = fs.readFileSync(src);
        if (usePlaceholders) {
          fileContents = (await this.resolvePlaceholders(fileContents, placeholderRegExp, placeholders)) as Buffer;
        }

        // ensure directories exist
        let parent = path.dirname(dest);
        this.mkdirsSync(parent);

        // write file contents to destination
        fs.writeFileSync(dest, fileContents);
      }
      return true;
    }; // copy function

    // actually copy the file recursively
    await this.recursiveApplyInDir(templateDir, workspace, copyFunc);

    return template;
  }

  public getTemplatesDir(): string {
    let absPath = this.econtext.asAbsolutePath('templates');
    this.outChannel.appendLine('ABS PATH: ' + absPath);
    return absPath;
  }

  public async chooseTemplate(): Promise<string | undefined> {
    // read templates
    let templates = this.getTemplates();
    let templateRoot = this.getTemplatesDir();

    if (templates.length === 0) {
      let optionGoToTemplates = <vscode.MessageItem>{
        title: 'Open Templates Folder',
      };

      vscode.window.showInformationMessage('No templates found!', optionGoToTemplates).then((option) => {
        // nothing selected
        if (!option) {
          return;
        }

        this.openFolderInExplorer(templateRoot);
      });

      return undefined;
    }

    // show the list of available templates.
    return vscode.window.showQuickPick(templates);
  }

  public getTemplates(): string[] {
    let templateDir: string = this.getTemplatesDir();

    let templates: string[] = fs
      .readdirSync(templateDir)
      .map(function (item) {
        // ignore hidden folders
        if (!/^\./.exec(item)) {
          return fs.statSync(path.join(templateDir, item)).isDirectory() ? item : null;
        }
        return null;
      })
      .filter(function (filename) {
        return filename !== null;
      }) as string[];

    return templates;
  }

  public openFolderInExplorer(folder: string) {
    let command = '';
    switch (process.platform) {
      case 'linux':
        command = 'xdg-open';
        break;
      case 'darwin':
        command = 'open';
        break;
      case 'win32':
        command = 'explorer.exe';
        break;
    }

    // executute open folder command
    if (command) {
      child_process.spawn(command, [folder]);
    }
  }

  /**
   * Recursively apply a function on a pair of files or directories from source to dest.
   *
   * @param src source file or folder
   * @param dest destination file or folder
   * @param func function to apply between src and dest
   * @return if recursion should continue
   * @throws Error if function fails
   */
  private async recursiveApplyInDir(
    src: string,
    dest: string,
    func: (src: string, dest: string) => Promise<boolean>
  ): Promise<boolean> {
    // apply function between src/dest
    let success = await func(src, dest);
    if (!success) {
      return false;
    }

    if (fs.lstatSync(src).isDirectory()) {
      // read contents of source directory and iterate
      const entries: string[] = fs.readdirSync(src);

      for (let entry of entries) {
        // full path of src/dest
        const srcPath = path.join(src, entry);
        const destPath = path.join(dest, entry);

        // if directory, recursively copy, otherwise copy file
        success = await this.recursiveApplyInDir(srcPath, destPath, func);
        if (!success) {
          return false;
        }
      }
    }

    return true;
  }

  /**
   * Replaces any placeholders found within the input data.  Will use a
   * dictionary of values from the user's workspace settings, or will prompt
   * if value is not known.
   *
   * @param data input data
   * @param placeholderRegExp  regular expression to use for detecting
   *                           placeholders.  The first capture group is used
   *                           as the key.
   * @param placeholders dictionary of placeholder key-value pairs
   * @returns the (potentially) modified data, with the same type as the input data
   */
  private async resolvePlaceholders(
    data: string | Buffer,
    placeholderRegExp: string,
    placeholders: { [placeholder: string]: string | undefined }
  ): Promise<string | Buffer> {
    // resolve each placeholder
    let regex = RegExp(placeholderRegExp, 'g');

    // collect set of expressions and their replacements
    let match;
    let nmatches = 0;
    let str: string;
    let encoding: BufferEncoding = 'utf8';

    if (Buffer.isBuffer(data)) {
      // get default encoding
      let fconfig = vscode.workspace.getConfiguration('files');
      encoding = fconfig.get('files.encoding', 'utf8');
      try {
        str = data.toString(encoding);
      } catch (Err) {
        // cannot decipher text from encoding, assume raw data
        return data;
      }
    } else {
      str = data;
    }

    while ((match = regex.exec(str))) {
      let key = match[1];
      let val: string | undefined = placeholders[key];
      if (!val) {
        let variableInput = <vscode.InputBoxOptions>{
          prompt: `Please enter the desired value for "${match[0]}"`,
        };

        val = await vscode.window.showInputBox(variableInput).then((value) => {
          if (value) {
            // update map
            placeholders[key] = value;
          }
          return value;
        });
      }
      ++nmatches;
    }

    // reset regex
    regex.lastIndex = 0;

    // compute output
    let out: string | Buffer = data;
    if (nmatches > 0) {
      // replace placeholders in string
      str = str.replace(regex, (match, key) => {
        let val = placeholders[key];
        if (!val) {
          val = match;
        }
        return val;
      });

      // if input was a buffer, re-encode to buffer
      if (Buffer.isBuffer(data)) {
        out = Buffer.from(str, encoding);
      } else {
        out = str;
      }
    }

    return out;
  }

  /**
   * Recursively make directories
   * @param path destination path
   */
  private mkdirsSync(dest: string, mode: string | number | null | undefined = undefined): boolean {
    // check if exists
    if (fs.existsSync(dest)) {
      if (fs.lstatSync(dest).isDirectory()) {
        return true;
      } else {
        return false;
      }
    }

    // empty path, we failed
    if (!path) {
      return false;
    }

    // ensure existence of parent
    let parent = path.dirname(dest);
    if (!this.mkdirsSync(parent, mode)) {
      return false;
    }

    // make current directory
    fs.mkdirSync(dest, mode);
    return true;
  }
}
