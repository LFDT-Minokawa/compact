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

#!chezscheme

;;; expand-modules-and-types resolves identifier bindings, expands away module and
;;; import forms, substitutes generic parameter references with the corresponding types
;;; and sizes, replaces struct-name, enum-name, contract-name, and ADT-name references
;;; with fully expanded struct, enum, contract, and ADT types, detects unbound identifiers,
;;; and detects misused identifiers such as a struct name used where an ordinary
;;; variable is expected or an ordinary variable used where a type variable is expected.
;;; a full description of the pass and how it works is in ../compiler.md.

(define-syntax standard-library-path (identifier-syntax "compiler/standard-library.compact"))
(define-syntax zkir-v3-library-path (identifier-syntax "compiler/zkir-v3-library.compact"))

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
    (module (zkir-v3-library-pelt* standard-library-pelt*)
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
                             (lambda (ignore) #'(begin (register-stdlib-sfd! 'sfd) '(pelt ...))))])])
          a))
      (define zkir-v3-library-pelt*
        (let-syntax ([a (nanopass-case (Lpreexpand Program) (run-passes
                                                              frontend-passes
                                                              (run-passes
                                                                parser-passes
                                                                zkir-v3-library-path))
                          [(program ,src ,pelt* ...)
                           (#%$require-include zkir-v3-library-path)
                           (with-syntax ([(pelt ...) (datum->syntax #'* pelt*)]
                                         [sfd (datum->syntax #'* (source-object-sfd src))])
                             (lambda (ignore) #'(begin (register-stdlib-sfd! 'sfd) '(pelt ...))))])])
          a))
      (unless (member standard-library-path (registered-source-pathnames))
        (register-source-pathname! standard-library-path))
      (unless (member zkir-v3-library-path (registered-source-pathnames))
        (register-source-pathname! zkir-v3-library-path)))
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
          [(tfield ,src ,ftype)
           (nanopass-case (Lexpanded Field-Type) ftype
             [(field-native) 2]
             [(field-scalar (curve-jubjub)) 3]
             [(field-base (curve-secp256k1)) 4]
             [(field-scalar (curve-secp256k1)) 5])]
          [(tunsigned ,src ,nat) (+ 6 nat)]
          [(tbytes ,src ,len) (+ 7 len)]
          [(topaque ,src ,opaque-type) (+ 8 (string-hash opaque-type))]
          ;; arrange for equivalent vectors and tuples to hash to same value with same elements,
          ;; limiting the cost in the case of large vectors
          [(tvector ,src ,len ,type)
           (+ 9 (combine (make-list (min len max-tuple-elts-to-hash) (type-hash type))))]
          [(ttuple ,src ,type* ...)
           (+ 9 (combine (map type-hash
                              (if (fx<= (length type*) max-tuple-elts-to-hash)
                                  type*
                                  (list-head type* max-tuple-elts-to-hash)))))]
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (+ 11 (combine (list (symbol-hash contract-name)
                            ;; contract elts are unordered, so just add their hashes
                            (apply + (map symbol-hash elt-name*)))))]
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           (+ 12 (combine (map symbol-hash (cons struct-name elt-name*))))]
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
           (+ 13 (combine (map symbol-hash (cons* enum-name elt-name elt-name*))))]
          [(tadt ,src ,adt-name ([,adt-formal* ,generic-value*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (+ 14 (combine (cons (symbol-hash adt-name) (map gv-hash generic-value*))))]
          [(talias ,src ,nominal? ,type-name ,type)
           (if nominal?
               (+ 15 (combine (list (symbol-hash type-name) (type-hash type))))
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
      (fields seqno src kind type-param* pelt p instance-table)
      (protocol
        (lambda (new)
          (lambda (seqno src kind type-param* pelt p)
            (new seqno src kind type-param* pelt p (make-instance-table))))))
    (module ()
      (record-writer (record-type-descriptor info-fun)
        (lambda (x p wr)
          (fprintf p "#[info-fun ~s ~s ~s]" (info-fun-seqno x) (format-source-object (info-fun-src x)) (info-fun-kind x)))))
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
      ; Info-fixup-alias supports renaming / fixup
      (Info-fixup-alias aliased-name info)
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
    (define cidecl* '())
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
    (define (env-insert! p src sym info)
      (assert (env? p))
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
             [(tfield ,src1 (field-native)) (T type2 [(tfield ,src2 (field-native)) #t])]
             [(tfield ,src1 (field-scalar (curve-jubjub)))
              (T type2
                [(tfield ,src2 (field-scalar (curve-jubjub))) #t])]
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
      (define (compatible-type-parameters? info-fun)
        (let ([type-param* (info-fun-type-param* info-fun)])
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
                       info*))))
      (define-record-type generic-failure
        (nongenerative)
        (fields src kind*)
        (protocol
          (lambda (new)
            (lambda (info-fun)
              (new
                (info-fun-src info-fun)
                (map (lambda (type-param)
                       (nanopass-case (Lpreexpand Type-Param) type-param
                         [(nat-valued ,src ,tvar-name) 'size]
                         [(type-valued ,src ,tvar-name) 'type]
                         ; currently not reachable since functions don't employ this kind of type-param
                         [(non-adt-type-valued ,src ,tvar-name) 'non-adt-type]))
                     (info-fun-type-param* info-fun)))))))
      (define (return id+* generic-failure*)
        (with-output-language (Lexpanded Function)
          `(fref ,src ,function-name
                 ((,id+* ...) ...)
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
      (define (find-functions function-name)
        ; find-functions finds all of the Info-functions bindings for function-name
        ; in the environment that are not shadowed by some other binding.
        (let outer ([p p] [rinfo-functions* '()] [rmaybe-alias* '()])
          (cond
            [(eq? p empty-env) (values rinfo-functions* rmaybe-alias* #f)]
            [(begin (assert (env? p)) (hashtable-ref (env-rib p) function-name #f)) =>
             (lambda (src.info)
               (let retry ([info (cdr src.info)] [maybe-alias #f])
                 (Info-case info
                   [(Info-functions name info-fun+)
                    (outer (env-p p) (cons info rinfo-functions*) (cons maybe-alias rmaybe-alias*))]
                   [(Info-fixup-alias aliased-name info)
                    (retry info aliased-name)]
                   [else (values rinfo-functions* rmaybe-alias* info)])))]
            [else (outer (env-p p) rinfo-functions* rmaybe-alias*)])))
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
      (let-values ([(rinfo-functions* rmaybe-alias* maybe-info) (find-functions function-name)])
        ; check to see if any of the function names are renamings of standard-library routines
        ; (per standard-library-aliases.ss) and if so, record the alias or say why not
        (let ([alias-name (ormap values rmaybe-alias*)])
          (when alias-name
            (if (renaming-table)
                (if (andmap (lambda (x) (eq? x alias-name)) rmaybe-alias*)
                    (let-values ([(^rinfo-functions* ^rmaybe-alias* ^maybe-info) (find-functions alias-name)])
                      (assert (or (not (null? ^rinfo-functions*)) ^maybe-info))
                      (if (equal? ^rinfo-functions* rinfo-functions*)
                          (record-alias! src function-name alias-name)
                          (source-warningf src "not renaming reference of ~s to ~s because ~1:*~s has other bindings in scope"
                                           function-name
                                           alias-name)))
                    (source-warningf src "not renaming reference of ~s to ~s because ~2:*~s has other bindings in scope"
                                     function-name
                                     alias-name))
                (record-alias! src function-name alias-name))))
        ; go through the the Info-functions list from innermost to outermost, pruning
        ; duplicate function bindings, registering those that are compatible with the
        ; generic arguments, and collecting a list of those that are not for infer-types.
        (let loop ([info-functions* (reverse rinfo-functions*)] [rid+* '()] [generic-failure* '()])
          (if (null? info-functions*)
              (if (and (null? rid+*) (null? generic-failure*))
                  (if maybe-info
                      (context-oops src function-name maybe-info)
                      (source-errorf src "unbound identifier ~s" function-name))
                  ; all done; return an `fref` form with the information gathered
                  (return (reverse rid+*) generic-failure*))
              (Info-case (car info-functions*)
                [(Info-functions name info-fun+)
                 (define (register info-fun) (make/register-frob src name info-fun info* #f))
                 (let-values ([(compatible* incompatible*) (partition compatible-type-parameters? (remp fun-visited? info-fun+))])
                   (loop (cdr info-functions*)
                         (if (null? compatible*)
                             rid+*
                             (cons (maplr register compatible*) rid+*))
                         (append (map make-generic-failure incompatible*) generic-failure*)))]
                [else (assertf cannot-happen "find-functions should return only Info-functions infos")])))))
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
        [(Info-fixup-alias aliased-name info) (describe-info info)]))
    (define (handle-type-ref src tvar-name info* p info)
      (with-output-language (Lexpanded Type)
        (with-type-cycle-check src info tvar-name
          (lambda ()
            (let retry ([info info])
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
                [(Info-fixup-alias aliased-name info)
                 (if (renaming-table)
                     (let ([info^ (lookup/no-error p aliased-name)])
                       (assertf info^ "aliased name ~s is not found in the environment" aliased-name)
                       (if (eq? info^ info)
                           (record-alias! src tvar-name aliased-name)
                           (source-warningf src "not renaming reference of ~s to ~s because this would cause the reference to be captured by an existing local binding for ~:*~s"
                                            tvar-name
                                            aliased-name)))
                     (record-alias! src tvar-name aliased-name))
                 (retry info)]
                [else (context-oops src tvar-name info)]))))))
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
                                                [(Info-fixup-alias aliased-name info)
                                                 (let ([prefix-aliased-name (add-prefix aliased-name)])
                                                   (env-insert! p src prefix-aliased-name info)
                                                   (Info-fixup-alias prefix-aliased-name info))]
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
                                                        (if (feature-zkir-v3) zkir-v3-library-pelt* '())
                                                        (let-values ([(native* zkir-v3-native*) (native-declarations)])
                                                          (if (feature-zkir-v3)
                                                              (append native* zkir-v3-native*)
                                                              native*))
                                                        (event-declarations)
                                                        (inline-declarations)
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
                                                                 (with-output-language (Lpreexpand Fixup-Alias-Definition)
                                                                   `(fixup-alias ,old-name ,new-name))))
                                                             (append
                                                               stdlib-type-aliases
                                                               stdlib-circuit-aliases)))
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
                               [(Info-fixup-alias aliased-name info)
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
                  (let* ([info-fun (make-info-fun (reverse seqno) src kind type-param* pelt p)]
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
                  [(native ,src ,exported? ,function-name ,native-entry (,type-param* ...) (,arg* ...) ,type)
                   (handle-fun src 'native pelt exported? function-name type-param*)]
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
                  [(fixup-alias ,function-name^ ,function-name)
                   (let ([src (make-source-object (get-stdlib-sfd) 0 0 1 1)]
                         [info (Info-fixup-alias function-name (assert (lookup/no-error p function-name)))])
                     (env-insert! p src function-name^ info)
                     (loop pelt* seqno*
                           (cons (make-exportit src function-name^ info) export*)
                           unresolved-export*))]
                  [(contract-implements ,src ,type)
                   (set! cidecl* (cons (cons pelt p) cidecl*))
                   (loop pelt* seqno* export* unresolved-export*)]))))))
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
                     [(Info-fixup-alias aliased-name info) (retry src export-name info)]
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
                 [cidecl* (map (lambda (cidecl) (Contract-Implements-Declaration (car cidecl) (cdr cidecl))) cidecl*)]
                 [exported-other* (sort (lambda (x y) (string<? (symbol->string (car x)) (symbol->string (car y))))
                                        exported-other*)])
             (let-values ([(event-struct-name* event-type*)
                           (let ([stdlib-env
                                   (let ([p (add-rib empty-env)])
                                     (do-import src 'CompactStandardLibrary '() "" #f p)
                                     p)])
                             (maplr2
                               (lambda (sd)
                                 (nanopass-case (Lpreexpand Structure-Definition) sd
                                   [(struct ,src ,exported? ,struct-name (,type-param* ...) [,src* ,elt-name* ,type*] ...)
                                    (assertf (null? type-param*) "~s has generic parameters, but parameterized event types are not supported" struct-name)
                                    (values
                                      struct-name
                                      (apply-struct src src struct-name type-param* elt-name* type* stdlib-env '()))]))
                               (event-declarations)))])
               `(program ,src
                  ((,(map car exported-other*) ,(map cdr exported-other*)) ...)
                  ((,event-struct-name* ,event-type*) ...)
                  (,unreachable* ...)
                  (,ecdecl* ...)
                  (,cidecl* ...)
                  ,(reverse exported-type*) ...
                  ,reachable* ...))))))])
  (Program-Element : Program-Element (ir p id) -> Program-Element ()
    [(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,[arg*] ...) ,[type] ,expr)
     (let ([var-id* (map arg->id arg*)] [p (add-rib p)])
       (begin
         (for-each
           (lambda (id) (env-insert! p src (id-sym id) (Info-var id)))
           var-id*)
         (when pure-dcl? (id-pure?-set! id #t)))
       `(circuit ,src ,id (,arg* ...) ,type ,(Expression expr p)))]
    [(native ,src ,exported? ,function-name ,native-entry (,type-param* ...) (,[arg*] ...) ,[type])
     `(native ,src ,id ,native-entry (,arg* ...) ,type)]
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
               (handle-type-ref src 'Cell (list (Info-type src type)) p (lookup p src '__compact_Cell)))))]
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
  (Contract-Implements-Declaration : Contract-Implements-Declaration (ir p) -> Contract-Implements-Declaration ()
    [(contract-implements ,src ,[type])
     `(contract-implements ,src ,type)])
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
    [(for ,src ,var-name ,[Type-Size->nat : tsize0 p 0 -> * nat0] ,[Type-Size->nat : tsize1 p 0 -> * nat1] ,expr2)
     (when (> nat0 (max-unsigned))
       (source-errorf src "start bound ~d is greater than the maximum unsigned integer ~d" nat0 (max-unsigned)))
     (when (> nat1 (max-unsigned))
       (source-errorf src "end bound ~d is greater than the maximum unsigned integer ~d" nat1 (max-unsigned)))
     (let ([n (- nat1 nat0)])
       (when (< n 0)
         (source-errorf src "end bound ~d is less than start bound ~s" nat1 nat0))
       (when (> n (max-bytes/vector-length))
         (source-errorf src "the difference ~d between end and start bounds exceeds the maximum vector size ~d" n (max-bytes/vector-length)))
       (let ([expr1 (with-output-language (Lexpanded Expression)
                       `(tuple ,src ,(map (lambda (i) `(single ,src (quote ,src ,(+ nat0 i)))) (iota n)) ...))])
         (let ([id (make-source-id src var-name)] [p (add-rib p)])
           (env-insert! p src var-name (Info-var id))
           `(for ,src ,id ,expr1 ,(Expression expr2 p)))))]
    [(for ,src ,var-name ,[expr1] ,expr2)
     (let ([id (make-source-id src var-name)] [p (add-rib p)])
       (env-insert! p src var-name (Info-var id))
       `(for ,src ,id ,expr1 ,(Expression expr2 p)))]
    [(tuple-slice ,src ,[expr] ,[index] ,[Type-Size->nat : tsize p 1 -> * nat])
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
     `(call ,src ,fun ,(map (lambda (e) (Expression e p)) expr*) ...)]
    [(serialize ,src ,[Type-Size->nat : tsize p 0 -> * nat] ,[type] ,[expr])
     `(serialize ,src ,nat ,type ,expr)]
    [(deserialize ,src ,[Type-Size->nat : tsize p 0 -> * nat] ,[type] ,[expr])
     `(deserialize ,src ,nat ,type ,expr)])
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
    [(tunsigned ,src ,[Type-Size->nat : tsize p 1 -> * nat])
     (unless (<= 1 nat (unsigned-bits))
        (source-errorf src "Uint width ~d is not between 1 and the maximum Uint width ~d (inclusive)"
                       nat
                       (unsigned-bits)))
     `(tunsigned ,src ,(- (expt 2 nat) 1))]
    [(tunsigned ,src ,[Type-Size->nat : tsize p 0 -> * nat] ,[Type-Size->nat : tsize^ p 1 -> * nat^])
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
    [(tvector ,src ,[Type-Size->nat : tsize p 1 -> * nat] ,[type])
     (check-length! src "vector type" nat)
     `(tvector ,src ,nat ,type)]
    [(tbytes ,src ,[Type-Size->nat : tsize p 1 -> * nat])
     (check-length! src "bytes type" nat)
     `(tbytes ,src ,nat)]
    [(ttuple ,src ,[type*] ...)
     (check-length! src "tuple type" (length type*))
     `(ttuple ,src ,type* ...)])
  (Type-Ref->Type : Type-Ref (ir p) -> Type ()
    [(type-ref ,src ,tvar-name ,[Type-Argument->info : targ* p -> * info*] ...)
     (handle-type-ref src tvar-name info* p (lookup p src tvar-name))])
  (Type-Size->nat : Type-Size (ir p default) -> * (nat)
    [(type-size ,src ,nat) nat]
    [(type-size-ref ,src ,tsize-name)
     (Info-lookup (p src tsize-name)
       [(Info-size src size) size]
       ; if we find a free tvar here, it's in an exported type where sizes are
       ; ultimately ignored, so any nat will do.  the default argument takes either
       ; 1 for Uint range end points and Uint widths
       ; 0 for everything else
       [(Info-free-tvar tvar-name) default])])
  (Type-Argument->info : Type-Argument (ir p) -> * (info)
    [(targ-size ,src ,nat) (Info-size src nat)]
    [(targ-type ,src (type-ref ,src^ ,tvar-name ,[Type-Argument->info : targ* p -> * info*] ...))
     (let ([info (lookup p src tvar-name)])
       (Info-case info
         [(Info-size src^^ size)
          (unless (null? info*) (generic-argument-count-oops src tvar-name (length info*) 0))
          (Info-size src size)]
         [else (Info-type src (handle-type-ref src tvar-name info* p info))]))]
    [(targ-type ,src ,type) (Info-type src (Type type p))])
)
