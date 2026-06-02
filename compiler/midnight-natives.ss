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

;; ==== Transient (Poseidon) hashing
(declare-native-entry circuit transientHash [A]
  "__compactRuntime.transientHash"
  ([value A (discloses "a hash of")])
  Field
  (rust "compact_runtime::transient_hash"))

(declare-native-entry circuit transientCommit [A]
  "__compactRuntime.transientCommit"
  ([value A (discloses nothing)]
   [rand Field (discloses nothing)])
  Field
  (rust "compact_runtime::transient_commit"))

;; ==== Persistent (SHA-256) hashing
(declare-native-entry circuit persistentHash [A]
  "__compactRuntime.persistentHash"
  ([value A (discloses "a hash of")])
  (Bytes 32)
  (rust "compact_runtime::persistent_hash"))

(declare-native-entry circuit persistentCommit [A]
  "__compactRuntime.persistentCommit"
  ([value A (discloses nothing)]
   [rand (Bytes 32) (discloses nothing)])
  (Bytes 32)
  (rust "compact_runtime::persistent_commit"))

(declare-native-entry circuit degradeToTransient
  "__compactRuntime.degradeToTransient"
  ([x (Bytes 32) (discloses "a modulus of")])
  Field
  (rust "compact_runtime::degrade_to_transient"))

(declare-native-entry circuit upgradeFromTransient
  "__compactRuntime.upgradeFromTransient"
  ([x Field (discloses "a converted form of")])
  (Bytes 32)
  (rust "compact_runtime::upgrade_from_transient"))

;; ==== Other hashing circuits
(declare-native-entry circuit keccak256 [A]
  "__compactRuntime.keccak256"
  ([value A (discloses "a hash of")])
  (Bytes 32)
  (rust "/* TODO M3.5+: no upstream Rust binding for keccak256; midnight crypto exposes keccak only as a ZK circuit chip. */ unimplemented!()"))

;; ====
(declare-native-entry circuit jubjubPointX
  "__compactRuntime.jubjubPointX"
  ([np (TypeRef JubjubPoint) (discloses "the X coordinate of")])
  Field
  (rust "compact_runtime::jubjub_point_x"))

(declare-native-entry circuit jubjubPointY
  "__compactRuntime.jubjubPointY"
  ([np (TypeRef JubjubPoint) (discloses "the Y coordinate of")])
  Field
  (rust "compact_runtime::jubjub_point_y"))

(declare-native-entry circuit ecAdd
  "__compactRuntime.ecAdd"
  ([a (TypeRef JubjubPoint) (discloses "an elliptic curve sum including")]
   [b (TypeRef JubjubPoint) (discloses "an elliptic curve sum including")])
  (TypeRef JubjubPoint)
  (rust "compact_runtime::ec_add"))

(declare-native-entry circuit ecMul
  "__compactRuntime.ecMul"
  ([a (TypeRef JubjubPoint) (discloses "an elliptic curve product including")]
   [b Field (discloses "an elliptic curve product including")])
  (TypeRef JubjubPoint)
  (rust "compact_runtime::ec_mul"))

(declare-native-entry circuit ecMulGenerator
  "__compactRuntime.ecMulGenerator"
  ([b Field (discloses "the product of the embedded group generator with")])
  (TypeRef JubjubPoint)
  (rust "compact_runtime::ec_mul_generator"))

(declare-native-entry circuit hashToCurve [A]
  "__compactRuntime.hashToCurve"
  ([value A (discloses "a hash of")])
  (TypeRef JubjubPoint)
  (rust "compact_runtime::hash_to_curve"))

(declare-native-entry circuit constructJubjubPoint
  "__compactRuntime.constructJubjubPoint"
  ([x Field (discloses "a JubjubPoint containing x coordinate")]
   [y Field (discloses "a JubjubPoint containing y coordinate")])
  (TypeRef JubjubPoint)
  (rust "compact_runtime::construct_jubjub_point"))

(declare-native-entry witness ownPublicKey
  "__compactRuntime.ownPublicKey"
  ()
  (TypeRef ZswapCoinPublicKey)
  (rust "/* TODO M3.5+: ownPublicKey is a host-side zswap witness; needs WitnessContext-mediated binding. */ unimplemented!()"))

(declare-native-entry witness createZswapInput
  "__compactRuntime.createZswapInput"
  ([coin (TypeRef QualifiedShieldedCoinInfo) (discloses nothing)])
  Void
  (rust "/* TODO M3.5+: createZswapInput is a host-side zswap witness; needs WitnessContext-mediated binding. */ unimplemented!()"))

(declare-native-entry witness createZswapOutput
  "__compactRuntime.createZswapOutput"
  ([coin (TypeRef ShieldedCoinInfo) (discloses nothing)]
   [recipient (TypeRef Either (TypeRef ZswapCoinPublicKey) (TypeRef ContractAddress)) (discloses nothing)])
  Void
  (rust "/* TODO M3.5+: createZswapOutput is a host-side zswap witness; needs WitnessContext-mediated binding. */ unimplemented!()"))
