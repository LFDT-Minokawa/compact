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

(define-pass expand-place-params : Lnoandornot (ir) -> Lnoplace ()
  ; This pass eliminates place references: &T in a type position and &e in an
  ; expression position.  The surface syntax, the parser, and the language plumbing are
  ; in place; the desugaring itself is not yet implemented, so for the moment the pass
  ; rejects every use of & with a diagnostic.
  ;
  ; When the desugaring lands it belongs here, and it belongs *before*
  ; expand-modules-and-types specifically because it changes a circuit's signature.
  ; The intended shape:
  ;
  ;   circuit credit(acct: &Cell<Uint<64>>, amount: Uint<64>) { ... }
  ;   credit(&accounts.lookup(to), amount);
  ;
  ; becomes a store type-parameter plus an ordinary value parameter carrying the access
  ; path's dynamic keys, and, at the call site, the matching pair of arguments:
  ;
  ;   circuit credit<%S>(acct__keys: keys(%S), amount: Uint<64>) { ... }
  ;   credit<accounts.lookup(.)>([to], amount);
  ;
  ; Monomorphization then does what it already does.  It cannot do the rewrite itself:
  ; expand-modules-and-types builds each specialized program element by running its
  ; transformer over the *raw* program element (process-frob), whose parameter list is
  ; fixed, so a pass that adds a parameter has to run earlier.  expand-patterns is the
  ; precedent -- it likewise rewrites parameter lists, turning a destructuring pattern
  ; in argument position into a plain parameter plus bindings.
  ;
  ; This pass is purely syntactic and cannot be otherwise: at this stage the compiler
  ; does not yet know whether the root of a place expression names a ledger field.
  ; ledger-ref does not exist until expand-modules-and-types resolves an identifier
  ; bound to Info-ledger, and public-ledger not until propagate-ledger-paths.  That is
  ; fine, because & is syntactically marked: the pass rewrites whatever appears under
  ; it and leaves every validity question to the later passes that can answer it.
  ;
  ; Note also that every diagnostic about & has to be produced here, in the user's own
  ; terms.  After this pass the form no longer exists, so anything reported downstream
  ; would be phrased in terms of a desugared shape the user never wrote.
  (Type : Type (ir) -> Type ()
    [(tplace ,src ,type)
     (source-errorf src "place reference types (&T) are not yet implemented")])
  (Expression : Expression (ir) -> Expression ()
    [(place-ref ,src ,expr)
     (source-errorf src "place references (&e) are not yet implemented")]))
