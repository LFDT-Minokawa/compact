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

(import (field))

(let ([out-ts (open-output-file "src/version.ts" 'replace)])
  (fprintf out-ts
            "~{\n~A~}\n\n"
            '("import { CompactError } from './error.js';"
             "import { MAX_FIELD as OCRT_MAX_FIELD } from './constants.js';"))
  (fprintf out-ts
           "export const versionString: string = ~s;\n"
           ((include "./extract-version.ss") "package.json"))
  (fprintf out-ts
    "~{\n~A~}\n"
    `(
     "export const checkRuntimeVersion = (expectedRuntimeVersionString: string): void => {"
     "  const expectedRuntimeVersion = expectedRuntimeVersionString.split('-')[0].split('.').map(Number);"
     "  const actualRuntimeVersion = versionString.split('-')[0].split('.').map(Number);"
     "  if (expectedRuntimeVersion[0] !== actualRuntimeVersion[0]"
     "      || (actualRuntimeVersion[0] === 0 && expectedRuntimeVersion[1] !== actualRuntimeVersion[1])"
     "      || expectedRuntimeVersion[1] > actualRuntimeVersion[1]"
     "      || (expectedRuntimeVersion[1] === actualRuntimeVersion[1] && expectedRuntimeVersion[2] > actualRuntimeVersion[2])) {"
     "      throw new CompactError(`Version mismatch: compiled code expects ${expectedRuntimeVersionString}, runtime is ${versionString}`);"
     "  }"
     ; NB keep in sync with (max-field) defined in compiler/field.ss
     ,(format "  const MAX_FIELD = ~dn;" (max-field))
     "  if (MAX_FIELD !== OCRT_MAX_FIELD) {"
     "    throw new CompactError(`Maximum field mismatch: compiled code uses ${MAX_FIELD}, runtime uses ${OCRT_MAX_FIELD}`);"
     "  }"
     "}"))
  (close-port out-ts))
