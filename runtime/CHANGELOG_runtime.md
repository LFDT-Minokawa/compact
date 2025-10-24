# `@midnight-ntwrk/compact-runtime` Changelog

# Runtime version `0.10.2`
- Adjusts the convertBytesToUint error message to account for `Uint` range end
  points now being exclusive rather than inclusive

# Runtime version `0.10.1`
- Addresses PM 19145: Migrated to ES Modules (ESM). The runtime package is now a pure ES module.
  * Added "type": "module" to package.json
  * All imports now require ES module syntax (import/export)
  * CommonJS (require/module.exports) is no longer supported
  * TypeScript configuration updated to use "module": "NodeNext" and "moduleResolution": "NodeNext"

# Runtime version `0.10.0`
- Addresses PM 18137: pull out independent composable contracts changes for runtime
  * Makes non-parametric `CompactType` definitions constants instead of classes so that we don't have to instantiate dummy 
    classes to use them. Now we use, e.g., `CompactTypeMerkleTreeDigest.alignment` instead of `new CompactTypeMerkleTreeDigest().alignment`.
  * Renames `constructorContext` and `witnessContext` context constructors to `createConstructorContext` and `createWitnessContext`. This allows us to use variables named, e.g., 
    `witnessContext` and avoid ambiguity.
  * Introduces the `createConstructorContext` for convenience.
  * Renames `transactionContext` to `currentQueryContext` in `CircuitContext`. This makes the name more informative and 
    consistent with the other members of `CircuitContext`.
  * Renames the `T` generic param in generated code to be `PS` to indicate private state.
  * Extracts a `checkRuntimeVersion` function to simplify the runtime version check logic at the top of generated code.
  * Separates everything that was previously in `runtime.ts` to separate files.
  * Adds linting and formatting to the runtime package.
  * Makes a number of renaming changes (capitalizing generics and using camel case).
  * Extracts the `queryLedgerState` function (previously generated for every contract under `Contract._query`).
  * Fixes a bug in `contract-dependencies.ts` where the recursion logic was looking for a string contract address instead of an encoded one.
  * Extract the `startContract` function at the top of the `test.ss` file into a designated TypeScript file.

# Runtime version `0.9.0`
- Renamed runtime's convert_bigint_to_Uint8Array and convert_Uint8Array_to_bigint
  to convertFieldToBytes and convertBytesToField, added a source string, and
  modified the error message to include the source information.  added a new
  routine convertBytesToUint to handle casts from Bytes to Uints.
