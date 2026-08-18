// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import fs from 'node:fs';
import path from 'node:path';
import { Result } from 'execa';
import { describe, expect, test } from 'vitest';
import { Arguments, compile, createTempFolder, ExitCodes, saveContract } from '@';

const CONTRACT = [
    'import CompactStandardLibrary;',
    'export ledger round: Counter;',
    'export circuit increment(): [] { round.increment(1); }',
].join('\n');

// CONTRACT through each stage's own unparser. The names and the safe-cast bound
// come from the passes, so a pass that changes either rewrites these.
const STAGE_OUTPUT: Record<string, string> = {
    lsrc: `(program
  (import CompactStandardLibrary () "")
  (public-ledger-declaration #t #f round (type-ref Counter))
  (circuit #t #f increment () () (ttuple)
    (block (elt-call round increment 1))))
`,
    frontend: `(program
  (import CompactStandardLibrary () "")
  (public-ledger-declaration #t #f round (type-ref Counter))
  (circuit #t #f increment () () (ttuple)
    (seq (elt-call round increment 1) (tuple))))
`,
    analyzed: `(program
  (kernel-declaration (%kernel.0 () (Kernel)))
  (public-ledger-declaration
    ((%round.1 (0) (Counter)))
    (constructor () (tuple)))
  (circuit
    %increment.2
    ()
    (ttuple)
    (seq (let* ([(%tmp.3 (tunsigned 65535)) (safe-cast
                                              (tunsigned 65535)
                                              (tunsigned 1)
                                              1)])
           (public-ledger %round.1 (0) increment %tmp.3))
         (tuple))))
`,
    circuit: `(program
  (kernel-declaration (%kernel.0 () (Kernel)))
  (public-ledger-declaration ((%round.1 (0) (Counter))))
  (circuit %increment.2 () (ty () ())
    (= 1 () (public-ledger %round.1 (0) increment 1)) ()))
`,
};

// Writes one stage, named by its key, through the unparser that stage carries.
function stageHook(stage: string): string {
    return [
        '(define hook',
        '  (lambda (stage* proof-circuit-name* compiler target-directory)',
        `    (let* ([stage (assq '${stage} stage*)]`,
        '           [program (cadr stage)]',
        '           [unparse (caddr stage)])',
        `      (call-with-output-file (string-append target-directory "/compiler/${stage}.sexp")`,
        '        (lambda (op) (pretty-print (unparse program) op))',
        "        'replace))))",
    ].join('\n');
}

function saveHook(source: string): string {
    const hookPath = createTempFolder() + 'hook.ss';
    fs.writeFileSync(hookPath, source, 'utf8');
    return hookPath;
}

describe(`[Compiler] ${Arguments.IR_HOOK}`, () => {
    test.each(Object.entries(STAGE_OUTPUT))('should hand over the %s stage', async (stage: string, expected: string) => {
        const target = createTempFolder();
        const result: Result = await compile([
            Arguments.SKIP_ZK,
            Arguments.IR_HOOK,
            saveHook(stageHook(stage)),
            saveContract(CONTRACT),
            target,
        ]);

        expect(result.exitCode).toBe(ExitCodes.Success);
        expect(fs.readFileSync(path.join(target, 'compiler', `${stage}.sexp`), 'utf8')).toBe(expected);
    });

    test('should let the hook read more than one stage', async () => {
        const target = createTempFolder();
        const hook = [
            '(define hook',
            '  (lambda (stage* proof-circuit-name* compiler target-directory)',
            '    (call-with-output-file (string-append target-directory "/compiler/stages.txt")',
            '      (lambda (op) (write (map car stage*) op))',
            "      'replace)))",
        ].join('\n');

        const result: Result = await compile([
            Arguments.SKIP_ZK,
            Arguments.IR_HOOK,
            saveHook(hook),
            saveContract(CONTRACT),
            target,
        ]);

        expect(result.exitCode).toBe(ExitCodes.Success);
        expect(fs.readFileSync(path.join(target, 'compiler', 'stages.txt'), 'utf8')).toBe(
            '(lsrc frontend analyzed circuit)',
        );
    });
});
