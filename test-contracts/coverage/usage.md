# Compact language usage index

Scanned the **433 fixtures** in `test-contracts/`.

## Not covered by any fixture — 86

| name | group |
|---|---|
| `merkleTreePathRoot` | Standard library circuits |
| `merkleTreePathRootNoLeafHash` | Standard library circuits |
| `nativeToken` | Standard library circuits |
| `tokenType` | Standard library circuits |
| `evolveNonce` | Standard library circuits |
| `shieldedBurnAddress` | Standard library circuits |
| `unshieldedBalance` | Standard library circuits |
| `unshieldedBalanceLt` | Standard library circuits |
| `unshieldedBalanceGte` | Standard library circuits |
| `unshieldedBalanceGt` | Standard library circuits |
| `unshieldedBalanceLte` | Standard library circuits |
| `jubjubSchnorrVerify` | Standard library circuits |
| `MerkleTreeDigest` | Standard library structs |
| `MerkleTreePathEntry` | Standard library structs |
| `MerkleTreePath` | Standard library structs |
| `ShieldedSendResult` | Standard library structs |
| `JubjubSchnorrSignature` | Standard library structs |
| `Kernel.caller` | Ledger ADT operations |
| `Kernel.balance` | Ledger ADT operations |
| `Kernel.balanceLessThan` | Ledger ADT operations |
| `Kernel.balanceGreaterThan` | Ledger ADT operations |
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
| `upgradeFromTransient` | Native circuits and witnesses |
| `sha512` | Native circuits and witnesses |
| `neg` | Native circuits and witnesses |
| `inv` | Native circuits and witnesses |
| `jubjubPointX` | Native circuits and witnesses |
| `jubjubPointY` | Native circuits and witnesses |
| `ecAdd` | Native circuits and witnesses |
| `ecNeg` | Native circuits and witnesses |
| `ecMul` | Native circuits and witnesses |
| `hashToCurve` | Native circuits and witnesses |
| `constructJubjubPoint` | Native circuits and witnesses |
| `secp256k1PointX` | Native circuits and witnesses |
| `secp256k1PointY` | Native circuits and witnesses |
| `secp256r1PointX` | Native circuits and witnesses |
| `secp256r1PointY` | Native circuits and witnesses |
| `curve25519PointX` | Native circuits and witnesses |
| `curve25519PointY` | Native circuits and witnesses |
| `ownPublicKey` | Native circuits and witnesses |
| `serialize` | Inline entries |
| `deserialize` | Inline entries |

## Builtin types — 6/6 covered

Declared in `parser.ss — keywordDataTypes`.

