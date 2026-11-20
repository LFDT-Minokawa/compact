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
(declare-native-type JubjubScalar tfield (field-scalar (curve-jubjub)))
(declare-native-type JubjubPoint tpoint (curve-jubjub))
(declare-native-type Curve25519Base tfield (field-base (curve-curve25519)))
(declare-native-type Curve25519Scalar tfield (field-scalar (curve-curve25519)))
(declare-native-type Curve25519Point tpoint (curve-curve25519))

(declare-native-type Secp256k1Base tfield (field-base (curve-secp256k1)))
(declare-native-type Secp256k1Scalar tfield (field-scalar (curve-secp256k1)))
(declare-native-type Secp256k1Point tpoint (curve-secp256k1))

(declare-native-type Secp256r1Base tfield (field-base (curve-secp256r1)))
(declare-native-type Secp256r1Scalar tfield (field-scalar (curve-secp256r1)))
(declare-native-type Secp256r1Point tpoint (curve-secp256r1))

;; ==== Transient (Poseidon) hashing
(declare-native-entry circuit transientHash [A]
  "__compactRuntime.transientHash"
  ([value A (discloses "a hash of")])
  Field)

(declare-native-entry circuit transientCommit [A]
  "__compactRuntime.transientCommit"
  ([value A (discloses nothing)]
   [rand Field (discloses nothing)])
  Field)

;; ==== Hashing
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

(declare-native-entry circuit keccak256 [A]
  "__compactRuntime.keccak256"
  ([value A (discloses "a hash of")])
  (Bytes 32))

(declare-native-entry circuit sha512 [A]
  "__compactRuntime.sha512"
  ([value A (discloses "a hash of")])
  (Bytes 64))

;; ==== Foreign field arithmetic
;; -- Secp256k1Base
(declare-native-entry circuit neg
  "__compactRuntime.secp256k1BaseNeg"
  ([s (TypeRef Secp256k1Base) (discloses "the negation of")])
  (TypeRef Secp256k1Base))

(declare-native-entry circuit inv
  "__compactRuntime.secp256k1BaseInv"
  ([s (TypeRef Secp256k1Base) (discloses "the inverse of")])
  (TypeRef Secp256k1Base))

;; -- Secp256k1Scalar
(declare-native-entry circuit neg
  "__compactRuntime.secp256k1ScalarNeg"
  ([s (TypeRef Secp256k1Scalar) (discloses "the negation of")])
  (TypeRef Secp256k1Scalar))

(declare-native-entry circuit inv
  "__compactRuntime.secp256k1ScalarInv"
  ([s (TypeRef Secp256k1Scalar) (discloses "the inverse of")])
  (TypeRef Secp256k1Scalar))

;; -- Secp256r1Base
(declare-native-entry circuit neg
  "__compactRuntime.secp256r1BaseNeg"
  ([s (TypeRef Secp256r1Base) (discloses "the negation of")])
  (TypeRef Secp256r1Base))

(declare-native-entry circuit inv
  "__compactRuntime.secp256r1BaseInv"
  ([s (TypeRef Secp256r1Base) (discloses "the inverse of")])
  (TypeRef Secp256r1Base))

;; -- Secp256r1Scalar
(declare-native-entry circuit neg
  "__compactRuntime.secp256r1ScalarNeg"
  ([s (TypeRef Secp256r1Scalar) (discloses "the negation of")])
  (TypeRef Secp256r1Scalar))

(declare-native-entry circuit inv
  "__compactRuntime.secp256r1ScalarInv"
  ([s (TypeRef Secp256r1Scalar) (discloses "the inverse of")])
  (TypeRef Secp256r1Scalar))

;; -- Curve25519Base
(declare-native-entry circuit neg
  "__compactRuntime.curve25519BaseNeg"
  ([s (TypeRef Curve25519Base) (discloses "the negation of")])
  (TypeRef Curve25519Base))

(declare-native-entry circuit inv
  "__compactRuntime.curve25519BaseInv"
  ([s (TypeRef Curve25519Base) (discloses "the inverse of")])
  (TypeRef Curve25519Base))

;; -- Curve25519Scalar
(declare-native-entry circuit neg
  "__compactRuntime.curve25519ScalarNeg"
  ([s (TypeRef Curve25519Scalar) (discloses "the negation of")])
  (TypeRef Curve25519Scalar))

(declare-native-entry circuit inv
  "__compactRuntime.curve25519ScalarInv"
  ([s (TypeRef Curve25519Scalar) (discloses "the inverse of")])
  (TypeRef Curve25519Scalar))

;; ==== Curves
(declare-native-entry circuit jubjubPointX
  "__compactRuntime.jubjubPointX"
  ([pt (TypeRef JubjubPoint) (discloses "the X coordinate of")])
  Field)

(declare-native-entry circuit jubjubPointY
  "__compactRuntime.jubjubPointY"
  ([pt (TypeRef JubjubPoint) (discloses "the Y coordinate of")])
  Field)

(declare-native-entry circuit ecAdd
  "__compactRuntime.ecAdd"
  ([a (TypeRef JubjubPoint) (discloses "an elliptic curve sum including")]
   [b (TypeRef JubjubPoint) (discloses "an elliptic curve sum including")])
  (TypeRef JubjubPoint))

