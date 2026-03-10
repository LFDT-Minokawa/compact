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

(declare-native-entry circuit transientHash [A]
  "__compactRuntime.transientHash"
  ([value A (discloses "a hash of")])
  Field)

(declare-native-entry circuit transientCommit [A]
  "__compactRuntime.transientCommit"
  ([value A (discloses nothing)]
   [rand Field (discloses nothing)])
  Field)

(declare-native-entry circuit persistentHash [A]
  "__compactRuntime.persistentHash"
  ([value A (discloses "a hash of")])
  (Bytes 32))

(declare-native-entry circuit persistentCommit [A]
  "__compactRuntime.persistentCommit"
  ([value A (discloses nothing)]
   [rand (Bytes 32) (discloses nothing)])
  (Bytes 32))

(declare-native-entry circuit degradeToTransient
  "__compactRuntime.degradeToTransient"
  ([x (Bytes 32) (discloses "a modulus of")])
  Field)

(declare-native-entry circuit upgradeFromTransient
  "__compactRuntime.upgradeFromTransient"
  ([x Field (discloses "a converted form of")])
  (Bytes 32))

(declare-native-entry circuit jubjubPointX
  "__compactRuntime.jubjubPointX"
  ([np (TypeRef JubjubPoint) (discloses "the X coordinate of")])
  Field)

(declare-native-entry circuit jubjubPointY
  "__compactRuntime.jubjubPointY"
  ([np (TypeRef JubjubPoint) (discloses "the Y coordinate of")])
  Field)

(declare-native-entry circuit ecAdd
  "__compactRuntime.ecAdd"
  ([a (TypeRef JubjubPoint) (discloses "an elliptic curve sum including")]
   [b (TypeRef JubjubPoint) (discloses "an elliptic curve sum including")])
  (TypeRef JubjubPoint))

(declare-native-entry circuit ecMul
  "__compactRuntime.ecMul"
  ([a (TypeRef JubjubPoint) (discloses "an elliptic curve product including")]
   [b Field (discloses "an elliptic curve product including")])
  (TypeRef JubjubPoint))

(declare-native-entry circuit ecMulGenerator
  "__compactRuntime.ecMulGenerator"
  ([b Field (discloses "the product of the embedded group generator with")])
  (TypeRef JubjubPoint))

(declare-native-entry circuit hashToCurve [A]
  "__compactRuntime.hashToCurve"
  ([value A (discloses "a hash of")])
  (TypeRef JubjubPoint))

(declare-native-entry circuit constructJubjubPoint
  "__compactRuntime.constructJubjubPoint"
  ([x Field (discloses "a JubjubPoint containing x coordinate")]
   [y Field (discloses "a JubjubPoint containing y coordinate")])
  (TypeRef JubjubPoint))

(declare-native-entry witness ownPublicKey
  "__compactRuntime.ownPublicKey"
  ()
  (TypeRef ZswapCoinPublicKey))

(declare-native-entry witness createZswapInput
  "__compactRuntime.createZswapInput"
  ([coin (TypeRef QualifiedShieldedCoinInfo) (discloses nothing)])
  Void)

(declare-native-entry witness createZswapOutput
  "__compactRuntime.createZswapOutput"
  ([coin (TypeRef ShieldedCoinInfo) (discloses nothing)]
   [recipient (TypeRef Either (TypeRef ZswapCoinPublicKey) (TypeRef ContractAddress)) (discloses nothing)])
  Void)
