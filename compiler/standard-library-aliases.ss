;;; This file is part of Compact.
;;; Copyright (C) 2025 Midnight Foundation
;;; SPDX-License-Identifier: Apache-2.0
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;; 	http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

(library (standard-library-aliases)
  (export native-aliases stdlib-circuit-aliases stdlib-struct-field-aliases ledger-op-aliases)
  (import (chezscheme))

  (define (to-symbol-hashtable alist)
    (let ([ht (make-hashtable symbol-hash eq?)])
      (for-each
        (lambda (a) (hashtable-set! ht (car a) (cdr a)))
        alist)
      ht))

  (define native-aliases
    (to-symbol-hashtable
      '((transient_hash . transientHash)
        (transient_commit . transientCommit)
        (persistent_hash . persistentHash)
        (persistent_commit . persistentCommit)
        (degrade_to_transient . degradeToTransient)
        (upgrade_from_transient . upgradeFromTransient)
        (ec_add . ecAdd)
        (ec_mul . ecMul)
        (ec_mul_generator . ecMulGenerator)
        (hash_to_curve . hashToCurve)
        (own_public_key . ownPublicKey)
        (create_zswap_input . createZswapInput)
        (create_zswap_output . createZswapOutput))))

  (define stdlib-circuit-aliases
    '((transient_hash . transientHash)
      (transient_commit . transientCommit)
      (persistent_hash . persistentHash)
      (persistent_commit . persistentCommit)
      (degrade_to_transient . degradeToTransient)
      (upgrade_from_transient . upgradeFromTransient)
      (ec_add . ecAdd)
      (ec_mul . ecMul)
      (ec_mul_generator . ecMulGenerator)
      (hash_to_curve . hashToCurve)
      (merkle_tree_path_root . merkleTreePathRoot)
      (merkle_tree_path_root_no_leaf_hash . merkleTreePathRootNoLeafHash)
      (native_token . nativeToken)
      (own_public_key . ownPublicKey)
      (create_zswap_input . createZswapInput)
      (create_zswap_output . createZswapOutput)
      (token_type . tokenType)
      (mint_token . mintShieldedToken)
      (evolve_nonce . evolveNonce)
      (burn_address . shieldedBurnAddress)
      (send_immediate . sendImmediateShielded)
      (merge_coin . mergeCoin)
      (merge_coin_immediate . mergeCoinImmediate)
      (mintToken . mintShieldedToken)
      (burnAddress . shieldedBurnAddress)
      (receive . receiveShielded)
      (send . sendShielded)
      (sendImmediate . sendImmediateShielded)))

  (define stdlib-struct-field-aliases
    '(
      #| delaying these replacements (in standard-library.compact and elsewhere) until we can coordinate the changes with the onchain runtime
      ((Maybe . is_some) . isSome)
      ((Either . is_left) . isLeft)
      ((MerkleTreePathEntry . goes_left) . goesLeft)
      ((LeafPreimage . domain_sep) . domainSep)
      ((QualifiedShieldedCoinInfo . mt_index) . mtIndex)
      |#
      ))

  (define ledger-op-aliases
    (to-symbol-hashtable
      '((check_root . checkRoot)
        (claim_contract_call . claimContractCall)
        (claim_zswap_coin_receive . claimZswapCoinReceive)
        (claim_zswap_coin_spend . claimZswapCoinSpend)
        (claim_zswap_nullifier . claimZswapNullifier)
        (insert_coin . insertCoin)
        (insert_default . insertDefault)
        (insert_hash . insertHash)
        (insert_hash_index . insertHashIndex)
        (insert_index . insertIndex)
        (insert_index_default . insertIndexDefault)
        (is_empty . isEmpty)
        (is_full . isFull)
        (less_than . lessThan)
        (pop_front . popFront)
        (push_front . pushFront)
        (push_front_coin . pushFrontCoin)
        (reset_history . resetHistory)
        (reset_to_default . resetToDefault)
        (write_coin . writeCoin))))
)
