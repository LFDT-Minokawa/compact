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

;;; The host interfaces a contract may declare in this iteration.  Host functions are
;;; resolved by the runtime rather than supplied by the DApp, and no capsule runtime exists
;;; yet to publish interfaces, therefore the compiler accepts exactly the interfaces
;;; compact-runtime knows (`runtime/src/host.ts` carries the matching implementations), by
;;; id and function name; a block may declare any subset of an interface's functions.  The
;;; declared signatures are the contract's requirement and are checked against the
;;; implementation's results at run time.
(library (host-interfaces)
  (export host-interface-ids host-interface-functions)
  (import (chezscheme))

  (define interfaces
    '(("midnight:capsule/keys@1.0.0" secretKey)
      ("midnight:capsule/zswap@1.0.0" ownPublicKey createZswapInput createZswapOutput)))

  (define (host-interface-ids) (map car interfaces))

  ;; the function names of a known interface, or #f for an unknown one
  (define (host-interface-functions interface-id)
    (cond
      [(assoc interface-id interfaces) => cdr]
      [else #f])))
