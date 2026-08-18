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

(define-pass reject-for-return : Lnopattern (ir) -> Lnopattern ()
  (Block : Block (ir [in-for? #f]) -> Block ()
    [(block ,src ,[stmt*] ...) ir])
  (Statement : Statement (ir [in-for? #f]) -> Statement ()
    [(for ,src ,var-name ,tsize0 ,tsize1 ,[stmt #t -> stmt]) ir]
    [(for ,src ,var-name ,[expr] ,[stmt #t -> stmt]) ir]
    [(return ,src)
     (when in-for? (source-errorf src "return is not supported within for loops"))
     ir]
    [(return ,src ,[expr])
     (when in-for? (source-errorf src "return is not supported within for loops"))
     ir]))
