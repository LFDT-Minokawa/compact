#! /usr/bin/env -S scheme --compile-imported-libraries --program
#!chezscheme

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

(import (chezscheme) (command-line-parsing))

(parameterize ([reset-handler abort])
  (command-line-case (command-line)
    [((string input-pathname)
      (string replacements-pathname)
      (string output-pathname))
     (call-with-port
       (open-input-file input-pathname)
       (lambda (ip)
         (call-with-port
           (open-input-file replacements-pathname)
           (lambda (rp)
             (call-with-port
               (open-output-file output-pathname 'replace)
               (lambda (op)
                 (let loop ([fp 0])
                   (let ([x (get-datum rp)])
                     (if (eof-object? x)
                         (put-string op (get-string-all ip))
                         (let-values ([(bfp efp str) (apply values x)])
                           (put-string op (get-string-n ip (- bfp fp)))
                           (put-string op str)
                           (get-string-n ip (- efp bfp))
                           (loop efp)))))))))))]))
