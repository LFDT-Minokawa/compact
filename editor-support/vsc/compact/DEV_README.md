# Midnight Visual Studio Code Plugin (VSC Plugin) Developer guide

VSC Plugin is a plugin for use in VisualStudioCode (VSC) that provides tooling of compactc langauge including:
* syntax definition
* patternMatchers used in error reporting
* code snippets
* project templates

Some elements of VSC Plugin are configured in every dApp:
* calling compact compiler from VSC Plugin
* which patternMatchers to use
* configuration for debugging

## syntax definition

VSC Plugin defines language `compact` recognized by file extension with the same name.
* comments and brackets are defined in `./language-configuration.json`
* other syntactic elements are defined in `./syntaxes/compact.tmLanguage.json`

```json
{
  "contributes": {
    "languages": [
      {
        "id": "compact",
        "extensions": [".compact"],
        "configuration": "./language-configuration.json",
      }
    ],
    "grammars": [
      {
        "language": "compact",
        "scopeName": "source.compact",
        "path": "./syntaxes/compact.tmLanguage.json"
      }
    ]
}}
```

Compiler have mechanism to collect all reserved words and export them using:
```sh
/Users/lemastero/work/iohk/abcirdc/compiler/export-keywords.ss
```
this should export file: `editor-support/vsc/compact/tests/resources/keywords.json`
that is used in unit tests to verify that all of them are used in `compact.tmLanguage.json`.

