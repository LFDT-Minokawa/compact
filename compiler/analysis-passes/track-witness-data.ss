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
      (Fun-native disclosure?* type))

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
    ; useful for sorting paths (with more direct problems first) and is more
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
                   (and (not (eq? x1* x2*)) ; quit when lists are null if not sooner
                        (case (elt-compare (car x1*) (car x2*))
                          [(<) #t]
                          [(>) #f]
                          [else (loop (cdr x1*) (cdr x2*))])))))))

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
          [(Fun-native disclosure?* type)
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
                  [via* (map (lambda (pp*)
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
                             (witness-path* witness))])
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
    [(program ,src (,contract-type* ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
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
    [(native ,src ,function-name ,native-entry (,arg* ...) ,type)
     (hashtable-set! function-ht function-name
       (Fun-native (native-entry-disclosure* native-entry) type))]
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

    [(emit ,src ,type ,[* abs])
     (unless (null? control-witness*)
       (record-leak! src "performing this emit operation" control-witness*))
     (let ([witness* (abs->witnesses
                       (add-path-point src "the argument to emit" "" abs))])
       (unless (null? witness*)
         (record-leak! src "emit operation" witness*)))
     abs]

    [(serialize ,src ,len ,type ,[* abs])
     (Abs-atomic (abs->witnesses abs))]

    [(deserialize ,src ,len ,type ,[* abs])
     (default-value type (abs->witnesses abs))]

    [(tuple-ref ,src ,[* abs] ,kindex)
     (Abs-case abs
       [(Abs-single abs) abs]
       [(Abs-multiple abs*) (list-ref abs* kindex)]
       [else (assert cannot-happen)])]

    [(bytes-ref ,src ,type ,[* abs] ,[* abs^])
     (add-witnesses
       (abs->witnesses
         (add-path-point src "the bytes-value reference" "the element selected by"
           abs^))
       abs)]

    [(vector-ref ,src ,type ,[* abs] ,[* abs^])
     (add-witnesses
       (abs->witnesses
         (add-path-point src "the vector or tuple reference" "the element selected by"
           abs^))
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
       (abs->witnesses
         (add-path-point src "the bytes-value slice" "the elements selected by"
           abs^))
       abs)]

    [(vector-slice ,src ,type ,[* abs] ,[* abs^] ,len)
     (add-witnesses
       (abs->witnesses
         (add-path-point src "the vector or tuple slice" "the elements selected by"
           abs^))
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
    [(< ,src ,bits ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]
    [(<= ,src ,bits ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]
    [(> ,src ,bits ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]
    [(>= ,src ,bits ,[* abs1] ,[* abs2]) (handle-comparison src abs1 abs2)]
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
    [(field->bytes ,src ,len ,ftype ,[* abs]) abs]
    [(bytes->vector ,src ,len ,[* abs]) (Abs-single (Abs-atomic (abs->witnesses abs)))]
    [(vector->bytes ,src ,len ,[* abs]) (Abs-atomic (abs->witnesses abs))]
    [(cast-to-field ,src ,ftype ,type ,[* abs]) abs]
    [(cast-from-field ,src ,nat ,ftype ,[* abs]) abs]
    [(downcast-unsigned ,src ,nat2 ,nat1 ,[* abs]) abs]
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
     (let-values ([(pure? type)
            (nanopass-case (Lwithpaths Type) (de-alias type)
              [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
               (let loop ([elt-name* elt-name*]
                          [pure-dcl* pure-dcl*]
                          [type* type*])
                 (if (eq? (car elt-name*) elt-name)
                     (values (car pure-dcl*) (car type*))
                     (loop (cdr elt-name*) (cdr pure-dcl*) (cdr type*))))])])
       (unless pure?
         (unless (null? control-witness*)
           (record-leak! src "making this contract call" control-witness*))
         (let ([witness* (abs->witnesses abs)])
           (unless (null? witness*) (record-leak! src "contract call contract reference" witness*)))
         (for-each
           (lambda (abs i)
             (let ([witness* (abs->witnesses abs)])
               (unless (null? witness*) (record-leak! src (format "contract call argument ~d" (fx+ i 1)) witness*))))
           abs*
           (enumerate abs*)))
       (default-value type))]
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
