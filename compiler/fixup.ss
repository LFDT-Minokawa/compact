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

(library (fixup)
  (export parse-file/fixup/format
          update-Uint-ranges)
  (import (except (chezscheme) errorf)
          (utils)
          (formatter)
          (parser)
          (frontend-passes)
          (analysis-passes)
          (pass-helpers)
          (nanopass)
          (lparser)
          (lparser-to-lsrc))

  (define update-Uint-ranges (make-parameter #f))

  (define (run-passes passes ir*)
    (fold-left
      (lambda (x* p)
        (let-values ([x* (apply (passrec-pass p) x*)])
          x*))
      ir*
      passes))

  (define-record-type deferred-warning
    (nongenerative)
    (fields src warn))

  (define deferred-warnings (make-parameter '()))

  (define-pass pre-fixup : Lparser (ir) -> Lparser ()
    (Program-Element : Program-Element (ir) -> Program-Element ()
      [(include ,src ,kwd ,file ,semicolon)
       (guard (string=? (token-value file) "std"))
       `(import ,src
                #f
                ,(make-token (token-src kwd) 'id 'import "import")
                ,(make-token (token-src file) 'id 'CompactStandardLibrary "CompactStandardLibrary")
                #f
                #f
                ,semicolon)])
    (Type : Type (ir) -> Type ()
      [(tunsigned ,src ,kwd ,langle ,[tsize] ,dotdot ,[tsize^] ,rangle)
       (guard (update-Uint-ranges))
       (let ()
         (define (restring n s)
           (or (and (fx>= (string-length s) 3)
                    (char=? (string-ref s 0) #\0)
                    (case (string-ref s 1)
                      [(#\b #\B) (format "0b~b" n)]
                      [(#\o #\O) (format "0o~o" n)]
                      [(#\x #\X) (format "0x~x" n)]
                      [else #f]))
               (format "~d" n)))
         `(tunsigned ,src ,kwd ,langle ,tsize ,dotdot
                     ,(nanopass-case (Lparser Type-Size) tsize^
                        [(type-size ,src ,nat)
                         `(type-size ,src
                                     ,(let ([n (+ (token-value nat) 1)])
                                        (make-token (token-src nat) (token-type nat) n (restring n (token-string nat)))))]
                        [(type-size-ref ,src ,tsize-name)
                         (deferred-warnings
                           (cons (make-deferred-warning
                                   (token-src tsize-name)
                                   (lambda ()
                                     (source-warningf
                                       (token-src tsize-name)
                                       "Uint range end expressed as a reference to generic size ~a is left unchanged and must be updated manually"
                                       (token-value tsize-name))))
                                 (deferred-warnings)))
                         tsize^])
                     ,rangle))]))

  (define-pass fixup : Lparser (ir) -> Lparser ()
    (definitions
      (define (maybe-rename src token)
        (cond
          [(hashtable-ref (renaming-table) src #f) =>
           (lambda (old.new)
             (hashtable-delete! (renaming-table) src)
             (let ([old (car old.new)] [new (cdr old.new)])
               (assert (string=? (symbol->string old) (token-string token)))
               (make-token (token-src token) (token-type token) new (symbol->string new))))]
          [else token])))
    (External-Declaration : External-Declaration (ir) -> External-Declaration ()
      [(external ,src ,kwd-export? ,kwd ,function-name ,generic-param-list? ,arg-list ,[type] ,semicolon)
       (let ([function-name (maybe-rename src function-name)]
             [generic-param-list? (and generic-param-list? (Generic-Param-List generic-param-list?))])
         `(external ,src ,kwd-export? ,kwd ,function-name ,generic-param-list? ,arg-list ,type ,semicolon))])
    (Export-Declaration : Export-Declaration (ir) -> Export-Declaration ()
      [(export ,src ,kwd ,lbrace (,name* ...) (,sep* ...) ,rbrace ,semicolon)
       (let ([name* (map (lambda (name) (maybe-rename (token-src name) name)) name*)])
         `(export ,src ,kwd ,lbrace (,name* ...) (,sep* ...) ,rbrace ,semicolon))])
    (Expression : Expression (ir) -> Expression ()
      [(elt-ref ,src ,[expr] ,dot ,elt-name)
       (let ([elt-name (maybe-rename (token-src dot) elt-name)])
         `(elt-ref ,src ,expr ,dot ,elt-name))]
      [(elt-call ,src ,[expr] ,dot ,elt-name ,lparen (,[expr*] ...) (,comma* ...) ,rparen)
       (let ([elt-name (maybe-rename (token-src dot) elt-name)])
         `(elt-call ,src ,expr ,dot ,elt-name ,lparen (,expr* ...) (,comma* ...) ,rparen))])
    (Function : Function (ir) -> Function ()
      [(fref ,src ,function-name ,generic-arg-list?)
       (let ([function-name (maybe-rename src function-name)]
             [generic-param-list? (and generic-arg-list? (Generic-Arg-List generic-arg-list?))])
         `(fref ,src ,function-name ,generic-arg-list?))])
    (Generic-Param-List : Generic-Param-List (ir) -> Generic-Param-List ())
    (Generic-Arg-List : Generic-Arg-List (ir) -> Generic-Arg-List ()))

  (define (parse-file/fixup/format source-pathname line-length)
    (let-values ([(token-stream ir) (parse-file/token-stream source-pathname)])
      (parameterize ([deferred-warnings '()])
        ; pre-fixup is used to fix things that don't depend on running the analysis passes and
        ; might cause errors in the analysis passes if not updated first
        (let ([ir (pre-fixup ir)])
          (let ([ir (parameterize ([renaming-table (make-eq-hashtable)])
                      ; run, for effect only, the passes needed to set up information for fixup
                      (run-passes fixup-analysis-passes (run-passes frontend-passes (list (Lparser->Lsrc ir))))
                      (let ([ir (fixup ir)])
                        (let-values ([(vsrc vold.new) (hashtable-entries (renaming-table))])
                          (vector-for-each
                            (lambda (src old.new)
                              (let ([old (car old.new)] [new (cdr old.new)])
                                (internal-errorf #f "failed to apply renaming of ~s to ~s at ~a"
                                                 old new (format-source-object src))))
                            vsrc vold.new))
                        ir))])
            (for-each
              (lambda (w) ((deferred-warning-warn w)))
              (sort (lambda (w1 w2) (source-object<? (deferred-warning-src w1) (deferred-warning-src w2)))
                    (deferred-warnings)))
            (let-values ([(op get) (open-string-output-port)])
              (print-Lparser ir token-stream line-length op)
              (get)))))))
)
