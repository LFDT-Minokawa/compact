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

(define-pass lower-emit : Lnoserialize (ir) -> Lloweredemit ()
  (definitions
    ; generates the vm-code instruction for `emit` which is `log' in vm.
    (define emit-vm-code-source
      #'((push [storage #f]
               [value (state-value 'array
                        ((state-value 'cell (align emit-version 4))
                         (state-value 'cell (align emit-tag 1))
                         (state-value 'cell emit-payload)))])
         ; this is the op code from the vm and has to stay log
         (log))))
  (Program : Program (ir) -> Program ()
    [(program ,src (,[contract-type*] ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,[pelt*] ...)
     `(program ,src (,contract-type* ...) ((,export-name* ,name*) ...) ,pelt* ...)])
  (Expression : Expression (ir) -> Expression ()
    [(emit ,src ,[type] ,len ,[expr])
     (nanopass-case (Lloweredemit Type) type
       [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
        (let ([event-tag (or (event-tag-of struct-name)
                             (source-errorf src "~a is not a declared event type" struct-name))])
          `(emit ,src ,event-version ,event-tag ,len ,expr
                ,(make-vm-code emit-vm-code-source)))]
       [else (assert cannot-happen)])]))
