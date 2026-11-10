#!/usr/bin/env bash

# This file is part of Compact.
# Copyright (C) 2026 Midnight Foundation
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Record the release being built by writing compiler/version-config.ss whole,
# so that `compactc --version` reports it.
#
# The tag arrives as a workflow input, so it cannot be committed; unstamped,
# a candidate reported the release it was a candidate for (issue #705).
#
# Usage: stamp-compiler-version.sh <tag> <commit> <commit-date> [config] [source]
#
#   <tag>          the release tag, with or without a leading `v`. Anything
#                  that is not a version -- a branch name, `dev-<commit>` --
#                  marks the build `-dev`.
#   <commit>       the commit being built, in full (`git rev-parse HEAD`);
#                  `compactc --version` abbreviates it itself
#   <commit-date>  that commit's date, YYYY-MM-DD (`git show -s --format=%cs`)
#   [config]       the file written whole; defaults to compiler/version-config.ss
#   [source]       where the committed triple is read from; defaults to
#                  compiler/compiler-version.ss
#
# Prints on stdout the line the built compiler will report, so a caller can
# assert it against the binary. Progress and errors go to stderr.

set -o errexit
set -o nounset

# What version-config.ss carries unstamped. A marker rather than "", so a
# build nothing stamped cannot look like a release.
UNSTAMPED='-dev'

if [ "$#" -lt 3 ]; then
  echo "usage: $(basename "$0") <tag> <commit> <commit-date> [file]" >&2
  exit 2
fi

TAG="$1"
COMMIT="$2"
COMMIT_DATE="$3"
CONFIG="${4:-compiler/version-config.ss}"
SOURCE="${5:-compiler/compiler-version.ss}"

# A call against the old <tag> <commit> [file] signature would stamp a
# pathname as the date; the shape check catches it.
if [[ ! "$COMMIT_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "::error::commit date '$COMMIT_DATE' is not YYYY-MM-DD" >&2
  exit 2
fi

# The whole hash: the compiler shortens it for the one-line form itself, and
# recorded provenance should not be lossy.
if [[ ! "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::commit '$COMMIT' is not a full 40-character hash" >&2
  echo "::error::pass 'git rev-parse HEAD'; --version derives the short form" >&2
  exit 2
fi

RAW="${TAG#v}"

# A semver prerelease with its leading `-`: dot-separated identifiers, each a
# number without a leading zero or an alphanumeric. The `-` is required, not
# stripped -- the suffix is appended to the version verbatim, so a dashless
# `rc.1` would stamp the non-semver `0.34.102rc.1`. Validated because the
# suffix lands in a Scheme string literal below, where a quote would end the
# string and compile the rest into the compiler. One regex rather than an
# `IFS` split, which would accept a trailing dot.
valid_prerelease() {
  local id='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
  [[ "$1" =~ ^-$id(\.$id)*$ ]]
}

# The committed triple is the compiler's own version, bumped per change and
# checked by changelog-check.yml, so a tag that disagrees is a mistake in the
# release rather than something to paper over.
COMMITTED="$("$(dirname "$0")/read-version.sh" compiler "$SOURCE")"

if [[ "$RAW" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(.*)$ ]]; then
  if [ "${BASH_REMATCH[1]}" != "$COMMITTED" ]; then
    echo "::error::tag $TAG is ${BASH_REMATCH[1]} but $SOURCE says $COMMITTED" >&2
    exit 1
  fi
  SUFFIX="${BASH_REMATCH[2]}"
  if [ -n "$SUFFIX" ] && ! valid_prerelease "$SUFFIX"; then
    echo "::error::tag $TAG has a suffix that is not a valid semver prerelease identifier: $SUFFIX" >&2
    echo "::error::expected something like -rc.2; the commit is recorded by the build, not the tag" >&2
    exit 1
  fi
else
  # No version in the tag means this is not a release: a scheduled build passes
  # the branch name, a dev publish passes `dev-<commit>`. The tag itself is
  # dropped -- a branch name can hold characters a prerelease cannot, and the
  # stamped commit already identifies the build.
  SUFFIX="$UNSTAMPED"
fi

# Refuse a path that is not the config library.
if ! grep -q "(library (version-config)" "$CONFIG"; then
  echo "::error::$CONFIG is not the version-config library; refusing to overwrite it" >&2
  exit 1
fi

cat > "$CONFIG" <<EOF
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

;; Generated by scripts/stamp-compiler-version.sh for tag \`${TAG}\` -- do not
;; commit; the committed copy carries the unstamped defaults.
(library (version-config)
  (export compiler-version-tag compiler-version-commit
          compiler-version-commit-date)
  (import (chezscheme))

  (define compiler-version-tag "${SUFFIX}")
  (define compiler-version-commit "${COMMIT}")
  (define compiler-version-commit-date "${COMMIT_DATE}")
)
EOF

# Must match `abbreviate-commit` in compiler/program-common.ss. Duplicated, but
# release-build.yml compares this line against what the binary prints, so a
# drift fails the next build.
SHORT="${COMMIT:0:9}"

REPORTED="${COMMITTED}${SUFFIX} (${SHORT} ${COMMIT_DATE})"
echo "compactc will report ${REPORTED}" >&2
echo "${REPORTED}"
