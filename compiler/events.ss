#!chezscheme

;;; This file is part of Compact.
;;; Copyright (C) 2026 Midnight Foundation
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

(library (events)
  (export event-declarations event-tag-of event-version max-emit-size)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (langs))

  ; Phase 1 wire format version. Bumped when the on-chain VersionedLogItem
  ; layout or per-event payload format changes.
  ; NB: version 0 is reserved for the on-chain decoder's fallback path
  ; (malformed input → wrapped as Misc). deliberate emissions start at 1.
  (define event-version 1)

  ; Maximum serialized event size in bytes. Must match MAX_LOG_SIZE in
  ; midnight-ledger's onchain-vm/src/ops.rs:
  ;     pub const MAX_LOG_SIZE: u64 = 1 << 19;
  (define-syntax max-emit-size
    (identifier-syntax (expt 2 19)))   ; 512 KiB = 524288 bytes

  ; maps event-name symbol -> tag integer.
  ; populated by event-declarations in midnight-events.ss.
  ; readable through event-tag-of.
  (define event-tag-table)

  (define (event-tag-of name)
    (hashtable-ref event-tag-table name #f))

  (define (event-declarations)
    (define edecl* '())
    (define event-src (make-source-object (assert (stdlib-sfd)) 0 0 1 1))

    ; Runtime collision check, called by the macro expansion before each insert.
    ; Ensures a 1-to-1 relationship between event names and tags.
    (define (check-tag-unique! name tag)
      (let-values ([(event-names event-tags) (hashtable-entries event-tag-table)])
        (vector-for-each
          (lambda (existing-name existing-tag)
            (when (eqv? existing-tag tag)
              (internal-errorf 'declare-event-type
                "duplicate event tag ~a for ~a (already used by ~a)"
                tag name existing-name)))
          event-names event-tags)))

    (define-syntax declare-event-type
      (lambda (q)
        (define (f name tag size argument-name* argument-type*)
          (define (convert-event-type type)
            (define (convert-event-targ targ)
              #`(targ-type ,event-src #,(convert-event-type targ)))
            (syntax-case type (TypeRef Bytes Uint)
              [(TypeRef id targ ...) #`(type-ref ,event-src id #,@(map convert-event-targ #'(targ ...)))]
              [(Bytes nat) (field? (datum nat)) #`(tbytes ,event-src (type-size ,event-src ,nat))]
              [(Uint nat) (field? (datum nat)) #`(tunsigned ,event-src (type-size ,event-src ,nat))]
              [other (syntax-error #'other "unrecognized event type")]))
          (define (convert-event-argument name type)
            #`(,event-src #,name #,(convert-event-type type)))
          #`(begin
              (check-tag-unique! '#,name #,tag)
              (hashtable-set! event-tag-table '#,name #,tag)
              (set! edecl*
                (cons
                  (with-output-language (Lpreexpand Structure-Definition)
                    `(struct ,event-src #t #,name ()
                        #,@(map convert-event-argument argument-name* argument-type*)))
                  edecl*))))
        (syntax-case q ()
          [(_ name tag size one-liner ([argument-name argument-type hinting ...] ...))
           (begin
             (unless (identifier? #'name)
               (syntax-error #'name "event name must be an identifier"))
             (let ([t (syntax->datum #'tag)])
               (unless (and (integer? t) (exact? t) (<= 0 t 255))
                 (syntax-error #'tag
                   "event tag must be an exact integer in [0, 255]")))
             (let ([s (syntax->datum #'size)])
               (unless (and (integer? s) (exact? s) (<= 0 s max-emit-size))
                 (syntax-error #'size
                   (format "event size must be an exact non-negative integer not exceeding max-emit-size (~a)"
                           max-emit-size))))
             (f #'name #'tag #'size #'(argument-name ...) #'(argument-type ...)))])))

    (set! event-tag-table (make-eq-hashtable))
    (include "midnight-events.ss")
    (reverse edecl*))

)
