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

;; ==== Non-native fields and curve points
;; TODO(kmillikin): enable Curve25519 in the standard library when it is fully supported.
;; For now it is inaccessible.
;; (declare-native-type Curve25519Base tfield (field-base (curve-curve25519)))
;; (declare-native-type Curve25519Scalar tfield (field-scalar (curve-curve25519)))
;; (declare-native-type Curve25519Point tpoint (curve-curve25519))

(declare-native-type Secp256k1Base tfield (field-base (curve-secp256k1)))
(declare-native-type Secp256k1Scalar tfield (field-scalar (curve-secp256k1)))
(declare-native-type Secp256k1Point tpoint (curve-secp256k1))

(declare-native-type Secp256r1Base tfield (field-base (curve-secp256r1)))
(declare-native-type Secp256r1Scalar tfield (field-scalar (curve-secp256r1)))
(declare-native-type Secp256r1Point tpoint (curve-secp256r1))

;; ==== Fields
;; -- neg
(declare-native-entry circuit neg
  "__compactRuntime.secp256k1BaseNeg"
  ([s (TypeRef Secp256k1Base) (discloses "the negation of")])
  (TypeRef Secp256k1Base))

(declare-native-entry circuit neg
  "__compactRuntime.secp256k1ScalarNeg"
  ([s (TypeRef Secp256k1Scalar) (discloses "the negation of")])
  (TypeRef Secp256k1Scalar))

(declare-native-entry circuit neg
  "__compactRuntime.secp256r1BaseNeg"
  ([s (TypeRef Secp256r1Base) (discloses "the negation of")])
  (TypeRef Secp256r1Base))

(declare-native-entry circuit neg
  "__compactRuntime.secp256r1ScalarNeg"
  ([s (TypeRef Secp256r1Scalar) (discloses "the negation of")])
  (TypeRef Secp256r1Scalar))

;; -- inv
(declare-native-entry circuit inv
  "__compactRuntime.secp256k1BaseInv"
  ([s (TypeRef Secp256k1Base) (discloses "the inverse of")])
  (TypeRef Secp256k1Base))

(declare-native-entry circuit inv
  "__compactRuntime.secp256k1ScalarInv"
  ([s (TypeRef Secp256k1Scalar) (discloses "the inverse of")])
  (TypeRef Secp256k1Scalar))

(declare-native-entry circuit inv
  "__compactRuntime.secp256r1BaseInv"
  ([s (TypeRef Secp256r1Base) (discloses "the inverse of")])
  (TypeRef Secp256r1Base))

(declare-native-entry circuit inv
  "__compactRuntime.secp256r1ScalarInv"
  ([s (TypeRef Secp256r1Scalar) (discloses "the inverse of")])
  (TypeRef Secp256r1Scalar))

;; -- accessors
(declare-native-entry circuit secp256k1PointX
  "__compactRuntime.secp256k1PointX"
  ([pt (TypeRef Secp256k1Point) (discloses "the x-coordinate of")])
  (TypeRef Secp256k1Base))

(declare-native-entry circuit secp256k1PointY
  "__compactRuntime.secp256k1PointY"
  ([pt (TypeRef Secp256k1Point) (discloses "the y-coordinate of")])
  (TypeRef Secp256k1Base))

(declare-native-entry circuit secp256r1PointX
  "__compactRuntime.secp256r1PointX"
  ([pt (TypeRef Secp256r1Point) (discloses "the x-coordinate of")])
  (TypeRef Secp256r1Base))

(declare-native-entry circuit secp256r1PointY
  "__compactRuntime.secp256r1PointY"
  ([pt (TypeRef Secp256r1Point) (discloses "the y-coordinate of")])
  (TypeRef Secp256r1Base))

;; -- ecAdd
(declare-native-entry circuit ecAdd
  "__compactRuntime.secp256k1Add"
  ([a (TypeRef Secp256k1Point) (discloses "an elliptic curve sum including")]
   [b (TypeRef Secp256k1Point) (discloses "an elliptic curve sum including")])
  (TypeRef Secp256k1Point))

(declare-native-entry circuit ecAdd
  "__compactRuntime.secp256r1Add"
  ([a (TypeRef Secp256r1Point) (discloses "an elliptic curve sum including")]
   [b (TypeRef Secp256r1Point) (discloses "an elliptic curve sum including")])
  (TypeRef Secp256r1Point))

;; -- ecMul
(declare-native-entry circuit ecMul
  "__compactRuntime.secp256k1Mul"
  ([a (TypeRef Secp256k1Point) (discloses "an elliptic curve product including")]
   [b (TypeRef Secp256k1Scalar) (discloses "an elliptic curve product including")])
  (TypeRef Secp256k1Point))

(declare-native-entry circuit ecMul
  "__compactRuntime.secp256r1Mul"
  ([a (TypeRef Secp256r1Point) (discloses "an elliptic curve product including")]
   [b (TypeRef Secp256r1Scalar) (discloses "an elliptic curve product including")])
  (TypeRef Secp256r1Point))

;; -- ecMulGenerator
(declare-native-entry circuit ecMulGenerator
  "__compactRuntime.secp256k1MulGenerator"
  ([b (TypeRef Secp256k1Scalar) (discloses "the product of the embedded group generator with")])
  (TypeRef Secp256k1Point))

(declare-native-entry circuit ecMulGenerator
  "__compactRuntime.secp256r1MulGenerator"
  ([b (TypeRef Secp256r1Scalar) (discloses "the product of the embedded group generator with")])
  (TypeRef Secp256r1Point))
