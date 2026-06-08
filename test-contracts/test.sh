#!/usr/bin/env bash
# This file is part of Compact.
# Copyright (C) 2025 Midnight Foundation
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

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Build the runtime in the default dev shell (provides Chez Scheme).
nix develop --no-warn-dirty --command bash -c \
  'rm -rf runtime/node_modules/@midnight-ntwrk && cd runtime && npm run build'

# Install deps and run fixtures in the compiler shell. We invoke yarn through
# corepack (bundled with the shell's node) so it resolves to the Yarn 4 version
# pinned in this package's packageManager field, rather than the classic yarn 1
# also on PATH there.
nix develop --no-warn-dirty .#compiler --command bash -c '
  cd test-contracts
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  corepack yarn install --immutable
  COMPACT_BINARY=compactc corepack yarn lint
  COMPACT_BINARY=compactc corepack yarn test "$@"
' bash "$@"
