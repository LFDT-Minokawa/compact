;;; This file is part of Compact.
;;; Copyright (C) 2026 Minokawa project contributors
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

#!chezscheme

;;; A target is the pair of the on-chain runtime and ZKIR versions that a
;;; compactc build is built for.  This library only defines the
;;; shape of a target; each directory under compiler/targets/ instantiates it in
;;; a library named (current-target).  Which instance a build uses is fixed at
;;; build time by which target directory is on the library path.
;;;
;;; The ledger version is informational as the compiler is not directly configured by it.
;;;
;;; A target is named ocrt-<major>_<minor>-zkir-<major>_<minor>, e.g.,
;;; ocrt-4_0-zkir-3_1, and the name has to agree with the versions of the record:
;;; make-target rejects a record whose on-chain runtime or ZKIR version is not the
;;; one its name says (and a name that is not of that form).  The record of a
;;; target is made from the name of its directory (see target-directory.ss), so it
;;; always does.

(library (target)
  (export make-target target? target-name target-onchain-runtime-version
          target-zkir-version target-ledger-version parse-target-name
          target-directory-prefix target-library-directories)
  (import (chezscheme))

  (define target-directory-prefix "compiler/targets/")

  ;; the entries of the library path that are target directories,
  ;; compiler/targets/<target>, as strings
  (define (target-library-directories)
    (filter
      (lambda (d)
        (and (fx>= (string-length d) (string-length target-directory-prefix))
             (string=? (substring d 0 (string-length target-directory-prefix))
                       target-directory-prefix)))
      (map car (library-directories))))

  ;; "4_0" -> "4.0" when both parts are non-empty strings of digits, else #f.
  (define (version-from-slug slug)
    (let loop ([i 0])
      (cond
        [(fx= i (string-length slug)) #f]
        [(char=? (string-ref slug i) #\_)
         (let ([major (substring slug 0 i)]
               [minor (substring slug (fx+ i 1) (string-length slug))])
           (and (digits? major) (digits? minor)
                (string-append major "." minor)))]
        [else (loop (fx+ i 1))])))

  (define (digits? s)
    (and (fx> (string-length s) 0)
         (let loop ([i 0])
           (or (fx= i (string-length s))
               (and (char-numeric? (string-ref s i)) (loop (fx+ i 1)))))))

  (define (split-on-dash s)
    (let loop ([i 0] [start 0] [part* '()])
      (cond
        [(fx= i (string-length s)) (reverse (cons (substring s start i) part*))]
        [(char=? (string-ref s i) #\-) (loop (fx+ i 1) (fx+ i 1) (cons (substring s start i) part*))]
        [else (loop (fx+ i 1) start part*)])))

  ;; "ocrt-4_0-zkir-3_1" -> ("4.0" "3.1"); #f for any other name.
  (define (parse-target-name name)
    (let ([part* (split-on-dash name)])
      (and (= (length part*) 4)
           (string=? (car part*) "ocrt")
           (string=? (caddr part*) "zkir")
           (let ([ocrt (version-from-slug (cadr part*))]
                 [zkir (version-from-slug (cadddr part*))])
             (and ocrt zkir (list ocrt zkir))))))

  (define-record-type target
    (fields name onchain-runtime-version zkir-version ledger-version)
    (protocol
      (lambda (new)
        (lambda (name onchain-runtime-version zkir-version ledger-version)
          (let ([versions (parse-target-name name)])
            (unless versions
              (assertion-violation 'make-target
                "target name is not of the form ocrt-<major>_<minor>-zkir-<major>_<minor>"
                name))
            (unless (string=? (car versions) onchain-runtime-version)
              (assertion-violation 'make-target
                (format "target ~a names on-chain runtime version ~a but its on-chain runtime version is ~a"
                  name (car versions) onchain-runtime-version)))
            (unless (string=? (cadr versions) zkir-version)
              (assertion-violation 'make-target
                (format "target ~a names ZKIR version ~a but its ZKIR version is ~a"
                  name (cadr versions) zkir-version))))
          (new name onchain-runtime-version zkir-version ledger-version))))))
