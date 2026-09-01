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
# `compactc --version' reports it.
#
# An internal release takes its tag as a workflow input, so `v0.33.0-rc.2' is
# not known when compiler-version.ss is committed. Without this the compiler
# reports the release it is a candidate for -- and 0.33.0 was never published,
# so `compactc --version' named a release that does not exist. See issue #705.
#
# Usage: stamp-compiler-version.sh <tag> <commit> [file]
#
#   <tag>     the release tag, with or without a leading `v'. Anything that is
#             not a version -- a branch name, `dev-<commit>' -- marks the build
#             `-dev'.
#   <commit>  the commit being built, in whatever length you want reported
#   [file]    defaults to compiler/compiler-version.ss

set -o errexit
set -o nounset

if [ "$#" -lt 2 ]; then
  echo "usage: $(basename "$0") <tag> <commit> [file]" >&2
  exit 2
fi

TAG="$1"
COMMIT="$2"
FILE="${3:-compiler/compiler-version.ss}"

RAW="${TAG#v}"

# The committed triple is the compiler's own version, bumped per change and
# checked by changelog-check.yml. The tag has to agree with it: a disagreement
# is a mistake in the release, not something to paper over by letting one
# overwrite the other.
COMMITTED="$(sed -nE "s/.*\(make-version 'compiler ([0-9]+) ([0-9]+) ([0-9]+)\).*/\1.\2.\3/p" "$FILE")"

if [ -z "$COMMITTED" ]; then
  echo "::error::could not read the compiler version from $FILE" >&2
  exit 1
fi

SUFFIX=""

if [[ "$RAW" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(.*)$ ]]; then
  if [ "${BASH_REMATCH[1]}" != "$COMMITTED" ]; then
    echo "::error::tag $TAG is ${BASH_REMATCH[1]} but $FILE says $COMMITTED" >&2
    exit 1
  fi
  SUFFIX="${BASH_REMATCH[2]}"
else
  # A tag that carries no version is not a release: a scheduled build passes
  # the branch name, and an on-demand dev publish passes `dev-<commit>'. Mark
  # those `-dev', which orders them below every release of the same triple, so
  # a tool handed one where a release was expected rejects it instead of
  # accepting it as the release it was built from. Without the marker such a
  # build reports the same shape as a finished release and only the commit
  # distinguishes them -- and dev publishes are installable, so one can escape.
  #
  # The tag itself is deliberately not carried through: a sanitized branch name
  # can contain characters a semver prerelease identifier may not, and the
  # commit below already identifies the build exactly.
  SUFFIX="-dev"
fi

STAMP="${SUFFIX}+g${COMMIT}"

# GNU and BSD sed disagree about -i, and the macOS runners have BSD sed.
sed "s|(define compiler-version-tag \"\")|(define compiler-version-tag \"${STAMP}\")|" \
  "$FILE" > "$FILE.stamped"
mv "$FILE.stamped" "$FILE"

# Fail loudly rather than shipping a binary that reports the wrong version: if
# the line ever moves or is already stamped, the substitution above silently
# does nothing.
if ! grep -q "(define compiler-version-tag \"${STAMP}\")" "$FILE"; then
  echo "::error::failed to stamp '${STAMP}' into $FILE" >&2
  exit 1
fi

echo "compactc will report ${COMMITTED}${STAMP}"
