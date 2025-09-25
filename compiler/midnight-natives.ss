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

(declare-native-entry external transientHash [A]
  "__compactRuntime.transientHash"
  ([A (discloses "a hash of")])
  Field)

(declare-native-entry external transientCommit [A]
  "__compactRuntime.transientCommit"
  ([A (discloses nothing)] [Field (discloses nothing)])
  Field)

(declare-native-entry external persistentHash [A]
  "__compactRuntime.persistentHash"
  ([A (discloses "a hash of")])
  (Bytes 32))

(declare-native-entry external persistentCommit [A]
  "__compactRuntime.persistentCommit"
  ([A (discloses nothing)] [(Bytes 32) (discloses nothing)])
  (Bytes 32))

(declare-native-entry external degradeToTransient
  "__compactRuntime.degradeToTransient"
  ([(Bytes 32) (discloses "a modulus of")])
  Field)

(declare-native-entry external upgradeFromTransient
  "__compactRuntime.upgradeFromTransient"
  ([Field (discloses "a converted form of")])
  (Bytes 32))

(declare-native-entry external ecAdd
  "__compactRuntime.ecAdd"
  ([(Struct Field Field) (discloses "an elliptic curve sum including")] [(Struct Field Field) (discloses "an elliptic curve sum including")])
  (Struct Field Field))

(declare-native-entry external ecMul
  "__compactRuntime.ecMul"
  ([(Struct Field Field) (discloses "an elliptic curve product including")] [Field (discloses "an elliptic curve product including")])
  (Struct Field Field))

(declare-native-entry external ecMulGenerator
  "__compactRuntime.ecMulGenerator"
  ([Field (discloses "the product of the embedded group generator with")])
  (Struct Field Field))

(declare-native-entry external hashToCurve [A]
  "__compactRuntime.hashToCurve"
  ([A (discloses "a hash of")])
  (Struct Field Field))

(declare-native-entry witness ownPublicKey
  "__compactRuntime.ownPublicKey"
  ()
  (Struct (Bytes 32)))

(declare-native-entry witness createZswapInput
  "__compactRuntime.createZswapInput"
  ([(Struct (Bytes 32) (Bytes 32) (Uint 128) (Uint 64)) (discloses nothing)])
  Void)

(declare-native-entry witness createZswapOutput
  "__compactRuntime.createZswapOutput"
  ([(Struct (Bytes 32) (Bytes 32) (Uint 128)) (discloses nothing)]
   [(Struct Boolean (Struct (Bytes 32)) (Struct (Bytes 32))) (discloses nothing)])
  Void)

#|
; this should be uncommented when the justfortesting tests are uncommented in test.ss
; used for testing type parametization unification errors
(declare-native-entry justfortesting [A]
  "__compactRuntime.transientHash"
  (A A)
  A)
|#