Resources:
* [Syntax Highlight Guide](https://code.visualstudio.com/api/language-extensions/syntax-highlight-guide)
* [TextMate Language Grammars syntax](https://macromates.com/manual/en/language_grammars)
* Most of current .tmLanguage was inspired by [VSC Atom JS grammar](https://github.com/microsoft/vscode-js-atom-grammar/blob/main/syntaxes/javascript.json)
  (official [grammar for TS](https://github.com/microsoft/TypeScript-TmLanguage) uses YAML does not seem that useful).

Potential alternatives / further development:
* Interesting direction would be support [semantic-highlight](https://code.visualstudio.com/api/language-extensions/semantic-highlight-guide) but it requires LSP Plugin.
* instead of `TextMate grammars` use [tree-sitter](https://tree-sitter.github.io/tree-sitter/) via using [georgewfraser/vscode-tree-sitter](https://github.com/georgewfraser/vscode-tree-sitter) (sadly [no official support](https://github.com/microsoft/vscode/issues/50140))

## Error reporting

Error reporting is handled using `problem matchers`.

They consists of regexp and information how to decode:
- file name and
- row and column numbers
where error happened.

dApp contains definition how to build compact source code (smart contract) and which pattern matchers to use
for detecting errors.

When user builds smart contract pattern matcher should catch error using regexp and link to proper place in source code. Moreover editor with code should highlight token with given column and line numbers.

### command to run compiler and use errorMatchers

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Compile compact file to JS",
      "type": "shell",
      "command": "npx run-compactc --vscode --skip-zk ./src/hello.compactc ./gen/hello-world\"",
      "group": "build",
      
      "presentation": {
        "echo": true,
        "reveal": "never",
        "focus": false,
        "panel": "shared",
        "showReuseMessage": false,
        "clear": true,
        "revealProblems": "onProblem"
      },

      "problemMatcher": [
        "$compactException",
        "$compactInternal",
        "$compactCommandNotFound"
      ]
}]}
```

More resources:
* [Documentation for using tasks](https://code.visualstudio.com/docs/editor/tasks#vscode)
* [JSON schema for task.json](https://code.visualstudio.com/docs/editor/tasks-appendix)
* [use of variables in task.json](https://code.visualstudio.com/docs/editor/tasks-appendix)
* [variables reference](https://code.visualstudio.com/docs/editor/variables-reference)
* [adding task as plugin](https://code.visualstudio.com/api/extension-guides/task-provider)
Note: moving task to Plugin was not done yet, and even though it is annoying to configure this,
it was more convenient to define commands in task.json (e.g. different dApps have different structure).

Probably one need to establish with compiler engineers format for some metadata for project (perhaps add section to package.json) and read it in task.json and from this figure out where to put compiled files.

### errorMatchers definition

Every definition of problem matchers contains:
* name (this needs to be used in dApp)
* regexp e.g. `^Exception: (.*?) line (\\d+), char (\\d+): (.*)$` (errors from compiler needs to match this)
* in regexp there are backets `capture groups` that specify how to find file name, line with error and character (column)

For example  first capture grup is file name, 4th error message:
```json
{
  "file": 1,
  "line": 2,
  "column": 3,
  "message": 4
}
```
Note error matchers for `compactInternal` and `compactCommandNotFound` there are no information about file. This should be discussed with compiler engineers.

```json
{
  "contributes": {
    "problemMatchers": [
      {
        "name": "compactException",
        "owner": "compact",
        "fileLocation": [
          "absolute"
        ],
        "pattern": {
          "regexp": "^Exception: (.*?) line (\\d+), char (\\d+): (.*)$",
          "file": 1,
          "line": 2,
          "column": 3,
          "message": 4
        }
      },
      {
        "name": "compactInternal",
        "owner": "compact",
        "fileLocation": [
          "absolute"
        ],
        "pattern": {
          "regexp": "^(Exception in (.*?): \\(internal error\\) (.*?))$",
          "message": 1
        }
      },
      {
        "name": "compactCommandNotFound",
        "owner": "compact",
        "fileLocation": [
          "absolute"
        ],
        "pattern": {
          "regexp": "^((.*?) command not found: (.*?))$",
          "message": 1
        }
      }
    ],
}}
```

Resources:
* [reference](https://code.visualstudio.com/api/references/contribution-points#contributes.problemMatchers)
* [documentation](https://code.visualstudio.com/docs/editor/tasks#_defining-a-problem-matcher).

## code snippets

VSC Code Snippets are defined in [compact.code-snippets](./compact.code-snippets) e.g.
```json
{
  "witness": {
    "prefix": ["witness", "private"],
    "body": [
      "witness ${1:foo}(${2:x}: ${3:Field}): ${4:Field};",
      "$0"
    ],
    "description": "new witness",
    "scope": "compact"
  },
}
```

"witness" and "private" prefixes, trigger creating compact code:

```typescript
witness ${1:foo}(${2:x}: ${3:Field}): ${4:Field};
```

VSC Plugin user can navigate using TAB through variables ${1} ${2} etc.  
At the end cursor is placed at $0.  
Variable 1 has default value foo - `${1:foo}`.

Configuration in VSC Plugin `package.json` enabling use of snippets:
```json
{
  "contributes": {
    "snippets": [
      {
        "language": "compact",
        "path": "compact.code-snippets"
      }
    ]
}}
```
Resources:
* [VSC docs User defined snippets](https://code.visualstudio.com/docs/editor/userdefinedsnippets)

## project templates
- prepare dApp in template
    - configure debugging
    - configure launching compiler
    - dApps outside input-output/mn-example-apps and mn-network/example-apps

# Maintainer Cookbook

## Always remember

1. Testing changes is easier if you update version in `package.json`:
```json
{
  "version": "0.2.11",
}
```
Important for end users and QA engineers!

2. Add information about changes in `editor-support/vsc/compact/CHANGELOG.md`


## Testing if VSC Plugin has up to date keywords

In compact [compiler directory](../../..), export keywords, datatypes:
```sh
./compiler/export-keywords.ss
```

In VSC Plugin directory

* export env variable
```sh
export TEST_COMPACT_PATH=../../../test-center/compact/test.compact
```
You can check if it points to a real file:
```sh
ls -la $TEST_COMPACT_PATH
cat $TEST_COMPACT_PATH
```

* run tests
```sh
yarn test
```

## updating dApps in template

Example application is located in:
```text
editor-support/vsc/compact/templates/dapp-template-counter/*
```

If you plan to use e.g. coracle
1. delete original content from there
2. copy content of example dApp you want to use as template e.g. https://github.com/input-output-hk/midnight-example-applications/tree/main/examples/bboard/ into https://github.com/input-output-hk/compactc/tree/master/editor-support/vsc/compact/templates/dapp-template-counter

(I use for this file manager Double Commander that ignores git metadata.
Remember to check .vscode directory - hidden files, marked using dot at start are usually ignored.

3. Verify in some utility that changes are intended (Git support in IntelliJ Idea is pretty good for this).

Usually I need to restore some changes:
* in mn-example-apps there are [common dependencies defined](https://github.com/input-output-hk/midnight-example-applications/blob/main/package.json) that would be missing
* template variables in [package.json](https://github.com/input-output-hk/compactc/blob/master/editor-support/vsc/compact/templates/dapp-template-counter/package.json) so user can define them
* often README.MD is not there in example apps or contains sone nix commands

## update graphics

VSC Plugin has graphical assets for:
* icon for file with smart contract
* logo used on description

Paths to them are in `package.json`:
```json
{
  "icon": "icon-white.png",
  "contributes": {
    "languages": [
      {
        "icon": {
          "light": "logo-black.png",
          "dark": "logo-white.png"
}}]}}
```
If you put graphics with different names remember paths.
SVG file format does not work.

## Testing locally

As explained in (README.md)[./README.md] you need compactc available as command.
One way to get it is to build it in root directory using `nix develop .#compiler`.

First time - create directory for plugin:
```sh
mkdir ~/.vscode/extensions/compact
```

Copy this directory into subdirectory in `~/.vscode/extensions` e.g.:

```sh
cp -r ./editor-support/vsc/compact/* ~/.vscode/extensions/compact
```

## Package

```sh
yarn package
```

There is also a nix expression that packages the extension into a `.vsix` file:

```sh
nix build .#compact-vscode-extension
```

NOTE: this will produce a `result/*.vsix` file.

Installing from VSIX package:

```sh
code --install-extension myextension.vsix
```

## Release

Create tag e.g. 0.2.3
1. `nix build`
2. create & push tag
  ```sh
  gut tag vsc0.2.3
  git push origin vsc0.2.3
  ```
3. open tag on GH e.g. https://github.com/input-output-hk/compactc/releases/tag/vsc0.2.3 and create release.
  * add binary package for the VSC Plugin e.g. ./result/compact-0.2.3.vsix
  * publish release

Note!
Currently CI does not put vsix file into any repository you need to upload it manually (create release and attach file).
You might copy somewhere vsix, add zip extension and unzip it to check if there are not unexpected files there.
In particular you did not package previously build VSC Plugin or some extra not committed files.

See `editor-support/vsc/compact/.vscodeignore` for list of ignored files while building extension.

Resources:
* [Building & publishing VSC plugins](https://code.visualstudio.com/api/working-with-extensions/bundling-extension)
* [Packaging extension](https://code.visualstudio.com/api/working-with-extensions/publishing-extension#packaging-extensions)
