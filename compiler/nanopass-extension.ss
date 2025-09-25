#!chezscheme

;;; Copyright 2023-2024 Input Output (Hong Kong) Ltd.
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;     http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

(library (nanopass-extension)
  (export define-language/pretty)
  (import (chezscheme) (nanopass))

  (define-syntax define-language/pretty
    ; NB: cannot have a grammar symbol named bracket, since bracket is
    ; used to indicate where brackets should be used in pretty-printer output
    (lambda (stx)
      (lambda (ctenv)
        ; terminal and terminal records represent parsed and (in the case of
        ; language extension) constructed define-language clauses
        ; a terminal has a type ttype (with implicit corresponding predicate
        ; ttype?), and a set of grammar symbols t*
        (define-record-type terminal
          (nongenerative)
          (fields ttype t*))
        ; a nonterminal has a name ntname, a set of grammar symbols ntabbrev*,
        ; and a set of productions p*
        (define-record-type nonterminal
          (nongenerative)
          (fields ntname ntabbrev* p*))
        ; each production within a nonterminal consists of an ir, a pretty (=> RHS
        ; with pretty-printer formatting), and eventually a depretty (=> RHS without
        ; formatting, as required by define-language).  pretty might by #f, in which
        ; case depretty is also #f.
        (define-record-type production
          (nongenerative)
          (fields ir pretty (mutable depretty))
          (protocol
            (lambda (new)
              (lambda (ir pretty)
                (new ir pretty #f)))))
        ; variables eventually holding the parsed language name and explicit or
        ; implicit entry clause
        (define language-name)
        (define entry-clause #f)

        ; terminal-ht and nonterminal-ht eventually hold the parsed language
        ; terminals and nonterminals.  terminal-ht maps symbolic ttype names
        ; to terminal records, and nonterminal-ht maps symbolic ntname names
        ; to nonterminal records.
        (define terminal-ht (make-hashtable symbol-hash eq?))
        (define nonterminal-ht (make-hashtable symbol-hash eq?))

        (module (language-info? dump-language-info restore-language-info!)
          (define-record-type language-info
            (nongenerative)
            (fields entry-clause terminal-ht nonterminal-ht))
          (define (dump-language-info)
            (datum->syntax #'*
              (make-language-info entry-clause terminal-ht nonterminal-ht)))
          (define (restore-language-info! info)
            (set! entry-clause (language-info-entry-clause info))
            (set! terminal-ht (hashtable-copy (language-info-terminal-ht info) #t))
            (set! nonterminal-ht (hashtable-copy (language-info-nonterminal-ht info) #t))))

        ; pretty-ht maps symbolic form names to sets of unprocessed pretties.
        ; these are for named forms, e.g., a let form
        (define pretty-ht (make-hashtable symbol-hash eq?))

        ; pretty-subform-ht maps symbolic grammar symbol names to unprocessed pretties.
        ; these are for unnamed subforms, e.g., a binding within a let
        (define pretty-subform-ht (make-hashtable symbol-hash eq?))

        ; pretty-printer formatting consists partly of the directive #f,
        ; which says to introduce a line break if necessary and indent by
        ; the standard indent, or a nonnegative fixnum n, which says to
        ; introduce a line break if necessary and indent by n spaces.
        (define (pretty-format? x) (or (eq? x #f) (fixnum? x)))

        ; grammar symbols can be postfixed by an arbitrary set of digits,
        ; carets, and asterisks.  root-name removes the postfix.
        (define (root-name sym)
          (let ([s (symbol->string sym)])
            (let loop ([i (string-length s)])
              (if (fx= i 0)
                  sym
                  (let ([c (string-ref s (fx- i 1))])
                    (if (or (char<=? #\0 c #\9)
                            (char=? c #\*)
                            (char=? c #\^))
                        (loop (fx- i 1))
                        (string->symbol (substring s 0 i))))))))

        ; parse the language definition, populating terminal-ht and nonterminal-ht
        (let ()
          (define (gather-nonterminal-elts elt*)
            (let f ([elt* elt*])
              (syntax-case elt* (=>)
                [() '()]
                [(ir => pretty elt ...)
                 (cons (make-production #'ir #'pretty)
                       (f #'(elt ...)))]
                [(ir elt ...)
                 (cons (make-production #'ir #f)
                       (f #'(elt ...)))])))
          (define (parse-full-language-clauses! clause*)
            (for-each
              (lambda (clause)
                (syntax-case clause (entry terminals)
                  [(entry name) (set! entry-clause clause)]
                  [(terminals (ttype (t ...)) ...)
                   (and (andmap identifier? #'(ttype ...))
                        (andmap (lambda (t*) (andmap identifier? t*)) #'((t ...) ...)))
                   (for-each
                     (lambda (ttype t*)
                       (hashtable-set! terminal-ht (syntax->datum ttype)
                         (make-terminal ttype t*)))
                     #'(ttype ...)
                     #'((t ...) ...))]
                  [(ntname (ntabbrev ...) elt ...)
                   (and (identifier? #'ntname) (andmap identifier? #'(ntabbrev ...)))
                   (begin
                     (unless entry-clause (set! entry-clause #'(entry ntname)))
                     (hashtable-set! nonterminal-ht (datum ntname)
                       (make-nonterminal
                         #'ntname
                         #'(ntabbrev ...)
                         (gather-nonterminal-elts #'(elt ...)))))]))
              clause*))

          ; we do part of define-language's job here by effectively expanding
          ; a language that extends another into a full language based on the
          ; other, since we need to operate on the full language.
          (define (parse-extend-language-clauses! clause*)
            (for-each
              (lambda (clause)
                (syntax-case clause (entry terminals)
                  [(entry name) (set! entry-clause clause)]
                  [(terminals tclause ...)
                   (for-each
                     (lambda (tclause)
                       (syntax-case tclause (- +)
                         [(- entry ...)
                          (for-each
                            (lambda (entry)
                              (syntax-case entry ()
                                [(ttype (t ...))
                                 (and (identifier? #'ttype) (andmap identifier? #'(t ...)))
                                 (begin
                                   (let ([x (hashtable-ref terminal-ht (datum ttype) #f)])
                                     (unless (and x
                                                  (free-identifier=? #'ttype (terminal-ttype x))
                                                  (equal? (datum (t ...)) (syntax->datum (terminal-t* x))))
                                       (syntax-error entry "unrecognized terminal clause")))
                                   (hashtable-delete! terminal-ht (datum ttype)))]))
                            #'(entry ...))]
                         [(+ entry ...)
                          (for-each
                            (lambda (entry)
                              (syntax-case entry ()
                                [(ttype (t ...))
                                 (and (identifier? #'ttype) (andmap identifier? #'(t ...)))
                                 (begin
                                   (when (hashtable-contains? terminal-ht (datum ttype))
                                     (syntax-error entry "conflicting terminal clause...use - before + when overriding an existing clause"))
                                   (hashtable-set! terminal-ht (datum ttype)
                                     (make-terminal #'ttype #'(t ...))))]))
                            #'(entry ...))]))
                     #'(tclause ...))]
                  [(ntname (ntabbrev ...) ntclause ...)
                   (let ([p* (fold-left
                               (lambda (p* ntclause)
                                 (syntax-case ntclause (- +)
                                   [(- ir ...)
                                    (fold-left
                                      (lambda (p* ir)
                                        (let f ([p* p*])
                                          (when (null? p*) (syntax-error ir "existing production not found to remove"))
                                          (if (equal? (syntax->datum ir) (syntax->datum (production-ir (car p*))))
                                              (cdr p*)
                                              (cons (car p*) (f (cdr p*))))))
                                      p*
                                      #'(ir ...))]
                                   [(+ elt ...) (append (gather-nonterminal-elts #'(elt ...)) p*)]))
                               (let ([x (hashtable-ref nonterminal-ht (datum ntname) #f)])
                                 (if x (nonterminal-p* x) '()))
                               #'(ntclause ...))])
                     (if (null? p*)
                         (hashtable-delete! nonterminal-ht (datum ntname))
                         (hashtable-set! nonterminal-ht (datum ntname)
                           (make-nonterminal #'ntname #'(ntabbrev ...) p*))))]))
              clause*))
          (syntax-case stx (extends)
            [(_ ?language-name (extends parent-language-name) clause ...)
             (begin
               (set! language-name #'?language-name)
               (let ([info (ctenv #'parent-language-name #'define-language/pretty)])
                 (unless (language-info? info) (syntax-error #'parent-language-name "unrecognized language"))
                 (restore-language-info! info))
               (parse-extend-language-clauses! #'(clause ...)))]
            [(_ ?language-name clause ...)
             (begin
               (set! language-name #'?language-name)
               (parse-full-language-clauses! #'(clause ...)))]))

        ; gather all the pretties, populating pretty-ht, and set the depretty
        ; corresponding to each pretty in the production records
        (let ()
          (define grammar-symbol?
            (let ([grammar-symbol-ht (make-hashtable symbol-hash eq?)])
              (vector-for-each
                (lambda (x) (for-each (lambda (t) (hashtable-set! grammar-symbol-ht (syntax->datum t) #t)) (terminal-t* x)))
                (hashtable-values terminal-ht))
              (vector-for-each
                (lambda (x) (for-each (lambda (ntabbrev) (hashtable-set! grammar-symbol-ht (syntax->datum ntabbrev) #t)) (nonterminal-ntabbrev* x)))
                (hashtable-values nonterminal-ht))
              (lambda (sym)
                (hashtable-contains? grammar-symbol-ht (root-name sym)))))

          (define (depretty pretty) ; returns input (by eq?) iff no formatting found
            (define (depretty-elt elt elt*)
              (syntax-case elt ()
                [fmt (pretty-format? (datum fmt)) elt*]
                [_ (cons (depretty elt) elt*)]))
            (syntax-case pretty ()
              [id (identifier? #'id) pretty]
              [(?bracket elt ...)
               (eq? (datum ?bracket) 'bracket)
               (depretty #'(elt ...))]
              [(elt ...)
               (let ([elt* (fold-right depretty-elt '() #'(elt ...))])
                 (if (and (fx= (length elt*) (length #'(elt ...)))
                          (andmap eq? elt* #'(elt ...)))
                     pretty
                     elt*))]))

          (vector-for-each
            (lambda (x)
              (for-each
                (lambda (p)
                  (let ([pretty (production-pretty p)])
                    (when pretty
                      (let ([dx (depretty pretty)])
                        (production-depretty-set! p dx)
                        (unless (eq? dx pretty)
                          (syntax-case pretty ()
                            [(id elt ...)
                             (and (identifier? #'id)
                                  (not (eq? (datum id) 'bracket))
                                  (not (grammar-symbol? (datum id))))
                             ; record a named pretty, taking care to avoid creating a pretty
                             ; for the bracket formatting wrapper and grammar symbols
                             (hashtable-update! pretty-ht (datum id)
                               (lambda (pretty*) (cons #'(_ elt ...) pretty*))
                               '())]
                            [_ (when (fx= (length (nonterminal-p* x)) 1)
                                 ; if we can't create a named pretty, and this is the only production
                                 ; for this nonterminal, we can create a subform pretty that we can
                                 ; eventually use in place of the corresponding grammar symbols in
                                 ; named pretties
                                 (for-each
                                   (lambda (ntabbrev)
                                     (hashtable-set! pretty-subform-ht (syntax->datum ntabbrev) pretty))
                                   (nonterminal-ntabbrev* x)))]))))))
                (nonterminal-p* x)))
            (hashtable-values nonterminal-ht)))

        ; generate the output
        (let ()
          ; pretty-formats processes the named pretties to create the list
          ; of pretty-formats for this language, substituting subform pretties
          ; for for grammar symbols when possible.  it also kills formatting
          ; passed ... in a list, since pretty-format doesn't support that.
          (define (pretty-formats)
            (define (sanitize pretty) ; pretty is a syntax object, return value is an s-expression
              (define cycle-ht (make-hashtable symbol-hash eq?))
              (let sanitize ([pretty pretty])
                (define (maybe-substitute-abbrev sym)
                  (let ([root (root-name sym)])
                    (let ([a (hashtable-cell cycle-ht root #f)])
                      (cond
                        [(and (not (cdr a))
                              (hashtable-ref pretty-subform-ht root #f)) =>
                         (lambda (pretty)
                           (set-cdr! a #t)
                           ; set cycle flag for root to avoid possibly unbounded
                           ; recursion substituting within a substitution
                           (let ([x (sanitize pretty)])
                             (set-cdr! a #f)
                             x))]
                        [else sym]))))
                (define (sanitize-elt elt)
                  (syntax-case elt ()
                    [fmt (pretty-format? (datum fmt)) (datum fmt)]
                    [_ (sanitize elt)]))
                (syntax-case pretty ()
                  [id (identifier? #'id) (maybe-substitute-abbrev (datum id))]
                  [(?bracket elt ...)
                   (eq? (datum ?bracket) 'bracket)
                   `(bracket ,@(sanitize #'(elt ...)))]
                  [(elt ...)
                   (fold-right
                     (lambda (elt elt*)
                       (if (and (identifier? elt) (free-identifier=? elt #'(... ...)))
                           ; pretty-format doesn't allow anything after ..., so discard it
                           (list '...)
                           (cons (sanitize-elt elt) elt*)))
                     '()
                     #'(elt ...))])))

            (let-values ([(vsym vpretty*) (hashtable-entries pretty-ht)])
              (vector->list
                (vector-map
                  (lambda (sym pretty*)
                    (cons sym
                          (if (fx= (length pretty*) 1)
                              (sanitize (car pretty*))
                              `(alt ,@(map sanitize pretty*)))))
                  vsym
                  vpretty*))))

          ; output-language clauses constructs the entry, terminal, and nonterminal clauses
          (define (output-language-clauses)
            #`(#,@(if entry-clause
                      (list entry-clause)
                      ; entry-clause = #f iff no entry clause and no nonterminals were found.
                      '())
               (terminals
                 #,@(map (lambda (x)
                           #`(#,(terminal-ttype x)
                              #,(terminal-t* x)))
                         (vector->list (hashtable-values terminal-ht))))
               #,@(map (lambda (x)
                         #`(#,(nonterminal-ntname x)
                            #,(nonterminal-ntabbrev* x)
                            #,@(let f ([p* (nonterminal-p* x)])
                                 (if (null? p*)
                                     '()
                                     (let ([p (car p*)] [p* (cdr p*)])
                                       (cons (production-ir p)
                                             (if (production-pretty p)
                                                 (cons* #'=> (production-depretty p) (f p*))
                                                 (f p*))))))))
                       (vector->list (hashtable-values nonterminal-ht)))))

          (with-syntax ([language-name language-name]
                        [info (dump-language-info)]
                        [(clause ...) (output-language-clauses)]
                        [language-name-pretty-formats
                         (datum->syntax language-name
                           (string->symbol
                             (format "~a-pretty-formats"
                               (syntax->datum language-name))))]
                        [pfs (datum->syntax #'* (pretty-formats))])
            #'(begin
                (define-language language-name clause ...)
                (define-property language-name define-language/pretty 'info)
                (define (language-name-pretty-formats) 'pfs)))))))
)
