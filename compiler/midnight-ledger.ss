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

;; define-ledger-type establishes local syntax bindings that are visible only in this file.
;; syntax: (declare-ledger-type type-name (type-param-name ...) compact-type rust-type)
;; Within compact-type, each type-param-name is bound to the compact-type of the corresponding parameter.

(declare-ledger-type Boolean ()
  (primitive-type Boolean)
  "bool")

(declare-ledger-type Field ()
  (primitive-type Field)
  "Fr")

(declare-ledger-type Void ()
  (primitive-type Void)
  "()")

(declare-ledger-type Bytes32 ()
  (primitive-type Bytes 32)
  "HashOutput")

(declare-ledger-type Uint16 ()
  (primitive-type Uint 16)
  "u16")

(declare-ledger-type Uint64 ()
  (primitive-type Uint 64)
  "u64")

(declare-ledger-type Uint128 ()
  (primitive-type Uint 128)
  "u128")

(declare-ledger-type ShieldedCoinInfo ()
  (type-ref ShieldedCoinInfo)
  "ShieldedCoinInfo")

(declare-ledger-type QualifiedShieldedCoinInfo ()
  (type-ref QualifiedShieldedCoinInfo)
  "QualifiedShieldedCoinInfo")

(declare-ledger-type MerkleTreeDigest ()
  (type-ref MerkleTreeDigest) 
  "MerkleTreeDigest")

(declare-ledger-type ContractAddress ()
  (type-ref ContractAddress) 
  "ContractAddress")

(declare-ledger-type UserAddress ()
  (type-ref UserAddress)
  "UserAddress")

(declare-ledger-type ZswapCoinPublicKey ()
  (type-ref ZswapCoinPublicKey) 
  "ZswapCoinPublicKey")

(declare-ledger-type ShieldedRecipient ()
  (type-ref Either
            (type-ref ZswapCoinPublicKey)
            (type-ref ContractAddress))
  "ShieldedRecipient")

(declare-ledger-type UnshieldedRecipient ()
  (type-ref Either
            (type-ref ContractAddress)
            (type-ref UserAddress))
  "UnshieldedRecipient")

(declare-ledger-type TokenType ()
  (type-ref Either
            (primitive-type Bytes 32)
            (primitive-type Bytes 32))
  "TokenType")

(declare-ledger-type Maybe (a)
  (type-ref Maybe a)
  "Option<_>")

