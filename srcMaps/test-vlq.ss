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

(import
  (rough-draft unit-test)
  (rough-draft console-test-runner)
  (vlq)
  (chezscheme))

(import vlq-for-testing)

(define-test-suite vlq-tests

  (define-test base64-decode-test
    (assert-equal? (base64-decode #\A) 0)
    (assert-equal? (base64-decode #\Z) 25)
    (assert-equal? (base64-decode #\a) 26)
    (assert-equal? (base64-decode #\y) 50)
    (assert-equal? (base64-decode #\z) 51)
    (assert-equal? (base64-decode #\0) 52)
    (assert-equal? (base64-decode #\9) 61)
    (assert-equal? (base64-decode #\+) 62)
    (assert-equal? (base64-decode #\/) 63)
  )

  (define-test base64-encode-test
    (assert-equal? (base64-encode 0)  #\A)
    (assert-equal? (base64-encode 1)  #\B)
    (assert-equal? (base64-encode 9)  #\J)
    (assert-equal? (base64-encode 25) #\Z)
    (assert-equal? (base64-encode 26) #\a)
    (assert-equal? (base64-encode 51) #\z)
    (assert-equal? (base64-encode 52) #\0)
    (assert-equal? (base64-encode 61) #\9)
    (assert-equal? (base64-encode 62) #\+)
    (assert-equal? (base64-encode 63) #\/)
  )

  (define-test vlq-decode-test
    (assert-equal? (vlq-decode "A")  '(0))
    (assert-equal? (vlq-decode "B")  '(0))
    (assert-equal? (vlq-decode "C")  '(1))
    (assert-equal? (vlq-decode "D")  '(-1))
    (assert-equal? (vlq-decode "E")  '(2))
    (assert-equal? (vlq-decode "F")  '(-2))
    (assert-equal? (vlq-decode "G")  '(3))
    (assert-equal? (vlq-decode "H")  '(-3))
    (assert-equal? (vlq-decode "I")  '(4))
    (assert-equal? (vlq-decode "J")  '(-4))
    (assert-equal? (vlq-decode "K")  '(5))
    (assert-equal? (vlq-decode "L")  '(-5))
    (assert-equal? (vlq-decode "M")  '(6))
    (assert-equal? (vlq-decode "N")  '(-6))
    (assert-equal? (vlq-decode "O")  '(7))
    (assert-equal? (vlq-decode "P")  '(-7))
    (assert-equal? (vlq-decode "Q")  '(8))
    (assert-equal? (vlq-decode "R")  '(-8))
    (assert-equal? (vlq-decode "S")  '(9))
    (assert-equal? (vlq-decode "T")  '(-9))
    (assert-equal? (vlq-decode "U")  '(10))
    (assert-equal? (vlq-decode "V")  '(-10))
    (assert-equal? (vlq-decode "W")  '(11))
    (assert-equal? (vlq-decode "X")  '(-11))
    (assert-equal? (vlq-decode "Y")  '(12))
    (assert-equal? (vlq-decode "Z")  '(-12))
    (assert-equal? (vlq-decode "a")  '(13))
    (assert-equal? (vlq-decode "b")  '(-13))
    (assert-equal? (vlq-decode "c")  '(14))
    (assert-equal? (vlq-decode "d")  '(-14))
    (assert-equal? (vlq-decode "e")  '(15))
    (assert-equal? (vlq-decode "f")  '(-15))
    
    (assert-equal? (vlq-decode "1B") '(-26))
    (assert-equal? (vlq-decode "/B") '(-31))
    
    (assert-equal? (vlq-decode "gB") '(16))
    (assert-equal? (vlq-decode "iB") '(17))
    (assert-equal? (vlq-decode "kB") '(18))
    (assert-equal? (vlq-decode "sB") '(22))
    (assert-equal? (vlq-decode "yB") '(25))
    
    (assert-equal? (vlq-decode "kD") '(50))
    (assert-equal? (vlq-decode "wM") '(200))
    (assert-equal? (vlq-decode "wc") '(456))
    (assert-equal? (vlq-decode "qxB") '(789))
    (assert-equal? (vlq-decode "2H")  '(123))
    (assert-equal? (vlq-decode "+/////D") '(2147483647))

    (assert-equal? (vlq-decode "a") '(13))
    (assert-equal? (vlq-decode "mF") '(83))
    (assert-equal? (vlq-decode "nF") '(-83))

    ; these tests are adapted from https://github.com/Rich-Harris/vlq/tree/master/test
    ; covered by an MIT license https://github.com/Rich-Harris/vlq/blob/master/LICENSE
    (assert-equal? (vlq-decode "AAAA") '(0 0 0 0))
    (assert-equal? (vlq-decode "AAgBC") '(0 0 16 1))
    (assert-equal? (vlq-decode "D") '(-1))
    ; NB: this is a broken test that reflects a bug in their implementation
    ; (assert-equal? (vlq-decode "B") '(-2147483648))
    (assert-equal? (vlq-decode "+/////D") '(2147483647))

    ; this test is adapted from an example given in:
    ; https://www.lucidchart.com/techblog/2019/08/22/decode-encoding-base64-vlqs-source-maps/
    (assert-equal? (vlq-decode "wkpykpCQjF") '(1227133512 8 -81))
  )

  (define-test vlq-decode-errors
    (assert-error (vlq-decode '(3)) "(3) is not a string")
    (assert-error (vlq-decode "0") "final byte 52 of \"0\" has continuation bit set")
    (assert-error (vlq-decode "AAA*") "#\\* is not a valid Base64 digit")
    (assert-error (vlq-decode "AAA\x80;") "#\\\x80; is not a valid Base64 digit")
    (assert-error (vlq-decode "AAA\x3bb;") "#\\\x3bb; is not a valid Base64 digit")
  )

  (define-test vlq-encode-test
    (assert-equal? (vlq-encode '(0))   "A")
    (assert-equal? (vlq-encode '(1))   "C")
    (assert-equal? (vlq-encode '(-1))  "D")
    (assert-equal? (vlq-encode '(2))   "E")
    (assert-equal? (vlq-encode '(-2))  "F")
    (assert-equal? (vlq-encode '(3))   "G")
    (assert-equal? (vlq-encode '(-3))  "H")
    (assert-equal? (vlq-encode '(4))   "I")
    (assert-equal? (vlq-encode '(-4))  "J")
    (assert-equal? (vlq-encode '(5))   "K")
    (assert-equal? (vlq-encode '(-5))  "L")
    (assert-equal? (vlq-encode '(6))   "M")
    (assert-equal? (vlq-encode '(-6))  "N")
    (assert-equal? (vlq-encode '(7))   "O")
    (assert-equal? (vlq-encode '(-7))  "P")
    (assert-equal? (vlq-encode '(8))   "Q")
    (assert-equal? (vlq-encode '(-8))  "R")
    (assert-equal? (vlq-encode '(9))   "S")
    (assert-equal? (vlq-encode '(-9))  "T")
    (assert-equal? (vlq-encode '(10))  "U")
    (assert-equal? (vlq-encode '(-10)) "V")
    (assert-equal? (vlq-encode '(11))  "W")
    (assert-equal? (vlq-encode '(-11)) "X")
    (assert-equal? (vlq-encode '(12))  "Y")
    (assert-equal? (vlq-encode '(-12)) "Z")
    (assert-equal? (vlq-encode '(13))  "a")
    (assert-equal? (vlq-encode '(-13)) "b")
    (assert-equal? (vlq-encode '(14))  "c")
    (assert-equal? (vlq-encode '(-14)) "d")
    (assert-equal? (vlq-encode '(15))  "e")
    (assert-equal? (vlq-encode '(-15)) "f")
    
    (assert-equal? (vlq-encode '(-26)) "1B")
    (assert-equal? (vlq-encode '(-31)) "/B")
    
    (assert-equal? (vlq-encode '(16)) "gB")
    (assert-equal? (vlq-encode '(17)) "iB")
    (assert-equal? (vlq-encode '(18)) "kB")
    (assert-equal? (vlq-encode '(22)) "sB")
    (assert-equal? (vlq-encode '(25)) "yB")
    
    (assert-equal? (vlq-encode '(50)) "kD")
    (assert-equal? (vlq-encode '(200)) "wM")
    (assert-equal? (vlq-encode '(456)) "wc")
    (assert-equal? (vlq-encode '(789)) "qxB")
    (assert-equal? (vlq-decode "2H")  '(123))
    (assert-equal? (vlq-encode '(2147483647)) "+/////D")

    (assert-equal? (vlq-encode '(13)) "a")
    (assert-equal? (vlq-encode '(83)) "mF")
    (assert-equal? (vlq-encode '(-83)) "nF")

    ; these tests are adapted from https://github.com/Rich-Harris/vlq/tree/master/test
    ; covered by an MIT license https://github.com/Rich-Harris/vlq/blob/master/LICENSE
    (assert-equal? (vlq-encode '(0 0 0 0)) "AAAA")
    (assert-equal? (vlq-encode '(0 0 16 1)) "AAgBC")
    (assert-equal? (vlq-encode '(-1)) "D")
    ; NB: this is a broken test that reflects a bug in their implementation
    ; (assert-equal? (vlq-encode '(-2147483648)) "B")
    (assert-equal? (vlq-encode '(2147483647)) "+/////D")

    ; this test is adapted from an example given in:
    ; https://www.lucidchart.com/techblog/2019/08/22/decode-encoding-base64-vlqs-source-maps/
    (assert-equal? (vlq-encode '(1227133512 8 -81)) "wkpykpCQjF")
  )

  (define-test vlq-decode-errors
    (assert-error (vlq-encode "0") "\"0\" is not a list of exact integers")
    (assert-error (vlq-encode '(a)) "(a) is not a list of exact integers")
    (assert-error (vlq-encode '(3 . 4)) "(3 . 4) is not a list of exact integers")
  )
)

(run-test-suite vlq-tests)
