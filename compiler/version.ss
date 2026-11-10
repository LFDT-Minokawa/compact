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

(library (version)
  (export Lversion make-version make-version-string make-version-checker
          version-with-tag
          #;version-tests)
  (import (except (chezscheme) errorf) (utils) (nanopass))

  ;; `tag` is a prerelease identifier with its leading #\- (`-rc.2`, `-dev`),
  ;; or "" for a plain release. It is printed but never compared -- the
  ;; operators below read only the numbers -- so a candidate satisfies the
  ;; same `pragma compiler_version` constraints as its release. Build
  ;; metadata never goes here, so the printed form stays valid semver; the
  ;; commit is reported beside the version instead (version-config.ss).
  ;; The 4-argument constructor leaves the tag "", so lexer.ss's calls
  ;; still work.
  (define-record-type version
    (nongenerative)
    (fields feature major minor bugfix tag)
    (protocol
      (lambda (new)
        (case-lambda
          [(feature major minor bugfix) (new feature major minor bugfix "")]
          [(feature major minor bugfix tag) (new feature major minor bugfix tag)]))))

  ;; `version` with its tag replaced. Separate from the constructor because the
  ;; tag is not known when the version is committed, and because
  ;; scripts/read-version.sh parses the literal `(make-version 'feature M m b)`
  ;; form for everything outside Scheme.
  (define (version-with-tag version tag)
    (make-version (version-feature version)
                  (version-major version)
                  (version-minor version)
                  (version-bugfix version)
                  tag))

  (define (make-version-string version)
    (format "~d.~d.~d~a"
            (version-major version)
            (version-minor version)
            (version-bugfix version)
            (version-tag version)))

  (module (version=? version<? version<=? version>=? version>?)
    (define (comp=? v v^)
      (or (eq? v^ '*)
          (= v v^)))
    (define (comp<? v v^)
      (if (eq? v^ '*)
          (not (= v 0))
          (< v v^)))
    (define (comp<=? v v^)
      (or (eq? v^ '*)
          (<= v v^)))
    (define (comp>? v v^)
      (if (eq? v^ '*)
          (not (= v 0))
          (> v v^)))
    (define (comp>=? v v^)
      (or (eq? v^ '*)
          (>= v v^)))
    (define (version=? v v^)
      (and (comp=? (version-major v) (version-major v^))
           (comp=? (version-minor v) (version-minor v^))
           (comp=? (version-bugfix v) (version-bugfix v^))))
    (module (version<? version<=? version>=? version>?)
      (define (version-rel comp-rel)
        (lambda (v v^)
          (if (comp=? (version-major v) (version-major v^))
              (if (comp=? (version-minor v) (version-minor v^))
                  (comp-rel (version-bugfix v) (version-bugfix v^))
                  (comp-rel (version-minor v) (version-minor v^)))
              (comp-rel (version-major v) (version-major v^)))))
      (define version<? (version-rel comp<?))
      (define version<=? (version-rel comp<=?))
      (define version>=? (version-rel comp>=?))
      (define version>? (version-rel comp>?))))

  (define-language Lversion
    (terminals (version (version)))
    (Version-Expression (ve)
      version
      (not version)
      (< version)
      (<= version)
      (>= version)
      (> version)
      (or ve1 ve2)
      (and ve1 ve2)))

  (define (version-okay? actual-version ve)
    (let f ([ve ve])
      (nanopass-case (Lversion Version-Expression) ve
        [,version (version=? actual-version version)]
        [(not ,version) (not (version=? actual-version version))]
        [(< ,version) (version<? actual-version version)]
        [(<= ,version) (version<=? actual-version version)]
        [(>= ,version) (version>=? actual-version version)]
        [(> ,version) (version>? actual-version version)]
        [(or ,ve1 ,ve2) (or (f ve1) (f ve2))]
        [(and ,ve1 ,ve2) (and (f ve1) (f ve2))]
        [else (internal-errorf #f 'version-okay? "unhandled version-expr ~s" ve)])))

  (define (make-version-checker version)
    (lambda (src ve)
      (or (version-okay? version ve)
          (source-errorf src "~a version ~a mismatch"
                         (version-feature version)
                         (make-version-string version)))))

  #| uncomment export of version-tests above and run tests with:
  echo '(import (version)) (version-tests)' | scheme -q
  |#  
  (define (version-tests)
    (define-syntax test
      (lambda (x)
        (syntax-case x ()
          [(_ M m b expr)
           #`(unless (version-okay? (make-version 'this M m b) expr)
               (syntax-error #'#,x "test failed"))])))
    (define-syntax test-not
      (lambda (x)
        (syntax-case x ()
          [(_ M m b expr)
           #`(when (version-okay? (make-version 'this M m b) expr)
               (syntax-error #'#,x "test failed"))])))
    (with-output-language (Lversion Version-Expression)
      (test 1 2 3 (make-version 'that 1 2 3))
      (test-not 1 2 3 (make-version 'that 1 2 0))
      (test-not 1 2 3 (make-version 'that 1 0 3))
      (test-not 1 2 3 (make-version 'that 0 2 3))
      (test 1 2 3 (make-version 'that 1 2 '*))
      (test 1 2 3 (make-version 'that 1 '* '*))
      (test 1 2 3 (make-version 'that 1 '* 3))
      (test-not 1 2 4 (make-version 'that 1 '* 3))
      (test 1 2 3 `(not ,(make-version 'that 1 2 2)))
      (test-not 1 2 3 `(not ,(make-version 'that 1 2 3)))
      (test 1 2 3 `(or ,(make-version 'that 1 2 3) ,(make-version 'that 1 2 4)))
      (test 1 2 4 `(or ,(make-version 'that 1 2 3) ,(make-version 'that 1 2 4)))
      (test-not 1 2 5 `(or ,(make-version 'that 1 2 3) ,(make-version 'that 1 2 4)))
      (test 1 2 2 `(< ,(make-version 'that 1 2 3)))
      (test-not 1 2 3 `(< ,(make-version 'that 1 2 3)))
      (test-not 1 3 3 `(< ,(make-version 'that 1 2 3)))
      (test-not 2 2 3 `(< ,(make-version 'that 1 2 3)))
      (test 1 2 3 `(< ,(make-version 'that 1 2 '*)))
      (test 1 2 3 `(< ,(make-version 'that 1 '* '*)))
      (test-not 1 2 0 `(< ,(make-version 'that 1 2 0)))
      (test-not 1 2 0 `(< ,(make-version 'that 1 2 '*)))
      (test 1 1 9 `(< ,(make-version 'that 1 2 '*)))
      (test-not 1 2 1 `(< ,(make-version 'that 1 2 0)))
      (test 1 2 1 `(< ,(make-version 'that 1 2 '*)))
      (test 1 2 2 `(<= ,(make-version 'that 1 2 3)))
      (test 1 2 3 `(<= ,(make-version 'that 1 2 3)))
      (test-not 1 2 4 `(<= ,(make-version 'that 1 2 3)))
      (test-not 1 3 3 `(<= ,(make-version 'that 1 2 3)))
      (test-not 2 2 3 `(<= ,(make-version 'that 1 2 3)))
      (test 1 2 3 `(<= ,(make-version 'that 1 2 '*)))
      (test 1 2 3 `(<= ,(make-version 'that 1 '* '*)))
      (test-not 1 2 2 `(>= ,(make-version 'that 1 2 3)))
      (test-not 1 2 2 `(>= ,(make-version 'that 1 2 3)))
      (test 1 2 3 `(>= ,(make-version 'that 1 2 3)))
      (test 1 2 4 `(>= ,(make-version 'that 1 2 3)))
      (test-not 1 1 3 `(>= ,(make-version 'that 1 2 3)))
      (test-not 0 2 3 `(>= ,(make-version 'that 1 2 3)))
      (test 1 2 3 `(>= ,(make-version 'that 1 2 '*)))
      (test 1 2 3 `(>= ,(make-version 'that 1 '* '*)))
      (test 1 2 3 `(> ,(make-version 'that 1 2 2)))
      (test-not 1 2 2 `(> ,(make-version 'that 1 2 2)))
      (test-not 1 1 3 `(> ,(make-version 'that 1 2 2)))
      (test-not 0 2 3 `(> ,(make-version 'that 1 2 2)))
      (test 1 2 3 `(> ,(make-version 'that 1 2 '*)))
      (test 1 2 3 `(> ,(make-version 'that 1 2 2)))
      (test-not 1 2 0 `(> ,(make-version 'that 1 2 0)))
      (test-not 1 2 0 `(> ,(make-version 'that 1 2 '*)))
      (test 1 2 1 `(> ,(make-version 'that 1 2 0)))
      (test 1 2 1 `(> ,(make-version 'that 1 2 '*)))
      (test 1 2 3 `(and ,(make-version 'that 1 2 3) ,(make-version 'that 1 2 3)))
      (test-not 1 2 3 `(and ,(make-version 'that 1 2 2) ,(make-version 'that 1 2 3)))
      (test-not 1 2 3 `(and ,(make-version 'that 1 2 3) ,(make-version 'that 1 2 4)))
      (test-not 1 2 2 `(and (>= ,(make-version 'that 1 2 3)) (<= ,(make-version 'that 1 2 4))))
      (test 1 2 3 `(and (>= ,(make-version 'that 1 2 3)) (<= ,(make-version 'that 1 2 4))))
      (test 1 2 4 `(and (>= ,(make-version 'that 1 2 3)) (<= ,(make-version 'that 1 2 4))))
      (test-not 1 2 5 `(and (>= ,(make-version 'that 1 2 3)) (<= ,(make-version 'that 1 2 4))))
      ;; a tag is printed but never compared
      (unless (string=? (make-version-string (make-version 'this 1 2 3)) "1.2.3")
        (syntax-error #'version-tests "untagged version prints wrongly"))
      (unless (string=? (make-version-string (version-with-tag (make-version 'this 1 2 3) "-rc.2"))
                        "1.2.3-rc.2")
        (syntax-error #'version-tests "version-with-tag prints wrongly"))
      (unless (string=? (make-version-string (version-with-tag (make-version 'this 1 2 3 "-rc.1") "")) "1.2.3")
        (syntax-error #'version-tests "version-with-tag should be able to clear a tag"))
      (unless (version-okay? (version-with-tag (make-version 'this 1 2 3) "-rc.2") (make-version 'that 1 2 3))
        (syntax-error #'version-tests "a tag applied afterwards must stay invisible to comparison"))
      (unless (string=? (make-version-string (make-version 'this 1 2 3 "-rc.2")) "1.2.3-rc.2")
        (syntax-error #'version-tests "tagged version prints wrongly"))
      (unless (string=? (make-version-string (make-version 'this 1 2 3 "-rc.0-a-b-c")) "1.2.3-rc.0-a-b-c")
        (syntax-error #'version-tests "a multi-identifier prerelease prints wrongly"))
      (unless (version-okay? (make-version 'this 1 2 3 "-rc.2") (make-version 'that 1 2 3))
        (syntax-error #'version-tests "a release candidate should satisfy its own release"))
      (unless (version-okay? (make-version 'this 1 2 3 "-rc.2") `(>= ,(make-version 'that 1 2 3)))
        (syntax-error #'version-tests "a release candidate should satisfy >= its own release"))
      (test 0 3 5 `(or ,(make-version 'that 0 3 5) (and (> ,(make-version 'that 0 2 0)) (< ,(make-version 'that 0 3 0)))))
      (test 0 2 5 `(or ,(make-version 'that 0 3 5) (and (> ,(make-version 'that 0 2 0)) (< ,(make-version 'that 0 3 0)))))
      (test-not 0 2 0 `(or ,(make-version 'that 0 3 5) (and (> ,(make-version 'that 0 2 0)) (< ,(make-version 'that 0 3 0)))))
      (test-not 0 3 0 `(or ,(make-version 'that 0 3 5) (and (> ,(make-version 'that 0 2 0)) (< ,(make-version 'that 0 3 0)))))
      (test-not 1 2 3 `(or ,(make-version 'that 0 3 5) (and (> ,(make-version 'that 0 2 0)) (< ,(make-version 'that 0 3 0)))))
      ))
)