;; declare-ledger-adt adds an ADT declaration to the compiler's internal table of ADTs.
;; syntax:
;;   (declare-ledger-adt ADT-name (ADT-arg-name ...) description (initial-value init) clause ...)
;; clause:
;;   (function class function-name ([input-name input-type] ...) result-type
;;     description
;;     (vm-op ...))
;;   (when scheme-expression clause ...)
;; op:
;;   (op-name [op-arg-name op-arg-value] ...)
;;
;; class is one of:
;;   read       information is extracted from the ledger
;;   write      information is written to the ledger
;;   update     information is updated in the ledger
;;   remove     information is removed from the ledger
;;   js-only    callable only from javascript
;;
;; when class is js-only, result-type and vm-op are treated as interpolated
;; javascript string instead.
;;
;; init is interpreted as if it were an argument to an operation
;;
;; where e.g. (addi [immediate 5]) gets encoded at runtime to
;;   { addi: { immediate: 5 } }
;; single ops, e.g. '(pop)' get encoded to a string:
;;   "pop"
;; ops will use the following symbolic placeholders:
;; values may use ADT-arg-name, type-arg-name
;;
;; inside operation arguments, the following scheme primitives are used, and
;; should be evaluated at compile-time.  the one exception to this is that the
;; arguments to + might not be constant, in which case the addition should be
;; performed at run time.
;; - list, reverse, car, cdr, length
;; - +, *, expt, add1, sub1
;; - void (standing in for null values)
;;
;; The following variables should be instantiated at compile time to the context
;; where the form is being used:
;; - f, the path to the field being operated on, and
;; - f-cached, a boolean indicating if f is guaranteed to be in cache.
;;
;; A path is a list of either aligned value instances, or the symbol 'stack.
;; Aligned value literals are created with the (align value bytes) literal, which
;; should emit code generating this literal AlignedValue (of a single atom) at runtime.
;;
;; Similarly, the following correspond to state initializers at runtime:
;; - (state-value 'null) initializes a null value
;; - (state-value 'cell aligned-value) initializes a state cell with the given value
;; - (state-value 'map ([key value] ...)) initializes a map with given key-value pairs
;; - (state-value 'merkle-tree ([key value] ...)) initializes a bounded merkle tree with
;;   given key-value pairs (Uint64 indexes as keys, and Bytes32 hash values)
;; - (state-value 'array (val ...)) initializes an array with given values
;;
;; Finally, the following runtime functions should emit code to the corresponding runtime effect
;; - (rt-aligned-concat value ...) concatenate the value ... AlignedValues into one.
;; - (rt-null type) output the default instance of the type
;; - (rt-max-sizeof type) output the maximum serialized size of a value of the given type
;; - (rt-value->int aligned-value) outputs an integer represented by an aligned-value
;; - (rt-coin-commit coin) outputs a coin commitment
;; - (rt-leaf-hash value) outputs the leaf to be placed in a merkle tree for value
;;
;; type-arg-name must be one of ADT-arg-name or a defined ledger type.

(declare-ledger-adt Kernel ()
  "a special ADT defining various built-in operations and valid only as a top-level ADT type"
  (initial-value #f)
  (function update claimZswapNullifier
            ([nul Bytes32 (discloses "a link between a claim of nullifier and the coin with the nullifier given by")])
            Void
    "Requires the presence of a nullifier in the containing transaction and \
    that no other call claims it."
    ((swap [n 0])
     (idx [cached #t] [pushPath #t] [path (list (align 0 1))])
     (push [storage #f] [value (state-value 'cell nul)])
     (push [storage #f] [value (state-value 'null)])
     (ins [cached #t] [n 2])
     (swap [n 0])))
  (function update claimZswapCoinSpend
            ([note Bytes32 (discloses "a link between a coin spend and the coin with the commitment given by")])
            Void
    "Requires the presence of a commitment in the containing transaction and \
    that no other call claims it as a spend."
    ((swap [n 0])
     (idx [cached #t] [pushPath #t] [path (list (align 2 1))])
     (push [storage #f] [value (state-value 'cell note)])
     (push [storage #f] [value (state-value 'null)])
     (ins [cached #t] [n 2])
     (swap [n 0])))
  (function update claimZswapCoinReceive
            ([note Bytes32 (discloses "a link between a coin receive and the coin with the commitment given by")])
            Void
    "Requires the presence of a commitment in the containing transaction and \
    that no other call claims it as a receive."
    ((swap [n 0])
     (idx [cached #t] [pushPath #t] [path (list (align 1 1))])
     (push [storage #f] [value (state-value 'cell note)])
     (push [storage #f] [value (state-value 'null)])
     (ins [cached #t] [n 2])
     (swap [n 0])))
  (function update claimContractCall
            ([addr Bytes32 (discloses "the address of a contract being called given by")]
             [entry_point Bytes32 (discloses "the hash of the contract's circuit being called given by")]
             [comm Field (discloses nothing)])
            Void
    "Require the presence of another contract call in the containing \
    transaction, with a match address, entry point hash, and communication \
    commitment, that is not claimed by any other call."
    ((swap [n 0])
     (idx [cached #t] [pushPath #t] [path (list (align 3 1))])
     (dup [n 0])
     (size)
     (push [storage #f] [value (state-value 'cell (rt-aligned-concat addr entry_point comm))])
     (concat [cached #t] [n 160])
     (push [storage #f] [value (state-value 'null)])
     (ins [cached #t] [n 2])
     (swap [n 0])))
  (function update checkpoint () Void
    "Marks all execution up to this point as being a single atomic unit, \
    allowing partial transaction failures to be split across it."
    ((ckpt)))
  (function update mintShielded
            ([domain_sep Bytes32 (discloses "the domain separator of the token being minted given by")]
             [amount Uint64 (discloses "the value of a token mint given by")])
            Void
    "Mints a given amount of shielded coins with a token type derived from the \
    contract's address, and a given domain separator."
    ;; [context, effects, state]
    ((swap [n 0])
    ;; [context, state, effects]
    (idx [cached #t] [pushPath #t] [path (list (align 4 1))])
    ;; [context, state, effects, path, shielded_mints]
    (push [storage #f] [value (state-value 'cell domain_sep)])
    ;; [context, state, effects, path, shielded_mints, domain_sep]
    (dup [n 1])
    ;; [context, state, effects, path, shielded_mints, domain_sep, shielded_mints]
    (dup [n 1])
    ;; [context, state, effects, path, shielded_mints, domain_sep, shielded_mints, domain_sep]
    (member)
    ;; [context, state, effects, path, shielded_mints, domain_sep, is_member]
    (push [storage #f] [value (state-value 'cell amount)])
    ;; [context, state, effects, path, shielded_mints, domain_sep, is_member, amount]
    (swap [n 0])
    ;; [context, state, effects, path, shielded_mints, domain_sep, amount, is_member]
    (neg)
    ;; [context, state, effects, path, shielded_mints, domain_sep, amount, !is_member]
    (branch [skip 4])
    ;; [context, state, effects, path, shielded_mints, domain_sep, amount]
    (dup [n 2])
    ;; [context, state, effects, path, shielded_mints, domain_sep, amount, shielded_mints]
    (dup [n 2])
    ;; [context, state, effects, path, shielded_mints, domain_sep, amount, shielded_mints, domain_sep]
    (idx [cached #t] [pushPath #f] [path (list 'stack)])
    ;; [context, state, effects, path, shielded_mints, domain_sep, amount, existing_amount]
    (add)
    ;; [context, state, effects, path, shielded_mints, domain_sep, amount | existing_amount + amount]
    (ins [cached #t] [n 2])
    ;; [context, state, effects]
    (swap [n 0])
    ;; [context, effects, state]
    ))
  (function read self () ContractAddress
    "Returns the current contract's address.  ContractAddress is defined in CompactStandardLibrary."
    ((dup [n 2])
     (idx [cached #t] [pushPath #f] [path (list (align 0 1))])
     (popeq [cached #t] [result (void)])))
  (function update mintUnshielded
            ([domain_sep Bytes32 (discloses "the domain separator of the unshielded token being minted given by")]
             [amount Uint64 (discloses "the amount of the unshielded token being minted given by")])
            Void
    "Mints a given amount of unshielded coins with a token type derived from the \
    contract's address, and a given domain separator."
    ;; [context, effects, state]
    ((swap [n 0])
    ;; [context, state, effects]
    (idx [cached #t] [pushPath #t] [path (list (align 5 1))])
    ;; [context, state, effects, path, unshielded_mints]
    (push [storage #f] [value (state-value 'cell domain_sep)])
    ;; [context, state, effects, path, unshielded_mints, domain_sep]
    (dup [n 1])
    ;; [context, state, effects, path, unshielded_mints, domain_sep, unshielded_mints]
    (dup [n 1])
    ;; [context, state, effects, path, unshielded_mints, domain_sep, unshielded_mints, domain_sep]
    (member)
    ;; [context, state, effects, path, unshielded_mints, domain_sep, is_member]
    (push [storage #f] [value (state-value 'cell amount)])
    ;; [context, state, effects, path, unshielded_mints, domain_sep, is_member, amount]
    (swap [n 0])
    ;; [context, state, effects, path, unshielded_mints, domain_sep, amount, is_member]
    (neg)
    ;; [context, state, effects, path, unshielded_mints, domain_sep, amount, !is_member]
    (branch [skip 4])
    ;; [context, state, effects, path, unshielded_mints, domain_sep, amount]
    (dup [n 2])
    ;; [context, state, effects, path, unshielded_mints, domain_sep, amount, unshielded_mints]
    (dup [n 2])
    ;; [context, state, effects, path, unshielded_mints, domain_sep, amount, unshielded_mints, domain_sep]
    (idx [cached #t] [pushPath #f] [path (list 'stack)])
    ;; [context, state, effects, path, unshielded_mints, domain_sep, amount, existing_amount]
    (add)
    ;; [context, state, effects, path, unshielded_mints, domain_sep, amount | existing_amount + amount]
    (ins [cached #t] [n 2])
    ;; [context, state, effects]
    (swap [n 0])
    ;; [context, effects, state]
    ))
  (function update claimUnshieldedCoinSpend
            ([token_type TokenType (discloses "the type of the unshielded token being transferred given by")]
             [address UnshieldedRecipient (discloses "the recipient of the unshielded token being transferred given by")]
             [amount Uint128 (discloses "the amount of the unshielded token being transferred given by")])
            Void
    "Claims an unshielded coin spend - authorizes an unshielded coin of the given token type to be transferred \
    to the given address."
    ;; [context, effects, state]
    ((swap [n 0])
    ;; [context, state, effects]
    (idx [cached #t] [pushPath #t] [path (list (align 8 1))])
    ;; [context, state, effects, path, claimed_unshielded_spends]
    (push [storage #f] [value (state-value 'cell (rt-aligned-concat token_type address))])
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address)]
    (dup [n 1])
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), claimed_unshielded_spends]
    (dup [n 1])
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), claimed_unshielded_spends, (token_type, address)]
    (member)
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), is_member]
    (push [storage #f] [value (state-value 'cell amount)])
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), is_member, amount]
    (swap [n 0])
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), amount, is_member]
    (neg)
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), amount, !is_member]
    (branch [skip 4])
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), amount]
    (dup [n 2])
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), amount, claimed_unshielded_spends]
    (dup [n 2])
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), amount, claimed_unshielded_spends, (token_type, address)]
    (idx [cached #t] [pushPath #f] [path (list 'stack)])
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), amount, existing_amount]
    (add)
    ;; [context, state, effects, path, claimed_unshielded_spends, (token_type, address), amount | existing_amount + amount]
    (ins [cached #t] [n 2])
    ;; [context, state, effects]
    (swap [n 0])
    ;; [context, effects, state]
    ))
  (function update incUnshieldedOutputs
            ([token_type TokenType (discloses "the type of the unshielded token being spent given by")]
             [amount Uint128 (discloses "the amount of the unshielded token being spent given by")])
            Void
    "Increments the unshielded output for the token of the given token type by the given amount - used when sending tokens."
    ;; [context, effects, state]
    ((swap [n 0])
    ;; [context, state, effects]
    (idx [cached #t] [pushPath #t] [path (list (align 7 1))])
    ;; [context, state, effects, path, unshielded_outputs]
    (push [storage #f] [value (state-value 'cell token_type)])
    ;; [context, state, effects, path, unshielded_outputs, token_type]
    (dup [n 1])
    ;; [context, state, effects, path, unshielded_outputs, token_type, unshielded_outputs]
    (dup [n 1])
    ;; [context, state, effects, path, unshielded_outputs, token_type, unshielded_outputs, token_type]
    (member)
    ;; [context, state, effects, path, unshielded_outputs, token_type, is_member]
    (push [storage #f] [value (state-value 'cell amount)])
    ;; [context, state, effects, path, unshielded_outputs, token_type, is_member, amount]
    (swap [n 0])
    ;; [context, state, effects, path, unshielded_outputs, token_type, amount, is_member]
    (neg)
    ;; [context, state, effects, path, unshielded_outputs, token_type, amount, !is_member]
    (branch [skip 4])
    ;; [context, state, effects, path, unshielded_outputs, token_type, amount]
    (dup [n 2])
    ;; [context, state, effects, path, unshielded_outputs, token_type, amount, unshielded_outputs]
    (dup [n 2])
    ;; [context, state, effects, path, unshielded_outputs, token_type, amount, unshielded_outputs, token_type]
    (idx [cached #t] [pushPath #f] [path (list 'stack)])
    ;; [context, state, effects, path, unshielded_outputs, token_type, amount, existing_amount]
    (add)
    ;; [context, state, effects, path, unshielded_outputs, token_type, amount | existing_amount + amount]
    (ins [cached #t] [n 2])
    ;; [context, state, effects]
    (swap [n 0])
    ;; [context, effects, state]
    ))
  (function update incUnshieldedInputs
            ([token_type TokenType (discloses "the type of the unshielded token being received given by")]
             [amount Uint128 (discloses "the amount of the unshielded token being received given by")])
            Void
    "Increments the unshielded input for the token of the given token type by the given amount - used when receiving tokens."
    ;; [context, effects, state]
    ((swap [n 0])
    ;; [context, state, effects]
    (idx [cached #t] [pushPath #t] [path (list (align 6 1))])
    ;; [context, state, effects, path, unshielded_inputs]
    (push [storage #f] [value (state-value 'cell token_type)])
    ;; [context, state, effects, path, unshielded_outputs, token_type]
    (dup [n 1])
    ;; [context, state, effects, path, unshielded_inputs, token_type, unshielded_inputs]
    (dup [n 1])
    ;; [context, state, effects, path, unshielded_inputs, token_type, unshielded_inputs, token_type]
    (member)
    ;; [context, state, effects, path, unshielded_inputs, token_type, is_member]
    (push [storage #f] [value (state-value 'cell amount)])
    ;; [context, state, effects, path, unshielded_inputs, token_type, is_member, amount]
    (swap [n 0])
    ;; [context, state, effects, path, unshielded_inputs, token_type, amount, is_member]
    (neg)
    ;; [context, state, effects, path, unshielded_inputs, token_type, amount, !is_member]
    (branch [skip 4])
    ;; [context, state, effects, path, unshielded_inputs, token_type, amount]
    (dup [n 2])
    ;; [context, state, effects, path, unshielded_inputs, token_type, amount, unshielded_inputs]
    (dup [n 2])
    ;; [context, state, effects, path, unshielded_inputs, token_type, amount, unshielded_inputs, token_type]
    (idx [cached #t] [pushPath #f] [path (list 'stack)])
    ;; [context, state, effects, path, unshielded_inputs, token_type, amount, existing_amount]
    (add)
    ;; [context, state, effects, path, unshielded_inputs, token_type, amount | existing_amount + amount]
    (ins [cached #t] [n 2])
    ;; [context, state, effects]
    (swap [n 0])
    ;; [context, effects, state]
    ))
  (function read balance
            ([token_type TokenType (discloses "the type of the unshielded token having its balanced checked given by")])
            Uint128
    "Returns the current contract's balance of the unshielded token of the given token type. The balance is not updated \
     during contract execution as a result of unshielded sends and receives. It is always fixed to the value provided \
     at the start of execution."
    ;; [context, effects, state]
    ((dup [n 2])
    ;; [context, effects, state, context]
    (idx [cached #t] [pushPath #f] [path (list (align 5 1))])
    ;; [context, effects, state, balances]
    (dup [n 0])
    ;; [context, effects, state, balances]
    (push [storage #f] [value (state-value 'cell token_type)])
    ;; [context, effects, state, balances, balances, token_type]
    (member)
    ;; [context, effects, state, balances, is_member]
    (branch [skip 3])
    ;; [context, effects, state, balances]
    (pop)
    ;; [context, effects, state]
    (push [storage #f] [value (state-value 'cell (align 0 16))])
    ;; [context, effects, state, 0]
    (jmp [skip 1])
    ;; [context, effects, state, balances]
    (idx [cached #t] [pushPath #f] [path (list token_type)])
    ;; [context, effects, state, balance | 0]
    (popeq [cached #t] [result (void)])
    ))
  (function read balanceLessThan
              ([token_type TokenType (discloses "the type of the unshielded token having its balanced checked given by")]
               [amount Uint128 (discloses "the upper bound of the balance of the unshielded token being checked")])
              Boolean
    "Checks whether the current balance of the unshielded token of the given type is less than the given amount."
    ;; [context, effects, state]
    ((dup [n 2])
    ;; [context, effects, state, context]
    (idx [cached #t] [pushPath #f] [path (list (align 5 1))])
    ;; [context, effects, state, balances]
    (dup [n 0])
    ;; [context, effects, state, balances]
    (push [storage #f] [value (state-value 'cell token_type)])
    ;; [context, effects, state, balances, balances, token_type]
    (member)
    ;; [context, effects, state, balances, is_member]
    (branch [skip 3])
    ;; [context, effects, state, balances]
    (pop)
    ;; [context, effects, state]
    (push [storage #f] [value (state-value 'cell (align 0 16))])
    ;; [context, effects, state, 0]
    (jmp [skip 1])
    ;; [context, effects, state, balances]
    (idx [cached #t] [pushPath #f] [path (list token_type)])
    ;; [context, effects, state, balance | 0]
    (push [storage #f] [value (state-value 'cell amount)])
    ;; [context, effects, state, balance | 0, amount]
    (lt)
    ;; [context, effects, state, balance | 0 < amount]
    (popeq [cached #t] [result (void)])
    ;; [context, effects, state]
    ))
  (function read balanceGreaterThan
                ([token_type TokenType (discloses "the type of the unshielded token having its balanced checked given by")]
                 [amount Uint128 (discloses "the lower bound of the balance of the unshielded token being checked")])
                Boolean
    "Checks whether the current balance of the unshielded token of the given type is greater than the given amount."
    ;; [context, effects, state]
    ((push [storage #f] [value (state-value 'cell amount)])
    ;; [context, effects, state, amount]
    (dup [n 3])
    ;; [context, effects, state, amount, context]
    (idx [cached #t] [pushPath #f] [path (list (align 5 1))])
    ;; [context, effects, state, amount, balances]
    (dup [n 0])
    ;; [context, effects, state, amount, balances, balances]
    (push [storage #f] [value (state-value 'cell token_type)])
    ;; [context, effects, state, amount, balances, balances, token_type]
    (member)
    ;; [context, effects, state, amount, balances, is_member]
    (branch [skip 3])
    ;; [context, effects, state, amount, balances]
    (pop)
    ;; [context, effects, state, amount]
    (push [storage #f] [value (state-value 'cell (align 0 16))])
    ;; [context, effects, state, amount, 0]
    (jmp [skip 1])
    ;; [context, effects, state, amount, balances]
    (idx [cached #t] [pushPath #f] [path (list token_type)])
    ;; [context, effects, state, amount, balance | 0]
    (lt)
    ;; [context, effects, state, amount < balance | 0]
    (popeq [cached #t] [result (void)])
    ;; [context, effects, state]
    ))
  (function read blockTimeLessThan
                  ([time Uint64 (discloses "the lower bound of the time being checked")])
                  Boolean
      "Checks whether the current block time (measured in seconds since the Unix epoch) is less than the given amount."
      ;; [context, effects, state]
      ((dup [n 2])
      ;; [context, effects, state, context]
      (idx [cached #t] [pushPath #f] [path (list (align 2 1))])
      ;; [context, effects, state, tblock]
      (push [storage #f] [value (state-value 'cell time)])
      ;; [context, effects, state, tblock, time]
      (lt)
      ;; [context, effects, state, tblock < time]
      (popeq [cached #t] [result (void)])))
  (function read blockTimeGreaterThan
                  ([time Uint64 (discloses "the upper bound of the time being checked")])
                  Boolean
      "Checks whether the current block time (measured in seconds since the Unix epoch) is greater than the given amount."
      ;; [context, effects, state]
      ((push [storage #f] [value (state-value 'cell time)])
      ;; [context, effects, state, time]
      (dup [n 3])
      ;; [context, effects, state, time, context]
      (idx [cached #t] [pushPath #f] [path (list (align 2 1))])
      ;; [context, effects, state, time, tblock]
      (lt)
      ;; [context, effects, state, time < tblock]
      (popeq [cached #t] [result (void)]))))

(declare-ledger-adt Cell ([Type value_type])
  "a single Cell containing a value of type value_type and is used implicitly when the ledger field type is an ordinary Compact type. Programmers cannot write Cell explicitly when declaring a ledger field."
  (initial-value (state-value 'cell (rt-null value_type)))
  (function read read () value_type
    "Returns the current contents of this Cell."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (popeq [cached f-cached] [result (void)])))
  (function write write ([value value_type]) Void
    "Overwrites the content of this Cell with the given value."
    ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
     (push [storage #f] [value (state-value 'cell (car (reverse f)))])
     (push [storage #t] [value (state-value 'cell value)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (suppress-zero (sub1 (length f)))])))
  (function remove resetToDefault () Void
    "Resets this Cell to the default value of its type."
    ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
     (push [storage #f] [value (state-value 'cell (car (reverse f)))])
     (push [storage #t] [value (state-value 'cell (rt-null value_type))])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (suppress-zero (sub1 (length f)))])))
  (when (= value_type QualifiedShieldedCoinInfo)
    (function (update-with-coin-check 0 1) writeCoin ([coin ShieldedCoinInfo] [recipient ShieldedRecipient]) Void
      "Writes a ShieldedCoinInfo to this Cell, which is transformed into a \
      QualifiedShieldedCoinInfo at runtime by looking up the relevant Merkle tree \
      index. This index must have been allocated within the current \
      transaction or this write fails. \
      ShieldedCoinInfo, ContractAddress, Either, and ZswapCoinPublicKey are defined in CompactStandardLibrary."
      ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
       (push [storage #f] [value (state-value 'cell (car (reverse f)))])
       ;; Reach to the context in the stack: past the two pushes above, the
       ;; result, and 2n path items of the idx, and the effects.
       ;; note that if `f` is longer than 5, this exceeds the limit of 15.
       (dup [n (+ 3 (* (sub1 (length f)) 2))])
       (push [storage #f] [value (state-value 'cell (rt-coin-commit coin recipient))])
       (idx [cached #t] [pushPath #f] [path (list (align 1 1) 'stack)])
       (push [storage #f] [value (state-value 'cell coin)])
       (swap [n 0])
       (concat [cached #t] [n 91])
       (ins [cached #f] [n 1])
       (ins [cached #t] [n (suppress-zero (sub1 (length f)))])))))

(declare-ledger-adt Counter ()
  "a simple counter"
  (initial-value (state-value 'cell (align 0 8)))
  (function read read () Uint64
    "Retrieves the current value of the counter."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (popeq [cached #t] [result (void)])))
  (function read lessThan ([threshold Uint64]) Boolean
    "Returns if the counter is less than the given threshold value."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (push [storage #f] [value (state-value 'cell threshold)])
     (lt)
     (popeq [cached #t] [result (void)])))
  (function update increment ([amount Uint16]) Void
    "Increments the counter by the given amount."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (addi [immediate (rt-value->int amount)])
     (ins [cached #t] [n (length f)])))
  (function update decrement ([amount Uint16]) Void
    "Decrements the counter by a given amount. Decrementing below zero \
    results in a run-time error."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (subi [immediate (rt-value->int amount)])
     (ins [cached #t] [n (length f)])))
  ;; Also used to setup initial Counter
  (function remove resetToDefault () Void
    "Resets this Counter to its default value of 0."
    ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
     (push [storage #f] [value (state-value 'cell (car (reverse f)))])
     (push [storage #t] [value (state-value 'cell (align 0 8))])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (suppress-zero (sub1 (length f)))]))))

(declare-ledger-adt Set ([Type value_type])
  "an unbounded set of values of type value_type"
  (initial-value (state-value 'map ()))
  (function remove resetToDefault () Void
    "Resets this Set to the empty set."
    ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
     (push [storage #f] [value (state-value 'cell (car (reverse f)))])
     (push [storage #t] [value (state-value 'map ())])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (suppress-zero (sub1 (length f)))])))
  (function js-only iter () "Iterator<${value_type}>"
    "Iterates over the entries in this Set."
    ("${this}.asMap().keys().map((elem) => ${value_type}.fromValue(elem.value))[Symbol.iterator]()"))
  (function read isEmpty () Boolean
    "Returns whether this Set is the empty set."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (size)
     (push [storage #f] [value (state-value 'cell (align 0 8))])
     (eq)
     (popeq [cached #t] [result (void)])))
  (function read size () Uint64
    "Returns the number of unique entries in this Set."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (size)
     (popeq [cached #t] [result (void)])))
  (function read member ([elem value_type]) Boolean
    "Returns if an element is contained within this Set."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (push [storage #f] [value (state-value 'cell elem)])
     (member)
     (popeq [cached #t] [result (void)])))
  (function update insert ([elem value_type]) Void
    "Updates this Set to include a given element."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (push [storage #f] [value (state-value 'cell elem)])
     (push [storage #t] [value (state-value 'null)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (length f)])))
  (function remove remove ([elem value_type]) Void
    "Update this Set to not include a given element."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (push [storage #f] [value (state-value 'cell elem)])
     (rem [cached #f])
     (ins [cached #t] [n (length f)])))
  (when (= value_type QualifiedShieldedCoinInfo)
    (function (update-with-coin-check 0 1) insertCoin ([coin ShieldedCoinInfo] [recipient ShieldedRecipient]) Void
      "Inserts a ShieldedCoinInfo into this Set, which is transformed into a \
      QualifiedShieldedCoinInfo at runtime by looking up the relevant Merkle tree \
      index. This index must have been allocated within the current \
      transaction or this insertion fails. \
      ShieldedCoinInfo, ContractAddress, Either, and ZswapCoinPublicKey are defined in CompactStandardLibrary."
       ;; [context, effects, state]
       ((idx [cached f-cached] [pushPath #t] [path f])
       ;; [context, effects, state, path, set]
       ;; Get qualified `coin` on the stack
       (dup [n (+ 2 (* (length f) 2))])
       ;; [context, effects, state, path, set, context]
       (push [storage #f] [value (state-value 'cell (rt-coin-commit coin recipient))])
       ;; [context, effects, state, path, set, context, coin_cm]
       (idx [cached #t] [pushPath #f] [path (list (align 1 1) 'stack)])
       ;; [context, effects, state, path, set, coin_idx]
       (push [storage #f] [value (state-value 'cell coin)])
       ;; [context, effects, state, path, set, coin_idx, coin]
       (swap [n 0])
       ;; [context, effects, state, path, set, coin, coin_idx]
       (concat [cached #t] [n 91])
       ;; [context, effects, state, path, set, qualified_coin]
       (push [storage #t] [value (state-value 'null)])
       ;; [context, effects, state, path, set, qualified_coin, null]
       (ins [cached #f] [n 1])
       ;; [context, effects, state, path, set']
       (ins [cached #t] [n (length f)])))))
       ;; [context, effects, state']

(declare-ledger-adt Map ([Type key_type] [ADT/Type value_type])
  "an unbounded set of mappings between values of type key_type and values of type value_type"
  (initial-value (state-value 'map ()))
  (function js-only iter () "Iterator<[${key_type}, ${value_type}]>"
    "Iterates over the key-value pairs contained in this Map."
    ("${this}.asMap().keys().map("
     "  (key) => {"
     "    const value = ${this}.asMap().get(key).asCell();"
     "    return ["
     "      ${key_type}.fromValue(key.value),"
     "      ${value_type}.fromValue(value.value)"
     "    ];"
     "  }"
     ")[Symbol.iterator]()"))
  (function remove resetToDefault () Void
    "Resets this Map to the empty map."
    ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
     (push [storage #f] [value (state-value 'cell (car (reverse f)))])
     (push [storage #t] [value (state-value 'map ())])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (suppress-zero (sub1 (length f)))])))
  (function read isEmpty () Boolean
    "Returns if this Map is the empty map."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (size)
     (push [storage #f] [value (state-value 'cell (align 0 8))])
     (eq)
     (popeq [cached #t] [result (void)])))
  (function read size () Uint64
    "Returns the number of entries in this Map."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (size)
     (popeq [cached #t] [result (void)])))
  (function read member ([key key_type]) Boolean
    "Returns if a key is contained within this Map."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (push [storage #f] [value (state-value 'cell key)])
     (member)
     (popeq [cached #t] [result (void)])))
  (function read lookup ([key key_type]) value_type
    "Looks up the value of a key within this Map. The returned value may be \
    another ADT."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (idx [cached #f] [pushPath #f] [path (list key)])
     (popeq [cached #f] [result (void)])))
  (function update insert ([key key_type] [value value_type]) Void
    "Updates this Map to include a new value at a given key."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (push [storage #f] [value (state-value 'cell key)])
     (push [storage #t] [value (state-value 'ADT value value_type)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (length f)])))
  (function update insertDefault ([key key_type]) Void
    "Updates this Map to include the value type's default value at a given key."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (push [storage #f] [value (state-value 'cell key)])
     (push [storage #t] [value (state-value 'ADT (rt-null value_type) value_type)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (length f)])))
  (function remove remove ([key key_type]) Void
    "Updates this Map to not include a given key."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (push [storage #f] [value (state-value 'cell key)])
     (rem [cached #f])
     (ins [cached #t] [n (length f)])))
  (when (= value_type QualifiedShieldedCoinInfo)
    (function (update-with-coin-check 1 2) insertCoin ([key key_type] [coin ShieldedCoinInfo] [recipient ShieldedRecipient]) Void
      "Inserts a ShieldedCoinInfo into this Map at a given key, where the ShieldedCoinInfo is \
      transformed into a QualifiedShieldedCoinInfo at runtime by looking up the \
      relevant Merkle tree index. This index must have been allocated within \
      the current transaction or this insertion fails. \
      ShieldedCoinInfo, ContractAddress, Either, and ZswapCoinPublicKey are defined in CompactStandardLibrary."
       ;; [context, effects, state]
       ((idx [cached f-cached] [pushPath #t] [path f])
       ;; [context, effects, state, path, map]
       (push [storage #f] [value (state-value 'cell key)])
       ;; [context, effects, state, path, map, key]
       ;; Get qualified `coin` on the stack
       (dup [n (+ 3 (* (length f) 2))])
       ;; [context, effects, state, path, map, key, context]
       (push [storage #f] [value (state-value 'cell (rt-coin-commit coin recipient))])
       ;; [context, effects, state, path, map, key, context, coin_cm]
       (idx [cached #t] [pushPath #f] [path (list (align 1 1) 'stack)])
       ;; [context, effects, state, path, map, key, coin_idx]
       (push [storage #f] [value (state-value 'cell coin)])
       ;; [context, effects, state, path, map, key, coin_idx, coin]
       (swap [n 0])
       ;; [context, effects, state, path, map, key, coin, coin_idx]
       (concat [cached #t] [n 91])
       ;; [context, effects, state, path, map, key, qualified_coin]
       (ins [cached #f] [n 1])
       ;; [context, effects, state, path, map]
       (ins [cached #t] [n (length f)])))))
       ;; [context, effects, state']

(declare-ledger-adt List ([Type value_type])
  "an unbounded list of values of type value_type"
  (initial-value (state-value 'array ((state-value 'null)
                                      (state-value 'null)
                                      (state-value 'cell (align 0 8)))))
  (function js-only iter () "Iterator<${value_type}>"
    "Iterates over the entries in this List."
    ("(() => {"
     "  var iter = { curr: ${this} };"
     "  iter.next = () => {"
     "    const arr = iter.curr.asArray();"
     "    const head = arr[0];"
     "    if(head.type() == \"null\") {"
     "      return { done: true };"
     "    } else {"
     "      iter.curr = arr[1];"
     "      return { value: ${value_type}.fromValue(head.asCell().value), done: false };"
     "    }"
     "  };"
     "  return iter;"
     "})()"))
  (function remove resetToDefault () Void
    "Resets this List to the empty list."
    ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
     (push [storage #f] [value (state-value 'cell (car (reverse f)))])
     (push [storage #t] [value (state-value 'array ((state-value 'null)
                                                    (state-value 'null)
                                                    (state-value 'cell (align 0 8))))])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (suppress-zero (sub1 (length f)))])))
  (function read isEmpty () Boolean
    "Returns if this List is the empty list."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (idx [cached #f] [pushPath #f] [path (list (align 1 1))])
     (type)
     (push [storage #f] [value (state-value 'cell (align 1 1))])
     (eq)
     (popeq [cached #t] [result (void)])))
  (function read length () Uint64
    "Returns the number of elements contained in this List."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (idx [cached #f] [pushPath #f] [path (list (align 2 1))])
     (popeq [cached #t] [result (void)])))
  (function read head () (Maybe value_type)
    "Retrieves the head of this List, returning a Maybe, ensuring this call \
    succeeds on the empty list. \
    Maybe is defined in CompactStandardLibrary (compact-runtime from Typescript)."
    ;; [context, effects, state]
    ((dup [n 0])
     ;; [context, effects, state, state]
     (idx [cached f-cached] [pushPath #f] [path f])
     ;; [context, effects, state, list]
     (idx [cached #f] [pushPath #f] [path (list (align 0 1))])
     ;; [context, effects, state, head]
     (dup [n 0])
     ;; [context, effects, state, head, head]
     (type)
     ;; [context, effects, state, head, type]
     (push [storage #f] [value (state-value 'cell (align 1 1))])
     ;; [context, effects, state, head, type, 1]
     (eq)
     ;; @tkerber - I don't understand this branching. Since '1' encodes a cell, it looks like the branch where the Maybe
     ;;            is 'None' it followed when the head value is non-null, which is the opposite of what I'd expect.
     ;; [context, effects, state, head, type == 1]
     (branch [skip 4])
     ;; [context, effects, state, head]
     (push [storage #f] [value (state-value 'cell (align 1 1))])
     ;; [context, effects, state, head, 1]
     (swap [n 0])
     ;; [context, effects, state, 1, head]
     (concat [cached #f] [n (+ 2 (rt-max-sizeof value_type))])
     ;; [context, effects, state, (1, head)]
     (jmp [skip 2])
     ;; [context, effects, state, head]
     (pop)
     ;; [context, effects, state]
     (push [storage #f] [value (state-value 'cell (rt-aligned-concat (align 0 1) (rt-null value_type)))])
     ;; [context, effects, state, (1, head) | (0, null)]
     (popeq [cached #t] [result (void)])))
     ;; [context, effects, state]
  (function remove popFront () Void
    "Removes the first element from the front of this list."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #f] [path (list (align 1 1))])
     (ins [cached #t] [n (length f)])))
  (function update pushFront ([value value_type]) Void
    "Pushes a new element onto the front of this list."
     ;; [context, effects, state]
     ((idx [cached f-cached] [pushPath #t] [path f])
     ;; [context, effects, state, path, [null, null, 0]]
     (dup [n 0])
     ;; [context, effects, state, path, [null, null, 0], [null, null, 0]]
     (idx [cached #f] [pushPath #f] [path (list (align 2 1))])
     ;; [context, effects, state, path, [null, null, 0], 0]
     (addi [immediate 1])
     ;; [context, effects, state, path, [null, null, 0], 1]
     (push [storage #t] [value (state-value 'array ((state-value 'cell value)
                                                    (state-value 'null)
                                                    (state-value 'null)))])
     ;; [context, effects, state, path, [null, null, 0], 1, [value, null, null]]
     (swap [n 0])
     ;; [context, effects, state, path, [null, null, 0], [value, null, null], 1]
     (push [storage #f] [value (state-value 'cell (align 2 1))])
     ;; [context, effects, state, path, [null, null, 0], [value, null, null], 1, 2]
     (swap [n 0])
     ;; [context, effects, state, path, [null, null, 0], [value, null, null], 2, 1]
     (ins [cached #t] [n 1])
     ;; [context, effects, state, path, [null, null, 0], [value, null, 1]]
     (swap [n 0])
     ;; [context, effects, state, path, [value, null, 1], [null, null, 0]]
     (push [storage #f] [value (state-value 'cell (align 1 1))])
     ;; [context, effects, state, path, [value, null, 1], [null, null, 0], 1]
     (swap [n 0])
     ;; [context, effects, state, path, [value, null, 1], 1, [null, null, 0]]
     (ins [cached #t] [n (add1 (length f))])))
     ;; [context, effects, state]

  (when (= value_type QualifiedShieldedCoinInfo)
    (function (update-with-coin-check 0 1) pushFrontCoin ([coin ShieldedCoinInfo] [recipient ShieldedRecipient]) Void
      "Pushes a ShieldedCoinInfo onto the front of this List, where the ShieldedCoinInfo is \
      transformed into a QualifiedShieldedCoinInfo at runtime by looking up the \
      relevant Merkle tree index. This index must have been allocated within \
      the current transaction or this push fails. \
      ShieldedCoinInfo, ContractAddress, Either, and ZswapCoinPublicKey are defined in CompactStandardLibrary."
       ;; [context, effects, state]
       ((idx [cached f-cached] [pushPath #t] [path f])
       ;; [context, effects, state, path, list]
       (dup [n 0])
       ;; [context, effects, state, path, list, list]
       (idx [cached #f] [pushPath #f] [path (list (align 2 1))])
       ;; [context, effects, state, path, list, len(list)]
       (addi [immediate 1])
       ;; [context, effects, state, path, list, len(list) + 1]
       (push [storage #t] [value (state-value 'array ((state-value 'null)
                                                      (state-value 'null)
                                                      (state-value 'null)))])
       ;; [context, effects, state, path, list, len(list) + 1, [null, null, null]]
       (push [storage #f] [value (state-value 'cell (align 0 1))])
       ;; [context, effects, state, path, list, len(list) + 1, [null, null, null], 0]
       ;; Get qualified `coin` on stack
       (dup [n (+ 5 (* (length f) 2))])
       ;; [context, effects, state, path, list, len(list) + 1, [null, null, null], 0, context]
       (push [storage #f] [value (state-value 'cell (rt-coin-commit coin recipient))])
       ;; [context, effects, state, path, list, len(list) + 1, [null, null, null], 0, context, coin_cm]
       (idx [cached #t] [pushPath #f] [path (list (align 1 1) 'stack)])
       ;; [context, effects, state, path, list, len(list) + 1, [null, null, null], 0, coin_idx]
       (push [storage #f] [value (state-value 'cell coin)])
       ;; [context, effects, state, path, list, len(list) + 1, [null, null, null], 0, coin_idx, coin]
       (swap [n 0])
       ;; [context, effects, state, path, list, len(list) + 1, [null, null, null], 0, coin, coin_idx]
       (concat [cached #t] [n 91])
       ;; [context, effects, state, path, list, len(list) + 1, [null, null, null], 0, qualified_coin]
       (ins [cached #t] [n 1])
       ;; [context, effects, state, path, list, len(list) + 1, [qualified_coin, null, null]]
       (swap [n 0])
       ;; [context, effects, state, path, list, [qualified_coin, null, null], len(list) + 1]
       (push [storage #f] [value (state-value 'cell (align 2 1))])
       ;; [context, effects, state, path, list, [qualified_coin, null, null], len(list) + 1, 2]
       (swap [n 0])
       ;; [context, effects, state, path, list, [qualified_coin, null, null], 2, len(list) + 1]
       (ins [cached #t] [n 1])
       ;; [context, effects, state, path, list, [qualified_coin, null, len(list) + 1]]
       (swap [n 0])
       ;; [context, effects, state, path, [qualified_coin, null, len(list) + 1], list]
       (push [storage #f] [value (state-value 'cell (align 1 1))])
       ;; [context, effects, state, path, [qualified_coin, null, len(list) + 1], list, 1]
       (swap [n 0])
       ;; [context, effects, state, path, [qualified_coin, null, len(list) + 1], 1, list]
       (ins [cached #t] [n (add1 (length f))])))))
        ;; [context, effects, state']

(declare-ledger-adt MerkleTree ([Nat nat] [Type value_type])
  "a bounded Merkle tree of depth nat where 2 <= nat <= 32 containing values of type value_type"
  (initial-value (state-value 'array ((state-value 'merkle-tree nat ())
                                      (state-value 'cell (align 0 8)))))
  (function js-only root () "${rtlib}MerkleTreeDigest"
    "Retrieves the root of the Merkle tree. \
    MerkleTreeDigest is defined in compact-runtime."
    ("((result) => result"
     "             ? ${rtlib}CompactTypeMerkleTreeDigest.fromValue(result)"
     "             : undefined)(${this}.asArray()[0].asBoundedMerkleTree().rehash().root()?.value)"))
  (function js-only first_free () "bigint"
    "Retrieves the first (guaranteed) free index in the Merkle tree."
    ("${rtlib}CompactTypeField.fromValue(${this}.asArray()[1].asCell().value)"))
  (function js-only path_for_leaf ([index Field] [leaf value_type]) "${rtlib}MerkleTreePath<${value_type}>"
    "Returns the Merkle path, given the knowledge that a specified leaf is at \
    the given index. It is an error to call this if this leaf is not \
    contained at the given index. \
    MerkleTreePath is defined in compact-runtime."
    ("((result) => result"
     "             ? new ${rtlib}CompactTypeMerkleTreePath(${nat}, ${value_type}).fromValue(result)"
     "             : undefined)("
     "  ${this}.asArray()[0].asBoundedMerkleTree().rehash().pathForLeaf("
     "    ${index},"
     "    {"
     "      value: ${value_type}.toValue(${leaf}),"
     "      alignment: ${value_type}.alignment()"
     "    }"
     "  )?.value)"))
  (function js-only find_path_for_leaf ([leaf value_type]) "${rtlib}MerkleTreePath<${value_type}> | undefined"
    "Finds the path for a given leaf in a Merkle tree. Be warned that this is \
    O(n) and should be avoided for large trees. Returns undefined if no such \
    leaf exists. \
    MerkleTreePath is defined in compact-runtime."
    ("((result) => result"
     "             ? new ${rtlib}CompactTypeMerkleTreePath(${nat}, ${value_type}).fromValue(result)"
     "             : undefined)("
     "  ${this}.asArray()[0].asBoundedMerkleTree().rehash().findPathForLeaf("
     "    {"
     "      value: ${value_type}.toValue(${leaf}),"
     "      alignment: ${value_type}.alignment()"
     "    }"
     "  )?.value)"))
  (function remove resetToDefault () Void
    "Resets this Merkle tree to the empty Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
     (push [storage #f] [value (state-value 'cell (car (reverse f)))])
     (push [storage #t] [value (state-value 'array ((state-value 'merkle-tree nat ())
                                                    (state-value 'cell (align 0 8))))])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (suppress-zero (sub1 (length f)))])))
  (function read isFull () Boolean
    "Returns if this Merkle tree is full and further items cannot be \
    directly inserted."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (idx [cached #f] [pushPath #f] [path (list (align 1 1))])
     (push [storage #f] [value (state-value 'cell (align (expt 2 nat) 8))])
     (lt)
     (neg)
     (popeq [cached #t] [result (void)])))
  (function read checkRoot ([rt MerkleTreeDigest]) Boolean
    "Tests if the given Merkle tree root is the root for this Merkle tree. \
    MerkleTreeDigest is defined in CompactStandardLibrary (compact-runtime from Typescript)."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (idx [cached #f] [pushPath #f] [path (list (align 0 1))])
     (root)
     (push [storage #f] [value (state-value 'cell rt)])
     (eq)
     (popeq [cached #t] [result (void)])))
  (function update insert ([item value_type]) Void
    "Inserts a new leaf at the first free index in this Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 1 1))])
     (push [storage #t] [value (state-value 'cell (rt-leaf-hash item))])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n 1])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (addi [immediate 1])
     (ins [cached #t] [n (add1 (length f))])))
  (function update insertIndex ([item value_type] [index Uint64]) Void
    "Inserts a new leaf at a specific index in this Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (push [storage #t] [value (state-value 'cell (rt-leaf-hash item))])
     (ins [cached #f] [n 2])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (addi [immediate 1])
     (dup [n 1])
     (dup [n 1])
     (lt)
     (branch [skip 2])
     (pop)
     (jmp [skip 2])
     (swap [n 0])
     (pop)
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (length f)])))
  (function update insertHash ([hash Bytes32]) Void
    "Inserts a new leaf with a given hash at the first free index in this Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 1 1))])
     (push [storage #t] [value (state-value 'cell hash)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n 1])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (addi [immediate 1])
     (ins [cached #t] [n (add1 (length f))])))
  (function update insertHashIndex ([hash Bytes32] [index Uint64]) Void
    "Inserts a new leaf with a given hash at a specific index in this Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (push [storage #t] [value (state-value 'cell hash)])
     (ins [cached #f] [n 2])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (addi [immediate 1])
     (dup [n 1])
     (dup [n 1])
     (lt)
     (branch [skip 2])
     (pop)
     (jmp [skip 2])
     (swap [n 0])
     (pop)
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (length f)])))
  (function update insertIndexDefault ([index Uint64]) Void
    "Inserts a default value leaf at a specific index in this Merkle tree. \
    This can be used to emulate a removal from the tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (push [storage #t] [value (state-value 'cell (rt-leaf-hash (rt-null value_type)))])
     (ins [cached #f] [n 2])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (addi [immediate 1])
     (dup [n 1])
     (dup [n 1])
     (lt)
     (branch [skip 2])
     (pop)
     (jmp [skip 2])
     (swap [n 0])
     (pop)
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (length f)]))))

(declare-ledger-adt HistoricMerkleTree ([Nat nat] [Type value_type])
  "a bounded Merkle tree of depth nat where 2 <= nat <= 32 containing values of type value_type, with history"
  (initial-value (state-value 'array ((state-value 'merkle-tree nat ())
                                      (state-value 'cell (align 0 8))
                                      (state-value 'map ()))))
  (function js-only root () "${rtlib}MerkleTreeDigest"
    "Retrieves the root of the Merkle tree. \
    MerkleTreeDigest is defined in compact-runtime."
    ("((result) => result"
     "             ? ${rtlib}CompactTypeMerkleTreeDigest.fromValue(result)"
     "             : undefined)(${this}.asArray()[0].asBoundedMerkleTree().rehash().root()?.value)"))
  (function js-only first_free () "bigint"
    "Retrieves the first (guaranteed) free index in the Merkle tree."
    ("${rtlib}CompactTypeField.fromValue(${this}.asArray()[1].asCell().value)"))
  (function js-only path_for_leaf ([index Field] [leaf value_type]) "${rtlib}MerkleTreePath<${value_type}>"
    "Returns the Merkle path, given the knowledge that a specified leaf is at \
    the given index. It is an error to call this if the index is out of bounds. \
    MerkleTreePath is defined in compact-runtime."
    ("((result) => result"
     "             ? new ${rtlib}CompactTypeMerkleTreePath(${nat}, ${value_type}).fromValue(result)"
     "             : undefined)("
     "  ${this}.asArray()[0].asBoundedMerkleTree().rehash().pathForLeaf("
     "    ${index},"
     "    {"
     "      value: ${value_type}.toValue(${leaf}),"
     "      alignment: ${value_type}.alignment()"
     "    }"
     "  )?.value)"))
  (function js-only find_path_for_leaf ([leaf value_type]) "${rtlib}MerkleTreePath<${value_type}> | undefined"
    "Finds the path for a given leaf in a Merkle tree. Be warned that this is \
    O(n) and should be avoided for large trees. Returns undefined if no such \
    leaf exists. 
    MerkleTreePath is defined in compact-runtime."
    ("((result) => result"
     "             ? new ${rtlib}CompactTypeMerkleTreePath(${nat}, ${value_type}).fromValue(result)"
     "             : undefined)("
     "  ${this}.asArray()[0].asBoundedMerkleTree().rehash().findPathForLeaf("
     "    {"
     "      value: ${value_type}.toValue(${leaf}),"
     "      alignment: ${value_type}.alignment()"
     "    }"
     "  )?.value)"))
  (function js-only history () "Iterator<${rtlib}MerkleTreeDigest>"
    "An iterator over the roots that are considered valid past roots for this \
    Merkle tree. \
    MerkleTreeDigest is defined in compact-runtime."
    ("${this}.asArray()[2].asMap().keys().map("
     "  (elem) => ${rtlib}CompactTypeMerkleTreeDigest.fromValue(elem.value)"
     ")[Symbol.iterator]()"))
  (function remove resetToDefault () Void
    "Resets this Merkle tree to the empty Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
     (push [storage #f] [value (state-value 'cell (car (reverse f)))])
     (push [storage #t] [value (state-value 'array ((state-value 'merkle-tree nat ())
                                                    (state-value 'cell (align 0 8))
                                                    (state-value 'map ())))])
     (idx [cached #f] [pushPath #t] [path (list (align 2 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 0 1))])
     (root)
     (push [storage #t] [value (state-value 'null)])
     (ins [cached #t] [n 2])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (suppress-zero (sub1 (length f)))])))
  (function read isFull () Boolean
    "Returns if this Merkle tree is full and further items cannot be \
    directly inserted."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (idx [cached #f] [pushPath #f] [path (list (align 1 1))])
     (push [storage #f] [value (state-value 'cell (align (expt 2 nat) 8))])
     (lt)
     (neg)
     (popeq [cached #t] [result (void)])))
  (function read checkRoot ([rt MerkleTreeDigest]) Boolean
    "Tests if the given Merkle tree root is one of the past roots for this \
    Merkle tree. \
    MerkleTreeDigest is defined in CompactStandardLibrary (compact-runtime from Typescript)."
    ((dup [n 0])
     (idx [cached f-cached] [pushPath #f] [path f])
     (idx [cached #f] [pushPath #f] [path (list (align 2 1))])
     (push [storage #f] [value (state-value 'cell rt)])
     (member)
     (popeq [cached #t] [result (void)])))
  (function update insert ([item value_type]) Void
    "Inserts a new leaf at the first free index in this Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 1 1))])
     (push [storage #t] [value (state-value 'cell (rt-leaf-hash item))])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n 1])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (addi [immediate 1])
     (ins [cached #t] [n 1])
     (idx [cached #f] [pushPath #t] [path (list (align 2 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 0 1))])
     (root)
     (push [storage #t] [value (state-value 'null)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (add1 (length f))])))
  (function update insertIndex ([item value_type] [index Uint64]) Void
    "Inserts a new leaf at a specific index in this Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (push [storage #t] [value (state-value 'cell (rt-leaf-hash item))])
     (ins [cached #f] [n 2])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (addi [immediate 1])
     (dup [n 1])
     (dup [n 1])
     (lt)
     (branch [skip 2])
     (pop)
     (jmp [skip 2])
     (swap [n 0])
     (pop)
     (ins [cached #f] [n 1])
     (idx [cached #f] [pushPath #t] [path (list (align 2 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 0 1))])
     (root)
     (push [storage #t] [value (state-value 'null)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (add1 (length f))])))
  (function update insertHash ([hash Bytes32]) Void
    "Inserts a new leaf with a given hash at the first free index in this Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 1 1))])
     (push [storage #t] [value (state-value 'cell hash)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n 1])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (addi [immediate 1])
     (ins [cached #t] [n 1])
     (idx [cached #f] [pushPath #t] [path (list (align 2 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 0 1))])
     (root)
     (push [storage #t] [value (state-value 'null)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (add1 (length f))])))
  (function update insertHashIndex ([hash Bytes32] [index Uint64]) Void
    "Inserts a new leaf with a given hash at a specific index in this Merkle tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (push [storage #t] [value (state-value 'cell hash)])
     (ins [cached #f] [n 2])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (addi [immediate 1])
     (dup [n 1])
     (dup [n 1])
     (lt)
     (branch [skip 2])
     (pop)
     (jmp [skip 2])
     (swap [n 0])
     (pop)
     (ins [cached #f] [n 1])
     (idx [cached #f] [pushPath #t] [path (list (align 2 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 0 1))])
     (root)
     (push [storage #t] [value (state-value 'null)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (add1 (length f))])))
  (function update insertIndexDefault ([index Uint64]) Void
    "Inserts a default value leaf at a specific index in this Merkle tree. \
    This can be used to emulate a removal from the tree."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (idx [cached #f] [pushPath #t] [path (list (align 0 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (push [storage #t] [value (state-value 'cell (rt-leaf-hash (rt-null value_type)))])
     (ins [cached #f] [n 2])
     (idx [cached #f] [pushPath #t] [path (list (align 1 1))])
     (push [storage #f] [value (state-value 'cell index)])
     (addi [immediate 1])
     (dup [n 1])
     (dup [n 1])
     (lt)
     (branch [skip 2])
     (pop)
     (jmp [skip 2])
     (swap [n 0])
     (pop)
     (ins [cached #f] [n 1])
     (idx [cached #f] [pushPath #t] [path (list (align 2 1))])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 0 1))])
     (root)
     (push [storage #t] [value (state-value 'null)])
     (ins [cached #f] [n 1])
     (ins [cached #t] [n (add1 (length f))])))
  (function update resetHistory () Void
    "Resets the history for this Merkle tree, leaving only the current root \
    valid."
    ((idx [cached f-cached] [pushPath #t] [path f])
     (push [storage #f] [value (state-value 'cell (align 2 1))])
     (push [storage #t] [value (state-value 'map ())])
     (dup [n 2])
     (idx [cached #f] [pushPath #f] [path (list (align 0 1))])
     (root)
     (push [storage #t] [value (state-value 'null)])
     (ins [cached #t] [n (+ (length f) 2)]))))
