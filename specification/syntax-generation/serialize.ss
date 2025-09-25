;;; This file is part of Compact.
;;; Copyright (C) 2025 Midnight Foundation
;;; SPDX-License-Identifier: Apache-2.0
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;  	http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

;;
;; This file defines serialization of nanopass IRs to a JSON representation 
;; 

#!chezscheme
(import (chezscheme) (nanopass) (langs) (compiler-version) (language-version))

(display "=== serializing Nanopass IR ===")
(newline)
(display "Compiler version: ")
(display compiler-version-string)
(newline)
(display "Language version: ")
(display language-version-string)
(newline)

;; Get S-expressions for IR definitions


;; Read command line arguments defining the IR that we want to
;; serialize, as well as the output path for the serialized JSON. 
(define args (cdr (command-line)))
(define ir-str (car args))        
(define json-path (car (cdr args)))

(display "IR name:")
(display ir-str)
(newline)
(display "JSON path:")
(display json-path)
(newline)

(display " -> Looking up symbol and converting to S-expression.")
(newline)

;; !! Dynamic lookup of IR symbol fails here, how to fix ??

;; For now, we solve this with a dirty search and replace with `sed`
;; in the shell script that invokes this module.

(define s-expr
  (cons (cons "Compiler version" (cons compiler-version-string '()))
	(cons (cons "Language version" (cons language-version-string '()))
	      (language->s-expression IR_SYMBOL))))

  
;;
;; Code below serializes S-expressions to JSON 
;; 

(define (serialize-atom atom)
  (cond
    ((number? atom) (number->string atom))           ;; Numbers to JSON numbers
    ((string? atom) (string-append "\"" atom "\""))  ;; Strings to JSON strings
    ((symbol? atom) (string-append "\"" (symbol->string atom) "\"")) ;; Symbols to JSON strings
    (else "\"null\"")))                              ;; Anything else becomes "null"

(define (serialize-list sexpr)
  (if (and (list? (car sexpr))                       ;; Check if it's an object-like list
           (symbol? (car sexpr)))                   ;; Keys must be symbols
      (serialize-object sexpr)                       ;; Call object serializer
      (serialize-array sexpr)))                      ;; Otherwise, treat it as an array

(define (serialize-object pairs)
  (let ((serialized-pairs 
          (map (lambda (pair)
                 (string-append (serialize-atom (car pair)) ": "
                                (serialize-sexp (cadr pair)))) pairs)))
    (string-append "{" (string-join serialized-pairs ", ") "}")))

(define (serialize-array elements)
  (let ((serialized-elements (map serialize-sexp elements)))
    (string-append "[" (string-join serialized-elements ", ") "]")))

(define (serialize-sexp sexpr)
  (cond
    ((list? sexpr) (serialize-list sexpr))         ;; If it's a list, serialize as array or object
    (else (serialize-atom sexpr))))                  ;; Otherwise, treat it as an atom

;; Helper function to join strings
(define (string-join lst sep)
  (apply string-append
         (let loop ((lst lst) (first #t))
           (if (null? lst)
               '()
               (cons (if first
                         (car lst)
                         (string-append sep (car lst)))
                     (loop (cdr lst) #f))))))



(display " -> Serializing S-expression to JSON.")
(newline)
(define json-string (serialize-sexp s-expr))

(define json-out (open-output-file json-path 'truncate))
(display json-string json-out)
(close-output-port json-out)
(display "Done.")
(exit) 
