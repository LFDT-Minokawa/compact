/**
 * Notes:
 *
 *     1. All equality comparisons are done using the `===` or `!==` operators.
 *     2. `witnesses` is renamed to `witnessSets` in the generated code.
 *     3. `var` is replaced with `const` or `let` in the generated code.
 *     4. `if`/`else` statements are replaced with functions that return the result of the condition.
 *     5. All the inner circuit functions, e.g. `#_public_key_0` are brought to the top level and renamed to, e.g., `_public_key_0`.
 *        If the function accepts a `witnesses` argument, it is passed explicitly as the first argument using the `witnessSets` argument
 *        to `executables`.
 *     6. `prog` is renamed to `program` in the generated code.
 */
'use strict';
// @parisa - Normally this would be "require('@midnight-ntwrk/compact-runtime')"
const __compactRuntime = require('@midnight-ntwrk/compact-runtime');
const __shared = require('../shared/index.cjs');
const expectedRuntimeVersionString = '0.7.0';
// @parisa - Normally this will be generated. Commenting out for development purposes.
// __compactRuntime.checkRuntimeVersion(expectedRuntimeVersionString);


/**
 * @parisa - This value should disambiguate between all contracts named 'AuthCell' in the source code.
 */
const contractId = 'AuthCell';

/**
 * @parisa - Instead of instantiating new descriptors for 32 byte array as in current output:
 *
 *    const _descriptor_0 = new __compactRuntime.CompactTypeBytes(32);
 *
 *  Just use the built-in descriptor the runtime now has for 32 byte arrays:
 *
 *    const _descriptor_0 = __compactRuntime.CompactTypeBytes32;
 */

const _descriptor_0 = __compactRuntime.CompactTypeBytes32;

/**
 * @parisa - Same here of instantiating new descriptors for UnsignedInteger(255n, 1) as in current output:
 *
 *    const _descriptor_3 = new __compactRuntime.CompactTypeUnsignedInteger(255n, 1);
 *
 *  Just use the built-in descriptor the runtime now has for max Uint 1:
 *
 *    const _descriptor_3 = __compactRuntime.CompactTypeUInt8;
 */
const _descriptor_3 = __compactRuntime.CompactTypeUInt8;

/**
 *
 * @joe - We should move equality comparisons into @compact-runtime so that we don't have to replicate definitions as
 *        below.
 */
function _equal_0(x0, y0) {
  return x0.every((x, i) => y0[i] === x);
}

function _equal_1(x0, y0) {
  return x0.every((x, i) => y0[i] === x);
}

function _get_0(witnessSets, context, partialProofData) {
  __compactRuntime.assert(_equal_0(__shared.public_key(_sk_0(context, witnessSets, partialProofData)), _descriptor_0.fromValue(__compactRuntime.queryLedgerState(context, partialProofData, [
    { dup: { n: 0 } },
    {
      idx: {
        cached: false,
        pushPath: false,
        path: [
          {
            tag: 'value',
            value: {
              value: __compactRuntime.CompactTypeUInt8.toValue(1n),
              alignment: __compactRuntime.CompactTypeUInt8.alignment(),
            },
          },
        ],
      },
    },
    {
      popeq: {
        cached: false,
        result: undefined,
      },
    },
  ]).value)), 'Unauthorized');
  return __shared._descriptor_3.fromValue(__compactRuntime.queryLedgerState(context, partialProofData, [{ dup: { n: 0 } }, {
    idx: {
      cached: false, pushPath: false, path: [{
        tag: 'value', value: {
          value: _descriptor_3.toValue(0n), alignment: _descriptor_3.alignment(),
        },
      }],
    },
  }, {
    popeq: {
      cached: false, result: undefined,
    },
  }]).value);
}

