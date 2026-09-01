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

# Record the release being built in compiler/compiler-version.ss, so that
# `compactc --version` reports it.
#
# The tag arrives as a workflow input, so it cannot be committed; unstamped,
# a candidate reported the release it was a candidate for (issue #705).
#
# Usage: stamp-compiler-version.sh <tag> <commit> <commit-date> [file]
#
#   <tag>          the release tag, with or without a leading `v`. Anything
#                  that is not a version -- a branch name, `dev-<commit>` --
#                  marks the build `-dev`.
#   <commit>       the commit being built, in full (`git rev-parse HEAD`);
#                  `compactc --version` abbreviates it itself
#   <commit-date>  that commit's date, YYYY-MM-DD (`git show -s --format=%cs`)
#   [file]         defaults to compiler/compiler-version.ss
#
# Prints on stdout the line the built compiler will report, so a caller can
# assert it against the binary. Progress and errors go to stderr.

set -o errexit
set -o nounset

# What compiler-version.ss carries unstamped. A marker rather than "", so a
# build nothing stamped cannot look like a release.
UNSTAMPED='-dev'

if [ "$#" -lt 3 ]; then
  echo "usage: $(basename "$0") <tag> <commit> <commit-date> [file]" >&2
  exit 2
fi

TAG="$1"
COMMIT="$2"
COMMIT_DATE="$3"
FILE="${4:-compiler/compiler-version.ss}"

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
COMMITTED="$(sed -nE "s/.*\(make-version 'compiler ([0-9]+) ([0-9]+) ([0-9]+)\).*/\1.\2.\3/p" "$FILE")"

if [ -z "$COMMITTED" ]; then
  echo "::error::could not read the compiler version from $FILE" >&2
  exit 1
fi

if [[ "$RAW" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(.*)$ ]]; then
  if [ "${BASH_REMATCH[1]}" != "$COMMITTED" ]; then
    echo "::error::tag $TAG is ${BASH_REMATCH[1]} but $FILE says $COMMITTED" >&2
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

# GNU and BSD sed disagree about -i, and the macOS runners have BSD sed.
sed -e "s|(define compiler-version-tag \"${UNSTAMPED}\")|(define compiler-version-tag \"${SUFFIX}\")|" \
    -e "s|(define compiler-version-commit \"\")|(define compiler-version-commit \"${COMMIT}\")|" \
    -e "s|(define compiler-version-commit-date \"\")|(define compiler-version-commit-date \"${COMMIT_DATE}\")|" \
  "$FILE" > "$FILE.stamped"
mv "$FILE.stamped" "$FILE"

# The substitutions fail silently if a line has moved or the file is already
# stamped, so check. The commit is the one that always changes -- a dev build
# keeps the `-dev` it was committed with -- so it is what catches a second run.
if ! grep -q "(define compiler-version-commit \"${COMMIT}\")" "$FILE"; then
  echo "::error::failed to stamp commit '${COMMIT}' into $FILE" >&2
  echo "::error::$FILE must contain (define compiler-version-commit \"\") before a build" >&2
  exit 1
fi

if ! grep -q "(define compiler-version-commit-date \"${COMMIT_DATE}\")" "$FILE"; then
  echo "::error::failed to stamp commit date '${COMMIT_DATE}' into $FILE" >&2
  exit 1
fi

if ! grep -q "(define compiler-version-tag \"${SUFFIX}\")" "$FILE"; then
  echo "::error::failed to stamp '${SUFFIX}' into $FILE" >&2
  echo "::error::$FILE must contain (define compiler-version-tag \"${UNSTAMPED}\") before a build" >&2
  exit 1
fi

# Must match `abbreviate-commit` in compiler/program-common.ss. Duplicated, but
# release-build.yml compares this line against what the binary prints, so a
# drift fails the next build.
SHORT="${COMMIT:0:9}"

REPORTED="${COMMITTED}${SUFFIX} (${SHORT} ${COMMIT_DATE})"
echo "compactc will report ${REPORTED}" >&2
echo "${REPORTED}"
