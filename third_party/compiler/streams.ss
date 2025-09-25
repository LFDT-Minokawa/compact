;;; The initial version of this code was extracted from Chez Scheme
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

(library (streams)
  (export stream-cons stream-car stream-cdr stream-nil stream-null?
    stream-map stream stream-append2 stream-append-all stream-filter)
  (import (chezscheme))

  (define stream-cons
    (lambda (x thunk)
      (cons x thunk)))

  (define stream-car
    (lambda (x)
      (car x)))

  (define stream-cdr
    (lambda (x)
      (when (procedure? (cdr x)) (set-cdr! x ((cdr x))))
      (cdr x)))

  (define stream-nil '())

  (define stream-null?
    (lambda (x)
      (null? x)))

  (define stream-map
    (lambda (f x)
      (if (stream-null? x)
          '()
          (stream-cons (f (stream-car x))
            (lambda ()
              (stream-map f (stream-cdr x)))))))

  (define stream
    (lambda xs
      xs))

  (define stream-append2
    (lambda (xs thunk)
      (if (null? xs)
          (thunk)
          (stream-cons (stream-car xs)
            (lambda ()
              (stream-append2 (stream-cdr xs) thunk))))))

  (define stream-append-all
    (lambda (stream$) ;; stream of streams
      (if (stream-null? stream$)
          stream$
          (stream-append2 (stream-car stream$)
            (lambda () (stream-append-all (stream-cdr stream$)))))))

  (define stream-filter
    (lambda (stream in?)
      (let stream-filter ([stream stream])
        (if (stream-null? stream)
            stream
            (let ([x (stream-car stream)])
              (if (in? x)
                  (stream-cons x (lambda () (stream-filter (stream-cdr stream))))
                  (stream-filter (stream-cdr stream))))))))
)
