;;; This file is part of Compact.
;;; Copyright (C) 2026 Minokawa project contributors
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

;; The build-provenance values `compactc --version` reports. A release build
;; rewrites this file whole (scripts/stamp-compiler-version.sh, run by
;; release-build.yml), so it holds all and only the stamped values; the
;; committed copy is what an unstamped build reports.
(library (version-config)
  (export compiler-version-tag compiler-version-commit
          compiler-version-commit-date)
  (import (chezscheme))

  ;; The prerelease identifier of the release being built: `-rc.2` for a
  ;; candidate, "" for a final. The tag arrives as a workflow input, so it
  ;; cannot be committed; the committed value is `-dev` rather than "", so a
  ;; build nothing stamped cannot pass for a release (issue #705).
  (define compiler-version-tag "-dev")

  ;; The commit this was built from, all forty characters; "" when nothing
  ;; stamped it -- a local build cannot know its commit. `--version`
  ;; abbreviates it; verbose and contract-info.json keep it whole. It sits
  ;; beside the version rather than inside it as build metadata, because
  ;; the version string is matched on and comparators do not reliably
  ;; ignore metadata (Rust's `semver` orders it), so `0.34.1+g<commit>`
  ;; would read as a different version.
  (define compiler-version-commit "")

  ;; That commit's date, YYYY-MM-DD. Reported by `--version`, but not recorded
  ;; in contract-info.json: the commit already identifies the build.
  (define compiler-version-commit-date "")
)
