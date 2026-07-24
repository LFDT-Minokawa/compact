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

nix develop --no-warn-dirty .#test-contracts --command bash -c '
  set -euo pipefail
  cd test-contracts
  ln -sfn "${COMPACT_RUNTIME_PKG:-../runtime}" .compact-runtime
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  corepack yarn install --immutable
  COMPACT_BINARY=compactc corepack yarn lint
  COMPACT_BINARY=compactc corepack yarn test "$@"
' bash "$@"
