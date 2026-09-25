#!/usr/bin/env bash

# This file is part of Compact.
# Copyright (C) 2026 Minokawa project contributors
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

# Print a version committed in Scheme source as x.y.z, read from its
# `(make-version '<feature> M m b)` line. CI needs these versions before any
# compiler binary exists, so they are read from source; this script is the one
# place that knows the literal form, so a change to it breaks one script
# rather than every workflow that greps.
#
# Usage: read-version.sh <feature> [file]
#
#   <feature>  the symbol make-version is called with: compiler, language
#   [file]     defaults to compiler/<feature>-version.ss

set -o errexit
set -o nounset

if [ "$#" -lt 1 ]; then
  echo "usage: $(basename "$0") <feature> [file]" >&2
  exit 2
fi

FEATURE="$1"
FILE="${2:-compiler/${FEATURE}-version.ss}"

# sed -nE rather than grep -P: the macOS runners' grep has no -P.
VERSION="$(sed -nE "s/.*\(make-version '${FEATURE} ([0-9]+) ([0-9]+) ([0-9]+)\).*/\1.\2.\3/p" "$FILE")"

if [ -z "$VERSION" ]; then
  echo "::error::could not read the ${FEATURE} version from $FILE" >&2
  exit 1
fi

echo "$VERSION"
