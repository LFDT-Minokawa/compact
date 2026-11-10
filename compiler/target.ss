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
;;; compactc build is built for.
;;;
;;; current-target is the record of the target of this build.  It is made when this
;;; library is compiled, from the name of the one directory compiler/targets/<target>/
;;; that is on the library path (CHEZSCHEMELIBDIRS): the name of a target is
;;; ocrt-<major>_<minor>-zkir-<major>_<minor>, e.g., ocrt-4_0-zkir-3_2, and its
;;; on-chain runtime and ZKIR versions are the ones the name says, so they cannot
;;; disagree.  It is an error for no directory, or more than one, of
;;; compiler/targets/ to be on the library path, and for the directory not to be
;;; named like a target.  The libraries that depend on the target (e.g.,
;;; typescript-passes) are found in that directory, which is how a build gets the
;;; ones of its target.
;;;
;;; (target-pathname f) is the pathname of the file f in the directory of the
;;; current target.

(library (target)
  (export target? target-name target-onchain-runtime-version target-zkir-version
          target-pathname
          current-target)
  (import (except (chezscheme) errorf)
          (utils))

  (define-syntax target-directory-prefix (identifier-syntax "compiler/targets/"))

  (define (target-pathname name)
    (format "~a~a/~a" target-directory-prefix (target-name current-target) name))

  (define-record-type target
    (nongenerative)
    (fields name onchain-runtime-version zkir-version))

  (module (current-target)
    (define-syntax make-current-target
      (lambda (x)
        (define (target-library-directories)
          (filter
            (lambda (d) (string-prefix? target-directory-prefix d))
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

        ;; "ocrt-4_0-zkir-3_2" -> ("4.0" "3.2"); #f for any other name.
        (define (parse-target-name name)
          (let ([part* (split-on-dash name)])
            (and (= (length part*) 4)
                 (string=? (car part*) "ocrt")
                 (string=? (caddr part*) "zkir")
                 (let ([ocrt (version-from-slug (cadr part*))]
                       [zkir (version-from-slug (cadddr part*))])
                   (and ocrt zkir (list ocrt zkir))))))

        (syntax-case x ()
          [(k)
           (let ([dir* (target-library-directories)])
             (unless (= (length dir*) 1)
               (syntax-error x
                 (format "expected exactly one target directory, compiler/targets/<target>, on the library path (CHEZSCHEMELIBDIRS) but found ~a"
                         (if (null? dir*) "none" dir*))))
             (let* ([dir (car dir*)]
                    [name (substring dir (string-length target-directory-prefix) (string-length dir))]
                    [versions (parse-target-name name)])
               (unless versions
                 (syntax-error x
                   (format "~a is not named like a target, ocrt-<major>_<minor>-zkir-<major>_<minor>" dir)))
               (with-syntax ([name name]
                             [ocrt (car versions)]
                             [zkir (cadr versions)])
                 #'(make-target name ocrt zkir))))])))

    (define current-target (make-current-target)))
)
