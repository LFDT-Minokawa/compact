;;; json.ss
;;; R. Kent Dybvig
;;; August 2023

;;; Some portions of this code are adapted from Chez Scheme
;;; examples/ez-grammar-test.ss, which is covered by the following
;;; copyright notice:
;;;
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

#!chezscheme

;;; A json object is a tree in which each internal node is either an
;;; array of json objects or an object mapping string field names to
;;; json objects.  Each leaf node is a string, number, or one of the
;;; symbols true, false, or null.
;;;
;;; The Scheme representation (accepted by print-json and returned by
;;; read-json and read-json-file) is similar, with arrays represented
;;; by vectors, objects by association lists, strings by strings, numbers
;;; by numbers (specifically, exact integers or inexact reals), true
;;; by #t, false by #f, and null by the value of (void),

(library (json)
  (export open-json-file read-json read-json-file replace-value-in-json print-json)
  (import (except (chezscheme) errorf)
          (utils)
          (state-case))

  ;;; this json reader attempts to follow https://datatracker.ietf.org/doc/html/rfc8259
  ;;; with the exception that if allow-comments? is true, C-style comments are allowed
  ;;; and is treated as whitespace.

  (define-record-type (token $make-token token?)
    (nongenerative)
    (fields type value bfp efp))

  (define-record-type xbfp
    (nongenerative)
    (fields pos line col))

  (define xbfp0 (make-xbfp 0 1 1))

  (define (make-json-lexer sfd ip allow-comments?)
    (module (getc ungetc whitespace! make-token current-src)
      (define prev-pos xbfp0)
      (define pos 0)
      (define line 1)
      (define col 1)
      (define preceding-line-final-col #f)
      (define (getc)
        (let ([c (get-char ip)])
          (set! pos (+ pos 1))
          (if (eqv? c #\newline)
              (begin
                (set! line (+ line 1))
                (set! preceding-line-final-col col)
                (set! col 1))
              (set! col (+ col 1)))
          c))
      (define (ungetc c)
        (set! pos (- pos 1))
        (if (eqv? col 1)
            (begin
              (unless preceding-line-final-col (internal-errorf 'json-lexer "invalid ungetc"))
              (set! col preceding-line-final-col)
              (set! preceding-line-final-col #f)
              (set! line (- line 1)))
            (set! col (- col 1)))
        (unless (eof-object? c) (unget-char ip c)))
      (define (whitespace!) (set! prev-pos (make-xbfp pos line col)))
      (define (make-token type value)
        (let ([tok ($make-token type value prev-pos pos)])
          (set! prev-pos (make-xbfp pos line col))
          tok))
      (define (current-src offset)
        (let-values ([(pos line col offset)
                      (if (and (< offset 0) (= col 1) preceding-line-final-col)
                          (values (- pos 1) (- line 1) preceding-line-final-col (+ offset 1))
                          (values pos line col offset))])
          ; refuse to wrap around to earlier lines for which we don't have final-column numbers
          (let* ([offset (max offset (- 1 col))]
                 [col (+ col offset)]
                 [pos (+ pos offset)])
            (make-source-object sfd pos pos line col)))))
    (define (unexpected c)
      (source-errorf (current-src -1) "unexpected ~a"
        (case c
          [(#!eof) "eof"]
          [(#\newline) "newline"]
          [else (format "character '~c'" c)])))
    (lambda ()
      (let-values ([(sp get-buf) (open-string-output-port)])
        (define return-token
          (case-lambda
            [(type) (make-token type type)]
            [(type value) (make-token type value)]))
        (define-syntax define-state-case
          (syntax-rules (eof else)
            [(_ ?def-id ?char-id clause ...)
             (identifier? #'?def-id)
             (define-state-case (?def-id) ?char-id clause ...)]
            [(_ (?def-id . args) ?char-id (eof eof1 eof2 ...) clause ... (else else1 else2 ...))
             (and (identifier? #'?def-id) (identifier? #'?char-id))
             (define (?def-id . args)
               (let ([?char-id (getc)])
                 (state-case ?char-id (eof eof1 eof2 ...) clause ... (else else1 else2 ...))))]
            [(_ (?def-id . args) ?char-id clause ... (else else1 else2 ...))
             (and (identifier? #'?def-id) (identifier? #'?char-id))
             (define (?def-id . args)
               (let ([?char-id (getc)])
                 (let ([f (lambda () else1 else2 ...)])
                   (state-case ?char-id (eof (f)) clause ... (else (f))))))]))
        (define-state-case lex c
          [eof (return-token 'eof)]
          [(#\space #\tab #\newline #\return) (whitespace!) (lex)]
          [(#\/)
           (unless allow-comments? (unexpected c))
           (lex-comment)
           (whitespace!)
           (lex)]
          [#\[ (return-token 'begin-array)]
          [#\] (return-token 'end-array)]
          [#\{ (return-token 'begin-object)]
          [#\} (return-token 'end-object)]
          [#\" (lex-string)]
          [#\: (return-token 'name-separator)]
          [#\, (return-token 'value-separator)]
          [#\- (lex-minus)]
          [#\0 (lex-zero 1)]
          [((#\0 - #\9)) (lex-int 1 (char- c #\0))]
          [((#\a - #\z)) (lex-identifier c)]
          [else (unexpected c)])
        (module (lex-comment)
          (define-state-case lex-comment c
            [#\* (lex-block-comment)]
            [#\/ (lex-line-comment)]
            [else (unexpected c)])
          (define-state-case lex-line-comment c
            [eof (ungetc c) (void)]
            [#\newline (void)]
            [else (lex-line-comment)])
          (define (lex-block-comment)
            (define-state-case maybe-end-comment c
              [eof (unexpected c)]
              [#\/ (void)]
              [else (lex-block-comment)])
            (define-state-case maybe-nested-comment c
              [eof (unexpected c)]
              [#\* (source-errorf (current-src -2) "attempt to nest block comment")]
              [#\/ (maybe-nested-comment)]
              [else (lex-block-comment)])
            (let ([c (getc)])
              (state-case c
                [eof (unexpected c)]
                [#\* (maybe-end-comment)]
                [#\/ (maybe-nested-comment)]
                [else (lex-block-comment)]))))
        (module (lex-string)
          (define-state-case (lex-string) c
            [eof (unexpected c)]
            [#\" (return-token 'string (get-buf))]
            [#\\ (backslash)]
            [else
             (let ([n (char->integer c)])
               (unless (or (<= #x20 n #x21)
                           (<= #x23 n #x5b)
                           (<= #x5d n #x10FFFF))
                 (unexpected c)))
             (put-char sp c)
             (lex-string)])
          (define-state-case (backslash) c
            [(#\" #\\ #\/) (put-char sp c) (lex-string)]
            [#\b (put-char sp #\backspace) (lex-string)]
            [#\f (put-char sp #\page) (lex-string)]
            [#\n (put-char sp #\newline) (lex-string)]
            [#\r (put-char sp #\return) (lex-string)]
            [#\t (put-char sp #\tab) (lex-string)]
            [#\u (hexchar 0 4)]
            [else (unexpected c)])
          (define-state-case (hexchar a n) c
            [((#\0 - #\9)) (hexchar-next (+ (* a 16) (char- c #\0)) n)]
            [((#\a - #\f)) (hexchar-next (+ (* a 16) (fx+ (char- c #\a) 10)) n)]
            [((#\A - #\F)) (hexchar-next (+ (* a 16) (fx+ (char- c #\A) 10)) n)]
            [else (unexpected c)])
          (define (hexchar-next a n)
            (if (fx= n 1)
                (begin
                  (put-char sp (integer->char a))
                  (lex-string))
                (hexchar a (fx- n 1)))))
        (module (lex-minus lex-zero lex-int)
          (define-state-case (lex-minus) c
            [#\0 (lex-zero -1)]
            [((#\1 - #\9)) (lex-int -1 (char- c #\0))]
            [else (unexpected c)])
          (define-state-case (lex-zero s) c
            [#\. (lex-frac s 0)]
            [#\e (lex-exp (if (< s 0) -0.0 +0.0))]
            [((#\1 - #\9)) (unexpected c)]
            [else (ungetc c) (return-token 'number (if (< s 0) -0.0 +0.0))])
          (define-state-case (lex-int s a) c
            [((#\0 - #\9)) (lex-int s (+ (* a 10) (char- c #\0)))]
            [#\. (lex-frac s a)]
            [#\e (lex-exp (* s a))]
            [else (ungetc c) (return-token 'number (* s a))])
          (define-state-case (lex-frac s a) c
            [((#\0 - #\9)) (lex-frac1 s (+ (* a 10) (char- c #\0)) 1)]
            [else (unexpected c)])
          (define-state-case (lex-frac1 s a e) c
            [((#\0 - #\9)) (lex-frac1 s (+ (* a 10) (char- c #\0)) (+ e 1))]
            [#\e (lex-exp (* s (/ a (expt 10 e))))]
            [else (ungetc c) (return-token 'number (* s (/ a (expt 10 e))))])
          (define-state-case (lex-exp a) c
            [#\- (lex-exp1 a -1)]
            [#\+ (lex-exp1 a +1)]
            [((#\0 - #\9)) (lex-exp2 a 1 (char- c #\0))]
            [else (unexpected c)])
          (define-state-case (lex-exp1 a s) c
            [((#\0 - #\9)) (lex-exp2 a s (char- c #\0))]
            [else (unexpected c)])
          (define-state-case (lex-exp2 a s e) c
            [((#\0 - #\9)) (lex-exp2 a s (+ (* e 10) (char- c #\0)))]
            [else (ungetc c) (return-token 'number (* a (expt 10 (* s e))))]))
        (module (lex-identifier)
          (define-state-case next c
            [((#\a - #\z)) (lex-identifier c)]
            [else (ungetc c) (return-token 'id (string->symbol (get-buf)))])
          (define (lex-identifier c)
            (put-char sp c)
            (next)))
        (lex))))

  (define-record-type json-file
    (nongenerative)
    (fields sfd ip lexer)
    (protocol
      (lambda (new)
        (lambda (sfd ip allow-comments?)
          (new sfd ip (make-json-lexer sfd ip allow-comments?))))))

  (define (format-token token)
    (format "~s" (token-value token)))

  (define (expected jf token message)
    (let ([src (let ([bfp (token-bfp token)] [efp (token-efp token)])
                 (make-source-object
                   (json-file-sfd jf)
                   (xbfp-pos bfp)
                   efp
                   (xbfp-line bfp)
                   (xbfp-col bfp)))])
      (source-errorf src "expected ~a (received ~a)" message (format-token token))))

  (define (get-token jf)
    ((json-file-lexer jf)))

  (define (json-text jf)
    (let ([token (get-token jf)])
      (case (token-type token)
        [(eof) #f]
        [(begin-array) (json-array jf)]
        [(begin-object) (json-object jf)]
        [else (expected jf token "object or array")])))

  (define (json-object jf)
    (let ([token (get-token jf)])
      (case (token-type token)
        [(end-object) '()]
        [else (let ([m (json-member jf token)])
                (cons m (json-object-tail jf)))])))

  (define (json-object-tail jf)
    (let ([token (get-token jf)])
      (case (token-type token)
        [(end-object) '()]
        [(value-separator)
         (let ([m (json-member jf (get-token jf))])
           (cons m (json-object-tail jf)))]
        [else (expected jf token "comma or close brace")])))

  (define (json-array jf)
    (list->vector
      (let ([token (get-token jf)])
        (case (token-type token)
          [(end-array) '()]
          [else (let ([v (json-value jf token)])
                  (cons v (json-array-tail jf)))]))))

  (define (json-array-tail jf)
    (let ([token (get-token jf)])
      (case (token-type token)
        [(end-array) '()]
        [(value-separator)
         (let ([v (json-value jf (get-token jf))])
           (cons v (json-array-tail jf)))]
        [else (expected jf token "comma or close bracket")])))

  (define (json-value jf token)
    (case (token-type token)
      [(id)
       (case (token-value token)
         [(false) #f]
         [(true) #t]
         [(null) (void)]
         [else (expected jf token "json value")])]
      [(number string) (token-value token)]
      [(begin-array) (json-array jf)]
      [(begin-object) (json-object jf)]
      [else (expected jf token "value")]))

  (define (json-member jf token)
    (case (token-type token)
      [(string) (cons (token-value token) (json-member-colon jf))]
      [else (expected jf token "string")]))

  (define (json-member-colon jf)
    (let ([token (get-token jf)])
      (case (token-type token)
        [(name-separator) (json-value jf (get-token jf))]
        [else (expected jf token "colon")])))

  (define open-json-file
    (case-lambda
      [(fn) (open-json-file fn #f)]
      [(fn allow-comments?)
       (let* ([ip (open-file-input-port fn)]
              [sfd (make-source-file-descriptor fn ip #t)]
              [ip (transcoded-port ip (native-transcoder))])
         (make-json-file sfd ip allow-comments?))]))

  (define (read-json jf)
    (let ([x (json-text jf)])
      (let ([token (get-token jf)])
        (case (token-type token)
          [(eof) x]
          [else (expected jf token "end-of-file")]))))

  (define read-json-file
    (case-lambda
      [(fn) (read-json-file fn #f)]
      [(fn allow-comments?)
       (read-json (open-json-file fn allow-comments?))]))

  (module (replace-value-in-json)
    (define (replace-value-in-json json-file key* new-value)
      (let* ([jf (open-json-file json-file #t)]
             [json (read-json jf)]
             [updated-json (replace json key* new-value)])
        (when (file-exists? json-file) (delete-file json-file))
        (let* ([op (open-file-output-port json-file)]
               [textual-op (transcoded-port op (native-transcoder))])
          (print-json textual-op updated-json)
          (close-output-port textual-op)
          (close-input-port (json-file-ip jf)))))

    (define (replace json path new-value)
      (cond
        [(null? path) json]
        [(and (pair? json) (list? json))
         (if (equal? (car path) (caar json))
             (if (null? (cdr path))
                 (cons* (cons (caar json) new-value) (cdr json))
                 (cons* (cons (caar json) (replace (cdar json) (cdr path) new-value))
                        (replace (cdr json) (cdr path) new-value)))
             (cons* (car json) (replace (cdr json) path new-value)))]
        [(and (pair? json) (not (list? json)))
         (if (equal? (car path) (car json))
             (if (null? (cdr path))
                 (cons (car json) new-value)
                 (cons (car json) (replace (cdr json) (cdr path) new-value)))
             (cons (car json) (replace (cdr json) path new-value)))]
        [(vector? json)
         (vector-map
           (lambda (js) (replace js path new-value))
           json)]
        [else json])))

  (define (print-json op json)
    (define (indent i)
      (fprintf op "\n~a" (make-string i #\space)))
    (define (print-string s)
      (put-char op #\")
      (let ([n (string-length s)])
        (do ([i 0 (fx+ i 1)])
            ((fx= i n))
          (let ([c (string-ref s i)])
            (case c
              [(#\") (put-string op "\\\"")]
              [(#\\) (put-string op "\\\\")]
              [(#\backspace) (put-string op "\\b")]
              [(#\page) (put-string op "\\f")]
              [(#\newline) (put-string op "\\n")]
              [(#\return) (put-string op "\\r")]
              [(#\tab) (put-string op "\\t")]
              [else
               (if (char<=? #\x20 c #\x10ffff)
                   (put-char op c)
                   (fprintf op "u~4,'0x" c))]))))
      (put-char op #\"))
    (define (f json i)
      (cond
        [(string? json) (print-string json)]
        [(vector? json)
         (fprintf op "[")
         (let ([i (fx+ i 2)])
           (let ([n (vector-length json)])
             (unless (fx= n 0)
               (let loop ([j 0])
                 (indent i)
                 (f (vector-ref json j) i)
                 (let ([j (fx+ j 1)])
                   (unless (fx= j n)
                     (fprintf op ",")
                     (loop j)))))))
         (indent i)
         (fprintf op "]")]
        [(and (list? json) (andmap pair? json))
         (fprintf op "{")
         (let ([i (fx+ i 2)])
           (unless (null? json)
             (let loop ([json+ json])
               (indent i)
               (let ([a (car json+)])
                 (fprintf op "\"~a\": " (car a))
                 (f (cdr a) i))
               (let ([json* (cdr json+)])
                 (unless (null? json*)
                   (fprintf op ",")
                   (loop json*))))))
         (indent i)
         (fprintf op "}")]
        [(and (integer? json) (exact? json)) (fprintf op "~d" json)]
        [(and (real? json) (inexact? json)) (fprintf op "~g" json)]
        [(boolean? json) (put-string op (if json "true" "false"))]
        [(eq? json (void)) (put-string op "null")]
        [else (internal-errorf 'print-json "unexpected input ~s" json)]))
    (f json 0))
)

#!eof

cat << END > /tmp/test.json
{
  "dependencies": {
    "string": "hello",
    "true": true,
    "false": false,
    "null": null,
    "zero": 0,
    "int": 1234567890,
    "frac": 1.5,
    "exp": 23e5,
    "frac/exp": 1.5e27,
    "-zero": -0,
    "-int": -1234567890,
    "-frac": -1.5,
    "-exp": -23e5,
    "-frac/exp": -1.5e27,
    "array": [ "a", 0, 123 ]
  }
}
[ "hello",
  true,
  false,
  null,
  0,
  1234567890,
  1.5,
  23e5,
  1.5e27,
  -0,
  -1234567890,
  -1.5,
  -23e5,
  -1.5e27,
  { "string": "a", "zero": 0, "int": 123}
]
END
echo '(import (json)) (equal? (read-json-file "/tmp/test.json") (read))' | scheme -q << END
((("dependencies"
    ("string" . "hello")
    ("true" . true)
    ("false" . false)
    ("null" . null)
    ("zero" . 0.0)
    ("int" . 1234567890)
    ("frac" . 3/2)
    ("exp" . 2300000)
    ("frac/exp" . 1500000000000000000000000000)
    ("-zero" . -0.0)
    ("-int" . -1234567890)
    ("-frac" . -3/2)
    ("-exp" . -2300000)
    ("-frac/exp" . -1500000000000000000000000000)
    ("array" . #("a" 0.0 123))))
  #("hello" true false null
    0.0 1234567890 3/2 2300000 1500000000000000000000000000
    -0.0 -1234567890 -3/2 -2300000 -1500000000000000000000000000
    (("string" . "a") ("zero" . 0.0) ("int" . 123))))
END

