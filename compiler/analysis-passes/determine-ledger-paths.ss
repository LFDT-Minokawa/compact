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

(define-pass determine-ledger-paths : Lnodca (ir) -> Lwithpaths0 ()
  (Kernel-Declaration : Kernel-Declaration (ir) -> Kernel-Declaration ()
    [(kernel-declaration ,public-binding)
     `(kernel-declaration ,(Public-Ledger-Binding public-binding '()))])
  (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ()
    (definitions
      (define (batch k x*)
        (let f ([x* x*] [n (length x*)])
          (if (fx<= n k)
            x*
            (let-values ([(q r) (div-and-mod n k)])
              (let ([x** (let g ([x* (list-tail x* r)] [n (fx- n r)])
                           (if (fx= n k)
                               (list x*)
                               (cons (list-head x* k)
                                     (g (list-tail x* k) (fx- n k)))))])
                (if (fx= r 0)
                    (f x** q)
                    (f (cons (list-head x* r) x**) (fx+ q 1)))))))))
    [(public-ledger-declaration ,public-binding* ... ,[lconstructor])
     `(public-ledger-declaration
        ,(let f ([pbtree (batch maximum-ledger-segment-length public-binding*)]
                 [ridx* '()])
           (if (list? pbtree)
               `(public-ledger-array
                  ,(map (lambda (pbtree i) (f pbtree (cons i ridx*)))
                      pbtree
                      (enumerate pbtree))
                  ...)
               (Public-Ledger-Binding pbtree (reverse ridx*))))
        ,lconstructor)])
  (Public-Ledger-Binding : Public-Ledger-Binding (ir idx*) -> Public-Ledger-Binding ()
    [(,src ,ledger-field-name ,[type])
     `(,src ,ledger-field-name (,idx* ...) ,type)]))
