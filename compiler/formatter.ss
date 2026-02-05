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

(library (formatter)
  (export print-Lparser parse-file/format)
  (import (except (chezscheme) errorf)
          (utils)
          (streams)
          (nanopass)
          (lparser)
          (parser))

  #|
  print-Lparser (hereafter referred to as "the formatter") is a pretty printer
  for Compact-language programs.  It prints the Compact program represented by
  a specified Lparser program, breaking it into multiple, properly indented lines
  where appropriate.  Comments appearing in the original source program are properly
  inserted into the formatted program.  Since comments are not directly represented
  in an Lparser program, the comments are obtained from a specified token stream
  and correlated with Lparser program points by source locations.

  The formatter operates in three phases:

  1. During the first phase, it scans the input token stream and builds up three
     tables each mapping source locations (src) to comments (cmt).  The tables differ
     by type of comment:

       up: cmt belongs to the form starting at src on a line above src

       left: cmt belongs to the form starting at src to the left of src on the same line.

       right: cmt belongs to the form ending at src to the right of src on the same line

     The formatter does not recognize any comments in the input token stream as
     "down" comments (belonging to a form ending at src on a line below src).
     Instead, it assumes these modify some form further down (even if that is the
     "eof" token).  Similarly, it treats as "right" comments only those that are
     not followed on the same line by some other form.

     The formatter also creates a fourth table containing all of the comments; this
     table is used used only for a diagnostic check that no comments are dropped.

  2. During the second phase, the formatter converts the Lparser program into
     a simple tree structure in which subtrees represent nesting and leaves
     represent either text to be printed or formatting directives.  The formatting
     directives indicate where spaces must appear, where new lines must be started,
     where new lines may be started if necessary, and the amount by which the
     text on a new line should be indented.

     Each element of the tree structure created during this phase is referred to as a "Q".
     "Q" doesn't stand for anything; it's just a short, arbitrary name used to identify
     the elements of the tree.

     A Q is one of the following:

       Qstring:  a record encapsulating a string representing an atomic bit of text to be printed
       Qconcat:  a record encapsulating a sequence of Qs; used for grouping and representing nesting of forms
       fixnum:   used to indicate optional newlines, spacing, and indentation
       nl:       a unique object used to indicate a required newline (not additive)
       nl2:      a unique object used to indicate a required double newline/blank line (not additive)
       nl!:      a unique object used to indicate a required newline (additive)
       nbsp:     a unique object used to represent a space

     A fixnum, nl, nl!, or nbsp should not occur outside of Qconcat

     Every Q has a size:

       Qstring:      essentially, the encapsulated string's length (but see below)
       Qconcat:      essentially, the sum of the sizes of its consituents (but see below)
       fixnum >= 0:  1
       fixnum < 0:   0
       nl, nl2, nl!: 0
       nbsp:         1

     Because of nl, nl2, nl!, and multiline strings (which can arise from source-language
     string constants with embedded newlines), the actual size computation is as
     follows. The actual size of a Qstring is the length of the first line (not
     including the newline) in the text represented by the encapsulated string.
     The actual size of a Qconcat is the maximum length of the lines represented
     by encapsulated sequence of Qs, taking into account nl, nl2, nl!, and multiline
     strings.

     This phase is the most involved because it has to process each kind of Lparser
     input form and token, create Qconcats for nesting grouping and nesting,
     add formatting directives, and insert comments.

     To obviate certain special cases in the numerous places where Qconcats are
     created, the Qconcat record constructor automatically discards empty Qstrings
     and Qconcats along with any fixnum or nbsp directives that precede them.
     Additionaly support for obviating special cases is built into the Q printer
     described below.

  3. During the third phase, the formatter uses a Q printer to render the program from
     the "Q" tree structure, breaking the resulting text into lines where directed
     or necessary to stay within a target line length and indenting new lines
     as directed.

     The Q printer, in essence, handles each kind of Q as follows:

       Qstring: print the contents of the encapsulated string
       Qconcat: recursively print the encapsulated sequence of Qs
       nl:      start a new line if not already at the start of a line
       nl2:     start a new line if not already at the start of a line;
                then another if not after an empty line
       nl!:     start a new line
       nbsp:    print a space, except at the beginning of a line
       fixnum:  possibly start a new line and indent, or possibly print a space

     In more detail, the Q printer maintains a set of state variables:

       q*:        a sequence of Qs to be printed
       col:       the current column
       reset-col: the current column at the start of the current Qconcat
       break?:    should optional new lines be exercised?
       nl?:       either #f indicating not at the start of a line, or
                  n >= 0 representing the number of new lines pending

     The initial values of these variables are:

       q* = (list Q), where Q is the Q for the entire program
       col = 0
       reset-col = 0
       break?: #f
       nl?: 0

     And the Q printer actually handles the forms as follows:

       Qstring: if nl? is a natural number n, print n newlines and col spaces.
                Regardless, print the contents of the encapsulated string.
                If the string is a multiline string, set nl? to 1.  Otherwise,
                increment col by the Qstring's size, and set nl? to 0.
       Qconcat: recur with new bindings for the state variables:
                  q* = list of encapsulated Qs
                  col = outer col
                  reset-col = outer col
                  break? = col + Qconcat's size > target line length
                  nl? = outer nl?
                after processing all of the encapsulated q*, set the outer
                col and nl? to the inner col? and nl?.
       nl:      set col to reset-col; if nl? is #f, set nl? to 1
       nl2:     set col to reset-col; set nl? to 2
       nl!:     set col to reset-col; set nl? to 1 if nl? is #f, otherwise increment nl?
       nbsp:    if nl? is #f, print a space and increemnt col? by 1
                otherwise set col to reset-col
       fixnum:  if either of nl? or break? is not #f, increment col by the
                fixnum's value (if nonnegative) or by one less than the fixnum's
                absolute value (if negative).  If nl? is #f, set nl? to 1.
                If both nl? and break? are #f and fixnum is nonnegative, print
                a space and increment col by 1.

     Some things are worth pointing out here:
       * the Q printer adds newlines and indentation only when it sees a Qstring
       * multiple consecutive nl and nl2? directives are not additive; this eliminates the
         need for some special casing when creating Qconcats (nl! directives are
         additive)
       * The nonnegative fixnum value n and the negative fixnum value -n-1 both
         force a new line when break? is #t and n spaces of indentation when either
         nl? or break? is true, but the negative value does not cause a space to
         be printed otherwise.  For example, -3 and 2 behave the same except only
         causes a space to be added when the line isn't broken.
  |#

  (define-pass print-Lparser : Lparser (ir token-stream target-line-length op) -> * ()
    (definitions
      (define bl ; represents a blank line
        (let ()
          (define-record-type bl)
          (record-writer (record-type-descriptor bl) ; for debugging
            (lambda (x p wr) (put-string p "bl")))
          (make-bl)))

      ; tables for recording comments from the input token stream
      (module (comment-all-table comment-up-table comment-left-table comment-right-table populate-comment-tables!)
        (define comment-all-table (make-hashtable values eqv?))
        (define comment-up-table (make-hashtable values eqv?))
        (define comment-left-table (make-hashtable values eqv?))
        (define comment-right-table (make-hashtable values eqv?))
        (define (populate-comment-tables! token-stream)
          (define (contains-newline? s)
            (let ([n (string-length s)])
              (let loop ([i 0])
                (and (not (fx= i n))
                     (or (char=? (string-ref s i) #\newline)
                         (loop (fx+ i 1)))))))
          (define (contains-two-newlines? s)
            (let ([n (string-length s)])
              (let loop ([i 0] [nl? #f])
                (and (not (fx= i n))
                     (if (char=? (string-ref s i) #\newline)
                         (or nl? (loop (fx+ i 1) #t))
                         (loop (fx+ i 1) nl?))))))
          (let loop ([stream token-stream] [last-nonwhite #f] [rcomment* '()] [rup* '()])
            (if (stream-null? stream)
                (assert (null? rcomment*)) ; can't have comments after the eof token
                (let ([token (stream-car stream)] [stream (stream-cdr stream)])
                  (case (token-type token)
                    [(line-comment)
                     (hashtable-set! comment-all-table (source-object-bfp (token-src token)) token)
                     (let ([rcomment* (cons token rcomment*)])
                       (if last-nonwhite
                           (begin
                             (hashtable-set! comment-right-table
                               (source-object-efp (token-src last-nonwhite))
                               (reverse rcomment*))
                             (loop stream #f '() rup*))
                           (loop stream #f '() (append rcomment* rup*))))]
                    [(block-comment)
                     (hashtable-set! comment-all-table (source-object-bfp (token-src token)) token)
                     (let ([rcomment* (cons token rcomment*)])
                       (if (contains-newline? (token-value token))
                           (if last-nonwhite
                               (begin
                                 (hashtable-set! comment-right-table
                                   (source-object-efp (token-src last-nonwhite))
                                   (reverse rcomment*))
                                 (loop stream #f '() rup*))
                               (loop stream #f '() (append rcomment* rup*)))
                           (loop stream last-nonwhite rcomment* rup*)))]
                    [(whitespace)
                     (let ([bl? (contains-two-newlines? (token-value token))])
                       (define (maybe-add-bl rup*) (if bl? (cons bl rup*) rup*))
                       (if (or bl? (contains-newline? (token-value token)))
                           (if (and last-nonwhite (not (null? rcomment*)))
                               (begin
                                 (hashtable-set! comment-right-table
                                   (source-object-efp (token-src last-nonwhite))
                                   (reverse rcomment*))
                                 (loop stream #f '() (maybe-add-bl rup*)))
                               (loop stream #f '() (maybe-add-bl (append rcomment* rup*))))
                           (loop stream last-nonwhite rcomment* rup*)))]
                    [else
                     (unless (null? rup*)
                       (hashtable-set! comment-up-table
                         (source-object-bfp (token-src token))
                         (reverse rup*)))
                     (unless (null? rcomment*)
                       (hashtable-set! comment-left-table
                         (source-object-bfp (token-src token))
                         (reverse rcomment*)))
                     (if (and (eq? (token-type token) 'string) (contains-newline? (token-value token)))
                         (loop stream #f '() '())
                         (loop stream token '() '()))])))))
        )

      ; basic Q support
      (module (nbsp nl nl2 nl! make-Qstring make-Qconcat
               Q-size Q-multiline?
               print-Q)
        (define nbsp
          (let ()
            (define-record-type nbsp)
            (record-writer (record-type-descriptor nbsp) ; for debugging
              (lambda (x p wr) (put-string p "nbsp")))
            (make-nbsp)))

        (define nl
          (let ()
            (define-record-type nl)
            (record-writer (record-type-descriptor nl) ; for debugging
              (lambda (x p wr) (put-string p "nl")))
            (make-nl)))

        (define nl2
          (let ()
            (define-record-type nl2)
            (record-writer (record-type-descriptor nl2) ; for debugging
              (lambda (x p wr) (put-string p "nl2")))
            (make-nl2)))

        (define nl!
          (let ()
            (define-record-type nl!)
            (record-writer (record-type-descriptor nl!) ; for debugging
              (lambda (x p wr) (put-string p "nl!")))
            (make-nl!)))

        (module (make-Qstring Qstring? Qstring-string Qstring-size Qstring-multiline?)
          (define-record-type Qstring
            (nongenerative)
            (sealed #t)
            (fields string size multiline?)
            (protocol
              (lambda (new)
                (lambda (s)
                  (let ([n (string-length s)])
                    (let loop ([i 0])
                      (if (fx= i n)
                          (new s i #f)
                          (if (char=? (string-ref s i) #\newline)
                              (new s i #t)
                              (loop (fx+ i 1))))))))))
          (record-writer (record-type-descriptor Qstring) ; for debugging
            (lambda (x p wr) (wr (Qstring-string x) p)))
          )

        (module (make-Qconcat Qconcat? Qconcat-q* Qconcat-size Qconcat-multiline?)
          (define-record-type Qconcat
            (nongenerative)
            (sealed #t)
            (fields q* size multiline?)
            (protocol
              (lambda (new)
                (lambda q*
                  ; weed out zero-length q's and fixnums that aren't followed by non-zero-length q's
                  (let loop ([rq* (reverse q*)] [last-size 0] [q* '()])
                    (if (null? rq*)
                        (let ([ret-q* q*])
                          (let loop ([q* q*] [size 0] [max-size 0] [ml? #f])
                            (if (null? q*)
                                (new ret-q* (fxmax max-size size) ml?)
                                (let ([q (car q*)] [q* (cdr q*)])
                                  (if (Q-multiline? q)
                                      (loop q* 0 (fxmax max-size (fx+ size (Q-size q))) #t)
                                      (loop q* (fx+ size (Q-size q)) max-size ml?))))))
                        (let ([q (car rq*)] [rq* (cdr rq*)])
                          (cond
                            [(or (eq? q nl) (eq? q nl2) (eq? q nl!)) (loop rq* 1 (cons q q*))]
                            [(eq? q nbsp)
                             (if (fx= last-size 0)
                                 (loop rq* 0 q*)
                                 (loop rq* 1 (cons q q*)))]
                            [(fixnum? q)
                             (if (fx= last-size 0)
                                 (loop rq* 0 q*)
                                 (loop rq* (if (fx< q 0) 0 1) (cons q q*)))]
                            [else
                             (let ([size (Q-size q)])
                               (loop rq* size (if (fx= size 0) q* (cons q q*))))]))))))))
          (record-writer (record-type-descriptor Qconcat) ; for debugging
            (lambda (x p wr) (wr (Qconcat-q* x) p))))

        (define (Q-size x)
          (cond
            [(Qstring? x) (Qstring-size x)]
            [(Qconcat? x) (Qconcat-size x)]
            [(fixnum? x) (if (fx< x 0) 0 1)]
            [(eq? x nbsp) 1]
            [(or (eq? x nl) (eq? x nl2) (eq? x nl!)) 0]
            [else (internal-errorf 'Q-size "unrecognized Q ~s" x)]))

        (define (Q-multiline? x)
          (cond
            [(Qstring? x) (Qstring-multiline? x)]
            [(Qconcat? x) (Qconcat-multiline? x)]
            [(fixnum? x) #f]
            [(eq? x nbsp) #f]
            [(or (eq? x nl) (eq? x nl2) (eq? x nl!)) #t]
            [else (internal-errorf 'Q-multiline "unrecognized Q ~s" x)]))

        (define (print-Q op target-line-length q)
          (let f ([q* (list q)] [col 0] [reset-col 0] [break? #f] [nl? 0] [sp? #f] [ml? #f])
            (if (null? q*)
                (values col nl? sp? ml?)
                (let ([q (car q*)] [q* (cdr q*)])
                  (cond
                    [(eq? q nl) (f q* reset-col reset-col break? (or nl? 1) #f #f)]
                    [(eq? q nl2) (f q* reset-col reset-col break? 2 #f #f)]
                    [(eq? q nl!) (f q* reset-col reset-col break? (if nl? (fx+ nl? 1) 1) #f #f)]
                    [(eq? q nbsp)
                     (if nl?
                         (f q* reset-col reset-col break? nl? sp? #f)
                         (if (not sp?)
                             (begin
                               (put-char op #\space)
                               (f q* (fx+ col 1) reset-col break? #f #t #f))
                             (f q* col reset-col break? #f sp? #f)))]
                    [(fixnum? q)
                     (if (or nl? break?)
                         (let ([col (fx+ reset-col (if (fx< q 0) (- -1 q) q))])
                           (f q* col reset-col break? (or nl? 1) #f #f))
                         (if (and (fx>= q 0) (not sp?))
                             (begin
                               (put-char op #\space)
                               (f q* (fx+ col 1) reset-col break? #f #t #f))
                             (f q* col reset-col break? #f sp? #f)))]
                    [(Qstring? q)
                     (if ml?
                         (begin
                           (put-string op (Qstring-string q))
                           (f q* col reset-col break? nl? sp? #t))
                         (begin
                           (when nl? (fprintf op "~a~v@t" (make-string nl? #\newline) col))
                           (put-string op (Qstring-string q))
                           (if (Qstring-multiline? q)
                               (f q* (fx+ col 1) reset-col break? 1 #f #t)
                               (f q* (fx+ col (Q-size q)) reset-col break? #f #f #f))))]
                    [(Qconcat? q)
                     (let-values ([(col nl? sp? ml?) (f (Qconcat-q* q) col col (fx> (fx+ col (Q-size q)) target-line-length) nl? sp? ml?)])
                     (f q* col reset-col break? nl? sp? ml?))]
                    [else (internal-errorf 'print-Q "unrecognized Q ~s" q)]))))
          (newline op)))

      ; routines for transfering comments from tables to Qs
      (module (// //before //after)
        (define (format-comment comment force-nl?)
          (cond
            [(eq? comment bl) nl2]
            [else
             (hashtable-delete! comment-all-table (source-object-bfp (token-src comment)))
             (case (token-type comment)
               [(line-comment) (make-Qconcat (make-Qstring (format "//~a" (token-value comment))) nl)]
               [(block-comment)
                (apply make-Qconcat
                  (make-Qstring "/*")
                  (let* ([s (token-value comment)]
                         [n (string-length s)])
                    (let f ([i 0] [j 0])
                      (if (fx= i n)
                          (cons*
                            (make-Qstring (substring s j i))
                            (make-Qstring "*/")
                            (if force-nl? (list nl) '()))
                          (if (char=? (string-ref s i) #\newline)
                              (cons* (make-Qstring (substring s j i)) nl! (f (fx+ i 1) (fx+ i 1)))
                              (f (fx+ i 1) j))))))]
               [else (internal-errorf 'format-comment "unrecognized comment ~s" comment)])]))
        (define (make-Qup-comment comment* q)
          (if (null? comment*)
              q
              (let ([comment (car comment*)] [comment* (cdr comment*)])
                (make-Qconcat
                  (format-comment comment #t)
                  (make-Qup-comment comment* q)))))
        (define (make-Qleft-comment comment* q)
          (if (null? comment*)
              q
              (let ([comment (car comment*)] [comment* (cdr comment*)])
                (make-Qconcat
                  (format-comment comment #f)
                  nbsp
                  (make-Qleft-comment comment* q)))))
        (define (make-Qright-comment comment* q)
          (if (null? comment*)
              q
              (let ([comment (car comment*)] [comment* (cdr comment*)])
                (make-Qconcat
                  (make-Qright-comment comment* q)
                  nbsp (format-comment comment #t)))))
        (module (// //before //after)
          (define ($// src before? after? qth)
            (define (retrieve table fp)
              (let ([a (hashtable-cell table fp '())])
                (let ([comment* (cdr a)])
                  (set-cdr! a '())
                  comment*)))
            ; look outermost-to-innermost for "up" comments so "up" comments are associated with the biggest
            ; possible form, e.g., and entire circuit definition rather than the leading export, pure, or
            ; keyword token.  otherwise we could get something like:
            ;   // this circuit ...
            ;   export
            ;   circuit ...
            ; rather than
            ;   // this circuit ...
            ;   export circuit ...
            (let ([Qup-comment* (if before? (retrieve comment-up-table (source-object-bfp src)) '())])
              ; now process the form
              (let ([q (qth)])
                ; to look innermost to outermost for "left" and "right" comments so these comments are
                ; attacheded to individual tokens rather than being treated as "up" tokens when they
                ; would otherwise be attached to a larger form that spans multiple lines
                (make-Qup-comment
                  Qup-comment*
                  (make-Qleft-comment
                    (if before? (retrieve comment-left-table (source-object-bfp src)) '())
                    (make-Qright-comment
                      (if after? (retrieve comment-right-table (source-object-efp src)) '())
                      q))))))
          (define-syntax //
            (syntax-rules ()
              [(_ ?src ?q) ($// ?src #t #t (lambda () ?q))]))
          (define-syntax //before
            (syntax-rules ()
              [(_ ?src ?q) ($// ?src #t #f (lambda () ?q))]))
          (define-syntax //after
            (syntax-rules ()
              [(_ ?src ?q) ($// ?src #f #t (lambda () ?q))]))))

      ; synthetic Q creators
      (define (make-Qtoken x)
        ; general purpose Q for tokens
        (// (token-src x)
            (make-Qstring (token-string x))))
      (define (add-modifier token? q*)
        ; for modifier tokens like export and sealed
        (if token?
            (cons* (make-Qtoken token?) nbsp q*)
            q*))
      (define (add-closer n m token q*)
        ; for closing tokens like close braces, brackets, parens, and angle brackets.
        ; the before ("up" and "left") tokens are attached to an empty string at the
        ; indentation level of the items within the braces, brackets, parens, and
        ; angle brackets, and the after tokens are attached to the closer itself. Thus
        ; we get:
        ;   struct S {
        ;     x: Field,
        ;     y: Field,
        ;     /* z: Field */
        ;   } // end of struct S
        ; rather than
        ;   struct S {
        ;     x: Field,
        ;     y: Field,
        ;   /* z: Field */ } // end of struct S
        (add-indent n
          (cons
            (//before (token-src token) (make-Qstring ""))
            (add-indent m
              (cons
                (//after (token-src token) (make-Qstring (token-string token)))
                q*)))))
      (define (add-punctuation token? q*)
        ; for punctuation tokens like colons, commas, semicolons
        ; before ("up" and "right") comments are added to an empty string before
        ; the punctuation; with an nbsp that will get discarded if there are no
        ; before comments, so we get:
        ;   export {a, b, c} /* extra exports */;
        ; rather than
        ;   export {a, b, c}/* extra exports */;
        (if token?
            (cons*
              nbsp (//before (token-src token?) (make-Qstring ""))
              (//after (token-src token?) (make-Qstring (token-string token?)))
              q*)
            q*))
      (define (add-indent n? q*)
        ; for conditional indentation
        (if n?
            (cons n? q*)
            q*))
      (define (maybe-add process-what what? q*)
        ; for conditional structured forms like generic parameter lists
        (if what?
            (cons (process-what what?) q*)
            q*))
      (define (add-block stmt proc)
        ; helper for creating Qs for forms with block bodies, e.g., circuit definitions and for loops
        (nanopass-case (Lparser Statement) stmt
          [(block ,src ,lbrace ,stmt* ... ,rbrace)
           (apply make-Qconcat
             (apply make-Qconcat
               (proc (list nbsp (make-Qtoken lbrace))))
             nl
             (fold-right
               (lambda (stmt q*)
                 (cons* 2 (Statement stmt) nl q*))
               (add-closer 2 nl rbrace '())
               stmt*))]
          [else (make-Qconcat (apply make-Qconcat (proc '())) 2 (Statement stmt))]))
      (define (make-Qsep sep* q* m closer?)
        ; for comma- and semicolon-separated lists, possibly with a closer
        (let ([nq (length q*)] [nsep (length sep*)])
          (assert (or (fx= nsep nq) (fx= (fx+ nsep 1) nq))))
        (if (null? q*)
            (if closer?
                (apply make-Qconcat (add-closer #f m closer? '()))
                (make-Qstring ""))
            (apply make-Qconcat
              (car q*)
              (let f ([q* (cdr q*)] [sep* sep*])
                (if (null? q*)
                    (let ([q* (if closer? (add-closer 0 m closer? '()) '())])
                      (if (null? sep*) q* (add-punctuation (car sep*) q*)))
                    (add-punctuation (car sep*) (cons* 0 (car q*) (f (cdr q*) (cdr sep*)))))))))
      )
    (Program : Program (ir) -> * ()
      [(program ,src ,pelt* ... ,eof)
       ; phase 1: map source locations to comments
       (populate-comment-tables! token-stream)
       ; phase 2: create a Q representing the program and all its subforms
       (let ([q (make-Qconcat
                  (apply make-Qconcat
                    (fold-right
                      (lambda (pelt q*) (cons* (Program-Element pelt) nl2 q*))
                      (list (// (token-src eof) (make-Qstring "")))
                      pelt*)))])
         ; phase 3: print the Q
         (print-Q op target-line-length q))
       ; warn about dropped comments.  this shouldn't happen unless things have been dropped
       ; from the original Lparser program, e.g., by a fixup tool
       (let ([vtoken (hashtable-values comment-all-table)])
         (unless (fx= (vector-length vtoken) 0)
           (warningf #f "dropped comments at~{\n~a~}"
                     (map format-source-object (map token-src (vector->list vtoken))))))])
    (Program-Element : Program-Element (ir) -> * (q)
      [(pragma ,src ,kwd ,name ,version-expr ,semicolon)
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd)
             nbsp (make-Qtoken name)
             nbsp (Version-Expression version-expr)
             (add-punctuation semicolon '())))]
      [(include ,src ,kwd ,file ,semicolon)
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd)
             nbsp (make-Qtoken file)
             (add-punctuation semicolon '())))]
      [(module ,src ,kwd-export? ,kwd ,module-name ,generic-param-list? ,lbrace ,pelt* ... ,rbrace)
       (// src
           (apply make-Qconcat
             (apply make-Qconcat
               (add-modifier kwd-export?
                 (cons*
                   (make-Qtoken kwd)
                   nbsp (make-Qtoken module-name)
                   (maybe-add Generic-Param-List generic-param-list?
                     (list 0 (make-Qtoken lbrace))))))
             nl
             (fold-right
               (lambda (pelt q*) (cons* 2 (Program-Element pelt) nl q*))
               (add-closer 2 0 rbrace '())
               pelt*)))]
      [(import ,src ,kwd ,import-selection? ,import-name ,generic-arg-list? ,import-prefix? ,semicolon)
       (define (add-import-selection q*)
         (if import-selection?
             (nanopass-case (Lparser Import-Selection) import-selection?
               [(,lbrace (,ielt* ...) (,comma* ...) ,rbrace ,kwd-from)
                (cons*
                  2 (make-Qtoken lbrace)
                  nbsp (make-Qsep comma* (map Import-Element ielt*) nbsp rbrace)
                  2 (make-Qtoken kwd-from)
                  q*)])
             q*))
       (define (add-prefix q*)
         (if import-prefix?
             (nanopass-case (Lparser Import-Prefix) import-prefix?
               [(,kwd-prefix ,prefix) (cons* 4 (make-Qtoken kwd-prefix) nbsp (make-Qtoken prefix) q*)])
             q*))
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd)
             (add-import-selection
               (cons*
                 nbsp (make-Qtoken import-name)
                 (maybe-add Generic-Arg-List generic-arg-list?
                   (add-prefix (add-punctuation semicolon '())))))))]
      [(export ,src ,kwd ,lbrace (,name* ...) (,comma* ...) ,rbrace ,semicolon?)
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd)
             nbsp
             (make-Qconcat
               (make-Qtoken lbrace)
               nbsp (make-Qsep comma* (map make-Qtoken name*) nbsp rbrace))
             (add-punctuation semicolon? '())))]
      [(public-ledger-declaration ,src ,kwd-export? ,kwd-sealed? ,kwd ,ledger-field-name ,colon ,type ,semicolon)
       (// src
           (apply make-Qconcat
             (add-modifier kwd-export?
               (add-modifier kwd-sealed?
                 (cons*
                   (make-Qtoken kwd)
                   nbsp (make-Qtoken ledger-field-name)
                   (add-punctuation colon
                     (cons*
                       nbsp (Type type)
                       (add-punctuation semicolon '()))))))))]
      [(constructor ,src ,kwd ,parg-list ,blck)
       (// src
           (add-block blck
             (lambda (q*)
               (cons*
                 (make-Qtoken kwd)
                 (Pattern-Argument-List parg-list #f)
                 q*))))]
      [(circuit ,src ,kwd-export? ,kwd-pure? ,kwd ,function-name ,generic-param-list? ,parg-list ,return-type ,blck)
       (// src
           (add-block blck
             (lambda (q*)
               (add-modifier kwd-export?
                 (add-modifier kwd-pure?
                   (cons*
                     (make-Qtoken kwd)
                     nbsp (let ([qfun (apply make-Qconcat
                                        (make-Qtoken function-name)
                                        (maybe-add Generic-Param-List generic-param-list? '()))])
                            (nanopass-case (Lparser Pattern-Argument-List) parg-list
                              [(,lparen (,parg* ...) (,comma* ...) ,rparen)
                               (if (null? parg*)
                                   (apply make-Qconcat
                                     qfun
                                     (make-Qtoken lparen)
                                     (add-closer #f #f rparen '()))
                                   (let ([n (Q-size qfun)])
                                     (apply make-Qconcat
                                       qfun
                                       (make-Qtoken lparen)
                                       (add-indent (and (fx> n 8) -3)
                                         (list
                                           (apply make-Qconcat
                                             (make-Qsep comma* (map Pattern-Argument parg*) #f #f)
                                             (add-closer 0 -1 rparen '())))))))]))
                     (Return-Type return-type)
                     q*))))))]
      [(external ,src ,kwd-export? ,kwd ,function-name ,generic-param-list? ,arg-list ,return-type ,semicolon)
       (// src
           (apply make-Qconcat
             (add-modifier kwd-export?
               (cons*
                 (make-Qtoken kwd)
                 nbsp (make-Qtoken function-name)
                 (maybe-add Generic-Param-List generic-param-list?
                   (cons*
                     (Argument-List arg-list)
                     (Return-Type return-type)
                     (add-punctuation semicolon '())))))))]
      [(witness ,src ,kwd-export? ,kwd ,function-name ,generic-param-list? ,arg-list ,return-type ,semicolon)
       (// src
           (apply make-Qconcat
             (add-modifier kwd-export?
               (cons*
                 (make-Qtoken kwd)
                 nbsp (make-Qtoken function-name)
                 (maybe-add Generic-Param-List generic-param-list?
                   (cons*
                     (Argument-List arg-list)
                     (Return-Type return-type)
                     (add-punctuation semicolon '())))))))]
      [(external-contract ,src ,kwd-export? ,kwd ,contract-name ,lbrace (,ecdecl-circuit* ...) (,sep* ...) ,rbrace ,semicolon?)
       (// src
           (apply make-Qconcat
             (apply make-Qconcat
               (add-modifier kwd-export?
                 (list
                   (make-Qtoken kwd)
                   nbsp (make-Qtoken contract-name)
                   0 (make-Qtoken lbrace))))
             2 (make-Qsep sep* (map External-Contract-Circuit ecdecl-circuit*) #f rbrace)
             (add-punctuation semicolon? '())))]
      [(struct ,src ,kwd-export? ,kwd ,struct-name ,generic-param-list? ,lbrace (,arg* ...) (,sep* ...) ,rbrace ,semicolon?)
       (// src
           (apply make-Qconcat
             (apply make-Qconcat
               (add-modifier kwd-export?
                 (cons*
                   (make-Qtoken kwd)
                   nbsp (make-Qtoken struct-name)
                   (maybe-add Generic-Param-List generic-param-list?
                     (list 0 (make-Qtoken lbrace))))))
             (let ([q* (cons nl (add-closer 2 nl rbrace (add-punctuation semicolon? '())))])
               (let f ([arg* arg*] [sep* sep*])
                 (if (null? arg*)
                     q*
                     (cons*
                       nl 2 (Argument (car arg*))
                       (if (null? sep*)
                           q*
                           (add-punctuation (car sep*) (f (cdr arg*) (cdr sep*))))))))))]
      [(enum ,src ,kwd-export? ,kwd ,enum-name ,lbrace (,elt-name ,elt-name* ...) (,comma* ...) ,rbrace ,semicolon?)
       (// src
           (apply make-Qconcat
             (apply make-Qconcat
               (add-modifier kwd-export?
                 (list
                   (make-Qtoken kwd)
                   nbsp (make-Qtoken enum-name)
                   nbsp (make-Qtoken lbrace))))
             (let ([q* (cons nl (add-closer 2 nl rbrace (add-punctuation semicolon? '())))])
               (let f ([elt-name* (cons elt-name elt-name*)] [comma* comma*])
                 (if (null? elt-name*)
                     q*
                     (cons*
                       nl 2 (make-Qtoken (car elt-name*))
                       (if (null? comma*)
                           q*
                           (add-punctuation (car comma*) (f (cdr elt-name*) (cdr comma*))))))))))])
    (Version-Expression : Version-Expression (ir) -> * (q)
      [,version-atom (Version-Atom version-atom)]
      [(not ,bang ,version-atom)
       (make-Qconcat (make-Qtoken bang) nbsp (Version-Atom version-atom))]
      [(< ,op ,version-atom)
       (make-Qconcat (make-Qtoken op) nbsp (Version-Atom version-atom))]
      [(<= ,op ,version-atom)
       (make-Qconcat (make-Qtoken op) nbsp (Version-Atom version-atom))]
      [(> ,op ,version-atom)
       (make-Qconcat (make-Qtoken op) nbsp (Version-Atom version-atom))]
      [(>= ,op ,version-atom)
       (make-Qconcat (make-Qtoken op) nbsp (Version-Atom version-atom))]
      [(and ,version-expr1 ,op ,version-expr2)
       (make-Qconcat
         (Version-Expression version-expr1)
         0 (make-Qtoken op)
         0 (Version-Expression version-expr2))]
      [(or ,version-expr1 ,op ,version-expr2)
       (make-Qconcat
         (Version-Expression version-expr1)
         0 (make-Qtoken op)
         0 (Version-Expression version-expr2))]
      [(parenthesized ,lparen ,version-expr ,rparen)
       (apply make-Qconcat
         (make-Qtoken lparen)
         (Version-Expression version-expr)
         (add-closer 1 #f rparen '()))])
    (Version-Atom : Version-Atom (ir) -> * (q)
      [,nat (make-Qtoken nat)]
      [,version (make-Qtoken version)])
    (Generic-Param : Generic-Param (ir) -> * (q)
      [(nat-valued ,src ,hashmark ,tvar-name)
       (// src
           (make-Qconcat (make-Qtoken hashmark) (make-Qtoken tvar-name)))]
      [(type-valued ,src ,tvar-name)
       (// src
           (make-Qtoken tvar-name))])
    (Generic-Param-List : Generic-Param-List (ir) -> * (q)
      [(,langle (,generic-param* ...) (,comma* ...) ,rangle)
       (make-Qconcat
         (make-Qtoken langle)
         (make-Qsep comma* (map Generic-Param generic-param*) #f rangle))])
    (Generic-Arg : Generic-Arg (ir) -> * (q)
      [(generic-arg-size ,src ,nat)
       (// src
           (make-Qtoken nat))]
      [(generic-arg-type ,src ,type)
       (// src
           (Type type))])
    (Generic-Arg-List : Generic-Arg-List (ir) -> * (q)
      [(,langle (,generic-arg* ...) (,comma* ...) ,rangle)
       (make-Qconcat
         (make-Qtoken langle)
         (make-Qsep comma* (map Generic-Arg generic-arg*) #f rangle))])
    (Argument : Argument (ir) -> * (q)
      [(,src ,var-name ,colon ,type)
       (// src
           (apply make-Qconcat
             (make-Qtoken var-name)
             (add-punctuation colon
               (cons* nbsp (Type type) '()))))])
    (Argument-List : Argument-List (ir) -> * (q)
      [(,lparen (,arg* ...) (,comma* ...) ,rparen)
       (make-Qconcat
         (make-Qtoken lparen)
         (make-Qsep comma* (map Argument arg*) #f rparen))])
    (Pattern-Argument : Pattern-Argument (ir) -> * (q)
      [(,src ,pattern)
       (// src
           (Pattern pattern))]
      [(,src ,pattern ,colon ,type)
       (// src
           (apply make-Qconcat
             (Pattern pattern)
             (add-punctuation colon
               (cons* nbsp (Type type) '()))))])
    (Const-Binding : Const-Binding (ir) -> * (q)
      [(,src ,parg ,op ,expr)
       (let ([qparg (Pattern-Argument parg)])
         (make-Qconcat
           qparg
           nbsp (make-Qtoken op)
           (if (> (Q-size qparg) 7) 8 nbsp) (Expression expr)))])
    (Pattern-Argument-List : Pattern-Argument-List (ir indent?) -> * (q)
      [(,lparen (,parg* ...) (,comma* ...) ,rparen)
       (apply make-Qconcat
         (make-Qtoken lparen)
         (add-indent (and indent? -5)
           (list (make-Qsep comma* (map Pattern-Argument parg*) #f rparen))))])
    (Pattern : Pattern (ir) -> * (q)
      [,var-name (make-Qtoken var-name)]
      [(tuple ,src ,lbracket (,pattern?* ...) (,comma* ...) ,rbracket)
       (make-Qconcat
         (make-Qtoken lbracket)
         (make-Qsep
           comma*
           (map (lambda (pattern?) (if pattern? (Pattern pattern?) (make-Qstring ""))) pattern?*)
           #f rbracket))]
      [(struct ,src ,lbrace (,pattern-struct-elt* ...) (,comma* ...) ,rbrace)
       (make-Qconcat
         (make-Qtoken lbrace)
         (make-Qsep comma* (map Pattern-Struct-Elt pattern-struct-elt*) #f rbrace))])
    (Pattern-Struct-Elt : Pattern-Struct-Elt (ir) -> * (q)
      [,elt-name (make-Qtoken elt-name)]
      [(,elt-name ,colon ,pattern)
       (apply make-Qconcat
         (make-Qtoken elt-name)
         (add-punctuation colon
           (cons* nbsp (Pattern pattern) '())))])
    (Return-Type : Return-Type (ir) -> * (q)
      [(,colon ,type)
       (apply make-Qconcat
         (add-punctuation colon
           (cons* nbsp (Type type) '())))])
    (External-Contract-Circuit : External-Contract-Circuit (ir) -> * (q)
      [(,src ,kwd-pure? ,kwd ,function-name ,arg-list ,return-type)
       (// src
           (apply make-Qconcat
             (add-modifier kwd-pure?
               (list
                 (make-Qtoken kwd)
                 nbsp (make-Qtoken function-name)
                 (Argument-List arg-list)
                 (Return-Type return-type)))))])
    (Import-Element : Import-Element (ir) -> * (q)
      [(,src ,name) (make-Qtoken name)]
      [(,src ,name ,kwd-as ,name^)
       (// src
           (make-Qconcat (make-Qtoken name) nbsp (make-Qtoken kwd-as) nbsp (make-Qtoken name^)))])
    (Block : Block (ir) -> * (q)
      [(block ,src ,lbrace ,stmt* ... ,rbrace)
       (// src
           (apply make-Qconcat
             (make-Qtoken lbrace)
             nl
             (fold-right
               (lambda (stmt q*)
                 (cons* 2 (Statement stmt) nl q*))
               (add-closer 2 nl rbrace '())
               stmt*)))])
    (Statement : Statement (ir) -> * (q)
      [(statement-expression ,src ,expr ,semicolon)
       (// src
           (apply make-Qconcat
             (Expression expr)
             (add-punctuation semicolon '())))]
      [(return ,src ,kwd ,semicolon)
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd)
             (add-punctuation semicolon '())))]
      [(return ,src ,kwd ,expr ,semicolon)
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd)
             nbsp (Expression expr)
             (add-punctuation semicolon '())))]
      [(const ,src ,kwd (,cbinding ,cbinding* ...) (,comma* ...) ,semicolon)
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd)
             nbsp
             (make-Qsep comma*
                        (map Const-Binding (cons cbinding cbinding*))
                        #f
                        #f)
             (add-punctuation semicolon '())))]
      [(if ,src ,kwd ,lparen ,expr ,rparen ,stmt)
       (// src
           (add-block stmt
             (lambda (q*)
               (cons* (make-Qtoken kwd) nbsp
                      (apply make-Qconcat
                        (make-Qtoken lparen)
                        (Expression expr)
                        (add-closer 1 #f rparen '()))
                      q*))))]
      [(if ,src ,kwd ,lparen ,expr ,rparen ,stmt1 ,kwd-else ,stmt2)
       (define (add-branch stmt nl? q*)
         (nanopass-case (Lparser Statement) stmt
           [(block ,src ,lbrace ,stmt* ... ,rbrace)
            (cons*
              nbsp (make-Qtoken lbrace)
              nl
              (fold-right
                (lambda (stmt q*)
                  (cons* 3 (Statement stmt) nl q*))
                (add-closer 3 nl rbrace q*)
                stmt*))]
           [else (cons* nl 3 (Statement stmt) (add-indent nl? q*))]))
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd) nbsp
             (apply make-Qconcat
               (make-Qtoken lparen)
               (Expression expr)
               (add-closer 1 #f rparen '()))
             (add-branch stmt1 nl
               (cons*
                 0 (make-Qtoken kwd-else)
                 (add-branch stmt2 #f '())))))]
      [(for ,src ,kwd ,lparen ,kwd-const ,var-name ,kwd-of ,nat1 ,dotdot ,nat2 ,rparen ,stmt)
       (// src
           (add-block stmt
             (lambda (q*)
               (cons*
                 (make-Qtoken kwd)
                 nbsp
                 (apply make-Qconcat
                   (make-Qtoken lparen)
                   (make-Qtoken kwd-const)
                   nbsp (make-Qtoken var-name)
                   nbsp (make-Qtoken kwd-of)
                   nbsp (make-Qtoken nat1)
                   (make-Qtoken dotdot)
                   (make-Qtoken nat2)
                   (add-closer 1 #f rparen '()))
                 q*))))]
      [(for ,src ,kwd ,lparen ,kwd-const ,var-name ,kwd-of ,expr ,rparen ,stmt)
       (// src
           (add-block stmt
             (lambda (q*)
               (cons*
                 (make-Qtoken kwd)
                 nbsp
                 (apply make-Qconcat
                   (make-Qtoken lparen)
                   (make-Qtoken kwd-const)
                   nbsp (make-Qtoken var-name)
                   nbsp (make-Qtoken kwd-of)
                   nbsp (Expression expr)
                   (add-closer 1 #f rparen '()))
                 q*))))]
      [,blck (Block blck)])
    (Expression : Expression (ir) -> * (q)
      [(true ,src ,kwd) (// src (make-Qtoken kwd))]
      [(false ,src ,kwd) (// src (make-Qtoken kwd))]
      [(field ,src ,nat) (make-Qtoken nat)]
      [(string ,src ,str) (make-Qtoken str)]
      [(pad ,src ,kwd ,lparen ,nat ,comma ,str ,rparen)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (apply make-Qconcat
               (make-Qtoken lparen)
               (make-Qtoken nat)
               (add-punctuation comma
                 (cons*
                   nbsp (make-Qtoken str)
                   (add-closer 1 #f rparen '()))))))]
      [(assert ,src ,kwd ,lparen ,expr ,comma ,mesg ,rparen)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (apply make-Qconcat
               (make-Qtoken lparen)
               (Expression expr)
               (add-punctuation comma
                 (cons*
                   nbsp (make-Qtoken mesg)
                   (add-closer 1 #f rparen '()))))))]
      [(var-ref ,src ,var-name)
       (// src
           (make-Qtoken var-name))]
      [(default ,src ,kwd ,langle ,type ,rangle)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (apply make-Qconcat
               (make-Qtoken langle)
               (Type type)
               (add-closer 1 #f rangle '()))))]
      [(if ,src ,expr0 ,hook ,expr1 ,colon ,expr2)
       (// src
           (make-Qconcat
             (Expression expr0)
             2 (make-Qtoken hook) nbsp (Expression expr1)
             2 (make-Qtoken colon)
             nbsp (Expression expr2)))]
      [(elt-ref ,src ,expr ,dot ,elt-name)
       (// src
           (make-Qconcat (Expression expr) (make-Qtoken dot) (make-Qtoken elt-name)))]
      [(elt-call ,src ,expr ,dot ,elt-name ,lparen (,expr* ...) (,comma* ...) ,rparen)
       (// src
           (let ([qfun (make-Qconcat
                         (Expression expr)
                         (make-Qtoken dot)
                         (make-Qtoken elt-name))])
             (apply make-Qconcat
               qfun
               (make-Qtoken lparen)
               (add-indent (and (> (Q-size qfun) 7) -3)
                 (list (make-Qsep comma* (map Expression expr*) #f rparen))))))]
      [(tuple ,src ,lbracket (,tuple-arg* ...) (,comma* ...) ,rbracket)
       (// src
           (make-Qconcat
             (make-Qtoken lbracket)
             (make-Qsep comma* (map Tuple-Argument tuple-arg*) #f rbracket)))]
      [(bytes ,src ,kwd ,lbracket (,bytes-arg* ...) (,comma* ...) ,rbracket)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (make-Qtoken lbracket)
             (make-Qsep comma* (map Tuple-Argument bytes-arg*) #f rbracket)))]
      [(tuple-ref ,src ,expr ,lbracket ,index ,rbracket)
       (// src
           (make-Qconcat
             (Expression expr)
             (apply make-Qconcat
               (make-Qtoken lbracket)
               (Expression index)
               (add-closer 1 #f rbracket '()))))]
      [(tuple-slice ,src ,kwd ,langle ,tsize ,rangle ,lparen ,expr ,comma ,index ,rparen)
       (// src
           (make-Qconcat
             (apply make-Qconcat
               (make-Qtoken kwd)
               (make-Qtoken langle)
               (Type-Size tsize)
               (add-closer 1 #f rangle '()))
             (apply make-Qconcat
               (make-Qtoken lparen)
               (Expression expr)
               (add-punctuation comma
                 (cons*
                   0
                   (Expression index)
                   (add-closer 1 #f rparen '()))))))]
      [(= ,src ,expr1 ,op ,expr2)
       (// src
           (make-Qconcat
             (Expression expr1)
             nbsp (make-Qtoken op)
             2 (Expression expr2)))]
      [(+= ,src ,expr1 ,op ,expr2)
       (// src
           (make-Qconcat
             (Expression expr1)
             nbsp (make-Qtoken op)
             3 (Expression expr2)))]
      [(-= ,src ,expr1 ,op ,expr2)
       (// src
           (make-Qconcat
             (Expression expr1)
             nbsp (make-Qtoken op)
             3 (Expression expr2)))]
      [(binop ,src ,expr1 ,op ,expr2)
       (define (same-group? op1 op2)
         (let ([v1 (token-value op1)] [v2 (token-value op2)])
           (or (equal? v1 v2)
               (let f ([group* '((#\+ #\-) ("==" "!=") (#\< "<=" ">=" #\>))])
                 (and (not (null? group*))
                      (if (member v1 (car group*))
                          (member v2 (car group*))
                          (f (cdr group*))))))))
       (let combine-left ([expr expr1] [op* (list op)] [expr* (list expr2)])
         (nanopass-case (Lparser Expression) expr
           [(binop ,src ,expr1 ,op^ ,expr2)
            (guard (same-group? op^ op))
            (combine-left expr1 (cons op^ op*) (cons expr2 expr*))]
           [else (// src
                     (apply make-Qconcat
                       (Expression expr)
                       (fold-right
                         (lambda (expr op q*)
                           (cons* nbsp (make-Qtoken op) 0 (Expression expr) q*))
                         '()
                         expr*
                         op*)))]))]
      [(not ,src ,bang ,expr)
       (// src
           (make-Qconcat (make-Qtoken bang) (Expression expr)))]
      [(map ,src ,kwd ,lparen ,fun ,comma (,expr ,expr* ...) (,comma* ...) ,rparen)
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd)
             (make-Qtoken lparen)
             (Function fun)
             (add-punctuation comma
               (cons*
                 nbsp (make-Qsep comma* (map Expression (cons expr expr*)) #f rparen)
                 '()))))]
      [(fold ,src ,kwd ,lparen ,fun ,comma (,expr0 ,expr ,expr* ...) (,comma* ...) ,rparen)
       (// src
           (apply make-Qconcat
             (make-Qtoken kwd)
             (make-Qtoken lparen)
             (Function fun)
             (add-punctuation comma
               (cons*
                 nbsp (make-Qsep comma* (map Expression (cons* expr0 expr expr*)) #f rparen)
                 '()))))]
      [(call ,src ,fun ,lparen (,expr* ...) (,comma* ...) ,rparen)
       (// src
           (let ([qfun (Function fun)])
             (apply make-Qconcat
               qfun
               (make-Qtoken lparen)
               (add-indent (and (> (Q-size qfun) 7) -3)
                 (list (make-Qsep comma* (map Expression expr*) #f rparen))))))]
      [(new ,src ,tref ,lbrace (,new-field* ...) (,comma* ...) ,rbrace)
       (// src
           (make-Qconcat
             (Type-Ref tref)
             nbsp (make-Qtoken lbrace)
             nbsp (make-Qsep comma* (map New-Field new-field*) nbsp rbrace)))]
      [(seq ,src (,expr* ...) (,comma* ...) ,expr)
       (// src
           (make-Qsep
             comma*
             (map Expression (append expr* (list expr)))
             #f #f))]
      [(cast ,src ,type ,kwd ,expr)
       (// src
           (make-Qconcat (Expression expr) 0 (make-Qtoken kwd) 0 (Type type)))]
      [(disclose ,src ,kwd ,lparen ,expr ,rparen)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (apply make-Qconcat
               (make-Qtoken lparen)
               (Expression expr)
               (add-closer 1 #f rparen '()))))]
      [(parenthesized ,src ,lparen ,expr ,rparen)
       (// src
           (apply make-Qconcat
             (make-Qtoken lparen)
             (Expression expr)
             (add-closer 1 #f rparen '())))])
    (Tuple-Argument : Tuple-Argument (ir) -> * (q)
      [(single ,src ,expr)
       (// src
           (Expression expr))]
      [(spread ,src ,dotdotdot ,expr)
       (// src
           (make-Qconcat (make-Qtoken dotdotdot) (Expression expr)))])
    (New-Field : New-Field (ir) -> * (q)
      [(spread ,src ,dotdotdot ,expr)
       (// src
           (make-Qconcat (make-Qtoken dotdotdot) (Expression expr)))]
      [(positional ,src ,expr)
       (// src
           (Expression expr))]
      [(named ,src ,elt-name ,colon ,expr)
       (// src
           (apply make-Qconcat
             (make-Qtoken elt-name)
             (add-punctuation colon
               (cons* nbsp (Expression expr) '()))))])
    (Function : Function (ir) -> * ()
      [(fref ,src ,function-name ,generic-arg-list?)
       (// src
           (apply make-Qconcat (make-Qtoken function-name) (maybe-add Generic-Arg-List generic-arg-list? '())))]
      [(arrow-block ,src ,parg-list ,return-type? ,arrow ,blck)
       (// src
           (apply make-Qconcat
             (Pattern-Argument-List parg-list #f)
             (maybe-add Return-Type return-type?
               (list
                 0 (make-Qtoken arrow)
                 nbsp (Block blck)))))]
      [(arrow-expr ,src ,parg-list ,return-type? ,arrow ,expr)
       (// src
           (apply make-Qconcat
             (Pattern-Argument-List parg-list #f)
             (maybe-add Return-Type return-type?
               (list
                 0 (make-Qtoken arrow)
                 nbsp (Expression expr)))))]
      [(parenthesized ,src ,lparen ,fun ,rparen)
       (// src
           (apply make-Qconcat
             (make-Qtoken lparen)
             (Function fun)
             (add-closer 1 #f rparen '())))])
    (Type : Type (ir) -> * (q)
      [,tref (Type-Ref tref)]
      [(tboolean ,src ,kwd)
       (// src
           (make-Qtoken kwd))]
      [(tfield ,src ,kwd)
       (// src
           (make-Qtoken kwd))]
      [(tunsigned ,src ,kwd ,langle ,tsize ,rangle)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (apply make-Qconcat
               (make-Qtoken langle)
               (Type-Size tsize)
               (add-closer 1 #f rangle '()))))]
      [(tunsigned ,src ,kwd ,langle ,tsize ,dotdot ,tsize^ ,rangle)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (apply make-Qconcat
               (make-Qtoken langle)
               (Type-Size tsize)
               (make-Qtoken dotdot)
               (Type-Size tsize^)
               (add-closer 1 #f rangle '()))))]
      [(tbytes ,src ,kwd ,langle ,tsize ,rangle)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (apply make-Qconcat
               (make-Qtoken langle)
               (Type-Size tsize)
               (add-closer 1 #f rangle '()))))]
      [(topaque ,src ,kwd ,langle ,opaque-type ,rangle)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (apply make-Qconcat
               (make-Qtoken langle)
               (make-Qtoken opaque-type)
               (add-closer 1 #f rangle '()))))]
      [(tvector ,src ,kwd ,langle ,tsize ,comma ,type ,rangle)
       (// src
           (make-Qconcat
             (make-Qtoken kwd)
             (apply make-Qconcat
               (make-Qtoken langle)
               (Type-Size tsize)
               (add-punctuation comma
                 (cons*
                   0
                   (Type type)
                   (add-closer 1 #f rangle '()))))))]
      [(ttuple ,src ,lbracket (,type* ...) (,comma* ...) ,rbracket)
       (// src
           (make-Qconcat
             (make-Qtoken lbracket)
             (make-Qsep comma* (map Type type*) #f rbracket)))])
    (Type-Ref : Type-Ref (ir) -> * (q)
      [(type-ref ,src ,tvar-name ,generic-arg-list?)
       (// src
           (apply make-Qconcat
             (make-Qtoken tvar-name)
             (maybe-add Generic-Arg-List generic-arg-list? '())))])
    (Type-Size : Type-Size (ir) -> * (q)
      [(type-size ,src ,nat)
       (// src
           (make-Qtoken nat))]
      [(type-size-ref ,src ,tsize-name)
       (// src
           (make-Qtoken tsize-name))])
    )

  (define (parse-file/format source-pathname line-length)
    (let-values ([(token-stream ir) (parse-file/token-stream source-pathname)])
      (let-values ([(op get) (open-string-output-port)])
        (print-Lparser ir token-stream line-length op)
        (get))))
)
