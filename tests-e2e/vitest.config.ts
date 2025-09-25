import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
    test: {
        globals: true,
        environment: 'node',
        include: ['**/*.test.ts'],
        exclude: ['./node_modules', './dist', 'src/fuzzer'],
        testTimeout: 60_000,
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
            '@': path.resolve(__dirname, './src'),
        },
    },
});
