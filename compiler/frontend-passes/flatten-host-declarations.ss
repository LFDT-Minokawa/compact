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

;; a host block names an interface and declares the functions the contract requires of it;
;; expansion binds functions one declaration at a time, therefore each signature becomes a
;; declaration of its own, carrying the interface id.  The interface and its functions must
;; be ones the runtime provides, so an unknown id or function is rejected here, before any
;; name is bound.
(define-pass flatten-host-declarations : Lnoinclude (ir) -> Lflathost ()
  (definitions
    (define (format-names name*)
      (format "~{~a~^, ~}" name*))
    (define (check-interface! src interface-id)
      (or (host-interface-functions interface-id)
          (source-errorf src "unknown host interface ~a: this compiler provides ~a"
            interface-id (format-names (host-interface-ids)))))
    (define (check-function! src interface-id function-name provided*)
      (unless (memq function-name provided*)
        (source-errorf src "host interface ~a has no function ~a: it provides ~a"
          interface-id function-name (format-names provided*))))
    (define (flatten-pelts pelt*)
      (fold-right
        (lambda (pelt pelt*)
          (nanopass-case (Lnoinclude Program-Element) pelt
            [(host ,src ,exported? ,interface-id ,hsig* ...)
             (let ([provided* (check-interface! src interface-id)])
               (fold-right
                 (lambda (hsig pelt*)
                   (cons (Host-Signature hsig exported? interface-id provided*) pelt*))
                 pelt*
                 hsig*))]
            [else (cons (Program-Element pelt) pelt*)]))
        '()
        pelt*)))
  (Program : Program (ir) -> Program ()
    [(program ,src ,pelt* ...)
     `(program ,src ,(flatten-pelts pelt*) ...)])
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [(module ,src ,exported? ,module-name (,[type-param*] ...) ,pelt* ...)
     `(module ,src ,exported? ,module-name (,type-param* ...) ,(flatten-pelts pelt*) ...)]
    ;; flatten-pelts takes every host block out of a program or module body
    [(host ,src ,exported? ,interface-id ,hsig* ...) (assert cannot-happen)])
  (Host-Signature : Host-Signature (ir exported? interface-id provided*) -> Program-Element ()
    [(,src ,function-name (,[arg*] ...) ,[type])
     (check-function! src interface-id function-name provided*)
     `(host ,src ,exported? ,interface-id ,function-name (,arg* ...) ,type)]))
