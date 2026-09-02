;;; This file is part of Compact.
;;; Copyright (C) 2026 Midnight Foundation
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

;; Record how often each SSA variable is consumed. The cancellation pass uses
;; this information to retain a bytes32_into_low_high whose limbs are shared.
(define-pass record-zkir-input-uses : Lzkir (ir use-count-ht) -> Lzkir ()
  (Input : Input (ir) -> Input ()
    [,var-name
     (let ([cell (eq-hashtable-cell use-count-ht var-name 0)])
       (set-cdr! cell (fx1+ (cdr cell))))
     ir]))

(define-pass cancel-bytes32-conversions$ : Lzkir (ir use-count-ht) -> Lzkir ()
  (definitions
    (define replacement-ht)

    (define (input-is-variable? inp var-name)
      (nanopass-case (Lzkir Input) inp
        [,var-name^ (eq? var-name^ var-name)]
        [else #f]))

    (define (resolve-input inp)
      (nanopass-case (Lzkir Input) inp
        [,var-name
         (if (hashtable-contains? replacement-ht var-name)
             (resolve-input (hashtable-ref replacement-ht var-name #f))
             inp)]
        [else inp]))

    ;; Only cancel immediately adjacent inverse conversions. This deliberately
    ;; avoids reasoning about intervening instructions or their effects.
    (define (cancel-adjacent instr*)
      (if (or (null? instr*) (null? (cdr instr*)))
          instr*
          (let ([instr0 (car instr*)] [instr1 (cadr instr*)])
            (nanopass-case (Lzkir Instruction) instr0
              [(bytes32_into_low_high ,outp0 ,outp1 ,inp)
               (nanopass-case (Lzkir Instruction) instr1
                 [(bytes32_from_low_high ,outp2 ,inp0 ,inp1)
                  (if (and (input-is-variable? inp0 outp0)
                           (input-is-variable? inp1 outp1))
                      (begin
                        (hashtable-set! replacement-ht outp2 inp)
                        (if (and (fx= (hashtable-ref use-count-ht outp0 0) 1)
                                 (fx= (hashtable-ref use-count-ht outp1 0) 1))
                            (cancel-adjacent (cddr instr*))
                            (cons instr0 (cancel-adjacent (cddr instr*)))))
                      (cons instr0 (cancel-adjacent (cdr instr*))))]
                 [else (cons instr0 (cancel-adjacent (cdr instr*)))])]
              [else (cons instr0 (cancel-adjacent (cdr instr*)))]))))
    )

  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src (,name* ...) ((,var-name* ,zkir-type*) ...)
       (,zkir-type0* ...) ,instr* ...)
     (fluid-let ([replacement-ht (make-eq-hashtable)])
       (let* ([instr* (cancel-adjacent instr*)]
              [instr* (maplr Instruction instr*)])
         `(circuit ,src (,name* ...) ((,var-name* ,zkir-type*) ...)
            (,zkir-type0* ...) ,instr* ...)))])

  (Instruction : Instruction (ir) -> Instruction ())

  (Input : Input (ir) -> Input ()
    [,var-name (resolve-input ir)]))

(define (cancel-bytes32-conversions ir)
  (let ([use-count-ht (make-eq-hashtable)])
    (cancel-bytes32-conversions$
      (record-zkir-input-uses ir use-count-ht)
      use-count-ht)))
