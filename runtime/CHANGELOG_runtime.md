<<<<<<< HEAD
# `Compact runtime` Changelog

# Runtime Version `0.9.0`, Compiler Version `0.23.117`, Language Version `0.15.111`

- Introduces standard type definitions for the different kinds of executable JavaScript the compiler generates, such as `Circuits` and `StateConstructor`.
  This allows third-party libraries, e.g. Midnight.js, to interact with contract executables in the most general and type-safe way possible.
- Introduces the `Executables` type to represent the collection of JavaScript executables generated for a compiled contract, including pure and impure circuits,
  an initial state constructor, a ledger state decoder, and witness sets. `Executables` replaces the `Contract` class the compiler previously generated.
- Generalizes `CircuitContext` to track the public and private states of multiple contracts and maintain the `ProofData` associated with each contract call.
  Functions for creating and manipulating `CircuitContext` are also introduced to simplify the compiler target and reduce code duplication.
- Introduces the `queryLedgerState` utility function. This prevents the compiler from having to generate a separate `query` function for each contract.
- Generalizes the `ConstructorContext` type to allow `initialPrivateState` to be optional. This makes it more economical to instantiate and execute contracts 
  that do not have a private state.
- Fixes a decoding bug in the `contractDependencies` function.
- Introduces the `callWitness` utility for the compiler target to use.
- Introduces the `interContractCall` utility for the compiler target to use.
- Introduces `CompactType` descriptors for commonly occurring descriptors like `CompactTypeUInt64` and `CompactTypeBytes32`. Also changes non-parametric descriptors
  like `CompactTypeMerkleTreeDigest` to be constants so that they don't have to be instantiated to be used. For example, `new CompactTypeMerkleTreeDigest().fromValue(...)`, 
  can now be written `CompactTypeMerkleTreeDigest.fromValue(...)`.
- Introduces the `checkRuntimeVersion` utility function to verify the runtime version of the contract against the expected version.

# Runtime Version `0.9.0`, Compiler Version `0.24.101`, language Version `0.16.101`
- addresses PM 14077
    - Exposes new types and functions from `@midnight-ntwrk/onchain-runtime` version `0.4.0-alpha` - functions like
      `encodeRawTokenType` and `encodeQualifiedShieldedCoinInfo` and types like `PublicAddress` and `UserAddress`.
    - Changes names to be consistent with shielded/unshielded token vernacular.

=======
# `@midnight-ntwrk/compact-runtime` Changelog

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
>>>>>>> main
