;;; The initial version of this code was extracted from Chez Scheme
;;; s/cmacros.ss, which is covered by the following copyright notice:
;;;
;;; Copyright 1984-2017 Cisco Systems, Inc.
;;; 
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;; 
;;; http://www.apache.org/licenses/LICENSE-2.0
;;; 
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

(library (state-case)
  (export state-case eof)
  (import (chezscheme))

  ;;; A state-case expression must take the following form:
  ;;;   (state-case var eof-clause clause ... else-clause)
  ;;; eof-clause and else-clause must take the form
  ;;;   (eof exp1 exp2 ...)
  ;;;   (else exp1 exp2 ...)
  ;;; and the remaining clauses must take the form
  ;;;   (char-set exp1 exp2 ...)
  ;;; The value of var must be an eof object or a character.
  ;;; state-case selects the first clause matching the value of var and
  ;;; evaluates the expressions exp1 exp2 ... of that clause.  If the
  ;;; value of var is an eof-object, eof-clause is selected.  Otherwise,
  ;;; the clauses clause ... are considered from left to right.  If the
  ;;; value of var is in the set of characters defined by the char-set of
  ;;; a given clause, the clause is selected.  If no other clause is
  ;;; selected, else-clause is selected.

  ;;; char-set may be
  ;;;   * a single character, e.g., #\a, or
  ;;;   * a list of subkeys, each of which is
  ;;;     - a single character, or
  ;;;     - a character range, e.g., (#\a - #\z)
  ;;; For example, (#\$ (#\a - #\z) (#\A - #\Z)) specifies the set
  ;;; containing $ and the uppercase and lowercase letters.

  (define-syntax state-case
    (lambda (x)
      (define state-case-test
        (lambda (cvar k)
          (with-syntax ((cvar cvar))
            (syntax-case k (-)
              (char
                (char? (datum char))
                #'(char=? cvar char))
              ((char1 - char2)
               (and (char? (datum char1)) (char? (datum char2)))
               #'(char<=? char1 cvar char2))
              (predicate
                (identifier? #'predicate)
                #'(predicate cvar))))))
      (define state-case-help
        (lambda (cvar clauses)
          (syntax-case clauses (else)
            (((else exp1 exp2 ...))
             #'(begin exp1 exp2 ...))
            ((((k ...) exp1 exp2 ...) . more)
             (with-syntax (((test ...)
                            (map (lambda (k) (state-case-test cvar k))
                              #'(k ...)))
                           (rest (state-case-help cvar #'more)))
               #'(if (or test ...) (begin exp1 exp2 ...) rest)))
            (((k exp1 exp2 ...) . more)
             (with-syntax ((test (state-case-test cvar #'k))
                           (rest (state-case-help cvar #'more)))
               #'(if test (begin exp1 exp2 ...) rest))))))
      (syntax-case x (eof)
        ((_ cvar (eof exp1 exp2 ...) more ...)
         (identifier? #'cvar)
         (with-syntax ((rest (state-case-help #'cvar #'(more ...))))
           #'(if (eof-object? cvar)
                 (begin exp1 exp2 ...)
                 rest))))))

  (define-syntax eof
    (lambda (x)
      (syntax-error x "misplaced aux keyword")))
)
