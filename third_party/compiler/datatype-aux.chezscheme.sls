;;; Copyright 2009 R. Kent Dybvig
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;     http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

(library (datatype-aux)
  (export datatype-reader/writer when-safe)
  (import (chezscheme))

  (define-syntax datatype-reader/writer
    (syntax-rules ()
      [(_ record-name constructor-number constructor accessor ...)
       (module ()
         (record-reader 'constructor (record-type-descriptor record-name))
         (record-writer (record-type-descriptor record-name)
           (lambda (x p wr)
             (wr `(constructor ,@(map (lambda (a) (a x)) (list accessor ...))) p))
           #;(lambda (x p wr)
             (display "#[" p)
             (wr 'constructor p)
             (display " " p)
             (wr constructor-number p)
             (begin
               (display " " p)
               (wr (accessor x) p))
             ...
             (display "]" p))))]))

  (define-syntax when-safe
    (lambda (x)
      (syntax-case x ()
        [(_ e ...)
         (if (fx= (optimize-level) 3)
             #'(void)
             #'(begin e ...))])))
)
