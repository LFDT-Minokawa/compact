import { Result } from 'execa';
import { describe, test } from 'vitest';
import { Arguments, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, expectFiles, saveContract } from '..';

const strings = generateStrings();

function generateStrings(): string[] {
    const strings: string[] = [];
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';

    for (let i = 0; i < 1000; i++) {
        const firstChar = alphabet[Math.floor(i / 26 / 26 / 26 / 26) % 26];
        const secondChar = alphabet[Math.floor(i / 26 / 26 / 26) % 26];
        const thirdChar = alphabet[Math.floor(i / 26 / 26) % 26];
        const fourthChar = alphabet[Math.floor(i / 26) % 26];
        const fifthChar = alphabet[i % 26];
        const sixthChar = alphabet[(i + 1) % 26];

        strings.push(`${firstChar}${secondChar}${thirdChar}${fourthChar}${fifthChar}${sixthChar}`);
    }

    return strings;
}

function getMinimumContractContent() {
    let content: string = '';
    content = content.concat('pragma language_version > 0.12.1;\n');
    content = content.concat('import CompactStandardLibrary;\n');
    return content;
}

function generateContractExports(): string {
    let content = getMinimumContractContent();
    generateStrings().forEach((s) => {
        content = content.concat(`export circuit ${s} (a: Boolean, b: Field): Boolean { return false; }\n`);
    });
    return content;
}

function generateContractEnums(): string {
    let content = getMinimumContractContent();
    const enums = ['a', 'b', 'c'].join(', ');
    strings.forEach((s) => {
        content = content.concat(`enum PublicState${s} { ${enums} }\n`);
    });
    return content;
}

describe('[Generated] Compiler', () => {
    test('should transpile minimum', async () => {
        const tempPath = createTempFolder();
        const contractFilePath = saveContract(getMinimumContractContent());
        const result: Result = await compile([contractFilePath, tempPath]);

        expectCompilerResult(result).toReturn('', compilerDefaultOutput(), 0);
        expectFiles(tempPath).thatGeneratedJSCodeIsValid();
    });

    test('should transpile with 10 000 circuits', async () => {
        const tempPath = createTempFolder();
        const contractFilePath = saveContract(generateContractExports());
        // skipping ZK, otherwise this takes a lot of time with new implementation
        const result: Result = await compile([Arguments.SKIP_ZK, contractFilePath, tempPath]);

        expectCompilerResult(result).toReturn('', compilerDefaultOutput(), 0);
        expectFiles(tempPath).thatGeneratedJSCodeIsValid();
    });

    test('should transpile with 10 000 enums', async () => {
        const tempPath = createTempFolder();
        const contractFilePath = saveContract(generateContractEnums());
        const result: Result = await compile([contractFilePath, tempPath]);

        expectCompilerResult(result).toReturn('', compilerDefaultOutput(), 0);
        expectFiles(tempPath).thatGeneratedJSCodeIsValid();
    });
});
