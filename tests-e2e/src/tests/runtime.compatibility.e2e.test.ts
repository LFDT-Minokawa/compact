import { beforeAll, describe, test } from 'vitest';
import { copyFiles, createTempFolder, getFileContent } from '../file-utils';
import { execa, Result } from 'execa';
import { Arguments, compile } from '../binary-utils';
import { expectCommandResult, expectCompilerResult } from '../result-assertions';
import { expectFiles } from '../files-assertions';
import fs from 'fs';
import { logger } from '../logger-utils';

const RUNTIME_ROOT = '../runtime/';

function savePackageJson(contractDir: string, packageJson: object): void {
    fs.writeFile(`${contractDir}/package.json`, JSON.stringify(packageJson), 'utf8', (err) => {
        if (err) {
            logger.error('Error writing file:', err);
            return;
        }
        logger.info('File written successfully!');
    });
}

describe('[Runtime] Dry running contract', () => {
    const getRuntimePackage = getFileContent(RUNTIME_ROOT + '/package.json');
    const packageVersion = getRuntimePackage.match(/"version"\s*:\s*"([^"]+)"/);

    const packageJson = {
        devDependencies: {
            '@midnight-ntwrk/compact-runtime': packageVersion?.[1],
        },
    };

    beforeAll(async () => {
        const nixBuilt = await execa('nix', ['build', '.#compactc', '.#runtime.forPublish'], { cwd: '..', reject: false });
        expectCommandResult(nixBuilt).toReturn('', '', 0);
    }, 180_000);

    test(`using - the actual npm runtime`, async () => {
        const outputDir = createTempFolder();
        const contractDir = `${outputDir}/contract`;

        const result: Result = await compile([Arguments.SKIP_ZK, '../examples/counter.compact', outputDir]);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        savePackageJson(contractDir, packageJson);

        const install = await execa('npm', ['install'], { cwd: contractDir, reject: false });
        expectCommandResult(install).toReturn('', '', 0);

        const run = await execa('node', [`${contractDir}/index.cjs`], { reject: false });
        expectCommandResult(run).toReturn('', '', 0);
    });

    test(`using - the nix built runtime`, async () => {
        const outputDir = createTempFolder(false);
        const contractDir = `${outputDir}/contract`;
        const builtLibs = `../result-1/lib/node_modules`;

        const result: Result = await compile([Arguments.SKIP_ZK, '../examples/counter.compact', outputDir]);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        savePackageJson(contractDir, packageJson);
        copyFiles(builtLibs, contractDir);

        const run = await execa('node', [`${contractDir}/index.cjs`], { reject: false });
        expectCommandResult(run).toReturn('', '', 0);
    });
});
