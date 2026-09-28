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

(library (compiler-version)
  (export compiler-version-string compiler-version-triple-string
          compiler-version-commit compiler-version-commit-date
          check-compiler-version)
  (import (chezscheme) (version) (version-config))

  ; NB: also update compactc version in ../flake.nix
  (define compiler-version
    (version-with-tag (make-version 'compiler 0 34 111) compiler-version-tag))

  (define compiler-version-string (make-version-string compiler-version))

  ;; The bare triple, for generated documents: a document is source, not a
  ;; build, so it cannot truthfully carry a build's tag.
  (define compiler-version-triple-string
    (make-version-string (version-with-tag compiler-version "")))

  (define check-compiler-version (make-version-checker compiler-version))
)
