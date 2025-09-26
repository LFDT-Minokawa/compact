const { common } = require('../grammar/common.cjs');

/*
 * Create a simple config for fuzzer.
 */
function buildConfig(grammar, startNode, outputDir, outputName, contractAmount) {
    return {
        grammar: Object.assign(grammar, common),
        startNode: startNode,
        outputDir: outputDir,
        outputName: outputName,
        contractAmount: contractAmount,
        stringLength: 32,
        numberPower: 128,
        tableLength: 200,
    };
}

exports.buildConfig = buildConfig;
