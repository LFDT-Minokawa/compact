;;; Copyright 2017 Cisco Systems, Inc.
;;; 
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;; 
;;; http://www.apache.org/licenses/LICENSE-2.0
;;; 
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

;;; See http://www.cs.nott.ac.uk/~pszgmh/monparsing.pdf for origins of 
;;; some of the monadic combinators.

;;; Authors: Jon Rossie, Kent Dybvig

;;; The define-grammar form produces a parser:
;;;
;;;   parser : token-stream -> ((Tree token-stream) ...)
;;;
;;; If the return value is the empty list, a parse error occurred.
;;; If the return value has multiple elements, the parse was ambiguous.
;;; The token-stream in each (Tree token-stream) is the tail of the
;;; input stream that begins with the last token consumed by the parse.
;;; This gives the consumer access to both the first and last token,
;;; allowing it to determine cheaply the extent of the parse, including
;;; source locations if source information is attached to the tokens.

;;; Internally, backtracking occurs whenever a parser return value
;;; has multiple elements.

;;; This code should be included into a lexical context that supplies
;;; some compile-time helpers for the define-grammar syntactic abstraction:
;;;
;;;    meta (constant? syntax-object) -> boolean
;;;    meta (suppress-constant? syntax-object) -> boolean
;;;    meta (constant->parser constant) -> parser
;;;    meta (constant->html constant) -> html representation of constant

;;; This code also expects the lexical scope to include some operations on
;;; source objects, which should encapsulate both starting and ending file
;;; positions:
;;;
;;;    (src0) -> inital source position at the start of the input stream
;;;    (token-src token) -> token's source position.
;;;    (make-src src1 src2) -> source object whose starting file position
;;;      is the starting file position of src1 and whose ending file position
;;;      is the ending file position of src2.
;;;    (src> src1 src2) -> #t if src1's starting file position is greater
;;;      than src2's starting file position.
;;;
;;; This code doesn't care how source objects are represented.
;;;
;;; See ez-grammar-test.ss for an example.