| name | first usage | uses |
|---|---|---:|
| `Boolean` | [`test-contracts/keywords/assert/old_statement_syntax/assert_old_statement_syntax.compact:21`](../../test-contracts/keywords/assert/old_statement_syntax/assert_old_statement_syntax.compact#L21) | 145 |
| `Bytes` | [`test-contracts/keywords/circuit/duplicate_definitions_unused/circuit_duplicate_definitions_unused.compact:16`](../../test-contracts/keywords/circuit/duplicate_definitions_unused/circuit_duplicate_definitions_unused.compact#L16) | 472 |
| `Field` | [`test-contracts/keywords/assert/in_untaken_branch/assert_in_untaken_branch.compact:16`](../../test-contracts/keywords/assert/in_untaken_branch/assert_in_untaken_branch.compact#L16) | 512 |
| `Opaque` | [`test-contracts/keywords/reserved/future/delete_as_identifier/reserved_future_delete_as_identifier.compact:16`](../../test-contracts/keywords/reserved/future/delete_as_identifier/reserved_future_delete_as_identifier.compact#L16) | 4 |
| `Uint` | [`test-contracts/keywords/circuit/duplicate_definitions_unused/circuit_duplicate_definitions_unused.compact:16`](../../test-contracts/keywords/circuit/duplicate_definitions_unused/circuit_duplicate_definitions_unused.compact#L16) | 231 |
| `Vector` | [`test-contracts/keywords/circuit/overload_ambiguous_by_widening/circuit_overload_ambiguous_by_widening.compact:16`](../../test-contracts/keywords/circuit/overload_ambiguous_by_widening/circuit_overload_ambiguous_by_widening.compact#L16) | 146 |

## Standard library circuits — 21/33 covered

Declared in `shipped Compact libraries — export circuit`.

| name | first usage | uses |
|---|---|---:|
| `some` | [`test-contracts/keywords/import/stdlib_requires_import/import_stdlib_requires_import.compact:18`](../../test-contracts/keywords/import/stdlib_requires_import/import_stdlib_requires_import.compact#L18) | 1 |
| `none` | [`test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact:30`](../../test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact#L30) | 2 |
| `left` | [`test-contracts/keywords/constructor/cannot_call_kernel_self_as_unshielded_recipient/constructor_cannot_call_kernel_self_as_unshielded_recipient.compact:22`](../../test-contracts/keywords/constructor/cannot_call_kernel_self_as_unshielded_recipient/constructor_cannot_call_kernel_self_as_unshielded_recipient.compact#L22) | 2 |
| `right` | [`test-contracts/keywords/constructor/cannot_call_kernel_self_as_shielded_recipient/constructor_cannot_call_kernel_self_as_shielded_recipient.compact:23`](../../test-contracts/keywords/constructor/cannot_call_kernel_self_as_shielded_recipient/constructor_cannot_call_kernel_self_as_shielded_recipient.compact#L23) | 3 |
| `merkleTreePathRoot` | **no fixture** | 0 |
| `merkleTreePathRootNoLeafHash` | **no fixture** | 0 |
| `nativeToken` | **no fixture** | 0 |
| `tokenType` | **no fixture** | 0 |
| `mintShieldedToken` | [`test-contracts/keywords/constructor/cannot_call_kernel_self_as_shielded_recipient/constructor_cannot_call_kernel_self_as_shielded_recipient.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_self_as_shielded_recipient/constructor_cannot_call_kernel_self_as_shielded_recipient.compact#L19) | 7 |
| `evolveNonce` | **no fixture** | 0 |
| `shieldedBurnAddress` | **no fixture** | 0 |
| `receiveShielded` | [`test-contracts/keywords/constructor/cannot_call_receive_shielded/constructor_cannot_call_receive_shielded.compact:19`](../../test-contracts/keywords/constructor/cannot_call_receive_shielded/constructor_cannot_call_receive_shielded.compact#L19) | 1 |
| `sendShielded` | [`test-contracts/keywords/constructor/cannot_call_send_shielded/constructor_cannot_call_send_shielded.compact:19`](../../test-contracts/keywords/constructor/cannot_call_send_shielded/constructor_cannot_call_send_shielded.compact#L19) | 1 |
| `sendImmediateShielded` | [`test-contracts/keywords/constructor/cannot_call_send_immediate_shielded/constructor_cannot_call_send_immediate_shielded.compact:19`](../../test-contracts/keywords/constructor/cannot_call_send_immediate_shielded/constructor_cannot_call_send_immediate_shielded.compact#L19) | 1 |
| `mergeCoin` | [`test-contracts/keywords/constructor/cannot_call_merge_coin/constructor_cannot_call_merge_coin.compact:19`](../../test-contracts/keywords/constructor/cannot_call_merge_coin/constructor_cannot_call_merge_coin.compact#L19) | 1 |
| `mergeCoinImmediate` | [`test-contracts/keywords/constructor/cannot_call_merge_coin_immediate/constructor_cannot_call_merge_coin_immediate.compact:19`](../../test-contracts/keywords/constructor/cannot_call_merge_coin_immediate/constructor_cannot_call_merge_coin_immediate.compact#L19) | 1 |
| `blockTimeLt` | [`test-contracts/keywords/constructor/cannot_call_block_time_lt/constructor_cannot_call_block_time_lt.compact:19`](../../test-contracts/keywords/constructor/cannot_call_block_time_lt/constructor_cannot_call_block_time_lt.compact#L19) | 1 |
| `blockTimeGte` | [`test-contracts/keywords/constructor/cannot_call_block_time_gte/constructor_cannot_call_block_time_gte.compact:19`](../../test-contracts/keywords/constructor/cannot_call_block_time_gte/constructor_cannot_call_block_time_gte.compact#L19) | 1 |
| `blockTimeGt` | [`test-contracts/keywords/constructor/cannot_call_block_time_gt/constructor_cannot_call_block_time_gt.compact:19`](../../test-contracts/keywords/constructor/cannot_call_block_time_gt/constructor_cannot_call_block_time_gt.compact#L19) | 1 |
| `blockTimeLte` | [`test-contracts/keywords/constructor/cannot_call_block_time_lte/constructor_cannot_call_block_time_lte.compact:19`](../../test-contracts/keywords/constructor/cannot_call_block_time_lte/constructor_cannot_call_block_time_lte.compact#L19) | 1 |
| `mintUnshieldedToken` | [`test-contracts/keywords/constructor/cannot_call_kernel_self_as_unshielded_recipient/constructor_cannot_call_kernel_self_as_unshielded_recipient.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_self_as_unshielded_recipient/constructor_cannot_call_kernel_self_as_unshielded_recipient.compact#L19) | 7 |
| `sendUnshielded` | [`test-contracts/keywords/constructor/cannot_call_send_unshielded/constructor_cannot_call_send_unshielded.compact:19`](../../test-contracts/keywords/constructor/cannot_call_send_unshielded/constructor_cannot_call_send_unshielded.compact#L19) | 1 |
| `receiveUnshielded` | [`test-contracts/keywords/constructor/cannot_call_receive_unshielded/constructor_cannot_call_receive_unshielded.compact:19`](../../test-contracts/keywords/constructor/cannot_call_receive_unshielded/constructor_cannot_call_receive_unshielded.compact#L19) | 1 |
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

## Standard library structs — 10/15 covered

Declared in `shipped Compact libraries — export struct`.

| name | first usage | uses |
|---|---|---:|
| `Maybe` | [`test-contracts/keywords/import/stdlib_requires_import/import_stdlib_requires_import.compact:17`](../../test-contracts/keywords/import/stdlib_requires_import/import_stdlib_requires_import.compact#L17) | 7 |
| `Either` | [`test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact:21`](../../test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact#L21) | 17 |
| `MerkleTreeDigest` | **no fixture** | 0 |
| `MerkleTreePathEntry` | **no fixture** | 0 |
| `MerkleTreePath` | **no fixture** | 0 |
| `ContractAddress` | [`test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact:21`](../../test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact#L21) | 13 |
| `ShieldedCoinInfo` | [`test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact:20`](../../test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact#L20) | 5 |
| `QualifiedShieldedCoinInfo` | [`test-contracts/keywords/constructor/cannot_call_create_zswap_input/constructor_cannot_call_create_zswap_input.compact:19`](../../test-contracts/keywords/constructor/cannot_call_create_zswap_input/constructor_cannot_call_create_zswap_input.compact#L19) | 5 |
| `ZswapCoinPublicKey` | [`test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact:21`](../../test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact#L21) | 10 |
| `ShieldedSendResult` | **no fixture** | 0 |
| `UserAddress` | [`test-contracts/keywords/constructor/cannot_call_kernel_claim_unshielded_coin_spend/constructor_cannot_call_kernel_claim_unshielded_coin_spend.compact:21`](../../test-contracts/keywords/constructor/cannot_call_kernel_claim_unshielded_coin_spend/constructor_cannot_call_kernel_claim_unshielded_coin_spend.compact#L21) | 3 |
| `JubjubSchnorrSignature` | **no fixture** | 0 |
| `Secp256k1EcdsaSignature` | [`test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact:40`](../../test-contracts/stdlib/secp256k1/bitcoin_kat/secp256k1_bitcoin_kat.compact#L40) | 12 |
| `Secp256r1EcdsaSignature` | [`test-contracts/stdlib/secp256r1/ecdsa_verify/secp256r1_ecdsa_verify.compact:31`](../../test-contracts/stdlib/secp256r1/ecdsa_verify/secp256r1_ecdsa_verify.compact#L31) | 13 |
| `Ed25519Signature` | [`test-contracts/stdlib/curve25519/slow/verify_sequential/curve25519_verify_sequential.compact:27`](../../test-contracts/stdlib/curve25519/slow/verify_sequential/curve25519_verify_sequential.compact#L27) | 27 |

## Ledger ADT operations — 26/62 covered

Declared in `compiler sources — declare-ledger-adt`.

| name | first usage | uses |
|---|---|---:|
| `Kernel.claimZswapNullifier` | [`test-contracts/keywords/constructor/cannot_call_kernel_claim_zswap_nullifier/constructor_cannot_call_kernel_claim_zswap_nullifier.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_claim_zswap_nullifier/constructor_cannot_call_kernel_claim_zswap_nullifier.compact#L19) | 1 |
| `Kernel.claimZswapCoinSpend` | [`test-contracts/keywords/constructor/cannot_call_kernel_claim_zswap_coin_spend/constructor_cannot_call_kernel_claim_zswap_coin_spend.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_claim_zswap_coin_spend/constructor_cannot_call_kernel_claim_zswap_coin_spend.compact#L19) | 1 |
| `Kernel.claimZswapCoinReceive` | [`test-contracts/keywords/constructor/cannot_call_kernel_claim_zswap_coin_receive/constructor_cannot_call_kernel_claim_zswap_coin_receive.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_claim_zswap_coin_receive/constructor_cannot_call_kernel_claim_zswap_coin_receive.compact#L19) | 1 |
| `Kernel.claimContractCall` | [`test-contracts/keywords/constructor/cannot_call_kernel_claim_contract_call/constructor_cannot_call_kernel_claim_contract_call.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_claim_contract_call/constructor_cannot_call_kernel_claim_contract_call.compact#L19) | 1 |
| `Kernel.checkpoint` | [`test-contracts/keywords/constructor/cannot_call_kernel_checkpoint/constructor_cannot_call_kernel_checkpoint.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_checkpoint/constructor_cannot_call_kernel_checkpoint.compact#L19) | 1 |
| `Kernel.mintShielded` | [`test-contracts/keywords/constructor/cannot_call_kernel_mint_shielded/constructor_cannot_call_kernel_mint_shielded.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_mint_shielded/constructor_cannot_call_kernel_mint_shielded.compact#L19) | 1 |
| `Kernel.self` | [`test-contracts/keywords/constructor/cannot_call_kernel_self_as_shielded_recipient/constructor_cannot_call_kernel_self_as_shielded_recipient.compact:23`](../../test-contracts/keywords/constructor/cannot_call_kernel_self_as_shielded_recipient/constructor_cannot_call_kernel_self_as_shielded_recipient.compact#L23) | 3 |
| `Kernel.caller` | **no fixture** | 0 |
| `Kernel.mintUnshielded` | [`test-contracts/keywords/constructor/cannot_call_kernel_mint_unshielded/constructor_cannot_call_kernel_mint_unshielded.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_mint_unshielded/constructor_cannot_call_kernel_mint_unshielded.compact#L19) | 1 |
| `Kernel.claimUnshieldedCoinSpend` | [`test-contracts/keywords/constructor/cannot_call_kernel_claim_unshielded_coin_spend/constructor_cannot_call_kernel_claim_unshielded_coin_spend.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_claim_unshielded_coin_spend/constructor_cannot_call_kernel_claim_unshielded_coin_spend.compact#L19) | 1 |
| `Kernel.incUnshieldedOutputs` | [`test-contracts/keywords/constructor/cannot_call_kernel_inc_unshielded_outputs/constructor_cannot_call_kernel_inc_unshielded_outputs.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_inc_unshielded_outputs/constructor_cannot_call_kernel_inc_unshielded_outputs.compact#L19) | 1 |
| `Kernel.incUnshieldedInputs` | [`test-contracts/keywords/constructor/cannot_call_kernel_inc_unshielded_inputs/constructor_cannot_call_kernel_inc_unshielded_inputs.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_inc_unshielded_inputs/constructor_cannot_call_kernel_inc_unshielded_inputs.compact#L19) | 1 |
| `Kernel.balance` | **no fixture** | 0 |
| `Kernel.balanceLessThan` | **no fixture** | 0 |
| `Kernel.balanceGreaterThan` | **no fixture** | 0 |
| `Kernel.blockTimeLessThan` | [`test-contracts/keywords/constructor/cannot_call_kernel_block_time_less_than/constructor_cannot_call_kernel_block_time_less_than.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_block_time_less_than/constructor_cannot_call_kernel_block_time_less_than.compact#L19) | 1 |
| `Kernel.blockTimeGreaterThan` | [`test-contracts/keywords/constructor/cannot_call_kernel_block_time_greater_than/constructor_cannot_call_kernel_block_time_greater_than.compact:19`](../../test-contracts/keywords/constructor/cannot_call_kernel_block_time_greater_than/constructor_cannot_call_kernel_block_time_greater_than.compact#L19) | 1 |
| `Cell.read` | [`test-contracts/keywords/type/new_type_of_adt/type_new_type_of_adt.compact:25`](../../test-contracts/keywords/type/new_type_of_adt/type_new_type_of_adt.compact#L25) | 1 |
| `Cell.write` | **no fixture** | 0 |
| `Cell.resetToDefault` | **no fixture** | 0 |
| `Counter.read` | [`test-contracts/keywords/const/initializer_side_effects/const_initializer_side_effects.compact:22`](../../test-contracts/keywords/const/initializer_side_effects/const_initializer_side_effects.compact#L22) | 2 |
| `Counter.lessThan` | **no fixture** | 0 |
| `Counter.increment` | [`test-contracts/keywords/const/initializer_side_effects/const_initializer_side_effects.compact:22`](../../test-contracts/keywords/const/initializer_side_effects/const_initializer_side_effects.compact#L22) | 14 |
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

## Event types — 1/11 covered

Declared in `compiler sources — declare-event-type`.

| name | first usage | uses |
|---|---|---:|
| `ShieldedSpend` | [`test-contracts/keywords/constructor/cannot_emit_via_fold/constructor_cannot_emit_via_fold.compact:19`](../../test-contracts/keywords/constructor/cannot_emit_via_fold/constructor_cannot_emit_via_fold.compact#L19) | 6 |
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

## Native circuits and witnesses — 6/27 covered

Declared in `compiler sources — declare-native-entry`.

| name | first usage | uses |
|---|---|---:|
| `transientHash` | **no fixture** | 0 |
| `transientCommit` | **no fixture** | 0 |
| `persistentHash` | [`test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input_derived_point/jubjub_scalar_keygen_without_jubjub_input_derived_point.compact:21`](../../test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input_derived_point/jubjub_scalar_keygen_without_jubjub_input_derived_point.compact#L21) | 61 |
| `persistentCommit` | **no fixture** | 0 |
| `degradeToTransient` | [`test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input_derived_point/jubjub_scalar_keygen_without_jubjub_input_derived_point.compact:21`](../../test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input_derived_point/jubjub_scalar_keygen_without_jubjub_input_derived_point.compact#L21) | 2 |
| `upgradeFromTransient` | **no fixture** | 0 |
| `keccak256` | [`test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input/jubjub_scalar_keygen_without_jubjub_input.compact:21`](../../test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input/jubjub_scalar_keygen_without_jubjub_input.compact#L21) | 66 |
| `sha512` | **no fixture** | 0 |
| `neg` | **no fixture** | 0 |
| `inv` | **no fixture** | 0 |
| `jubjubPointX` | **no fixture** | 0 |
| `jubjubPointY` | **no fixture** | 0 |
| `ecAdd` | **no fixture** | 0 |
| `ecNeg` | **no fixture** | 0 |
| `ecMul` | **no fixture** | 0 |
| `ecMulGenerator` | [`test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input_derived_point/jubjub_scalar_keygen_without_jubjub_input_derived_point.compact:21`](../../test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input_derived_point/jubjub_scalar_keygen_without_jubjub_input_derived_point.compact#L21) | 2 |
| `hashToCurve` | **no fixture** | 0 |
| `constructJubjubPoint` | **no fixture** | 0 |
| `secp256k1PointX` | **no fixture** | 0 |
| `secp256k1PointY` | **no fixture** | 0 |
| `secp256r1PointX` | **no fixture** | 0 |
| `secp256r1PointY` | **no fixture** | 0 |
| `curve25519PointX` | **no fixture** | 0 |
| `curve25519PointY` | **no fixture** | 0 |
| `ownPublicKey` | **no fixture** | 0 |
| `createZswapInput` | [`test-contracts/keywords/constructor/cannot_call_create_zswap_input/constructor_cannot_call_create_zswap_input.compact:19`](../../test-contracts/keywords/constructor/cannot_call_create_zswap_input/constructor_cannot_call_create_zswap_input.compact#L19) | 1 |
| `createZswapOutput` | [`test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact:19`](../../test-contracts/keywords/constructor/cannot_call_create_zswap_output/constructor_cannot_call_create_zswap_output.compact#L19) | 1 |

## Native types — 11/11 covered

Declared in `compiler sources — declare-native-type`.

| name | first usage | uses |
|---|---|---:|
| `JubjubScalar` | [`test-contracts/stdlib/jubjub/scalar/casts/to_boolean/jubjub_scalar_casts_to_boolean.compact:20`](../../test-contracts/stdlib/jubjub/scalar/casts/to_boolean/jubjub_scalar_casts_to_boolean.compact#L20) | 12 |
| `JubjubPoint` | [`test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input_derived_point/jubjub_scalar_keygen_without_jubjub_input_derived_point.compact:19`](../../test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input_derived_point/jubjub_scalar_keygen_without_jubjub_input_derived_point.compact#L19) | 3 |
| `Curve25519Base` | [`test-contracts/stdlib/curve25519/base/casts/to_boolean/curve25519_base_casts_to_boolean.compact:20`](../../test-contracts/stdlib/curve25519/base/casts/to_boolean/curve25519_base_casts_to_boolean.compact#L20) | 8 |
| `Curve25519Scalar` | [`test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact:20`](../../test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact#L20) | 10 |
| `Curve25519Point` | [`test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact:18`](../../test-contracts/stdlib/curve25519/default/maybe_either/curve25519_default_maybe_either.compact#L18) | 30 |
| `Secp256k1Base` | [`test-contracts/stdlib/secp256k1/base/casts/to_boolean/secp256k1_base_casts_to_boolean.compact:20`](../../test-contracts/stdlib/secp256k1/base/casts/to_boolean/secp256k1_base_casts_to_boolean.compact#L20) | 5 |
| `Secp256k1Scalar` | [`test-contracts/stdlib/foreign_field/self_subtract/foreign_field_self_subtract.compact:18`](../../test-contracts/stdlib/foreign_field/self_subtract/foreign_field_self_subtract.compact#L18) | 8 |
| `Secp256k1Point` | [`test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input/jubjub_scalar_keygen_without_jubjub_input.compact:19`](../../test-contracts/stdlib/jubjub/scalar/keygen_without_jubjub_input/jubjub_scalar_keygen_without_jubjub_input.compact#L19) | 16 |
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
