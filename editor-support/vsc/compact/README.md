# Compact VSC Plugin

## Features

### Syntax highlighting

Smart contracts are written in compact language. Following languages features
will be automatically highlighted:
* keywords like `enum`, `struct`, `circuit`, etc.
* string, boolean, number literals
* comments
* parenthesis

![syntax-highlighting](https://user-images.githubusercontent.com/10901543/198249320-46a85170-98b7-4441-bf1f-167ea824585c.png)

### Building Compact source files

For building smart contract you probably will want to create script in `package.json`
e.g.
```
"compact": "compactc --vscode ./src/myContract.compact ./src/managed/myContract"
```
This assume compact compiler is on the path.

When you are using VSC Plugin you have to set the `--vscode` flag to get correct error messages.
This flag causes the compiler to remove the newlines from error messages due to VSC Plugin
limitation for multi-line error messages.

When you work on your smart contract it is more convenient to
add [task file](https://code.visualstudio.com/docs/editor/tasks) `.vscode/tasks.json` containing
```json
  {
    "tasks": [
      {
        "label": "Compile compact file",
         "type": "shell",
         "command": "compactc --vscode --skip-zk ${file} ${workspaceFolder}/src/managed",
         "group": "build",
         "presentation": {
           "echo": true,
           "reveal": "silent",
           "focus": false,
           "panel": "new",
           "showReuseMessage": false,
           "clear": false
         },
         "problemMatcher": [
             "$compactException",
             "$compactInternal",
             "$compactCommandNotFound"
         ]
      }
    ]
  }
```
Thanks to configured problemMatchers:
```json
 "problemMatcher": [
     "$compactException",
     "$compactInternal",
     "$compactCommandNotFound"
 ]
```
and ignoring generating files necessary for ZK proofs `compactc --skip-zk`
you will get fast feedback in Problems tab.

### Code snippets

VSC Plugin provides following [code snippets](https://code.visualstudio.com/docs/editor/userdefinedsnippets) when editing Compact smart contracts:
* `ledger` (`state`)
* `constructor` in ledger
* potentially exported `circuit` (`function` / `transition`)
* `witness` (`private` function)
* constructor
* import Compact `standard library` (`init`, `stdlib`)
* `if` statement (`cond`)
* `map` (`for`)
* `fold`
* `enum`
* `struct`
* `module`
* `assert`
* `pragma`

There is also `compact` template that will generate simple structure for smart contract.

### New Compact smart contract from selected code

If you are creating dApp, you can create a new smart contract
with an empty ledger and a single circuit:
1. bring up the commands pallette (Cmd+Shift+P)
2. select `Snippets: Fill File with snippet` and then
3. select `compact`.
   If you are in existing file this overwrites content of this file.
   Other snippets are available from inside the file. Just start typing the name of the function

### License
Apache 2.0
