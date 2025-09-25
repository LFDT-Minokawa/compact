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

(library (formatter-test)
  (export formatter-testing-passes)
  (import (except (chezscheme) errorf)
          (pass-helpers)
          (streams)
          (only (lparser) make-token token-type token-src)
          (langs)
          (lparser-to-lsrc)
          (formatter)
          (parser)
          (pass-helpers))

  (define (parse-file/format/reparse pathname)
    (let* ([op (get-target-port 'formatter-output.compact)]
           [formatter-pathname (port-name op)])
      (let-values ([(token-stream ir) (parse-file/token-stream pathname)])
        (let* ([ir2 (let ([token-stream (let f ([token-stream token-stream])
                                          (let ([token (stream-car token-stream)])
                                            (case (token-type token)
                                              [(eof) token-stream]
                                              [(whitespace line-comment block-comment) (cons token (f (stream-cdr token-stream)))]
                                              ; add a comment before every non-whitespace, non-comment token.
                                              ; if any comments are dropped, print-compact should complain.
                                              [else (cons* (make-token
                                                             (token-src token)
                                                             'block-comment
                                                             "$"
                                                             "/*$*/")
                                                           token
                                                           (f (stream-cdr token-stream)))])))])
                      ; produce output with the modified token stream ...
                      (print-Lparser ir token-stream 80 op)
                      (flush-output-port op)
                      ; ... and see if it will parse
                      (parse-file formatter-pathname))]
               [ir3 (begin
                      (set-port-position! op 0)
                      (set-port-length! op 0)
                      ; produce output with the original token stream ...
                      (print-Lparser ir token-stream 80 op)
                      (flush-output-port op)
                      ; ... and see if it will parse
                      (parse-file formatter-pathname))])
          ; now verify that both parses are equivalent to the original
          (assert (equal? (unparse-Lsrc ir2) (unparse-Lsrc (Lparser->Lsrc ir))))
          (assert (equal? (unparse-Lsrc ir3) (unparse-Lsrc (Lparser->Lsrc ir))))
          ir3))))

  (define-passes formatter-testing-passes
    (parse-file/format/reparse Lsrc))
)
