import globals from 'globals';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import js from '@eslint/js';
import { FlatCompat } from '@eslint/eslintrc';
import vitest from "@vitest/eslint-plugin";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const compat = new FlatCompat({
    baseDirectory: __dirname,
    recommendedConfig: js.configs.recommended,
    allConfig: js.configs.all,
});

export default [
    ...compat.extends('plugin:prettier/recommended', 'plugin:@typescript-eslint/recommended-requiring-type-checking'),
    {
        plugins: { vitest },
        // fuzzer is in cjs, so ignore ts checks there for now
        ignores: ['src/fuzzer/**/*', 'src/resources/**/*'],
        languageOptions: {
            globals: {
                ...globals.browser,
                ...globals.node,
                ...vitest.environments.env.globals,
            },

            ecmaVersion: 'latest',
            sourceType: 'module',

            parserOptions: {
                project: ['tsconfig.json'],
            },
        },
        rules: {
            '@typescript-eslint/no-misused-promises': 'off',
            '@typescript-eslint/no-floating-promises': 'warn',
            '@typescript-eslint/promise-function-async': 'off',
            '@typescript-eslint/no-redeclare': 'off',
            '@typescript-eslint/no-invalid-void-type': 'off',
            '@typescript-eslint/no-unsafe-call': 'off',
            '@typescript-eslint/no-unsafe-member-access': 'off',
            '@typescript-eslint/explicit-function-return-type': 'off',
            '@typescript-eslint/consistent-type-definitions': 'off',
            ...vitest.configs.recommended.rules,
            'vitest/expect-expect': 'off',
            'vitest/valid-expect': 'off',
        },
    },
];
