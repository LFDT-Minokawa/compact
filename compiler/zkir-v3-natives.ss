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

;; ==== Fields
(declare-native-entry circuit neg
  "__compactRuntime.secp256k1ScalarNeg"
  ([s Secp256k1Scalar (discloses "the negation of")])
  Secp256k1Scalar)

(declare-native-entry circuit inv
  "__compactRuntime.secp256k1ScalarInv"
  ([s Secp256k1Scalar (discloses "the inverse of")])
  Secp256k1Scalar)

(declare-native-entry circuit secp256k1PointX
  "__compactRuntime.secp256k1PointX"
  ([pt (TypeRef Secp256k1Point) (discloses "the X coordinate of")])
  Secp256k1Base)

(declare-native-entry circuit secp256k1PointY
  "__compactRuntime.secp256k1PointY"
  ([pt (TypeRef Secp256k1Point) (discloses "the Y coordinate of")])
  Secp256k1Base)

(declare-native-entry circuit ecAdd
  "__compactRuntime.secp256k1Add"
  ([a (TypeRef Secp256k1Point) (discloses "an elliptic curve sum including")]
   [b (TypeRef Secp256k1Point) (discloses "an elliptic curve sum including")])
  (TypeRef Secp256k1Point))

(declare-native-entry circuit ecMul
  "__compactRuntime.secp256k1Mul"
  ([a (TypeRef Secp256k1Point) (discloses "an elliptic curve product including")]
   [b Secp256k1Scalar (discloses "an elliptic curve product including")])
  (TypeRef Secp256k1Point))

(declare-native-entry circuit ecMulGenerator
  "__compactRuntime.secp256k1MulGenerator"
  ([b Secp256k1Scalar (discloses "the product of the embedded group generator with")])
  (TypeRef Secp256k1Point))

