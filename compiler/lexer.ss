#!chezscheme

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

;;; Some portions of this code are adapted from Chez Scheme
;;; examples/ez-grammar-test.ss, which is covered by the following
;;; copyright notice:
;;;
;;; Copyright 2017 Cisco Systems, Inc.
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;; http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

(library (lexer)
  (export lexer)
  (import (except (chezscheme) errorf)
          (utils)
          (state-case)
          (streams)
          (only (field) field?)
          (rename (only (lparser) make-token) (make-token $make-token))
          (only (version) make-version))

  (define lexer
    (lambda (sfd file-content)
      (module (getc ungetc make-token current-col current-src)
        (define prev-pos 0)
        (define prev-line 1)
        (define prev-col 1)
        (define pos 0)
        (define line 1)
        (define col 1)
        (define final-cols '())
        (define (getc)
          (let ([c (if (fx>= pos (string-length file-content))
                       #!eof
                       (string-ref file-content pos))])
            (set! pos (fx+ pos 1))
            (if (eqv? c #\newline)
                (begin
                  (set! line (fx+ line 1))
                  (set! final-cols (cons col final-cols))
                  (set! col 1))
                (set! col (fx+ col 1)))
            c))
        (define (ungetc c)
          (set! pos (fx- pos 1))
          (if (eqv? col 1)
              (begin
                (set! col (car final-cols))
                (set! final-cols (cdr final-cols))
                (set! line (fx- line 1)))
              (set! col (fx- col 1))))
        (define (make-token type value)
          (let ([str (if (eq? type 'eof) "" (substring file-content prev-pos pos))]
                [src (make-source-object sfd prev-pos pos prev-line prev-col)])
            (set! prev-pos pos)
            (set! prev-line line)
            (set! prev-col col)
            ($make-token src type value str)))
        (define (current-col) col)
        (define (current-src offset)
          (let-values ([(line col) (let loop ([offset offset] [final-cols final-cols] [line line] [col col])
                                     (if (fx= offset 0)
                                         (values line col)
                                         (if (fx= col 1)
                                             (loop (fx+ offset 1) (cdr final-cols) (fx- line 1) (car final-cols))
                                             (loop (fx+ offset 1) final-cols line (fx- col 1)))))])
            (make-source-object sfd pos pos line col))))
      (define (unexpected c)
        (source-errorf (current-src -1) "unexpected ~a"
          (case c
            [(#!eof) "end of file"]
            [(#\newline) "newline"]
            [else (format "character '~c'" c)])))
      (define (nested-comment-error)
        (source-errorf (current-src -2) "attempt to nest block comment"))
      (let-values ([(sp get-buf) (open-string-output-port)])
        (define (return-eof)
          (stream-cons (make-token 'eof #!eof) stream-nil))
        (define (return-token type value)
          (stream-cons (make-token type value) lex))
        (define-syntax define-state-case
          (syntax-rules (eof else)
            [(_ ?def-id ?char-id clause ...)
             (identifier? #'?def-id)
             (define-state-case (?def-id) ?char-id clause ...)]
            [(_ (?def-id . args) ?char-id (eof eof1 eof2 ...) clause ... (else else1 else2 ...))
             (and (identifier? #'?def-id) (identifier? #'?char-id))
             (define (?def-id . args)
               (let ([?char-id (getc)])
                 (state-case ?char-id (eof eof1 eof2 ...) clause ... (else else1 else2 ...))))]
            [(_ (?def-id . args) ?char-id clause ... (else else1 else2 ...))
             (and (identifier? #'?def-id) (identifier? #'?char-id))
             (define (?def-id . args)
               (let ([?char-id (getc)])
                 (let ([f (lambda () else1 else2 ...)])
                   (state-case ?char-id (eof (f)) clause ... (else (f))))))]))
        (define-state-case lex c
          [eof (return-eof)]
          [char-whitespace? (put-char sp c) (lex-whitespace)]
          [identifier-initial? (lex-identifier c)]
          [#\0 (lex-zero)]
          [((#\1 - #\9)) (lex-decimal c)]
          [#\" (lex-string (lambda (c) (eqv? c #\")))]
          [#\' (lex-string (lambda (c) (eqv? c #\')))]
          [#\/ (seen-slash)]
          [#\+ (seen-plus)]
          [#\- (seen-minus)]
          [#\* (return-token 'binop c)]
          [#\# (return-token 'punctuation c)]
          [#\= (seen-equal)]
          [#\! (seen-bang)]
          [#\< (seen-lt)]
          [#\> (seen-gt)]
          [#\& (seen-ampersand)]
          [#\| (seen-vertical-bar)]
          [#\. (seen-leading-dot)]
          [(#\: #\; #\, #\( #\) #\{ #\} #\[ #\] #\?)
           (return-token 'punctuation c)]
          [else (unexpected c)])
        (module (identifier-initial? lex-identifier)
          (define identifier-initial?
            (lambda (c)
              (or (char-alphabetic? c)
                  (memv c '(#\_ #\$)))))
          (define identifier-subsequent?
            (lambda (c)
              (or (identifier-initial? c)
                  (char<=? #\0 c #\9))))
          (define (id)
            (return-token 'id (string->symbol (get-buf))))
          (define-state-case next c
            [identifier-subsequent? (lex-identifier c)]
            [else (ungetc c) (id)])
          (define (lex-identifier c) (put-char sp c) (next)))
        (define-state-case lex-zero c
          [char-numeric?
           (source-errorf (current-src -2)
                          "unsupported numeric syntax syntax: leading 0 must be followed by b, B, o, O, x, X")]
          [(#\b #\B) (lex-binary)]
          [(#\o #\O) (lex-octal)]
          [(#\x #\X) (lex-hexadecimal)]
          [(#\.) (seen-one-dot 0)]
          [else (ungetc c) (return-token 'field 0)])
        (define (return-field n)
          (unless (field? n)
            (source-errorf (current-src (- (string-length (number->string n)))) "~s is out of Field range" n))
          (return-token 'field n))
        (module (lex-binary)
          (define-state-case lex-binary c
            [((#\0 - #\1)) (next (char- c #\0))]
            [((#\2 - #\9)) (source-errorf (current-src -1) "unexpected digit ~a (expected 0 or 1)" c)]
            [else (unexpected c)])
          (define-state-case (next n) c
            [((#\0 - #\1)) (next (+ (* n 2) (char- c #\0)))]
            [((#\2 - #\9)) (source-errorf (current-src -1) "unexpected digit ~a (expected 0 or 1)" c)]
            [else (ungetc c) (return-field n)]))
        (module (lex-octal)
          (define-state-case lex-octal c
            [((#\0 - #\7)) (next (char- c #\0))]
            [((#\8 - #\9)) (source-errorf (current-src -1) "unexpected digit ~a (expected 0 through 7)" c)]
            [else (unexpected c)])
          (define-state-case (next n) c
            [((#\0 - #\7)) (next (+ (* n 8) (char- c #\0)))]
            [((#\8 - #\9)) (source-errorf (current-src -1) "unexpected digit ~a (expected 0 through 7)" c)]
            [else (ungetc c) (return-field n)]))
        (module (lex-hexadecimal)
          (define-state-case lex-hexadecimal c
            [((#\0 - #\9)) (next (char- c #\0))]
            [((#\a - #\f)) (next (fx+ (char- c #\a) 10))]
            [((#\A - #\F)) (next (fx+ (char- c #\A) 10))]
            [else (unexpected c)])
          (define-state-case (next n) c
            [((#\0 - #\9)) (next (+ (* n 16) (char- c #\0)))]
            [((#\a - #\f)) (next (+ (* n 16) (fx+ (char- c #\a) 10)))]
            [((#\A - #\F)) (next (+ (* n 16) (fx+ (char- c #\A) 10)))]
            [else (ungetc c) (return-field n)]))
        (module (lex-decimal)
          (define-state-case next c
            [((#\0 - #\9)) (lex-decimal c)]
            [(#\.) (seen-one-dot (string->number (get-buf)))]
            [else (ungetc c) (return-field (string->number (get-buf)))])
          (define (lex-decimal c) (put-char sp c) (next)))
        (module (lex-string)
          (define-state-case (lex-string terminator?) c
            [eof (unexpected c)]
            [terminator? (return-token 'string (get-buf))]
            [#\\ (backslash terminator?)]
            [else (put-char sp c) (lex-string terminator?)])
          (define-state-case (backslash terminator?) c
            [(#\" #\' #\\) (put-char sp c) (lex-string terminator?)]
            [#\n (put-char sp #\newline) (lex-string terminator?)]
            [#\r (put-char sp #\return) (lex-string terminator?)]
            [#\0 (put-char sp #\nul) (lex-string terminator?)]
            [#\b (put-char sp #\backspace) (lex-string terminator?)]
            [#\f (put-char sp #\page) (lex-string terminator?)]
            [#\t (put-char sp #\tab) (lex-string terminator?)]
            [#\v (put-char sp #\vtab) (lex-string terminator?)]
            [#\u (hexchar 0 4 terminator?)]
            [#\x (hexchar 0 2 terminator?)]
            [#\newline (lex-string terminator?)]
            [else (unexpected c)])
          (define-state-case (hexchar a n terminator?) c
            [((#\0 - #\9)) (hexchar-next (+ (* a 16) (char- c #\0)) n terminator?)]
            [((#\a - #\f)) (hexchar-next (+ (* a 16) (fx+ (char- c #\a) 10)) n terminator?)]
            [((#\A - #\F)) (hexchar-next (+ (* a 16) (fx+ (char- c #\A) 10)) n terminator?)]
            [else (unexpected c)])
          (define (hexchar-next a n terminator?)
            (if (fx= n 1)
                (begin
                  (put-char sp (integer->char a))
                  (lex-string terminator?))
                (hexchar a (fx- n 1) terminator?))))
        (define-state-case (seen-one-dot n1) c
          [((#\0 - #\9)) (put-char sp c) (seen-one-dot+decimal n1)]
          [(#\.) (ungetc c) (ungetc c) (return-field n1)]
          [else (unexpected c)])
        (define-state-case (seen-one-dot+decimal n1) c
          [((#\0 - #\9)) (put-char sp c) (seen-one-dot+decimal n1)]
          [(#\.) (seen-two-dots n1 (string->number (get-buf)))]
          [else (ungetc c) (return-token 'version (make-version '* n1 (string->number (get-buf)) '*))])
        (define-state-case (seen-two-dots n1 n2) c
          [((#\0 - #\9)) (put-char sp c) (seen-two-dots+decimal n1 n2)]
          [else (unexpected c)])
        (define-state-case (seen-two-dots+decimal n1 n2) c
          [((#\0 - #\9)) (put-char sp c) (seen-two-dots+decimal n1 n2)]
          [else (ungetc c) (return-token 'version (make-version '* n1 n2 (string->number (get-buf))))])
        (define-state-case seen-plus c
          [#\= (return-token 'binop "+=")]
          [else (ungetc c) (return-token 'binop #\+)])
        (define-state-case seen-minus c
          [#\= (return-token 'binop "-=")]
          [else (ungetc c) (return-token 'binop #\-)])
        (define-state-case seen-equal c
          [#\= (return-token 'binop "==")]
          [#\> (return-token 'punctuation "=>")]
          [else (ungetc c) (return-token 'binop #\=)])
        (define-state-case seen-bang c
          [#\= (return-token 'binop "!=")]
          [else (ungetc c) (return-token 'punctuation #\!)])
        (define-state-case seen-lt c
          [#\= (return-token 'binop "<=")]
          [else (ungetc c) (return-token 'binop #\<)])
        (define-state-case seen-gt c
          [#\= (return-token 'binop ">=")]
          [else (ungetc c) (return-token 'binop #\>)])
        (define-state-case seen-ampersand c
          [#\& (return-token 'binop "&&")]
          [else (unexpected c)])
        (define-state-case seen-vertical-bar c
          [#\| (return-token 'binop "||")]
          [else (unexpected c)])
        (define-state-case seen-leading-dot c
          [#\. (seen-two-leading-dots)]
          [else (ungetc c) (return-token 'punctuation #\.)])
        (define-state-case seen-two-leading-dots c
          [#\. (seen-three-leading-dots)]
          [else (ungetc c) (return-token 'punctuation "..")])
        (define-state-case seen-three-leading-dots c
          [#\. (unexpected c)]
          [else (ungetc c) (return-token 'punctuation "...")])
        (define-state-case lex-whitespace c
          [char-whitespace? (put-char sp c) (lex-whitespace)]
          [else (ungetc c) (return-token 'whitespace (get-buf))])
        (define-state-case seen-slash c
          [#\* (lex-block-comment)]
          [#\/ (lex-line-comment)]
          [else (ungetc c) (return-token 'binop #\/)])
        (define-state-case lex-line-comment c
          [eof (ungetc c) (return-token 'line-comment (get-buf))]
          [#\newline (ungetc c) (return-token 'line-comment (get-buf))]
          [else (put-char sp c) (lex-line-comment)])
        (define (lex-block-comment)
          ; leading whitespace on the second and subsequent lines is trimmed so
          ; that they line up properly with the base of the first.  For example,
          ; for the block comment below:
          ;   return; /* first line ...
          ;              second line ...
          ;           */
          ; the lexer produces a block-comment token with value:
          ;   "/* first line ...\n   second line...\n*/".
          ; for this purpose, tab stops are assumed to be at multiples of 8.
          ; (current-col) is one-based.  subtract one for that plus two for "/*"
          (let ([base (fx- (current-col) 3)])
            (define-state-case (skip-spaces n) c
              [eof (unexpected c)]
              [#\space (skip-spaces (fx+ n 1))]
              [#\tab (skip-spaces (fx+ n (fx- 8 (fxmod n 8))))]
              [else
               (when (fx> n base) (put-string sp (make-string (fx- n base) #\space)))
               (lex-block-comment c)])
            (define-state-case maybe-end-comment c
              [eof (unexpected c)]
              [#\/ (return-token 'block-comment (get-buf))]
              [else (put-char sp #\*) (lex-block-comment c)])
            (define-state-case maybe-nested-comment c
              [eof (unexpected c)]
              [#\* (nested-comment-error)]
              [else (lex-block-comment c)])
            (define (lex-block-comment c)
              (state-case c
                [eof (unexpected c)]
                [#\newline (put-char sp c) (skip-spaces 0)]
                [#\* (maybe-end-comment)]
                [#\/ (put-char sp c) (maybe-nested-comment)]
                [else (put-char sp c) (lex-block-comment (getc))]))
            (lex-block-comment (getc))))
        (lex))))
)
