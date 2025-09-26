'use strict';
const __compactRuntime = require('@midnight-ntwrk/compact-runtime');
const __shared = require('../shared/index.cjs');
const __AuthCell = require('../AuthCell/index.cjs');
const expectedRuntimeVersionString = '0.7.0';
// @parisa - Normally this will be generated. Commenting out for development purposes.
// __compactRuntime.checkRuntimeVersion(expectedRuntimeVersionString);

/**
 * @parisa - This value should disambiguate between all contracts named 'AuthCellUser' in the source code.
 */
const contractId = 'AuthCellUser';

/**
 * @parisa - Instead of generating the above descriptor for contract addresses, use the built-in descriptor for contract
 *           addresses the runtime now contains. To be clear, the unnecessary descriptor above is commented out.
 *
 *  @note - We would eventually like to in-line non-parametric descriptors like the one below. Then we could
 *          eliminate the '_descriptor_1' declaration. User-defined structs are examples of descriptors we
 *          cannot in-line.
 */
const _descriptor_1 = __compactRuntime.CompactTypeContractAddress;

/**
 * @parisa - Same here of instantiating new descriptors for UnsignedInteger(255n, 1) as in current output:
 *
 *    const _descriptor_4 = new __compactRuntime.CompactTypeUnsignedInteger(255n, 1);
 *
 *  Just use the built-in descriptor the runtime now has for max Uint 1:
 *
 *    const _descriptor_4 = __compactRuntime.CompactTypeUInt1;
 *
 *  @note - See note in comment above.
 */
const _descriptor_4 = __compactRuntime.CompactTypeUInt1;

