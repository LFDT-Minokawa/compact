#! /bin/sh

# This file is part of Compact.
# Copyright (C) 2025 Midnight Foundation
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# 	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset

# on macos chez scheme is usually available as chez on linux as scheme
if command -v scheme &> /dev/null
then
   SCHEME=scheme
else
   SCHEME=chez
fi

echo "====================== VLQ TESTS ======================"

exec "$SCHEME" -q << END
(reset-handler abort)
(debug-level 3)
(load-program "srcMaps/test-vlq.ss")
END
