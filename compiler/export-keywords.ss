#! /usr/bin/env -S scheme --program
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

(import (parser) (chezscheme))

(define out-path
  (let ([args (cdr (command-line))])
    (case (length args)
      [(0) "editor-support/vsc/compact/tests/resources/keywords.json"]
      [(1) (car args)]
      [else (fprintf (current-error-port) "usage: ~a [ output-path ]\n" (car (command-line)))
            (exit 1)])))

; KD := tuple (name of group of keywords , keywords list)
(define (kd-name  kd) (car kd))
(define (kd-words kd) (cadr kd))

;; get input
(define input-kd (parser-keywords))

;; JSON utils
(define (json-str str sep)
  (format "~a\"~a\"" sep str))
(define (json-entry key value)
  (string-append
    (json-str key "  ")
    ":"
    (json-str value " ")))
(define (json-obj x)
  (format "{\n~a\n}" x))

(define (kd->json kd)
  (json-entry
    (kd-name kd)
    (format "~{~a~^|~}" (kd-words kd))))
(define (kds->json kds)
  (json-obj
    (format "~{~a~^,\n~}"
            (map kd->json kds))))

;; file IO
(define (write-to-file fname content)
  (let ([outFile (open-output-file fname 'replace)])
    (display content outFile)
    (newline outFile)
    (close-output-port outFile)))

; write keywords to JSON file
(write-to-file out-path (kds->json input-kd))