function _sk_0(witnessSets, context, partialProofData) {
  const result = __compactRuntime.callWitness(context, ledger(context.currentQueryContext.state), witnessSets, contractId, 'sk');
  if (!(result.buffer instanceof ArrayBuffer && result.BYTES_PER_ELEMENT === 1 && result.length === 32)) {
    __compactRuntime.typeError('sk', 'return value', 'examples/auth-cell.compact line 7, char 1', 'Bytes[32]', result);
  }
  partialProofData.privateTranscriptOutputs.push({
    value: _descriptor_0.toValue(result), alignment: _descriptor_0.alignment(),
  });
  return result;
}

// @parisa - rename 'witnesses' to 'witnessSets' at every generated function for a circuit and witness
function _set_0(witnessSets, context, partialProofData, new_value) {
  // @parisa - All contracts export pure circuits even if it's an empty object, so we access pure circuits defined
  //           in other contracts that way.
  __compactRuntime.assert(_equal_1(__shared.pureCircuits.public_key(_sk_0(context, witnessSets, partialProofData)), _descriptor_0.fromValue(__compactRuntime.queryLedgerState(context, partialProofData, [{ dup: { n: 0 } }, {
    idx: {
      cached: false, pushPath: false, path: [{
        tag: 'value', value: {
          value: _descriptor_3.toValue(1n), alignment: _descriptor_3.alignment(),
        },
      }],
    },
  }, {
    popeq: {
      cached: false, result: undefined,
    },
  }]).value)), 'Unauthorized');
  __compactRuntime.queryLedgerState(context, partialProofData, [{
    push: {
      storage: false, value: __compactRuntime.StateValue.newCell({
        value: _descriptor_3.toValue(0n), alignment: _descriptor_3.alignment(),
      }).encode(),
    },
  }, {
    push: {
      storage: true, value: __compactRuntime.StateValue.newCell({
        value: __shared._descriptor_3.toValue(new_value), alignment: __shared._descriptor_3.valueAlignment(new_value),
      }).encode(),
    },
  }, { ins: { cached: false, n: 1 } }]);
}

