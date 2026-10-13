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

# Print the part of a compactc release artifact name that identifies the target,
# given the name of a directory in compiler/targets/:
#
#   ocrt-4_0-zkir-3_1  ->  ocrt_v4.0-zkir_v3.1
#
# so that the artifact of a release is
#
#   compactc_v<compiler-version>_<os>_ocrt_v<M.m>-zkir_v<M.m>.zip
#
# e.g., compactc_v0.36.0_aarch64-darwin_ocrt_v4.0-zkir_v3.1.zip.  A name that is
# not of the form ocrt-<major>_<minor>-zkir-<major>_<minor> is an error.

set -o errexit
set -o nounset

if [ $# -ne 1 ]; then
  echo "usage: $(basename "$0") <target>" >&2
  exit 2
fi

target="$1"
pattern='^ocrt-([0-9]+)_([0-9]+)-zkir-([0-9]+)_([0-9]+)$'

if [[ ! "$target" =~ $pattern ]]; then
  echo "error: '$target' is not of the form ocrt-<major>_<minor>-zkir-<major>_<minor>" >&2
  exit 1
fi

echo "ocrt_v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}-zkir_v${BASH_REMATCH[3]}.${BASH_REMATCH[4]}"
