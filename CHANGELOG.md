# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased compiler version 0.26.108 language version 0.18.1]

- Retargets the compiler for the new Compact runtime with support for inter-contract calls and
  witness sets. 
  - Changes the names of generated JavaScript and TypeScript language elements to be consistent with the new runtime.
  - The generated `d.cts` files now use the new `Executables` type and `executables` type constructor instead of the previous
    `Contract` class and class constructor.
  - Introduces tests in `test-center` which use the `AuthCell` example to verify inter-contract calls execute as expected.
  - Moves the helper functions in the generated JavaScript for circuits to the top level of the `index.cjs` file.
  - Implements code generation for inter-contract calls by using the `interContractCall` utility from the new runtime.
  - Moves the pure circuits object to the top level of `d.cts` and `index.cjs` so that users can access pure functions
    without needing to instantiate a contract object.
- Some notes on composable contracts:
  - Due to changes mentioned above any contract even if it doesn't uses composable contract will need to be recompiled 
    if one wants to deploy it again.
  - At the moment, it is assumed that contract types do not have a default value. This will be changed in later iterations
    of this feature.

## [Unreleased compiler version 0.26.107 language version 0.18.1]

### Fixed

- A bug that allowed const statements binding patterns or multiple variables
  to appear in a single-statement context, e.g., the consequent or alternative
  of an `if` statement.

## [Unreleased compiler version 0.26.106 language version 0.18.1]

### Added

- Selective module import and renaming, e.g.:
    `import { getMatch, putMatch as $putMatch } from Matching;`
      imports `getMatch` as `getMatch`, `putMatch` as `$putMatch`
    `import { getMatch, putMatch as originalPutMatch } from Matching prefix M$;`
      imports `getMatch` as `M$getMatch`, `putMatch` as `M$originalPutMatch`
  The original form of import is still supported:
    `import Matching;`
      imports everything from `Matching` under their unchanged export names
    `import Matching prefix M$;`
      imports everything from `Matching` with prefix M$

### Fixed

- A bug that sometimes caused impure circuits to be identified as pure
