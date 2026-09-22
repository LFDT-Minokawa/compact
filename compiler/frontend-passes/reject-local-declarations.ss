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

;; The `local` forms flow through the frontend but do not yet compile past it,
;; therefore this pass rejects them with a clear error rather than letting a
;; later pass choke.
(define-pass reject-local-declarations : Lnoandornot (ir) -> Lnolocal ()
  (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ()
    [(local-ledger-declaration ,src ,exported? ,ledger-field-name ,type)
     (source-errorf src "local declarations are not yet implemented")])
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(local-constructor ,src ,expr)
     (source-errorf src "the local constructor is not yet implemented")])
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(local-circuit ,src ,exported? ,function-name (,type-param* ...) (,arg* ...) ,type ,expr)
     (source-errorf src "local functions are not yet implemented")]))
