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

;; To generate the list of parser keywords run the command:
;; scheme --program ./compiler/export-keywords.ss
;; or
;; scheme --program ./compiler/export-keywords.ss 0
;; or if you want to specify the path:
;; scheme --program ./compiler/export-keywords.ss 0 <path>
;;
;; To generate the list of all keywords run the command:
;; scheme --program ./compiler/export-keywords.ss 1
;; or if you want to specify the path:
;; scheme --program ./compiler/export-keywords.ss 1 <path>
;;
(define-values (mode out-path)
  (let ([args (cdr (command-line))])
    (case (length args)
      [(0) (values 0 "editor-support/vsc/compact/tests/resources/keywords.json")]
      [(1) (let ([m (string->number (car args))])
             (if (and m (or (= m 0) (= m 1)))
                 (values m
                         (if (= m 1)
                             "doc/all-keywords.html"
                             "editor-support/vsc/compact/tests/resources/keywords.json"))
                 (begin
                   (fprintf (current-error-port) "usage: ~a [ mode ] [ output-path ]\n       where mode can be 0 for parser keywords in json or 1 for all keywords in html\n" (car (command-line)))
                   (exit 1))))]
      [(2) (let ([m (string->number (car args))])
             (if (and m (or (= m 0) (= m 1)))
                 (values m (cadr args))
                 (begin
                   (fprintf (current-error-port) "usage: ~a [ mode ] [ output-path ]\n       where mode can be 0 for parser keywords in json or 1 for all keywords in html\n" (car (command-line)))
                   (exit 1))))]
      [else (fprintf (current-error-port) "usage: ~a [ mode [ output-path ] ]\n" (car (command-line)))
            (exit 1)])))

; KD := tuple (name of group of keywords , keywords list)
(define (kd-name  kd) (car kd))
(define (kd-words kd) (cadr kd))

;; get input
(define input-kd
  (if (= mode 1)
      (append (parser-keywords)
              `((keywordReservedForFutureUse ,keywordReservedForFutureUse)))
      (parser-keywords)))

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

;; HTML utils
(define (html-keyword word)
  (format "      <li>~a</li>" word))

(define (html-group kd)
  (format "    <h2>~a</h2>\n    <ul>\n~{~a~^\n~}\n    </ul>"
          (kd-name kd)
          (map html-keyword (kd-words kd))))

(define (html-page body)
  (string-append
    "<!DOCTYPE html>\n"
    "<html>\n"
    "<head>\n"
    "  <meta charset=\"UTF-8\">\n"
    "  <title>Keywords</title>\n"
    "</head>\n"
    "<body>\n"
    "  <h1>Keywords</h1>\n"
    body
    "\n</body>\n"
    "</html>"))

(define (kds->html kds)
  (html-page
    (format "~{~a~^\n~}" (map html-group kds))))

;; file IO
(define (write-to-file fname content)
  (let ([outFile (open-output-file fname 'replace)])
    (display content outFile)
    (newline outFile)
    (close-output-port outFile)))

;; write keywords
(define (kds->output kds mode)
  (if (= mode 1)
      (kds->html kds)
      (kds->json kds)))

(write-to-file out-path (kds->output input-kd mode))
