;;; Copyright (c) 2005 R. Kent Dybvig

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

(library (html) (export %html) (import (chezscheme))

(module %html ((<html> <*> attribute $tag)
               (<head> <*> attribute $tag)
               (<body> <*> attribute $tag)
               (<script> <*> attribute $tag)
               (<style> <*> attribute $tag)
               (<title> <*> attribute $tag)
               (<base> <*> attribute $tag)
               (<link> <*> attribute $tag)
               (<meta> <*> attribute $tag)
               (<address> <*> attribute $tag)
               (<blockquote> <*> attribute $tag)
               (<del> <*> attribute $tag)
               (<div> <*> attribute $tag)
               (<h1> <*> attribute $tag)
               (<h2> <*> attribute $tag)
               (<h3> <*> attribute $tag)
               (<h4> <*> attribute $tag)
               (<h5> <*> attribute $tag)
               (<h6> <*> attribute $tag)
               (<ins> <*> attribute $tag)
               (<noscript> <*> attribute $tag)
               (<p> <*> attribute $tag)
               (<pre> <*> attribute $tag)
               (<hr> <*> attribute $tag)
               (<dd> <*> attribute $tag)
               (<dl> <*> attribute $tag)
               (<dt> <*> attribute $tag)
               (<li> <*> attribute $tag)
               (<ol> <*> attribute $tag)
               (<ul> <*> attribute $tag)
               (<table> <*> attribute $tag)
               (<caption> <*> attribute $tag)
               (<colgroup> <*> attribute $tag)
               (<thead> <*> attribute $tag)
               (<tfoot> <*> attribute $tag)
               (<tbody> <*> attribute $tag)
               (<tr> <*> attribute $tag)
               (<td> <*> attribute $tag)
               (<th> <*> attribute $tag)
               (<col> <*> attribute $tag)
               (<form> <*> attribute $tag)
               (<button> <*> attribute $tag)
               (<fieldset> <*> attribute $tag)
               (<legend> <*> attribute $tag)
               (<label> <*> attribute $tag)
               (<select> <*> attribute $tag)
               (<optgroup> <*> attribute $tag)
               (<option> <*> attribute $tag)
               (<textarea> <*> attribute $tag)
               (<input> <*> attribute $tag)
               (<a> <*> attribute $tag)
               (<bdo> <*> attribute $tag)
               (<map> <*> attribute $tag)
               (<object> <*> attribute $tag)
               (<q> <*> attribute $tag)
               (<span> <*> attribute $tag)
               (<sub> <*> attribute $tag)
               (<sup> <*> attribute $tag)
               (<br> <*> attribute $tag)
               (<img> <*> attribute $tag)
               (<area> <*> attribute $tag)
               (<param> <*> attribute $tag)
               (<abbr> <*> attribute $tag)
               (<acronym> <*> attribute $tag)
               (<cite> <*> attribute $tag)
               (<code> <*> attribute $tag)
               (<dfn> <*> attribute $tag)
               (<em> <*> attribute $tag)
               (<kbd> <*> attribute $tag)
               (<samp> <*> attribute $tag)
               (<strong> <*> attribute $tag)
               (<var> <*> attribute $tag)
               (<b> <*> attribute $tag)
               (<big> <*> attribute $tag)
               (<i> <*> attribute $tag)
               (<small> <*> attribute $tag)
               (<tt> <*> attribute $tag)
               <doctype>
               html-text nbsp encode-url-parameter flush-html-output)
  (define $tag
    (lambda (tag attributes text end-tag)
      (define (simple-value? s)
        (define (simple-char? c)
          (or (char<=? #\0 c #\9)
              (char<=? #\a c #\z)
              (char<=? #\A c #\Z)
              (char=? c #\-)
              (char=? c #\.)))
        (let ([n (string-length s)])
          (and (fx> n 0)
               (let f ([i (fx- n 1)])
                 (and (simple-char? (string-ref s i))
                      (or (fx= i 0) (f (fx- i 1))))))))
      (printf "<~a" tag)
      (for-each
        (lambda (a)
          (if (pair? a)
              (let ([value (let ([s (cdr a)])
                             (if (string? s)
                                 s
                                 (format "~a" (cdr a))))])
                (if (simple-value? value)
                    (printf " ~a=~a" (car a) value)
                    (let ([n (string-length value)])
                      (printf " ~a=\"" (car a))
                      (do ([i 0 (fx+ i 1)])
                          ((fx= i n) (write-char #\"))
                        (display
                          (let ([c (string-ref value i)])
                            (if (char=? c #\")
                                "&quot;"
                                (html-text-char c))))))))
              (printf " ~a" a)))
        attributes)
      (printf ">")
      (cond
        [end-tag (let-values ([v* (text)])
                   (printf "</~a>" tag)
                   (apply values v*))]
        [else (text)])))
  (meta define <*>
    (lambda (id)
      (datum->syntax-object id
        (string->symbol
          (string-append "<" (symbol->string (syntax-object->datum id)) ">")))))
  (meta define (attribute x)
    (syntax-case x ()
      [(a v) (identifier? #'a) #'(cons 'a v)]
      [a (identifier? #'a) #''a]
      [else (syntax-error x "improper attribute")]))
  (define-syntax define-tags
    (lambda (x)
      (syntax-case x ()
        [(_ tag ...)
         (with-syntax ([(<tag> ...) (map <*> (syntax->list #'(tag ...)))])
           #'(begin
               (define-syntax <tag>
                 (lambda (x)
                   (syntax-case x ()
                     [(_ (attr (... ...)) text (... ...))
                      (with-syntax ([(attr (... ...))
                                     (map attribute
                                          (syntax->list #'(attr (... ...))))])
                        #'($tag 'tag (list attr (... ...))
                            (lambda () (void) text (... ...)) #t))])))
               ...))])))
  (define-syntax define-endless-tags
    (lambda (x)
      (syntax-case x ()
        [(_ tag ...)
         (with-syntax ([(<tag> ...) (map <*> (syntax->list #'(tag ...)))])
           #'(begin
               (define-syntax <tag>
                 (lambda (x)
                   (syntax-case x ()
                     [(_) #'($tag 'tag '() (lambda () "") #f)]
                     [(_ (attr (... ...)))
                      (with-syntax ([(attr (... ...))
                                     (map attribute
                                       (syntax->list #'(attr (... ...))))])
                        #'($tag 'tag (list attr (... ...))
                            (lambda () "") #f))])))
               ...))])))

 ; top-level
  (define-tags html head body)

 ; head
  (define-tags script style title) ; script also special inline
  (define-endless-tags base link meta)

 ; block-level generic
 ; del and ins are also phrase
  (define-tags address blockquote del div h1 h2 h3 h4 h5 h6 ins noscript p pre)
  (define-endless-tags hr)

 ; lists
  (define-tags dd dl dt li ol ul)

 ; tables
  (define-tags table caption colgroup thead tfoot tbody tr td th)
  (define-endless-tags col)

 ; forms
  (define-tags form button fieldset legend label select optgroup option textarea)
  (define-endless-tags input)

 ; special inline
  (define-tags a bdo map object q span sub sup)
  (define-endless-tags br img area param)

 ; phrase
  (define-tags abbr acronym cite code dfn em kbd samp strong var)

 ; font-style
  (define-tags b big i small tt)

 ; pseudo tags
  (define (<doctype>)
    (printf "<!DOCTYPE html>\n"))

 ;;; other helpers
  (define (html-text-char c)
    (case c
      [(#\<) "&lt;"]
      [(#\>) "&gt;"]
      [(#\&) "&amp;"]
      [(#\return) ""]
      [else c]))

  (define (html-text fmt . args)
    (let ([s (apply format fmt args)])
      (let ([n (string-length s)])
        (do ([i 0 (fx+ i 1)])
            ((fx= i n))
          (display (html-text-char (string-ref s i)))))))

  (define (nbsp) (display-string "&nbsp;"))

  (define encode-url-parameter
    (let ()
      (define get-encoding
        (let ([encoding (make-vector 256)])
          (do ([i 0 (fx+ i 1)])
              ((fx= i 256))
            (let ([c (integer->char i)])
              (cond
                [(or (char<=? #\a c #\z)
                     (char<=? #\A c #\Z)
                     (char<=? #\0 c #\9)
                     (memv c '(#\$ #\- #\_ #\. #\+ #\! #\* #\' #\( #\) #\,)))
                 (vector-set! encoding i c)]
                [(char=? c #\space) (vector-set! encoding i #\+)]
                [else (vector-set! encoding i (format "%~(~2,'0x~)" i))])))
          (lambda (c)
            (let ([n (char->integer c)])
              (if (fx< n 256)
                  (vector-ref encoding c)
                  (errorf 'encode-url-parameter "cannot encode non-latin-1 character ~s" c))))))
      (lambda (s)
        (define (string-insert! s1 i1 s2 n2)
          (do ([i2 0 (fx+ i2 1)] [i1 i1 (fx+ i1 1)])
              ((fx= i2 n2))
            (string-set! s1 i1 (string-ref s2 i2))))
        (let ([n (string-length s)])
          (let f ([i 0] [j 0])
            (if (fx= i n)
                (make-string j)
                (let ([x (get-encoding (string-ref s i))])
                  (if (char? x)
                      (let ([s (f (fx+ i 1) (fx+ j 1))])
                        (string-set! s j x)
                        s)
                      (let ([xn (string-length x)])
                        (let ([s (f (fx+ i 1) (fx+ j xn))])
                          (string-insert! s j x xn)
                          s))))))))))

  (define (flush-html-output) (flush-output-port))
)

)
