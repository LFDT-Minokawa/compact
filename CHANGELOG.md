# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased compiler version 0.26.10? language version 0.18.1]

### Added

- A new IR is added.  It is called `Lexpanedcontractcall`.  It adds the wrapper 
  function name for a circuit defined in a contract.  This wrapper name is what 
  is eventually called for a contract call and since it is prodcued in one 
  pass but consumed in another we pass it through a structure between these
  two passes.  This IR also adds `contract-call` expression.
  These were needed for what the corresponding pass needs to generate. 
  TODO fix the tcontract and contract-call in this IR.
- A new pass `wrap-contract-circuits : Lnoandornot -> Lexpandedcontractcall` is 
  added to frontend passes.  It adds a module `__compact_contract_C` for a contract
  type `C` to the program.  `compact_contract_C`
  - imports `CompactStandardLibrary` and renames it to `__compact_std`
  - defines wrapper circuits for each circtuit defined in `C`.  For circuit `foo`
    it defines 
    ```
    export circuit __compact_C_foo (__compact_c: C, x1: T1, ...): T {
      (block (__compact_local_res)
        (let* ([__compact_local_res (contract-call foo (__compact_local_c C))])
          (seq
            (elt-call __compact_std_kernel claimContractCall __compact_local_c
                      <foo-hash>
                      (call (fref __compact_std_transientCommit (ttuple T1 ... T))
                            (tuple x1 ... __compact_local_res)
                            (call __compact_std_createNonce)))
            (return __compact_local_res))))
    }
    ```
  - then `__compact_contract_C` is imported in the program where a contract call
    to `C` existed and if `foo` was exported an export of `__compact_C_foo` is 
    also added in the same scope.
- changes to ecdecl-circuit record 
- elt-call -> function call 
- where tcontract and contract-call are dropped
- what you get for zkir
- Inserts `transientCommit` when a contract declaration exists in 
  `insert-transientCommit`. Note: this has to come before `expand-modules-and-types` 
  so that the `transientCommit` is added to the external declarations and so that 
  `print-typescript` and `print-zkir` get the same call to `transientCommit` related to a
  contract call.
- Inserts the Kernel binding for a `contract-call` in `combine-ledger-declarations`.
- Expands a `contract-call` into a sequence of `transientCommit` and `claimContractCall`
  in `expand-contract-call`.
- Drops extra stuff somewhere TBF

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
