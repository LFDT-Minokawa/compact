;;; This file is part of Compact.
;;; Copyright (C) 2025 Midnight Foundation
;;; SPDX-License-Identifier: Apache-2.0
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;  	http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

#!chezscheme

(define-pass print-zkir-v3 : Lzkir (ir) -> Lzkir ()
  (definitions
    (define (alignment-atom->alist atom)
      (nanopass-case (Lflattened Alignment) atom
        [(acompress) `((tag . "atom") (value . ((tag . "compress"))))]
        [(abytes ,nat) `((tag . "atom") (value . ((length . ,nat) (tag . "bytes"))))]
        [(afield) `((tag . "atom") (value . ((tag . "field"))))]
        ;; Alignment for ADT and contract types can't appear?
        [else (assert cannot-happen)]))
    (define (alignment->vector alignment*)
      (list->vector (map alignment-atom->alist alignment*)))
    (module (with-var-table var->string)
      (define ht)
      (define counter)
      (define-syntax with-var-table
        (syntax-rules ()
          [(_ b1 b2 ...)
           (fluid-let ([ht (make-eq-hashtable)] [counter 0])
             b1 b2 ...)]))
      (define (var->string var)
        (let ([a (eq-hashtable-cell ht var #f)])
          (or (cdr a)
              (let ([str (format "%~s.~d" (id-sym var) counter)])
                (set! counter (fx+ counter 1))
                (set-cdr! a str)
                str)))))
    ;; Field representations (which *can* be negative) are represented with an optional leading minus
    ;; sign and then hexadecimal byte values in little endian order.
    (define (zkir-field-rep->string fr)
      (call-with-string-output-port
        (lambda (sp)
          (let ([fr (if (< fr 0)
                        (begin (put-string sp "-0x") (- fr))
                        (begin (put-string sp "0x") fr))])
            (let loop ([fr fr])
              (if (< fr 256)
                  (fprintf sp "~(~2,'0x~)" fr)
                  (let-values ([(q r) (div-and-mod fr 256)])
                    (fprintf sp "~(~2,'0x~)" r)
                    (loop q))))))))
    )
  (Program : Program (ir) -> Program ()
    [(program ,src ,cdefn* ...)
     (for-each Circuit-Definition cdefn*)
     ir])
  (Circuit-Definition : Circuit-Definition (ir) -> * ()
    [(circuit ,src (,name* ...) ((,var-name* ,zkir-type*) ...) (,zkir-type0* ...) ,instr* ...)
     (define (print-circuit op)
       (print-json-compact op
         (with-var-table
           (let* ([inputs (list->vector (maplr (lambda (var-name zkir-type)
                                                 `((name . ,(var->string var-name))
                                                   (type . ,zkir-type)))
                                          var-name* zkir-type*))]
                  [instructions (list->vector (maplr Instruction instr*))]
                  [outputs (list->vector zkir-type0*)])
             `((version . ((major . 3) (minor . 0)))
               (do_communications_commitment . #t)
               (inputs . ,inputs)
               (outputs . ,outputs)
               (instructions . ,instructions))))))
     (let ([output-port*
             (fold-left (lambda (output-port* name)
                          (let ([target (assq name (target-ports))])
                            (if target
                                (cons (cdr target) output-port*)
                                output-port*)))
               '() name*)])
       ;; Exported pure circuits are in the IR but don't have any corresponding target ports.
       (unless (null? output-port*)
         (if (null? (cdr output-port*))
             ;; Directly print it to the port.
             (print-circuit (car output-port*))

             ;; Stringify it first.
             (let ([str (call-with-string-output-port print-circuit)])
               (for-each (lambda (op) (put-string op str)) output-port*)))))])
  (Instruction : Instruction (ir) -> * (json)
    [(add ,[* outp] ,[* inp0] ,[* inp1])
     `((op . "add") (output . ,outp) (a . ,inp0) (b . ,inp1))]
    [(assert ,[* inp])
     `((op . "assert") (cond . ,inp))]
    [(bytes32_from_low_high ,[* outp] ,[* inp0] ,[* inp1])
     `((op . "bytes32_from_low_high") (output . ,outp) (inputs . ,(vector inp0 inp1)))]
    [(bytes32_into_low_high ,outp0 ,outp1 ,[* inp])
     (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
       `((op . "bytes32_into_low_high") (outputs . ,(vector outp0 outp1)) (bytes . ,inp)))]
    [(cond_select ,[* outp] ,[* inp0] ,[* inp1] ,[* inp2])
     `((op . "cond_select") (output . ,outp) (bit . ,inp0) (a . ,inp1) (b . ,inp2))]
    [(constrain_bits ,[* inp] ,imm)
     `((op . "constrain_bits") (val . ,inp) (bits . ,imm))]
    [(constrain_eq ,[* inp0] ,[* inp1])
     `((op . "constrain_eq") (a . ,inp0) (b . ,inp1))]
    [(constrain_to_boolean ,[* inp])
     `((op . "constrain_to_boolean") (val . ,inp))]
    [(copy ,[* outp] ,[* inp])
     `((op . "copy") (output . ,outp) (val . ,inp))]
    [(div_mod_power_of_two ,[* outp0] ,[* outp1] ,[* inp] ,imm)
     `((op . "div_mod_power_of_two") (outputs . ,(vector outp0 outp1)) (val . ,inp)
       (bits . ,imm))]
    [(ec_mul ,[* outp] ,[* inp0] ,[* inp1])
     `((op . "ec_mul") (output . ,outp) (a . ,inp0) (scalar . ,inp1))]
    [(ec_mul_generator ,[* outp] ,[* inp])
     `((op . "ec_mul_generator") (output . ,outp) (scalar . ,inp))]
    [(encode (,outp* ...) ,[* inp])
     (let ([outp* (maplr Output outp*)])
       `((op . "encode") (outputs . ,(list->vector outp*)) (input . ,inp)))]
    [(from_bytes32 ,zkir-type ,[* outp] ,[* inp])
     `((op . "from_bytes32") (type . ,zkir-type) (output . ,outp) (bytes . ,inp))]
    [(from_coordinates ,[* outp] ,[* inp0] ,[* inp1])
     `((op . "from_coordinates") (output . ,outp) (inputs . ,(vector inp0 inp1)))]
    [(hash_to_curve ,[* outp] ,[* inp*] ...)
     `((op . "hash_to_curve") (output . ,outp) (inputs . ,(list->vector inp*)))]
    [(impact ,[* inp] ,[* inp*] ...)
     `((op . "impact") (guard . ,inp) (inputs . ,(list->vector inp*)))]
    [(into_bytes32 ,[* outp] ,[* inp])
     `((op . "into_bytes32") (output . ,outp) (input . ,inp))]
    [(into_coordinates ,outp0 ,outp1 ,[* inp])
     (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
       `((op . "into_coordinates") (outputs . ,(vector outp0 outp1)) (point . ,inp)))]
    [(inv ,[* outp] ,[* inp])
     `((op . "inv") (output . ,outp) (a . ,inp))]
    [(jubjub_scalar_from_native ,[* outp] ,[* inp])
     `((op . "jubjub_scalar_from_native") (output . ,outp) (native . ,inp))]
    [(keccak256 ,[* outp] (,alignment* ...) ,[* inp*] ...)
     `((op . "keccak256") (output . ,outp)
       (alignment . ,(alignment->vector alignment*)) (inputs . ,(list->vector inp*)))]
    [(less_than ,[* outp] ,[* inp0] ,[* inp1] ,imm)
     `((op . "less_than") (output . ,outp) (a . ,inp0) (b . ,inp1) (bits . ,imm))]
    [(mul ,[* outp] ,[* inp0] ,[* inp1])
     `((op . "mul") (output . ,outp) (a . ,inp0) (b . ,inp1))]
    [(neg ,[* outp] ,[* inp])
     `((op . "neg") (output . ,outp) (a . ,inp))]
    ;; TODO(kmillikin): we don't actually use this instruction, we use (cond_select t 0 1).  But
    ;; we should use this one instead.
    [(not ,[* outp] ,[* inp])
     `((op . "not") (output . ,outp) (a . ,inp))]
    [(output ,[* inp*] ...)
     `((op . "output") (vals . ,(list->vector inp*)))]
    [(persistent_hash ,[* outp] (,alignment* ...) ,[* inp*] ...)
     `((op . "persistent_hash") (output . ,outp)
       (alignment . ,(alignment->vector alignment*)) (inputs . ,(list->vector inp*)))]
    [(private_input ,zkir-type ,[* outp])
     ;; Kind of warty: rather than a literal true guard or making it truly optional by leaving it
     ;; out of the JSON representation, ZKIR wants to put a JSON null value there.
     `((op . "private_input") (type . ,zkir-type) (output . ,outp) (guard . ,(void)))]
    [(private_input ,zkir-type ,[* outp] ,[* inp])
     `((op . "private_input") (type . ,zkir-type) (output . ,outp) (guard . ,inp))]
    [(public_input ,zkir-type ,[* outp])
     ;; Kind of warty: rather than a literal true guard or making it truly optional by leaving it
     ;; out of the JSON representation, ZKIR wants to put a JSON null value there.
     `((op . "public_input") (type . ,zkir-type) (output . ,outp) (guard . ,(void)))]
    [(public_input ,zkir-type ,[* outp] ,[* inp])
     `((op . "public_input") (type . ,zkir-type) (output . ,outp) (guard . ,inp))]
    [(reconstitute_field ,[* outp] ,[* inp0] ,[* inp1] ,imm)
     `((op . "reconstitute_field") (output . ,outp) (divisor . ,inp0) (modulus . ,inp1)
       (bits . ,imm))]
    [(reverse_bytes ,[* outp] ,[* inp])
     `((op . "reverse_bytes") (output . ,outp) (bytes . ,inp))]
    [(test_eq ,[* outp] ,[* inp0] ,[* inp1])
     `((op . "test_eq") (output . ,outp) (a . ,inp0) (b . ,inp1))]
    [(transient_hash ,[* outp] ,[* inp*] ...)
     `((op . "transient_hash") (output . ,outp) (inputs . ,(list->vector inp*)))])
  (Input : Input (ir) -> * (json)
    (,fr (zkir-field-rep->string fr))
    (,var-name (var->string var-name)))
  (Output : Output (ir) -> * (json)
    (,var-name (var->string var-name))))
