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

import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
    test: {
        globals: true,
        environment: 'node',
        include: ['**/*.test.ts'],
        exclude: ['./node_modules', './dist', 'src/fuzzer'],
        testTimeout: 180_000,
        reporters: process.env.GITHUB_ACTIONS
            ? [
                  'verbose',
                  'github-actions',
                  ['junit', { outputFile: './reports/test-report.xml' }],
                  ['html', { outputFile: './reports/html/index.html' }],
                  ['@d2t/vitest-ctrf-json-reporter', { outputDir: './reports', outputFile: 'ctrf-report.json' }],
                  ['allure-vitest/reporter', { resultsDir: './reports/allure-reports' }],
              ]
            : ['verbose', ['html', { outputFile: './reports/html/index.html' }]],
        setupFiles: ['allure-vitest/setup', 'vitest.setup.mjs'],
    },
    resolve: {
        extensions: ['.ts', '.js'],
        alias: {
            '@': path.resolve(__dirname, 'src'),
        },
    },
});
