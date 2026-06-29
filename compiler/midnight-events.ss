;;; This file is part of Compact.
;;; Copyright (C) 2026 Midnight Foundation
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

(declare-event-type ShieldedSpend 0 32
  "Shielded coin consumed, new coin created for a user recipient."
  ([nullifier (Bytes 32) (hint "indexed")]))

(declare-event-type ShieldedReceive 1 578
  "A contract accepts an incoming shielded coin.\n`contract_address` set when received by a contract, absent for user recipients."
  ([commitment (Bytes 32) (hint "indexed")]
   [contract_address (TypeRef Maybe (Bytes 32))]
   [ciphertext (TypeRef Maybe (Bytes 512))]))

(declare-event-type ShieldedMint 2 81
  "New shielded tokens created.\n`token_type` derived by the consumer from `domain_sep` + `ContractLog.address`."
  ([commitment (Bytes 32) (hint "indexed")]
   [domain_sep (Bytes 32) (hint "indexed")]
   [amount (TypeRef Maybe (Uint 128))]))

(declare-event-type ShieldedBurn 3 49
  "Shielded coin sent to the burn address.\nSupply tracking — tokens permanently removed from circulation."
  ([nullifier (Bytes 32) (hint "indexed")]
   [amount (TypeRef Maybe (Uint 128))]))

(declare-event-type UnshieldedSpend 4 113
  "Public token sent from a sender."
  ([sender (TypeRef Either (TypeRef ZswapCoinPublicKey) (TypeRef ContractAddress)) (hint "indexed")]
   [token_type (Bytes 32) (hint "indexed")]
   [amount (Uint 128)]))

(declare-event-type UnshieldedReceive 5 113
  "Public token sent to a recipient."
  ([recipient (TypeRef Either (TypeRef ZswapCoinPublicKey) (TypeRef ContractAddress)) (hint "indexed")]
   [token_type (Bytes 32) (hint "indexed")]
   [amount (Uint 128)]))

(declare-event-type UnshieldedMint 6 80
  "New unshielded tokens created."
  ([domain_sep (Bytes 32) (hint "indexed")]
   [token_type (Bytes 32) (hint "indexed")]
   [amount (Uint 128)]))

(declare-event-type UnshieldedBurn 7 113
  "Unshielded coin sent to the burn address."
  ([sender (TypeRef Either (TypeRef ZswapCoinPublicKey) (TypeRef ContractAddress)) (hint "indexed")]
   [token_type (Bytes 32) (hint "indexed")]
   [amount (Uint 128)]))

(declare-event-type Paused 8 0
  "Contract operations suspended."
  ())

(declare-event-type Unpaused 9 0
  "Contract operations resumed."
  ())

(declare-event-type Misc 10 288
  "Miscellaneous event type."
  ([name (Bytes 32)]
   [payload (Bytes 256)]))
