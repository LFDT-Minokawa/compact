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
  (export compiler-version-string check-compiler-version)
  (import (chezscheme) (version))

  ;; The release tag of this build: a prerelease identifier, build metadata, or
  ;; both, including the leading #\- or #\+. Empty in a development tree.
  ;;
  ;; Set by .github/workflows/release-build.yml from the tag being built, and
  ;; not committed with a value, because an internal release takes its tag as a
  ;; workflow input -- `v0.33.0-rc.2' is not known when this file is written.
  ;; Without it a candidate reports the release it is a candidate for, and
  ;; 0.33.0 never shipped, so `compactc --version' named a release that does not
  ;; exist. See issue #705.
  (define compiler-version-tag "")

  ; NB: also update compactc version in ../flake.nix
  (define compiler-version
    (version-with-tag (make-version 'compiler 0 34 101) compiler-version-tag))

  (define compiler-version-string (make-version-string compiler-version))

  (define check-compiler-version (make-version-checker compiler-version))
)
