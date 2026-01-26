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

(library (analysis-passes)
  (export analysis-passes fixup-analysis-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (langs)
          (ledger)
          (natives)
          (json)
          (pass-helpers)
          (parser)
          (frontend-passes)
          (standard-library-aliases))

  ;;; expand-modules-and-types resolves identifier bindings, expands away module and
  ;;; import forms, substitutes generic parameter references with the corresponding types
  ;;; and sizes, replaces struct-name, enum-name, contract-name, and ADT-name references
  ;;; with fully expanded struct, enum, contract, and ADT types, detects unbound identifiers,
  ;;; and detects misused identifiers such as a struct name used where an ordinary
  ;;; variable is expected or an ordinary variable used where a type variable is expected.
  ;;; a full description of the pass and how it works is in ../compiler.md.

  (define-syntax standard-library-path (identifier-syntax "compiler/standard-library.compact"))

  (define-pass expand-modules-and-types : Lpreexpand (ir) -> Lexpanded ()
    (definitions
      (define-syntax run-passes
        (syntax-rules ()
          [(_ passes x)
           (apply values
             (fold-left
               (lambda (x* p)
                 (let-values ([x* (apply (passrec-pass p) x*)])
                   x*))
               (list x)
               passes))]))
      (module (standard-library-pelt*)
        (define standard-library-pelt*
          (let-syntax ([a (nanopass-case (Lpreexpand Program) (run-passes
                                                                frontend-passes
                                                                (run-passes
                                                                  parser-passes
                                                                  standard-library-path))
                            [(program ,src ,pelt* ...)
                             (#%$require-include standard-library-path)
                             (with-syntax ([(pelt ...) (datum->syntax #'* pelt*)]
                                           [sfd (datum->syntax #'* (source-object-sfd src))])
                               (lambda (ignore) #'(begin (stdlib-sfd 'sfd) '(pelt ...))))])])
            a))
        (unless (member standard-library-path (registered-source-pathnames))
          (register-source-pathname! standard-library-path)))
      (define program-src)
      (module (make-instance-table instance-table-cell)
        (define (combine hash*)
          (fold-left (lambda (hash hash^)
                       (bitwise-and
                         (most-positive-fixnum)
                         (+ (ash hash 1) hash^)))
            0 hash*))
        (define (gv-hash generic-value)
          (nanopass-case (Lexpanded Generic-Value) generic-value
            [,nat nat]
            [,type (type-hash type)]))
        (define (type-hash type)
          (define max-tuple-elts-to-hash 10)
          (nanopass-case (Lexpanded Type) type
            [(tboolean ,src) 1]
            [(tfield ,src) 2]
            [(tunsigned ,src ,nat) (+ 3 nat)]
            [(tbytes ,src ,len) (+ 4 len)]
            [(topaque ,src ,opaque-type) 5]
            ; arrange for equivalent vectors and tuples to hash to same value with same elements,
            ; limiting the cost in the case of large vectors
            [(tvector ,src ,len ,type)
             (+ 6 (combine (make-list (min len max-tuple-elts-to-hash) (type-hash type))))]
            [(ttuple ,src ,type* ...)
             (+ 6 (combine (map type-hash
                                (if (fx<= (length type*) max-tuple-elts-to-hash)
                                    type*
                                    (list-head type* max-tuple-elts-to-hash)))))]
            [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
             (+ 8 (combine (list (symbol-hash contract-name)
                                 ; contract elts are unordered, so just add their hashes
                                 (apply + (map symbol-hash elt-name*)))))]
            [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
             (+ 9 (combine (map symbol-hash (cons struct-name elt-name*))))]
            [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
             (+ 10 (combine (map symbol-hash (cons* enum-name elt-name elt-name*))))]
            [(tadt ,src ,adt-name ([,adt-formal* ,generic-value*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
             (+ 11 (combine (cons (symbol-hash adt-name) (map gv-hash generic-value*))))]
            [(talias ,src ,nominal? ,type-name ,type)
             (if nominal?
                 (+ 12 (combine (list (symbol-hash type-name) (type-hash type))))
                 (type-hash type))]
            [else (internal-errorf 'type-hash "unrecognized type ~s" type)]))
        (define (targ-info-hash info*)
          (combine
            (map (lambda (info)
                   (Info-case info
                     [(Info-type src type) (type-hash type)]
                     [(Info-size src size) size]
                     [else (assert cannot-happen)]))
                 info*)))
        (define (targ-info-equal? info1* info2*)
          (andmap (lambda (info1 info2)
                    (Info-case info1
                      [(Info-type src1 type1)
                       (Info-case info2
                         [(Info-type src2 type2) (sametype? type1 type2)]
                         [else #f])]
                      [(Info-size src1 size1)
                       (Info-case info2
                         [(Info-size src2 size2) (= size1 size2)]
                         [else #f])]
                      [else (assert cannot-happen)]))
                  info1* info2*))
        (define (make-instance-table)
          (make-hashtable targ-info-hash targ-info-equal?))
        (define (instance-table-cell instance-table info* default)
          (hashtable-cell instance-table info* default)))
      (define-record-type info-fun
        (nongenerative)
        (fields seqno src kind type-param* pelt p instance-table renamed?)
        (protocol
          (lambda (new)
            (lambda (seqno src kind type-param* pelt p renamed?)
              (new seqno src kind type-param* pelt p (make-instance-table) renamed?)))))
      (module ()
        (record-writer (record-type-descriptor info-fun)
          (lambda (x p wr)
            (fprintf p "#[info-fun ~s ~s ~s ~s]" (info-fun-seqno x) (format-source-object (info-fun-src x)) (info-fun-kind x) (info-fun-renamed? x)))))
      (define-record-type ecdecl-circuit
        (nongenerative)
        (fields function-name pure? type* type))
      ; environments map raw names (symbols) to Infos, i.e., p : symbol -> Info
      (define-datatype Info
        ; the following Infos represent Lpreexpand program elements
        (Info-module type-param* pelt* p seqno dirname instance-table)
        (Info-functions name info-fun+)
        (Info-contract src contract-name ecdecl-circuit* p)
        (Info-enum src enum-name elt-name elt-name*)
        (Info-struct src struct-name type-param* elt-name* type* p)
        (Info-type-alias src nominal? type-name type-param* type p)
        (Info-ledger ledger-field-name)
        (Info-ledger-ADT adt-name type-param* vm-expr adt-op* adt-rt-op* p)
        ; an Info-var is "baked" into the Lexpanded language and represents a run-time variable bindings
        (Info-var id)
        ; an Info-bogus represents an id scoped within a block but outside of its let binding
        (Info-bogus)
        ; the following are "baked" into the Lexpanded language and represent values of generic parameters
        (Info-type src type) ; type is an Lexpanded Type
        (Info-size src size)
        ; an Info-free-tvar represents a generic parameter name in an exported struct definition.
        ; Info-free-tvars can therefore appear only in the type parameters for an Info-struct
        (Info-free-tvar tvar-name)
        ; Info-circuit-alias supports renaming / fixup
        (Info-circuit-alias aliased-name info)
        )
      (define-record-type exportit
        (nongenerative)
        (fields src name info))
      (define-record-type frob
        (nongenerative)
        (fields seqno pelt p id))
      (define frob* '())
      (define seqno.pelt* '())
      (define all-info-funs '())
      (define all-Info-modules '())
      (define ecdecl* '())
      (define-record-type (env add-rib env?)
        (nongenerative)
        (fields rib p)
        (protocol
          (lambda (new)
            (lambda (p)
              (new (make-hashtable symbol-hash eq?) p)))))
      (define empty-env (string #\m #\t))
      (define outer-module-rib (make-hashtable equal-hash equal?))
      (define outer-module-next-seqno '(0 -1))
      (define Cell-ADT-env #f)
      (define (complain-about-shadowed-renamings! p src sym info)
        ; this should be removed when we retire the version of fixup-compactc that
        ; camelCases standard library circuit and ledger operators names.
        (when (renaming-table)
          (unless (stdlib-src? src)
            (let loop ([p p])
              (unless (eq? p empty-env)
                (cond
                  [(hashtable-ref (env-rib p) sym #f) =>
                   (lambda (src.info)
                     (let ([info (cdr src.info)])
                       (Info-case info
                         [(Info-functions name info-fun+)
                          (for-each
                            (lambda (info-fun)
                              (when (info-fun-renamed? info-fun)
                                (source-warningf src
                                  "existing binding of ~s may lead to unintended shadowing of renamed standard-library circuit ~:*~s"
                                  sym)))
                            info-fun+)
                          (loop (env-p p))]
                         [else (void)])))]
                  [else (loop (env-p p))]))))))
      (define (env-insert! p src sym info)
        (assert (env? p))
        (complain-about-shadowed-renamings! p src sym info)
        (let ([a (hashtable-cell (env-rib p) sym #f)])
          (if (cdr a)
              (let ([info^ (cddr a)])
                (unless (eq? info info^)
                  (cond
                    [(Info-case info
                       [(Info-functions name info-fun+)
                        (let retry ([info^ info^])
                          (Info-case info^
                            [(Info-functions name old-info-fun+)
                             (Info-functions name (append info-fun+ old-info-fun+))]
                            [(Info-circuit-alias aliased-name info^) (retry info^)]
                            [else #f]))]
                       [else #f]) =>
                     (lambda (info) (set-cdr! (cdr a) info))]
                    [else (source-errorf src "another binding found for ~s in the same scope at ~a" sym (format-source-object (cadr a)))])))
              (set-cdr! a (cons src info)))))
      (define (add-tvar-rib src p type-param* info*)
        (if (null? info*)
            p
            (let ([p (add-rib p)])
              (for-each
                (lambda (type-param info)
                  (define (oops src src^ what tvar-name)
                    (source-errorf src
                                   "expected ~a but received ~a for generic parameter ~s declared at ~a"
                                   what
                                   (describe-info info)
                                   tvar-name
                                   (format-source-object src^)))
                  (nanopass-case (Lpreexpand Type-Param) type-param
                    [(nat-valued ,src^ ,tvar-name)
                     (Info-case info
                       [(Info-type src type) (oops src src^ "size" tvar-name)]
                       [(Info-size src size) (void)]
                       [(Info-free-tvar tvar-name) (void)]
                       [else (assert cannot-happen)])
                     (env-insert! p src tvar-name info)]
                    [(type-valued ,src^ ,tvar-name)
                     (Info-case info
                       [(Info-type src type) (void)]
                       [(Info-size src size) (oops src src^ "type" tvar-name)]
                       [(Info-free-tvar tvar-name) (void)]
                       [else (assert cannot-happen)])
                     (env-insert! p src tvar-name info)]
                    [(non-adt-type-valued ,src^ ,tvar-name)
                     (Info-case info
                       [(Info-type src type)
                        (when (public-adt? type)
                          (oops src src^ "non-ADT type" tvar-name))]
                       [(Info-size src size) (oops src src^ "non-ADT type" tvar-name)]
                       [(Info-free-tvar tvar-name) (void)]
                       [else (assert cannot-happen)])
                     (env-insert! p src tvar-name info)]))
                type-param*
                info*)
              p)))
      (define (de-alias type nominal-too?)
        (nanopass-case (Lexpanded Type) type
          [(talias ,src ,nominal? ,type-name ,type)
           (guard (or nominal-too? (not nominal?)))
           (de-alias type nominal-too?)]
          [else type]))
      (module (sametype?)
        (define-syntax T
          (syntax-rules ()
            [(T ty clause ...)
             (nanopass-case (Lexpanded Type) ty clause ... [else #f])]))
        (define (same-generic-value? gv1 gv2)
          (nanopass-case (Lexpanded Generic-Value) gv1
            [,nat1
             (nanopass-case (Lexpanded Generic-Value) gv2
               [,nat2 (= nat1 nat2)]
               ; this is currently unreachable because generic values currently only occur
               ; in public-adt types, and we never construct a public-adt type that has a
               ; type where a nat is expected or visa versa
               [else #f])]
            [,type1
             (nanopass-case (Lexpanded Generic-Value) gv2
               [,type2 (sametype? type1 type2)]
               ; this is currently unreachabe.  see note just above.
               [else #f])]))
        (define (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*)
          (andmap (lambda (elt-name2 pure-dcl2 type2* type2)
                    (ormap (lambda (elt-name1 pure-dcl1 type1* type1)
                             (and (eq? elt-name1 elt-name2)
                                  (eq? pure-dcl1 pure-dcl2)
                                  (fx= (length type1*) (length type2*))
                                  (andmap sametype? type1* type2*)
                                  (sametype? type1 type2)))
                           elt-name1* pure-dcl1* type1** type1*))
                  elt-name2* pure-dcl2* type2** type2*))
        (define (sametype? type1 type2)
          (let ([type1 (de-alias type1 #f)] [type2 (de-alias type2 #f)])
            (T type1
               [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
               [(tfield ,src1) (T type2 [(tfield ,src2) #t])]
               [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])]
               [(tbytes ,src1 ,len1) (T type2 [(tbytes ,src2 ,len2) (= len1 len2)])]
               [(topaque ,src1 ,opaque-type1)
                (T type2
                   [(topaque ,src2 ,opaque-type2)
                    (string=? opaque-type1 opaque-type2)])]
               [(tvector ,src1 ,len1 ,type1)
                (T type2
                   [(tvector ,src2 ,len2 ,type2)
                    (and (= len1 len2)
                         (sametype? type1 type2))]
                   [(ttuple ,src2 ,type2* ...)
                    (and (= len1 (length type2*))
                         (andmap (lambda (type2) (sametype? type1 type2)) type2*))])]
               [(ttuple ,src1 ,type1* ...)
                (T type2
                   [(tvector ,src2 ,len2 ,type2)
                    (and (= (length type1*) len2)
                         (andmap (lambda (type1) (sametype? type1 type2)) type1*))]
                   [(ttuple ,src2 ,type2* ...)
                    (and (= (length type1*) (length type2*))
                         (andmap sametype? type1* type2*))])]
               ; only one of the two arguments can be tundeclared, so (T ...) here might be unreachable
               [(tundeclared) (T type2 [(tundeclared) #t])]
               [(tcontract ,src1 ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
                (T type2
                   [(tcontract ,src2 ,contract-name2 (,elt-name2* ,pure-dcl2* (,type2** ...) ,type2*) ...)
                    (and (eq? contract-name1 contract-name2)
                         (fx= (length elt-name1*) (length elt-name2*))
                         (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*))])]
              [(tstruct ,src1 ,struct-name1 (,elt-name1* ,type1*) ...)
                (T type2
                   [(tstruct ,src2 ,struct-name2 (,elt-name2* ,type2*) ...)
                    (and (eq? struct-name1 struct-name2)
                         (fx= (length elt-name1*) (length elt-name2*))
                         (andmap eq? elt-name1* elt-name2*)
                         (andmap sametype? type1* type2*))])]
              [(tenum ,src1 ,enum-name1 ,elt-name1 ,elt-name1* ...)
               (T type2
                  [(tenum ,src2 ,enum-name2 ,elt-name2 ,elt-name2* ...)
                   (and (eq? enum-name1 enum-name2)
                        (eq? elt-name1 elt-name2)
                        (fx= (length elt-name1*) (length elt-name2*))
                        (andmap eq? elt-name1* elt-name2*))])]
              [(talias ,src1 ,nominal1? ,type-name1 ,type1)
               (assert nominal1?)
               (T type2
                  [(talias ,src2 ,nominal2? ,type-name2 ,type2)
                   (assert nominal2?)
                   (and (eq? type-name1 type-name2)
                        (sametype? type1 type2))])]
              [(tadt ,src1 ,adt-name1 ([,adt-formal1* ,generic-value1*] ...) ,vm-expr (,adt-op1* ...) (,adt-rt-op1* ...))
               (T type2
                  [(tadt ,src2 ,adt-name2 ([,adt-formal2* ,generic-value2*] ...) ,vm-expr (,adt-op2* ...) (,adt-rt-op2* ...))
                   (and (eq? adt-name1 adt-name2)
                        (fx= (length generic-value1*) (length generic-value2*))
                        (andmap same-generic-value? generic-value1* generic-value2*))])]))))
      (define (cycle-checker what)
        (let ([ht (make-eq-hashtable)] [stack '()])
          (lambda (src key name th)
            (let ([a (eq-hashtable-cell ht key #f)])
              (let ([stack^ (cdr a)])
                (when stack^
                  (let ([name* (let f ([stack stack])
                                 (if (eq? stack stack^)
                                     '()
                                     (begin
                                       (assert (pair? stack))
                                       (cons (car stack) (f (cdr stack))))))])
                    (source-errorf src
                                   "cycle involving ~a~?"
                                   what
                                   "~#[~; ~a~;s ~a and ~a~:;s~@{~#[~; and~] ~a~^,~}~]"
                                   name*))))
              (set-cdr! a stack)
              (set! stack (cons name stack))
              (let ([v (th)])
                (set-cdr! a #f)
                (set! stack (cdr stack))
                v)))))
      (define with-module-cycle-check (cycle-checker "module"))
      (define with-type-cycle-check (cycle-checker "type"))
      (define (make/register-frob src name info-fun info* exported?)
        (let ([a (instance-table-cell (info-fun-instance-table info-fun) info* #f)])
          (or (cdr a)
              (let ([type-param* (info-fun-type-param* info-fun)])
                (assert (= (length type-param*) (length info*)))
                (let ([id (frob-id
                            (let ([frob (make-frob
                                          (info-fun-seqno info-fun)
                                          (info-fun-pelt info-fun)
                                          (add-tvar-rib src (info-fun-p info-fun) type-param* info*)
                                          (make-source-id (info-fun-src info-fun) name))])
                              (set! frob* (cons frob frob*))
                              frob))])
                  (set-cdr! a id)
                  id)))))
      (define (lookup/no-error p sym)
        (let loop ([p p])
          (and (not (eq? p empty-env))
               (begin
                 (assert (env? p))
                 (cond
                   [(hashtable-ref (env-rib p) sym #f) => cdr]
                   [else (loop (env-p p))])))))
      (define (lookup p src sym)
        (or (lookup/no-error p sym)
            (source-errorf src "unbound identifier ~s" sym)))
      (define (lookup-fun p src function-name info*)
        ; lookup-fun checks whether each visible function binding for function-name is
        ; compatible with the generic arguments represented by info*.  those that are
        ; are recorded as candidates at the call site; those that aren't are
        ; recorded as generic-instantiation failures.  this allows the type
        ; inferencer to decide which if any to choose and, in case there is
        ; no suitable candidate, to list the generic-instantiation failures among
        ; the unsuitable candidates in the resulting error message.
        (define (compatible-type-parameters? type-param* info*)
          (and (= (length info*) (length type-param*))
               (andmap (lambda (type-param info)
                         (nanopass-case (Lpreexpand Type-Param) type-param
                           [(nat-valued ,src^ ,tvar-name)
                            (Info-case info
                              [(Info-size src size) #t]
                              [else #f])]
                           [(type-valued ,src^ ,tvar-name)
                            (Info-case info
                              [(Info-type src type) #t]
                              [else #f])]
                           ; this is not presently reachable, since only adt definitions use
                           ; type-param kind non-adt-type-valued
                           [(non-adt-type-valued ,src^ ,tvar-name)
                            (Info-case info
                              [(Info-type src type) (not (public-adt? type))]
                              [else #f])]))
                       type-param*
                       info*)))
        (define-record-type generic-failure
          (nongenerative)
          (fields src kind*))
        (define (return id+* symbolic-function-name+* generic-failure*)
          (with-output-language (Lexpanded Function)
            `(fref ,src ,function-name
                   (([,symbolic-function-name+* ,id+*] ...) ...)
                   (,(map (lambda (info)
                            (Info-case info
                              [(Info-type src type) type]
                              [(Info-size src size) size]
                              [else (assert cannot-happen)]))
                          info*)
                     ...)
                   ((,(map generic-failure-src generic-failure*)
                     ,(map generic-failure-kind* generic-failure*)
                     ...)
                    ...))))
        (define fun-visited?
          ; the same info-fun can appear in an outer contour and an inner contour due
          ; to module import.  Consider:
          ;   circuit f0(): [] { }
          ;   module M {
          ;     circuit f1(): [] { }
          ;     export circuit f2(): [] { }
          ;     export circuit f3(): [] { f1(); }
          ;   }
          ;   import M;
          ; the environment recorded for procesing bar's body will have two contours:
          ; an inner contour containing f1, f2, and f3 and an outer contour containing
          ; f0, f2, and f3.  the check here prevents f1 from appearing twice in the
          ; output of lookup-fun for the reference to f1 in the body of f3.
          (let ([ht (make-eq-hashtable)])
            (lambda (info-fun)
              (let ([a (eq-hashtable-cell ht info-fun #f)])
                (or (cdr a) (begin (set-cdr! a #t) #f))))))
        (let outer ([p p] [seen? #f] [id+* '()] [symbolic-function-name+* '()] [generic-failure* '()])
          (cond
            [(eq? p empty-env)
             (when (and (null? id+*) (null? generic-failure*)) (source-errorf src "unbound identifier ~s" function-name))
             ; each generic-failure = (src . string) e.g., (src . "<type, size>")
             (return (reverse id+*) (reverse symbolic-function-name+*) generic-failure*)]
            [(begin (assert (env? p)) (hashtable-ref (env-rib p) function-name #f)) =>
             (lambda (src.info)
               (let retry ([info (cdr src.info)] [symbolic-function-name function-name])
                 (Info-case info
                   [(Info-functions name info-fun+)
                    (let inner ([info-fun* info-fun+] [id* '()] [symbolic-function-name* '()] [generic-failure* generic-failure*])
                      (if (null? info-fun*)
                          (outer (env-p p) #t
                                 (if (null? id*) id+* (cons id* id+*))
                                 (if (null? symbolic-function-name*) symbolic-function-name+* (cons symbolic-function-name* symbolic-function-name+*))
                                 generic-failure*)
                          (let ([info-fun (car info-fun*)]
                                [info-fun* (cdr info-fun*)])
                            (if (fun-visited? info-fun)
                                (inner info-fun* id* symbolic-function-name* generic-failure*)
                                (if (compatible-type-parameters? (info-fun-type-param* info-fun) info*)
                                    (let ([id (make/register-frob src name info-fun info* #f)])
                                      (inner info-fun* (cons id id*) (cons symbolic-function-name symbolic-function-name*) generic-failure*))
                                    (inner info-fun* id* symbolic-function-name*
                                           (cons (make-generic-failure
                                                   (info-fun-src info-fun)
                                                   (map (lambda (type-param)
                                                          (nanopass-case (Lpreexpand Type-Param) type-param
                                                            [(nat-valued ,src ,tvar-name) 'size]
                                                            [(type-valued ,src ,tvar-name) 'type]
                                                            ; currently not reachable since functions don't employ this kind of type-param
                                                            [(non-adt-type-valued ,src ,tvar-name) 'non-adt-type]))
                                                        (info-fun-type-param* info-fun)))
                                                 generic-failure*)))))))]
                   [(Info-circuit-alias aliased-name info)
                    (retry info aliased-name)]
                   [else (if seen?
                             (return (reverse id+*) (reverse symbolic-function-name+*) generic-failure*)
                             (context-oops src function-name info))])))]
            [else (outer (env-p p) seen? id+* symbolic-function-name+* generic-failure*)])))
      (define-syntax Info-lookup
        (syntax-rules ()
          [(_ (p ?src ?name) clause ...)
           (let ([src ?src] [name ?name])
             (let ([info (lookup p src name)])
               (Info-case info
                 clause ...
                 [else (context-oops src name info)])))]))
      (define (describe-info info)
        (Info-case info
          [(Info-module type-param* ^export* p seqno dirname instance-table) "module"]
          [(Info-var id) "variable"]
          [(Info-bogus) "variable"]
          [(Info-type src type) (if (public-adt? type) "ledger ADT type" "type")]
          [(Info-free-tvar tvar-name) "type"]
          [(Info-size src size) "size"]
          [(Info-functions name info-fun+) "function"]
          [(Info-contract src contract-name ecdecl-circuit* p) "contract type"]
          [(Info-enum src enum-name elt-name elt-name*) "enum"]
          [(Info-struct src struct-name type-param* elt-name type* p) "struct"]
          [(Info-type-alias src nominal? type-name type-param* type p) "type alias"]
          [(Info-ledger ledger-field-name) "ledger field"]
          [(Info-ledger-ADT adt-name type-param* vm-expr adt-op* adt-rt-op* p) "ledger ADT type"]
          [(Info-circuit-alias aliased-name info) "function"]))
      (define (handle-type-ref src tvar-name info* info)
        (with-output-language (Lexpanded Type)
          (with-type-cycle-check src info tvar-name
            (lambda ()
              (Info-case info
                [(Info-type src^ type)
                 (unless (null? info*) (generic-argument-count-oops src tvar-name (length info*) 0))
                 type]
                [(Info-free-tvar tvar-name)
                 (unless (null? info*) (generic-argument-count-oops src tvar-name (length info*) 0))
                 tvar-name]
                [(Info-contract src contract-name ecdecl-circuit* p)
                 (unless (null? info*) (generic-argument-count-oops src tvar-name (length info*) 0))
                 (let ([Type (lambda (type) (Type type p))])
                   `(tcontract ,src ,contract-name
                      (,(map ecdecl-circuit-function-name ecdecl-circuit*)
                       ,(map ecdecl-circuit-pure? ecdecl-circuit*)
                       (,(map (lambda (type*) (map Type type*)) (map ecdecl-circuit-type* ecdecl-circuit*)) ...)
                       ,(map Type (map ecdecl-circuit-type ecdecl-circuit*)))
                      ...))]
                [(Info-enum src^ enum-name elt-name elt-name*)
                 (unless (null? info*) (generic-argument-count-oops src tvar-name (length info*) 0))
                 `(tenum ,src ,enum-name ,elt-name ,elt-name* ...)]
                [(Info-struct src^ struct-name type-param* elt-name* type* p)
                 (apply-struct src src^ struct-name type-param* elt-name* type* p info*)]
                [(Info-type-alias src^ nominal? type-name type-param* type p)
                 (apply-type-alias src src^ nominal? type-name type-param* type p info*)]
                [(Info-ledger-ADT adt-name type-param* vm-expr adt-op* adt-rt-op* p)
                 (apply-ledger-ADT src adt-name type-param* vm-expr adt-op* adt-rt-op* p info*)]
                [else (context-oops src tvar-name info)])))))
      (define (context-oops src name info)
        (source-errorf src "invalid context for reference to ~a name ~s"
                       (describe-info info)
                       name))
      (define (export-oops src name info)
        (source-errorf src "cannot export ~a (~s) from the top level"
                       (describe-info info)
                       name))
      (define (do-import src import-name info* prefix maybe-ielt* p)
        (define (import-insert! src name info)
          (define (add-prefix x) (string->symbol (format "~a~a" prefix (symbol->string x))))
          (let-values ([(name info) (if (equal? prefix "")
                                        (values name info)
                                        (values (add-prefix name)
                                                (Info-case info
                                                  [(Info-circuit-alias aliased-name info)
                                                   (Info-circuit-alias (add-prefix aliased-name) info)]
                                                  [else info])))])
            (env-insert! p src name info)))
        (let* ([module-name (if (symbol? import-name) import-name (string->symbol (path-last import-name)))]
               [info (or (and (symbol? import-name) (lookup/no-error p import-name))
                         (and (eq? import-name 'CompactStandardLibrary)
                              (let ([a (hashtable-cell outer-module-rib (cons import-name import-name) #f)])
                                (or (cdr a)
                                    (let ([info (Info-module
                                                  '()
                                                  (append standard-library-pelt*
                                                          (map (lambda (adt-defn)
                                                                  (nanopass-case (Lpreexpand ADT-Definition) adt-defn
                                                                    [(define-adt ,src ,exported? ,adt-name (,type-param* ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                                                                     (guard (eq? adt-name 'Cell))
                                                                     (with-output-language (Lpreexpand ADT-Definition)
                                                                       `(define-adt ,src ,exported? __compact_Cell (,type-param* ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)))]
                                                                    [else adt-defn]))
                                                                (ledger-adt-definitions))
                                                          (map (lambda (a)
                                                                 (let ([old-name (car a)] [new-name (cdr a)])
                                                                   (with-output-language (Lpreexpand Circuit-Alias-Definition)
                                                                     `(circuit-alias ,old-name ,new-name))))
                                                               stdlib-circuit-aliases))
                                                  empty-env
                                                  outer-module-next-seqno
                                                  #f
                                                  (make-instance-table))])
                                      (set! outer-module-next-seqno (cons (fx1+ (car outer-module-next-seqno)) (cdr outer-module-next-seqno)))
                                      (set-cdr! a info)
                                      info))))
                         (let* ([pathname (find-source-pathname src
                                            (if (symbol? import-name) (symbol->string import-name) import-name)
                                            (lambda (pathname) (source-errorf src "failed to locate file ~s" pathname)))]
                                [import-name (if (symbol? import-name) import-name (string->symbol (path-last import-name)))]
                                [a (hashtable-cell outer-module-rib (cons import-name pathname) #f)])
                           (or (cdr a)
                               (let ([dirname (path-parent pathname)])
                                 (nanopass-case (Lpreexpand Program) (parameterize ([relative-path dirname])
                                                                       (run-passes
                                                                         frontend-passes
                                                                         (run-passes
                                                                           parser-passes
                                                                           pathname)))
                                   [(program ,src^ (module ,src^^ ,exported? ,module-name^ (,type-param* ...) ,pelt^* ...))
                                    (unless (eq? module-name^ module-name)
                                      (source-errorf src "~a defines module ~s rather than expected module ~s" pathname module-name^ module-name))
                                    (let ([info (Info-module type-param* pelt^* empty-env outer-module-next-seqno dirname (make-instance-table))])
                                      (set! outer-module-next-seqno (cons (fx1+ (car outer-module-next-seqno)) (cdr outer-module-next-seqno)))
                                      (set-cdr! a info)
                                      info)]
                                   [else (source-errorf src "~a does not contain a (single) module defintion" pathname)])))))])
          (Info-case info
            [(Info-module type-param* pelt^* p^ seqno^ dirname instance-table)
             (let ([export* (let ([a (instance-table-cell instance-table info* #f)])
                              (or (cdr a)
                                  (begin
                                    (let ([nactual (length info*)] [ndeclared (length type-param*)])
                                      (unless (fx= nactual ndeclared)
                                        (source-errorf src "mismatch between actual number ~s and declared number ~s of import generic parameters for ~s"
                                                       nactual
                                                       ndeclared
                                                       module-name)))
                                    (let ([export* (let ([p^ (add-tvar-rib src p^ type-param* info*)])
                                                     (with-module-cycle-check src info import-name
                                                       (lambda ()
                                                         (parameterize ([relative-path (if dirname dirname (relative-path))])
                                                           (process-pelts #f
                                                             pelt^*
                                                             (map (lambda (i) (cons i seqno^)) (enumerate pelt^*))
                                                             p^)))))])
                                      (set-cdr! a export*)
                                      export*))))])
               (if maybe-ielt*
                   (let ([export-ht (make-hashtable symbol-hash eq?)])
                     (for-each
                       (lambda (x)
                         (hashtable-update! export-ht (exportit-name x)
                           (lambda (info*) (cons (exportit-info x) info*))
                           '()))
                       export*)
                     (for-each
                       (lambda (ielt)
                         (nanopass-case (Lpreexpand Import-Element) ielt
                           [(,src ,name ,name^)
                            (let ([info* (hashtable-ref export-ht name '())])
                              (when (null? info*)
                                (source-errorf src "no export named ~a in module ~a"
                                               name
                                               import-name))
                              (for-each
                                (lambda (info) (import-insert! src name^ info))
                                info*))]))
                       maybe-ielt*))
                   (for-each
                     (lambda (x) (import-insert! src (exportit-name x) (exportit-info x)))
                     export*)))]
            [else (context-oops src module-name info)])))
      (define (process-pelts top-level? pelt* seqno* p)
        (let ([p (add-rib p)])
          (let loop ([pelt* pelt*] [seqno* seqno*] [export* '()] [unresolved-export* '()])
            (if (null? pelt*)
                (fold-left
                  (lambda (export* src.name*)
                    (fold-left
                      (lambda (export* src.name)
                        (let ([src (car src.name)] [name (cdr src.name)])
                          (let ([info (lookup p src name)])
                            (cond
                              [(Info-case info
                                 [(Info-type src type) "generic parameter"]
                                 [(Info-free-tvar tvar-name) "generic parameter"] ; can't happen
                                 [(Info-size src size) "generic parameter"]
                                 [(Info-var id) "variable"] ; can't happen at present
                                 [(Info-bogus) "variable"] ; can't happen at present
                                 [(Info-circuit-alias aliased-name info)
                                  (record-alias! src name aliased-name)
                                  #f]
                                 [else #f]) =>
                               (lambda (what)
                                 (source-errorf src "attempt to export ~a name ~s" what name))])
                            (cons (make-exportit src name info) export*))))
                        export*
                        src.name*))
                  export*
                  unresolved-export*)
                (let ([pelt (car pelt*)] [pelt* (cdr pelt*)] [seqno (car seqno*)] [seqno* (cdr seqno*)])
                  (define (handle-fun src kind pelt exported? name type-param*)
                    (let* ([renamed? (and (stdlib-src? src)
                                          (memp (lambda (a) (eq? (cdr a) name)) stdlib-circuit-aliases)
                                          #t)]
                           [info-fun (make-info-fun (reverse seqno) src kind type-param* pelt p renamed?)]
                           [info (Info-functions name (list info-fun))])
                      (set! all-info-funs (cons (cons info-fun name) all-info-funs))
                      (env-insert! p src name info)
                      (loop pelt* seqno*
                            (if exported? (cons (make-exportit src name info) export*) export*)
                            unresolved-export*)))
                  (nanopass-case (Lpreexpand Program-Element) pelt
                    [(module ,src ,exported? ,module-name (,type-param* ...) ,pelt^* ...)
                     (let ([info (Info-module type-param* pelt^* p seqno #f (make-instance-table))])
                       (set! all-Info-modules (cons (cons info module-name) all-Info-modules))
                       (env-insert! p src module-name info)
                       (loop pelt* seqno*
                             (if exported? (cons (make-exportit src module-name info) export*) export*)
                             unresolved-export*))]
                    [(import ,src ,import-name (,[Type-Argument->info : targ* p -> info*] ...) ,prefix)
                     (do-import src import-name info* prefix #f p)
                     (loop pelt* seqno* export* unresolved-export*)]
                    [(import ,src ,import-name (,[Type-Argument->info : targ* p -> info*] ...) ,prefix (,ielt* ...))
                     (do-import src import-name info* prefix ielt* p)
                     (loop pelt* seqno* export* unresolved-export*)]
                    [(export ,src (,src* ,name*) ...)
                     (loop pelt* seqno* export*
                       (cons (map cons src* name*) unresolved-export*))]
                    [(public-ledger-declaration ,src ,exported? ,sealed? ,ledger-field-name ,type)
                     (let ([id (make-source-id src ledger-field-name)])
                       (let ([info (Info-ledger id)])
                         (env-insert! p src ledger-field-name info)
                         (set! frob* (cons (make-frob (reverse seqno) pelt p id) frob*))
                         (loop pelt* seqno*
                               (if exported? (cons (make-exportit src ledger-field-name info) export*) export*)
                               unresolved-export*)))]
                    [(constructor ,src (,arg* ...) ,expr)
                     (unless top-level?
                       (source-errorf src "misplaced constructor: should appear only at the top level of a program"))
                     (set! frob* (cons (make-frob (reverse seqno) pelt p #f) frob*))
                     (loop pelt* seqno* export* unresolved-export*)]
                    [(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg ...) ,type ,expr)
                     (handle-fun src 'circuit pelt exported? function-name type-param*)]
                    [(external ,src ,exported? ,function-name (,type-param* ...) (,arg* ...) ,type)
                     (handle-fun src 'external pelt exported? function-name type-param*)]
                    [(witness ,src ,exported? ,function-name (,type-param* ...) (,arg* ...) ,type)
                     (handle-fun src 'witness pelt exported? function-name type-param*)]
                    [(external-contract ,src ,exported? ,contract-name (,src* ,pure-dcl* ,function-name* ((,src** ,var-name** ,type**) ...) ,type*) ...)
                     (let ([info (Info-contract src contract-name (map make-ecdecl-circuit function-name* pure-dcl* type** type*) p)])
                       (env-insert! p src contract-name info)
                       (set! ecdecl* (cons (cons pelt p) ecdecl*))
                       (loop pelt* seqno*
                             (if exported? (cons (make-exportit src contract-name info) export*) export*)
                             unresolved-export*))]
                    [(struct ,src ,exported? ,struct-name (,type-param* ...) [,src* ,elt-name* ,type*] ...)
                     (let ([info (Info-struct src struct-name type-param* elt-name* type* p)])
                       (env-insert! p src struct-name info)
                       (loop pelt* seqno*
                             (if exported? (cons (make-exportit src struct-name info) export*) export*)
                             unresolved-export*))]
                    [(enum ,src ,exported? ,enum-name ,elt-name ,elt-name* ...)
                     (let ([info (Info-enum src enum-name elt-name elt-name*)])
                       (env-insert! p src enum-name info)
                       (loop pelt* seqno*
                             (if exported? (cons (make-exportit src enum-name info) export*) export*)
                             unresolved-export*))]
                    [(typedef ,src ,exported? ,nominal? ,type-name (,type-param* ...) ,type)
                     (let ([info (Info-type-alias src nominal? type-name type-param* type p)])
                       (env-insert! p src type-name info)
                       (loop pelt* seqno*
                             (if exported? (cons (make-exportit src type-name info) export*) export*)
                             unresolved-export*))]
                    [(define-adt ,src ,exported? ,adt-name (,type-param* ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                     (let ([info (Info-ledger-ADT adt-name type-param* vm-expr adt-op* adt-rt-op* p)])
                       (env-insert! p src adt-name info)
                       (loop pelt* seqno*
                             (if exported?
                                 (cons (make-exportit src adt-name info) export*)
                                 ; this case can't happen: these appear only in the ledger.ss output, which exports all
                                 export*)
                             unresolved-export*))]
                    [(circuit-alias ,function-name^ ,function-name)
                     (let ([src (make-source-object (assert (stdlib-sfd)) 0 0 1 1)]
                           [info (Info-circuit-alias function-name (assert (lookup/no-error p function-name)))])
                       (env-insert! p src function-name^ info)
                       (loop pelt* seqno*
                             (cons (make-exportit src function-name^ info) export*)
                             unresolved-export*))]))))))
      (define (process-frob frob)
        (Program-Element (frob-pelt frob) (frob-p frob) (frob-id frob)))
      (define (type-param->tvar-name type-param)
        (nanopass-case (Lpreexpand Type-Param) type-param
          [(nat-valued ,src ,tvar-name) tvar-name]
          [(type-valued ,src ,tvar-name) tvar-name]))
      (define (arg->id arg)
        (nanopass-case (Lexpanded Argument) arg
          [(,var-name ,type) var-name]))
      (define (generic-argument-count-oops src struct-name nactual ndeclared)
        (source-errorf src "mismatch between actual number ~s and declared number ~s of generic parameters for ~s"
                       nactual
                       ndeclared
                       struct-name))
      (define (apply-struct src struct-src struct-name type-param* elt-name* type* p^ info*)
        (let ([nactual (length info*)] [ndeclared (length type-param*)])
          (unless (fx= nactual ndeclared) (generic-argument-count-oops src struct-name nactual ndeclared)))
        (let ([p^ (add-tvar-rib src p^ type-param* info*)])
          (let ([type* (map (lambda (type) (Type type p^)) type*)])
            (with-output-language (Lexpanded Type)
              `(tstruct ,struct-src ,struct-name (,elt-name* ,type*) ...)))))
      (define (apply-type-alias src alias-src nominal? type-name type-param* type p^ info*)
        (let ([nactual (length info*)] [ndeclared (length type-param*)])
          (unless (fx= nactual ndeclared) (generic-argument-count-oops src type-name nactual ndeclared)))
        (let ([p^ (add-tvar-rib src p^ type-param* info*)])
          (with-output-language (Lexpanded Type)
            `(talias ,alias-src ,nominal? ,type-name ,(Type type p^)))))
      (define (apply-ledger-ADT src adt-name type-param* vm-expr adt-op* adt-rt-op* p info*)
        (let ([nactual (length info*)] [ndeclared (length type-param*)])
          (unless (fx= nactual ndeclared)
            (source-errorf src "mismatch between actual number ~s and declared number ~s of ADT parameters for ~s"
                           nactual
                           ndeclared
                           adt-name)))
        (let ([p (add-tvar-rib src p type-param* info*)]
              [adt-formal* (map (lambda (type-param)
                                  (nanopass-case (Lpreexpand Type-Param) type-param
                                    [(nat-valued ,src ,tvar-name) tvar-name]
                                    [(type-valued ,src ,tvar-name) tvar-name]
                                    [(non-adt-type-valued ,src ,tvar-name) tvar-name]))
                                type-param*)]
              [generic-value* (map (lambda (info)
                                     (with-output-language (Lexpanded Generic-Value)
                                       (Info-case info
                                         [(Info-type src type) type]
                                         [(Info-size src size) size]
                                         [else (assert cannot-happen)])))
                                   info*)])
          (let ([adt-op* (fold-right
                           (lambda (adt-op adt-op*)
                             (nanopass-case (Lpreexpand ADT-Op) adt-op
                               [(,ledger-op ,op-class ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code ,adt-op-cond* ...)
                                (if (andmap (let ([alist (map cons adt-formal* info*)])
                                              (lambda (adt-op-cond)
                                                (nanopass-case (Lpreexpand ADT-Op-Condition) adt-op-cond
                                                  [(= ,tvar-name ,type^)
                                                   (cond
                                                     [(assq tvar-name alist) =>
                                                      (lambda (a)
                                                        (Info-case (cdr a)
                                                          [(Info-type src type) (sametype? type (Type type^ p))]
                                                          [else (assert cannot-happen)]))]
                                                     [else (assert cannot-happen)])])))
                                            adt-op-cond*)
                                    (cons
                                      (let ([var-name* (map (lambda (var-name) (make-source-id src var-name)) var-name*)]
                                            [type* (map (lambda (type) (Type type p)) type*)]
                                            [type (Type type p)]
                                            [op-class (ADT-Op-Class op-class)])
                                        (with-output-language (Lexpanded ADT-Op)
                                          `(,ledger-op ,op-class ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)))
                                      adt-op*)
                                    adt-op*)]))
                           '()
                           adt-op*)]
                [adt-rt-op* (map (lambda (adt-rt-op)
                                   (nanopass-case (Lpreexpand ADT-Runtime-Op) adt-rt-op
                                     [(,ledger-op ((,var-name* ,type*) ...) ,result-type ,runtime-code)
                                      (let ([var-name* (map (lambda (var-name) (make-source-id src var-name)) var-name*)]
                                            [type* (map (lambda (type) (Type type p)) type*)])
                                        (with-output-language (Lexpanded ADT-Runtime-Op)
                                          `(,ledger-op ((,var-name* ,type*) ...) ,result-type ,runtime-code)))]))
                                 adt-rt-op*)])
            (with-output-language (Lexpanded Type)
              `(tadt ,src ,adt-name ([,adt-formal* ,generic-value*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))))))
      (define (get-native-entry src external-name ndeclared)
        (let ([external-name
               (cond
                 [(hashtable-ref native-aliases external-name #f) =>
                  (lambda (new-external-name)
                    (record-alias! src external-name new-external-name)
                    new-external-name)]
                 [else external-name])])
          (let ([x (hashtable-ref native-table external-name #f)])
            (unless x (source-errorf src "unrecognized native entry ~s" external-name))
            (let ([nexpected (length (native-entry-argument-types x))])
              (unless (= nexpected ndeclared)
                (source-errorf src "mismatch between declared argument count ~s and expected argument count ~s for native ~s"
                               ndeclared
                               nexpected
                               external-name)))
            x)))
      (define (check-length! src what len)
        (unless (len? len)
          (source-errorf src "~a length\n  ~d\n  exceeds the maximum supported length ~d"
                         what
                         len
                         (max-bytes/vector-length))))
      (define (public-adt? type)
        (nanopass-case (Lexpanded Type) (de-alias type #t)
          [(tadt ,src ,adt-name ([,adt-formal* ,generic-value*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #t]
          [else #f]))
      )
    (Program : Program (ir) -> Program ()
      (definitions
        (define (sp<? seqno.pelt1 seqno.pelt2)
          (let f ([n1* (car seqno.pelt1)] [n2* (car seqno.pelt2)])
            (if (null? n1*)
                #f
                (or (< (car n1*) (car n2*))
                    (and (= (car n1*) (car n2*))
                         (f (cdr n1*) (cdr n2*)))))))
        (define (process-frob-worklist seqno.pelt*)
          ; We're going to some trouble here to maintain the original ordering
          ; of pelts to simplify testing and manual comparision of pass outputs.
          ; A specific ordering is not required for correctness.  The order of
          ; any two pelts or groups of (module) pelts produced via type
          ; parameterization of the same function is not guaranteed.
          (if (null? frob*)
              (map cdr (sort sp<? seqno.pelt*))
              (let ([frob (car frob*)])
                (set! frob* (cdr frob*))
                (process-frob-worklist
                  (cons
                    (cons (frob-seqno frob) (process-frob frob))
                    seqno.pelt*))))))
      [(program ,src ,pelt* ...)
       (fluid-let ([program-src src])
         (let ([exported-type* '()] [exported-other* '()])
           (let ([export* (process-pelts #t pelt* (map list (enumerate pelt*)) empty-env)])
             (let ([export-ht (make-hashtable symbol-hash eq?)])
               (define (already-exported? src export-name key)
                 (let ([a (hashtable-cell export-ht export-name #f)])
                   (if (cdr a)
                       (or (eq? (cdr a) key)
                           (source-errorf src "multiple top-level exports for ~s" export-name))
                       (begin
                         (set-cdr! a key)
                         #f))))
               (for-each
                 (lambda (x)
                   (let retry ([src (exportit-src x)] [export-name (exportit-name x)] [info (exportit-info x)])
                     (Info-case info
                       [(Info-functions name info-fun+)
                        (for-each
                          (lambda (info-fun)
                            (unless (eq? (info-fun-kind info-fun) 'circuit)
                              (source-errorf src "cannot export ~s (~s) from the top level" (info-fun-kind info-fun) export-name))
                            (unless (null? (info-fun-type-param* info-fun))
                              (source-errorf src "cannot export type-parameterized function (~s) from the top level" export-name))
                            (let ([id (make/register-frob src name info-fun '() #t)])
                              (unless (already-exported? src export-name id)
                                (id-exported?-set! id #t)
                                (set! exported-other* (cons (cons export-name id) exported-other*)))))
                          info-fun+)]
                       [(Info-circuit-alias aliased-name info) (retry src export-name info)]
                       [(Info-struct src^ struct-name type-param* elt-name* type* p^)
                        (unless (already-exported? src export-name info)
                          (set! exported-type*
                            (cons
                              (let ([type (apply-struct src src^ struct-name type-param* elt-name* type* p^
                                                        (map Info-free-tvar (map type-param->tvar-name type-param*)))]
                                    [tvar-name* (fold-right
                                                  (lambda (type-param tvar-name*)
                                                    (nanopass-case (Lpreexpand Type-Param) type-param
                                                      [(nat-valued ,src ,tvar-name) tvar-name*]
                                                      [(type-valued ,src ,tvar-name) (cons tvar-name tvar-name*)]))
                                                  '()
                                                  type-param*)])
                                (with-output-language (Lexpanded Export-Type-Definition)
                                  `(export-typedef ,src^ ,export-name (,tvar-name* ...) ,type)))
                              exported-type*)))]
                       [(Info-enum src^ enum-name elt-name elt-name*)
                        (unless (already-exported? src export-name info)
                          (set! exported-type*
                            (cons
                              (with-output-language (Lexpanded Export-Type-Definition)
                                `(export-typedef ,src^ ,export-name () (tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)))
                              exported-type*)))]
                       [(Info-type-alias src^ nominal? type-name type-param* type p^)
                        (unless (already-exported? src export-name info)
                          (set! exported-type*
                            (cons
                              (let ([type (apply-type-alias src src^ #f type-name type-param* type p^
                                            (map Info-free-tvar (map type-param->tvar-name type-param*)))]
                                    [tvar-name* (fold-right
                                                  (lambda (type-param tvar-name*)
                                                    (nanopass-case (Lpreexpand Type-Param) type-param
                                                      [(nat-valued ,src ,tvar-name) tvar-name*]
                                                      [(type-valued ,src ,tvar-name) (cons tvar-name tvar-name*)]))
                                                  '()
                                                  type-param*)])
                                (with-output-language (Lexpanded Export-Type-Definition)
                                  `(export-typedef ,src^ ,export-name (,tvar-name* ...) ,type)))
                              exported-type*)))]
                       [(Info-ledger ledger-field-name)
                        (unless (already-exported? src export-name ledger-field-name)
                          (id-exported?-set! ledger-field-name #t)
                          (set! exported-other* (cons (cons export-name ledger-field-name) exported-other*)))]
                       [else (export-oops src export-name info)])))
                 (reverse export*))))
           (let ([reachable* (process-frob-worklist seqno.pelt*)])
             ; process uninstantiated modules to catch any errors therein, skipping those
             ; with generic parameters since we have no generic values to supply
             (let loop ()
               (unless (null? all-Info-modules)
                 (let-values ([(info name) (let ([a (car all-Info-modules)]) (values (car a) (cdr a)))])
                   (set! all-Info-modules (cdr all-Info-modules))
                   (Info-case info
                     [(Info-module type-param* pelt* p seqno dirname instance-table)
                      (when (and (null? type-param*) (eqv? (hashtable-size instance-table) 0))
                        (with-module-cycle-check src info name
                          (lambda ()
                            ; presently dirname should never be non-false for an unreachable module:
                            ; the only way a module has a non-false dirname is via a reachable import
                            (parameterize ([relative-path (if dirname dirname (relative-path))])
                              (process-pelts #f
                                pelt*
                                (map (lambda (i) (cons i seqno)) (enumerate pelt*))
                                p)))))]
                     [else (assert cannot-happen)])
                   (loop))))
             (for-each
               (lambda (info-fun name)
                 (when (and (null? (info-fun-type-param* info-fun))
                            (eqv? (hashtable-size (info-fun-instance-table info-fun)) 0))
                   (make/register-frob src name info-fun '() #f)))
               (map car all-info-funs)
               (map cdr all-info-funs))
             (let ([unreachable* (process-frob-worklist '())]
                   [ecdecl* (map (lambda (ecdecl) (External-Contract-Declaration (car ecdecl) (cdr ecdecl))) ecdecl*)]
                   [exported-other* (sort (lambda (x y) (string<? (symbol->string (car x)) (symbol->string (car y))))
                                          exported-other*)])
               `(program ,src
                  ((,(map car exported-other*) ,(map cdr exported-other*)) ...)
                  (,unreachable* ...)
                  (,ecdecl* ...)
                  ,(reverse exported-type*) ...
                  ,reachable* ...)))))])
    (Program-Element : Program-Element (ir p id) -> Program-Element ()
      [(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,[arg*] ...) ,[type] ,expr)
       (let ([var-id* (map arg->id arg*)] [p (add-rib p)])
         (begin
           (for-each
             (lambda (id) (env-insert! p src (id-sym id) (Info-var id)))
             var-id*)
           (when pure-dcl? (id-pure?-set! id #t)))
         `(circuit ,src ,id (,arg* ...) ,type ,(Expression expr p)))]
      [(external ,src ,exported? ,function-name (,type-param* ...) (,[arg*] ...) ,[type])
       (let ([native-entry (get-native-entry src function-name (length arg*))])
         `(external ,src ,id ,native-entry (,arg* ...) ,type))]
      [(witness ,src ,exported? ,function-name (,type-param* ...) (,[arg*] ...) ,[type])
       `(witness ,src ,id (,arg* ...) ,type)]
      [(public-ledger-declaration ,src ,exported? ,sealed? ,ledger-field-name ,[type])
       (when sealed? (id-sealed?-set! id #t))
       `(public-ledger-declaration ,src ,id
          ,(if (public-adt? type)
               type
               (let ([p (or Cell-ADT-env
                            (let ([p (add-rib empty-env)])
                              (do-import src 'CompactStandardLibrary '() ""
                                         (list (with-output-language (Lpreexpand Import-Element)
                                                 `(,src __compact_Cell __compact_Cell)))
                                         p)
                              (set! Cell-ADT-env p)
                              p))])
                 (handle-type-ref src 'Cell (list (Info-type src type)) (lookup p src '__compact_Cell)))))]
      [(constructor ,src (,[arg*] ...) ,expr)
       (let ([var-id* (map arg->id arg*)] [p (add-rib p)])
         (for-each
           (lambda (id) (env-insert! p src (id-sym id) (Info-var id)))
           var-id*)
         `(constructor ,src (,arg* ...) , (Expression expr p)))]
      [else (internal-errorf 'expand-modules-and-types "unexpected program element ~s" ir)])
    (External-Contract-Declaration : External-Contract-Declaration (ir p) -> External-Contract-Declaration ()
      [(external-contract ,src ,exported? ,contract-name ,[ecdecl-circuit*] ...)
       `(external-contract ,src ,contract-name ,ecdecl-circuit* ...)])
    (External-Contract-Circuit : External-Contract-Circuit (ir p) -> External-Contract-Circuit ()
      [(,src ,pure-dcl ,function-name (,[arg*] ...) ,[type])
       `(,src ,pure-dcl ,function-name (,arg* ...) ,type)])
    (ADT-Op-Class : ADT-Op-Class (ir) -> ADT-Op-Class ())
    (Argument : Argument (ir p) -> Argument ()
      [(,src ,var-name ,[type]) `(,(make-source-id src var-name) ,type)])
    (Expression : Expression (ir p) -> Expression ()
      [(var-ref ,src ,var-name)
       (Info-lookup (p src var-name)
         [(Info-var id) `(var-ref ,src ,id)]
         [(Info-size src^ size) `(quote ,src ,size)]
         [(Info-ledger ledger-field-name) `(ledger-ref ,src ,ledger-field-name)]
         [(Info-bogus)
          (source-errorf src "identifier ~s might be referenced before it is assigned"
                         var-name)])]
      [(block ,src (,var-name* ...) ,expr)
       (let ([p (add-rib p)])
         (for-each
           (lambda (var-name) (env-insert! p src var-name (Info-bogus)))
           var-name*)
         (Expression expr p))]
      [(let* ,src ([,[arg*] ,[expr*]] ...) ,expr)
       (let ([var-id* (map arg->id arg*)] [p (add-rib p)])
         (for-each
           (lambda (id) (env-insert! p src (id-sym id) (Info-var id)))
           var-id*)
         `(let* ,src ([,arg* ,expr*] ...) ,(Expression expr p)))]
      [(for ,src ,var-name ,[expr1] ,expr2)
       (let ([id (make-source-id src var-name)] [p (add-rib p)])
         (env-insert! p src var-name (Info-var id))
         `(for ,src ,id ,expr1 ,(Expression expr2 p)))]
      [(tuple-slice ,src ,[expr] ,[index] ,[Type-Size->nat : tsize p -> * nat])
       (check-length! src "slice" nat)
       `(tuple-slice ,src ,expr ,index ,nat)]
      [(elt-ref ,src ,expr ,elt-name^)
       (or (nanopass-case (Lpreexpand Expression) expr
             [(var-ref ,src^ ,var-name)
              (Info-case (lookup p src^ var-name)
                [(Info-enum src^ enum-name elt-name elt-name*)
                 `(enum-ref ,src (tenum ,src ,enum-name ,elt-name ,elt-name* ...) ,elt-name^)]
                [(Info-type src type)
                 (nanopass-case (Lexpanded Type) (de-alias type #t)
                   [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                    `(enum-ref ,src ,type ,elt-name^)]
                   [else #f])]
                [(Info-type-alias src nominal? type-name type-param* type p)
                 (let ([type (apply-type-alias src src^ nominal? type-name type-param* type p '())])
                   (nanopass-case (Lexpanded Type) (de-alias type #t)
                     [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                      `(enum-ref ,src ,type ,elt-name^)]
                     [else #f]))]
                [else #f])]
             [else #f])
           `(elt-ref ,src ,(Expression expr p) ,elt-name^))]
      [(call ,src ,[fun] ,expr* ...) ; force fun to be processed before expr* to get better error messages
       `(call ,src ,fun ,(map (lambda (e) (Expression e p)) expr*) ...)])
    (Function : Function (ir p) -> Function ()
      [(fref ,src ,function-name)
       (lookup-fun p src function-name '())]
      [(fref ,src ,function-name (,[Type-Argument->info : targ* p -> * info*] ...))
       (lookup-fun p src function-name info*)]
      [(circuit ,src (,[arg*] ...) ,[type] ,expr)
       (let ([var-id* (map arg->id arg*)] [p (add-rib p)])
         (for-each
           (lambda (id) (env-insert! p src (id-sym id) (Info-var id)))
           var-id*)
         `(circuit ,src (,arg* ...) ,type , (Expression expr p)))])
    (Tuple-Argument : Tuple-Argument (ir p) -> Tuple-Argument ())
    (New-Field : New-Field (ir p) -> New-Field ())
    (Type : Type (ir p) -> Type ()
      [,tref (Type-Ref->Type ir p)]
      [(tunsigned ,src ,[Type-Size->nat : tsize p -> * nat])
       (unless (<= 1 nat (unsigned-bits))
         (source-errorf src "Uint width ~d is not between 1 and the maximum Uint width ~d (inclusive)"
                        nat
                        (unsigned-bits)))
       `(tunsigned ,src ,(- (expt 2 nat) 1))]
      [(tunsigned ,src ,[Type-Size->nat : tsize p -> * nat] ,[Type-Size->nat : tsize^ p -> * nat^])
       (unless (= nat 0)
         (source-errorf src "range start for Uint type is ~d but must be 0" nat))
       (unless (<= 1 nat^)
         (source-errorf src "range end for Uint type is ~d but must be at least 1 (the range end is exclusive)"
                        nat^))
       (unless (<= nat^ (+ (max-unsigned) 1))
         (source-errorf src "range end\n    ~d\n  for Uint type exceeds the limit of\n    ~d (2^~d)\n  (the range end is exclusive)"
                        nat^
                        (+ (max-unsigned) 1)
                        (unsigned-bits)))
       `(tunsigned ,src ,(- nat^ 1))]
      [(tvector ,src ,[Type-Size->nat : tsize p -> * nat] ,[type])
       (check-length! src "vector type" nat)
       `(tvector ,src ,nat ,type)]
      [(tbytes ,src ,[Type-Size->nat : tsize p -> * nat])
       (check-length! src "bytes type" nat)
       `(tbytes ,src ,nat)]
      [(ttuple ,src ,[type*] ...)
       (check-length! src "tuple type" (length type*))
       `(ttuple ,src ,type* ...)])
    (Type-Ref->Type : Type-Ref (ir p) -> Type ()
      [(type-ref ,src ,tvar-name ,[Type-Argument->info : targ* p -> * info*] ...)
       (handle-type-ref src tvar-name info* (lookup p src tvar-name))])
    (Type-Size->nat : Type-Size (ir p) -> * (nat)
      [(type-size ,src ,nat) nat]
      [(type-size-ref ,src ,tsize-name)
       (Info-lookup (p src tsize-name)
         [(Info-size src size) size]
         ; if we find a free tvar here, it's in an exported type where sizes are
         ; ultimately ignored, so any nat will do
         [(Info-free-tvar tvar-name) 0])])
    (Type-Argument->info : Type-Argument (ir p) -> * (info)
      [(targ-size ,src ,nat) (Info-size src nat)]
      [(targ-type ,src (type-ref ,src^ ,tvar-name ,[Type-Argument->info : targ* p -> * info*] ...))
       (let ([info (lookup p src tvar-name)])
         (Info-case info
           [(Info-size src^^ size)
            (unless (null? info*) (generic-argument-count-oops src tvar-name (length info*) 0))
            (Info-size src size)]
           [else (Info-type src (handle-type-ref src tvar-name info* info))]))]
      [(targ-type ,src ,type) (Info-type src (Type type p))])
  )

  (define-pass generate-contract-ht : Lexpanded (ir) -> Lexpanded ()
    (definitions
      (define (register-contract-info! src contract-name)
        (define (contract-source-filename)
          (let ([sd (source-directory)])
            (if (string=? sd "")
                (format "~a.compact" contract-name)
                (format "~a/~a.compact" sd contract-name))))
        (define (contract-info-filename)
          (format "~a/~a/compiler/contract-info.json"
            (path-parent (target-directory))
            contract-name))
        (define (malformed msg . args)
          (external-errorf "malformed contract-info file ~a for ~s: ~a; try recompiling ~a"
                           (contract-info-filename)
                           contract-name
                           (apply format msg args)
                           contract-name))
        (define (get-assoc key alist)
          (cond
            [(and (pair? alist) (assoc key alist)) => cdr]
            [else (malformed "missing association for ~s" key)]))
        (let ([info (let* ([contract-ht (contract-ht)]
                           [a (hashtable-cell contract-ht contract-name #f)])
                      (or (cdr a)
                          (let ([source-fn (contract-source-filename)]
                                [info-fn (contract-info-filename)])
                            (let ([jf (guard (c [else (source-errorf src "error opening ~a; try (re)compiling ~a" info-fn source-fn)])
                                        (open-json-file info-fn))])
                              (when (and (file-exists? source-fn)
                                         (time<?
                                           (file-modification-time info-fn)
                                           (file-modification-time source-fn)))
                                (source-errorf src "~a has been modified more recently than ~a; try recompiling ~a"
                                               source-fn
                                               info-fn
                                               source-fn))
                              (let ([info (guard (c [else (source-errorf src "error reading ~a: ~a" info-fn
                                                            (with-output-to-string
                                                              (lambda ()
                                                                (display-condition c))))])
                                            (read-json jf))])
                                (set-cdr! a info)
                                info)))))])
          (let* ([alist info]
                 [v (vector-map string->symbol (get-assoc "contracts" alist))])
          (unless (vector? v) (malformed "\"contracts\" is not associated with a vector"))
          (vector-for-each (lambda (contract-name)
                             (register-contract-info! src contract-name))
              v))))
        )
    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) (,unused-pelt* ...) (,[ecdecl*] ...) ,pelt* ...)
       `(program ,src ((,export-name* ,name*) ...) (,unused-pelt* ...) (,ecdecl* ...) ,pelt* ...)])
    (build-contract-info! : External-Contract-Declaration (ir) -> External-Contract-Declaration ()
      [(external-contract ,src ,contract-name ,ecdecl-circuit* ...)
       (register-contract-info! src contract-name)
       ir]))

  (define-pass infer-types : Lexpanded (ir) -> Ltypes ()
    (definitions
      (define-syntax T
        (syntax-rules ()
          [(T ty clause ...)
           (nanopass-case (Ltypes Type) ty clause ... [else #f])]))
      (define-datatype Idtype
        ; ordinary expression types
        (Idtype-Base type)
        ; circuits, witnesses, and statements
        (Idtype-Function kind arg-name* arg-type* return-type)
        )
      (module (set-idtype! unset-idtype! get-idtype)
        (define ht (make-eq-hashtable))
        (define (set-idtype! id idtype)
          (hashtable-set! ht id idtype))
        (define (unset-idtype! id)
          (hashtable-delete! ht id))
        (define (get-idtype src id)
          (or (hashtable-ref ht id #f)
              (internal-errorf 'set-idtype! "type of identifier ~s at ~a has not been set"
                (id-sym id)
                (format-source-object src))))
        )
      (define (arg->name arg)
        (nanopass-case (Ltypes Argument) arg
          [(,var-name ,type) var-name]))
      (define (arg->type arg)
        (nanopass-case (Ltypes Argument) arg
          [(,var-name ,type) type]))
      (define (format-adt-arg adt-arg)
        (nanopass-case (Ltypes Public-Ledger-ADT-Arg) adt-arg
          [,nat (format "~d" nat)]
          [,type (format-type type)]))
      (define (format-public-adt adt-name adt-arg*)
        (if (eq? adt-name '__compact_Cell)
            (begin
              (assert (= (length adt-arg*) 1))
              (format-adt-arg (car adt-arg*)))
            (format "~s~@[<~{~a~^, ~}>~]" adt-name (and (not (null? adt-arg*)) (map format-adt-arg adt-arg*)))))
      (define (format-type type)
        (nanopass-case (Ltypes Type) type
          [(tboolean ,src) "Boolean"]
          [(tfield ,src) "Field"]
          [(tunsigned ,src ,nat)
           (or (and (> nat 0)
                    (let ([bits (integer-length nat)])
                      (and (= (expt 2 bits) (+ nat 1))
                           (format "Uint<~d>" bits))))
               (format "Uint<0..~d>" (+ nat 1)))]
          [(topaque ,src ,opaque-type) (format "Opaque<~s>" opaque-type)]
          [(tunknown) "Unknown"]
          [(tundeclared) "Undeclared"]
          [(tvector ,src ,len ,type) (format "Vector<~s, ~a>" len (format-type type))]
          [(tbytes ,src ,len) (format "Bytes<~s>" len)]
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (format "contract ~a<~{~a~^, ~}>" contract-name
             (map (lambda (elt-name pure-dcl type* type)
                    (if pure-dcl
                        (format "pure ~a(~{~a~^, ~}): ~a" elt-name
                                (map format-type type*) (format-type type))
                        (format "~a(~{~a~^, ~}): ~a" elt-name
                                (map format-type type*) (format-type type))))
                  elt-name* pure-dcl* type** type*))]
          [(ttuple ,src ,type* ...)
           (format "[~{~a~^, ~}]" (map format-type type*))]
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           (format "struct ~a<~{~a~^, ~}>" struct-name
             (map (lambda (elt-name type)
                    (format "~a: ~a" elt-name (format-type type)))
                  elt-name* type*))]
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
           (format "Enum<~a, ~s~{, ~s~}>" enum-name elt-name elt-name*)]
          [(talias ,src ,nominal? ,type-name ,type)
           (if nominal?
               (format "~a" type-name)
               (format-type type))]
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (format-public-adt adt-name adt-arg*)]
          [else (internal-errorf 'format-type "unrecognized type ~a" type)]))
      (define (de-alias type nominal-too?)
        (nanopass-case (Ltypes Type) type
          [(talias ,src ,nominal? ,type-name ,type)
           (guard (or nominal-too? (not nominal?)))
           (de-alias type nominal-too?)]
          [else type]))
      (module (sametype? subtype?)
        (define (same-adt-arg? adt-arg1 adt-arg2)
          (nanopass-case (Ltypes Public-Ledger-ADT-Arg) adt-arg1
            [,nat1
             (nanopass-case (Ltypes Public-Ledger-ADT-Arg) adt-arg2
               [,nat2 (= nat1 nat2)]
               ; with current restrictions, this case won't get past ledger meta-type checks
               [else #f])]
            [,type1
             (nanopass-case (Ltypes Public-Ledger-ADT-Arg) adt-arg2
               [,type2 (sametype? type1 type2)]
               ; with current restrictions, this case won't get past ledger meta-type checks
               [else #f])]))
        (define (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*)
          (andmap (lambda (elt-name2 pure-dcl2 type2* type2)
                    (ormap (lambda (elt-name1 pure-dcl1 type1* type1)
                             (and (eq? elt-name1 elt-name2)
                                  (eq? pure-dcl1 pure-dcl2)
                                  (fx= (length type1*) (length type2*))
                                  (andmap sametype? type1* type2*)
                                  (sametype? type1 type2)))
                           elt-name1* pure-dcl1* type1** type1*))
                  elt-name2* pure-dcl2* type2** type2*))
        (define (sametype? type1 type2)
          (let ([type1 (de-alias type1 #f)] [type2 (de-alias type2 #f)])
            (or (eq? type1 type2)
                (T type1
                   [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
                   [(tfield ,src1) (T type2 [(tfield ,src2) #t])]
                   [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])]
                   [(tbytes ,src1 ,len1) (T type2 [(tbytes ,src2 ,len2) (= len1 len2)])]
                   [(topaque ,src1 ,opaque-type1)
                    (T type2
                       [(topaque ,src2 ,opaque-type2)
                        (string=? opaque-type1 opaque-type2)])]
                   [(tvector ,src1 ,len1 ,type1)
                    (T type2
                       [(tvector ,src2 ,len2 ,type2)
                        (and (= len1 len2)
                             (sametype? type1 type2))]
                       [(ttuple ,src2 ,type2* ...)
                        (and (= len1 (length type2*))
                             (andmap (lambda (type2) (sametype? type1 type2)) type2*))])]
                   [(ttuple ,src1 ,type1* ...)
                    (T type2
                       [(tvector ,src2 ,len2 ,type2)
                        (and (= (length type1*) len2)
                             (andmap (lambda (type1) (sametype? type1 type2)) type1*))]
                       [(ttuple ,src2 ,type2* ...)
                        (and (= (length type1*) (length type2*))
                             (andmap sametype? type1* type2*))])]
                   [(tunknown) (T type2 [(tunknown) #t])]
                   [(tundeclared) (T type2 [(tundeclared) #t])]
                   [(tcontract ,src1 ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
                    (T type2
                       [(tcontract ,src2 ,contract-name2 (,elt-name2* ,pure-dcl2* (,type2** ...) ,type2*) ...)
                        (and (eq? contract-name1 contract-name2)
                             (fx= (length elt-name1*) (length elt-name2*))
                             (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*))])]
                   [(tstruct ,src1 ,struct-name1 (,elt-name1* ,type1*) ...)
                    (T type2
                       [(tstruct ,src2 ,struct-name2 (,elt-name2* ,type2*) ...)
                        ; include struct-name and elt-name tests for nominal typing; remove
                        ; for structural typing.
                        (and (eq? struct-name1 struct-name2)
                             (fx= (length elt-name1*) (length elt-name2*))
                             (andmap eq? elt-name1* elt-name2*)
                             (andmap sametype? type1* type2*))])]
                   [(tenum ,src1 ,enum-name1 ,elt-name1 ,elt-name1* ...)
                    (T type2
                       [(tenum ,src2 ,enum-name2 ,elt-name2 ,elt-name2* ...)
                        (and (eq? enum-name1 enum-name2)
                             (eq? elt-name1 elt-name2)
                             (fx= (length elt-name1*) (length elt-name2*))
                             (andmap eq? elt-name1* elt-name2*))])]
                   [(talias ,src1 ,nominal1? ,type-name1 ,type1)
                    (assert nominal1?)
                    (T type2
                       [(talias ,src2 ,nominal2? ,type-name2 ,type2)
                        (assert nominal2?)
                        (and (eq? type-name1 type-name2)
                             (sametype? type1 type2))])]
                   [(tadt ,src1 ,adt-name1 ([,adt-formal1* ,adt-arg1*] ...) ,vm-expr (,adt-op1* ...) (,adt-rt-op1* ...))
                    (T type2
                       [(tadt ,src2 ,adt-name2 ([,adt-formal2* ,adt-arg2*] ...) ,vm-expr (,adt-op2* ...) (,adt-rt-op2* ...))
                        (and (eq? adt-name1 adt-name2)
                             (fx= (length adt-arg1*) (length adt-arg2*))
                             (andmap same-adt-arg? adt-arg1* adt-arg2*))])]))))
        (define (subtype? type1 type2)
          (let ([type1 (de-alias type1 #f)] [type2 (de-alias type2 #f)])
            (or (eq? type1 type2)
                (T type1
                   [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
                   [(tfield ,src1) (T type2 [(tfield ,src2) #t])]
                   [(tunsigned ,src1 ,nat1)
                    (T type2
                       [(tunsigned ,src2 ,nat2) (<= nat1 nat2)]
                       [(tfield ,src2) #t])]
                   [(tbytes ,src1 ,len1) (T type2 [(tbytes ,src2 ,len2) (= len1 len2)])]
                   [(topaque ,src1 ,opaque-type1)
                    (T type2
                       [(topaque ,src2 ,opaque-type2)
                        (string=? opaque-type1 opaque-type2)])]
                   [(tvector ,src1 ,len1 ,type1)
                    (T type2
                       [(tvector ,src2 ,len2 ,type2)
                        (and (= len1 len2)
                             (subtype? type1 type2))]
                       [(ttuple ,src2 ,type2* ...)
                        (and (= len1 (length type2*))
                             (andmap (lambda (type2) (subtype? type1 type2)) type2*))])]
                   [(ttuple ,src1 ,type1* ...)
                    (T type2
                       [(tvector ,src2 ,len2 ,type2)
                        (and (= (length type1*) len2)
                             (andmap (lambda (type1) (subtype? type1 type2)) type1*))]
                       [(ttuple ,src2 ,type2* ...)
                        (and (= (length type1*) (length type2*))
                             (andmap subtype? type1* type2*))])]
                   [(tunknown) #t] ; tunknown values originate from empty-vector constants.
                   [(tundeclared) (T type2 [(tundeclared) #t])]
                   [(tcontract ,src1 ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
                    (T type2
                       [(tcontract ,src2 ,contract-name2 (,elt-name2* ,pure-dcl2* (,type2** ...) ,type2*) ...)
                        (and (eq? contract-name1 contract-name2)
                             (fx>= (length elt-name1*) (length elt-name2*))
                             (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*))])]
                   [(tstruct ,src1 ,struct-name1 (,elt-name1* ,type1*) ...)
                    (T type2
                       [(tstruct ,src2 ,struct-name2 (,elt-name2* ,type2*) ...)
                        ; include struct-name and elt-name tests for nominal typing; remove
                        ; and change sametype? to subtype? for structural typing.
                        (and (eq? struct-name1 struct-name2)
                             (fx= (length elt-name1*) (length elt-name2*))
                             (andmap eq? elt-name1* elt-name2*)
                             (andmap sametype? type1* type2*))])]
                   [(tenum ,src1 ,enum-name1 ,elt-name1 ,elt-name1* ...)
                    (T type2
                       [(tenum ,src2 ,enum-name2 ,elt-name2 ,elt-name2* ...)
                        (and (eq? enum-name1 enum-name2)
                             (eq? elt-name1 elt-name2)
                             (fx= (length elt-name1*) (length elt-name2*))
                             (andmap eq? elt-name1* elt-name2*))])]
                   [(talias ,src1 ,nominal1? ,type-name1 ,type1)
                    (assert nominal1?)
                    (T type2
                       [(talias ,src2 ,nominal2? ,type-name2 ,type2)
                        (assert nominal2?)
                        (and (eq? type-name1 type-name2)
                             (sametype? type1 type2))])]
                   [(tadt ,src1 ,adt-name1 ([,adt-formal1* ,adt-arg1*] ...) ,vm-expr (,adt-op1* ...) (,adt-rt-op1* ...))
                    (T type2
                       [(tadt ,src2 ,adt-name2 ([,adt-formal2* ,adt-arg2*] ...) ,vm-expr (,adt-op2* ...) (,adt-rt-op2* ...))
                        (and (eq? adt-name1 adt-name2)
                             (fx= (length adt-arg1*) (length adt-arg2*))
                             (andmap same-adt-arg? adt-arg1* adt-arg2*))])])
                (T type2
                   [(tundeclared) #t])))))
      (define (public-adt? type)
        (nanopass-case (Ltypes Type) (de-alias type #t)
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #t]
          [else #f]))
      (define (verify-non-adt-type! src type fmt . arg*)
        (when (public-adt? type)
          (source-errorf src
                          "expected ~a type to be an ordinary Compact type but received ADT type ~a"
                          (apply format fmt arg*)
                          (format-type type))))
      (define-syntax Non-ADT-Type
        (syntax-rules ()
          [(_ ?type ?src ?fmt ?arg ...)
           (let ([type (Type ?type)])
             (verify-non-adt-type! ?src type ?fmt ?arg ...)
             type)]))
      (define (contains-contract? type)
        (T (de-alias type #t)
           [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... ) #t]
           [(ttuple ,src ,type* ...) (ormap contains-contract? type*)]
           [(tvector ,src ,len ,type) (contains-contract? type)]
           [(tstruct ,src ,struct-name (,elt-name* ,type*) ...) (ormap contains-contract? type*)]))
      (define check-contract
        (lambda (src contract-name)
          (let ([info (hashtable-cell (contract-ht) contract-name #f)])
            (lambda (src elt-name pure-dcl type* type)
              (define (contract-info-filename)
                (format "~a/~a/compiler/contract-info.json"
                  (path-parent (target-directory))
                  contract-name))
              (define (malformed msg . args)
                (external-errorf "malformed contract-info file ~a for ~s: ~a; try recompiling ~a"
                                 (contract-info-filename)
                                 contract-name
                                 (apply format msg args)
                                 contract-name))
              (define (get-assoc key alist)
                (cond
                  [(and (pair? alist) (assoc key alist)) => cdr]
                  [else (malformed "missing association for ~s" key)]))
              (define (tonat n)
                (unless (field? n) (malformed "expected nat, got ~a" n))
                n)
              (define (tosym s)
                (unless (string? s) (malformed "expected a string, got ~s" s))
                (string->symbol s))
              (define (tolist v)
                (unless (vector? v) (malformed "expected a vector, got ~s" v))
                (vector->list v))
              (define (tobool b)
                (unless (boolean? b) (malformed "expected a boolean, got ~s" b))
                b)
              (define (totype alist)
                (with-output-language (Ltypes Type)
                  (let ([type-name (get-assoc "type-name" alist)])
                    (case type-name
                      [("Boolean") `(tboolean ,src)]
                      [("Field") `(tfield ,src)]
                      [("Uint") `(tunsigned ,src ,(tonat (get-assoc "maxval" alist)))]
                      [("Bytes") `(tbytes ,src ,(tonat (get-assoc "length" alist)))]
                      [("Opaque") `(topaque ,src ,(get-assoc "tsType" alist))]
                      [("Vector") `(tvector ,src ,(tonat (get-assoc "length" alist)) ,(totype (get-assoc "type" alist)))]
                      [("Tuple") `(ttuple ,src ,(map totype (tolist (get-assoc "types" alist))) ...)]
                      ;; this will never be exercised since exported circuits cannot take contracts as their
                      ;; parameter or return value
                      [("Contract")
                       (let ([circuits (tolist (get-assoc "circuits" alist))])
                         `(tcontract ,src
                                     ,(tosym (get-assoc "name" alist))
                                     (,(map (lambda (alist) (tosym (get-assoc "name" alist))) circuits)
                                      ,(map (lambda (alist) (tobool (get-assoc "pure" alist))) circuits)
                                      (,(map (lambda (alist) (map totype (tolist (get-assoc "argument-types" alist)))) circuits) ...)
                                      ,(map (lambda (alist) (totype (get-assoc "result-type" alist))) circuits))
                                     ...))]
                      [("Struct")
                       (let ([elt-alist* (tolist (get-assoc "elements" alist))])
                         `(tstruct ,src
                                   ,(tosym (get-assoc "name" alist))
                                   (,(map (lambda (alist) (tosym (get-assoc "name" alist))) elt-alist*)
                                    ,(map (lambda (alist) (totype (get-assoc "type" alist))) elt-alist*))
                                   ...))]
                      [("Enum")
                       (let ([enum-name (tosym (get-assoc "name" alist))]
                             [elt+ (tolist (get-assoc "elements" alist))])
                         (when (null? elt+) (malformed "enum ~a does not have any members" enum-name))
                         (let ([elt-name+ (map tosym elt+)])
                           `(tenum ,src ,enum-name
                                   ,(car elt-name+)
                                   ,(cdr elt-name+)
                                   ...)))]
                      [("Alias")
                       (let ([type-name (tosym (get-assoc "name" alist))]
                             [type (totype (get-assoc "type" alist))])
                         `(talias ,src #t ,type-name ,type))]
                      [else (malformed "unrecognized type-name ~a" type-name)]))))
              (let ([alist (cdr info)])
                (let ([v (get-assoc "circuits" alist)])
                  (unless (vector? v) (malformed "\"circuits\" is not associated with a vector"))
                  (let ([n (vector-length v)])
                    (let find-elt ([i 0])
                      (if (fx= i n)
                          (source-errorf src "contract declaration has a circuit named ~s, but it is not present in the actual contract definition" elt-name)
                          (let ([alist (vector-ref v i)])
                            (let ([name (get-assoc "name" alist)]
                                  [is-pure (tobool (get-assoc "pure" alist))])
                              (if (equal? (symbol->string elt-name) name)
                                  (let ([type^* (map (lambda (alist) (totype (get-assoc "type" alist)))
                                                  (tolist (get-assoc "arguments" alist)))]
                                        [type^ (totype (get-assoc "result-type" alist))])
                                    (when (and pure-dcl (not is-pure))
                                      (source-errorf src "contract declaration claims circuit ~s is pure, but it is not in the actual contract definition" elt-name))
                                    (let ([nargs (length type*)] [nargs^ (length type^*)])
                                      (unless (= nargs nargs^)
                                        (source-errorf src "contract declaration claims circuit ~s has ~s argument~:*~p, but in the actual contract definition it has ~s"
                                                       elt-name
                                                       nargs
                                                       nargs^)))
                                    (for-each
                                      (lambda (type type^ k)
                                        (unless (sametype? type type^)
                                          (source-errorf src "contract declaration claims the type of circuit ~s argument ~s is ~a, but in the actual contract definition it is ~a"
                                                         elt-name
                                                         (fx+ k 1)
                                                         (format-type type)
                                                         (format-type type^))))
                                      type* type^* (enumerate type*))
                                    (unless (sametype? type type^)
                                      (source-errorf src "contract declaration claims the return type of circuit ~s is ~a, but in the actual contract definition it is ~a"
                                                     elt-name
                                                     (format-type type)
                                                     (format-type type^))))
                                (find-elt (fx+ i 1))))))))))))))
      (define (declared? type)
        (nanopass-case (Ltypes Type) type
          [(tundeclared) #f]
          [else #t]))
      (define current-whose-body #f)
      (define current-return-type #f)
      (define (do-circuit-body src whose-body arg* return-type expr)
        (let ([id* (map arg->name arg*)] [type* (map arg->type arg*)])
          (for-each (lambda (id type) (set-idtype! id (Idtype-Base type))) id* type*)
          (let-values ([(expr actual-type) (fluid-let ([current-whose-body whose-body]
                                                       [current-return-type return-type])
                                             (Care expr))])
            (unless (subtype? actual-type return-type)
              (source-errorf src "mismatch between actual return type ~a and declared return type ~a of ~a"
                (format-type actual-type)
                (format-type return-type)
                whose-body))
            (for-each unset-idtype! id*)
            (if (declared? return-type)
                (values (maybe-safecast src return-type actual-type expr) return-type)
                (values expr actual-type)))))
      (define maybe-safecast
        (case-lambda
          [(src) (lambda (declared-type actual-type expr)
                   (maybe-safecast src declared-type actual-type expr))]
          [(src declared-type actual-type expr)
           (if (sametype? declared-type actual-type)
               expr
               (with-output-language (Ltypes Expression)
                 `(safe-cast ,src ,declared-type ,actual-type ,expr)))]))
      (define (do-call src fold? fun actual-type* build-call)
        (define compatible-args?
          (let ([nactual (length actual-type*)])
            (lambda (arg-type*)
              (and (= (length arg-type*) nactual)
                   (andmap subtype? actual-type* arg-type*)))))
        (nanopass-case (Lexpanded Function) fun
          [(fref ,src^ ,symbolic-function-name (([,symbolic-function-name** ,function-name**] ...) ...)
                 (,generic-value* ...)
                 ((,src* ,generic-kind** ...) ...))
           (define-record-type blob (nongenerative) (fields name symbolic-name arg-type* return-type))
           (define (blob<? blob1 blob2)
             (source-object<?
               (id-src (blob-name blob1))
               (id-src (blob-name blob2))))
           (let outer ([function-name** function-name**] [symbolic-function-name** symbolic-function-name**] [arg-incompatible-blob** '()] [fold-incompatible-blob** '()])
             (if (null? function-name**)
                 (let ()
                   (define (functions-are ls)
                     (let ([n (length ls)])
                       (if (fx= n 1) "one function is" (format "~r functions are" n))))
                   (source-errorf src "no compatible function named ~a is in scope at this call~@[~a~]~@[~a~]~@[~a~]"
                     symbolic-function-name
                     (let ([generic-failure* (let-values ([(src* generic-kind**)
                                                           (let ([x* (sort (lambda (x y) (source-object<? (car x) (car y)))
                                                                           (map cons src* generic-kind**))])
                                                             (values (map car x*) (map cdr x*)))])
                                               (map (lambda (src generic-kind*)
                                                      (format "declared generics for function at ~a:\n        <~{~s~^, ~}>"
                                                        (format-source-object src)
                                                        generic-kind*))
                                                    src*
                                                    generic-kind**))])
                       (and (not (null? generic-kind**))
                            (format "\n    \
                                     ~a incompatible with the supplied generic values\n      \
                                     supplied generic values:\n        <~{~a~^, ~}>\
                                     ~{\n      ~a~}"
                              (functions-are generic-failure*)
                              (map (lambda (generic-value)
                                     (nanopass-case (Lexpanded Generic-Value) generic-value
                                       [,type (format "type ~a" (format-type (Type type)))]
                                       [,nat (format "size ~d" nat)]))
                                   generic-value*)
                              generic-failure*)))
                     (let ([arg-incompatible* (map (lambda (blob)
                                                     (format "declared argument types for function at ~a:\n        (~{~a~^, ~})"
                                                       (format-source-object (id-src (blob-name blob)))
                                                       (map format-type (blob-arg-type* blob))))
                                                   (sort blob<? (apply append arg-incompatible-blob**)))])
                       (and (not (null? arg-incompatible*))
                            (format "\n    \
                                     ~a incompatible with the supplied argument types\n      \
                                     supplied argument types:\n        (~{~a~^, ~})\
                                     ~{\n      ~a~}"
                              (functions-are arg-incompatible*)
                              (map format-type actual-type*)
                              arg-incompatible*)))
                     (let ([fold-incompatible* (map (lambda (blob)
                                                      (format "declared first-argument and return types for function at ~a:\n        ~a\n        ~a"
                                                        (format-source-object (id-src (blob-name blob)))
                                                        (format-type (car (blob-arg-type* blob)))
                                                        (format-type (blob-return-type blob))))
                                                    (sort blob<? (apply append fold-incompatible-blob**)))])
                       (and (not (null? fold-incompatible*))
                            (format "\n    \
                                     ~a incompatible because fold requires the return type and the first argument type to be the same\
                                     ~{\n      ~a~}"
                              (functions-are fold-incompatible*)
                              fold-incompatible*)))))
                 (let ([function-name* (car function-name**)]
                       [function-name** (cdr function-name**)]
                       [symbolic-function-name* (car symbolic-function-name**)]
                       [symbolic-function-name** (cdr symbolic-function-name**)])
                   (let ([blob* (map (lambda (function-name symbolic-function-name)
                                       (Idtype-case (get-idtype src function-name)
                                         [(Idtype-Function kind arg-name* arg-type* return-type)
                                          (make-blob function-name symbolic-function-name arg-type* return-type)]
                                         [else (assert cannot-happen)]))
                                     function-name*
                                     symbolic-function-name*)])
                     (let*-values ([(arg-compatible-blob* arg-incompatible-blob*)
                                    (partition (lambda (x) (compatible-args? (blob-arg-type* x))) blob*)]
                                   [(compatible-blob* fold-incompatible-blob*)
                                    (if fold?
                                        (partition (lambda (x) (sametype? (blob-return-type x) (car (blob-arg-type* x)))) arg-compatible-blob*)
                                        (values arg-compatible-blob* '()))])
                       (cond
                         [(null? compatible-blob*)
                          (outer function-name** symbolic-function-name**
                                 (cons arg-incompatible-blob* arg-incompatible-blob**)
                                 (cons fold-incompatible-blob* fold-incompatible-blob**))]
                         [(null? (cdr compatible-blob*))
                          (let ([blob (car compatible-blob*)])
                            (unless (eq? (blob-symbolic-name blob) symbolic-function-name)
                              (record-alias! src^ symbolic-function-name (blob-symbolic-name blob)))
                            (build-call
                              (blob-arg-type* blob)
                              (blob-return-type blob)
                              (with-output-language (Ltypes Function)
                                `(fref ,src^ ,(blob-name blob)))))]
                         [else
                          (source-errorf src
                                         "call site ambiguity (multiple compatible functions) in call to ~a\n    \
                                         supplied argument types:\n      \
                                         (~{~a~^, ~})\n    \
                                         compatible functions:\
                                         ~{\n      ~a~}"
                            symbolic-function-name
                            (map format-type actual-type*)
                            (map format-source-object
                                 (sort source-object<?
                                       (map (lambda (blob) (id-src (blob-name blob)))
                                            compatible-blob*))))]))))))]
          [(circuit ,src^ (,[Argument : arg*] ...) ,[Return-Type : type src^ "anonymous circuit" -> type] ,expr)
           ; Inferring the first-argument and return types for fold is a bit
           ; tricky, since the return type becomes the first argument type for
           ; the second and subsequent fold iterations.  We handle inference
           ; as follows.
           ;
           ; When both types are declared:
           ;   We complain as usual if the declared types are not the same type,
           ;   and we complain as usual if either the inferred first-argument type
           ;   or the inferred body type is not a subtype of the declared
           ;   return and first-argument type.
           ;
           ; When the first argument type is declared but not the return type:
           ;   We infer the type of the body as usual based on the declared
           ;   first-argument type.  If the inferred body type is not the same as
           ;   the declared first-argument type, we complain.  Otherwise, we
           ;   use the first-argument type as the return type.
           ;
           ;   An alternative when the inferred body type is a proper subtype
           ;   of the declared first-argument type is is to use the declared
           ;   first-argument type as the return type and upcast the body's
           ;   return value accordingly.  This situation is unusual, however,
           ;   and probably involves an explicit downcast in the body, so doing
           ;   so might be surprising.
           ;
           ; When the return type is declared but not the first-argument type:
           ;   If the inferred first-argument type is not a subtype of the
           ;   declared return type, we complain.  Otherwise we use the declared
           ;   return type for the first-argument type, infer the body type based
           ;   on this, and complain as usual if the inferred body type is not a
           ;   subtype of the declared return type.
           ;
           ; When neither the first-argument type nor the return type is declared:
           ;   We use the inferred type of the first argument as the first-argument
           ;   type and infer the body type based on this.  We complain if the
           ;   inferred body type is not the same the inferred first-argument type.
           ;   Otherwise we also use the inferred first-argument type as the return
           ;   type.
           ;
           ;   An alternative when the inferred body type is a proper supertype
           ;   of the inferred first-argument type is to use the inferred body
           ;   type as the first-argument type and infer the body type again.
           ;   Unfortunately, this might result in a still greater inferred body
           ;   type.  In this case, there might not be a fixpoint or it might be
           ;   prohibitively expensive to find.  And even processing the body
           ;   twice can lead to quadratic compile time if folds are nested.
           (define (replace-undeclared type type^)
             (if (declared? type)
                 type
                 type^))
           (define (fold-error first-arg-type first-arg-type-declared? return-type return-type-declared?)
             (source-errorf src
                            "fold requires the return type and first-argument type to be the same\n    \
                             ~:[[inferred] ~;~]first-argument type: ~a,\n    \
                             ~:[[inferred] ~;~]return type: ~a"
               first-arg-type-declared?
               (format-type first-arg-type)
               return-type-declared?
               (format-type return-type)))
           (let ([arg-type* (map arg->type arg*)])
             (unless (compatible-args? arg-type*)
               (source-errorf src
                              "incompatible arguments in call to anonymous circuit\n    \
                              supplied argument types:\n      \
                              (~{~a~^, ~})\n    \
                              declared circuit type:\n      \
                              (~{~a~^, ~})"
                              (map format-type actual-type*)
                              (map format-type arg-type*)))
             (let* ([known-arg-type*
                      (if (and fold?
                               (declared? type)
                               (not (declared? (car arg-type*))))
                          (begin
                            (unless (subtype? (car actual-type*) type)
                              (fold-error (car actual-type*) #f type #t))
                            (cons type (map replace-undeclared (cdr arg-type*) (cdr actual-type*))))
                          (map replace-undeclared arg-type* actual-type*))]
                    [arg* (map (lambda (var-name known-arg-type)
                                 (with-output-language (Ltypes Argument)
                                   `(,var-name ,known-arg-type)))
                               (map arg->name arg*)
                               known-arg-type*)])
               (let-values ([(expr known-type) (do-circuit-body src^ "anonymous circuit" arg* type expr)])
                 (when fold?
                   (unless (sametype? known-type (car known-arg-type*))
                     (fold-error
                       (car known-arg-type*)
                       (eq? (car known-arg-type*) (car arg-type*))
                       known-type
                       (eq? known-type type))))
                 (build-call
                   known-arg-type*
                   known-type
                   (with-output-language (Ltypes Function)
                     `(circuit ,src (,arg* ...) ,known-type ,expr))))))]))
      (define (max-type type*)
        (let loop ([type* type*] [max-type (with-output-language (Ltypes Type) `(tunknown))])
          (if (null? type*)
              max-type
              (let ([type (car type*)] [type* (cdr type*)])
                (cond
                  [(subtype? type max-type) (loop type* max-type)]
                  [(subtype? max-type type) (loop type* type)]
                  [else #f])))))
      (define (vector-element-type src what type)
        (nanopass-case (Ltypes Type) (de-alias type #t)
          [(ttuple ,src^ ,type^* ...)
           (values
             (length type^*)
             (or (max-type type^*)
                 (source-errorf src "~a should be a vector but has a tuple type ~a that cannot be converted to a vector because its element types are unrelated"
                                what
                                (format-type type))))]
          [(tbytes ,src^ ,len) (values len (with-output-language (Ltypes Type) `(tunsigned ,src 255)))]
          [(tvector ,src^ ,len ,type) (values len type)]
          [else (source-errorf src "~a should be a vector, tuple, or Bytes but has type ~a"
                               what
                               (format-type type))]))
      (define (vector-element-types src who type+ argno)
        (let loop ([type+ type+] [n #f] [argno argno] [rtype* '()])
          (let ([type (car type+)] [type* (cdr type+)])
            (let-values ([(nat type) (vector-element-type src (format "~a ~:r argument" who argno) type)])
              (unless (or (not n) (= nat n))
                (source-errorf src "mismatch in ~s-argument vector lengths" who))
              (let ([rtype* (cons type rtype*)])
                (if (null? type*)
                    (values nat (reverse rtype*))
                    (loop type* nat (fx+ argno 1) rtype*)))))))
      (define (maybe-bind src result-type expr k)
        (nanopass-case (Ltypes Expression) expr
          [(quote ,src ,datum) (k expr)]
          [(var-ref ,src ,var-name) (k expr)]
          [else (let ([t (make-temp-id src 't)])
                  (with-output-language (Ltypes Expression)
                    `(let* ,src ([(,t ,result-type) ,expr])
                       ,(k `(var-ref ,src ,t)))))]))
      (define (arithmetic-binop src op expr1 expr2 k)
        (let*-values ([(expr1 type1) (Care expr1)] [(expr2 type2) (Care expr2)])
          (define (condense type l/r)
            (nanopass-case (Ltypes Type) type
              [(talias ,src ,nominal? ,type-name ,type)
               (let-values ([(type-name* nat) (condense type l/r)])
                 (values
                   (if nominal? (cons type-name type-name*) type-name*)
                   nat))]
              [(tfield ,src1) (values '() #f)]
              [(tunsigned ,src ,nat) (values '() nat)]
              [else (source-errorf src "~a requires its ~a operand to be a Field or Uint; the actual type is ~a"
                                   op
                                   l/r
                                   (format-type type))]))
          (let-values ([(type-name1* nat1) (condense type1 "left")]
                       [(type-name2* nat2) (condense type2 "right")])
            (let-values ([(result-expr result-type)
                          (if (and nat1 nat2)
                              (let ([result-nat (case op
                                                  [+ (+ nat1 nat2)]
                                                  [* (* nat1 nat2)]
                                                  [- nat1]
                                                  [else (assert cannot-happen)])])
                                (unless (<= result-nat (max-unsigned))
                                  (source-errorf src "resulting value might exceed largest representable Uint value (for Field semantics, cast either operand to Field)"))
                                (let ([mbits (max 1 (integer-length result-nat))])
                                  (assert (<= mbits (unsigned-bits)))
                                  (let ([result-type (with-output-language (Ltypes Type) `(tunsigned ,src ,result-nat))])
                                    (define (maybe-cast nat^ type^ expr)
                                      (if (= nat^ result-nat)
                                          expr
                                          (with-output-language (Ltypes Expression)
                                            `(safe-cast ,src ,result-type ,type^ ,expr))))
                                    (values
                                      (with-output-language (Ltypes Expression)
                                        (if (eq? op '-)
                                            (maybe-bind src type1 expr1
                                              (lambda (expr1)
                                                (maybe-bind src type2 expr2
                                                  (lambda (expr2)
                                                    `(seq ,src
                                                       (assert ,src
                                                               ,(let-values ([(type nat) (if (< nat1 nat2) (values type2 nat2) (values type1 nat1))])
                                                                  (let ([mbits (fxmax 1 (integer-length nat))])
                                                                    (with-output-language (Ltypes Expression)
                                                                      `(>= ,src ,mbits ,(maybe-safecast src type type1 expr1) ,(maybe-safecast src type type2 expr2)))))
                                                               "result of subtraction would be negative")
                                                       ,(k mbits
                                                           (maybe-cast nat1 type1 expr1)
                                                           (maybe-cast nat2 type2 expr2)))))))
                                            (k mbits
                                               (maybe-cast nat1 type1 expr1)
                                               (maybe-cast nat2 type2 expr2))))
                                      result-type))))
                              (let ([result-type (with-output-language (Ltypes Type) `(tfield ,src))])
                                (values
                                  (k #f
                                     (maybe-safecast src result-type type1 expr1)
                                     (maybe-safecast src result-type type2 expr2))
                                  result-type)))])
              (if (and (null? type-name1*) (null? type-name2*))
                  (values result-expr result-type)
                  (begin
                    ; this is, in effect, (sametype? type1 type2)
                    (unless (and (equal? type-name1* type-name2*) (eqv? nat1 nat2))
                      (source-errorf src "incompatible combination of types ~a and ~a for binary arithmetic operator ~s"
                                     (format-type type1)
                                     (format-type type2)
                                     op))
                    ; from here, type1 = type2, nat1 = nat2
                    (values
                      (with-output-language (Ltypes Expression)
                        (if nat1
                            (if (eq? op '-) result-expr `(downcast-unsigned ,src ,nat1 ,result-expr))
                            `(safe-cast ,src ,type1 ,result-type ,result-expr)))
                      type1)))))))
      (define (relational-operator src expr1 expr2 k)
        (values
          (let*-values ([(expr1 type1) (Care expr1)] [(expr2 type2) (Care expr2)])
            (or (let f ([type1 type1] [type2 type2])
                  (T (de-alias type1 #f)
                     [(tunsigned ,src1 ,nat1)
                      (T (de-alias type2 #f)
                         [(tunsigned ,src2 ,nat2)
                          (let-values ([(type nat) (if (< nat1 nat2) (values type2 nat2) (values type1 nat1))])
                            (let ([mbits (fxmax 1 (integer-length nat))])
                              (k mbits (maybe-safecast src type type1 expr1) (maybe-safecast src type type2 expr2))))])]
                     [(talias ,src1 ,nominal1? ,type-name1 ,type1)
                      (T (de-alias type2 #f)
                         [(talias ,src2 ,nominal2? ,type-name2 ,type2)
                          (and (eq? type-name1 type-name2)
                               (f type1 type2))])]))
                (source-errorf src "incompatible combination of types ~a and ~a for relational operator"
                               (format-type type1)
                               (format-type type2))))
          (with-output-language (Ltypes Type) `(tboolean ,src))))
      (define (equality-operator src expr1 expr2 k)
        (let*-values ([(expr1 type1) (Care expr1)] [(expr2 type2) (Care expr2)])
          (verify-non-adt-type! src type1 "equality-operator left operand")
          (verify-non-adt-type! src type2 "equality-operator right operand")
          (let ([type (cond
                        [(subtype? type1 type2) type2]
                        [(subtype? type2 type1) type1]
                        [else #f])])
            (unless type
              (source-errorf src "incompatible types ~a and ~a for equality operator"
                             (format-type type1)
                             (format-type type2)))
            (values
              (k type (maybe-safecast src type type1 expr1) (maybe-safecast src type type2 expr2))
              (with-output-language (Ltypes Type) `(tboolean ,src))))))
      (define (find-adt-op src elt-name sugar? adt-name adt-op* type* expr expr* fail)
        (let ([elt-name (cond
                          [(hashtable-ref ledger-op-aliases elt-name #f) =>
                           (lambda (new-elt-name)
                             (record-alias! src elt-name new-elt-name)
                             new-elt-name)]
                          [else elt-name])])
          (let loop ([adt-op* adt-op*])
            (if (null? adt-op*)
                (fail)
                (nanopass-case (Ltypes ADT-Op) (car adt-op*)
                  [(,ledger-op ,op-class ((,var-name* ,type^* ,discloses?*) ...) ,type ,vm-code)
                   (if (eq? ledger-op elt-name)
                       (begin
                         (let ([ndeclared (length type^*)] [nactual (length type*)])
                           (unless (fx= nactual ndeclared)
                             (source-errorf src "~s ~s requires ~s argument~:*~p but received ~s"
                                            adt-name ledger-op ndeclared nactual)))
                         (for-each
                           (lambda (declared-type actual-type i)
                             (unless (subtype? actual-type declared-type)
                               (if sugar?
                                   (source-errorf src "expected right-hand side of ~a to have type ~a but received ~a"
                                                  sugar?
                                                  (format-type declared-type)
                                                  (format-type actual-type))
                                   (source-errorf src "expected ~:r argument of ~s to have type ~a but received ~a"
                                                  (fx1+ i)
                                                  ledger-op
                                                  (format-type declared-type)
                                                  (format-type actual-type)))))
                           type^* type* (enumerate type^*))
                         (values
                           (let ([expr* (map (maybe-safecast src) type^* type* expr*)])
                             (with-output-language (Ltypes Expression)
                               `(ledger-call ,src ,elt-name ,sugar? ,expr ,expr* ...)))
                           type))
                       (loop (cdr adt-op*)))])))))
      (define (adt-op-error! src elt-name sugar? adt-name adt-rt-op* adt-arg*)
        (for-each
          (lambda (adt-rt-op)
            (nanopass-case (Ltypes ADT-Runtime-Op) adt-rt-op
              [(,ledger-op (,arg* ...) ,result-type ,runtime-code)
               (when (eq? ledger-op elt-name)
                 (source-errorf src "~s ~s is a runtime-only method, but was invoked in-circuit"
                                adt-name ledger-op))]))
          adt-rt-op*)
        (source-errorf src "operation ~a undefined for ledger field type ~a"
                       (or sugar? elt-name)
                       (format-public-adt adt-name adt-arg*)))
      (define (find-adt-op! src elt-name sugar? adt-name adt-op* adt-rt-op* type* expr expr* adt-arg*)
        (find-adt-op src elt-name sugar? adt-name adt-op* type* expr expr*
          (lambda ()
            (adt-op-error! src elt-name sugar? adt-name adt-rt-op* adt-arg*))))
      (define (find-contract-circuit src src^ contract-name elt-name elt-name* declared-type** return-type* actual-type actual-type* expr expr*)
        (let loop ([elt-name* elt-name*] [declared-type** declared-type**] [return-type* return-type*])
          (if (null? elt-name*)
              (source-errorf src^ "contract ~s has no circuit declaration named ~s"
                             contract-name
                             elt-name)
            (if (eq? (car elt-name*) elt-name)
                (let ([declared-type* (car declared-type**)])
                  (let ([ndeclared (length declared-type*)] [nactual (length actual-type*)])
                    (unless (fx= nactual ndeclared)
                      (source-errorf src "~s.~s requires ~s argument~:*~p but received ~s"
                                     contract-name elt-name ndeclared nactual)))
                  (for-each
                    (lambda (declared-type actual-type i)
                      (unless (subtype? actual-type declared-type)
                        (source-errorf src "expected ~:r argument of ~s.~s to have type ~a but received ~a"
                                       (fx1+ i)
                                       contract-name
                                       elt-name
                                       (format-type declared-type)
                                       (format-type actual-type))))
                    declared-type* actual-type* (enumerate declared-type*))
                  (values
                    (let ([expr* (map (maybe-safecast src) declared-type* actual-type* expr*)])
                      (with-output-language (Ltypes Expression)
                        `(contract-call ,src ,elt-name (,expr ,actual-type) ,expr* ...)))
                    (car return-type*)))
                (loop (cdr elt-name*) (cdr declared-type**) (cdr return-type*))))))
      (define (get-contract-name ecdecl)
        (nanopass-case (Lexpanded External-Contract-Declaration) ecdecl
          [(external-contract ,src ,contract-name ,ecdecl-circuit* ...)
           contract-name])))
    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) (,unused-pelt* ...) (,ecdecl* ...) ,pelt* ...)
       (for-each Set-Program-Element-Type! unused-pelt*)
       (for-each Set-Program-Element-Type! pelt*)
       (for-each External-Contract-Declaration! ecdecl*)
       (maplr Program-Element unused-pelt*)
       (let ([contract-name* (map get-contract-name ecdecl*)])
         `(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,(maplr Program-Element pelt*) ...))])
    (Set-Program-Element-Type! : Program-Element (ir) -> * (void)
      (definitions
        (define (build-function kind name arg* type)
          (let ([var-name* (map arg->name arg*)] [type* (map arg->type arg*)])
            (set-idtype! name (Idtype-Function kind var-name* type* type)))))
      [(circuit ,src ,function-name (,[arg*] ...) ,[Return-Type : type src "circuit" -> type] ,expr)
       (build-function 'circuit function-name arg* type)]
      [(external ,src ,function-name ,native-entry (,[arg*] ...) ,[Return-Type : type src "circuit" -> type])
       (define param-ht (make-hashtable symbol-hash eq?))
       (define failed-unification #f)
       (define (format-native-nat native-nat)
         (native-nat-case native-nat
           [(native-nat-value n) (format "~d" n)]
           [(native-nat-param name) (format "~a" name)]))
       (define (format-native-type native-type)
         (native-type-case native-type
           [(native-type-boolean) "Boolean"]
           [(native-type-field) "Field"]
           [(native-type-unsigned native-nat) (format "Uint<~a>" (format-native-nat native-nat))]
           [(native-type-bytes native-nat) (format "Bytes<~a>" (format-native-nat native-nat))]
           [(native-type-vector native-nat native-type)
            (format "Vector<~a, ~a>" (format-native-nat native-nat) (format-native-type native-type))]
           [(native-type-struct native-type*)
            (format "Struct<~{~a~^, ~}>" (map format-native-type native-type*))]
           [(native-type-alias name) (format "~a" name)]
           ; this can be tested by uncommenting the justfortesting in test.ss and midnight-natives.ss
           [(native-type-param name) (format "~a" name)]
           [(native-type-void) "[]"]))
       (define (verify-native-nat native-nat nat p2?)
         (native-nat-case native-nat
           [(native-nat-value n) (= (if p2? (sub1 (expt 2 n)) n) nat)]
           [(native-nat-param name)
            (let ([a (hashtable-cell param-ht name #f)])
              (if (cdr a)
                  (or (= (cdr a) nat)
                      (begin
                        (set! failed-unification (format "~a previously matched to ~a" name (cdr a)))
                        #f))
                  (begin
                    (set-cdr! a nat)
                    #t)))]))
       (define (verify-native-type native-type type)
         (let ([type (de-alias type #f)])
           (native-type-case native-type
             [(native-type-boolean)
              (nanopass-case (Ltypes Type) type
                [(tboolean ,src) #t]
                [else #f])]
             [(native-type-field)
              (nanopass-case (Ltypes Type) type
                [(tfield ,src) #t]
                [else #f])]
             [(native-type-unsigned native-nat)
              (nanopass-case (Ltypes Type) type
                [(tunsigned ,src ,nat) (verify-native-nat native-nat nat #t)]
                [else #f])]
             [(native-type-bytes native-nat)
              (nanopass-case (Ltypes Type) type
                [(tbytes ,src ,len)
                 (verify-native-nat native-nat len #f)]
                [else #f])]
             [(native-type-vector native-nat native-type)
              (nanopass-case (Ltypes Type) type
                [(tvector ,src ,len ,type)
                 (and (verify-native-nat native-nat len #f)
                      (verify-native-type native-type type))]
                [else #f])]
             [(native-type-struct native-type*)
              (nanopass-case (Ltypes Type) type
                [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
                 (and (= (length type*) (length native-type*))
                      (andmap verify-native-type native-type* type*))]
                [else #f])]
             [(native-type-alias name)
              (nanopass-case (Ltypes Type) type
                [(talias ,src^ ,nominal? ,type-name ,type) (eq? type-name name)]
                [else #f])]
             [(native-type-param name)
              (let ([a (hashtable-cell param-ht name #f)])
                (if (cdr a)
                    (or (sametype? type (cdr a))
                        (begin
                          (set! failed-unification (format "~a previously matched to ~a" name (format-type (cdr a))))
                          #f))
                    (begin
                      (set-cdr! a type)
                      #t)))]
             [(native-type-void)
              (nanopass-case (Ltypes Type) type
                [(ttuple ,src) #t]
                [else #f])])))
       (for-each
         (lambda (native-type type argno)
           (unless (verify-native-type native-type type)
             (source-errorf src "mismatch between declared type ~a and expected type ~a for ~:r argument of native ~s~@[ (~a)~]"
                            (format-type type)
                            (format-native-type native-type)
                            (fx+ argno 1)
                            (id-sym function-name)
                            failed-unification)))
         (native-entry-argument-types native-entry)
         (map arg->type arg*)
         (enumerate arg*))
       (let ([native-type (native-entry-result-type native-entry)])
         (unless (verify-native-type native-type type)
           (source-errorf src "mismatch between declared type ~a and expected type ~a for return value of native ~a~@[ (~a)~]"
                          (format-type type)
                          (format-native-type native-type)
                          (id-sym function-name)
                          failed-unification)))
       (build-function 'circuit function-name arg* type)]
      [(witness ,src ,function-name (,[arg*] ...) ,[Return-Type : type src "witness" -> type])
       (when (contains-contract? type)
         (source-errorf src "invalid type ~a for witness ~a return value:\n  witness return values cannot include contract values"
                        (format-type type)
                        (id-sym function-name)))
       (build-function 'witness function-name arg* type)]
      [(public-ledger-declaration ,src ,ledger-field-name ,[type])
       (unless (public-adt? type)
         (source-errorf src "expected ADT-type for ledger declaration after expand-modules-and-types, received ~a"
                            (format-type type)))
       (set-idtype! ledger-field-name (Idtype-Base type))]
      [else (void)])
    (External-Contract-Declaration! : External-Contract-Declaration (ir) -> * (void)
      [(external-contract ,src ,contract-name ,ecdecl-circuit* ...)
       (let ([check-circuit (check-contract src contract-name)])
         (for-each
           (lambda (ecdecl-circuit)
             (External-Contract-Circuit! ecdecl-circuit check-circuit))
           ecdecl-circuit*))])
    (External-Contract-Circuit! : External-Contract-Circuit (ir check-circuit) -> * (void)
      [(,src ,pure-dcl ,elt-name (,[arg*] ...) ,type)
       (let ([type (Non-ADT-Type type src "circuit ~a return" elt-name)])
         (check-circuit src elt-name pure-dcl (map arg->type arg*) type))])
    (Program-Element : Program-Element (ir) -> Program-Element ())
    (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
      [(constructor ,src (,[arg*] ...) ,expr)
       (let-values ([(expr return-type) (do-circuit-body src "ledger constructor" arg* (with-output-language (Ltypes Type) `(ttuple ,src)) expr)])
         `(constructor ,src (,arg* ...) ,expr))])
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,function-name (,[arg*] ...) ,[Return-Type : type src "circuit" -> type] ,expr)
       (when (id-exported? function-name)
         (when (contains-contract? type)
           (source-errorf src "invalid type ~a for circuit ~a return value:\n  exported circuit return values cannot include contract values"
                          (format-type type)
                          (id-sym function-name)))
         (for-each
           (lambda (type argno)
             (when (contains-contract? type)
               (source-errorf src "invalid type ~a for circuit ~a argument ~d:\n  exported circuit arguments cannot include contract values"
                              (format-type type)
                              (id-sym function-name)
                              (fx1+ argno))))
           (map arg->type arg*)
           (enumerate arg*)))
       (let-values ([(expr return-type) (do-circuit-body src (format "circuit ~a" (id-sym function-name)) arg* type expr)])
         `(circuit ,src ,function-name (,arg* ...) ,return-type ,expr))])
    (External-Declaration : External-Declaration (ir) -> External-Declaration ()
      [(external ,src ,function-name ,native-entry (,[arg*] ...) ,[Return-Type : type src "circuit" -> type])
       `(external ,src ,function-name ,native-entry (,arg* ...) ,type)])
    (Witness-Declaration : Witness-Declaration (ir) -> Witness-Declaration ()
      [(witness ,src ,function-name (,[arg*] ...) ,[Return-Type : type src "witness" -> type])
       `(witness ,src ,function-name (,arg* ...) ,type)])
    (Export-Type-Definition :  Export-Type-Definition (ir) -> Export-Type-Definition ()
      [(export-typedef ,src ,type-name (,tvar-name* ...) ,[type])
       (if (public-adt? type)
           (source-errorf src "cannot export alias for ADT types from the top level")
           `(export-typedef ,src ,type-name (,tvar-name* ...) ,type))])
    (ADT-Op : ADT-Op (ir) -> ADT-Op ())
    (ADT-Op-Class : ADT-Op-Class (ir) -> ADT-Op-Class ())
    (Argument : Argument (ir) -> Argument ()
      [(,var-name ,type)
       (let ([type (Non-ADT-Type type (id-src var-name) "argument '~a'" (id-sym var-name))])
         `(,var-name ,type))])
    (Return-Type : Type (ir src what) -> Type ()
      [else (Non-ADT-Type ir src "~a return" what)])
    (Generic-Value : Generic-Value (ir) -> Public-Ledger-ADT-Arg ())
    (Type : Type (ir) -> Type ()
      [(tboolean ,src) `(tboolean ,src)]
      [(tfield ,src) `(tfield ,src)]
      [(tunsigned ,src ,nat) `(tunsigned ,src ,nat)]
      [(topaque ,src ,opaque-type) `(topaque ,src ,opaque-type)]
      [(tundeclared) `(tundeclared)]
      [(tvector ,src ,len ,type)
       (let ([type (Non-ADT-Type type src "vector element")])
         `(tvector ,src ,len ,type))]
      [(tbytes ,src ,len)
       `(tbytes ,src ,len)]
      [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
       (let ([type** (map (lambda (type* elt-name)
                            (map (lambda (type i)
                                   (Non-ADT-Type type src "circuit '~a' argument ~d" elt-name (fx+ i 1)))
                                 type*
                                 (enumerate type*)))
                          type**
                          elt-name*)]
             [type* (map (lambda (type elt-name) (Non-ADT-Type type src "circuit '~a' return" elt-name))
                         type*
                         elt-name*)])
         `(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...))]
      [(ttuple ,src ,type* ...)
       (let ([type* (map (lambda (type i)
                           (Non-ADT-Type type src "tuple element ~d" (fx+ i 1)))
                         type*
                         (enumerate type*))])
         `(ttuple ,src ,type* ...))]
      [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
       (let ([type* (map (lambda (type elt-name)
                           (Non-ADT-Type type src "struct field '~a'" elt-name))
                         type*
                         elt-name*)])
         `(tstruct ,src ,struct-name (,elt-name* ,type*) ...))]
      [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
       `(tenum ,src ,enum-name ,elt-name ,elt-name* ...)]
      [(talias ,src ,nominal? ,type-name ,[type])
       `(talias ,src ,nominal? ,type-name ,type)]
      [(tadt ,src ,adt-name ([,adt-formal* ,generic-value*] ...) ,vm-expr (,[adt-op*] ...) (,[adt-rt-op*] ...))
       (when (or (eq? adt-name 'MerkleTree) (eq? adt-name 'HistoricMerkleTree))
         (let ([depth (car generic-value*)])
           (unless (<= (min-merkle-tree-depth) depth (max-merkle-tree-depth))
             (source-errorf src "~a depth ~d does not fall in ~d <= depth <= ~d"
                            adt-name
                            depth
                            (min-merkle-tree-depth)
                            (max-merkle-tree-depth)))))
       `(tadt ,src ,adt-name ([,adt-formal* ,(map Generic-Value generic-value*)] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))])
    (CareNot : Expression (ir) -> Expression ()
      [(if ,src ,[Care : expr0 type0] ,expr1 ,expr2)
       (unless (nanopass-case (Ltypes Type) (de-alias type0 #t)
                 [(tboolean ,src1) #t]
                 [else #f])
         (source-errorf src "expected test to have type Boolean, received ~a"
                        (format-type type0)))
       (let ([expr1 (CareNot expr1)] [expr2 (CareNot expr2)])
         `(if ,src ,expr0 ,expr1 ,expr2))]
      [(seq ,src ,expr* ... ,expr)
       (let* ([expr* (maplr CareNot expr*)] [expr (CareNot expr)])
         `(seq ,src ,expr* ... ,expr))]
      [(let* ,src ([(,var-name* ,[type*]) ,expr*] ...) ,expr)
       (let ([declared-type* type*])
         (let-values ([(expr* actual-type*) (maplr2 Care expr*)])
           (let ([declared-type* (maplr (lambda (var-name declared-type actual-type)
                                          (unless (subtype? actual-type declared-type)
                                            (source-errorf src "mismatch between actual type ~a and declared type ~a of const binding"
                                                           (format-type actual-type)
                                                           (format-type declared-type)))
                                          (let ([type (if (declared? declared-type)
                                                          declared-type
                                                          actual-type)])
                                            (set-idtype! var-name (Idtype-Base type))
                                            type))
                                        var-name*
                                        declared-type*
                                        actual-type*)])
             (let ([expr (CareNot expr)])
               (for-each unset-idtype! var-name*)
               `(let* ,src ([(,var-name* ,declared-type*)
                             ,(map (maybe-safecast src) declared-type* actual-type* expr*)]
                            ...)
                  ,expr)))))]
      [else (let-values ([(expr type) (Care ir)]) expr)])
    (elt-call-lhs : Expression (ir src op adt-type-only?) -> Expression (type)
      (definitions
        (define (elt-call-oops src type)
          (source-errorf src (if adt-type-only?
                                 "expected left-hand side of ~a to have an ADT type, received ~a"
                                 "expected left-hand side of ~a to have an ADT or contract type, received ~a")
                         op
                         (format-type type)))
        (define (check-result-type src expr type)
          (nanopass-case (Ltypes Type) (de-alias type #t)
            [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
             (source-errorf src "expected a ledger field name at base of ledger access")]
            [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
             (guard (not adt-type-only?))
             (values expr type)]
            [else (elt-call-oops src type)])))
      [(var-ref ,src ,var-name)
       (Idtype-case (get-idtype src var-name)
         [(Idtype-Base type) (check-result-type src `(var-ref ,src ,var-name) type)]
         [(Idtype-Function kind arg-name* arg-type* return-type)
          ; can't happen if expand-modules-and-types is doing its job
          (source-errorf src "invalid context for reference to ~s name ~s"
                         kind
                         (id-sym var-name))])]
      [(ledger-ref ,src ,ledger-field-name)
       (values
         `(ledger-ref ,src ,ledger-field-name)
         (Idtype-case (get-idtype src ledger-field-name)
           [(Idtype-Base type) type]
           [(Idtype-Function kind arg-name* arg-type* return-type)
            ; can't happen if expand-modules-and-types is doing its job
            (source-errorf src "invalid context for reference to ~s name ~s"
                           kind
                           (id-sym ledger-field-name))]))]
      [(elt-call ,src ,[elt-call-lhs : expr src "." #f -> expr type] ,elt-name ,[Care : expr* type*] ...)
       (let ([actual-type type] [actual-type* type*])
         (define (handle-contract expr actual-type err)
           (nanopass-case (Ltypes Type) (de-alias actual-type #t)
             [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
              (guard (not adt-type-only?))
              (find-contract-circuit src src^ contract-name elt-name elt-name* type** type* actual-type actual-type* expr expr*)]
             [else (err)]))
         (nanopass-case (Ltypes Type) (de-alias actual-type #t)
           [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
            (find-adt-op src elt-name #f adt-name adt-op* actual-type* expr expr*
              (lambda ()
                (let-values ([(expr actual-type) (find-adt-op src 'read #f adt-name adt-op* '() expr '()
                                                   (lambda () (adt-op-error! src elt-name #f adt-name adt-rt-op* adt-arg*)))])
                  (handle-contract expr actual-type (lambda () (adt-op-error! src elt-name #f adt-name adt-rt-op* adt-arg*))))))]
           [else (handle-contract expr actual-type (lambda () (elt-call-oops src actual-type)))]))]
      [else (let-values ([(expr type) (Care ir)])
              (check-result-type src expr type))])
    (Care : Expression (ir) -> Expression (type)
      (definitions
        (define (desugar-ledger-read src expr type)
          (nanopass-case (Ltypes Type) (de-alias type #t)
            [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
             (find-adt-op src 'read #f adt-name adt-op* '() expr '()
               (lambda ()
                 (source-errorf src "incomplete chain of ledger indirects: final result must be a regular type, but received ADT type ~a"
                                (format-type type))))]
            [else (values expr type)]))
        )
      [(quote ,src ,datum)
       (values
         `(quote ,src ,datum)
         (with-output-language (Ltypes Type)
           (cond
             [(boolean? datum) `(tboolean ,src)]
             [(field? datum)
              (if (<= datum (max-unsigned))
                  `(tunsigned ,src ,datum)
                  (source-errorf src "constant ~d is larger than the largest representable Uint; use\
                                 \n    ~:*~d as Field\
                                 \n  to treat as a value of type Field"
                                 datum))]
             [(bytevector? datum)
              ; no need to check len? for the generated tbytes.  this is already caught in
              ; the parser
              `(tbytes ,src ,(bytevector-length datum))]
             [else (assert cannot-happen)])))]
      [(var-ref ,src ,var-name)
       (values
         `(var-ref ,src ,var-name)
         (Idtype-case (get-idtype src var-name)
           [(Idtype-Base type) type]
           [(Idtype-Function kind arg-name* arg-type* return-type)
            ; can't happen if expand-modules-and-types is doing its job
            (source-errorf src "invalid context for reference to ~s name ~s"
                           kind
                           (id-sym var-name))]))]
      [(ledger-ref ,src ,ledger-field-name)
       (desugar-ledger-read src
         `(ledger-ref ,src ,ledger-field-name)
         (Idtype-case (get-idtype src ledger-field-name)
           [(Idtype-Base type) type]
           [(Idtype-Function kind arg-name* arg-type* return-type)
            ; can't happen if expand-modules-and-types is doing its job
            (source-errorf src "invalid context for reference to ~s name ~s"
                           kind
                           (id-sym ledger-field-name))]))]
      [(default ,src ,[type])
       (nanopass-case (Ltypes Type) (de-alias type #t)
         [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
          (source-errorf src "default is not defined for contract types")]
         [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
          (guard (eq? adt-name 'Kernel))
          (source-errorf src "default is not defined for ADT type Kernel")]
         [else (values `(default ,src ,type) type)])]
      [(if ,src ,[Care : expr0 type0] ,expr1 ,expr2)
       (unless (nanopass-case (Ltypes Type) (de-alias type0 #t)
                 [(tboolean ,src1) #t]
                 [else #f])
         (source-errorf src "expected test to have type Boolean, received ~a"
                        (format-type type0)))
       (let-values ([(expr1 type1) (Care expr1)] [(expr2 type2) (Care expr2)])
         (let ([type (cond
                       [(subtype? type1 type2) type2]
                       [(subtype? type2 type1) type1]
                       [else (source-errorf src "mismatch between type ~a and type ~a of condition branches"
                                            (format-type type1)
                                            (format-type type2))])])
           (values
             `(if ,src
                  ,expr0
                  ,(maybe-safecast src type type1 expr1)
                  ,(maybe-safecast src type type2 expr2))
             type)))]
      [(elt-ref ,src ,[Care : expr type] ,elt-name)
       (nanopass-case (Ltypes Type) (de-alias type #t)
         [(tstruct ,src1 ,struct-name (,elt-name* ,type*) ...)
          (let ([elt-name (cond
                            [(and (stdlib-src? src1)
                                  (assp (lambda (x) (and (eq? (car x) struct-name) (eq? (cdr x) elt-name)))
                                        stdlib-struct-field-aliases)) =>
                             (lambda (a)
                               (let ([new-elt-name (cdr a)])
                                 (record-alias! src elt-name new-elt-name)
                                 new-elt-name))]
                            [else elt-name])])
            (let loop ([elt-name* elt-name*] [type* type*] [i 0])
              (if (null? elt-name*)
                  (source-errorf src "structure ~s has no field named ~s"
                                 struct-name
                                 elt-name)
                  (if (eq? (car elt-name*) elt-name)
                      (values
                        `(elt-ref ,src ,expr ,elt-name ,i)
                        (car type*))
                      (loop (cdr elt-name*) (cdr type*) (fx+ i 1))))))]
         [else (source-errorf src "expected structure type, received ~a"
                              (format-type type))])]
      [(elt-call ,src ,expr ,elt-name ,expr* ...)
       (let-values ([(expr type) (elt-call-lhs ir src "." #f)])
         (desugar-ledger-read src expr type))]
      [(= ,src ,[elt-call-lhs : expr1 src "=" #t -> expr1 type1] ,[Care : expr2 type2])
       (nanopass-case (Ltypes Type) (de-alias type1 #t)
         [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
          (find-adt-op! src 'write "=" adt-name adt-op* adt-rt-op* (list type2) expr1 (list expr2) adt-arg*)]
         [else (source-errorf src "expected left-hand side of = to have an ADT type, received ~a"
                              (format-type type1))])]
      [(+= ,src ,[elt-call-lhs : expr1 src "+=" #t -> expr1 type1] ,[Care : expr2 type2])
       (nanopass-case (Ltypes Type) (de-alias type1 #t)
         [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
          (find-adt-op! src 'increment "+=" adt-name adt-op* adt-rt-op* (list type2) expr1 (list expr2) adt-arg*)]
         [else (source-errorf src "expected left-hand side of += to have an ADT type, received ~a"
                              (format-type type1))])]
      [(-= ,src ,[elt-call-lhs : expr1 src "-=" #t -> expr1 type1] ,[Care : expr2 type2])
       (nanopass-case (Ltypes Type) (de-alias type1 #t)
         [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
          (find-adt-op! src 'decrement "-=" adt-name adt-op* adt-rt-op* (list type2) expr1 (list expr2) adt-arg*)]
         [else (source-errorf src "expected left-hand side of -= to have an ADT type, received ~a"
                              (format-type type1))])]
      [(enum-ref ,src ,[type] ,elt-name^)
       (nanopass-case (Ltypes Type) (de-alias type #t)
         [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
          (unless (or (eq? elt-name^ elt-name) (memq elt-name^ elt-name*))
            (source-errorf src "enum ~s has no field named ~s"
                           enum-name
                           elt-name^))
          (values
            `(enum-ref ,src ,type ,elt-name^)
            type)]
         [else
          ; can't presently happen: we never construct an enum-ref unless we have an enum type
          (source-errorf src "expected enum type, received ~a"
                         (format-type type))])]
      [(tuple ,src ,[Tuple-Argument : tuple-arg* -> expr* type* kind* nat* elt-type**] ...)
       (define (unrelated-elt-types elt-type+)
         (let ([type (car elt-type+)])
           (let loop ([type* (cdr elt-type+)])
             (let ([type^ (car type*)])
               (unless (or (subtype? type^ type) (subtype? type type^))
                 (source-errorf src "tuple/vector construction expression with vector-typed spreads has unrelated element types ~a and ~a"
                                (format-type type) (format-type type^)))
               (loop (cdr type*))))))
       (if (memq 'vector-spread kind*)
           ; when a tuple expression contains a spread of a vector-typed value, the resulting value is a vector
           ; and must have a vector type, so the type of each non-spread element and the element type of each tuple or
           ; vector element must be liftable to a common element type. if we someday extend the tuple type to incorporate
           ; both single and spread elements, e.g., (ttuple (single Field) (spread 3 Boolean)), we can lift this
           ; restriction; though then it would also be incumbent upon us to add a source-level syntax for such types.
           ; one way to look at such types is as a compressed representation of a tuple type.  for example, the
           ; the tuple type above could also be written as (tuple Field Boolean Boolean Boolean).  compression is
           ; useful, if not critical, when spreading longer vectors: (ttuple (single Field) (spread 1000000 Boolean))
           ; would be rather large if uncompressed.
           (let ([elt-type (let ([elt-type* (apply append elt-type**)])
                             (or (max-type elt-type*) (unrelated-elt-types elt-type*)))])
             (define (make-vector-type len)
               (unless (len? len)
                 (source-errorf src "the size of tuple/vector construction expression with vector-typed spread\n    ~d\n  exceeds the maximum vector size allowed\n    ~d"
                                len
                                (max-bytes/vector-length)))
               (with-output-language (Ltypes Type)
                 `(tvector ,src ,len ,elt-type)))
             (values
               `(vector ,src ,(map (lambda (kind nat expr type)
                                     (if (eq? kind 'single)
                                         `(single ,src ,(maybe-safecast src elt-type type expr))
                                         `(spread ,src ,nat ,(maybe-safecast src (make-vector-type nat) type expr))))
                                   kind* nat* expr* type*)
                        ...)
               (make-vector-type (apply + nat*))))
           ; if a tuple contains only non-spread elements and spreads of tuple-typed values, the resulting value
           ; is a tuple and can have any mix of element types.
           (let* ([elt-type* (apply append elt-type**)]
                  [len (length elt-type*)])
             (unless (len? len)
               (source-errorf src "the size of tuple/vector construction expression with tuple-typed spread\n    ~d\n  exceeds the maximum tuple size allowed\n    ~d"
                              len
                              (max-bytes/vector-length)))
             (values
               `(tuple ,src ,(map (lambda (kind nat expr)
                                    (if (eq? kind 'single)
                                        `(single ,src ,expr)
                                        `(spread ,src ,nat ,expr)))
                                  kind* nat* expr*)
                       ...)
               (with-output-language (Ltypes Type)
                 `(ttuple ,src ,elt-type* ...)))))]
      [(bytes ,src ,[Bytes-Argument : tuple-arg* nat*] ...)
       (let ([len-total (apply + nat*)])
         (unless (len? len-total)
           (source-errorf src "Bytes construction length\n    ~d exceeds the maximum bytes length allowed\n    ~d"
                          len-total
                          (max-bytes/vector-length)))
         (values
           `(vector->bytes ,src ,len-total
              (vector ,src ,tuple-arg* ...))
           (with-output-language (Ltypes Type)
             `(tbytes ,src ,len-total))))]
      [(tuple-ref ,src ,[Care : expr expr-type] ,[Care : index index-type])
       (nanopass-case (Ltypes Type) (de-alias index-type #t)
         [(tunsigned ,src^ ,nat) nat]
         [else (source-errorf src "expected index to have an unsigned type, received ~a"
                              (format-type index-type))])
       (cond
         [(let f ([index index])
            (nanopass-case (Ltypes Expression) index
              [(quote ,src ,datum)
               (unless (kindex? datum)
                 (source-errorf src "index ~d exceeds maximum allowed index ~d for a tuple or vector reference"
                                datum
                                (- (max-bytes/vector-length) 1)))
               datum]
              [(safe-cast ,src ,type ,type^ ,index) (f index)]
              [else #f])) =>
          (lambda (kindex)
            (define (bounds-check what len)
              (unless (< kindex len)
                (source-errorf src "index ~d is out-of-bounds for a ~a of length ~d"
                               kindex what len)))
            (nanopass-case (Ltypes Type) (de-alias expr-type #t)
              [(tbytes ,src ,len)
               (bounds-check "Bytes value" len)
               (values
                 `(bytes-ref ,src ,expr-type ,expr (quote ,src ,kindex))
                 (with-output-language (Ltypes Type) `(tunsigned ,src 255)))]
              [(ttuple ,src^ ,type* ...)
               (bounds-check "tuple" (length type*))
               (values
                 `(tuple-ref ,src ,expr ,kindex)
                 (list-ref type* kindex))]
              [(tvector ,src^ ,len^ ,type^)
               (bounds-check "vector" len^)
               (values
                 `(tuple-ref ,src ,expr ,kindex)
                 type^)]
              [else (source-errorf src "expected a tuple, Vector, or Bytes type, received ~a"
                                   (format-type expr-type))]))]
         [else
          (let ()
            (define (zero-check len)
              (unless (> len 0)
                (source-errorf src "expected a non-empty tuple, vector, or Bytes type, received ~a"
                               (format-type expr-type))))
            (nanopass-case (Ltypes Type) (de-alias expr-type #t)
              [(tbytes ,src^ ,len)
               (zero-check len)
               (values
                 `(bytes-ref ,src ,expr-type ,expr ,index)
                 (with-output-language (Ltypes Type) `(tunsigned ,src 255)))]
              [else
               (let-values ([(len^ elt-type) (vector-element-type src "tuple reference with a non-constant index" expr-type)])
                 (zero-check len^)
                 (let* ([vector-type (with-output-language (Ltypes Type) `(tvector ,src ,len^ ,elt-type))]
                        [expr (maybe-safecast src vector-type expr-type expr)])
                   (values
                     `(vector-ref ,src ,vector-type ,expr ,index)
                     elt-type)))]))])]
      [(tuple-slice ,src ,[Care : expr expr-type] ,[Care : index index-type] ,len)
       (nanopass-case (Ltypes Type) (de-alias index-type #t)
         [(tunsigned ,src^ ,nat) nat]
         [else (source-errorf src "expected index to have an unsigned type, received ~a"
                              (format-type index-type))])
       (cond
         [(let f ([index index])
            (nanopass-case (Ltypes Expression) index
              [(quote ,src ,datum)
               (unless (kindex? datum)
                 (source-errorf src "index ~d exceeds maximum index allowed ~d for a slice"
                                datum
                                (- (max-bytes/vector-length) 1)))
               datum]
              [(safe-cast ,src ,type ,type^ ,index) (f index)]
              [else #f])) =>
          (lambda (kindex)
            (define (bounds-check what input-len)
              (unless (<= (+ kindex len) input-len)
                (source-errorf src "slice index ~d plus length ~d is out-of-bounds for a ~a of length ~d"
                               kindex len what input-len)))
            (nanopass-case (Ltypes Type) (de-alias expr-type #t)
              [(tbytes ,src ,len^)
               (bounds-check "Bytes value" len^)
               (values
                 `(bytes-slice ,src ,expr-type ,expr (quote ,src ,kindex) ,len)
                 (with-output-language (Ltypes Type)
                   `(tbytes ,src ,len)))]
              [(ttuple ,src^ ,type* ...)
               (bounds-check "tuple" (length type*))
               (values
                 `(tuple-slice ,src ,expr-type ,expr ,kindex ,len)
                 (with-output-language (Ltypes Type)
                   `(ttuple ,src ,(list-head (list-tail type* kindex) len) ...)))]
              [(tvector ,src^ ,len^ ,type^)
               (bounds-check "vector" len^)
               (values
                 `(tuple-slice ,src ,expr-type ,expr ,kindex ,len)
                 (with-output-language (Ltypes Type)
                   `(tvector ,src ,len ,type^)))]
              [else (source-errorf src "expected first slice argument to be a tuple, Vector, or Bytes type, received ~a"
                                   (format-type expr-type))]))]
         [else
          (let ()
            (define (bounds-check input-len)
              (unless (<= len input-len)
                (source-errorf src "slice length ~d exceeds the length ~d of the input tuple, vector, or Bytes value" len input-len)))
            (nanopass-case (Ltypes Type) (de-alias expr-type #t)
              [(tbytes ,src^ ,len^)
               (bounds-check len^)
               (values
                 `(bytes-slice ,src ,expr-type ,expr ,index ,len)
                 (with-output-language (Ltypes Type) `(tbytes ,src ,len)))]
              [else
               (let-values ([(input-len elt-type) (vector-element-type src "tuple slice with a non-constant index" expr-type)])
                 (bounds-check input-len)
                 (let* ([vector-type (with-output-language (Ltypes Type)
                                       ; there is no need to check (len? len^) since since if the check is violated the construction of expr-type
                                       ; would have already caught it
                                       `(tvector ,src ,input-len ,elt-type))]
                        [expr (maybe-safecast src vector-type expr-type expr)])
                   (values
                     `(vector-slice ,src ,vector-type ,expr ,index ,len)
                     (with-output-language (Ltypes Type)
                       `(tvector ,src ,len ,elt-type)))))]))])]
      [(+ ,src ,expr1 ,expr2)
       (arithmetic-binop src '+ expr1 expr2
         (lambda (mbits expr1 expr2)
           `(+ ,src ,mbits ,expr1 ,expr2)))]
      [(- ,src ,expr1 ,expr2)
       (arithmetic-binop src '- expr1 expr2
         (lambda (mbits expr1 expr2)
           `(- ,src ,mbits ,expr1 ,expr2)))]
      [(* ,src ,expr1 ,expr2)
       (arithmetic-binop src '* expr1 expr2
         (lambda (mbits expr1 expr2)
           `(* ,src ,mbits ,expr1 ,expr2)))]
      [(< ,src ,expr1 ,expr2)
       (relational-operator src expr1 expr2
         (lambda (mbits expr1 expr2)
           `(< ,src ,mbits ,expr1 ,expr2)))]
      [(<= ,src ,expr1 ,expr2)
       (relational-operator src expr1 expr2
         (lambda (mbits expr1 expr2)
           `(<= ,src ,mbits ,expr1 ,expr2)))]
      [(> ,src ,expr1 ,expr2)
       (relational-operator src expr1 expr2
         (lambda (mbits expr1 expr2)
           `(> ,src ,mbits ,expr1 ,expr2)))]
      [(>= ,src ,expr1 ,expr2)
       (relational-operator src expr1 expr2
         (lambda (mbits expr1 expr2)
           `(>= ,src ,mbits ,expr1 ,expr2)))]
      [(== ,src ,expr1 ,expr2)
       (equality-operator src expr1 expr2
         (lambda (type expr1 expr2)
           `(== ,src ,type ,expr1 ,expr2)))]
      [(!= ,src ,expr1 ,expr2)
       (equality-operator src expr1 expr2
         (lambda (type expr1 expr2)
           `(!= ,src ,type ,expr1 ,expr2)))]
      [(for ,src ,var-name ,expr1 ,expr2)
       (let-values ([(expr1 type1) (Care expr1)])
         (let-values ([(len elt-type) (vector-element-type src "for 'of' expression" type1)])
           (set-idtype! var-name (Idtype-Base elt-type))
           (let-values ([(expr2 type2) (Care expr2)])
             (unset-idtype! var-name)
             (values
               `(fold ,src ,len
                  ,(let ([t (make-temp-id src 't)])
                     (with-output-language (Ltypes Function)
                       `(circuit ,src ((,t (ttuple ,src))
                                       (,var-name ,elt-type))
                                 (ttuple ,src)
                                 (seq ,src ,expr2 (var-ref ,src ,t)))))
                  ((tuple ,src) (ttuple ,src))
                  (,expr1 ,type1 ,elt-type))
               (with-output-language (Ltypes Type)
                 `(ttuple ,src))))))]
      [(map ,src ,fun ,expr ,expr* ...)
       (let*-values ([(expr+ actual-type+) (maplr2 Care (cons expr expr*))]
                     [(len actual-elt-type+) (vector-element-types src 'map actual-type+ 2)])
         (do-call src #f fun actual-elt-type+
           (lambda (declared-type+ return-type fun)
             (values
               `(map ,src ,len ,fun
                  ; each map-arg contains
                  ; - an expression whose value should be a tuple, vector, or bytes
                  ; - the value's type, which should be a tttuple with a tvector supertype, a tvector, or a tbytes
                  ; - the type to which each element of the expression's value must be cast, i.e., the declared type of fun's corresponding parameter
                  (,(car expr+) ,(car actual-type+) ,(car declared-type+))
                  (,(cdr expr+) ,(cdr actual-type+) ,(cdr declared-type+))
                  ...)
               (with-output-language (Ltypes Type)
                 `(tvector ,src ,len ,return-type))))))]
      [(fold ,src ,fun ,expr0 ,expr ,expr* ...)
       (let*-values ([(expr0 actual-type0) (Care expr0)]
                     [(expr+ actual-type+) (maplr2 Care (cons expr expr*))]
                     [(len actual-elt-type+) (vector-element-types src 'fold actual-type+ 3)])
         (do-call src #t fun (cons actual-type0 actual-elt-type+)
           (lambda (declared-type+ return-type fun)
             (let ([declared-type0 (car declared-type+)] [declared-type+ (cdr declared-type+)])
               (let ([expr0 (maybe-safecast src declared-type0 actual-type0 expr0)])
                 (values
                   `(fold ,src ,len ,fun
                      (,expr0 ,declared-type0)
                      ; see the note about map args above
                      (,(car expr+) ,(car actual-type+) ,(car declared-type+))
                      (,(cdr expr+) ,(cdr actual-type+) ,(cdr declared-type+))
                      ...)
                   return-type))))))]
      [(call ,src ,fun ,expr* ...)
       (let-values ([(expr* actual-type*) (maplr2 Care expr*)])
         (do-call src #f fun actual-type*
           (lambda (declared-type* return-type fun)
             (values
               `(call ,src ,fun ,(map (maybe-safecast src) declared-type* actual-type* expr*) ...)
               return-type))))]
      [(new ,src ,[type] ,new-field* ...)
       (nanopass-case (Ltypes Type) (de-alias type #t)
         [(tstruct ,src1 ,struct-name (,elt-name* ,type*) ...)
          (define-record-type field
            (nongenerative)
            (fields src (mutable expr) (mutable type))
            (protocol (lambda (n) (lambda (src expr) (n src expr #f)))))
          (define-record-type spread
            (nongenerative)
            (parent field)
            (fields)
            (protocol (lambda (n) (lambda (src expr) ((n src expr))))))
          (define-record-type positional
            (nongenerative)
            (parent field)
            (fields)
            (protocol (lambda (n) (lambda (src expr) ((n src expr))))))
          (define-record-type named
            (nongenerative)
            (parent field)
            (fields elt-name)
            (protocol (lambda (n) (lambda (src elt-name expr) ((n src expr) elt-name)))))
          (define (process-field! field)
            (let-values ([(expr type) (Care (field-expr field))])
              (field-expr-set! field expr)
              (field-type-set! field type)))
          (define (s0)
            (if (null? new-field*)
                (finish #f '() '())
                (nanopass-case (Lexpanded New-Field) (car new-field*)
                  [(spread ,src^ ,expr) (snamed (cdr new-field*) (make-spread src^ expr) '() '())]
                  [else (spositional new-field* '())])))
          (define (spositional new-field* rpositional*)
            (if (null? new-field*)
                (finish #f (reverse rpositional*) '())
                (nanopass-case (Lexpanded New-Field) (car new-field*)
                  [(positional ,src^ ,expr) (spositional (cdr new-field*) (cons (make-positional src^ expr) rpositional*))]
                  [else (snamed new-field* #f (reverse rpositional*) '())])))
          (define (snamed new-field* maybe-spread positional* rnamed*)
            (if (null? new-field*)
                (finish maybe-spread positional* (reverse rnamed*))
                (nanopass-case (Lexpanded New-Field) (car new-field*)
                  [(named ,src^ ,elt-name ,expr)
                   (let ([elt-name (cond
                                     [(and (stdlib-src? src1)
                                           (assp (lambda (x) (and (eq? (car x) struct-name) (eq? (cdr x) elt-name)))
                                                 stdlib-struct-field-aliases)) =>
                                      (lambda (a)
                                        (let ([new-elt-name (cdr a)])
                                          (record-alias! src^ elt-name new-elt-name)
                                          new-elt-name))]
                                     [else elt-name])])
                     (snamed (cdr new-field*) maybe-spread positional* (cons (make-named src^ elt-name expr) rnamed*)))]
                  [(positional ,src^ ,expr) (source-errorf src^ "positional initializer found after spread or named initializer in struct creation syntax")]
                  [(spread ,src^ ,expr) (source-errorf src^ "spread initializer found after positional or named initializers in struct creation syntax")])))
          (define (finish maybe-spread positional* named*)
            (let ([npositional (length positional*)])
              (let ([ndeclared (length elt-name*)])
                (when (fx> npositional ndeclared)
                  (source-errorf src "more positional initializers (~d) supplied than the number of fields (~d) of ~a"
                                 npositional
                                 ndeclared
                                 (format-type type))))
              (when maybe-spread (process-field! maybe-spread))
              (for-each process-field! positional*)
              (for-each process-field! named*)
              (when maybe-spread
                (unless (sametype? (field-type maybe-spread) type)
                  (source-errorf (field-src maybe-spread)
                                 "the type of the spread structure:\n    ~a\n  does match the declared type of the structure to be created:\n    ~a"
                                 (format-type (field-type maybe-spread))
                                 (format-type type))))
              (let ([ht (make-hashtable symbol-hash eq?)])
                ; NB: assuming field names are not duplicated, which should have already been caught
                (for-each
                  (lambda (elt-name positional)
                    (hashtable-set! ht elt-name positional))
                  (list-head elt-name* npositional)
                  positional*)
                (for-each
                  (lambda (named)
                    (let ([a (hashtable-cell ht (named-elt-name named) #f)])
                      (when (cdr a)
                        (let ([src (field-src named)] [src^ (field-src (cdr a))])
                          (if (positional? (cdr a))
                              (source-errorf src
                                             "value of field ~s is already specified positionally at ~a"
                                             (named-elt-name named)
                                             (format-source-object src^))
                              (source-errorf src
                                             "value of field ~s is already given at ~a"
                                             (named-elt-name named)
                                             (format-source-object src^)))))
                      (set-cdr! a named)))
                  named*)
                (values
                  ((lambda (k)
                     (if maybe-spread
                         (maybe-bind src (field-type maybe-spread) (field-expr maybe-spread) k)
                         (k #f)))
                   (lambda (maybe-spread-expr)
                     (let ([th* (maplr
                                   (lambda (elt-name declared-type i)
                                     (cond
                                       [(hashtable-ref ht elt-name #f) =>
                                        (lambda (field)
                                          (hashtable-delete! ht elt-name)
                                          ; delay type checks until structural checks are completed so the
                                          ; compiler complains about structural problems in preference to
                                          ; type errors
                                          (lambda ()
                                            (let ([actual-type (field-type field)])
                                              (unless (subtype? actual-type declared-type)
                                                (source-errorf src "mismatch between actual type ~a and declared type ~a for field ~s of ~a"
                                                               (format-type actual-type)
                                                               (format-type declared-type)
                                                               elt-name
                                                               (format-type type)))
                                              (maybe-safecast src declared-type actual-type (field-expr field)))))]
                                       [maybe-spread-expr
                                        (lambda () `(elt-ref ,src ,maybe-spread-expr ,elt-name ,i))]
                                       [else
                                        (source-errorf src "value for element ~s is missing in creation syntax for ~a"
                                                       elt-name
                                                       (format-type type))]))
                                   elt-name* type* (enumerate elt-name*))])
                       (for-each
                         (lambda (named)
                           (when (hashtable-contains? ht (named-elt-name named))
                             (source-errorf (field-src named)
                                            "value for unrecognized field named ~a appears in creation syntax for ~a"
                                            (named-elt-name named)
                                            (format-type type))))
                         named*)
                       ; force type checks now that structural checks are completed
                       (let ([expr* (maplr (lambda (th) (th)) th*)])
                         `(new ,src ,type ,expr* ...)))))
                  type))))
          (s0)]
         [else (source-errorf src "expected structure type, received ~a"
                              (format-type type))])]
      [(seq ,src ,expr* ... ,expr)
       (let*-values ([(expr*) (maplr CareNot expr*)] [(expr type) (Care expr)])
         (values
           `(seq ,src ,expr* ... ,expr)
           type))]
      [(let* ,src ([(,var-name* ,[type*]) ,expr*] ...) ,expr)
       (let ([declared-type* type*])
         (let-values ([(expr* actual-type*) (maplr2 Care expr*)])
           (let ([declared-type* (maplr (lambda (var-name declared-type actual-type)
                                          (unless (subtype? actual-type declared-type)
                                            (source-errorf src "mismatch between actual type ~a and declared type ~a of const binding"
                                                           (format-type actual-type)
                                                           (format-type declared-type)))
                                          (let ([type (if (declared? declared-type)
                                                          declared-type
                                                          actual-type)])
                                            (set-idtype! var-name (Idtype-Base type))
                                            type))
                                        var-name*
                                        declared-type*
                                        actual-type*)])
             (let-values ([(expr body-type) (Care expr)])
               (for-each unset-idtype! var-name*)
               (values
                 `(let* ,src ([(,var-name* ,declared-type*)
                               ,(map (maybe-safecast src) declared-type* actual-type* expr*)]
                              ...)
                    ,expr)
                  body-type)))))]
      [(assert ,src ,[Care : expr type0] ,mesg)
       (unless (nanopass-case (Ltypes Type) (de-alias type0 #t)
                 [(tboolean ,src1) #t]
                 [else #f])
         (source-errorf src "expected test to have type Boolean, received ~a"
                        (format-type type0)))
       (values
         `(assert ,src ,expr ,mesg)
         (with-output-language (Ltypes Type) `(ttuple ,src)))]
      [(cast ,src ,type (quote ,src^ ,datum))
       (guard
         ; NB: guards are run before automatic recursion, so type is an Lexpanded Type, not an Ltypes Type
         (let f ([type type])
           (nanopass-case (Lexpanded Type) type
             [(tfield ,src) #t]
             [(talias ,src ,nominal? ,type-name ,type) (f type)]
             [else #f]))
         (field? datum)
         (> datum (max-unsigned)))
       (values
         `(quote ,src^ ,datum)
         (Type type))]
      [(cast ,src ,[type] ,[Care : expr type^])
       (define (handle-unaliased type type^ expr)
         (define (u8-subtype? type)
           (nanopass-case (Ltypes Type) (de-alias type #t)
             [(tunsigned ,src ,nat) (<= nat 255)]
             [else #f]))
         (define (u8-supertype? type)
           (nanopass-case (Ltypes Type) (de-alias type #t)
             [(tunsigned ,src ,nat) (>= nat 255)]
             [(tfield ,src) #t]
             [else #f]))
         (or (and (subtype? type^ type)
                  (maybe-safecast src type type^ expr))
             (T type
                [(tfield ,src1)
                 (T type^
                    [(tbytes ,src2 ,len2)
                     (guard (not (= len2 0)))
                     `(cast-from-bytes ,src ,type ,len2 ,expr)]
                    [(tenum ,src2 ,enum-name ,elt-name ,elt-name* ...)
                     `(cast-from-enum ,src ,type ,type^ ,expr)]
                    [(tboolean ,src2)
                     `(if ,src ,expr
                          (safe-cast ,src ,type (tunsigned ,src 1) (quote ,src 1))
                          (safe-cast ,src ,type (tunsigned ,src 0) (quote ,src 0)))])]
                [(tbytes ,src1 ,len1)
                 (T type^
                    [(tfield ,src2)
                     (guard (not (= len1 0)))
                     `(field->bytes ,src ,len1 ,expr)]
                    [(tunsigned ,src2 ,nat2)
                     (guard (not (= len1 0)))
                     `(field->bytes ,src ,len1 (safe-cast ,src (tfield ,src2) ,type^ ,expr))]
                    [(ttuple ,src2 ,type2* ...)
                     (guard
                       (= (length type2*) len1)
                       (andmap u8-subtype? type2*))
                     `(vector->bytes ,src ,len1 ,expr)]
                    [(tvector ,src2 ,len2 ,type2)
                     (guard (= len2 len1) (u8-subtype? type2))
                     `(vector->bytes ,src ,len1 ,expr)])]
                [(ttuple ,src1 ,type^* ...)
                 (T type^
                    [(tbytes ,src2 ,len2)
                     (guard (= len2 (length type^*)) (andmap u8-supertype? type^*))
                     (maybe-safecast src type
                       (with-output-language (Ltypes Type)
                         `(tvector ,src ,len2 (tunsigned ,src 255)))
                       `(bytes->vector ,src ,len2 ,expr))])]
                [(tvector ,src1 ,len1 ,type^^)
                 (T type^
                    [(tbytes ,src2 ,len2)
                     (guard (= len2 len1) (u8-supertype? type^^))
                     (maybe-safecast src type
                       (with-output-language (Ltypes Type)
                         `(tvector ,src ,len2 (tunsigned ,src 255)))
                       `(bytes->vector ,src ,len1 ,expr))])]
                [(tunsigned ,src1 ,nat1)
                 (T type^
                    [(tfield ,src2)
                     `(downcast-unsigned ,src ,nat1 ,expr)]
                    [(tunsigned ,src2 ,nat2)
                     (assert (> nat2 nat1))
                     `(downcast-unsigned ,src ,nat1 ,expr)]
                    [(tbytes ,src2 ,len2)
                     (guard (not (= len2 0)))
                     `(cast-from-bytes ,src ,type ,len2 ,expr)]
                    [(tenum ,src2 ,enum-name ,elt-name ,elt-name* ...)
                     `(cast-from-enum ,src ,type ,type^ ,expr)]
                    [(tboolean ,src2)
                     (if (= nat1 0)
                         `(if ,src ,expr
                              (downcast-unsigned ,src ,nat1 (quote ,src 1))
                              (quote ,src 0))
                         `(if ,src ,expr
                              ,(if (eqv? nat1 1)
                                   `(quote ,src 1)
                                   `(safe-cast ,src ,type (tunsigned ,src 1) (quote ,src 1)))
                              (safe-cast ,src ,type (tunsigned ,src 0) (quote ,src 0))))])]
                [(tboolean ,src1)
                 (T type^
                    [(tfield ,src2)
                     `(if ,src
                          (== ,src ,type^ ,expr (safe-cast ,src ,type^ (tunsigned ,src 0) (quote ,src 0)))
                          (quote ,src #f)
                          (quote ,src #t))]
                    [(tunsigned ,src2 ,nat2)
                     (if (eqv? nat2 0)
                         `(quote ,src #f)
                         `(if ,src
                              (== ,src ,type^ ,expr (safe-cast ,src ,type^ (tunsigned ,src 0) (quote ,src 0)))
                              (quote ,src #f)
                              (quote ,src #t)))])]
                [(tenum ,src1 ,enum-name ,elt-name ,elt-name* ...)
                 (guard (T type^ [(tfield ,src) #t] [(tunsigned ,src ,nat) #t]))
                 `(cast-to-enum ,src ,type ,type^ ,expr)])
             (source-errorf src "cannot cast from type ~a to type ~a"
                            (format-type type^)
                            (format-type type))))
       (values
         (let ([unaliased-type (de-alias type #t)] [unaliased-type^ (de-alias type^ #t)])
           (let ([expr (maybe-safecast src unaliased-type^ type^ expr)])
             (maybe-safecast src type unaliased-type (handle-unaliased unaliased-type unaliased-type^ expr))))
         type)]
      [(disclose ,src ,[Care : expr type])
       (values
         `(disclose ,src ,expr)
         type)]
      [(return ,src)
       (assert current-return-type)
       (let ([type (with-output-language (Ltypes Type) `(ttuple ,src))])
         (unless (subtype? type current-return-type)
           (source-errorf src "~a is declared to return a value of type ~a, but its body can return without supplying a value"
                          current-whose-body
                          (format-type current-return-type)))
         (values
           `(return ,src (tuple ,src))
           type))]
      [(return ,src ,[Care : expr type])
       (assert current-return-type)
       (unless (subtype? type current-return-type)
         (source-errorf src "mismatch between actual return type ~a and declared return type ~a of ~a"
                        (format-type type)
                        (format-type current-return-type)
                        current-whose-body))
       (values
         `(return ,src ,expr)
         type)]
      [else (internal-errorf 'Care "unexpected ir ~s" ir)])
    (Tuple-Argument : Tuple-Argument (ir) -> Expression (type kind nat elt-type*)
      [(single ,src ,[Care : expr type])
       (verify-non-adt-type! src type "tuple element")
       (values expr type 'single 1 (list type))]
      [(spread ,src ,[Care : expr type])
       (nanopass-case (Ltypes Type) (de-alias type #t)
         [(ttuple ,src ,type* ...) (values expr type 'tuple-spread (length type*) type*)]
         [(tvector ,src ,len ,type^) (values expr type 'vector-spread len (list type^))]
         [(tbytes ,src ,len)
          (let ([expr `(bytes->vector ,src ,len ,expr)])
            (let* ([type^ (with-output-language (Ltypes Type) `(tunsigned ,src 255))]
                   [type (with-output-language (Ltypes Type) `(tvector ,src ,len , type^))])
              (values expr type 'vector-spread len (list type^))))]
         [else (source-errorf src "expected tuple/vector spread expression to have a tuple, Vector, or Bytes type but received ~a"
                              (format-type type))])])
    (Bytes-Argument : Tuple-Argument (ir) -> Tuple-Argument (nat)
      (definitions
        (define (u8-subtype? type)
          (nanopass-case (Ltypes Type) (de-alias type #t)
            [(tunsigned ,src ,nat) (<= nat 255)]
            [(tunknown) #t]
            [else #f])))
      [(single ,src ,[Care : expr type])
       (unless (u8-subtype? type)
         (source-errorf src "expected type of Bytes constructor argument to be a subtype of Uint<8> but received ~a"
                        (format-type type)))
       (values
         (let ([new-type (with-output-language (Ltypes Type)
                           `(tunsigned ,src 255))])
           `(single ,src ,(maybe-safecast src new-type type expr)))
         1)]
      [(spread ,src ,[Care : expr type])
       (nanopass-case (Ltypes Type) (de-alias type #t)
         [(tbytes ,src ,len)
          (values
            `(spread ,src ,len (bytes->vector ,src ,len ,expr))
            len)]
         [(ttuple ,src ,type* ...)
          (guard (andmap u8-subtype? type*))
          (let ([nat (length type*)])
            (values
              `(spread ,src ,nat
                       ,(let ([new-type (with-output-language (Ltypes Type)
                                          ; there is no need to check (len? nat) since construction of tuple
                                          ; would have already caught it
                                          `(tvector ,src ,nat (tunsigned ,src 255)))])
                          (maybe-safecast src new-type type expr)))
              nat))]
         [(tvector ,src ,len ,type^)
          (guard (u8-subtype? type^))
          (values
            `(spread ,src ,len
                     ,(let ([new-type (with-output-language (Ltypes Type)
                                        `(tvector ,src ,len (tunsigned ,src 255)))])
                        (maybe-safecast src new-type type expr)))
            len)]
         [else (source-errorf src "expected type of Bytes spread to be a Bytes value or a Tuple or Vector of Uint<8> subtypes but received ~a"
                              (format-type type))])])
    )

  (define-pass remove-tundeclared : Ltypes (ir) -> Lnotundeclared ())

  (define-pass combine-ledger-declarations : Lnotundeclared (ir) -> Loneledger ()
    (definitions
      (define kernel-id*)
      (define (de-alias type)
        (nanopass-case (Lnotundeclared Type) type
          [(talias ,src ,nominal? ,type-name ,type)
           (de-alias type)]
          [else type]))
      (define (kernel? ldecl)
        (nanopass-case (Lnotundeclared Ledger-Declaration) ldecl
          [(public-ledger-declaration ,src ,ledger-field-name ,type)
           (nanopass-case (Lnotundeclared Type) (de-alias type)
             [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
              (eq? adt-name 'Kernel)]
             [else (assert cannot-happen)])])))
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (let*-values ([(ldecl* pelt*) (partition Lnotundeclared-Ledger-Declaration? pelt*)]
                     [(lconstructor* pelt*) (partition Lnotundeclared-Ledger-Constructor? pelt*)]
                     [(kernel-ldecl* ldecl*) (partition kernel? ldecl*)])
         (fluid-let ([kernel-id* (map (lambda (kernel-ldecl)
                                        (nanopass-case (Lnotundeclared Ledger-Declaration) kernel-ldecl
                                          [(public-ledger-declaration ,src ,ledger-field-name ,type)
                                           ledger-field-name]))
                                      kernel-ldecl*)])
           `(program ,src (,contract-name* ...) ((,export-name* ,name*) ...)
              ,(if (null? kernel-ldecl*)
                   '()
                   (list
                     (nanopass-case (Lnotundeclared Ledger-Declaration) (car kernel-ldecl*)
                       [(public-ledger-declaration ,src ,ledger-field-name ,type)
                        `(kernel-declaration (,src ,ledger-field-name ,(Type type)))])))
              ...
              (public-ledger-declaration
                ,(map (lambda (ldecl)
                        (nanopass-case (Lnotundeclared Ledger-Declaration) ldecl
                          [(public-ledger-declaration ,src ,ledger-field-name ,type)
                           `(,src ,ledger-field-name ,(Type type))]))
                      ldecl*)
                ...
                ,(cond
                  [(null? lconstructor*) `(constructor ,src () (tuple ,src))]
                  [(null? (cdr lconstructor*))
                   (nanopass-case (Lnotundeclared Ledger-Constructor) (car lconstructor*)
                     [(constructor ,src (,arg* ...) ,expr)
                      `(constructor ,src (,(map Argument arg*) ...) ,(Expression expr))])]
                  [else
                   (let ([src* (map (lambda (lconstructor)
                                      (nanopass-case (Lnotundeclared Ledger-Constructor) lconstructor
                                        [(constructor ,src (,arg* ...) ,expr) src]))
                                    lconstructor*)])
                     (source-errorf (car src*)
                                    "found other ledger constructors in program: \
                                     ~{\n    ~a~^,~}"
                                    (map format-source-object (cdr src*))))]))
              ,(map Program-Element pelt*)
              ...)))])
    (Program-Element : Program-Element (ir) -> Program-Element ()
      [,ldecl (assert cannot-happen)]
      [,lconstructor (assert cannot-happen)])
    (Argument : Argument (ir) -> Argument ())
    (Type : Type (ir) -> Type ())
    (Expression : Expression (ir) -> Expression ()
      [(ledger-ref ,src ,ledger-field-name) (assert cannot-happen)]
      [(ledger-call ,src ,ledger-op ,sugar? ,expr ,expr* ...)
       (let loop ([src src] [ledger-op ledger-op] [expr expr] [expr* expr*] [accessor* '()])
         (let ([accessor* (cons (with-output-language (Loneledger Ledger-Accessor)
                                  `(,src ,ledger-op ,(map Expression expr*) ...))
                                accessor*)])
           (nanopass-case (Lnotundeclared Expression) expr
             [(ledger-call ,src ,ledger-op ,sugar^? ,expr ,expr* ...)
              (assert (not sugar^?))
              (loop src ledger-op expr expr* accessor*)]
             [(ledger-ref ,src ,ledger-field-name)
              (let ([ledger-field-name (if (memq ledger-field-name kernel-id*)
                                           (car kernel-id*)
                                           ledger-field-name)])
                `(public-ledger ,src ,ledger-field-name ,sugar? ,accessor* ...))]
             [else (assert cannot-happen)])))])
  )

  (define-pass discard-unused-functions : Loneledger (ir) -> Loneledger ()
    (definitions
      (define worklist)
      (define deferred-ht (make-eq-hashtable))
      (define-record-type ipelt (nongenerative) (fields index pelt))
      (define (ipelt<? ipelt1 ipelt2) (fx<? (ipelt-index ipelt1) (ipelt-index ipelt2)))
      (define (ipelt->function-name ipelt)
        (nanopass-case (Loneledger Program-Element) (ipelt-pelt ipelt)
          [(circuit ,src ,function-name (,arg* ...) ,type ,expr) function-name]
          [(external ,src ,function-name ,native-entry (,arg* ...) ,type) function-name]
          [(witness ,src ,function-name (,arg* ...) ,type) function-name]
          [else #f]))
      (define (exported? ipelt)
        (let ([id (ipelt->function-name ipelt)])
          (or (not id) (id-exported? id)))))
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (let-values ([(exported* nonexported*) (partition exported? (map make-ipelt (enumerate pelt*) pelt*))])
         (for-each
           (lambda (ipelt) (hashtable-set! deferred-ht (ipelt->function-name ipelt) ipelt))
           nonexported*)
         (fluid-let ([worklist exported*])
           (let loop ([keep* '()])
             (if (null? worklist)
                 `(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,(map ipelt-pelt (sort ipelt<? keep*)) ...)
                 (let ([ipelt (car worklist)])
                   (set! worklist (cdr worklist))
                   (loop (cons (make-ipelt (ipelt-index ipelt) (Program-Element (ipelt-pelt ipelt))) keep*)))))))])
    (Program-Element : Program-Element (ir) -> Program-Element ())
    (Function : Function (ir) -> Function ()
      [(fref ,src ,function-name)
       (cond
         [(hashtable-ref deferred-ht function-name #f) =>
          (lambda (ipelt)
            (hashtable-delete! deferred-ht function-name)
            (set! worklist (cons ipelt worklist)))])
       ir]))

  (define-pass reject-recursive-circuits : Loneledger (ir) -> Loneledger ()
    (definitions
      (define call-stack '())
      ; circuit-ht maps ids (specifically circuit names) to one of:
      ;   an Loneledger Expression (id names a circuit that has yet to be processed)
      ;   the symbol in-process (id names a circuit that is being processed)
      ;   the symbol processed (id names a circuit that has already been processed)
      (define circuit-ht (make-eq-hashtable))
      (define (process-circuit function-name)
        (let ([a (eq-hashtable-cell circuit-ht function-name 'not-a-circuit)])
          (case (cdr a)
            [(processed not-a-circuit) (void)]
            [(in-process)
             (let ([id+ (sort (lambda (id1 id2) (source-object<? (id-src id1) (id-src id2)))
                                (let f ([call-stack call-stack] [function-name^ function-name])
                                   (cons function-name^
                                        (let ([function-name^ (car call-stack)])
                                          (if (eq? function-name^ function-name)
                                              '()
                                              (f (cdr call-stack) function-name^))))))])
               (let ([id (car id+)] [id* (cdr id+)])
                 (source-errorf (id-src id)
                   "recursion involving~?"
                   "~#[~; ~a~; ~a and ~a~:;~@{~#[~; and~] ~a~^,~}~]"
                   (cons (id-sym id)
                         (map (lambda (id) (format "~s at ~a" (id-sym id) (format-source-object (id-src id))))
                              id*)))))]
            [else
             (let ([expr (cdr a)])
               (set-cdr! a 'in-process)
               (fluid-let ([call-stack (cons function-name call-stack)])
                 (Expression expr)
                 (set-cdr! a 'processed)))])))
      )
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each record-circuit! pelt*)
       `(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,(map Program-Element pelt*) ...)])
    (record-circuit! : Program-Element (ir) -> * (void)
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (eq-hashtable-set! circuit-ht function-name expr)]
      [else (void)])
    (Program-Element : Program-Element (ir) -> Program-Element ()
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (process-circuit function-name)
       ir]
      [else ir])
    (Expression : Expression (ir) -> Expression ())
    (Function : Function (ir) -> Function ()
      [(fref ,src ,function-name)
       (process-circuit function-name)
       ir]))

  (define-pass recognize-let : Loneledger (ir) -> Lnodca ()
    ; this pass has two benefits for the downstream typescript generation pass:
    ; - it simplifies the generated code a bit, and, more importantly,
    ; - it allows exercise of non-top-level let expressions
    (Expr : Expression (ir) -> Expression ()
      [(call ,src (fref ,src^ ,function-name) ,[expr*] ...)
       `(call ,src ,function-name ,expr* ...)]
      [(call ,src (circuit ,src^ ((,var-name* ,[type*]) ...) ,[type] ,[expr]) ,[expr*] ...)
       `(let* ,src ([(,var-name* ,type*) ,expr*] ...) ,expr)]
      ; nanopass doesn't recognize that the two clauses together cover all calls
      [(call ,src ,fun ,expr* ...) (assert cannot-happen)]))

  (define-pass check-types/Lnodca : Lnodca (ir) -> Lnodca ()
    (definitions
      (define-syntax T
        (syntax-rules ()
          [(T ty clause ...)
           (nanopass-case (Lnodca Type) ty clause ... [else #f])]))
      (define (datum-type src x)
        (with-output-language (Lnodca Type)
          (cond
            [(boolean? x) `(tboolean ,src)]
            [(field? x) (if (<= x (max-unsigned)) `(tunsigned ,src ,x) `(tfield ,src))]
            [(bytevector? x) `(tbytes ,src ,(bytevector-length x))]
            [else (internal-errorf 'datum-type "unexpected datum ~s" x)])))
      (define-datatype Idtype
        ; ordinary expression types
        (Idtype-Base type)
        ; circuits, witnesses, and statements
        (Idtype-Function kind arg-name* arg-type* return-type)
        )
      (module (set-idtype! unset-idtype! get-idtype)
        (define ht (make-eq-hashtable))
        (define (set-idtype! id idtype)
          (hashtable-set! ht id idtype))
        (define (unset-idtype! id)
          (hashtable-delete! ht id))
        (define (get-idtype src id)
          (or (hashtable-ref ht id #f)
              (source-errorf src "encountered undefined identifier ~s"
                id)))
        )
      (define (arg->name arg)
        (nanopass-case (Lnodca Argument) arg
          [(,var-name ,type) var-name]))
      (define (arg->type arg)
        (nanopass-case (Lnodca Argument) arg
          [(,var-name ,type) type]))
      (define (format-type type)
        (define (format-adt-arg adt-arg)
          (nanopass-case (Lnodca Public-Ledger-ADT-Arg) adt-arg
            [,nat (format "~d" nat)]
            [,type (format-type type)]))
        (nanopass-case (Lnodca Type) type
          [(tboolean ,src) "Boolean"]
          [(tfield ,src) "Field"]
          [(tunsigned ,src ,nat) (format "Uint<0..~d>" (+ nat 1))]
          [(topaque ,src ,opaque-type) (format "Opaque<~s>" opaque-type)]
          [(tunknown) "Unknown"]
          [(tvector ,src ,len ,type) (format "Vector<~s, ~a>" len (format-type type))]
          [(tbytes ,src ,len) (format "Bytes<~s>" len)]
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (format "contract ~a<~{~a~^, ~}>" contract-name
             (map (lambda (elt-name pure-dcl type* type)
                    (if pure-dcl
                        (format "pure ~a(~{~a~^, ~}): ~a" elt-name
                                (map format-type type*) (format-type type))
                        (format "~a(~{~a~^, ~}): ~a" elt-name
                                (map format-type type*) (format-type type))))
                  elt-name* pure-dcl* type** type*))]
          [(ttuple ,src ,type* ...)
           (format "[~{~a~^, ~}]" (map format-type type*))]
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           (format "struct ~a<~{~a~^, ~}>" struct-name
             (map (lambda (elt-name type)
                    (format "~a: ~a" elt-name (format-type type)))
                  elt-name* type*))]
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
           (format "Enum<~a, ~s~{, ~s~}>" enum-name elt-name elt-name*)]
          [(talias ,src ,nominal? ,type-name ,type)
           (let ([s (format-type type)])
             (if nominal?
                 (format "~a=~a" type-name s)
                 s))]
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (format "~s~@[<~{~a~^, ~}>~]" adt-name (and (not (null? adt-arg*)) (map format-adt-arg adt-arg*)))]
          [else (internal-errorf 'check-types/Lnodca-format-type "unexpected type ~s" type)]))
      (define (de-alias type)
        (nanopass-case (Lnodca Type) type
          [(talias ,src ,nominal? ,type-name ,type)
           (de-alias type)]
          [else type]))
      (define (sametype? type1 type2)
        (define (same-adt-arg? adt-arg1 adt-arg2)
          (nanopass-case (Lnodca Public-Ledger-ADT-Arg) adt-arg1
            [,nat1
             (nanopass-case (Lnodca Public-Ledger-ADT-Arg) adt-arg2
               [,nat2 (= nat1 nat2)]
               [else #f])]
            [,type1
             (nanopass-case (Lnodca Public-Ledger-ADT-Arg) adt-arg2
               [,type2 (sametype? type1 type2)]
               [else #f])]))
        (let ([type1 (de-alias type1)] [type2 (de-alias type2)])
          (T type1
             [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
             [(tfield ,src1) (T type2 [(tfield ,src2) #t])]
             [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])]
             [(tbytes ,src1 ,len1) (T type2 [(tbytes ,src2 ,len2) (= len1 len2)])]
             [(topaque ,src1 ,opaque-type1)
              (T type2
                 [(topaque ,src2 ,opaque-type2)
                  (string=? opaque-type1 opaque-type2)])]
             [(tvector ,src1 ,len1 ,type1)
              (T type2
                 [(tvector ,src2 ,len2 ,type2)
                  (and (= len1 len2)
                       (sametype? type1 type2))]
                 [(ttuple ,src2 ,type2* ...)
                  (and (= len1 (length type2*))
                       (andmap (lambda (type2) (sametype? type1 type2)) type2*))])]
             [(ttuple ,src1 ,type1* ...)
              (T type2
                 [(tvector ,src2 ,len2 ,type2)
                  (and (= (length type1*) len2)
                       (andmap (lambda (type1) (sametype? type1 type2)) type1*))]
                 [(ttuple ,src2 ,type2* ...)
                  (and (= (length type1*) (length type2*))
                       (andmap sametype? type1* type2*))])]
             [(tunknown) (T type2 [(tunknown) #t])]
             [(tcontract ,src1 ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
              (T type2
                 [(tcontract ,src2 ,contract-name2 (,elt-name2* ,pure-dcl2* (,type2** ...) ,type2*) ...)
                  (define (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*)
                    (andmap (lambda (elt-name2 pure-dcl2 type2* type2)
                              (ormap (lambda (elt-name1 pure-dcl1 type1* type1)
                                       (and (eq? elt-name1 elt-name2)
                                            (eq? pure-dcl1 pure-dcl2)
                                            (fx= (length type1*) (length type2*))
                                            (andmap sametype? type1* type2*)
                                            (sametype? type1 type2)))
                                     elt-name1* pure-dcl1* type1** type1*))
                            elt-name2* pure-dcl2* type2** type2*))
                  (and (eq? contract-name1 contract-name2)
                       (fx= (length elt-name1*) (length elt-name2*))
                       (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*))])]
             [(tstruct ,src1 ,struct-name1 (,elt-name1* ,type1*) ...)
              (T type2
                 [(tstruct ,src2 ,struct-name2 (,elt-name2* ,type2*) ...)
                  ; include struct-name and elt-name tests for nominal typing; remove
                  ; for structural typing.
                  (and (eq? struct-name1 struct-name2)
                       (= (length elt-name1*) (length elt-name2*))
                       (andmap eq? elt-name1* elt-name2*)
                       (andmap sametype? type1* type2*))])]
             [(tenum ,src1 ,enum-name1 ,elt-name1 ,elt-name1* ...)
              (T type2
                 [(tenum ,src2 ,enum-name2 ,elt-name2 ,elt-name2* ...)
                  (and (eq? enum-name1 enum-name2)
                       (eq? elt-name1 elt-name2)
                       (= (length elt-name1*) (length elt-name2*))
                       (andmap eq? elt-name1* elt-name2*))])]
             [(tadt ,src1 ,adt-name1 ([,adt-formal1* ,adt-arg1*] ...) ,vm-expr (,adt-op1* ...) (,adt-rt-op1* ...))
              (T type2
                 [(tadt ,src2 ,adt-name2 ([,adt-formal2* ,adt-arg2*] ...) ,vm-expr (,adt-op2* ...) (,adt-rt-op2* ...))
                  (and (eq? adt-name1 adt-name2)
                       (fx= (length adt-arg1*) (length adt-arg2*))
                       (andmap same-adt-arg? adt-arg1* adt-arg2*))])])))
      (define (do-circuit-body src what arg* return-type expr)
        (let ([id* (map arg->name arg*)] [type* (map arg->type arg*)])
          (for-each (lambda (id type) (set-idtype! id (Idtype-Base type))) id* type*)
          (let ([actual-type (Care expr)])
            (unless (sametype? actual-type return-type)
              (source-errorf src "mismatch between actual return type ~a and declared return type ~a in ~a"
                (format-type actual-type)
                (format-type return-type)
                what))
            (for-each unset-idtype! id*))))
      (define (do-call src fold? fun actual-type*)
        (define compatible?
          (let ([nactual (length actual-type*)])
            (lambda (arg-type* return-type)
              (and (= (length arg-type*) nactual)
                   (andmap sametype? actual-type* arg-type*)
                   (or (not fold?)
                       (sametype? return-type (car arg-type*)))))))
        (nanopass-case (Lnodca Function) fun
          [(fref ,src^ ,function-name)
           (Idtype-case (get-idtype src function-name)
             [(Idtype-Function kind arg-name* arg-type* return-type)
              (unless (compatible? arg-type* return-type)
                (source-errorf src
                               "incompatible arguments in call to ~a;\n    \
                               supplied argument types:\n      \
                               (~{~a~^, ~});\n    \
                               declared argument types:\n      \
                               ~a: (~{~a~^, ~})"
                  (symbol->string (id-sym function-name))
                  (map format-type actual-type*)
                  (format-source-object (id-src function-name))
                  (map format-type arg-type*)))
            return-type]
           [else (source-errorf src "invalid context for reference to ~s (defined at ~a)"
                                function-name
                                (format-source-object (id-src function-name)))])]
          [(circuit ,src^ (,arg* ...) ,type ,expr)
           (let ([arg-type* (map arg->type arg*)])
             (unless (compatible? arg-type* type)
               (source-errorf src
                              "incompatible arguments in call to anonymous circuit;\n    \
                              supplied argument types:\n      \
                              (~{~a~^, ~});\n    \
                              declared circuit type:\n      \
                              (~{~a~^, ~})~@[: ~a~]\
                              ~:[~;;\n    (fold also requires return type and first-argument type to be the same)~]"
                 (map format-type actual-type*)
                 (map format-type arg-type*)
                 (and fold? (format-type type))
                 fold?)))
           (do-circuit-body src^ "anonymous circuit" arg* type expr)
           type]
          [else (assert cannot-happen)]))
       (define (arithmetic-binop src op mbits expr1 expr2)
         (let ([type1 (Care expr1)] [type2 (Care expr2)])
           (let ([unaliased-type1 (de-alias type1)] [unaliased-type2 (de-alias type2)])
             (or (T unaliased-type1
                    [(tfield ,src1) (T unaliased-type2 [(tfield ,src2) #t])]
                    [(tunsigned ,src1 ,nat1) (T unaliased-type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])])
                 (source-errorf src "incompatible combination of types ~a and ~a for ~s"
                                (format-type type1)
                                (format-type type2)
                                op))
             (unless (eqv? (T unaliased-type1 [(tunsigned ,src ,nat) (fxmax 1 (integer-length nat))]) mbits)
               (source-errorf src "mismatched mbits ~s and type ~a for ~s"
                              mbits
                              (format-type type1)
                              op)))
           type1))
       (define (relational-operator src mbits expr1 expr2)
         (let ([type1 (Care expr1)] [type2 (Care expr2)])
           (let ([unaliased-type1 (de-alias type1)] [unaliased-type2 (de-alias type2)])
             (or (T unaliased-type1
                    [(tunsigned ,src1 ,nat1) (T unaliased-type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])])
                   ; the error message says "relational operator" here rather than "<" to avoid misleading
                   ; type-mismatch messages for <=, >, and >=; which all get converted to < earlier in the compiler.
                 (source-errorf src "incompatible combination of types ~a and ~a for relational operator"
                                (format-type type1)
                                (format-type type2)))
             (unless (eqv? (T unaliased-type1 [(tunsigned ,src ,nat) (fxmax 1 (integer-length nat))]) mbits)
               ; the error message says "relational operator" here rather than "<" to avoid misleading
               ; type-mismatch messages for <=, >, and >=; which all get converted to < earlier in the compiler.
               (source-errorf src "mismatched mbits ~s and type ~a for relational operator"
                              mbits
                              (format-type type1)))))
         (with-output-language (Lnodca Type) `(tboolean ,src)))
       (define (equality-operator src type expr1 expr2)
         (let* ([type1 (Care expr1)] [type2 (Care expr2)])
           (unless (sametype? type1 type2)
             ; the error message say "equality operator" here rather than "==" to avoid misleading
             ; type-mismatch messages for !=, which gets converted to == earlier in the compiler.
             (source-errorf src "non-equivalent types ~a and ~a for equality operator"
                            (format-type type1)
                            (format-type type2)))
           (unless (sametype? type type1)
             ; the error message say "equality operator" here rather than "==" to avoid misleading
             ; type-mismatch messages for !=, which gets converted to == earlier in the compiler.
             (source-errorf src "mismatch between recorded type ~a and equality operand type ~a"
                            (format-type type)
                            (format-type type1))))
         (with-output-language (Lnodca Type) `(tboolean ,src)))
      (module (record-adt-ops! lookup-adt-ops)
        (define ledger-ht (make-eq-hashtable))
        (define (record-one! public-binding)
          (nanopass-case (Lnodca Public-Ledger-Binding) public-binding
            [(,src ,ledger-field-name ,type)
             (nanopass-case (Lnodca Type) (de-alias type)
               [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                (hashtable-set! ledger-ht ledger-field-name adt-op*)]
               [else (assert cannot-happen)])]))
        (define (record-adt-ops! pelt)
          (nanopass-case (Lnodca Program-Element) pelt
            [(kernel-declaration ,public-binding)
             (record-one! public-binding)]
            [(public-ledger-declaration ,public-binding* ... ,lconstructor)
             (for-each record-one! public-binding*)]
            [else (void)]))
        (define (lookup-adt-ops ledger-field-name)
          (assert (hashtable-ref ledger-ht ledger-field-name #f))))
      )
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each record-adt-ops! pelt*)
       (guard (c [else (internal-errorf 'check-types/Lnodca
                                        "downstream type-check failure:\n~a"
                                        (with-output-to-string (lambda () (display-condition c))))])
         (for-each Set-Program-Element-Type! pelt*)
         (for-each Program-Element pelt*)
         ir)])
    (Set-Program-Element-Type! : Program-Element (ir) -> * (void)
      (definitions
        (define (build-function kind name arg* type)
          (let ([var-name* (map arg->name arg*)] [type* (map arg->type arg*)])
            (set-idtype! name (Idtype-Function kind var-name* type* type)))))
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (build-function 'circuit function-name arg* type)]
      [(external ,src ,function-name ,native-entry (,arg* ...) ,type)
       (build-function 'circuit function-name arg* type)]
      [(witness ,src ,function-name (,arg* ...) ,type)
       (build-function 'witness function-name arg* type)]
      [(public-ledger-declaration ,public-binding* ... ,lconstructor) (void)]
      [(kernel-declaration ,public-binding) (void)]
      [(export-typedef ,src ,type-name (,tvar-name* ...) ,type) (void)])
    (Ledger-Constructor : Ledger-Constructor (ir) -> * (void)
      [(constructor ,src (,arg* ...) ,expr)
       (do-circuit-body src "ledger constructor" arg* (with-output-language (Lnodca Type) `(ttuple ,src)) expr)])
    (Program-Element : Program-Element (ir) -> * (void)
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (do-circuit-body src (format "circuit ~a" (id-sym function-name)) arg* type expr)]
      [else (void)])
    (CareNot : Expression (ir) -> * (void)
      [(if ,src ,[Care : expr0 -> * type0] ,expr1 ,expr2)
       (unless (nanopass-case (Lnodca Type) (de-alias type0)
                 [(tboolean ,src1) #t]
                 [else #f])
         (source-errorf src "expected test to have type Boolean, received ~a"
                        (format-type type0)))
       (CareNot expr1)
       (CareNot expr2)]
      [(seq ,src ,expr* ... ,expr)
       (maplr CareNot expr*)
       (CareNot expr)]
      [(let* ,src ([,local* ,expr*] ...) ,expr)
       (let ([var-name* (map arg->name local*)] [declared-type* (map arg->type local*)])
         (let ([actual-type* (maplr Care expr*)])
           (for-each (lambda (var-name declared-type actual-type)
                       (let ([type (nanopass-case (Lnodca Type) declared-type
                                     [(tunknown) actual-type]
                                     [else
                                      (unless (sametype? actual-type declared-type)
                                        (source-errorf src "mismatch between actual type ~a and declared type ~a of ~s"
                                                       (format-type actual-type)
                                                       (format-type declared-type)
                                                  var-name))
                                      declared-type])])
                         (set-idtype! var-name (Idtype-Base type))
                         type))
                     var-name*
                     declared-type*
                     actual-type*))
         (CareNot expr)
         (for-each unset-idtype! var-name*))]
      [else
       (Care ir)
       (void)])
    (Care : Expression (ir) -> * (type)
      [(quote ,src ,datum)
       (datum-type src datum)]
      [(var-ref ,src ,var-name)
       (Idtype-case (get-idtype src var-name)
         [(Idtype-Base type) type]
         [(Idtype-Function kind arg-name* arg-type* return-type)
          (source-errorf src "invalid context for reference to ~s name ~s"
                         kind
                         var-name)])]
      [(default ,src ,type) type]
      [(if ,src ,[Care : expr0 -> * type0] ,expr1 ,expr2)
       (unless (nanopass-case (Lnodca Type) (de-alias type0)
                 [(tboolean ,src1) #t]
                 [else #f])
         (source-errorf src "expected test to have type Boolean, received ~a"
                        (format-type type0)))
       (let ([type1 (Care expr1)] [type2 (Care expr2)])
         (cond
           [(sametype? type1 type2) type1]
           [else (source-errorf src "mismatch between type ~a and type ~a of condition branches"
                                (format-type type1)
                                (format-type type2))]))]
      [(elt-ref ,src ,[Care : expr -> * type] ,elt-name ,nat)
       (nanopass-case (Lnodca Type) (de-alias type)
         [(tstruct ,src1 ,struct-name (,elt-name* ,type*) ...)
          (let loop ([elt-name* elt-name*] [type* type*] [i 0])
            (if (null? elt-name*)
                (source-errorf src "structure ~s has no field named ~s"
                               struct-name
                               elt-name)
                (if (eq? (car elt-name*) elt-name)
                    (begin
                      (unless (eqv? nat i)
                        (source-errorf src "recorded index ~d does not match actual index ~d for elt ~s of ~s"
                                       nat
                                       i
                                       elt-name
                                       struct-name))
                      (car type*))
                    (loop (cdr elt-name*) (cdr type*) (fx+ i 1)))))]
         [else (source-errorf src "expected structure type, received ~a"
                              (format-type type))])]
      [(enum-ref ,src ,type ,elt-name^)
       (nanopass-case (Lnodca Type) (de-alias type)
         [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
          (unless (or (eq? elt-name^ elt-name) (memq elt-name^ elt-name*))
            (source-errorf src "enum ~s has no field named ~s"
                           enum-name
                           elt-name^))
          type]
         [else
          ; can't presently happen: we never construct an enum-ref unless we have an enum type
          (source-errorf src "expected enum type, received ~a"
                         (format-type type))])]
      [(tuple-ref ,src ,[Care : expr -> * expr-type] ,kindex)
       (define (bounds-check len)
         (unless (< kindex len)
           (source-errorf src "index ~s is out-of-bounds for tuple or vector of length ~s"
                          kindex len)))
       (nanopass-case (Lnodca Type) (de-alias expr-type)
         [(ttuple ,src ,type* ...)
          (bounds-check (length type*))
          (list-ref type* kindex)]
         [(tvector ,src ,len ,type)
          (bounds-check len)
          type]
         [else (source-errorf src "expected tuple or vector type, received ~a"
                              (format-type expr-type))])]
      [(bytes-ref ,src ,type ,[Care : expr -> * expr-type] ,[Care : index -> * index-type])
       (nanopass-case (Lnodca Type) (de-alias index-type)
         [(tunsigned ,src^ ,nat) nat]
         [else (source-errorf src "expected index to have an unsigned type, received ~a"
                              (format-type index-type))])
       (unless (sametype? expr-type type)
         (source-errorf src "expected bytes-ref argument to have type ~a, received ~a"
                        type expr-type))
       (with-output-language (Lnodca Type) `(tunsigned ,src 255))]
      [(vector-ref ,src ,type ,[Care : expr -> * expr-type] ,[Care : index -> * index-type])
       (nanopass-case (Lnodca Type) (de-alias index-type)
         [(tunsigned ,src^ ,nat) nat]
         [else (source-errorf src "expected index to have an unsigned type, received ~a"
                              (format-type index-type))])
       (unless (sametype? expr-type type)
         (source-errorf src "expected vector-ref argument to have type ~a, received ~a"
                        type expr-type))
       (nanopass-case (Lnodca Type) (de-alias expr-type)
         [(tvector ,src^ ,len^ ,type^)
          (guard (> len^ 0))
          type^]
         [(ttuple ,src^ ,type^ ,type^* ...)
          (guard (andmap (lambda (type^^) (sametype? type^^ type^)) type^*))
          type^]
         [else (source-errorf src "expected vector-ref expr to have a non-empty vector type, received ~a"
                              (format-type expr-type))])]
      [(tuple-slice ,src ,[type] ,[Care : expr -> * expr-type] ,kindex ,len)
       (define (bounds-check input-len)
         (unless (<= (+ kindex len) input-len)
           (source-errorf src "index ~d plus length ~d is out-of-bounds for a tuple or vector of length ~d"
                          kindex len input-len)))
       (unless (sametype? expr-type type)
         (source-errorf src "expected slice argument to have type ~a, received ~a"
                        (format-type type) (format-type expr-type)))
       (with-output-language (Lnodca Type)
         (nanopass-case (Lnodca Type) (de-alias expr-type)
           [(ttuple ,src^ ,type* ...)
            (bounds-check (length type*))
            `(ttuple ,src ,(list-head (list-tail type* kindex) len) ...)]
           [(tvector ,src^ ,len^ ,type)
            (bounds-check len^)
            `(tvector ,src ,len ,type)]
           [else (source-errorf src "expected tuple or vector type, received ~a"
                                (format-type expr-type))]))]
      [(bytes-slice ,src ,type ,[Care : expr -> * expr-type] ,[Care : index -> * index-type] ,len)
       (nanopass-case (Lnodca Type) (de-alias index-type)
         [(tunsigned ,src^ ,nat) nat]
         [else (source-errorf src "expected index to have an unsigned type, received ~a"
                              (format-type index-type))])
       (unless (sametype? expr-type type)
         (source-errorf src "expected slice argument to have type ~a, received ~a"
                        (format-type type) (format-type expr-type)))
       (let ([input-len (nanopass-case (Lnodca Type) (de-alias expr-type)
                          [(tbytes ,src ,len) len]
                          [else (source-errorf src "expected slice expr to have a Bytes type, received ~a"
                                               (format-type expr-type))])])
         (unless (<= len input-len)
           (source-errorf src "slice length ~d exceeds the length ~d of the input Bytes" len input-len))
         (with-output-language (Lnodca Type)
           `(tbytes ,src ,len)))]
      [(vector-slice ,src ,type ,[Care : expr -> * expr-type] ,[Care : index -> * index-type] ,len)
       (nanopass-case (Lnodca Type) (de-alias index-type)
         [(tunsigned ,src^ ,nat) nat]
         [else (source-errorf src "expected index to have an unsigned type, received ~a"
                              (format-type index-type))])
       (unless (sametype? expr-type type)
         (source-errorf src "expected slice argument to have type ~a, received ~a"
                        (format-type type) (format-type expr-type)))
       (let-values ([(input-len elt-type) (nanopass-case (Lnodca Type) (de-alias expr-type)
                                            [(tvector ,src^ ,len^ ,type^) (values len^ type^)]
                                            [(ttuple ,src^) (values 0 (with-output-language (Lnodca Type) `(tunknown)))]
                                            [(ttuple ,src^ ,type^ ,type^* ...)
                                             (guard (andmap (lambda (type^^) (sametype? type^^ type^)) type^*))
                                             (values (fx+ (length type^*) 1) type^)]
                                            [else (source-errorf src "expected slice expr to have a vector type, received ~a"
                                                                 (format-type expr-type))])])
         (unless (<= len input-len)
           (source-errorf src "slice length ~d exceeds the length ~d of the input vector" len input-len))
         (with-output-language (Lnodca Type)
           `(tvector ,src ,len ,elt-type)))]
      [(+ ,src ,mbits ,expr1 ,expr2)
       (arithmetic-binop src "+" mbits expr1 expr2)]
      [(- ,src ,mbits ,expr1 ,expr2)
       (arithmetic-binop src "-" mbits expr1 expr2)]
      [(* ,src ,mbits ,expr1 ,expr2)
       (arithmetic-binop src "*" mbits expr1 expr2)]
      [(< ,src ,mbits ,expr1 ,expr2)
       (relational-operator src mbits expr1 expr2)]
      [(<= ,src ,mbits ,expr1 ,expr2)
       (relational-operator src mbits expr1 expr2)]
      [(> ,src ,mbits ,expr1 ,expr2)
       (relational-operator src mbits expr1 expr2)]
      [(>= ,src ,mbits ,expr1 ,expr2)
       (relational-operator src mbits expr1 expr2)]
      [(== ,src ,type ,expr1 ,expr2)
       (equality-operator src type expr1 expr2)]
      [(!= ,src ,type ,expr1 ,expr2)
       (equality-operator src type expr1 expr2)]
      [(map ,src ,len ,fun ,map-arg ,map-arg* ...)
       (let ([elt-type+ (let ([map-arg+ (cons map-arg map-arg*)])
                          (map (lambda (map-arg i)
                                 (Map-Argument map-arg src 'map len (fx+ i 1)))
                               map-arg+
                               (enumerate map-arg+)))])
         (let ([return-type (do-call src #f fun elt-type+)])
           (with-output-language (Lnodca Type)
             `(tvector ,src ,len ,return-type))))]
      [(fold ,src ,len ,fun (,expr0 ,type0) ,map-arg ,map-arg* ...)
       (let ([type0^ (Care expr0)])
         (unless (sametype? type0^ type0)
           (source-errorf src "mismatch between actual type ~a and declared type ~a of fold first argument"
                          (format-type type0^)
                          (format-type type0))))
       (let ([elt-type+ (let ([map-arg+ (cons map-arg map-arg*)])
                          (map (lambda (map-arg i)
                                 (Map-Argument map-arg src 'fold len (fx+ i 2)))
                               map-arg+
                               (enumerate map-arg+)))])
         (do-call src #t fun (cons type0 elt-type+)))]
      [(call ,src ,function-name ,expr* ...)
       (do-call src #f
                (with-output-language (Lnodca Function)
                  `(fref ,src ,function-name))
                (maplr Care expr*))]
      [(new ,src ,type ,expr* ...)
       (let ([actual-type* (maplr Care expr*)])
         (nanopass-case (Lnodca Type) (de-alias type)
           [(tstruct ,src1 ,struct-name (,elt-name* ,type*) ...)
            (let ([nactual (length actual-type*)] [ndeclared (length type*)])
              (unless (fx= nactual ndeclared)
                (source-errorf src "mismatch between actual number ~s and declared number ~s of field values for ~s"
                               nactual
                               ndeclared
                               struct-name)))
            (for-each
              (lambda (declared-type actual-type elt-name)
                (unless (sametype? actual-type declared-type)
                  (source-errorf src "mismatch between actual type ~a and declared type ~a for field ~s of ~s"
                    (format-type actual-type)
                    (format-type declared-type)
                    elt-name
                    struct-name)))
              type*
              actual-type*
              elt-name*)]
           [else (source-errorf src "expected structure type, received ~a"
                                (format-type type))])
         type)]
      [(seq ,src ,expr* ... ,expr)
       (for-each CareNot expr*)
       (Care expr)]
      [(let* ,src ([,local* ,expr*] ...) ,expr)
       (let ([var-name* (map arg->name local*)] [declared-type* (map arg->type local*)])
         (let ([actual-type* (maplr Care expr*)])
           (for-each (lambda (var-name declared-type actual-type)
                       (let ([type (nanopass-case (Lnodca Type) declared-type
                                     [(tunknown) actual-type]
                                     [else
                                      (unless (sametype? actual-type declared-type)
                                        (source-errorf src "mismatch between actual type ~a and declared type ~a of ~s"
                                                       (format-type actual-type)
                                                       (format-type declared-type)
                                                  var-name))
                                      declared-type])])
                         (set-idtype! var-name (Idtype-Base type))
                         type))
                     var-name*
                     declared-type*
                     actual-type*)
           (let ([type (Care expr)])
             (for-each unset-idtype! var-name*)
             type)))]
      [(assert ,src ,[Care : expr -> * type] ,mesg)
       (unless (nanopass-case (Lnodca Type) (de-alias type)
                 [(tboolean ,src1) #t]
                 [else #f])
         (source-errorf src "expected test to have type Boolean, received ~a"
                        (format-type type)))
       (with-output-language (Lnodca Type) `(ttuple ,src))]
      [(disclose ,src ,[Care : expr -> * type]) type]
      [(tuple ,src ,tuple-arg* ...)
       (with-output-language (Lnodca Type)
         `(ttuple ,src
            ,(fold-right
               (lambda (tuple-arg type*)
                 (nanopass-case (Lnodca Tuple-Argument) tuple-arg
                   [(single ,src ,expr) (cons (Care expr) type*)]
                   [(spread ,src ,nat ,expr)
                    (let ([type (Care expr)])
                      (nanopass-case (Lnodca Type) (de-alias type)
                        [(ttuple ,src ,type^* ...) (append type^* type*)]
                        [else (source-errorf src "expected type of tuple spread to be a ttuple type but received ~a"
                                             (format-type type))]))]))
               '()
               tuple-arg*)
            ...))]
      [(vector ,src ,tuple-arg* ...)
       (with-output-language (Lnodca Type)
         (let-values ([(nat* type**) (maplr2 (lambda (tuple-arg)
                                               (nanopass-case (Lnodca Tuple-Argument) tuple-arg
                                                 [(single ,src ,expr) (values 1 (list (Care expr)))]
                                                 [(spread ,src ,nat ,expr)
                                                  (let ([type (Care expr)])
                                                    (nanopass-case (Lnodca Type) (de-alias type)
                                                      [(ttuple ,src ,type* ...) (values (length type*) type*)]
                                                      [(tvector ,src ,len ,type) (values len (list type))]
                                                      [(tbytes ,src ,len) (values len (list `(tunsigned ,src 255)))]
                                                      [else (source-errorf src "expected type of vector spread to be a ttuple, ttvector, or tbytes type but received ~a"
                                                                           (format-type type))]))]))
                                             tuple-arg*)])
           (let ([type* (apply append type**)])
             (let ([type (if (null? type*)
                             ; this case isn't exercised at present since infer-type creates vector forms only when at least
                             ; one element is a vector, and every vector type has an element type (possible tunknown)
                             `(tunknown)
                             (let ([type (car type*)])
                               (for-each (lambda (type^)
                                           (unless (sametype? type^ type)
                                             (source-errorf src "different vector element types ~a and ~a"
                                                            (format-type type)
                                                            (format-type type^))))
                                         (cdr type*))
                               type))])
               `(tvector ,src ,(apply + nat*) ,type)))))]
      [(cast-from-enum ,src ,type ,type^ ,[Care : expr -> * type^^])
       (unless (sametype? type^^ type^)
         (source-errorf src "expected ~a, got ~a for cast-from-enum"
                        (format-type type^)
                        (format-type type^^)))
       type]
      [(cast-to-enum ,src ,type ,type^ ,[Care : expr -> * type^^])
       (unless (sametype? type^^ type^)
         (source-errorf src "expected ~a, got ~a for cast-to-enum"
                        (format-type type^)
                        (format-type type^^)))
       type]
      [(cast-from-bytes ,src ,[type] ,len ,[Care : expr -> * type^])
       (nanopass-case (Lnodca Type) (de-alias type^)
         [(tbytes ,src ,len^)
          (unless (= len^ len)
            (source-errorf src "mismatch between Bytes lengths ~s and ~s for cast-from-bytes"
                           len
                           len^))]
         [else (source-errorf src "expected Bytes<~d>, got ~a for cast-from-bytes"
                              len 
                              (format-type type^))])
       type]
      [(field->bytes ,src ,len ,[Care : expr -> * type])
       (when (= len 0) (source-errorf src "invalid cast from field to Bytes<0>"))
       (unless (nanopass-case (Lnodca Type) (de-alias type)
                 [(tfield ,src) #t]
                 [else #f])
         (source-errorf src "mismatch between actual type ~a and expected type Field for field->bytes"
                        (format-type type)))
       (with-output-language (Lnodca Type) `(tbytes ,src ,len))]
      [(bytes->vector ,src ,len ,[Care : expr -> * type])
       (unless (nanopass-case (Lnodca Type) (de-alias type)
                 [(tbytes ,src ,len^) (= len^ len)]
                 [else #f])
         (source-errorf src "expected Bytes<~d> for bytes->vector call, received ~a"
                        len
                        (format-type type)))
       (with-output-language (Lnodca Type) `(tvector ,src ,len (tunsigned ,src 255)))]
      [(vector->bytes ,src ,len ,[Care : expr -> * type])
       (define (u8-subtype? type)
         (nanopass-case (Lnodca Type) (de-alias type)
           [(tunsigned ,src ,nat) (<= nat 255)]
           [(tunknown) #t]
           [else #f]))
       (unless (nanopass-case (Lnodca Type) (de-alias type)
                 [(ttuple ,src1 ,type* ...) (and (= (length type*) len) (andmap u8-subtype? type*))]
                 [(tvector ,src1 ,len1 ,type) (and (= len1 len) (u8-subtype? type))]
                 [else #f])
         (source-errorf src "expected Vector<~d, Uint<8>> for vector->bytes call, received ~a"
                        len
                        (format-type type)))
       (with-output-language (Lnodca Type) `(tbytes ,src ,len))]
      [(downcast-unsigned ,src ,nat ,[Care : expr -> * type])
       (unless (nanopass-case (Lnodca Type) (de-alias type)
                 [(tfield ,src) #t]
                 [(tunsigned ,src ,nat) #t]
                 [else #f])
         (source-errorf src "expected Uint, got ~a for downcast-unsigned"
                              (format-type type)))
       (with-output-language (Lnodca Type) `(tunsigned ,src ,nat))]
      [(safe-cast ,src ,type ,type^ ,[Care : expr -> * type^^])
       (unless (sametype? type^^ type^)
         (source-errorf src "expected ~a, got ~a for upcast"
                        (format-type type^)
                        (format-type type^^)))
       type]
      [(public-ledger ,src ,ledger-field-name ,sugar? ,accessor ,accessor* ...)
       (let loop ([accessor accessor]
                  [accessor* accessor*]
                  [adt-op* (lookup-adt-ops ledger-field-name)])
         (nanopass-case (Lnodca Ledger-Accessor) accessor
           [(,src^ ,ledger-op ,expr* ...)
            (let ([type^* (map Care expr*)])
              (let find-adt-op ([adt-op* adt-op*])
                (assert (not (null? adt-op*)))
                (nanopass-case (Lnodca ADT-Op) (car adt-op*)
                  [(,ledger-op^ ,op-class ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
                   (guard (eq? ledger-op^ ledger-op))
                   (assert (fx=? (length type*) (length type^*)))
                   (for-each
                     (lambda (type type^ i)
                       (unless (sametype? type^ type)
                         (source-errorf src "expected ~:r argument of ~s to have type ~a but received ~a"
                                        (fx1+ i)
                                        ledger-op
                                        (format-type type)
                                        (format-type type^))))
                     type* type^* (enumerate type*))
                   (if (null? accessor*)
                       type
                       (loop (car accessor*)
                             (cdr accessor*)
                             (nanopass-case (Lnodca Type) (de-alias type)
                               [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                                adt-op*]
                               [else (assert cannot-happen)])))]
                  [else (find-adt-op (cdr adt-op*))])))]))]
      ; FIXME: syntax post-desugar should require at least one accessor
      [(public-ledger ,src ,ledger-field-name ,sugar? ,accessor* ...)
       (assert cannot-happen)]
      [(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
       (nanopass-case (Lnodca Type) (de-alias type)
         [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
          (let ([actual-type* (map Care expr*)])
            (let loop ([elt-name* elt-name*] [type** type**] [type* type*])
              (if (null? elt-name*)
                (source-errorf src^ "contract ~s has no circuit declaration named ~s"
                               contract-name
                               elt-name)
                (if (eq? (car elt-name*) elt-name)
                  (let ([declared-type* (car type**)])
                    (let ([ndeclared (length declared-type*)] [nactual (length actual-type*)])
                      (unless (fx= nactual ndeclared)
                        (source-errorf src "~s.~s requires ~s argument~:*~p but received ~s"
                                       contract-name elt-name ndeclared nactual)))
                    (for-each
                      (lambda (declared-type actual-type i)
                        (unless (sametype? actual-type declared-type)
                          (source-errorf src "expected ~:r argument of ~s.~s to have type ~a but received ~a"
                                         (fx1+ i)
                                         contract-name
                                         elt-name
                                         (format-type declared-type)
                                         (format-type actual-type))))
                      declared-type* actual-type* (enumerate declared-type*))
                    (car type*))
                  (loop (cdr elt-name*) (cdr type**) (cdr type*))))))]
         [else (assert cannot-happen)])]
      [(return ,src ,[Care : expr -> * type]) type])
    (Map-Argument : Map-Argument (ir src who expected-length argno) -> * (type)
      [(,[Care : expr -> * expr-type] ,type ,type^)
       (unless (sametype? expr-type type)
         (source-errorf src "mismatch between recorded type ~a and actual type ~a for ~a argument ~d"
                        (format-type expr-type)
                        (format-type type)
                        who
                        argno))
       (let ([len (nanopass-case (Lnodca Type) (de-alias type)
                    [(ttuple ,src ,type* ...) (length type*)]
                    [(tvector ,src ,len ,type) len]
                    [(tbytes ,src ,len) len]
                    [else (assert cannot-happen)])])
         (unless (= len expected-length)
           (source-errorf src "mismatch between recorded length ~d and actual length ~d for ~a argument ~d"
                          expected-length
                          len
                          who
                          argno)))
       type^])

    )

  (define-pass check-sealed-fields : Lnodca (ir) -> Lnodca ()
    ; this pass complains if a sealed field can be modified by an exported circuit or any
    ; circuit that is reachable from an exported circuit.  we presently assume that no
    ; witnesses or external circuits can modify any sealed fields.
    (definitions
      (define-condition-type &sealed-condition &condition
        make-sealed-condition sealed-condition?
        (function-name sealed-condition-function-name)
        (src sealed-condition-src)
        (reason sealed-condition-reason))
      ; function-ht maps function names to one of:
      ;   an Lnodca Expression:  a circuit that has yet to be processed
      ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
      ;   #f:                    a processed circuit, determined not to modify any sealed fields
      ;   a sealed condition:    a processed circuit, determined to modify at least one sealed field
      (define function-ht (make-eq-hashtable))
      (define (process-circuit! a)
        (let ([function-name (car a)] [maybe-expr (cdr a)])
          (when (Lnodca-Expression? maybe-expr)
            (guard (c [(sealed-condition? c) (set-cdr! a c)]
                      [else (raise-continuable c)])
              (set-cdr! a 'inprocess-circuit)
              (Expression maybe-expr function-name)
              (set-cdr! a #f)))))
      (define (process-function-name! function-name)
        (let ([a (eq-hashtable-cell function-ht function-name #f)])
          (process-circuit! a)
          (let ([result (cdr a)])
            (assert (not (eq? result 'inprocess-circuit)))
            (when (sealed-condition? result)
              (raise-continuable result)))))
      (define (read-op? ledger-field-name accessor+)
        (let loop ([accessor+ accessor+]
                   [adt-op* (lookup-adt-ops ledger-field-name)])
          (let ([accessor (car accessor+)] [accessor* (cdr accessor+)])
            (nanopass-case (Lnodca Ledger-Accessor) accessor
              [(,src ,ledger-op ,expr* ...)
               (let find-adt-op ([adt-op* adt-op*])
                 (assert (not (null? adt-op*)))
                 (nanopass-case (Lnodca ADT-Op) (car adt-op*)
                   [(,ledger-op^ ,op-class ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
                    (guard (eq? ledger-op^ ledger-op))
                    (if (null? accessor*)
                        (eq? op-class 'read)
                        (loop accessor*
                              (nanopass-case (Lnodca Type) (de-alias type)
                                [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                                 adt-op*]
                                [else (assert cannot-happen)])))]
                   [else (find-adt-op (cdr adt-op*))]))]))))
      (module (record-adt-ops! lookup-adt-ops)
        (define ledger-ht (make-eq-hashtable))
        (define (record-one! public-binding)
          (nanopass-case (Lnodca Public-Ledger-Binding) public-binding
            [(,src ,ledger-field-name ,type)
             (nanopass-case (Lnodca Type) (de-alias type)
               [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                (hashtable-set! ledger-ht ledger-field-name adt-op*)]
               [else (assert cannot-happen)])]))
        (define (record-adt-ops! pelt)
          (nanopass-case (Lnodca Program-Element) pelt
            [(kernel-declaration ,public-binding)
             (record-one! public-binding)]
            [(public-ledger-declaration ,public-binding* ... ,lconstructor)
             (for-each record-one! public-binding*)]
            [else (void)]))
        (define (lookup-adt-ops ledger-field-name)
          (assert (hashtable-ref ledger-ht ledger-field-name #f))))
      (define (de-alias type)
        (nanopass-case (Lnodca Type) type
          [(talias ,src ,nominal? ,type-name ,type)
           (de-alias type)]
          [else type]))
    )
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each record-adt-ops! pelt*)
       (for-each record-function! pelt*)
       (for-each Program-Element pelt*)
       ir])
    (record-function! : Program-Element (ir) -> * (void)
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (eq-hashtable-set! function-ht function-name expr)]
      [else (void)])
    (Program-Element : Program-Element (ir) -> Program-Element ()
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (when (id-exported? function-name)
         (let ([a (eq-hashtable-cell function-ht function-name #f)])
           (process-circuit! a)
           (let ([result (cdr a)])
             (when (sealed-condition? result)
               (let ([offending-function-name (sealed-condition-function-name result)])
                 (if (eq? offending-function-name #f)
                     (source-errorf src "exported circuits cannot modify sealed ledger fields but ~a at ~a"
                                    (sealed-condition-reason result)
                                    (format-source-object (sealed-condition-src result)))
                     (source-errorf src "exported circuits cannot modify sealed ledger fields but ~a calls (directly or indirectly) ~a, which ~a at ~a"
                                    (id-sym function-name)
                                    (id-sym offending-function-name)
                                    (sealed-condition-reason result)
                                    (format-source-object (sealed-condition-src result)))))))))
       ir]
      [else ir])
    (Expression : Expression (ir function-name) -> Expression ()
      [(public-ledger ,src ,ledger-field-name ,sugar? ,[accessor*] ...)
       (when (id-sealed? ledger-field-name)
         (unless (read-op? ledger-field-name accessor*)
           (raise (make-sealed-condition function-name src
                    (format "modifies sealed field ~a" (id-sym ledger-field-name))))))
       ir]
      [(call ,src ,function-name ,[expr*] ...)
       (process-function-name! function-name)
       ir])
    (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
    (Function : Function (ir function-name) -> Function ()
      [(fref ,src ,function-name)
       (process-function-name! function-name)
       ir]))

  (define-pass reject-constructor-cc-calls : Lnodca (ir) -> Lnodca ()
    ; this pass raises an exception if the constructor attempts a cross-contract call
    ; TODO: later we might want to allow constructors to call pure circuits from an external contract.
    (definitions
      (define-condition-type &cc-call-condition &condition
        make-cc-call-condition cc-call-condition?
        (function-name cc-call-condition-function-name)
        (src cc-call-condition-src)
        (reason cc-call-condition-reason))
      ; function-ht maps ids (circuit names) to one of:
      ;   an Lnodca Expression:  a circuit that has yet to be processed
      ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
      ;   #f:                    a processed circuit, determined not to make any cross-contract calls
      ;   a sealed condition:    a processed circuit, determined to make at least one cross-contract call
      (define function-ht (make-eq-hashtable))
      (define (process-circuit! a)
        (let ([function-name (car a)] [maybe-expr (cdr a)])
          (when (Lnodca-Expression? maybe-expr)
            (guard (c [(cc-call-condition? c) (set-cdr! a c)]
                      [else (raise-continuable c)])
              (set-cdr! a 'inprocess-circuit)
              (Expression maybe-expr function-name)
              (set-cdr! a #f)))))
      (define (process-function-name! function-name)
        (let ([a (eq-hashtable-cell function-ht function-name #f)])
          (process-circuit! a)
          (let ([result (cdr a)])
            (assert (not (eq? result 'inprocess-circuit)))
            (when (cc-call-condition? result)
              (raise-continuable result)))))
      (define (de-alias type)
        (nanopass-case (Lnodca Type) type
          [(talias ,src ,nominal? ,type-name ,type)
           (de-alias type)]
          [else type]))
      (define (name-of-contract type)
        (nanopass-case (Lnodca Type) (de-alias type)
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
            contract-name]
          [else (assert cannot-happen)]))
    )
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each record-function-kind! pelt*)
       (for-each Program-Element pelt*)
       ir])
    (record-function-kind! : Program-Element (ir) -> * (void)
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (eq-hashtable-set! function-ht function-name expr)]
      [else (void)])
    (Program-Element : Program-Element (ir) -> Program-Element ()
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (process-circuit! (eq-hashtable-cell function-ht function-name #f))
       ir])
    (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
      [(constructor ,src (,arg* ... ) ,expr)
       (let ([a (cons #f expr)])
         (process-circuit! a)
         (let ([result (cdr a)])
           (when (cc-call-condition? result)
             (let ([offending-function-name (cc-call-condition-function-name result)])
               (if (eq? offending-function-name #f)
                   (source-errorf src "constructor cannot call external contracts but ~a at ~a"
                                  (cc-call-condition-reason result)
                                  (format-source-object (cc-call-condition-src result)))
                   (source-errorf src "constructor cannot call external contracts but calls (directly or indirectly) ~a, which ~a at ~a"
                                  (id-sym offending-function-name)
                                  (cc-call-condition-reason result)
                                  (format-source-object (cc-call-condition-src result))))))))
       ir])
    (Expression : Expression (ir function-name) -> Expression ()
      [(call ,src ,function-name^ ,[expr*] ...)
       (process-function-name! function-name^)
       ir]
      [(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
       (raise (make-cc-call-condition function-name src
                (format "calls circuit ~a from external contract ~a"
                  elt-name
                  (name-of-contract type))))])
    (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
    (Function : Function (ir function-name) -> Function ()
      [(fref ,src ,function-name)
       (process-function-name! function-name)
       ir]))

  (define-pass identify-pure-circuits : Lnodca (ir) -> Lnodca ()
    ; impure circuits are those that might touch public state, call any witnesses, or
    ; call any other impure circuits.  pure circuits are those that are not impure.
    ; we presently assume that all external circuits are pure.
    (definitions
      (define-condition-type &impure-condition &condition
        make-impure-condition impure-condition?
        (function-name impure-condition-function-name)
        (src impure-condition-src)
        (reason impure-condition-reason))
      ; function-ht maps function names to one of:
      ;   witness:               a witness
      ;   an Lnodca Expression:  a circuit that has yet to be processed
      ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
      ;   pure-circuit:          a processed circuit, determined pure
      ;   an impure condition:   a processed circuit, determined impure
      (define function-ht (make-eq-hashtable))
      (define (process-circuit! a)
        (let ([function-name (car a)] [maybe-expr (cdr a)])
          (when (Lnodca-Expression? maybe-expr)
            (guard (c [(impure-condition? c) (set-cdr! a c)]
                      [else (raise-continuable c)])
              (set-cdr! a 'inprocess-circuit)
              (Expression maybe-expr function-name)
              (set-cdr! a 'pure-circuit)))))
      (define (process-function-name! calling-function-name src function-name)
        (let ([a (eq-hashtable-cell function-ht function-name #f)])
          (process-circuit! a)
          (let ([result (cdr a)])
            (cond
              [(eq? result 'pure-circuit) (void)]
              [(eq? result 'witness)
               (raise (make-impure-condition calling-function-name src
                        (format "calls witness ~s" (id-sym function-name))))]
              [(eq? result 'impure-external)
               (raise (make-impure-condition calling-function-name src
                        (format "calls impure external ~s" (id-sym function-name))))]
              [(impure-condition? result) (raise-continuable result)]
              [(eq? result 'inprocess-circuit) (assert cannot-happen)] ; should have been caught by reject-recursive-circuits
              [else (assert cannot-happen)]))))
      (define (de-alias type)
        (nanopass-case (Lnodca Type) type
          [(talias ,src ,nominal? ,type-name ,type)
           (de-alias type)]
          [else type]))
    )
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each record-function-kind! pelt*)
       (for-each Program-Element pelt*)
       ir])
    (record-function-kind! : Program-Element (ir) -> * (void)
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (eq-hashtable-set! function-ht function-name expr)]
      [(external ,src ,function-name ,native-entry (,arg* ...) ,type)
       (eq-hashtable-set! function-ht function-name
         (if (eq? (native-entry-class native-entry) 'witness)
             'impure-external
             (begin
               (id-pure?-set! function-name #t)
               'pure-circuit)))]
      [(witness ,src ,function-name (,arg* ...) ,type)
       (eq-hashtable-set! function-ht function-name 'witness)]
      [,kdecl (void)]
      [,ldecl (void)]
      [,export-tdefn (void)]
      [else (assert cannot-happen)])
    (Program-Element : Program-Element (ir) -> Program-Element ()
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (let ([a (eq-hashtable-cell function-ht function-name #f)])
         (process-circuit! a)
         (let ([result (cdr a)])
           (cond
             [(eq? result 'pure-circuit)
              (id-pure?-set! function-name #t)]
             [(impure-condition? result)
              (when (id-pure? function-name)
                (let ([offending-function-name (impure-condition-function-name result)])
                  (if (eq? offending-function-name function-name)
                      (source-errorf src "circuit ~a is marked pure but is actually impure because it ~a at ~a"
                                     (id-sym function-name)
                                     (impure-condition-reason result)
                                     (format-source-object (impure-condition-src result)))
                      (source-errorf src "circuit ~a is marked pure but is actually impure because it calls (directly or indirectly) impure circuit ~a;\
                                         \n    ~:*~a is impure because it ~a at ~a"
                                         (id-sym function-name)
                                         (id-sym offending-function-name)
                                         (impure-condition-reason result)
                                         (format-source-object (impure-condition-src result))))))]
             [else (assert cannot-happen)])))
       ir]
      [else ir])
    (Expression : Expression (ir function-name) -> Expression ()
      [(public-ledger ,src ,ledger-field-name ,sugar? ,accessor* ...)
       (raise (make-impure-condition function-name src
                (format "accesses ledger field ~s" (id-sym ledger-field-name))))]
      [(call ,src ,function-name^ ,[expr*] ...)
       (process-function-name! function-name src function-name^)
       ir]
      [(contract-call ,src ,elt-name (,expr ,type) ,[expr*] ...)
       (nanopass-case (Lnodca Type) (de-alias type)
         [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
          (let loop ([elt-name* elt-name*] [pure-dcl* pure-dcl*])
            (when (null? elt-name*) (assert cannot-happen))
            (if (eq? (car elt-name*) elt-name)
                (if (car pure-dcl*)
                    ir
                    (raise (make-impure-condition function-name src
                             (format "calls impure circuit ~a of external contract ~a"
                               elt-name
                               contract-name))))
                (loop (cdr elt-name*) (cdr pure-dcl*))))]
         [else (assert cannot-happen)])])
    (Tuple-Argument : Tuple-Argument (ir function-name) -> Tuple-Argument ())
    (Map-Argument : Map-Argument (ir function-name) -> Map-Argument ())
    (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
    (Function : Function (ir function-name) -> Function ()
      [(fref ,src ,function-name^)
       (process-function-name! function-name src function-name^)
       ir]))

  (define-pass determine-ledger-paths : Lnodca (ir) -> Lwithpaths0 ()
    (Kernel-Declaration : Kernel-Declaration (ir) -> Kernel-Declaration ()
      [(kernel-declaration ,public-binding)
       `(kernel-declaration ,(Public-Ledger-Binding public-binding '()))])
    (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ()
      (definitions
        (define (batch k x*)
          (let f ([x* x*] [n (length x*)])
            (if (fx<= n k)
              x*
              (let-values ([(q r) (div-and-mod n k)])
                (let ([x** (let g ([x* (list-tail x* r)] [n (fx- n r)])
                             (if (fx= n k)
                                 (list x*)
                                 (cons (list-head x* k)
                                       (g (list-tail x* k) (fx- n k)))))])
                  (if (fx= r 0)
                      (f x** q)
                      (f (cons (list-head x* r) x**) (fx+ q 1)))))))))
      [(public-ledger-declaration ,public-binding* ... ,[lconstructor])
       `(public-ledger-declaration
          ,(let f ([pbtree (batch maximum-ledger-segment-length public-binding*)]
                   [ridx* '()])
             (if (list? pbtree)
                 `(public-ledger-array
                    ,(map (lambda (pbtree i) (f pbtree (cons i ridx*)))
                        pbtree
                        (enumerate pbtree))
                    ...)
                 (Public-Ledger-Binding pbtree (reverse ridx*))))
          ,lconstructor)])
    (Public-Ledger-Binding : Public-Ledger-Binding (ir idx*) -> Public-Ledger-Binding ()
      [(,src ,ledger-field-name ,[type])
       `(,src ,ledger-field-name (,idx* ...) ,type)]))

  ; FIXME: building in knowledge of the ledger here
  (define-pass propagate-ledger-paths : Lwithpaths0 (ir) -> Lwithpaths ()
    (definitions
      (module (memoize)
        (define $memoize
          (let ([ht (make-eq-hashtable)])
            (lambda (ir th)
              (let ([a (eq-hashtable-cell ht ir #f)])
                (or (cdr a)
                    (let ([v (th)])
                      (set-cdr! a v)
                      v))))))
        (define-syntax memoize
          (syntax-rules ()
            [(_ ir e) ($memoize ir (lambda () e))])))
      (module (record-ledger-binding! lookup-ledger-binding)
        (define ledger-ht (make-eq-hashtable))
        (define (check-adt-nesting! type)
          (nanopass-case (Lwithpaths Type) (de-alias type)
            [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
             (for-each
               (lambda (adt-arg)
                 (nanopass-case (Lwithpaths Public-Ledger-ADT-Arg) adt-arg
                   [,type
                    (nanopass-case (Lwithpaths Type) (de-alias type)
                      [(tadt ,src ,adt-name^ ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                       (unless (eq? adt-name 'Map)
                         ; this should already be ruled out by the ledger meta-type checks
                         (source-errorf src "ADT nesting is permitted only within Map ADTs"))
                       (when (eq? adt-name^ 'Kernel)
                         (source-errorf src "cannot nest ~s ADTs within another ADT" adt-name^))
                       (check-adt-nesting! type)]
                      [else (void)])]
                   [else (void)]))
               adt-arg*)]))
        (define (record-one! public-binding)
          (nanopass-case (Lwithpaths0 Public-Ledger-Binding) public-binding
            [(,src ,ledger-field-name (,path-index* ...) ,[Type : type])
             (check-adt-nesting! type)
             (hashtable-set! ledger-ht ledger-field-name (list (de-alias type) path-index*))]))
        (define (record-ledger-binding! pelt)
          (nanopass-case (Lwithpaths0 Program-Element) pelt
            [(kernel-declaration ,public-binding)
             (record-one! public-binding)]
            [(public-ledger-declaration ,pl-array ,lconstructor)
             (let f ([pl-array pl-array])
               (nanopass-case (Lwithpaths0 Public-Ledger-Array) pl-array
                 [(public-ledger-array ,pl-array-elt* ...)
                  (for-each
                    (lambda (pl-array-elt)
                      (nanopass-case (Lwithpaths0 Public-Ledger-Array-Element) pl-array-elt
                        [,pl-array (f pl-array)]
                        [,public-binding (record-one! public-binding)]))
                    pl-array-elt*)]))]
            [else (void)]))
        (define (lookup-ledger-binding ledger-field-name)
          (assert (hashtable-ref ledger-ht ledger-field-name #f))))
      (define (de-alias type)
        (nanopass-case (Lwithpaths Type) type
          [(talias ,src ,nominal? ,type-name ,type)
           (de-alias type)]
          [else type]))
      (define (public-adt? type)
        (nanopass-case (Lwithpaths Type) (de-alias type)
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #t]
          [else #f]))
      )
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each record-ledger-binding! pelt*)
       `(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,(map Program-Element pelt*) ...)])
    (Program-Element : Program-Element (ir) -> Program-Element ())
    (Type : Type (ir) -> Type ()
      [(tadt ,src ,adt-name ((,adt-formal* ,[adt-arg*]) ...) ,vm-expr (,adt-op* ...) (,[adt-rt-op*] ...))
       (memoize ir
         (let ([adt-op* (map (lambda (adt-op) (ADT-Op adt-op adt-name adt-formal* adt-arg*)) adt-op*)])
           `(tadt ,src ,adt-name ((,adt-formal* ,adt-arg*) ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))))])
    (ADT-Op : ADT-Op (ir adt-name adt-formal* adt-arg*) -> ADT-Op ()
      [(,ledger-op ,[op-class] ((,var-name* ,[type*] ,discloses?*) ...) ,[type] ,vm-code)
       `(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)])
    (ADT-Op-Class : ADT-Op-Class (ir) -> ADT-Op-Class ())
    (Expr : Expression (ir) -> Expression ()
      (definitions
        (define (bind-if-complex src expr* type* k)
          (define (complex? expr)
            (nanopass-case (Lwithpaths Expression) expr
              [(quote ,src ,datum) #f]
              [(var-ref ,src ,var-name) #f]
              [(enum-ref ,src ,type ,elt-name^) #f]
              [(default ,src ,type)
               (nanopass-case (Lwithpaths Type) (de-alias type)
                 [(tboolean ,src) #f]
                 [(tfield ,src) #f]
                 [(tunsigned ,src ,nat) #f]
                 [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) #f]
                 [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #f]
                 [else #t])]
              [(disclose ,src ,expr) (complex? expr)]
              [else #t]))
          (let f ([expr* expr*] [type* type*] [rexpr* '()])
            (if (null? expr*)
                (k (reverse rexpr*))
                (let ([expr (car expr*)] [expr* (cdr expr*)])
                  (if (complex? expr)
                      (let ([var-name (make-temp-id src 'tmp)])
                        (with-output-language (Lwithpaths Expression)
                          `(let* ,src ([(,var-name ,(car type*)) ,expr])
                             ,(f expr* (cdr type*) (cons `(var-ref ,src ,var-name) rexpr*)))))
                      (f expr* (cdr type*) (cons expr rexpr*))))))))
      [(public-ledger ,src ,ledger-field-name ,sugar? ,accessor ,accessor* ...)
       (let-values ([(public-adt path-index*) (apply values (lookup-ledger-binding ledger-field-name))])
         (let loop ([accessor accessor]
                    [accessor* accessor*]
                    [public-adt public-adt]
                    [rpath-src* '()]
                    [rpath-expr* '()]
                    [rpath-type* '()])
           (nanopass-case (Lwithpaths0 Ledger-Accessor) accessor
             [(,src^ ,ledger-op ,expr* ...)
              (let ([expr* (map Expr expr*)])
                (nanopass-case (Lwithpaths Type) (de-alias public-adt)
                  [(tadt ,src^^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                   (let find-adt-op ([adt-op* adt-op*])
                     (assert (not (null? adt-op*)))
                     (let ([adt-op (car adt-op*)] [adt-op* (cdr adt-op*)])
                       (nanopass-case (Lwithpaths ADT-Op) adt-op
                         [(,ledger-op^ ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
                          (if (eq? ledger-op^ ledger-op)
                              (begin
                                (assert (fx= (length type*) (length expr*)))
                                (if (null? accessor*)
                                    (let ([path-src* (reverse rpath-src*)]
                                          [path-expr* (reverse rpath-expr*)]
                                          [path-type* (reverse rpath-type*)])
                                      (bind-if-complex src expr* type*
                                        (lambda (expr*)
                                          (bind-if-complex src path-expr* path-type*
                                            (lambda (path-expr*)
                                              `(public-ledger ,src ,ledger-field-name ,sugar? (,path-index* ... (,path-src* ,path-type* ,path-expr*) ...) ,src^ ,adt-op ,expr* ...))))))
                                    (begin
                                      ; nothing but Map should have gotten past check-adt-nesting!
                                      (assert (eq? adt-name 'Map))
                                      ; nothing but lookup with one argument (the key) should have gotten past the type checker
                                      (assert (and (eq? ledger-op 'lookup) (fx= (length expr*) 1)))
                                      ; and the only element of type* should be a base type
                                      (assert (not (public-adt? (car type*))))
                                      ; and since we're nested, nothing but a public-adt return type should have gotten past the type checker
                                      (assert (public-adt? type))
                                      (loop (car accessor*)
                                            (cdr accessor*)
                                            type
                                            (cons src^ rpath-src*)
                                            (cons (car expr*) rpath-expr*)
                                            (cons (car type*) rpath-type*)))))
                              (find-adt-op adt-op*))])))]))])))]))

  (define-pass track-witness-data : Lwithpaths (ir) -> Lwithpaths ()
    ; track-witness-data is the so-called "witness-protection program" or WPP for short
    ; that enforces explicit disclosure of witness values, i.e., values that come into a
    ; contract via the constructor, exported circuit arguments, or witness return values
    ; and are possibly disclosed (leaked) into the public ledger or (in the case of
    ; witness return values only) into the output of an exported circuit.
    (definitions
      ; the WPP is implemented as an abstract interpreter, and instances of the Abs datatype
      ; represent abstract values.
      ; invariant: each witness* is sorted by uid with no duplicates.
      ; struct and tuple fields are tracked individually; array elements are tracked in the aggregate
      (define-datatype Abs
        (Abs-atomic witness*)
        (Abs-boolean true? witness*)
        (Abs-multiple abs*)
        (Abs-single abs))

      ; witness record instances represent witness values
      (define-record-type witness
        (nongenerative)
        ; src is the location where a witness value enters the contract
        ; src already distinguishes witnesses; the uid serves as an inexpensive sorting key and hash value
        ; info is instance of a Witness-Info datatype
        ; a path is simply a list pp* of path points; path* is a sorted nonempty list of paths without duplicates
        ; two witness records can have the same src, uid, and info but different path*
        (fields src uid info path*)
        (protocol
          (lambda (new)
            (case-lambda
              [(src uid info) (new src uid info '(()))]
              [(src uid info path*)
               (assert (not (null? path*)))
               ; maintain invariant: path* is always sorted according to path<? and has no duplicates
               (let ([path* (let ([path* (sort path<? path*)])
                              (let loop ([path (car path*)] [path* (cdr path*)])
                                (if (null? path*)
                                    (list path)
                                    (let ([path^ (car path*)] [path* (cdr path*)])
                                      (if (same-path? path^ path)
                                          (loop path path*)
                                          (cons path (loop path^ path*)))))))])
                 (new src uid info path*))]))))

      (define-datatype Witness-Info
        (Witness-Return-Value function-name)
        (Constructor-Argument argument-name)
        (Circuit-Argument function-name argument-name))

      ; path point represents some interesting point along a data-flow path through the contract
      (define-record-type path-point
        (nongenerative)
        ; src is the location of the point
        ; description is a string describing the point, e.g., "the argument of transientHash"
        ; exposure is a string describing the conversion, if any, made at the point, e.g., "a hash of",
        ; and is "" if the point simply passes the unmodified witness value along
        (fields src description exposure))

      ; instances of the Fun datatype represent the different kinds of functions
      (define-datatype Fun
        (Fun-circuit src name var-name* expr uid)
        (Fun-witness abs)
        (Fun-external disclosure?* type))

      ; instances of the Cell datatype represent different stages in the processing of a function call
      (define-datatype Call
        (Call-unprocessed)
        (Call-inprocess)
        (Call-processed abs))

      #|
      ; printing of abstract values, witnesses, and paths for debugging
      (module (print-abs)
        (define (indent op i) (unless (fx= i 0) (fprintf op "~vs" (fx* i 2) i)))
        (define (print-info op i info)
          (indent op i)
          (Witness-Info-case info
            [(Witness-Return-Value function-name)
             (fprintf op "Witness-Return-Value ~s\n" (id-sym function-name))]
            [(Constructor-Argument argument-name)
             (fprintf op "Constructor-Argument ~s\n" (id-sym argument-name))]
            [(Circuit-Argument function-name argument-name)
             (fprintf op "Circuit-Argument ~s ~s\n" (id-sym function-name) (id-sym argument-name))]))
        (define (print-description op i description)
          (indent op i)
          (fprintf op "~a\n" description))
        (define (print-exposure op i exposure)
          (indent op i)
          (fprintf op "~a\n" exposure))
        (define (print-path-point op i pp)
          (indent op i)
          (fprintf op "path-point ~a:\n" (format-source-object (path-point-src pp)))
          (print-description op (fx+ i 1) (path-point-description pp))
          (print-exposure op (fx+ i 1) (path-point-exposure pp)))
        (define (print-path op i pp*)
          (for-each
            (lambda (pp) (print-path-point op i pp))
            pp*))
        (define (print-paths op i path*)
          (for-each
            (lambda (pp* n)
              (indent op i)
              (fprintf op "path ~d (length ~d):\n" n (length pp*))
              (print-path op (fx+ i 1) pp*))
            path*
            (enumerate path*)))
        (define (print-witness op i witness)
          (indent op i)
          (fprintf op "witness ~d ~a:\n" (witness-uid witness) (format-source-object (witness-src witness)))
          (print-info op (fx+ i 1) (witness-info witness))
          (print-paths op (fx+ i 1) (witness-path* witness)))
        (define (print-abs op i abs)
          (indent op i)
          (Abs-case abs
            [(Abs-atomic witness*)
             (fprintf op "Abs-atomic:\n")
             (for-each (lambda (witness) (print-witness op (fx+ i 1) witness)) witness*)]
            [(Abs-boolean true? witness*)
             (fprintf op "Abs-boolean ~a:\n" true?)
             (for-each (lambda (witness) (print-witness op (fx+ i 1) witness)) witness*)]
            [(Abs-multiple abs*)
             (fprintf op "Abs-multiple:\n")
             (for-each (lambda (abs) (print-abs op (fx+ i 1) abs)) abs*)]
            [(Abs-single abs)
             (fprintf op "Abs-single:\n")
             (print-abs op (fx+ i 1) abs)])))
      |#

      (define (uid-generator)
        (let ([uid 0])
          (lambda ()
            (set! uid (fx+ uid 1))
            uid)))

      (define next-circuit-uid (uid-generator))
      (define next-witness-uid (uid-generator))

      ; function-ht: function name => Fun record
      (define function-ht (make-eq-hashtable))

      ; for purposes of path points, all standard library routines are treated as if they have
      ; the same source location
      (define (same-ppsrc? src1 src2)
        (or (eq? src1 src2)
            (and (stdlib-src? src1) (stdlib-src? src2))))

      (define (ppsrc<? src1 src2)
        (and (not (eq? src1 src2))
             (not (stdlib-src? src1))
             (or (stdlib-src? src2)
                 (source-object<? src1 src2))))

      ; add-path-point returns a new abs created adding by a new path point to the
      ; paths of every witness contained within abs.  if the new path point is the same
      ; as one already in a path, it is not added to the path.  this leads to faster
      ; convergence of abstract values to fixed points.  it also leads to simpler though
      ; less accurate error messages like "a hash of" instead of "a hash of a hash of
      ; a hash of ...".
      (define (add-path-point src description exposure abs)
        ; if a standard library program point doesn't expose anything, there's nothing interesting
        ; to say about it, so we drop it.
        (if (and (equal? exposure "") (stdlib-src? src))
            abs
            (let ()
              (define add-to-path
                (let ([new-pp (make-path-point src description exposure)])
                  (lambda (pp*)
                    (if (ormap (lambda (pp)
                                 (and (same-ppsrc? (path-point-src pp) src)
                                      (string=? (path-point-description pp) description)
                                      (string=? (path-point-exposure pp) exposure)))
                               pp*)
                        pp*
                        (cons new-pp pp*)))))
              (define (add-to-witness witness)
                (make-witness
                  (witness-src witness)
                  (witness-uid witness)
                  (witness-info witness)
                  (map add-to-path (witness-path* witness))))
              (let add-path-point ([abs abs])
                (Abs-case abs
                  [(Abs-atomic witness*) (Abs-atomic (map add-to-witness witness*))]
                  [(Abs-boolean true? witness*) (Abs-boolean true? (map add-to-witness witness*))]
                  [(Abs-multiple abs*) (Abs-multiple (map add-path-point abs*))]
                  [(Abs-single abs) (Abs-single (add-path-point abs))])))))

      (define (add-path-binding var-name abs)
        (if (id-temp? var-name)
            abs
            (add-path-point (id-src var-name) (format "the binding of ~a" (id-sym var-name)) "" abs)))

      (define (same-path-point? pp1 pp2)
        (and (same-ppsrc? (path-point-src pp1) (path-point-src pp2))
             (string=? (path-point-description pp1) (path-point-description pp2))
             (string=? (path-point-exposure pp1) (path-point-exposure pp2))))

      (define (same-path? pp1* pp2*)
        (and (fx= (length pp1*) (length pp2*))
             ; paths are ordered and so are equivalent only if pairwise equivalent
             (andmap same-path-point? pp1* pp2*)))

      (define (same-paths? path1* path2*)
        (and (fx= (length path1*) (length path2*))
             ; path lists are sorted and so are equivalent only if pairwise equivalent
             (andmap same-path? path1* path2*)))

      ; NB: list<? treats any shorter list as less than any longer list.  this is
      ; useful for sorting paths and vias (with more direct problems first) and is more
      ; efficient when the list lengths differ and the comparisons are expensive.
      ;
      ; elt-compare should take two arguments and return one of <, >, or = depending on
      ; whether the first argument is <, >, or = to the second.  list<? could be written
      ; to use a simple #t/#f less-than predicate, but it would have to call it twice
      ; for every list element, which would be more expensive for expensive comparisons.
      (define (list<? elt-compare x1* x2*)
        (let ([n1 (length x1*)] [n2 (length x2*)])
          (or (fx< n1 n2)
              (and (fx= n1 n2)
                   (let loop ([x1* x1*] [x2* x2*])
                     (and (not (null? x1*))
                          (let ([x1 (car x1*)] [x2 (car x2*)])
                            (case (elt-compare (car x1*) (car x2*))
                              [(<) #t]
                              [(>) #f]
                              [else (loop (cdr x1*) (cdr x2*))]))))))))

      (define (string-compare s1 s2)
        (cond
          [(string=? s1 s2) '=]
          [(string<? s1 s2) '<]
          [else '>]))

      (define (path<? pp1* pp2*)
        (define (pp-compare pp1 pp2)
          (let ([src1 (path-point-src pp1)] [src2 (path-point-src pp2)])
            (cond
              [(ppsrc<? src1 src2) '<]
              [(ppsrc<? src2 src1) '>]
              [else (case (string-compare (path-point-exposure pp1) (path-point-exposure pp2))
                      [(<) '<]
                      [(>) '>]
                      [else (string-compare (path-point-description pp1) (path-point-description pp2))])])))
        (list<? pp-compare pp1* pp2*))

      (define (merge-witnesses witness1* witness2*)
        ; invariant: witness1* and witness2* are sorted and have no duplicates
        (cond
          [(null? witness1*) witness2*]
          [(null? witness2*) witness1*]
          [else
           (let ([witness1 (car witness1*)] [witness2 (car witness2*)])
             (if (eq? witness1 witness2)
                 (cons witness1 (merge-witnesses (cdr witness1*) (cdr witness2*)))
                 (let ([uid1 (witness-uid witness1)] [uid2 (witness-uid witness2)]) 
                   (cond
                     [(fx= uid1 uid2)
                      (cons (let ([path1* (witness-path* witness1)] [path2* (witness-path* witness2)])
                              (make-witness
                                (witness-src witness1)
                                uid1
                                (witness-info witness1)
                                (append path1* path2*)))
                            (merge-witnesses (cdr witness1*) (cdr witness2*)))]
                     [(fx< uid1 uid2) (cons witness1 (merge-witnesses (cdr witness1*) witness2*))]
                     [else (cons witness2 (merge-witnesses witness1* (cdr witness2*)))]))))]))

      (define (abs->witnesses abs)
        (Abs-case abs
          [(Abs-atomic witness*) witness*]
          [(Abs-boolean true? witness*) witness*]
          [(Abs-multiple abs*) (fold-left merge-witnesses '() (map abs->witnesses abs*))]
          [(Abs-single abs) (abs->witnesses abs)]))

      (define (same-witnesses? witness1* witness2*)
        (and (fx= (length witness1*) (length witness2*))
             (andmap (lambda (witness1 witness2)
                       (or (eq? witness1 witness2)
                           (and (fx= (witness-uid witness1) (witness-uid witness2))
                                (same-paths? (witness-path* witness1) (witness-path* witness2))
                                (same-witnesses? (cdr witness1*) (cdr witness2*)))))
                     witness1*
                     witness2*)))

      (define (abs-equal? abs1 abs2)
        (Abs-case abs1
          [(Abs-atomic witness1*)
           (Abs-case abs2
             [(Abs-atomic witness2*) (same-witnesses? witness1* witness2*)]
             [else #f])]
          [(Abs-boolean true1? witness1*)
           (Abs-case abs2
             [(Abs-boolean true2? witness2*) (and (eq? true1? true2?) (same-witnesses? witness1* witness2*))]
             [else #f])]
          [(Abs-multiple abs1*)
           (Abs-case abs2
             [(Abs-multiple abs2*) (andmap abs-equal? abs1* abs2*)]
             [else #f])]
          [(Abs-single abs1)
           (Abs-case abs2
             [(Abs-single abs2) (abs-equal? abs1 abs2)]
             [else #f])]))

      (define (combine-abs abs1 abs2)
        ; invariant: abs1 and abs2 have the same shape (both structs, both arrays, or both atomic)
        ; combine-abs is used to combine abstract values of values that have identical types, e.g.,
        ; the consequent and alternative of a conditional, the arguments of an arithetic operator,
        ; or the elements of a vector.
        (Abs-case abs1
          [(Abs-atomic witness1*)
           (Abs-case abs2
             [(Abs-atomic witness2*) (Abs-atomic (merge-witnesses witness1* witness2*))]
             [(Abs-boolean true2? witness2*) (Abs-atomic (merge-witnesses witness1* witness2*))]
             [else (assert cannot-happen)])]
          [(Abs-boolean true1? witness1*)
           (Abs-case abs2
             [(Abs-atomic witness2*) (Abs-atomic (merge-witnesses witness1* witness2*))]
             [(Abs-boolean true2? witness2*)
              (if (eq? true2? true1?)
                  (Abs-boolean true1? (merge-witnesses witness1* witness2*))
                  (Abs-atomic (merge-witnesses witness1* witness2*)))]
             [else (assert cannot-happen)])]
          [(Abs-multiple abs1*)
           (Abs-case abs2
             [(Abs-multiple abs2*) (Abs-multiple (map combine-abs abs1* abs2*))]
             [(Abs-single abs2) (Abs-multiple (map (lambda (abs1) (combine-abs abs1 abs2)) abs1*))]
             [else (assert cannot-happen)])]
          [(Abs-single abs1)
           (Abs-case abs2
             [(Abs-multiple abs2*) (Abs-multiple (map (lambda (abs2) (combine-abs abs1 abs2)) abs2*))]
             [(Abs-single abs2) (Abs-single (combine-abs abs1 abs2))]
             [else (assert cannot-happen)])]))

      (module (call-ht-cell)
        (define-record-type key
          (nongenerative)
          (fields uid abs* control-witness*))
        (define (key-hash key)
          (define (combine hash1 hash2)
            (bitwise-and
              (most-positive-fixnum)
              (+ (ash hash1 1) hash2)))
          (define (combine-many hash hash*)
            (fold-left combine hash hash*))
          (define (abs-hash abs)
            (Abs-case abs
              [(Abs-atomic witness*) (combine-many 1 (map witness-uid witness*))]
              [(Abs-boolean true? witness*) (combine-many 2 (map witness-uid witness*))]
              [(Abs-multiple abs*) (combine-many 3 (map abs-hash abs*))]
              [(Abs-single abs) (combine 4 (abs-hash abs))]))
          (combine-many
            (combine-many (key-uid key) (map abs-hash (key-abs* key)))
            (map witness-uid (key-control-witness* key))))
        (define (key-equal? key1 key2)
          (and (eqv? (key-uid key1) (key-uid key2))
               (andmap abs-equal? (key-abs* key1) (key-abs* key2))
               (and (same-witnesses? (key-control-witness* key1) (key-control-witness* key2)))))
        (define call-ht (make-hashtable key-hash key-equal?))
        (define (call-ht-cell uid abs* control-witness*)
          (hashtable-cell call-ht (make-key uid abs* control-witness*) (Call-unprocessed))))

      (module (empty-env extend-env lookup-env)
        (define empty-env '())
        (define (extend-env p var-name* abs*)
          (cons (map cons var-name* abs*) p))
        (define (lookup-env p var-name)
          (let f ([p p])
            (assert (not (eq? p '())))
            (cond
              [(assq var-name (car p)) => cdr]
              [else (f (cdr p))]))))

      (define (handle-call src? function-name abs* control-witness* return-value-discloses?)
        (let ([fun (hashtable-ref function-ht function-name #f)])
          (assert fun)
          (Fun-case fun
            [(Fun-circuit src name var-name* expr uid)
             (let ([a (call-ht-cell uid abs* control-witness*)])
               (or (Call-case (cdr a)
                     [(Call-processed abs)
                      ; when return-value-discloses? is true, we need to reprocess to report return-value leaks,
                      ; because the first time through will have been in service of some other circuit or the
                      ; constructor body and will not have reported return-value leaks
                      (and (not return-value-discloses?) abs)]
                     [(Call-unprocessed) #f]
                     [(Call-inprocess) (assert cannot-happen)])
                   (begin
                     (assert (= (length var-name*) (length abs*)))
                     (set-cdr! a (Call-inprocess))
                     (let ([abs (let ([abs* (if src?
                                                (map (lambda (abs i?)
                                                       (add-path-point
                                                         src?
                                                         (format "the ~@[~:r ~]argument to ~a" (and i? (fx+ i? 1)) (id-sym function-name))
                                                         ""
                                                         abs))
                                                     abs*
                                                     (if (= (length abs*) 1) '(#f) (enumerate abs*)))
                                                abs*)])
                                  (define (go)
                                    (Expression
                                      expr
                                      (extend-env empty-env var-name* abs*)
                                      control-witness*
                                      (and return-value-discloses? function-name)))
                                  (if (and src? (not (stdlib-src? src?)) (stdlib-src? (id-src function-name)))
                                      (fluid-let ([record-leak!
                                                   (let ([record-leak! record-leak!])
                                                     (lambda (ignore-src ignore-what witness)
                                                       (record-leak! src? (format "the call to standard-library circuit ~a" (id-sym function-name)) witness)))])
                                        (go))
                                      (go)))])
                       (set-cdr! a (Call-processed abs))
                       abs))))]
            [(Fun-witness abs) abs]
            [(Fun-external disclosure?* type)
             (assert (fx= (length disclosure?*) (length abs*)))
             (default-value type
               (fold-left
                 (lambda (witness* abs disclosure? i?)
                   (if disclosure?
                       (merge-witnesses
                         (abs->witnesses (if src? (add-path-point src? (format "the ~@[~:r ~]argument to ~a" (and i? (fx+ i? 1)) (id-sym function-name)) disclosure? abs) abs))
                         witness*)
                       witness*))
                 '()
                 abs*
                 disclosure?*
                 (if (= (length abs*) 1) '(#f) (enumerate abs*))))])))

      (define default-value
        (case-lambda
          [(type) (default-value type '())]
          [(type witness*)
           (let default-value ([type type])
             (nanopass-case (Lwithpaths Type) type
               [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                (Abs-multiple (map default-value type*))]
               [(ttuple ,src ,type* ...)
                (Abs-multiple (map default-value type*))]
               [(tvector ,src ,len ,type)
                (Abs-single (default-value type))]
               [(talias ,src ,nominal? ,type-name ,type) (default-value type)]
               [else (Abs-atomic witness*)]))]))

      (define (add-witnesses additional-witness* abs)
        (let add-witnesss ([abs abs])
          (Abs-case abs
            [(Abs-atomic witness*) (Abs-atomic (merge-witnesses additional-witness* witness*))]
            [(Abs-boolean true? witness*) (Abs-boolean true? (merge-witnesses additional-witness* witness*))]
            [(Abs-multiple abs*) (Abs-multiple (map add-witnesss abs*))]
            [(Abs-single abs) (Abs-single (add-witnesss abs))])))

      (define (disclose abs)
        (Abs-case abs
          [(Abs-atomic witness*) (Abs-atomic '())]
          [(Abs-boolean true? witness*) (Abs-boolean true? '())]
          [(Abs-multiple abs*) (Abs-multiple (map disclose abs*))]
          [(Abs-single abs) (Abs-single (disclose abs))]))

      (module (record-leak! get-leaks)
        (define (source-object-hash src)
          (+ (source-file-descriptor-checksum (source-object-sfd src))
             (source-object-bfp src)
             (* (source-object-efp src) 5)))
        (define leak-table (make-hashtable (lambda (x) (+ (source-object-hash (car x)) (string-hash (cdr x)))) equal?))
        (define (record-leak! src what witness*)
          (hashtable-update! leak-table (cons src what)
            (lambda (witness0*) (merge-witnesses witness* witness0*))
            '()))
        (define (get-leaks)
          (let-values ([(vkey vval) (hashtable-entries leak-table)])
            (vector-sort
              (lambda (key1 key2)
                (or (source-object<? (car key1) (car key2))
                    (and (not (source-object<? (car key2) (car key1)))
                         (string<? (cadr key1) (cadr key2)))))
              (vector-map (lambda (key val) (list (car key) (cdr key) val)) vkey vval)))))

      (define (complain src what witness*)
        (define-record-type via
          (nongenerative)
          (fields desc* exposure))
        (define (via<? via1 via2)
          (let ([n1 (string-length (via-exposure via1))]
                [n2 (string-length (via-exposure via2))])
            (or (fx< n1 n2)
                (and (fx= n1 n2)
                     (or (string<? (via-exposure via1) (via-exposure via2))
                         (and (not (string<? (via-exposure via1) (via-exposure via2)))
                              (let ([n1 (length (via-desc* via1))]
                                    [n2 (length (via-desc* via2))])
                                (or (fx< n1 n2)
                                    (and (fx= n1 n2)
                                         (list<? string-compare (via-desc* via1) (via-desc* via2)))))))))))
        (parameterize ([parent-src src])
          (for-each
            (lambda (witness)
              (let ([witness-value (let ([where (format-source-object (witness-src witness))])
                                     (Witness-Info-case (witness-info witness)
                                       [(Witness-Return-Value function-name)
                                        (format "the return value of witness ~a at ~a"
                                          (id-sym function-name)
                                          where)]
                                       [(Constructor-Argument argument-name)
                                        (format "the value of parameter ~a of the constructor at ~a"
                                          (id-sym argument-name)
                                          where)]
                                       [(Circuit-Argument function-name argument-name)
                                        (format "the value of parameter ~a of exported circuit ~a at ~a"
                                          (id-sym argument-name)
                                          (id-sym function-name)
                                          where)]))]
                    [via* (sort via<?
                                (map (lambda (pp*)
                                       (make-via
                                         (fold-right
                                           (lambda (pp desc*)
                                             (let ([src (path-point-src pp)])
                                               (if (stdlib-src? src)
                                                   desc*
                                                   (cons (format "~a at ~a"
                                                           (path-point-description pp)
                                                           (format-source-object src))
                                                         desc*))))
                                           '()
                                           pp*)
                                         (fold-right
                                           (lambda (pp exposure)
                                             (let ([exposure^ (path-point-exposure pp)])
                                               (if (equal? exposure^ "")
                                                   exposure
                                                   (format "~a ~a" exposure^ exposure))))
                                           "the witness value"
                                           pp*)))
                                     (witness-path* witness)))])
                (pending-errorf src
                  "potential witness-value disclosure must be declared but is not:\n    witness value potentially disclosed:\n      ~a~{~a~}"
                  witness-value
                  (map (lambda (via)
                         (format "\n    nature of the disclosure:\n      ~a might disclose ~a~@[\n    via this path through the program:~{\n      ~a~}~]"
                           what
                           (via-exposure via)
                           (let ([desc* (via-desc* via)])
                             (and (not (null? desc*))
                                  (reverse desc*)))))
                       via*))))
            ; witnesses are sorted by uid.  resort by source position for the error message.
            (sort
              (lambda (w1 w2) (source-object<? (witness-src w1) (witness-src w2)))
              witness*))))

      (define (de-alias type)
        (nanopass-case (Lwithpaths Type) type
          [(talias ,src ,nominal? ,type-name ,type)
           (de-alias type)]
          [else type]))
    )
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each record-function-kind! pelt*)
       (for-each Program-Element pelt*)
       (vector-for-each
         (lambda (leak) (apply complain leak))
         (get-leaks))
       ir])
    (record-function-kind! : Program-Element (ir) -> * (void)
      [(circuit ,src ,function-name ((,var-name* ,type*) ...) ,type ,expr)
       (hashtable-set! function-ht function-name
         (Fun-circuit src function-name var-name* expr (next-circuit-uid)))]
      [(external ,src ,function-name ,native-entry (,arg* ...) ,type)
       (hashtable-set! function-ht function-name
         (Fun-external (native-entry-disclosures native-entry) type))]
      [(witness ,src ,function-name (,arg* ...) ,type)
       (hashtable-set! function-ht function-name
         (Fun-witness
           (default-value type
             (list (make-witness src (next-witness-uid)
                     (Witness-Return-Value function-name))))))]
      [,kdecl (void)]
      [,ldecl (void)]
      [,export-tdefn (void)]
      [else (assert cannot-happen)])
    (Program-Element : Program-Element (ir) -> * ()
      [(circuit ,src ,function-name ((,var-name* ,type*) ...) ,type ,expr)
       (when (id-exported? function-name)
         (let ([witness** (maplr (lambda (var-name)
                                   (list (make-witness (id-src var-name) (next-witness-uid)
                                           (Circuit-Argument function-name var-name))))
                                 var-name*)])
           (handle-call #f function-name (map default-value type* witness**) '() #t)))]
      [(public-ledger-declaration ,pl-array (constructor ,src ((,var-name* ,type*) ...) ,expr))
       (Expression
         expr
         (extend-env empty-env var-name*
           (map default-value
                type*
                (map (lambda (var-name)
                       (list (make-witness (id-src var-name) (next-witness-uid)
                               (Constructor-Argument var-name))))
                     var-name*)))
         '()
         #f)]
      [else (void)])
    (Effect : Expression (ir p control-witness* disclosing-function-name?) -> * ()
      [(if ,src ,[* abs0] ,expr1 ,expr2)
       (let ([control-witness* (merge-witnesses
                                 (abs->witnesses (add-path-point src "the conditional branch" "the boolean value of" abs0))
                                 control-witness*)])
         (Abs-case abs0
           [(Abs-boolean true? witness*) (Effect (if true? expr1 expr2) p control-witness* disclosing-function-name?)]
           [(Abs-atomic witness*) (Effect expr1 p control-witness* disclosing-function-name?) (Effect expr2 p control-witness* disclosing-function-name?)]
           [else (assert cannot-happen)]))]
      [(seq ,src ,[*] ... ,expr)
       (Effect expr p control-witness* disclosing-function-name?)]
      [(let* ,src ([(,var-name* ,type*) ,[* abs*]] ...) ,expr)
       (let ([abs* (map add-path-binding var-name* abs*)])
         (Effect expr (extend-env p var-name* abs*) control-witness* disclosing-function-name?))]
      [else (Expression ir p control-witness* disclosing-function-name?)])
    (Expression : Expression (ir p control-witness* disclosing-function-name?) -> * (abs)
      (definitions
        (define (handle-comparison src abs1 abs2)
          (add-path-point src
            "the comparison"
            "the result of a comparison involving"
            (Abs-atomic (merge-witnesses (abs->witnesses abs1) (abs->witnesses abs2)))))
        )
      [(quote ,src ,datum)
       (case datum
         [(#t) (Abs-boolean #t '())]
         [(#f) (Abs-boolean #f '())]
         [else (Abs-atomic '())])]

      [(default ,src ,type) (default-value type)]
      [(enum-ref ,src ,type ,elt-name^) (Abs-atomic '())]

      [(var-ref ,src ,var-name) (lookup-env p var-name)]

      [(if ,src ,[* abs0] ,expr1 ,expr2)
       (let ([control-witness* (merge-witnesses
                                 (abs->witnesses (add-path-point src "the conditional branch" "the boolean value of" abs0))
                                 control-witness*)])
         (add-witnesses (abs->witnesses (add-path-point src "the conditional expression" "the boolean value of" abs0))
           (Abs-case abs0
             [(Abs-boolean true? witness*) (Expression (if true? expr1 expr2) p control-witness* disclosing-function-name?)]
             [(Abs-atomic witness*) (combine-abs (Expression expr1 p control-witness* disclosing-function-name?) (Expression expr2 p control-witness* disclosing-function-name?))]
             [else (assert cannot-happen)])))]

      [(elt-ref ,src ,[* abs] ,elt-name ,nat)
       (Abs-case abs
         [(Abs-multiple abs*) (list-ref abs* nat)]
         [else (assert cannot-happen)])]

      [(tuple-ref ,src ,[* abs] ,kindex)
       (Abs-case abs
         [(Abs-single abs) abs]
         [(Abs-multiple abs*) (list-ref abs* kindex)]
         [else (assert cannot-happen)])]

      [(bytes-ref ,src ,type ,[* abs] ,[* abs^])
       (add-witnesses
         (abs->witnesses abs^)
         abs)]

      [(vector-ref ,src ,type ,[* abs] ,[* abs^])
       (add-witnesses
         (abs->witnesses abs^)
         (Abs-case abs
           [(Abs-single abs) abs]
           ; Eventually all vector-ref indices must reduce to constants, so this is overly restrictive.
           ; We would have to move witness-protection after simplify-circuit to ease the restrictiveness.
           [(Abs-multiple abs*) (fold-left combine-abs (car abs*) (cdr abs*))]
           [else (assert cannot-happen)]))]

      [(tuple-slice ,src ,type ,[* abs] ,kindex ,len)
       (Abs-case abs
         [(Abs-single abs^) abs]
         [(Abs-multiple abs*) (Abs-multiple (list-head (list-tail abs* kindex) len))]
         [else (assert cannot-happen)])]

      [(bytes-slice ,src ,type ,[* abs] ,[* abs^] ,len)
       (add-witnesses
         (abs->witnesses abs^)
         abs)]

      [(vector-slice ,src ,type ,[* abs] ,[* abs^] ,len)
       (add-witnesses
         (abs->witnesses abs^)
         (Abs-single
           (Abs-case abs
             [(Abs-single abs) abs]
             [(Abs-multiple abs*)
              (if (null? abs*)
                  abs
                  ; Eventually all vector-ref indices must reduce to constants, so this is overly restrictive.
                  ; We would have to move witness-protection after simplify-circuit to ease the restrictiveness.
                  (fold-left combine-abs (car abs*) (cdr abs*)))]
             [else (assert cannot-happen)])))]

      ; arithmetic isn't sanitizing: could be x + 0, x - 0, x * 1, age == 18, (age < 19 && 17 < age)
      [(+ ,src ,mbits ,[* abs1] ,[* abs2])
       (add-path-point src "the computation" "the result of an addition involving" (combine-abs abs1 abs2))]
      [(- ,src ,mbits ,[* abs1] ,[* abs2])
       (add-path-point src "the computation" "the result of a subtraction involving" (combine-abs abs1 abs2))]
      [(* ,src ,mbits ,[* abs1] ,[* abs2])
       (add-path-point src "the computation" "the result of a multiplication involving" (combine-abs abs1 abs2))]
      [(< ,src ,mbits ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]
      [(<= ,src ,mbits ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]
      [(> ,src ,mbits ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]
      [(>= ,src ,mbits ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]
      [(== ,src ,type ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]
      [(!= ,src ,type ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]

      [(map ,src ,len ,fun ,[* abs] ,[* abs*] ...)
       (if (= len 0)
           (Abs-multiple '())
           (let ([abs+ (cons abs abs*)])
             (if (ormap (lambda (abs) (Abs-case abs [(Abs-multiple abs*) #t] [else #f])) abs+)
                 (Abs-multiple
                   (let f ([abs++ (map (lambda (abs)
                                         (Abs-case abs
                                           [(Abs-single abs) (make-list len abs)]
                                           [(Abs-atomic witness*) (make-list len abs)]
                                           [(Abs-multiple abs*) abs*]
                                           [else (assert cannot-happen)]))
                                     abs+)])
                     (let ([abs+ (map car abs++)] [abs*+ (map cdr abs++)])
                       (cons (Function fun src p abs+ control-witness*)
                             (if (null? (car abs*+))
                                 '()
                                 (f abs*+))))))
                 (let ([abs+ (map (lambda (abs)
                                    (Abs-case abs
                                      [(Abs-single abs) abs]
                                      [(Abs-atomic witness*) abs]
                                      [else (assert cannot-happen)]))
                                  abs+)])
                   (Abs-single (Function fun src p abs+ control-witness*))))))]

      [(fold ,src ,len ,fun (,[* abs0] ,type0) ,[* abs] ,[* abs*] ...)
       (if (= len 0)
           abs0
           (let ([abs+ (cons abs abs*)])
             (if (ormap (lambda (abs) (Abs-case abs [(Abs-multiple abs*) #t] [else #f])) abs+)
                 (let loop ([abs abs0]
                            [abs++ (map (lambda (abs)
                                          (Abs-case abs
                                            [(Abs-single abs) (make-list len abs)]
                                            [(Abs-atomic witness*) (make-list len abs)]
                                            [(Abs-multiple abs*) abs*]
                                            [else (assert cannot-happen)]))
                                      abs+)])
                   (let ([abs+ (map car abs++)] [abs*+ (map cdr abs++)])
                     (let ([abs (Function fun src p (cons abs abs+) control-witness*)])
                       (if (null? (car abs*+))
                           abs
                           (loop abs abs*+)))))
                 (let ([abs+ (map (lambda (abs)
                                    (Abs-case abs
                                      [(Abs-single abs) abs]
                                      [(Abs-atomic witness*) abs]
                                      [else (assert cannot-happen)]))
                                  abs+)])
                   (let loop ([abs (Function fun src p (cons abs0 abs+) control-witness*)] [len len])
                     (if (= len 1)
                         abs
                         (let ([abs^ (Function fun src p (cons abs abs+) control-witness*)])
                           (if (abs-equal? abs^ abs)
                               abs
                               (loop abs^ (- len 1))))))))))]

      [(call ,src ,function-name ,[* abs*] ...) (handle-call src function-name abs* control-witness* #f)]

      [(disclose ,src ,[* abs]) (disclose abs)]

      [(new ,src ,type ,[* abs*] ...) (Abs-multiple abs*)]

      [(tuple ,src ,tuple-arg* ...)
       (Abs-multiple
         (fold-right
           (lambda (tuple-arg abs*)
             (nanopass-case (Lwithpaths Tuple-Argument) tuple-arg
               [(single ,src ,[Expression : expr p control-witness* disclosing-function-name? -> abs])
                (cons abs abs*)]
               [(spread ,src ,nat ,[Expression : expr p control-witness* disclosing-function-name? -> abs])
                (Abs-case abs
                  ; this case isn't exercised because tuple forms don't vector-typed spreads
                  [(Abs-single abs) (append (make-list nat abs) abs*)]
                  [(Abs-multiple abs^*) (append abs^* abs*)]
                  [else (assert cannot-happen)])]))
           '()
           tuple-arg*))]

      [(vector ,src ,tuple-arg* ...)
       (let ([abs* (fold-right
                     (lambda (tuple-arg abs*)
                       (nanopass-case (Lwithpaths Tuple-Argument) tuple-arg
                         [(single ,src ,[Expression : expr p control-witness* disclosing-function-name? -> abs])
                          (cons abs abs*)]
                         [(spread ,src ,nat ,[Expression : expr p control-witness* disclosing-function-name? -> abs])
                          (Abs-case abs
                            [(Abs-single abs) (cons abs abs*)]
                            [(Abs-multiple abs^*) (append abs^* abs*)]
                            [else (assert cannot-happen)])]))
                     '()
                     tuple-arg*)])
         (if (null? abs*)
             (Abs-multiple '())
             (Abs-single
               (add-witnesses
                 (fold-left merge-witnesses '() (map abs->witnesses (cdr abs*)))
                 (car abs*)))))]

      [(seq ,src ,[*] ... ,[* abs]) abs]

      [(let* ,src ([(,var-name* ,type*) ,[* abs*]] ...) ,expr)
       (let ([abs* (map add-path-binding var-name* abs*)])
         (Expression expr (extend-env p var-name* abs*) control-witness* disclosing-function-name?))]
      ; define-pass doesn't realize above pattern covers let*
      [(let* ,src ([,local* ,[* abs*]] ...) ,expr) (assert cannot-happen)]

      [(assert ,src ,[* abs] ,mesg) (Abs-atomic '())]

      [(cast-from-enum ,src ,type ,type^ ,[* abs]) abs]
      [(cast-to-enum ,src ,type ,type^ ,[* abs]) abs]
      [(cast-from-bytes ,src ,type ,len ,[* abs]) abs]
      [(field->bytes ,src ,len ,[* abs]) abs]
      [(bytes->vector ,src ,len ,[* abs]) (Abs-single (Abs-atomic (abs->witnesses abs)))]
      [(vector->bytes ,src ,len ,[* abs]) (Abs-atomic (abs->witnesses abs))]
      [(downcast-unsigned ,src ,nat ,[* abs]) abs]
      [(safe-cast ,src ,type ,type^ ,[* abs]) abs]

      [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[* abs*] ...)
       (nanopass-case (Lwithpaths ADT-Op) adt-op
         [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
          (unless (null? control-witness*)
            (record-leak! src^ "performing this ledger operation" control-witness*))
          (for-each
            (lambda (abs discloses? i?)
              (when discloses?
                (let ([witness* (abs->witnesses
                                  (add-path-point src^
                                    (if sugar?
                                        (format "the right-hand side of ~a" sugar?)
                                        (format "the ~@[~:r ~]argument to ~a" (and i? (fx+ i? 1)) ledger-op))
                                    discloses?
                                    abs))])
                  (unless (null? witness*)
                    (record-leak! src^ "ledger operation" witness*)))))
            abs*
            discloses?*
            (if (= (length abs*) 1) '(#f) (enumerate abs*)))
          (default-value type)])]
      [(contract-call ,src ,elt-name (,[* abs] ,type) ,[* abs*] ...)
       (unless (null? control-witness*)
         (record-leak! src "making this contract call" control-witness*))
       (let ([witness* (abs->witnesses abs)])
         (unless (null? witness*) (record-leak! src "contract call contract reference" witness*)))
       (for-each
         (lambda (abs i)
           (let ([witness* (abs->witnesses abs)])
             (unless (null? witness*) (record-leak! src (format "contract call argument ~d" (fx+ i 1)) witness*))))
         abs*
         (enumerate abs*))
       (default-value
         (nanopass-case (Lwithpaths Type) (de-alias type)
           [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
            (let loop ([elt-name* elt-name*]
                       [type* type*])
              (if (eq? (car elt-name*) elt-name)
                  (car type*)
                  (loop (cdr elt-name*) (cdr type*))))]))]
      [(return ,src ,[* abs])
       (when disclosing-function-name?
         (let ()
           (define (filter-witnesses witness*)
             (filter
               (lambda (witness)
                 ; don't report exposure of an exported circuit's own arguments via the circuit's return value
                 (Witness-Info-case (witness-info witness)
                   [(Witness-Return-Value function-name) #t]
                   [(Constructor-Argument argument-name) #f]
                   [(Circuit-Argument function-name argument-name) #f]))
               witness*))
           (let ([control-witness* (filter-witnesses control-witness*)])
             (unless (null? control-witness*)
               (record-leak! src
                 (format "returning this value from exported circuit ~s" (id-sym disclosing-function-name?))
                 control-witness*)))
           (let ([witness* (filter-witnesses (abs->witnesses abs))])
             (unless (null? witness*)
               (record-leak! src
                 (format "the value returned from exported circuit ~s" (id-sym disclosing-function-name?))
                 witness*)))))
       abs])
    (Map-Argument : Map-Argument (ir p control-witness* disclosing-function-name?) -> * (abs)
      [(,[* abs] ,type ,type^) abs])
    (Function : Function (ir src p abs* control-witness*) -> Function ()
      [(fref ,src^ ,function-name) (handle-call src function-name abs* control-witness* #f)]
      [(circuit ,src ((,var-name* ,type*) ...) ,type ,expr)
       (assert (= (length var-name*) (length abs*)))
       (Expression expr (extend-env p var-name* abs*) control-witness* #f)]))

  (define-pass remove-disclose : Lwithpaths (ir) -> Lnodisclose ()
    (ADT-Op : ADT-Op (ir) -> ADT-Op ()
      [(,ledger-op ,[op-class] (,adt-name (,adt-formal* ,[adt-arg*]) ...) ((,var-name* ,[type*] ,discloses?*) ...) ,[type] ,vm-code)
       `(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)])
    (Expression : Expression (ir) -> Expression ()
      [(disclose ,src ,[expr]) expr]))

  (define-passes analysis-passes
    (expand-modules-and-types        Lexpanded)
    (generate-contract-ht            Lexpanded)
    (infer-types                     Ltypes)
    (remove-tundeclared              Lnotundeclared)
    (combine-ledger-declarations     Loneledger)
    (discard-unused-functions        Loneledger)
    (reject-recursive-circuits       Loneledger)
    (recognize-let                   Lnodca)
    (check-sealed-fields             Lnodca)
    (reject-constructor-cc-calls     Lnodca)
    (identify-pure-circuits          Lnodca)
    (determine-ledger-paths          Lwithpaths0)
    (propagate-ledger-paths          Lwithpaths)
    (track-witness-data              Lwithpaths)
    (remove-disclose                 Lnodisclose))

  (define-passes fixup-analysis-passes
    (expand-modules-and-types        Lexpanded)
    (infer-types                     Ltypes))

  (define-checker check-types/Lnodca Lnodca)
)