(declare-native-entry circuit ecNeg
  "__compactRuntime.ecNeg"
  ([a (TypeRef JubjubPoint) (discloses "the elliptic curve negation of")])
  (TypeRef JubjubPoint))

(declare-native-entry circuit ecMul
  "__compactRuntime.ecMul"
  ([a (TypeRef JubjubPoint) (discloses "an elliptic curve product including")]
   [b (TypeRef JubjubScalar) (discloses "an elliptic curve product including")])
  (TypeRef JubjubPoint))

(declare-native-entry circuit ecMulGenerator
  "__compactRuntime.ecMulGenerator"
  ([b (TypeRef JubjubScalar) (discloses "the product of the embedded group generator with")])
  (TypeRef JubjubPoint))

(declare-native-entry circuit hashToCurve [A]
  "__compactRuntime.hashToCurve"
  ([value A (discloses "a hash of")])
  (TypeRef JubjubPoint))

(declare-native-entry circuit constructJubjubPoint
  "__compactRuntime.constructJubjubPoint"
  ([x Field (discloses "a JubjubPoint containing X coordinate")]
   [y Field (discloses "a JubjubPoint containing Y coordinate")])
  (TypeRef JubjubPoint))

;; ==== Foreign curve accessors and arithmetic
;; -- Secp256k1Point
(declare-native-entry circuit secp256k1PointX
  "__compactRuntime.secp256k1PointX"
  ([pt (TypeRef Secp256k1Point) (discloses "the x-coordinate of")])
  (TypeRef Secp256k1Base))

(declare-native-entry circuit secp256k1PointY
  "__compactRuntime.secp256k1PointY"
  ([pt (TypeRef Secp256k1Point) (discloses "the y-coordinate of")])
  (TypeRef Secp256k1Base))

(declare-native-entry circuit ecAdd
  "__compactRuntime.secp256k1Add"
  ([a (TypeRef Secp256k1Point) (discloses "an elliptic curve sum including")]
   [b (TypeRef Secp256k1Point) (discloses "an elliptic curve sum including")])
  (TypeRef Secp256k1Point))

(declare-native-entry circuit ecMul
  "__compactRuntime.secp256k1Mul"
  ([a (TypeRef Secp256k1Point) (discloses "an elliptic curve product including")]
   [b (TypeRef Secp256k1Scalar) (discloses "an elliptic curve product including")])
  (TypeRef Secp256k1Point))

(declare-native-entry circuit ecMulGenerator
  "__compactRuntime.secp256k1MulGenerator"
  ([b (TypeRef Secp256k1Scalar) (discloses "the product of the group generator with")])
  (TypeRef Secp256k1Point))

;; -- Secp256r1Point
(declare-native-entry circuit secp256r1PointX
  "__compactRuntime.secp256r1PointX"
  ([pt (TypeRef Secp256r1Point) (discloses "the x-coordinate of")])
  (TypeRef Secp256r1Base))

(declare-native-entry circuit secp256r1PointY
  "__compactRuntime.secp256r1PointY"
  ([pt (TypeRef Secp256r1Point) (discloses "the y-coordinate of")])
  (TypeRef Secp256r1Base))

(declare-native-entry circuit ecAdd
  "__compactRuntime.secp256r1Add"
  ([a (TypeRef Secp256r1Point) (discloses "an elliptic curve sum including")]
   [b (TypeRef Secp256r1Point) (discloses "an elliptic curve sum including")])
  (TypeRef Secp256r1Point))

(declare-native-entry circuit ecMul
  "__compactRuntime.secp256r1Mul"
  ([a (TypeRef Secp256r1Point) (discloses "an elliptic curve product including")]
   [b (TypeRef Secp256r1Scalar) (discloses "an elliptic curve product including")])
  (TypeRef Secp256r1Point))

(declare-native-entry circuit ecMulGenerator
  "__compactRuntime.secp256r1MulGenerator"
  ([b (TypeRef Secp256r1Scalar) (discloses "the product of the group generator with")])
  (TypeRef Secp256r1Point))

;; -- Curve25519Point
(declare-native-entry circuit curve25519PointX
  "__compactRuntime.curve25519PointX"
  ([pt (TypeRef Curve25519Point) (discloses "the x-coordinate of")])
  (TypeRef Curve25519Base))

(declare-native-entry circuit curve25519PointY
  "__compactRuntime.curve25519PointY"
  ([pt (TypeRef Curve25519Point) (discloses "the y-coordinate of")])
  (TypeRef Curve25519Base))

(declare-native-entry circuit ecAdd
  "__compactRuntime.curve25519Add"
  ([a (TypeRef Curve25519Point) (discloses "an elliptic curve sum including")]
   [b (TypeRef Curve25519Point) (discloses "an elliptic curve sum including")])
  (TypeRef Curve25519Point))

(declare-native-entry circuit ecMul
  "__compactRuntime.curve25519Mul"
  ([a (TypeRef Curve25519Point) (discloses "an elliptic curve product including")]
   [b (TypeRef Curve25519Scalar) (discloses "an elliptic curve product including")])
  (TypeRef Curve25519Point))

(declare-native-entry circuit ecMulGenerator
  "__compactRuntime.curve25519MulGenerator"
  ([b (TypeRef Curve25519Scalar) (discloses "the product of the group generator with")])
  (TypeRef Curve25519Point))

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
