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

(library (utils)
  (export not-implemented cannot-happen
          compact-input-transcoder compact-path relative-path find-source-pathname
          register-source-root! registered-source-root
          register-target-pathname! registered-target-pathname
          register-source-pathname! registered-source-pathnames
          unregister-pathnames!
          verbose-source-path? source-object<? format-source-object
          parent-src
          errorf internal-errorf external-errorf error-accessing-file pending-errorf source-errorf source-warningf
          format-condition
          maplr maplr2 compose shell string-prefix? rm-rf mkdir-p
          to-camel-case
          source-error-condition?
          make-halt-condition halt-condition?
          pending-conditions
          stdlib-sfd stdlib-src?
          renaming-table record-alias!)
  (import (except (chezscheme) errorf))

  ; when set, renaming-table maps src -> (old-name . new-name) and is used by the fixup tool to
  ; replace snake_case names with camelCase in the standard library and ledger ADTs
  (define renaming-table (make-parameter #f))
  (define (record-alias! src old-name new-name)
    (cond
      [(renaming-table) =>
       (lambda (ht) (hashtable-set! ht src (cons old-name new-name)))]
      [else
       (pending-errorf src
                       "apparent use of an old standard-library / ledger operator name ~a:\n    the new name is ~a"
                       old-name new-name)]))

  (define stdlib-sfd (make-parameter #f))
  (define (stdlib-src? src) (eq? (source-object-sfd src) (stdlib-sfd)))

  (define pending-conditions (make-parameter '()))

  (define-condition-type &source-error-condition &condition
    make-source-error-condition source-error-condition?)

  (define-condition-type &halt-condition &condition
    make-halt-condition halt-condition?)

  (define-syntax not-implemented (identifier-syntax #f))
  (define-syntax cannot-happen (identifier-syntax #f))

  ; this transcoder is used when reading compact source files and when looking
  ; up source positions in compact source files.  (eol-style lf) has the effect
  ; of converting crlf (and other less common line endings) into lf.
  (define compact-input-transcoder (make-transcoder (utf-8-codec) (eol-style lf)))

  (define compact-path
    (make-parameter
      (let ()
        (define (split-search-path str)
          (let ([n (string-length str)])
            (let f ([i 0] [j 0])
              (if (fx= j n)
                  (if (fx= i j) '() (list (substring str i j)))
                  (if (char=? (string-ref str j) (if (directory-separator? #\\) #\; #\:))
                      (cons (substring str i j) (f (fx+ j 1) (fx+ j 1)))
                      (f i (fx+ j 1)))))))
        (split-search-path (or (getenv "COMPACT_PATH") "")))))

  (module (register-source-root! registered-source-root
           register-target-pathname! registered-target-pathname
           register-source-pathname! registered-source-pathnames
           unregister-pathnames!)
    (define declared-source-root #f)
    (define (register-source-root! x) (set! declared-source-root x))
    (define (registered-source-root) declared-source-root)

    (define target-pathname #f)
    (define (register-target-pathname! x) (set! target-pathname x))
    (define (registered-target-pathname) target-pathname)

    (define source-pathname* '())
    (define (register-source-pathname! x) (set! source-pathname* (cons x source-pathname*)))
    (define (registered-source-pathnames) source-pathname*)

    (define (unregister-pathnames!)
      (set! declared-source-root #f)
      (set! target-pathname #f)
      (set! source-pathname* '())))

  (define relative-path (make-parameter #f))

  (define (find-source-pathname src pathname err)
    (let ([pathname (format "~a.compact" pathname)])
      (or (and (file-exists? pathname) pathname)
          (and (not (path-absolute? pathname))
               (ormap
                 (lambda (dir)
                   (let ([pathname (format "~a/~a" dir pathname)])
                     (and (file-exists? pathname) pathname)))
                 (if (relative-path)
                     (cons (relative-path) (compact-path))
                     (compact-path))))
          (err pathname))))

  (define (source-object<? src1 src2)
    (let ([path1 (source-file-descriptor-path (source-object-sfd src1))]
          [path2 (source-file-descriptor-path (source-object-sfd src2))])
      (or (string<? path1 path2)
          (and (string=? path1 path2)
               (or (< (source-object-bfp src1) (source-object-bfp src2))
                   (and (= (source-object-bfp src1) (source-object-bfp src2))
                        (< (source-object-efp src1) (source-object-efp src2))))))))

  (define parent-src (make-parameter #f))
  (define verbose-source-path? (make-parameter #f))
  (define (format-source-object src)
    (if (stdlib-src? src)
        "<standard library>"
        (let ([path (let ([same-as-parent? (and (parent-src)
                                                (eq? (source-object-sfd src)
                                                     (source-object-sfd (parent-src))))])
                      (and (not same-as-parent?)
                           (let ([full-path (source-file-descriptor-path (source-object-sfd src))])
                             (if (verbose-source-path?)
                                 full-path
                                 (let ([short-path (path-last full-path)])
                                   (let f ([path* (registered-source-pathnames)] [seen? #f])
                                     (if (null? path*)
                                         short-path
                                         (if (string=? (path-last (car path*)) short-path)
                                             (if seen? full-path (f (cdr path*) #t))
                                             (f (cdr path*) seen?)))))))))])
          (call-with-values
            (lambda () (locate-source-object-source src #t #f))
            (case-lambda
              [() (format "~@[~a ~]character ~s" path (source-object-bfp src))]
              [(ignore-path line col) (format "~@[~a ~]line ~s char ~s" path line col)])))))

  (define-syntax errorf
    (lambda (q)
      (syntax-error q "use internal-errorf to report internal compiler errors, pending-errorf or source-errorf to report errors in the input program")))

  (module (error-accessing-file pending-errorf source-errorf source-warningf external-errorf)
    (define (go message irritants base-cond raise)
      (call/cc
        (lambda (k)
          (raise
            (condition
              base-cond
              (make-source-error-condition)
              (make-format-condition)
              (make-message-condition message)
              (make-irritants-condition irritants)
              (make-continuation-condition k))))))
    (define (error-accessing-file c action)
      (if (message-condition? c)
          (let ([msg (condition-message c)]
                [irritants (if (irritants-condition? c) (condition-irritants c) '())])
            (go "error ~a: ~a"
                (list action
                      (if (format-condition? c)
                          (apply format msg irritants)
                          (if (null? irritants)
                              msg
                              (format "~a: ~{~a~^, ~}" msg irritants))))
                (make-serious-condition)
                raise))
          (go "error ~a" action (make-serious-condition) raise)))
    (define (external-errorf msg . arg*)
      (go msg arg* (make-serious-condition) raise))
    (define-syntax pending-errorf
      (syntax-rules ()
        [(_ ?src ?msg ?arg ...)
         (let ([c (source-conditionf ?src ?msg (list ?arg ...) (make-serious-condition) values)])
           (pending-conditions (cons c (pending-conditions))))]))
    (indirect-export pending-errorf source-conditionf)
    (define-syntax source-errorf
      (syntax-rules ()
        [(_ ?src ?msg ?arg ...)
         (source-conditionf ?src ?msg (list ?arg ...) (make-serious-condition) raise)]))
    (indirect-export source-errorf source-conditionf)
    (define-syntax source-warningf
      (syntax-rules ()
        [(_ ?src ?msg ?arg ...)
         (source-conditionf ?src ?msg (list ?arg ...) (make-warning) raise-continuable)]))
    (indirect-export source-warningf source-conditionf)
    (define-syntax source-conditionf
      (syntax-rules ()
        [(_ ?src ?msg ?arg* ?base-cond ?raise)
         (let ([src ?src])
           (let ([arg* (parameterize ([parent-src src]) ?arg*)])
             ($source-conditionf src ?msg arg* ?base-cond ?raise)))]))
    (indirect-export source-conditionf $source-conditionf)
    (define ($source-conditionf src msg arg* base-cond raise)
      (go "~a:\n  ~?"
          (list (parameterize ([parent-src #f]) (format-source-object src))
                msg
                arg*)
          base-cond
          raise)))

  (indirect-export source-errorf parent-src)

  (module (format-condition)
    (define (fmt s line-length)
      (define (wrap indent word* line*)
        (if (null? word*)
            (cons "" line*)
            (let ([line-length (fx- line-length indent)]
                  [indent-string (make-string indent #\space)])
              (let wrap ([word* word*] [n indent] [rword* '()])
                (if (null? word*)
                    (cons (format "~a~{~a~^ ~}" indent-string (reverse rword*)) line*)
                    (let ([word (car word*)])
                      (let ([n^ (fx+ n (string-length word) (if (null? rword*) 0 1))])
                        (if (or (fx<= n^ line-length) (null? rword*))
                            (wrap (cdr word*) n^ (cons word rword*))
                            (cons (format "~a~{~a~^ ~}" indent-string (reverse rword*))
                                  (wrap word* indent '()))))))))))
      (let ([sn (string-length s)])
        (if (fx= sn 0)
            ""
            (format "~{~a~^\n~}"
              (let next-line ([start 0])
                (let next-space ([start start] [indent 0])
                  (if (and (fx< start sn) (eqv? (string-ref s start) #\space))
                      (next-space (fx+ start 1) (fx+ indent 1))
                      (let next-word ([start start] [rword* '()])
                        (let next-char ([end start])
                          (define (end-line end line*)
                            (wrap indent
                                  (reverse
                                    (let ([rword* (if (fx= end start) rword* (cons (substring s start end) rword*))])
                                      (or (and (fx>= (length rword*) 2)
                                               (let ([word (car rword*)])
                                                 (and (fx<= (string-length word) 2)
                                                      ; prevent widow on the last line
                                                      (cons (format "~a ~a" (cadr rword*) word) (cddr rword*)))))
                                          rword*)))
                                  line*))
                          (if (fx= end sn)
                              (end-line end '())
                              (let ([c (string-ref s end)])
                                (case c
                                  [(#\newline) (end-line end (next-line (fx+ end 1)))]
                                  [(#\space)
                                   (if (fx= end start)
                                       (next-word (fx+ start 1) rword*)
                                       (next-word (fx+ end 1) (cons (substring s start end) rword*)))]
                                  [(#\" #\') (let find-matching ([end end])
                                               (let ([end (fx+ end 1)])
                                                 (if (fx= end sn)
                                                     (end-line end '())
                                                     (let ([c^ (string-ref s end)])
                                                       (cond
                                                         [(eqv? c^ c) (next-char (fx+ end 1))]
                                                         [(eqv? c^ #\newline) (end-line end (next-line (fx+ end 1)))]
                                                         [else (find-matching end)])))))]
                                  [else (next-char (fx+ end 1))]))))))))))))
    (define (format-condition c)
      (let ([s (with-output-to-string (lambda () (display-condition c)))])
        (if (source-error-condition? c)
            (fmt s 100)
            s))))

  (define (internal-errorf who fmt . arg*)
    (import (only (chezscheme) errorf))
    (errorf who "~?" fmt arg*))

  ; like map but processes left-to-right
  (define (maplr p ls . ls*)
    (import (rename (only (chezscheme) map) (map pmap)))
    (let map ([p p] [ls ls] [ls* ls*])
      (if (null? ls)
          '()
          (let ([x (apply p (car ls) (pmap car ls*))])
            (cons x (map p (cdr ls) (pmap cdr ls*)))))))

  (define (maplr2 p ls . ls*) ; returns two lists
    (import (rename (only (chezscheme) map) (map pmap)))
    (let map ([p p] [ls ls] [ls* ls*])
      (if (null? ls)
          (values '() '())
          (let*-values ([(x1 x2) (apply p (car ls) (pmap car ls*))]
                        [(x1* x2*) (map p (cdr ls) (pmap cdr ls*))])
            (values (cons x1 x1*) (cons x2 x2*))))))

  ; Mathematical function composition
  (define (compose . f*)
    (lambda (x)
      (fold-right (lambda (f x) (f x)) x f*)))

  (define (shell command)
    (let-values ([(to-stdin from-stdout from-stderr pid)
                  (open-process-ports
                    command
                    (buffer-mode block)
                    (native-transcoder))])
      (close-port to-stdin)
      (let* ([stdout-stuff (get-string-all from-stdout)]
             [stderr-stuff (get-string-all from-stderr)])
        (close-port from-stdout)
        (close-port from-stderr)
        (values
          (if (eof-object? stdout-stuff) "" stdout-stuff)
          (if (eof-object? stderr-stuff) "" stderr-stuff)))))

  (define (string-prefix? prefix str)
    (let ([n (string-length prefix)])
      (and (fx>= (string-length str) n)
           (string=? (substring str 0 n) prefix))))

  ; rm-rf is adapted from Chez Scheme mat.ss
  ; Copyright 1984-2017 Cisco Systems Inc. and licensed under Apache Version 2.0
  (define rm-rf
    (lambda (path)
      (when (file-exists? path)
        (let f ([path path])
          (chmod path #o770)
          (if (file-directory? path)
              (begin
                (for-each (lambda (x) (f (format "~a/~a" path x))) (directory-list path))
                (delete-directory path))
              (delete-file path))))))

  (define mkdir-p
    (lambda (path)
      (unless (or (equal? path "") (file-directory? path))
        (mkdir-p (path-parent path))
        (mkdir path))))

  (define (to-camel-case x initial-capital?)
    (with-output-to-string
      (lambda ()
        (let* ([str (if (symbol? x) (symbol->string x) x)] [n (string-length str)])
          (define (cap i)
            (let ([c (string-ref str i)] [i (fx+ i 1)])
              (case c
                [(#\_) (write-char c) (seen-underscore i)]
                [else (write-char (char-upcase c)) (nocap i)])))
          (define (uncap i)
            (let ([c (string-ref str i)] [i (fx+ i 1)])
              (case c
                [(#\_) (write-char c) (seen-underscore i)]
                [else (write-char (char-downcase c)) (nocap i)])))
          (define (nocap i)
            (unless (fx= i n)
              (let ([c (string-ref str i)] [i (fx+ i 1)])
                (case c
                  [(#\_) (seen-underscore i)]
                  [else (write-char c) (nocap i)]))))
          (define (seen-underscore i)
            (if (fx= i n)
                (write-char #\_)
                (cap i)))
          (unless (fx= n 0) (if initial-capital? (cap 0) (uncap 0)))))))
)
