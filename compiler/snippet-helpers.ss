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

(library (snippet-helpers)
  (export get-requested-snippets insert-requested-snippets)
  (import (chezscheme)
          (state-case))

  (define who)
  (define anchor-ht)

  (define (title->anchor title)
    (let ([candidate 
            (list->string
              (fold-right
                (lambda (c c*)
                  (cond
                    [(char-alphabetic? c) (cons (char-downcase c) c*)]
                    [(eqv? c #\space) (cons #\- c*)]
                    [else c*]))
                '()
                (string->list title)))])
      (let ([a (hashtable-cell anchor-ht candidate 0)])
        (let ([n (cdr a)])
          (set-cdr! a (fx+ n 1))
          (if (eqv? n 0)
              candidate
              (format "~a-~d" candidate n))))))

  (define (parse-text line line-number found-anchor found-request found-code found-nada)
    (let ([n (string-length line)])
      (define (getc i) (and (fx< i n) (string-ref line i)))
      (define (s0)
        (case (getc 0)
          [(#\#) (seen-hash 1)]
          [(#\@) (seen-at 1)]
          [(#\`) (seen-backquote 1)]
          [else (found-nada)]))
      (define (seen-hash i)
        (case (getc i)
          [(#\#) (seen-hash (fx+ i 1))]
          [(#\space) (seen-hash-space (fx+ i 1))]
          [else (errorf who "invalid header on line ~d: ~s" line-number line)]))
      (define (seen-hash-space i)
        (case (getc i)
          [(#\space) (seen-hash-space (fx+ i 1))]
          [(#f) (errorf who "invalid header on line ~d: ~s" line-number line)]
          [else (seen-title-char i (fx+ i 1))]))
      (define (seen-title-char start i)
        (case (getc i)
          [(#f #\{) (found-anchor (title->anchor (substring line start i)))]
          [else (seen-title-char start (fx+ i 1))]))
      (define (seen-at i)
        (case (getc i)
          [(#\()
           (found-request
             (guard (c [else (errorf who
                                     "error reading @ form on line ~d: ~a"
                                     line-number
                                     (with-output-to-string
                                       (lambda () (display-condition c))))])
               (read (open-input-string (substring line i n)))))]
          [else (found-nada)]))
      (define (seen-backquote i)
        (if (fx= i 3)
            (found-code)
            (case (getc i)
              [(#\`) (seen-backquote (fx+ i 1))]
              [else (found-nada)])))
      (s0)))

  (define (code-end? line)
    (let ([n (string-length line)])
      (define (getc i) (and (fx< i n) (string-ref line i)))
      (define (s0)
        (case (getc 0)
          [(#\`) (seen-backquote 1)]
          [else #f]))
      (define (seen-backquote i)
        (or (fx= i 3)
            (case (getc i)
              [(#\`) (seen-backquote (fx+ i 1))]
              [else #f])))
      (s0)))

  (define (get-requested-snippets proto-file)
    (fluid-let ([who 'get-requested-snippets]
                [anchor-ht (make-hashtable string-hash string=?)])
      (call-with-port
        (open-input-file proto-file)
        (lambda (ip)
          (let f ([current-anchor #f] [line-number 0])
            (let ([line (get-line ip)] [line-number (fx+ line-number 1)])
              (if (eof-object? line)
                  '()
                  (parse-text line line-number
                    (lambda (anchor) (f anchor line-number))
                    (lambda (req)
                      (cons
                        (syntax-case req ()
                          [(?anchor-here name ...)
                           (and (eq? #'?anchor-here 'anchor-here) (andmap symbol? #'(name ...)))
                           `(anchor-here ,current-anchor ,@#'(name ...))]
                          [(?request-snippet name ...)
                           (and (eq? #'?request-snippet 'request-snippet) (andmap symbol? #'(name ...)))
                           `(request-snippet ,current-anchor ,@#'(name ...))]
                          [else (errorf who "malformed snippet request on line ~d: ~s" line-number req)])
                        (f current-anchor line-number)))
                    (lambda ()
                      (let loop ([line-number^ line-number])
                        (let ([line (get-line ip)] [line-number^ (fx+ line-number^ 1)])
                          (cond
                            [(eof-object? line)
                             (errorf who
                                     "file ended in code block that started on line ~d"
                                     line-number)]
                            [(code-end? line) (f current-anchor line-number^)]
                            [else (loop line-number^)]))))
                    (lambda () (f current-anchor line-number))))))))))
  
  (define (insert-requested-snippets snippet* proto-file output-file)
    (define (put-line op line) (fprintf op "~a\n" line))
    (fluid-let ([who 'insert-requested-snippets]
                [anchor-ht (make-hashtable string-hash string=?)])
      (call-with-port
        (open-input-file proto-file)
        (lambda (ip)
          (call-with-port
            (open-output-file output-file 'replace)
            (lambda (op)
              (let outer ([snippet* snippet*] [line-number 0])
                (let ([line (get-line ip)] [line-number (fx+ line-number 1)])
                  (unless (eof-object? line)
                    (parse-text line line-number
                      (lambda (anchor)
                        (put-line op line)
                        (outer snippet* line-number))
                      (lambda (req)
                        (syntax-case req ()
                          [(?anchor-here name ...)
                           (and (eq? #'?anchor-here 'anchor-here) (andmap symbol? #'(name ...)))
                           (outer snippet* line-number)]
                          [(?request-snippet name ...)
                           (and (eq? #'?request-snippet 'request-snippet) (andmap symbol? #'(name ...)))
                           (begin
                             (put-string op (car snippet*))
                             (outer (cdr snippet*) line-number))]
                          [else (errorf who "malformed snippet request on line ~d: ~s" line-number req)]))
                      (lambda ()
                        (put-line op line)
                        (let inner ([line-number^ line-number])
                          (let ([line (get-line ip)] [line-number^ (fx+ line-number^ 1)])
                            (cond
                              [(eof-object? line)
                               (errorf who
                                       "file ended in code block that started on line ~d"
                                       line-number)]
                              [(code-end? line) (put-line op line) (outer snippet* line-number^)]
                              [else (put-line op line) (inner line-number^)]))))
                      (lambda ()
                        (put-line op line)
                        (outer snippet* line-number))))))))))))
)