(module (define-grammar
          is sat sat/what item peek seq ++ +++ many many+ ?
          parse-consumed-all? parse-result-value parse-result-unused
          grammar-trace
          )
  (import (streams))
  (import (chezscheme))

  (define grammar-trace (make-parameter #f))

  (define-record-type parse-result
    (nongenerative parse-result)
    (sealed #t)
    (fields value unused))

  ;; to enable $trace-is to determine the ending source position (esrc) of a parse
  ;; form, the input stream actually points to the preceding token rather than
  ;; to the current token.  the next few routines establish, maintain, and deal
  ;; with that invariant.
  (define make-top-level-parser
    (lambda (parser)
      (lambda (inp success fail)
        (fluid-let ([last-token #f] [last-token-tries '()])
          (let ([res* (parser (stream-cons 'dummy-token inp))])
            (if (null? res*)
                (fail last-token (last-token-failures))
                (success res*)))))))

  (define preceding-token
    (lambda (inp)
      (stream-car inp)))

  (define last-token)
  (define last-token-tries)

  (define current-token
    (lambda (inp)
      (let ([token (stream-car (stream-cdr inp))])
        (when (or (not last-token)
                  (src>? (token-src token)
                         (token-src last-token)))
          (set! last-token token)
          (set! last-token-tries '()))
        token)))

  (define remaining-tokens
    (lambda (inp)
      (stream-cdr inp)))

  (define no-more-tokens?
    (lambda (inp)
      (stream-null? (stream-cdr inp))))

  (define parse-consumed-all?
    (lambda (res)
      (no-more-tokens? (parse-result-unused res))))

  ;; A parser generator
  (define result
    (lambda (v)
      ;; this is a parser that ignores its input and produces v
      (lambda (inp)
        (stream (make-parse-result v inp)))))

  ;; A parse that always generates a parse error
  (define zero
    (lambda (inp)
      stream-nil))

  ;; For a non-empty stream, successfully consume the first element
  (define item
    (lambda (inp)
      (cond
        [(no-more-tokens? inp) '()]
        [else
          (stream (make-parse-result (current-token inp) (remaining-tokens inp)))])))

  (define (peek p)
    (lambda (inp)
      (stream-map (lambda (pr)
                    (make-parse-result (parse-result-value pr) inp))
        (p inp))))

  (module (try with-nonterminal-try)
    (define stack-depth 0)

    (define (try desc parser)
      (lambda (inp)
        (let ([res* (parser inp)])
          (when (null? res*)
            (let ([token (current-token inp)])
              (when (eq? token last-token)
                (set! last-token-tries
                  (cons (cons stack-depth desc) last-token-tries)))))
          res*)))

    (define (with-nonterminal-try id proc)
      (lambda (inp)
        (let ([token (current-token inp)])
          (when (and (eq? token last-token) (not (gensym? (syntax->datum id))))
            (set! last-token-tries
              (cons (cons stack-depth (cons 'start id)) last-token-tries)))
          (let ([v (fluid-let ([stack-depth (fx+ stack-depth 1)]) ((proc) inp))])
            (when (and (eq? token last-token) (not (gensym? (syntax->datum id))))
              (set! last-token-tries (cons (cons stack-depth '(end)) last-token-tries)))
            v)))))

  (define (last-token-failures)
    ; returns the last token tried and a list of match failures on the last token tried,
    ; sorted from outermost to innermost levels of the parser stack.  each failure
    ; is either:
    ;   a string representing a terminal
    ;   a list (nonterminal-name failure ...) representing a nonterminal and the
    ;          match failures occuring while trying to match the nonterminal
    (let-values ([(failure* try*)
                  (let f ([try* (reverse last-token-tries)])
                    (if (null? try*)
                        (values '() '())
                        (let ([try (car try*)] [try* (cdr try*)])
                          (let ([depth (car try)] [try (cdr try)])
                            (if (pair? try)
                                (case (car try)
                                  [(start)
                                   (let-values ([(failure^* try*) (f try*)])
                                     (let-values ([(failure* try*) (f try*)])
                                       (values
                                         (cons (cons depth (cons (cdr try) failure^*)) failure*)
                                         try*)))]
                                  [(end) (values '() try*)]
                                  [else (assert #f)])
                                (let-values ([(failure* try*) (f try*)])
                                  (values
                                    (cons (cons depth try) failure*)
                                    try*)))))))])
      (assert (null? try*))
      (let f ([failure* failure*])
        (let ([failure* (map cdr (sort (lambda (x y) (fx< (car x) (car y))) failure*))])
          (map (lambda (failure)
                 (if (pair? failure)
                     (cons (car failure) (f (cdr failure)))
                     failure))
               failure*)))))

  ;;------------------------------------------

  (define bind
    (lambda (parser receiver)
      (lambda (inp)
        (let ([res* (parser inp)])
          (stream-append-all
            (stream-map (lambda (res)
                          ((receiver (parse-result-value res))
                           (parse-result-unused res)))
              res*))))))

  ;; monad comprehensions
  (define-syntax is-where ; used by is and trace-is
    (lambda (x)
      (syntax-case x (where <-)
        [(_ expr (where)) #'expr]
        [(_ expr (where [x <- p] clauses ...))
         #'(bind p (lambda (x) (is-where expr (where clauses ...))))]
        [(_ expr (where pred clauses ...))
         #'(if pred (is-where expr (where clauses ...)) zero)]
        [(_ expr where-clause) (syntax-error #'where-clause)])))
  (indirect-export is-where bind)

  (define-syntax is
    (syntax-rules ()
      [(_ expr where-clause) (is-where (result expr) where-clause)]))
  (indirect-export is is-where)

  (define-syntax is/what
    (syntax-rules ()
      [(_ desc expr where-clause)
       (try desc (is-where (result expr) where-clause))]))
  (indirect-export is/what is-where try)

  (module (trace-is)
    (define ($trace-is name proc head)
      (lambda (unused)
        (let ([res (if (eq? unused head)
                       ; nothing consumed
                       (let ([src (if (eq? (preceding-token unused) 'dummy-token)
                                      ; at beginning of the file
                                      (src0)
                                      ; elsewhere
                                      (token-src (preceding-token unused)))])
                         (proc src src))
                       (proc (token-src (current-token head))
                             (token-src (preceding-token unused))))])
          (when (and name (grammar-trace)) (printf "<<~s = ~s~%" name res))
          (stream (make-parse-result res unused)))))

    (define-syntax trace-is
      (syntax-rules ()
        [(_ name proc-expr where-clause)
         (lambda (inp) ((is-where ($trace-is 'name proc-expr inp) where-clause) inp))]))
    (indirect-export trace-is $trace-is))

  (define (seq2 p q) (is (cons x y) (where [x <- p] [y <- q])))

  (define seq
    (lambda p*
      (let loop ([p* p*])
        (cond
          [(null? p*) (result '())]
          [else (seq2 (car p*) (loop (cdr p*)))]))))

  (define (sat pred) (is x (where [x <- item] (pred x))))

  (define (sat/what desc pred) (is/what desc x (where [x <- item] (pred x))))

  (define ++ ;; introduce ambiguity
    (lambda (p q)
      (lambda (inp)
        (stream-append2 (p inp)
          (lambda ()
            (q inp))))))

  (define (many+ p) (is (cons x xs) (where [x <- p] [xs <- (many p)])))

  (define (many p) (++ (many+ p) (result '())))

  (define (? p) (++ (sat p) (result #f)))

  (define (sepby1 p sep suppress-sep? permit-trailing-sep?)
    (is (cons x
              (if suppress-sep?
                  xs
                  (fold-right (lambda (p xs) (cons* (car p) (cdr p) xs)) (if sep? (list sep?) '()) xs)))
      (where
        [x <- p]
        [xs <- (many (is (if suppress-sep? y (cons x y)) (where [x <- sep] [y <- p])))]
        [sep? <- (if permit-trailing-sep? (++ sep (result #f)) (result #f))])))

  (define (sepby p sep suppress-sep? permit-trailing-sep?) (++ (sepby1 p sep suppress-sep? permit-trailing-sep?) (result '())))

  (define (bracket open p close) (is x (where [_ <- open] [x <- p] [_ <- close])))

  (define (optional p default)
    (lambda (inp)
      (let ([res (p inp)])
        (if (stream-null? res)
            (stream (make-parse-result default inp))
            res))))

  (define (first p)
    (lambda (inp)
      (let ([res (p inp)])
        (if (stream-null? res)
            res
            (stream (stream-car res))))))

  (define (+++ p q) (first (++ p q))) ;; choose first match, cut backtracking

  (define (format-inp inp)
    (if (no-more-tokens? inp)
        "#<null-stream>"
        (format "(~s ...)" (current-token inp))))

  (define-syntax define-grammar
    (lambda (x)
      (define-record-type grammar
        (nongenerative)
        (sealed #t)
        (fields title paragraph* section*))
      (define-record-type section
        (nongenerative)
        (sealed #t)
        (fields title paragraph* suppressed? clause*))
      (define-record-type clause
        (nongenerative)
        (fields id alias* before-paragraph* after-paragraph*))
      (define-record-type nonterminal-clause
        (nongenerative)
        (sealed #t)
        (parent clause)
        (fields prod*))
      (define-record-type terminal-clause
        (nongenerative)
        (sealed #t)
        (fields term*))
      (define-record-type terminal
        (nongenerative)
        (sealed #t)
        (fields parser alias* paragraph*))
      (define-record-type production
        (nongenerative)
        (sealed #t)
        (fields name paragraph* elt* receiver)
        (protocol
          (let ()
            (define (check-elts elt*)
              (for-each (lambda (elt) (unless (elt? elt) (errorf 'make-production "~s is not an elt" elt))) elt*))
            (lambda (new)
              (case-lambda
                [(name elt* receiver)
                 (check-elts elt*)
                 (new name #f elt* receiver)]
                [(name paragraph* elt* receiver)
                 (check-elts elt*)
                 (new name paragraph* elt* receiver)])))))
      (define-record-type elt
        (nongenerative)
        (fields suppress?))
      (define-record-type sep-elt
        (nongenerative)
        (sealed #t)
        (parent elt)
        (fields +? elt sep permit-trailing-sep?)
        (protocol (lambda (new) (lambda (+? elt sep suppress? permit-trailing-sep?) ((new suppress?) +? elt sep permit-trailing-sep?)))))
      (define-record-type opt-elt
        (nongenerative)
        (sealed #t)
        (parent elt)
        (fields elt default)
        (protocol (lambda (new) (lambda (elt default) ((new #f) elt default)))))
      (define-record-type kleene-elt
        (nongenerative)
        (sealed #t)
        (parent elt)
        (fields +? elt)
        (protocol (lambda (new) (lambda (+? elt) ((new #f) +? elt)))))
      (define-record-type constant-elt
        (nongenerative)
        (sealed #t)
        (parent elt)
        (fields k)
        (protocol (lambda (new) (lambda (k suppress?) ((new suppress?) k)))))
      (define-record-type id-elt
        (nongenerative)
        (sealed #t)
        (parent elt)
        (fields id)
        (protocol (lambda (new) (lambda (id) ((new #f) id)))))
      (define paragraph?
        (lambda (x)
          (syntax-case x (include HTML EVAL)
            [(include filename) (string? (datum filename))]
            [(HTML str ...) (andmap string? (datum (str ...)))]
            [(EVAL expr) #t]
            [(str ...) (andmap string? (datum (str ...)))]
            [else #f])))
      (define (gentemp) (datum->syntax #'* (gensym)))
      (define (elt-temps elt*)
        (for-each (lambda (elt) (unless (elt? elt) (errorf 'elt-temps "~s is not an elt" elt))) elt*)
        (fold-left
          (lambda (t* elt)
            (if (elt-suppress? elt) t* (cons (gentemp) t*)))
          '()
          elt*))
      (define (eliminate-left-recursion clause new-clause*)
        (define recursive-prod? 
          (lambda (prod)
            (let ([elt* (production-elt* prod)])
              (and (not (null? elt*))
                   (let ([elt (car elt*)])
                     (and (id-elt? elt)
                          (ormap (lambda (id) (free-identifier=? (id-elt-id elt) id))
                                 (clause-alias* clause))))))))
        (let-values ([(recursive-prod* nonrecursive-prod*) (partition recursive-prod? (nonterminal-clause-prod* clause))])
          (cond
            [(null? recursive-prod*) (cons clause new-clause*)]
            [(null? nonrecursive-prod*)
             (syntax-error (clause-id clause) "no base-case productions found for left recursive nonterminal")]
            [else
             (let ([tail-nt (gentemp)])
               (cons*
                 (make-nonterminal-clause
                   (clause-id clause)
                   (clause-alias* clause)
                   (clause-before-paragraph* clause)
                   (clause-after-paragraph* clause)
                   (map
                     (lambda (prod)
                       (let ([elt* (production-elt* prod)] [tail-elt (make-id-elt tail-nt)])
                         (make-production
                           (production-name prod)
                           (append elt* (list tail-elt))
                           (let ([u* (elt-temps elt*)] [build-tmp (gentemp)])
                             #`(lambda (bsrc esrc #,@u* #,build-tmp)
                                 (#,build-tmp bsrc
                                   (#,(production-receiver prod) bsrc esrc #,@u*)))))))
                     nonrecursive-prod*))
                 (make-nonterminal-clause tail-nt '() '() '()
                   (cons
                     (make-production #f '() #`(lambda (bsrc esrc) (lambda (bsrc x) x)))
                     (map
                       (lambda (prod)
                         (let ([elt* (cdr (production-elt* prod))] [tail-elt (make-id-elt tail-nt)])
                           (make-production
                             (production-name prod)
                             (append elt* (list tail-elt))
                             (let ([u* (elt-temps elt*)] [build-tmp (gentemp)])
                               #`(lambda (bsrc esrc #,@u* #,build-tmp)
                                   (lambda (bsrc x)
                                     (#,build-tmp bsrc
                                       (#,(production-receiver prod) bsrc esrc x #,@u*))))))))
                       recursive-prod*)))
                 new-clause*))])))
      (define (left-factor clause*)
        ; left factoring can make a huge difference in the running time of a parser by
        ; eliminating what could be an exponential amount of reparsing in the case of a
        ; recursive grammar.  it can, however affect backtracking order.  consider, for
        ; example, the following productions for parsing "if" expressions:
        ; 
        ; [two-armed-if :: if #\( expr-seq #\) stmt else stmt => ...]
        ; [one-armed-if :: if #\( expr-seq #\) stmt => ...]
        ; 
        ; "if (a) if (b) c; else d;" can be parsed either as (if a (if b c d) (tuple)) or
        ; as (if a (if b c (tuple)) d).  say, as is typical, we desire the first of these,
        ; which attaches the "else" to the inner "if".  Since the parser is outermost to
        ; innermost, and the clauses are tried in the order listed, the parser will try
        ; every possible way to get the outer "if" to parse as a two-armed "if", and
        ; succeed in doing so, before trying to parse the outer "if" as a one-armed "if".
        ; this is, of course, not the desired parse.
        ; 
        ; The left-factored version, however, leads, perhaps surprisingly, to the
        ; desired parse.  While left factoring doesn't change the set of strings
        ; accepted by a grammar or the number of possible parses in cases like this
        ; where the grammar is ambiguous, it does change the order of the set of
        ; possible parses assuming the same (nondeterministic) implemenatation is used
        ; for the resulting grammar.  In this case, the left-factored version is:
        ;
        ; statement:
        ;   [if-stmt :: src if #\( expr-seq #\) stmt if-tail => ...]
        ; if-tail:
        ;   [if-tail :: => else stmt => ...]
        ;   [if-tail :: => ...]
        ;
        ; if-stmt with input string "if (a) if (b) c; else d;" consumes "if (a)" and
        ; tries to match "stmt if-tail" against "if (b) c; else d;".  this ends up back
        ; in if-stmt, which consumes "if (b)" and tries to match "stmt if-tail" against
        ; "c; else d;".  stmt matches "c;", sending "else d;" to if-tail.  if-tail
        ; matches "else d;" and we have a complete parse, with "else" attached to the
        ; inner "if", as desired.  if-tail applied to "else d;" can also match "",
        ; leaving the remainder for the outer if-tail, but the parser never needs to
        ; backtrack and try that case.  ez-grammar's implementation of left factoring
        ; could "fix" this case to behave the same with and without left factoring by
        ; switching the order of the if-tail clauses, but this would not fix every case
        ; where left factoring a grammar produces an different backtracking order.
        ;
        ; if we want to maintain consistent semantics we can consider ditching left
        ; factoring and instead use memoization in the resulting combinators to
        ; eliminate the exponential reparsing overhead, albeit with more run-time
        ; overhead.
        (define syntax-equal?
          (lambda (x y)
            (equal? (syntax->datum x) (syntax->datum y))))
        (define (elt-equal? x y)
          (cond
            [(sep-elt? x) 
             (and (sep-elt? y)
                  (eq? (sep-elt-+? x) (sep-elt-+? y))
                  (elt-equal? (sep-elt-elt x) (sep-elt-elt y))
                  (syntax-equal? (sep-elt-sep x) (sep-elt-sep y))
                  (eq? (sep-elt-permit-trailing-sep? x) (sep-elt-permit-trailing-sep? y)))]
            [(opt-elt? x) 
             (and (opt-elt? y)
                  (elt-equal? (opt-elt-elt x) (opt-elt-elt y))
                  (syntax-equal? (opt-elt-default x) (opt-elt-default y)))]
            [(kleene-elt? x) 
             (and (kleene-elt? y)
                  (eq? (kleene-elt-+? x) (kleene-elt-+? y))
                  (elt-equal? (kleene-elt-elt x) (kleene-elt-elt y)))]
            [(constant-elt? x)
             (and (constant-elt? y)
                  (syntax-equal? (constant-elt-k x) (constant-elt-k y)))]
            [(id-elt? x)
             (and (id-elt? y)
                  (syntax-equal? (id-elt-id x) (id-elt-id y)))]
            [else #f]))
        (let lp1 ([clause* clause*] [new-clause* '()])
          (if (null? clause*)
              (reverse new-clause*)
              (let ([clause (car clause*)])
                (let lp2 ([prod* (nonterminal-clause-prod* clause)] [new-prod* '()] [clause* (cdr clause*)])
                  (if (null? prod*)
                      (lp1 clause* (cons (make-nonterminal-clause (clause-id clause) (clause-alias* clause) '() '() (reverse new-prod*)) new-clause*))
                      (let ([prod (car prod*)] [prod* (cdr prod*)])
                        (let ([elt* (production-elt* prod)])
                          (if (null? elt*)
                              (lp2 prod* (cons prod new-prod*) clause*)
                              (let ([elt (car elt*)])
                                (let-values ([(haves have-nots) (partition
                                                                  (lambda (prod)
                                                                    (let ([elt* (production-elt* prod)])
                                                                      (and (not (null? elt*))
                                                                           (elt-equal? (car elt*) elt))))
                                                                  prod*)])
                                  (if (null? haves)
                                      (lp2 prod* (cons prod new-prod*) clause*)
                                      (let ([haves (cons prod haves)])
                                        ; "haves" start with the same elt.  to cut down on the number of new
                                        ; nonterminals and receiver overhead, find the largest common prefix
                                        (let ([prefix (cons elt
                                                        (let f ([elt** (map production-elt* haves)])
                                                          (let ([elt** (map cdr elt**)])
                                                            (if (ormap null? elt**)
                                                                '()
                                                                (let ([elt (caar elt**)])
                                                                  (if (andmap (lambda (elt*) (elt-equal? (car elt*) elt)) (cdr elt**))
                                                                      (cons elt (f elt**))
                                                                      '()))))))])
                                          (let ([t (gentemp)] [n (length prefix)] [t* (elt-temps prefix)])
                                            (lp2 have-nots
                                              (cons (make-production #f (append prefix (list (make-id-elt t)))
                                                      #`(lambda (bsrc esrc #,@t* p) (p bsrc #,@t*)))
                                                new-prod*)
                                              (cons (make-nonterminal-clause t '() '() '()
                                                      (map (lambda (prod)
                                                             (let ([elt* (list-tail (production-elt* prod) n)])
                                                               (make-production (production-name prod) elt*
                                                                 (let ([u* (elt-temps elt*)])
                                                                   #`(lambda (bsrc esrc #,@u*)
                                                                       (lambda (bsrc #,@t*)
                                                                         (#,(production-receiver prod) bsrc esrc #,@t* #,@u*)))))))
                                                        haves))
                                                clause*)))))))))))))))))
      (define (make-env tclause* clause*)
        (let ([env (make-hashtable (lambda (x) (symbol-hash (syntax->datum x))) free-identifier=?)])
          (define (insert parser)
            (lambda (name)
              (let ([a (hashtable-cell env name #f)])
                (when (cdr a) (syntax-error name "duplicate terminal/non-terminal name"))
                (set-cdr! a parser))))
          (for-each
            (lambda (tclause)
              (for-each
                (lambda (term)
                  (let ([parser (terminal-parser term)])
                    (for-each (insert parser) (cons parser (terminal-alias* term)))))
                (terminal-clause-term* tclause)))
            tclause*)
          (for-each
            (lambda (clause)
              (let ([id (clause-id clause)])
                (for-each (insert id) (cons id (clause-alias* clause)))))
            clause*)
          env))
      (define (lookup id env)
        (or (hashtable-ref env id #f)
            (syntax-error id "unrecognized terminal or nonterminal")))
      (define (render-html name grammar htmlfn env)
        (import (html))
        (import %html)
        (define (separators sep ls)
          (if (null? ls)
              ""
              (apply string-append
                (cons (car ls)
                  (map (lambda (s) (format "~a~a" sep s)) (cdr ls)))))) 
        ; NB: ignoring hard-leading-newline at least for now
        (define (render-paragraph hard-leading-newline?)
          (lambda (paragraph)
            (<p> ()
              (syntax-case paragraph (include HTML EVAL)
                [(include filename)
                 (string? (datum filename))
                 (display-string (call-with-port (open-input-file (datum filename)) get-string-all))]
                [(HTML sentence ...)
                 (andmap string? (datum (sentence ...)))
                 (let ([sentence* (datum (sentence ...))])
                   (unless (null? sentence*)
                     (printf "~a\n" (separators " " sentence*))))]
                [(EVAL expr)
                 (let ([s (eval (datum expr))])
                   (unless (string? s)
                     (errorf #f "non-string value from eval of EVAL expr ~s" (datum expr)))
                   (unless (string=? s "")
                     (printf "~a\n" s)))]
                [(sentence ...)
                 (andmap string? (datum (sentence ...)))
                 (let ([sentence* (datum (sentence ...))])
                   (unless (null? sentence*)
                     (printf "~a\n" (separators " " (map (lambda (x) (with-output-to-string (lambda () (html-text "~a" x)))) sentence*)))))]))))
        (define (subscriptize x)
          (if (string? x)
              (let ([n (string-length x)])
                (if (and (>= n 2) (char-numeric? (string-ref x (fx- n 1))) (not (char-numeric? (string-ref x (fx- n 2)))))
                    (format "~a<sub>~a</sub>" (substring x 0 (fx- n 1)) (string-ref x (fx- n 1)))
                    x))
              x))
        (define (format-elt x)
          (cond
            [(sep-elt? x)
             (let ([one (format-elt (sep-elt-elt x))]
                   [sep (constant->html (syntax->datum (sep-elt-sep x)))])
               (format "~a ~a &mldr;~@[~*&sup1;~] ~2:*~a ~2:*~a ~2*~@[~2:*~a<sup>opt</sup>~]" one sep (sep-elt-+? x) (sep-elt-permit-trailing-sep? x)))]
            [(opt-elt? x)
             (with-output-to-string
               (lambda ()
                 (printf "~a" (format-elt (opt-elt-elt x)))
                 (<sup> () (display-string "opt"))))]
            [(kleene-elt? x)
             (let ([one (format-elt (kleene-elt-elt x))])
               (format "~a &mldr;~@[~*&sup1;~] ~2:*~a" one (kleene-elt-+? x)))]
            [(constant-elt? x)
             (with-output-to-string
               (lambda ()
                 (display-string (constant->html (syntax->datum (constant-elt-k x))))))]
            [(id-elt? x)
             (with-output-to-string
               (lambda ()
                 (<a> ([href (format "#~a" (syntax->datum (lookup (id-elt-id x) env)))])
                   (<em> () (display-string (subscriptize (format "~a" (syntax->datum (id-elt-id x)))))))))]
            [else (errorf 'format-elt "unexpected elt ~s" x)]))
        (define (render-elt x) (nbsp) (nbsp) (display-string (format-elt x)))
        (define (render-production prod)
          (let ([elt* (production-elt* prod)])
            (if (null? elt*)
                (begin (nbsp) (nbsp) (write-char #\() (<em> () (printf "empty")) (write-char #\)))
                (for-each render-elt elt*))))
        (define (render-clause clause)
          (define (format-alias alias)
            (with-output-to-string
              (lambda ()
                (<em> () (display-string (subscriptize (format "~a" (syntax->datum alias))))))))
          (if (terminal-clause? clause)
              (for-each
                (lambda (term)
                  (let ([term (format "~a" (syntax->datum (terminal-parser term)))]
                        [alias* (terminal-alias* term)])
                    (<h4> ()
                      (<a> ([name term])
                        (printf "~a <span style=\"font-weight: normal\">(~{~a~^, ~})</span>" term (map format-alias alias*)))))
                  (newline)
                  (for-each (render-paragraph #f) (terminal-paragraph* term)))
                (terminal-clause-term* clause))
              (let ([nonterm (format "~a" (syntax->datum (clause-id clause)))]
                    [alias* (map format-alias (clause-alias* clause))])
                (<h4> ()
                  (<a> ([name nonterm])
                    (printf "~a <span style=\"font-weight: normal\">(~{~a~^, ~})</span>" (subscriptize nonterm) alias*)))
                (newline)
                (for-each (render-paragraph #f) (clause-before-paragraph* clause))
                (<table> ()
                  (let ([lhs (subscriptize (if (null? alias*) nonterm (car alias*)))])
                    (let loop ([prod* (or (nonterminal-clause-prod* clause) '())] [lhs lhs])
                      (unless (null? prod*)
                        (let ([prod (car prod*)])
                          (<tr> ()
                            (<td> () (display-string lhs) (nbsp))
                            (<td> () (display-string "&rarr;"))
                            (<td> () (render-production prod))
                            (unless (null? (production-paragraph* prod))
                              (<td> () (for-each (render-paragraph #t) (production-paragraph* prod))))))
                        (loop (cdr prod*) "")))))
                (for-each (render-paragraph #f) (clause-after-paragraph* clause)))))
        (define (render-section section)
          (unless (section-suppressed? section)
            (when (section-title section)
              (<h2> () (display-string (section-title section))))
            (for-each (render-paragraph #f) (section-paragraph* section))
            (for-each render-clause (section-clause* section))))
        (with-output-to-file htmlfn
          (lambda ()
            (<doctype>)
            (<html> ()
              (newline)
              (<head> ()
                (newline)
                (<meta> ([http-equiv "Content-Type"]
                         [content "text/html;charset=utf-8"]))
                  (newline)
                  (<title> () (html-text "~a" (syntax->datum name)))
                  (newline))
              (newline)
              (<h1> () (if (grammar-title grammar)
                           (html-text (grammar-title grammar))
                           (printf "Grammar for ~a" (syntax->datum name))))
              (newline)
              (for-each (render-paragraph #f) (grammar-paragraph* grammar))
              (for-each render-section (grammar-section* grammar))
              (newline)))
          'replace))
      (module (parse-grammar)
        (define parse-elt
          (lambda (elt)
            (syntax-case elt (SEP+ SEP* OPT K* K+)
              [(SEP+ p sep) (make-sep-elt #t (parse-elt #'p) #'sep (suppress-constant? #'sep) #f)]
              [(SEP+ p sep permit-trailing-sep?) (make-sep-elt #t (parse-elt #'p) #'sep (suppress-constant? #'sep) (datum permit-trailing-sep?))]
              [(SEP* p sep) (make-sep-elt #f (parse-elt #'p) #'sep (suppress-constant? #'sep) #f)]
              [(SEP* p sep permit-trailing-sep?) (make-sep-elt #f (parse-elt #'p) #'sep (suppress-constant? #'sep) (datum permit-trailing-sep?))]
              [(OPT p default) (make-opt-elt (parse-elt #'p) #'default)]
              [(K+ p) (make-kleene-elt #t (parse-elt #'p))]
              [(K* p) (make-kleene-elt #f (parse-elt #'p))]
              [k (constant? #'k) (make-constant-elt #'k (suppress-constant? #'k))]
              [id (identifier? #'id) (make-id-elt #'id)]
              [_ (syntax-error elt "invalid production element")])))
        (define parse-production
          (lambda (prod)
            (define (finish name src? paragraph* elt* receiver)
              (let ([elt* (map parse-elt elt*)])
                (make-production name paragraph* elt*
                  (with-syntax ([(t ...) (elt-temps elt*)])
                    (let ([n (let ([n (length #'(t ...))]) (if src? (fx+ n 1) n))])
                      (unless (syntax-case receiver (lambda)
                                [(lambda (x ...) b1 b2 ...)
                                 (fx= n (length #'(x ...)))]
                                [(lambda r b1 b2 ...)
                                 (identifier? #'r)
                                 #t]
                                [(lambda (x y ... . r) b1 b2 ...)
                                 (fx> n (length #'(y ...)))]
                                [else #t])
                        (syntax-error receiver (format "expected number ~d of arguments not accepted by receiver" n))))
                    #`(lambda (bsrc esrc t ...)
                        #,(if src?
                              #`(#,receiver (make-src bsrc esrc) t ...)
                              #`(#,receiver t ...)))))))
            (syntax-case prod (:: src =>)
              [[name :: src elt ... => receiver]
               (finish #'name #t '() #'(elt ...) #'receiver)]
              [[name :: elt ... => receiver]
               (finish #'name #f '() #'(elt ...) #'receiver)])))
        (define (parse-terminal term)
          (syntax-case term (DESCRIPTION)
            [(parser (alias ...) (DESCRIPTION paragraph ...))
             (and (identifier? #'parser) (andmap identifier? #'(alias ...)) (andmap paragraph? #'(paragraph ...)))
             (make-terminal #'parser #'(alias ...) #'(paragraph ...))]
            [(parser (alias ...))
             (and (identifier? #'parser) (andmap identifier? #'(alias ...)))
             (make-terminal #'parser #'(alias ...) '())]))
        (define (parse-clause clause nt alias* before-paragraph* after-paragraph* stuff*)
          (syntax-case stuff* ()
            [(prod prods ...)
             (make-nonterminal-clause nt alias* before-paragraph* after-paragraph* (map parse-production #'(prod prods ...)))]
            [else (syntax-error clause)]))
        (define (parse-top top* knull kgrammar ksection kclause)
          (if (null? top*)
              (knull)
              (let ([top (car top*)] [top* (cdr top*)])
                (syntax-case top (GRAMMAR SECTION SUPPRESSED DESCRIPTION TERMINALS)
                  [(GRAMMAR title paragraph ...)
                   (andmap paragraph? #'(paragraph ...))
                   (kgrammar top* (datum title) #'(paragraph ...))]
                  [(SECTION SUPPRESSED title paragraph ...)
                   (andmap paragraph? #'(paragraph ...))
                   (ksection top* (datum title) #'(paragraph ...) #t)]
                  [(SECTION title paragraph ...)
                   (andmap paragraph? #'(paragraph ...))
                   (ksection top* (datum title) #'(paragraph ...) #f)]
                  [(TERMINALS term ...)
                   (kclause top* (make-terminal-clause (map parse-terminal #'(term ...))))]
                  [(TERMINALS term ...)
                   (kclause top* (make-terminal-clause (map parse-terminal #'(term ...))))]
                  [(nt (alias ...) (DESCRIPTION paragraph1 ...) stuff ... (DESCRIPTION paragraph2 ...))
                   (and (identifier? #'nt) (andmap identifier? #'(alias ...)) (andmap paragraph? #'(paragraph1 ...)) (andmap paragraph? #'(paragraph2 ...)))
                   (kclause top* (parse-clause top #'nt #'(alias ...) #'(paragraph1 ...) #'(paragraph2 ...) #'(stuff ...)))]
                  [(nt (alias ...) (DESCRIPTION paragraph ...) stuff ...)
                   (and (identifier? #'nt) (andmap identifier? #'(alias ...)) (andmap paragraph? #'(paragraph ...)))
                   (kclause top* (parse-clause top #'nt #'(alias ...) #'(paragraph ...) '() #'(stuff ...)))]
                  [(nt (alias ...) stuff ... (DESCRIPTION paragraph ...))
                   (and (identifier? #'nt) (andmap identifier? #'(alias ...)) (andmap paragraph? #'(paragraph ...)))
                   (kclause top* (parse-clause top #'nt #'(alias ...) '() #'(paragraph ...) #'(stuff ...)))]
                  [(nt (alias ...) stuff ...)
                   (and (identifier? #'nt) (andmap identifier? #'(alias ...)))
                   (kclause top* (parse-clause top #'nt #'(alias ...) '() '() #'(stuff ...)))]))))
        (define (parse-grammar top*)
          (define (misplaced-grammar-error top)
            (syntax-error top "unexpected GRAMMAR element after other elements"))
          (define (s1 top*) ; looking for GRAMMAR form, first SECTION form, or clause
            (parse-top top*
              (lambda () (make-grammar #f '() '()))
              (lambda (top* title paragraph*)
                (make-grammar title paragraph* (s2 top*)))
              (lambda (top* title paragraph* suppressed?)
                (make-grammar #f '()
                  (s3 top* title paragraph* suppressed? '() '())))
              (lambda (top* clause)
                (make-grammar #f '()
                  (s3 top* #f '() #f (list clause) '())))))
          (define (s2 top*) ; looking for first SECTION form or clause
            (parse-top top*
              (lambda () '())
              (lambda (top title paragraph*) (misplaced-grammar-error (car top*)))
              (lambda (top* title paragraph* suppressed?)
                (s3 top* title paragraph* suppressed? '() '()))
              (lambda (top* clause)
                (s3 top* #f '() #f (list clause) '()))))
          (define (s3 top* title paragraph* suppressed? rclause* rsection*) ; steady state: looking for remaining SECTION forms and clauses
            (define (finish-section)
              (cons (make-section title paragraph* suppressed? (reverse rclause*)) rsection*))
            (parse-top top*
              (lambda () (reverse (finish-section)))
              (lambda (top title paragraph*) (misplaced-grammar-error (car top*)))
              (lambda (top* title paragraph* suppressed?)
                (s3 top* title paragraph* suppressed? '() (finish-section)))
              (lambda (top* clause)
                (s3 top* title paragraph* suppressed? (cons clause rclause*) rsection*))))
          (s1 top*)))
      (define (go init-nts top* htmldir ++/+++)
        (let ([grammar (parse-grammar top*)])
          (let* ([clause* (apply append (map section-clause* (grammar-section* grammar)))]
                 [terminal-clause* (filter terminal-clause? clause*)]
                 [nonterminal-clause* (left-factor (fold-right eliminate-left-recursion '() (filter nonterminal-clause? clause*)))]
                 [env (make-env terminal-clause* nonterminal-clause*)])
            (define (elt-helper x)
              (cond
                [(sep-elt? x) #`(#,(if (sep-elt-+? x) #'sepby1 #'sepby)
                                 #,(elt-helper (sep-elt-elt x))
                                 #,(constant->parser (sep-elt-sep x))
                                 #,(elt-suppress? x)
                                 #,(sep-elt-permit-trailing-sep? x))]
                [(opt-elt? x) #`(optional #,(elt-helper (opt-elt-elt x)) #,(opt-elt-default x))]
                [(kleene-elt? x) #`(#,(if (kleene-elt-+? x) #'many+ #'many) #,(elt-helper (kleene-elt-elt x)))]
                [(constant-elt? x) (constant->parser (constant-elt-k x))]
                [(id-elt? x) (lookup (id-elt-id x) env)]
                [else (errorf 'elt-helper "unhandled elt ~s\n" x)]))
            (define (nt-helper clause)
              #`[#,(clause-id clause)
                 (with-nonterminal-try '#,(clause-id clause)
                   (lambda ()
                     #,(let f ([prod* (nonterminal-clause-prod* clause)])
                         (if (null? prod*)
                             #'zero
                             (let ([elt* (production-elt* (car prod*))])
                               (with-syntax ([name (production-name (car prod*))]
                                             [(elt ...) elt*]
                                             [receiver (production-receiver (car prod*))])
                                 (with-syntax ([(x ...) (generate-temporaries elt*)])
                                   (with-syntax ([([y _] ...) (remp (lambda (pr) (elt-suppress? (cadr pr))) #'([x elt] ...))])
                                     (with-syntax ([(where-nt ...) (map elt-helper elt*)])
                                       #`(#,++/+++
                                           (lambda (inp)
                                             (when (and 'name (grammar-trace)) (printf ">>~s(~a)~%" 'name (format-inp inp)))
                                             (let ([res ((trace-is name (lambda (bsrc esrc) (receiver bsrc esrc y ...)) (where [x <- where-nt] ...)) inp)])
                                               (when (and 'name (grammar-trace))
                                                 (if (stream-null? res)
                                                     (printf "<<~s(~a) failed~%" 'name (format-inp inp))
                                                     (printf "<<~s(~a) succeeded~%" 'name (format-inp inp))))
                                               res))
                                           #,(f (cdr prod*))))))))))))])
            (with-syntax ([(init-nt ...)
                           (syntax-case init-nts ()
                             [(id1 id2 ...) (andmap identifier? #'(id1 id2 ...)) #'(id1 id2 ...)]
                             [id (identifier? #'id) (list #'id)])])
              (when htmldir
                (let f ([htmldir htmldir])
                  (unless (member htmldir '("/" "" "." ".."))
                    (unless (file-directory? htmldir)
                      (f (path-parent htmldir))
                      (mkdir htmldir))))
                (for-each
                  (lambda (init-nt)
                    (let ([htmlfn (format "~a/~a.html" htmldir (syntax->datum init-nt))])
                      (render-html init-nt grammar htmlfn env)))
                  #'(init-nt ...)))
              (with-syntax ([((lhs rhs) ...) (map nt-helper nonterminal-clause*)])
                #'(module (init-nt ...)
                    (module M (init-nt ...) (define lhs rhs) ...)
                    (define init-nt
                      (let ()
                        (import M)
                        (make-top-level-parser init-nt)))
                    ...))))))
      (define (parse-options option*)
        (let f ([option* option*] [htmldir #f] [first-match? #f])
          (if (null? option*)
              (values htmldir first-match?)
              (syntax-case (car option*) ()
                [(name val)
                 (case (datum name)
                   [(html-directory) (f (cdr option*) (datum val) first-match?)]
                   [(first-match) (f (cdr option*) htmldir (datum val))]
                   [else (syntax-error #'name "unrecognized define-grammar option")])]))))
      (syntax-case x ()
        [(_ init-nts (options option ...) top ...)
         (let-values ([(htmldir first-match?) (parse-options #'(option ...))])
           (go #'init-nts #'(top ...) htmldir (if first-match? #'+++ #'++)))]
        [(_ init-nts top ...) (go #'init-nts #'(top ...) #f #'+++)])))

  (indirect-export define-grammar
    result
    zero
    is
    trace-is
    sepby1
    sepby
    optional
    many
    many+
    ++
    +++

    grammar-trace
    format-inp
    trace-is

    make-top-level-parser
  )
)
