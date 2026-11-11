# Compact language usage index

Scanned the **372 fixtures** in `test-contracts/`.

## Not covered by any fixture — 122

| name | group |
|---|---|
| `merkleTreePathRoot` | Standard library circuits |
| `merkleTreePathRootNoLeafHash` | Standard library circuits |
| `nativeToken` | Standard library circuits |
| `tokenType` | Standard library circuits |
| `mintShieldedToken` | Standard library circuits |
| `evolveNonce` | Standard library circuits |
| `shieldedBurnAddress` | Standard library circuits |
| `receiveShielded` | Standard library circuits |
| `sendShielded` | Standard library circuits |
| `sendImmediateShielded` | Standard library circuits |
| `mergeCoin` | Standard library circuits |
| `mergeCoinImmediate` | Standard library circuits |
| `blockTimeLt` | Standard library circuits |
| `blockTimeGte` | Standard library circuits |
| `blockTimeGt` | Standard library circuits |
| `blockTimeLte` | Standard library circuits |
| `mintUnshieldedToken` | Standard library circuits |
| `sendUnshielded` | Standard library circuits |
| `receiveUnshielded` | Standard library circuits |
| `unshieldedBalance` | Standard library circuits |
| `unshieldedBalanceLt` | Standard library circuits |
| `unshieldedBalanceGte` | Standard library circuits |
| `unshieldedBalanceGt` | Standard library circuits |
| `unshieldedBalanceLte` | Standard library circuits |
| `jubjubSchnorrVerify` | Standard library circuits |
| `MerkleTreeDigest` | Standard library structs |
| `MerkleTreePathEntry` | Standard library structs |
| `MerkleTreePath` | Standard library structs |
| `ContractAddress` | Standard library structs |
| `QualifiedShieldedCoinInfo` | Standard library structs |
| `ZswapCoinPublicKey` | Standard library structs |
| `ShieldedSendResult` | Standard library structs |
| `UserAddress` | Standard library structs |
| `JubjubSchnorrSignature` | Standard library structs |
| `Kernel.claimZswapNullifier` | Ledger ADT operations |
| `Kernel.claimZswapCoinSpend` | Ledger ADT operations |
| `Kernel.claimZswapCoinReceive` | Ledger ADT operations |
| `Kernel.claimContractCall` | Ledger ADT operations |
| `Kernel.checkpoint` | Ledger ADT operations |
| `Kernel.mintShielded` | Ledger ADT operations |
| `Kernel.self` | Ledger ADT operations |
| `Kernel.caller` | Ledger ADT operations |
| `Kernel.mintUnshielded` | Ledger ADT operations |
| `Kernel.claimUnshieldedCoinSpend` | Ledger ADT operations |
| `Kernel.incUnshieldedOutputs` | Ledger ADT operations |
| `Kernel.incUnshieldedInputs` | Ledger ADT operations |
| `Kernel.balance` | Ledger ADT operations |
| `Kernel.balanceLessThan` | Ledger ADT operations |
| `Kernel.balanceGreaterThan` | Ledger ADT operations |
| `Kernel.blockTimeLessThan` | Ledger ADT operations |
| `Kernel.blockTimeGreaterThan` | Ledger ADT operations |
| `Cell.write` | Ledger ADT operations |
| `Cell.resetToDefault` | Ledger ADT operations |
| `Counter.lessThan` | Ledger ADT operations |
| `Counter.decrement` | Ledger ADT operations |
| `Counter.resetToDefault` | Ledger ADT operations |
| `Set.resetToDefault` | Ledger ADT operations |
| `Set.isEmpty` | Ledger ADT operations |
| `Set.size` | Ledger ADT operations |
| `Set.member` | Ledger ADT operations |
| `Set.remove` | Ledger ADT operations |
| `Map.resetToDefault` | Ledger ADT operations |
| `Map.isEmpty` | Ledger ADT operations |
| `Map.member` | Ledger ADT operations |
| `Map.lookup` | Ledger ADT operations |
| `Map.remove` | Ledger ADT operations |
| `List.resetToDefault` | Ledger ADT operations |
| `List.isEmpty` | Ledger ADT operations |
| `List.length` | Ledger ADT operations |
| `List.popFront` | Ledger ADT operations |
| `MerkleTree.isFull` | Ledger ADT operations |
| `MerkleTree.checkRoot` | Ledger ADT operations |
| `MerkleTree.insertIndex` | Ledger ADT operations |
| `MerkleTree.insertHash` | Ledger ADT operations |
| `MerkleTree.insertHashIndex` | Ledger ADT operations |
| `MerkleTree.insertIndexDefault` | Ledger ADT operations |
| `HistoricMerkleTree.isFull` | Ledger ADT operations |
| `HistoricMerkleTree.checkRoot` | Ledger ADT operations |
| `HistoricMerkleTree.insertIndex` | Ledger ADT operations |
| `HistoricMerkleTree.insertHash` | Ledger ADT operations |
| `HistoricMerkleTree.insertHashIndex` | Ledger ADT operations |
| `HistoricMerkleTree.insertIndexDefault` | Ledger ADT operations |
| `HistoricMerkleTree.resetHistory` | Ledger ADT operations |
| `ShieldedSpend` | Event types |
| `ShieldedReceive` | Event types |
| `ShieldedMint` | Event types |
| `ShieldedBurn` | Event types |
| `UnshieldedSpend` | Event types |
| `UnshieldedReceive` | Event types |
| `UnshieldedMint` | Event types |
| `UnshieldedBurn` | Event types |
| `Paused` | Event types |
| `Unpaused` | Event types |
| `Misc` | Event types |
| `transientHash` | Native circuits and witnesses |
| `transientCommit` | Native circuits and witnesses |
| `persistentCommit` | Native circuits and witnesses |
| `degradeToTransient` | Native circuits and witnesses |
| `upgradeFromTransient` | Native circuits and witnesses |
| `sha512` | Native circuits and witnesses |
| `neg` | Native circuits and witnesses |
| `inv` | Native circuits and witnesses |
| `jubjubPointX` | Native circuits and witnesses |
| `jubjubPointY` | Native circuits and witnesses |
| `ecAdd` | Native circuits and witnesses |
| `ecNeg` | Native circuits and witnesses |
| `ecMul` | Native circuits and witnesses |
| `ecMulGenerator` | Native circuits and witnesses |
| `hashToCurve` | Native circuits and witnesses |
| `constructJubjubPoint` | Native circuits and witnesses |
| `secp256k1PointX` | Native circuits and witnesses |
| `secp256k1PointY` | Native circuits and witnesses |
| `secp256r1PointX` | Native circuits and witnesses |
| `secp256r1PointY` | Native circuits and witnesses |
| `curve25519PointX` | Native circuits and witnesses |
| `curve25519PointY` | Native circuits and witnesses |
| `ownPublicKey` | Native circuits and witnesses |
| `createZswapInput` | Native circuits and witnesses |
| `createZswapOutput` | Native circuits and witnesses |
| `JubjubPoint` | Native types |
| `serialize` | Inline entries |
| `deserialize` | Inline entries |

