;;; Copyright (c) 2026 R. Kent Dybvig

;;; Permission is hereby granted, free of charge, to any person obtaining a
;;; copy of this software and associated documentation files (the "Software"),
;;; to deal in the Software without restriction, including without limitation
;;; the rights to use, copy, modify, merge, publish, distribute, sublicense,
;;; and/or sell copies of the Software, and to permit persons to whom the
;;; Software is furnished to do so, subject to the following conditions:

;;; The above copyright notice and this permission notice shall be included in
;;; all copies or substantial portions of the Software.

;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
;;; THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;;; DEALINGS IN THE SOFTWARE.

(library (markdown)
  (export %html)
  (import (chezscheme))
  (module %html (<doctype>
                 <html>
                 <head>
                 <meta>
                 <title>
                 <h1>
                 <h2>
                 <h3>
                 <h4>
                 <p>
                 <a>
                 <sup>
                 <em>
                 <b>
                 <span>
                 <table>
                 <tr>
                 <td>
                 html-text nbsp
                )
    (define (<doctype>) (void))
    (define (html-text-char c)
      (case c
        [(#\<) "&lt;"]
        [(#\>) "&gt;"]
        [(#\&) "&amp;"]
        [(#\{) "\\{"]   ; specific to mdx
        [(#\|) "\\|"]   ; specific to mdx
        [(#\return) ""]
        [else c]))
    (define (html-text fmt . args)
      (let ([s (apply format fmt args)])
        (let ([n (string-length s)])
          (do ([i 0 (fx+ i 1)])
            ((fx= i n))
            (display (html-text-char (string-ref s i)))))))
    (define (nbsp) (printf "&nbsp;"))
    (define-syntax <html>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin b1 b2 ...)]))
    (define-syntax <head>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin b1 b2 ...)]))
    (define-syntax <meta>
      (syntax-rules ()
        [(_ ignore ...)
         (void)]))
    (define-syntax <title>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (void)]))
    (define-syntax <h1>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin
           (printf "# ")
           b1 b2 ...
           (newline))]))
    (define-syntax <h2>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin
           (printf "## ")
           b1 b2 ...
           (newline))]))
    (define-syntax <h3>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin
           (printf "### ")
           b1 b2 ...
           (newline))]))
    (define-syntax <h4>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin
           (printf "#### ")
           b1 b2 ...
           (newline))]))
    (define-syntax <p>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin (void) b1 b2 ... (newline))]))
    (define-syntax <a>
      (syntax-rules ()
        [(_ ([?href text]) b1 b2 ...)
         (eq? (datum ?href) 'href)
         (begin
           (printf "[")
           b1 b2 ...
           (printf "](~a)" text))]
        [(_ ([?name text]) b1 b2 ...)
         (eq? (datum ?name) 'name)
         (begin
           (printf "<a name=\"~a\">" text)
           b1 b2 ...
           (printf "</a>"))]))
    (define-syntax <sup>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin (printf "<sup>") b1 b2 ... (printf "</sup>"))]))
    (define-syntax <em>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin (printf "*") b1 b2 ... (printf "*"))]))
    (define-syntax <b>
      (syntax-rules ()
        [(_ () b1 b2 ...)
         (begin (printf "**") b1 b2 ... (printf "**"))]))
    (define-syntax <span>
      (syntax-rules ()
        [(_ (ignore ...) b1 b2 ...)
         (begin (void) b1 b2 ...)]))
    (module ((<table> table-row*) (<tr> table-row* table-col*) (<td> table-col*))
      (define table-row* (make-parameter #f))
      (define table-col* (make-parameter #f))
      (module ((<table> $<table>))
        (define ($<table> th)
          (let* ([row* (parameterize ([table-row* '()])
                         (th)
                         (when (null? (table-row*))
                           (errorf '<table> "table does not have a least one row"))
                         (reverse (table-row*)))]
                 [ncols (let ([n (apply max (map length row*))])
                          (when (fx= n 0)
                            (errorf '<table> "table does not have a least one column"))
                          n)]
                 [row* (map (lambda (row)
                              (append row
                                (make-list
                                  (fxmax 0 (fx- ncols (length row)))
                                  "")))
                            row*)]
                 [w* (fold-left
                       (lambda (w* row)
                         (map (lambda (w col) (max w (string-length col)))
                              w*
                              row))
                       (make-list ncols 0)
                       row*)]
                 [row* (map (lambda (row)
                              (map (lambda (w col)
                                     (string-append col
                                       (make-string
                                         (fxmax 0 (fx- w (string-length col)))
                                         #\space)))
                                   w*
                                   row))
                            row*)])
            (printf "<div className=\"lang-ref-table\">\n")
            (printf "|~{ ~a |~}\n" (map (lambda (w) (make-string w #\space)) w*))
            (printf "|~{~a|~}\n" (map (lambda (w) (make-string (fx+ w 2) #\-)) w*))
            (for-each (lambda (row) (printf "|~{ ~a |~}\n" row)) row*)
            (printf "</div>\n\n")))
        (define-syntax <table>
          (syntax-rules ()
            [(_ () b1 b2 ...)
             ($<table> (lambda () (void) b1 b2 ...))])))
      (define-syntax <tr>
        (syntax-rules ()
          [(_ () b1 b2 ...)
           (begin
             (unless (table-row*) (errorf '<tr> "found <tr> outside of <table>"))
             (parameterize ([table-col* '()])
               (begin (void) b1 b2 ...)
               (table-row* (cons (reverse (table-col*)) (table-row*)))))]))
      (define-syntax <td>
        (syntax-rules ()
          [(_ () b1 b2 ...)
           (begin
             (unless (table-col*) (errorf '<td> "found <td> outside of <tr>"))
             (table-col*
               (cons
                 (with-output-to-string (lambda () (void) b1 b2 ...))
                 (table-col*))))])))
  )
)
