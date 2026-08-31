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

(define-pass check-ledger-budgets : Lwithpaths (ir) -> Lwithpaths ()
  ; this pass complains if the opcode sequence emitted for a ledger operation would
  ; exceed one of the Impact VM's nibble-encoded operand budgets.
  ;
  ; dup, swap, and ins encode their operand in the low nibble of a single opcode byte,
  ; and idx encodes its path length there.  An out-of-range operand therefore does not
  ; fail: it silently aliases to a different, valid instruction.  dup 16 has the same
  ; field representation as dup 0.  Nothing downstream range-checks it -- not the VM,
  ; not the Op serializer, and not the ledger's transcript validation -- so an
  ; over-long access path produces a well-formed transaction that reads the wrong
  ; stack slot.  The check has to happen here.
  ;
  ; Access-path depth has two sources, and only one of them is visible in a type: the
  ; nesting depth of the ledger field's ADTs, and the depth of the B-tree that
  ; determine-ledger-paths builds over the contract's top-level ledger fields.  Adding
  ; a sixteenth ledger field deepens every path in the contract by one.
  ;
  ; The operand values are computed by arbitrary Scheme in the ledger ADT table (see
  ; the (length f) expressions throughout midnight-ledger.ss) and they differ per
  ; operation: there are several distinct dup formulas alone.  Rather than re-deriving
  ; a maximum path depth per operation, which would duplicate those formulas and drift
  ; from them, we expand each operation's VM code against its concrete access path and
  ; inspect the operands that are actually emitted.  That way an operation added later
  ; with a formula nobody anticipated is still checked.
  (definitions
    ; Impact VM operand limits.  From the opcode encoding in onchain-vm/src/ops.rs:
    ;   dup n  -> 0x30 | n              swap n -> 0x40 | n
    ;   ins n  -> 0x90 | n, 0xa0 | n    idx    -> 0x50..0x80 | (path length - 1)
    (define maximum-stack-reach 15)
    (define minimum-ins-levels 1)
    (define maximum-ins-levels 15)
    (define maximum-idx-path-length 16)

    ; The budget arithmetic in the ADT table depends only on the access path f.  It
    ; never does arithmetic on an operation's arguments: those reach only state-value
    ; and rt-... forms, which wrap their operands without examining them.  So we can
    ; bind the operation's arguments to a placeholder and supply an access path of the
    ; right length.  The ADT's own type arguments are bound to their actual values,
    ; because a Nat argument (a Merkle tree's depth, say) can legitimately take part in
    ; arithmetic.
    (define placeholder '|<ledger-budget-check>|)

    (define (whole-number? x)
      (and (integer? x) (exact? x) (>= x 0)))

    (define (operand v name)
      (let ([a (assoc name (vminstr-arg* v))])
        (and a (cdr a))))

    ; Counts the static path elements (the ledger field's position in the field layout)
    ; and the dynamic ones (one per traversed Map lookup).
    (define (path-element-counts path-elt*)
      (let loop ([path-elt* path-elt*] [static 0] [dynamic 0])
        (if (null? path-elt*)
            (values static dynamic)
            (nanopass-case (Lwithpaths Path-Element) (car path-elt*)
              [,path-index (loop (cdr path-elt*) (fx+ static 1) dynamic)]
              [else (loop (cdr path-elt*) static (fx+ dynamic 1))]))))

    (define (budget-error! src ledger-field-name adt-name ledger-op path-elt* what
                           op-name value limit)
      (let-values ([(static dynamic) (path-element-counts path-elt*)])
        (source-errorf src
          "~s ~s exceeds the Impact VM's ~a limit of ~d: at this access path it emits ~a ~d. \
           The path to ledger field ~s has depth ~d (~d from the ledger field layout, \
           ~d from ADT nesting).  Reduce the nesting depth, or reduce the number of \
           top-level ledger fields, which deepens every access path in the contract."
          adt-name ledger-op what limit op-name value
          (id-sym ledger-field-name) (length path-elt*) static dynamic)))

    (define (check-instruction! src ledger-field-name adt-name ledger-op path-elt* v)
      (let ([op-name (vminstr-op v)])
        (cond
          [(or (string=? op-name "dup") (string=? op-name "swap"))
           (let ([n (operand v "n")])
             (when (and (whole-number? n) (> n maximum-stack-reach))
               (budget-error! src ledger-field-name adt-name ledger-op path-elt*
                 "stack reach" op-name n maximum-stack-reach)))]
          [(string=? op-name "ins")
           (let ([n (operand v "n")])
             ; a suppressed operand is not a number: the instruction is omitted
             (when (and (whole-number? n)
                        (or (< n minimum-ins-levels) (> n maximum-ins-levels)))
               (budget-error! src ledger-field-name adt-name ledger-op path-elt*
                 "insert level" op-name n maximum-ins-levels)))]
          [(string=? op-name "idx")
           (let ([path (operand v "path")])
             ; an empty path is emitted as nothing at all, so only the upper bound matters
             (when (and (list? path) (> (length path) maximum-idx-path-length))
               (budget-error! src ledger-field-name adt-name ledger-op path-elt*
                 "index path length" op-name (length path) maximum-idx-path-length)))]
          [else (void)])))

    (define (check-ledger-operation! src ledger-field-name path-elt* adt-op)
      (nanopass-case (Lwithpaths ADT-Op) adt-op
        [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...)
                     ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
         (let ([f (map (lambda (path-elt) placeholder) path-elt*)]
               [arg-alist (append
                            (map cons adt-formal* adt-arg*)
                            (map (lambda (var-name) (cons (id-sym var-name) placeholder))
                                 var-name*))])
           (for-each
             (lambda (v)
               (check-instruction! src ledger-field-name adt-name ledger-op path-elt* v))
             (expand-vm-code src f #f arg-alist (vm-code-code vm-code))))])))
  (Expression : Expression (ir) -> Expression ()
    [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[expr*] ...)
     (check-ledger-operation! src^ ledger-field-name path-elt* adt-op)
     ir]))