function executables(...args) {
  // @parisa - If the executables have no witness set dependencies, then this assertion can be removed.
  if (args.length !== 1) {
    throw new __compactRuntime.CompactError(`Executables constructor: expected 1 argument, received ${args.length}`);
  }
  // 'witnessSets' corresponds to 'WitnessSets' type from 'AuthCell/index.d.cts'
  // @parisa - If the executables have no witness set dependencies, then this becomes `const witnessSets = {};`
  const witnessSets = args[0];
  // @parisa - If this particular contract has no witness dependencies, then this assertion can be removed.
  if (typeof (witnessSets) !== 'object') {
    throw new __compactRuntime.CompactError('first (witnesses) argument to executables constructor is not an object');
  }
  // @parisa - If this particular contract has no witnesses, then  these types of assertion can be removed.
  if (typeof (witnessSets.contractId) !== 'object') {
    // @parisa - Also note the use of backticks in string formatting to use ${contractId}.
    throw new __compactRuntime.CompactError(`witnesses argument to executables constructor does not contain a ${contractId} implementation`);
  }
  // @parisa - If this particular contract has no witnesses, then these types of assertion can be removed.
  if (typeof (witnessSets.contractId.sk) !== 'function') {
    throw new __compactRuntime.CompactError(`${contractId} implementation to executables constructor does not contain a function-valued field named 'sk'`);
  }
  const impureCircuits = {
    get: (...args_0) => {
      if (args_0.length !== 1) {
        throw new __compactRuntime.CompactError(`get: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
      }
      const context = args_0[0];
      // @parisa - Simplified 'context' object structure check below
      if (typeof (context) === 'object' || context.currentQueryContext === null || context.currentPrivateState === null) {
        __compactRuntime.typeError('get', 'argument 1 (as invoked from Typescript)', 'examples/auth-cell.compact line 18, char 1', 'CircuitContext', context);
      }
      const partialProofData = {
        input: { value: [], alignment: [] }, // TODO: (not for Parisa) Leave out 'output' field.
        output: undefined, publicTranscript: [], privateTranscriptOutputs: [],
      };
      const result = _get_0(witnessSets, context, partialProofData);
      // TODO: (not for Parisa) Replace mutation with spread operator
      partialProofData.output = {
        // @parisa - 'valueAlignment' is deprecated
        value: __shared._descriptor_3.toValue(result), alignment: __shared._descriptor_3.alignment(),
      };
      // @parisa - 'finalizeCircuitContext' is called at the end of every top-level function definition in the 'impureCircuits' object.
      //           the current 'get' function is 'top-level' the '_get_0' function is lower-level.
      __compactRuntime.finalizeCircuitContext(context, partialProofData);
      return { result: result, context: context };
    },
    set: (...args_0) => {
      if (args_0.length !== 2) {
        throw new __compactRuntime.CompactError(`set: expected 2 arguments (as invoked from Typescript), received ${args_0.length}`);
      }
      const context = args_0[0];
      const new_value = args_0[1];
      // @parisa - Simplified 'context' object structure check below
      if (typeof (context) === 'object' || context.currentQueryContext === null || context.currentPrivateState === null) {
        // @parisa - 'type_error' to 'typeError' everywhere
        __compactRuntime.typeError('set', 'argument 1 (as invoked from Typescript)', 'examples/auth-cell.compact line 23, char 1', 'CircuitContext', context);
      }
      if (!(typeof (new_value) === 'object' && typeof (new_value.value) === 'bigint' && new_value.value >= 0 && new_value.value <= __compactRuntime.MAX_FIELD)) {
        __compactRuntime.typeError('set', 'argument 1 (argument 2 as invoked from Typescript)', 'examples/auth-cell.compact line 23, char 1', 'struct StructExample[value: Field]', new_value);
      }
      const partialProofData = {
        input: {
          // @parisa - 'valueAlignment' is deprecated
          value: __shared._descriptor_3.toValue(new_value), alignment: __shared._descriptor_3.alignment(),
        }, output: undefined, publicTranscript: [], privateTranscriptOutputs: [],
      };
      const result = _set_0(witnessSets, context, partialProofData, new_value);
      partialProofData.output = { value: [], alignment: [] };
      __compactRuntime.finalizeCircuitContext(context, partialProofData);
      return { result: result, context: context };
    },
  };

  function initialState(...args) {
    if (args.length !== 2) {
      throw new __compactRuntime.CompactError(`Contract state constructor: expected 2 arguments (as invoked from Typescript), received ${args.length}`);
    }
    const constructorContext = args[0];
    const value_param = args[1];
    if (!(value_param.buffer.bytes instanceof ArrayBuffer && value_param.BYTES_PER_ELEMENT === 1 && value_param.length === 32)) {
      __compactRuntime.typeError('Contract state constructor', 'argument 1 (argument 2 as invoked from Typescript)', '@parisa - Insert correct string here', '@parisa - Insert correct string here', value_param);
    }
    const state = new __compactRuntime.ContractState();
    let stateValue = __compactRuntime.StateValue.newArray();
    stateValue = stateValue.arrayPush(__compactRuntime.StateValue.newNull());
    stateValue = stateValue.arrayPush(__compactRuntime.StateValue.newNull());
    state.data = stateValue;
    state.setOperation('get', new __compactRuntime.ContractOperation());
    state.setOperation('set', new __compactRuntime.ContractOperation());
    const dummyAddress = __compactRuntime.dummyContractAddress();
    const privateStates = { [dummyAddress]: constructorContext.initialPrivateState };
    const contractStates = { [dummyAddress]: state.data };
    const partialProofData = {
      input: { value: [], alignment: [] },
      output: undefined,
      publicTranscript: [],
      privateTranscriptOutputs: [],
    };
    const context = __compactRuntime.createCircuitContext(contractId, 'constructor', dummyAddress, __compactRuntime.decodeCoinPublicKey(constructorContext.initialZswapLocalState.coinPublicKey.bytes), contractStates, privateStates);
    __compactRuntime.queryLedgerState(context, partialProofData, [{
      push: {
        storage: false, value: __compactRuntime.StateValue.newCell({
          value: _descriptor_3.toValue(0n), alignment: _descriptor_3.alignment(),
        }).encode(),
      },
    }, {
      push: {
        storage: true, value: __compactRuntime.StateValue.newCell({
          value: __shared._descriptor_3.toValue({ value: 0n }),
          alignment: __shared._descriptor_3.valueAlignment({ value: 0n }),
        }).encode(),
      },
    }, { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context, partialProofData, [{
      push: {
        storage: false, value: __compactRuntime.StateValue.newCell({
          value: _descriptor_3.toValue(1n), alignment: _descriptor_3.alignment(),
        }).encode(),
      },
    }, {
      push: {
        storage: true, value: __compactRuntime.StateValue.newCell({
          value: _descriptor_0.toValue(new Uint8Array(32)), alignment: _descriptor_0.alignment(),
        }).encode(),
      },
    }, { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context, partialProofData, [{
      push: {
        storage: false, value: __compactRuntime.StateValue.newCell({
          value: _descriptor_3.toValue(0n), alignment: _descriptor_3.alignment(),
        }).encode(),
      },
    }, {
      push: {
        storage: true, value: __compactRuntime.StateValue.newCell({
          value: __shared._descriptor_3.toValue(value_param), alignment: __shared._descriptor_3.alignment(value_param),
        }).encode(),
      },
    }, { ins: { cached: false, n: 1 } }]);
    const tmp = __shared.pureCircuits.public_key(_sk_0(context, witnessSets, partialProofData));
    __compactRuntime.queryLedgerState(context, partialProofData, [{
      push: {
        storage: false, value: __compactRuntime.StateValue.newCell({
          value: _descriptor_3.toValue(1n), alignment: _descriptor_3.alignment(),
        }).encode(),
      },
    }, {
      push: {
        storage: true, value: __compactRuntime.StateValue.newCell({
          value: _descriptor_0.toValue(tmp), alignment: _descriptor_0.alignment(),
        }).encode(),
      },
    }, { ins: { cached: false, n: 1 } }]);
    state.data = context.currentQueryContext.state;
    return {
      currentContractState: state,
      currentPrivateState: context.currentPrivateState,
      currentZswapLocalState: context.currentZswapLocalState,
    };
  }

  return {
    contractId,
    witnessSets,
    impureCircuits,
    pureCircuits,
    initialState,
    ledger,
  };
}

function ledger(state) {
  const context = {
    currentQueryContext: new __compactRuntime.QueryContext(state, __compactRuntime.dummyContractAddress()),
  };
  const partialProofData = {
    input: { value: [], alignment: [] }, output: undefined, publicTranscript: [], privateTranscriptOutputs: [],
  };
  return {
    get value() {
      return __shared._descriptor_3.fromValue(__compactRuntime.queryLedgerState(context, partialProofData, [{ dup: { n: 0 } }, {
        idx: {
          cached: false, pushPath: false, path: [{
            tag: 'value', value: {
              value: _descriptor_3.toValue(0n), alignment: _descriptor_3.alignment(),
            },
          }],
        },
      }, {
        popeq: {
          cached: false, result: undefined,
        },
      }]).value);
    },
    get authorizedPk() {
      return _descriptor_0.fromValue(__compactRuntime.queryLedgerState(context, partialProofData, [{ dup: { n: 0 } }, {
        idx: {
          cached: false, pushPath: false, path: [{
            tag: 'value', value: {
              value: _descriptor_3.toValue(1n), alignment: _descriptor_3.alignment(),
            },
          }],
        },
      }, {
        popeq: {
          cached: false, result: undefined,
        },
      }]).value);
    },
  };
}

const pureCircuits = {
  my_pure_circuit(x) {
    return x;
  },
};

exports.contractId = contractId;
exports.contractReferenceLocations = []; // @parisa - replace with actual 'contractReferenceLocations'
exports.pureCircuits = pureCircuits;
exports.executables = executables;
exports.ledger = ledgerStateDecoder;
//# sourceMappingURL=index.cjs.map