## Builtin types — 6/6 covered

Declared in `parser.ss — keywordDataTypes`.

| name | first usage | uses |
|---|---|---:|
| `Boolean` | [`test-contracts/keywords/assert/old_statement_syntax/assert_old_statement_syntax.compact:21`](../../test-contracts/keywords/assert/old_statement_syntax/assert_old_statement_syntax.compact#L21) | 143 |
| `Bytes` | [`test-contracts/keywords/circuit/duplicate_definitions_unused/circuit_duplicate_definitions_unused.compact:16`](../../test-contracts/keywords/circuit/duplicate_definitions_unused/circuit_duplicate_definitions_unused.compact#L16) | 432 |
| `Field` | [`test-contracts/keywords/assert/in_untaken_branch/assert_in_untaken_branch.compact:16`](../../test-contracts/keywords/assert/in_untaken_branch/assert_in_untaken_branch.compact#L16) | 445 |
| `Opaque` | [`test-contracts/keywords/reserved/future/delete_as_identifier/reserved_future_delete_as_identifier.compact:16`](../../test-contracts/keywords/reserved/future/delete_as_identifier/reserved_future_delete_as_identifier.compact#L16) | 4 |
| `Uint` | [`test-contracts/keywords/circuit/duplicate_definitions_unused/circuit_duplicate_definitions_unused.compact:16`](../../test-contracts/keywords/circuit/duplicate_definitions_unused/circuit_duplicate_definitions_unused.compact#L16) | 216 |
| `Vector` | [`test-contracts/keywords/circuit/overload_ambiguous_by_widening/circuit_overload_ambiguous_by_widening.compact:16`](../../test-contracts/keywords/circuit/overload_ambiguous_by_widening/circuit_overload_ambiguous_by_widening.compact#L16) | 123 |

## Standard library circuits — 8/33 covered

Declared in `shipped Compact libraries — export circuit`.

| name | first usage | uses |
|---|---|---:|
| `some` | [`test-contracts/keywords/import/stdlib_requires_import/import_stdlib_requires_import.compact:18`](../../test-contracts/keywords/import/stdlib_requires_import/import_stdlib_requires_import.compact#L18) | 1 |
| `none` | [`test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact:30`](../../test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact#L30) | 2 |
| `left` | [`test-contracts/keywords/return/if_else_either/return_if_else_either.compact:21`](../../test-contracts/keywords/return/if_else_either/return_if_else_either.compact#L21) | 1 |
| `right` | [`test-contracts/keywords/return/if_else_either/return_if_else_either.compact:23`](../../test-contracts/keywords/return/if_else_either/return_if_else_either.compact#L23) | 2 |
| `merkleTreePathRoot` | **no fixture** | 0 |
| `merkleTreePathRootNoLeafHash` | **no fixture** | 0 |
| `nativeToken` | **no fixture** | 0 |
| `tokenType` | **no fixture** | 0 |
| `mintShieldedToken` | **no fixture** | 0 |
| `evolveNonce` | **no fixture** | 0 |
| `shieldedBurnAddress` | **no fixture** | 0 |
| `receiveShielded` | **no fixture** | 0 |
| `sendShielded` | **no fixture** | 0 |
| `sendImmediateShielded` | **no fixture** | 0 |
| `mergeCoin` | **no fixture** | 0 |
| `mergeCoinImmediate` | **no fixture** | 0 |
| `blockTimeLt` | **no fixture** | 0 |
| `blockTimeGte` | **no fixture** | 0 |
| `blockTimeGt` | **no fixture** | 0 |
| `blockTimeLte` | **no fixture** | 0 |
| `mintUnshieldedToken` | **no fixture** | 0 |
| `sendUnshielded` | **no fixture** | 0 |
| `receiveUnshielded` | **no fixture** | 0 |
| `unshieldedBalance` | **no fixture** | 0 |
| `unshieldedBalanceLt` | **no fixture** | 0 |
| `unshieldedBalanceGte` | **no fixture** | 0 |
| `unshieldedBalanceGt` | **no fixture** | 0 |
| `unshieldedBalanceLte` | **no fixture** | 0 |
| `jubjubSchnorrVerify` | **no fixture** | 0 |
| `secp256k1EcdsaVerify` | [`test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact:43`](../../test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact#L43) | 16 |
| `secp256k1EthereumAddress` | [`test-contracts/stdlib/secp256k1/ethereum_address/secp256k1_ethereum_address.compact:28`](../../test-contracts/stdlib/secp256k1/ethereum_address/secp256k1_ethereum_address.compact#L28) | 2 |
| `secp256r1EcdsaVerify` | [`test-contracts/stdlib/secp256r1/ecdsa_verify/secp256r1_ecdsa_verify.compact:34`](../../test-contracts/stdlib/secp256r1/ecdsa_verify/secp256r1_ecdsa_verify.compact#L34) | 17 |
| `ed25519Verify` | [`test-contracts/stdlib/curve25519/slow/verify_sequential/curve25519_verify_sequential.compact:31`](../../test-contracts/stdlib/curve25519/slow/verify_sequential/curve25519_verify_sequential.compact#L31) | 31 |

## Standard library structs — 6/15 covered

Declared in `shipped Compact libraries — export struct`.

| name | first usage | uses |
|---|---|---:|
| `Maybe` | [`test-contracts/keywords/import/stdlib_requires_import/import_stdlib_requires_import.compact:17`](../../test-contracts/keywords/import/stdlib_requires_import/import_stdlib_requires_import.compact#L17) | 7 |
| `Either` | [`test-contracts/keywords/return/if_else_either/return_if_else_either.compact:19`](../../test-contracts/keywords/return/if_else_either/return_if_else_either.compact#L19) | 3 |
| `MerkleTreeDigest` | **no fixture** | 0 |
| `MerkleTreePathEntry` | **no fixture** | 0 |
| `MerkleTreePath` | **no fixture** | 0 |
| `ContractAddress` | **no fixture** | 0 |
| `ShieldedCoinInfo` | [`test-contracts/keywords/type/redefines_stdlib_type/type_redefines_stdlib_type.compact:19`](../../test-contracts/keywords/type/redefines_stdlib_type/type_redefines_stdlib_type.compact#L19) | 1 |
| `QualifiedShieldedCoinInfo` | **no fixture** | 0 |
| `ZswapCoinPublicKey` | **no fixture** | 0 |
| `ShieldedSendResult` | **no fixture** | 0 |
| `UserAddress` | **no fixture** | 0 |
| `JubjubSchnorrSignature` | **no fixture** | 0 |
| `Secp256k1EcdsaSignature` | [`test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact:40`](../../test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact#L40) | 12 |
| `Secp256r1EcdsaSignature` | [`test-contracts/stdlib/secp256r1/ecdsa_verify/secp256r1_ecdsa_verify.compact:31`](../../test-contracts/stdlib/secp256r1/ecdsa_verify/secp256r1_ecdsa_verify.compact#L31) | 13 |
| `Ed25519Signature` | [`test-contracts/stdlib/curve25519/slow/verify_sequential/curve25519_verify_sequential.compact:27`](../../test-contracts/stdlib/curve25519/slow/verify_sequential/curve25519_verify_sequential.compact#L27) | 27 |

## Ledger ADT operations — 13/62 covered

Declared in `compiler sources — declare-ledger-adt`.

| name | first usage | uses |
|---|---|---:|
| `Kernel.claimZswapNullifier` | **no fixture** | 0 |
| `Kernel.claimZswapCoinSpend` | **no fixture** | 0 |
| `Kernel.claimZswapCoinReceive` | **no fixture** | 0 |
| `Kernel.claimContractCall` | **no fixture** | 0 |
| `Kernel.checkpoint` | **no fixture** | 0 |
| `Kernel.mintShielded` | **no fixture** | 0 |
| `Kernel.self` | **no fixture** | 0 |
| `Kernel.caller` | **no fixture** | 0 |
| `Kernel.mintUnshielded` | **no fixture** | 0 |
| `Kernel.claimUnshieldedCoinSpend` | **no fixture** | 0 |
| `Kernel.incUnshieldedOutputs` | **no fixture** | 0 |
| `Kernel.incUnshieldedInputs` | **no fixture** | 0 |
| `Kernel.balance` | **no fixture** | 0 |
| `Kernel.balanceLessThan` | **no fixture** | 0 |
| `Kernel.balanceGreaterThan` | **no fixture** | 0 |
| `Kernel.blockTimeLessThan` | **no fixture** | 0 |
| `Kernel.blockTimeGreaterThan` | **no fixture** | 0 |
| `Cell.read` | [`test-contracts/keywords/type/new_type_of_adt/type_new_type_of_adt.compact:25`](../../test-contracts/keywords/type/new_type_of_adt/type_new_type_of_adt.compact#L25) | 1 |
| `Cell.write` | **no fixture** | 0 |
| `Cell.resetToDefault` | **no fixture** | 0 |
| `Counter.read` | [`test-contracts/keywords/const/initializer_side_effects/const_initializer_side_effects.compact:22`](../../test-contracts/keywords/const/initializer_side_effects/const_initializer_side_effects.compact#L22) | 2 |
| `Counter.lessThan` | **no fixture** | 0 |
| `Counter.increment` | [`test-contracts/keywords/const/initializer_side_effects/const_initializer_side_effects.compact:22`](../../test-contracts/keywords/const/initializer_side_effects/const_initializer_side_effects.compact#L22) | 10 |
| `Counter.decrement` | **no fixture** | 0 |
| `Counter.resetToDefault` | **no fixture** | 0 |
| `Set.resetToDefault` | **no fixture** | 0 |
| `Set.isEmpty` | **no fixture** | 0 |
| `Set.size` | **no fixture** | 0 |
| `Set.member` | **no fixture** | 0 |
| `Set.insert` | [`test-contracts/keywords/if/branches_write_ledger/if_branches_write_ledger.compact:38`](../../test-contracts/keywords/if/branches_write_ledger/if_branches_write_ledger.compact#L38) | 2 |
| `Set.remove` | **no fixture** | 0 |
| `Map.resetToDefault` | **no fixture** | 0 |
| `Map.isEmpty` | **no fixture** | 0 |
| `Map.size` | [`test-contracts/primitives/vector/slice/non_constant_index/vector_slice_non_constant_index.compact:21`](../../test-contracts/primitives/vector/slice/non_constant_index/vector_slice_non_constant_index.compact#L21) | 1 |
| `Map.member` | **no fixture** | 0 |
| `Map.lookup` | **no fixture** | 0 |
| `Map.insert` | [`test-contracts/stdlib/historic_merkle_tree/deep_default/historic_merkle_tree_deep_default.compact:48`](../../test-contracts/stdlib/historic_merkle_tree/deep_default/historic_merkle_tree_deep_default.compact#L48) | 2 |
| `Map.insertDefault` | [`test-contracts/stdlib/historic_merkle_tree/deep_default/historic_merkle_tree_deep_default.compact:44`](../../test-contracts/stdlib/historic_merkle_tree/deep_default/historic_merkle_tree_deep_default.compact#L44) | 2 |
| `Map.remove` | **no fixture** | 0 |
| `List.resetToDefault` | **no fixture** | 0 |
| `List.isEmpty` | **no fixture** | 0 |
| `List.length` | **no fixture** | 0 |
| `List.head` | [`test-contracts/keywords/if/branches_write_ledger/if_branches_write_ledger.compact:49`](../../test-contracts/keywords/if/branches_write_ledger/if_branches_write_ledger.compact#L49) | 1 |
| `List.popFront` | **no fixture** | 0 |
| `List.pushFront` | [`test-contracts/keywords/if/branches_write_ledger/if_branches_write_ledger.compact:48`](../../test-contracts/keywords/if/branches_write_ledger/if_branches_write_ledger.compact#L48) | 1 |
| `MerkleTree.resetToDefault` | [`test-contracts/stdlib/merkle_tree/deep_default/merkle_tree_deep_default.compact:38`](../../test-contracts/stdlib/merkle_tree/deep_default/merkle_tree_deep_default.compact#L38) | 3 |
| `MerkleTree.isFull` | **no fixture** | 0 |
| `MerkleTree.checkRoot` | **no fixture** | 0 |
| `MerkleTree.insert` | [`test-contracts/stdlib/merkle_tree/deep_default/merkle_tree_deep_default.compact:32`](../../test-contracts/stdlib/merkle_tree/deep_default/merkle_tree_deep_default.compact#L32) | 3 |
| `MerkleTree.insertIndex` | **no fixture** | 0 |
| `MerkleTree.insertHash` | **no fixture** | 0 |
| `MerkleTree.insertHashIndex` | **no fixture** | 0 |
| `MerkleTree.insertIndexDefault` | **no fixture** | 0 |
| `HistoricMerkleTree.resetToDefault` | [`test-contracts/stdlib/historic_merkle_tree/deep_default/historic_merkle_tree_deep_default.compact:38`](../../test-contracts/stdlib/historic_merkle_tree/deep_default/historic_merkle_tree_deep_default.compact#L38) | 3 |
| `HistoricMerkleTree.isFull` | **no fixture** | 0 |
| `HistoricMerkleTree.checkRoot` | **no fixture** | 0 |
| `HistoricMerkleTree.insert` | [`test-contracts/stdlib/historic_merkle_tree/deep_default/historic_merkle_tree_deep_default.compact:32`](../../test-contracts/stdlib/historic_merkle_tree/deep_default/historic_merkle_tree_deep_default.compact#L32) | 3 |
| `HistoricMerkleTree.insertIndex` | **no fixture** | 0 |
| `HistoricMerkleTree.insertHash` | **no fixture** | 0 |
| `HistoricMerkleTree.insertHashIndex` | **no fixture** | 0 |
| `HistoricMerkleTree.insertIndexDefault` | **no fixture** | 0 |
| `HistoricMerkleTree.resetHistory` | **no fixture** | 0 |

## Event types — 0/11 covered

Declared in `compiler sources — declare-event-type`.

| name | first usage | uses |
|---|---|---:|
| `ShieldedSpend` | **no fixture** | 0 |
| `ShieldedReceive` | **no fixture** | 0 |
| `ShieldedMint` | **no fixture** | 0 |
| `ShieldedBurn` | **no fixture** | 0 |
| `UnshieldedSpend` | **no fixture** | 0 |
| `UnshieldedReceive` | **no fixture** | 0 |
| `UnshieldedMint` | **no fixture** | 0 |
| `UnshieldedBurn` | **no fixture** | 0 |
| `Paused` | **no fixture** | 0 |
| `Unpaused` | **no fixture** | 0 |
| `Misc` | **no fixture** | 0 |

## Native circuits and witnesses — 2/27 covered

Declared in `compiler sources — declare-native-entry`.

| name | first usage | uses |
|---|---|---:|
| `transientHash` | **no fixture** | 0 |
| `transientCommit` | **no fixture** | 0 |
| `persistentHash` | [`test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact:43`](../../test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact#L43) | 59 |
| `persistentCommit` | **no fixture** | 0 |
| `degradeToTransient` | **no fixture** | 0 |
| `upgradeFromTransient` | **no fixture** | 0 |
| `keccak256` | [`test-contracts/stdlib/keccak256/adt_rejected/keccak256_adt_rejected.compact:28`](../../test-contracts/stdlib/keccak256/adt_rejected/keccak256_adt_rejected.compact#L28) | 64 |
| `sha512` | **no fixture** | 0 |
| `neg` | **no fixture** | 0 |
| `inv` | **no fixture** | 0 |
| `jubjubPointX` | **no fixture** | 0 |
| `jubjubPointY` | **no fixture** | 0 |
| `ecAdd` | **no fixture** | 0 |
| `ecNeg` | **no fixture** | 0 |
| `ecMul` | **no fixture** | 0 |
| `ecMulGenerator` | **no fixture** | 0 |
| `hashToCurve` | **no fixture** | 0 |
| `constructJubjubPoint` | **no fixture** | 0 |
| `secp256k1PointX` | **no fixture** | 0 |
| `secp256k1PointY` | **no fixture** | 0 |
| `secp256r1PointX` | **no fixture** | 0 |
| `secp256r1PointY` | **no fixture** | 0 |
| `curve25519PointX` | **no fixture** | 0 |
| `curve25519PointY` | **no fixture** | 0 |
| `ownPublicKey` | **no fixture** | 0 |
| `createZswapInput` | **no fixture** | 0 |
| `createZswapOutput` | **no fixture** | 0 |

## Native types — 10/11 covered

Declared in `compiler sources — declare-native-type`.

| name | first usage | uses |
|---|---|---:|
| `JubjubScalar` | [`test-contracts/stdlib/jubjub/scalar/casts/to_boolean/jubjub_scalar_casts_to_boolean.compact:20`](../../test-contracts/stdlib/jubjub/scalar/casts/to_boolean/jubjub_scalar_casts_to_boolean.compact#L20) | 3 |
| `JubjubPoint` | **no fixture** | 0 |
| `Curve25519Base` | [`test-contracts/stdlib/curve25519/base/casts/to_boolean/curve25519_base_casts_to_boolean.compact:20`](../../test-contracts/stdlib/curve25519/base/casts/to_boolean/curve25519_base_casts_to_boolean.compact#L20) | 8 |
| `Curve25519Scalar` | [`test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact:20`](../../test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact#L20) | 10 |
| `Curve25519Point` | [`test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact:18`](../../test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact#L18) | 30 |
| `Secp256k1Base` | [`test-contracts/stdlib/secp256k1/base/casts/to_boolean/secp256k1_base_casts_to_boolean.compact:20`](../../test-contracts/stdlib/secp256k1/base/casts/to_boolean/secp256k1_base_casts_to_boolean.compact#L20) | 5 |
| `Secp256k1Scalar` | [`test-contracts/stdlib/foreign_field/self_subtract/foreign_field_self_subtract.compact:18`](../../test-contracts/stdlib/foreign_field/self_subtract/foreign_field_self_subtract.compact#L18) | 8 |
| `Secp256k1Point` | [`test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact:41`](../../test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact#L41) | 14 |
| `Secp256r1Base` | [`test-contracts/stdlib/foreign_field/self_subtract/foreign_field_self_subtract.compact:20`](../../test-contracts/stdlib/foreign_field/self_subtract/foreign_field_self_subtract.compact#L20) | 7 |
| `Secp256r1Scalar` | [`test-contracts/stdlib/secp256r1/scalar/casts/to_boolean/secp256r1_scalar_casts_to_boolean.compact:20`](../../test-contracts/stdlib/secp256r1/scalar/casts/to_boolean/secp256r1_scalar_casts_to_boolean.compact#L20) | 3 |
| `Secp256r1Point` | [`test-contracts/stdlib/secp256r1/ecdsa_verify/secp256r1_ecdsa_verify.compact:32`](../../test-contracts/stdlib/secp256r1/ecdsa_verify/secp256r1_ecdsa_verify.compact#L32) | 13 |

## Inline entries — 0/2 covered

Declared in `compiler sources — declare-inline-entry`.

| name | first usage | uses |
|---|---|---:|
| `serialize` | **no fixture** | 0 |
| `deserialize` | **no fixture** | 0 |

## What this does and does not show

- **Used is not tested.** A usage site proves a fixture mentions the name. Whether it is meaningfully exercised depends on that fixture's assertions.
- **Names are matched as words**, after comments and string literals are removed. A local variable sharing a standard-library name would still count.
- **Generic instantiations are not separated** — `some<Field>` and `some<Bytes<32>>` are one entry.