function _use_auth_cell_0(witnessSets, circuitContext, partialProofData, x) {
  // Instantiate executables for AuthCell.
  // TODO pata. add the following, ask if it's when you see contract type decl?
  const executables_0 = __AuthCell.executables(witnessSets);
  // Finds the contract address for 'AuthCell' in the ledger state.
  const contractRefProgram0 = [
    { dup: { n: 0 } },
    {
      idx: {
        cached: false,
        pushPath: false,
        path: [
          {
            tag: 'value',
            value: {
              /**
               * The value 'CompactTypeUInt1.toValue(0n)' here represents the index of the item in the ledger state,
               * which is represented as a 0-indexed array where each item is a 'ledger' declaration starting from the
               * top. Here, we're saying "get me the value of the top-most ledger declaration."
               *
               * Running 'queryLedgerState' with this program would normally return you back a struct representation of
               * "ContractAddress" as declared in the Compact standard library. If you gave it to 'queryForContractRef'
               * instead, you get back the hex representation of the address, which the runtime uses for maintaining state.
               */
              value: __compactRuntime.CompactTypeUInt1.toValue(0n),
              alignment: __compactRuntime.CompactTypeUInt1.alignment(),
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
  ];
    //can this be wrapped in descriptor from value? my guess is that once the change from struct to contracttype happens this would also be fixed.
    //TODO/check
  const v = __compactRuntime.interContractCall(circuitContext, executables_0, __AuthCell.contractId, 'get', contractRefProgram0, partialProofData);
  // Invoke 'set'
  __compactRuntime.interContractCall(circuitContext, executables_0, __AuthCell.contractId, 'set', contractRefProgram0, partialProofData, { value: v.value + x.value });
  return v;
}

// This is a factory function. It replaces the 'Contract' constructor for compactc for DevNet.
function executables(...args) {
  if (args.length !== 1) {
    throw new __compactRuntime.CompactError(`Executables constructor: expected 1 argument, received ${args.length}`);
  }
  // 'witnessSets' corresponds to 'WitnessSets' type from 'AuthCellUser/index.d.cts'.
  const witnessSets = args[0];
  // check we have entries in 'witnessSets' for 'AuthCell' and 'AuthCellUser'.
  if (typeof (witnessSets) !== 'object') {
    throw new __compactRuntime.CompactError('first (witnesses) argument to executables constructor is not an object');
  }
  if (typeof (witnessSets[contractId]) !== 'object') {
    throw new __compactRuntime.CompactError('first (witnesses) argument to executables constructor is not an object');
  }
  if (typeof (witnessSets[__AuthCell.contractId]) !== 'object') {
    throw new __compactRuntime.CompactError('witnesses argument to executables constructor does not contain a \'AuthCellUser\' implementation');
  }
  // Check all witness entries are present
  if (typeof (witnessSets[__AuthCell.contractId].sk) !== 'function') {
    throw new __compactRuntime.CompactError('\'AuthCellUser\' implementation in witness sets passed to executables constructor does not contain a function-valued field named \'sk\'');
  }
  const impureCircuits = {
    use_auth_cell: (...args_0) => {
      if (args_0.length !== 2) {
        throw new __compactRuntime.CompactError(`use_auth_cell: expected 2 arguments (as invoked from Typescript), received ${args_0.length}`);
      }
      const context = args_0[0];
      const x = args_0[1];
      // @parisa - Simplified 'context' object structure check below
      if (typeof (context) === 'object' || context.currentQueryContext === null || context.currentPrivateState === null) {
        __compactRuntime.typeError('use_auth_cell',
          'argument 1 (as invoked from Typescript)',
          'examples/auth-cell-user.compact line 14, char 1',
          'CircuitContext',
          context);
      }
      if (!(typeof (x) === 'object' && typeof (x.value) === 'bigint' && x.value >= 0 && x.value <= __compactRuntime.MAX_FIELD)) {
        __compactRuntime.typeError('use_auth_cell',
          'argument 1 (argument 2 as invoked from Typescript)',
          'examples/auth-cell-user.compact line 14, char 1',
          'struct StructExample[value: Field]',
          x);
      }
      const partialProofData = {
        input: {
          value: __shared._descriptor_3.toValue(x),
          alignment: __shared._descriptor_3.alignment(),
        },
        // TODO: Leave out 'output' field.
        output: undefined,
        publicTranscript: [],
        privateTranscriptOutputs: [],
      };
      const result = _use_auth_cell_0(witnessSets, context, partialProofData, x);
      // TODO: Replace mutation with spread operator
      partialProofData.output = {
        value: __shared._descriptor_3.toValue(result),
        alignment: __shared._descriptor_3.alignment(),
      };
      // The 'finalizeCircuitContext' call always occurs just before the result is returned.
      __compactRuntime.finalizeCircuitContext(context, partialProofData);
      return { result: result, context: context };
    },
  };

  function stateConstructor(...args) {
    if (args.length !== 2) {
      throw new __compactRuntime.CompactError(`Contract state constructor: expected 2 arguments (as invoked from Typescript), received ${args.length}`);
    }
    // TODO next line to the return of stateconstructor.
    const constructorContext = args[0];
    const auth_cell_param = args[1];
    if (!(typeof (auth_cell_param) === 'object' && auth_cell_param)) {
      __compactRuntime.typeError('Contract state constructor', 'argument 1 (argument 2 as invoked from Typescript)', 'examples/auth-cell.compact line 12, char 5', 'struct StructExample[value: Field]', auth_cell_param);
    }
    const state = new __compactRuntime.ContractState();
    let stateValue = __compactRuntime.StateValue.newArray();
    stateValue = stateValue.arrayPush(__compactRuntime.StateValue.newNull());
    state.data = stateValue;
    state.setOperation('use_auth_cell', new __compactRuntime.ContractOperation());

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
    __compactRuntime.queryLedgerState(context,
      partialProofData,
      [
        {
          push: {
            storage: false,
            value: __compactRuntime.StateValue.newCell({
              value: _descriptor_4.toValue(0n),
              alignment: _descriptor_4.alignment(),
            }).encode(),
          },
        },
        {
          push: {
            storage: true,
            value: __compactRuntime.StateValue.newCell({
              value: _descriptor_1.toValue(auth_cell_param),
              alignment: _descriptor_1.alignment(),
            }).encode(),
          },
        },
        { ins: { cached: false, n: 1 } },
      ]);
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
    stateConstructor,
    ledgerStateDecoder,
  };
}

// @parisa - 'ledgerStateDecoder' is just the 'ledger' function renamed
function ledgerStateDecoder(state) {
  const context = {
    currentQueryContext: new __compactRuntime.QueryContext(state, __compactRuntime.dummyContractAddress()),
  };
  const partialProofData = {
    input: { value: [], alignment: [] },
    output: undefined,
    publicTranscript: [],
    privateTranscriptOutputs: [],
  };
  return {
    get authCell() {
      // For contract references stored in the ledger state, we can use the 'queryContractAddress' utility function.
      // Otherwise, output as compactc would for DevNet.
      // @parisa - 'prog' should be generated as it would if you were reading a 'std.ContractAddress' struct from somewhere
      //           in the ledger state. It would be in-lined.
        // TODO fix prog, it's 0n now.
      return __compactRuntime.queryLedgerState(context, partialProofData, prog);
    },
  };
}

const pureCircuits = {};

exports.contractId = contractId;
exports.contractReferenceLocations = []; // @parisa - replace with actual 'contractReferenceLocations'
exports.pureCircuits = pureCircuits;
exports.executables = executables;
exports.ledgerStateDecoder = ledgerStateDecoder;
//# sourceMappingURL=index.cjs.map
