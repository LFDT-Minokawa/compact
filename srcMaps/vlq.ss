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

(library (vlq)
  (export vlq-encode vlq-decode vlq-for-testing)
  (import (chezscheme))

#|
  Overview
  --------

  This library implements a pair of procedures, vlq-encode and
  vlq-decode, for encoding lists of integers as Base64-VLQ strings
  and decoding Base64-VLQ strings back into the lists of integers
  they represent.  The Base64-VLQ encoding of a list of integers
  is a textual rather than binary encoding.  It uses 64 printing
  characters: 26 upper-case letters, 26 lower-case letters, 10
  digits, and the two symbols + and /.  The size of the encoding
  is proportional to the magnitudes of the integers, making it most
  efficient for encoding small integer values.  It is used by source
  maps to encode offsets between interesting source positions in a
  file.  These offsets tend to be small or at least much smaller
  than absolute source positions.

  VLQ encodings of nonnegative integers
  -------------------------------------

  The VLQ encoding of a nonnegative integer N represented in binary
  by the bits bₖ ... b₀ is a specific sequence of 6-bit values
  <V₀, V₁, ...> of exactly the length necessary to hold the k bits
  of N.  V₀ contains the lowest order four bits of N (b₃ b₂ b₁ b₀),
  V₁ contains the next five bits (b₈ b₇ b₆ b₅ b₄), V₂ contains the
  next five bits, and so on.  Each 6-bit value V also contains a
  continuation bit; this bit is 1 for all but the last value in the
  sequence and 0 for the last value.  The first value V₀ also
  contains a sign bit, which is 0 for the encoding of nonnegative
  integers.

  The format of the first 6-bit value V₀ is:

     +---+----+----+----+----+---+
     | c | b₃ | b₂ | b₁ | b₀ | s |
     +---+----+----+----+----+---+

  where c is the continuation bit and s is the sign bit.

  (In this and other diagrams of 6-bit values, more-significant
  bits appear to the left of less-significant bits.)

  The format of the second 6-bit value V₁ (if needed) is:

     +---+----+----+----+----+----+
     | c | b₈ | b₇ | b₆ | b₅ | b₄ |
     +---+----+----+----+----+----+

  The subsequent 6-bit values are structured the same as the second,
  with the third containing bits 9 through 13, the fourth containing
  bits 14 through 18, etc.

  VLQ encodings of single negative integers
  -----------------------------------------

  The VLQ encoding of a negative integer M = -N is the same as the
  VLQ encoding of N except that the sign bit s in the first 6-bit
  value V₀ is 1.

  Base64-VLQ encodings of single integers
  ---------------------------------------

  The Base64-VLQ encoding of any integer is the same as its VLQ
  encoding except that each of the 6-bit values is represented by
  a Base64 digit, with 0 represented by A, 1 represented by B, and
  so on for the Base64 digits A-Z, a-z, 0-9, +, and /.

  Example Base64-VLQ encodings of single integers
  -----------------------------------------------

  Example 1: The VLQ encoding of 13₁₀ = 1101₂ is <011010₂>, and its
  Base64-VLQ encoding is "a".

  Explanation: The VLQ encoding of 13₁₀ = 1101₂, which has only
  four significant bits, requires exactly one 6-bit value V₀.

  In V₀, b₃ = 1, b₂ = 1, b₁ = 0, and b₀ = 1, since 13₁₀ = 1101₂:
  
         c   b₃   b₂   b₁   b₀   s  
       +---+----+----+----+----+---+
  V₀ = |   |  1 |  1 |  0 |  1 |   |
       +---+----+----+----+----+---+

  c = 0, since no other 6-bits values are needed:

         c   b₃   b₂   b₁   b₀   s  
       +---+----+----+----+----+---+
  V₀ = | 0 |  1 |  1 |  0 |  1 |   |
       +---+----+----+----+----+---+

  and s = 0, since 13₁₀ is nonnegative:

         c   b₃   b₂   b₁   b₀   s  
       +---+----+----+----+----+---+
  V₀ = | 0 |  1 |  1 |  0 |  1 | 0 |
       +---+----+----+----+----+---+

  The Base64 encoding of V₀ = 011010₂ = 26₁₀ is the 26th Base64
  digit (counted starting at 0), i.e., #\a, so the Base64-VLQ
  encoding of 13₁₀ = "a".

  Example 2: The VLQ encoding of 83₁₀ = 1010011₂ is
  <100110₂, 0001010₂>, and its Base64-VLQ encoding is "mF".

  Explanation: The VLQ encoding of 83₁₀ = 1010011₂, which has seven
  significant bits, requires exactly two 6-bit values V₀ and V₁.

  In V₀, c = 1, since V₀ is not the last value.  b₃ = 0, b₂ = 0,
  b₁ = 1, and b₀ = 1, since the least-significant four bits of
  1010011₂ are 1101.  s is 0, since 83₁₀ is nonnegative:

         c   b₃   b₂   b₁   b₀   s  
       +---+----+----+----+----+---+
  V₀ = | 1 |  0 |  0 |  1 |  1 | 0 |
       +---+----+----+----+----+---+

  In V₁, c = 0, since V₁ is the last value.  b₆ = 1, b₅ = 0, and
  b₄ = 1, since the most-significant three bits of 1010011₂ are
  101.  b₈ = b₇ = 0, since they are effectively leading zeros.

         c   b₈   b₇   b₆   b₅   b₄  
       +---+----+----+----+----+----+
  V₁ = | 0 |  0 |  0 |  1 |  0 |  1 |
       +---+----+----+----+----+----+

  The Base64 encoding of V₀ = 100110₂ = 38₁₀ is #\m, and the Base64
  encoding of V₁ = 101₂ = 5₁₀ is #\F, so that Base64-VLQ encoding
  of 83₁₀ = "mF".

  Example 3: The VLQ encoding of -83₁₀ = -1010011₂ is
  <100111₂, 0001010₂>, and its Base64-VLQ encoding is "nF".

  Explanation: The VLQ encoding of -83₁₀ differs from the VLQ
  encoding of 83₁₀ only in that the sign (least-significant) bit
  of V₀ is 1 rather than 0.

         c   b₃   b₂   b₁   b₀   s  
       +---+----+----+----+----+---+
  V₀ = | 1 |  0 |  0 |  1 |  1 | 1 |
       +---+----+----+----+----+---+

         c   b₈   b₇   b₆   b₅   b₄  
       +---+----+----+----+----+----+
  V₁ = | 0 |  0 |  0 |  1 |  0 |  1 |
       +---+----+----+----+----+----+

  The Base64 encoding of V₀ = 100111₂ = 39₁₀ is #\n, and the Base64
  encoding of V₁ = 101₂ = 5₁₀ is again #\F, so the Base64-VLQ
  encoding of -83₁₀ is "nF".

  Base64-VLQ encodings of sequences of integers, with examples
  ------------------------------------------------------------

  Source maps require the encoding of lists of integers rather than
  just single integers.  The encoding of a list of integers is
  simply the concatenation of the encodings of the elements of the
  list in order, i.e., the characters in the encoding of the first
  integer followed by the characters in the encoding of the second,
  and so on.

  No added delimiter is needed between the encodings of the
  integer elements of a list because the Base64 encoding of the
  last 6-bit value of each integer is effectively marked by
  its continuation bit c = 0.

  Example 4: The Base64-VLQ encoding of '(13 83 -83) is "amFnF".

  Explanation: From Examples 1, 2, and 3 the encodings of 13, 83,
  and -83 are "a", "mF", and "nF".  The concatenation of these three
  strings is "amFnF"

  Encoding a list of integers in Base64-VLQ
  -----------------------------------------

  To encode a list of integers, vlq-encode recurs through the list
  (using fold-right) to build a list of the characters that make
  up the Base64-VLQ encoding of the list, then converts that list
  to a string.  Each step of the recursion builds the characters
  that make up the Base64-VLQ representation of one integer element
  and adds them to the list of characters representing the remaining
  integer elements.  The body of the fold recurs over the value of
  the integer, extracting the characters it needs to construct each
  6-bit value in turn and shifting them off until there are no more
  bits left, i.e., the value of the integer reaches zero.  To
  simplify the setting of the continuation bit (or not), the 6-bit
  value computed on each step of the recursion is passed along to
  the next step, which sets the bit only if the base case has not
  been reached before adding the Base64-encoding of the value to
  the running list of characters.

  Decoding a Base64-VLQ string into a list of integers
  ----------------------------------------------------

  To decode a Base64-VLQ string representing a list of integers
  back to the original list of integers, vlq-decode employs a
  recursive function to build up the list of integers and, on each
  step of the recursion, loops through the characters of the input
  string, consuming characters and building up a single integer
  value until it finds the Base64-encoding of a 6-bit value whose
  continuation bit c = 0.  The remaining characters (if any) of the
  string, if any, are used to decode the remaining integers in the
  list.  Constructing each integer element involves putting the
  bits encoded in the Base64 encodings of the 6-bit values back
  together and negating the result if necessary.

  References
  ----------
  
  https://github.com/champkeh/base64-vlq
    The picture from this is good
  https://docs.google.com/document/d/1U1RGAehQwRypUTovF1KRlpiOFze0b-_2gc6fAH0KY0k/
    This is as close as we can get to specification for VLQ variant used in source maps: base64 VLQ encoding using 7 bit words
    More popular variant used in MIDI format is usually described when one is looking for VLQ. Wiki description uses words of length 8 bits.
  https://github.com/Rich-Harris/vlq
    The referential implementation by author of the source maps description.
|#

  (module base64 (base64-encode base64-decode)
    (define encodings "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    (define decodings
      (let ([ht (make-hashtable char->integer eqv?)])
        (let ([c* (string->list encodings)])
          (for-each (lambda (c i) (hashtable-set! ht c i)) c* (enumerate c*))
          ht)))
    (define (base64-encode n)
      (string-ref encodings n))
    (define (base64-decode c)
      (or (hashtable-ref decodings c #f)
          (errorf 'base64-decode "~s is not a valid Base64 digit" c))))

  (import base64)

  (define (vlq-encode n*)
    (unless (and (list? n*) (andmap (lambda (n) (and (integer? n) (exact? n))) n*))
      (errorf 'vlq-encode "~s is not a list of exact integers" n*))
    (list->string
      (fold-right
        (lambda (n char*)
          (let-values ([(sign-bit n) (if (< n 0) (values 1 (- n)) (values 0 n))])
            (let f ([b (fxlogor (fxsll (bitwise-bit-field n 0 4) 1) sign-bit)]
                    [n (ash n -4)])
              (if (eqv? n 0)
                  (cons (base64-encode b) char*)
                  (cons (base64-encode (fxlogor #b100000 b))
                        (f (bitwise-bit-field n 0 5) (ash n -5)))))))
        '()
        n*)))

  (define (vlq-decode str)
    (unless (string? str) (errorf 'vlq-decode "~s is not a string" str))
    (let ([n (string-length str)])
      (let next-vlq ([i 0])
        (if (fx= i n)
            '()
            (let* ([b (base64-decode (string-ref str i))]
                   [val (fxbit-field b 1 5)]
                   [neg? (fxbit-set? b 0)])
              (let next-byte ([i (fx+ i 1)] [last-b b] [val val] [shift 4])
                (if (fxbit-set? last-b 5)
                    (if (fx= i n)
                        (errorf 'vlq-decode "final byte ~s of ~s has continuation bit set" b str)
                        (let* ([b (base64-decode (string-ref str i))]
                               [val (logor val (ash (fxbit-field b 0 5) shift))])
                          (next-byte (fx+ i 1) b val (+ shift 5))))
                    (cons (if neg? (- val) val) (next-vlq i)))))))))

  (module vlq-for-testing (base64-encode base64-decode)
    (import base64)
  )
)
