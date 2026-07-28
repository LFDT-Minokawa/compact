import * as __compactRuntime from '@midnight-ntwrk/compact-runtime';
__compactRuntime.checkRuntimeVersion('0.18.0-rc.1');

const _descriptor_0 = __compactRuntime.CompactTypeSecp256k1Point;

const _descriptor_1 = __compactRuntime.CompactTypeSecp256k1Base;

const _descriptor_2 = new __compactRuntime.CompactTypeBytes(20);

const _descriptor_3 = new __compactRuntime.CompactTypeUnsignedInteger(255n, 1);

const _descriptor_4 = new __compactRuntime.CompactTypeVector(32, _descriptor_3);

class _tuple_0 {
  alignment() {
    return _descriptor_4.alignment().concat(_descriptor_4.alignment());
  }
  fromValue(value_0) {
    return [
      _descriptor_4.fromValue(value_0),
      _descriptor_4.fromValue(value_0)
    ]
  }
  toValue(value_0) {
    return _descriptor_4.toValue(value_0[0]).concat(_descriptor_4.toValue(value_0[1]));
  }
}

const _descriptor_5 = new _tuple_0();

const _descriptor_6 = new __compactRuntime.CompactTypeBytes(32);

const _descriptor_7 = new __compactRuntime.CompactTypeUnsignedInteger(18446744073709551615n, 8);

const _descriptor_8 = __compactRuntime.CompactTypeBoolean;

class _Either_0 {
  alignment() {
    return _descriptor_8.alignment().concat(_descriptor_6.alignment().concat(_descriptor_6.alignment()));
  }
  fromValue(value_0) {
    return {
      is_left: _descriptor_8.fromValue(value_0),
      left: _descriptor_6.fromValue(value_0),
      right: _descriptor_6.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_8.toValue(value_0.is_left).concat(_descriptor_6.toValue(value_0.left).concat(_descriptor_6.toValue(value_0.right)));
  }
}

const _descriptor_9 = new _Either_0();

const _descriptor_10 = new __compactRuntime.CompactTypeUnsignedInteger(340282366920938463463374607431768211455n, 16);

class _ContractAddress_0 {
  alignment() {
    return _descriptor_6.alignment();
  }
  fromValue(value_0) {
    return {
      bytes: _descriptor_6.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_6.toValue(value_0.bytes);
  }
}

const _descriptor_11 = new _ContractAddress_0();

const _descriptor_12 = new __compactRuntime.CompactTypeUnsignedInteger(4294967295n, 4);

export class Contract {
  witnesses;
  constructor(...args_0) {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`Contract constructor: expected 1 argument, received ${args_0.length}`);
    }
    const witnesses_0 = args_0[0];
    if (typeof(witnesses_0) !== 'object') {
      throw new __compactRuntime.CompactError('first (witnesses) argument to Contract constructor is not an object');
    }
    this.witnesses = witnesses_0;
    this.circuits = {
      storeEthereumAddress: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`storeEthereumAddress: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const pk_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('storeEthereumAddress',
                                     'argument 1 (as invoked from Typescript)',
                                     'prove-ethereum-address.compact line 42 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_0.toValue(pk_0),
            alignment: _descriptor_0.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._storeEthereumAddress_0(context,
                                                            partialProofData,
                                                            pk_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      }
    };
    this.impureCircuits = {
      storeEthereumAddress: this.circuits.storeEthereumAddress
    };
    this.provableCircuits = {
      storeEthereumAddress: this.circuits.storeEthereumAddress
    };
  }
  async initialState(...args_0) {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`Contract state constructor: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const constructorContext_0 = args_0[0];
    if (typeof(constructorContext_0) !== 'object') {
      throw new __compactRuntime.CompactError(`Contract state constructor: expected 'constructorContext' in argument 1 (as invoked from Typescript) to be an object`);
    }
    if (!('initialZswapLocalState' in constructorContext_0)) {
      throw new __compactRuntime.CompactError(`Contract state constructor: expected 'initialZswapLocalState' in argument 1 (as invoked from Typescript)`);
    }
    if (typeof(constructorContext_0.initialZswapLocalState) !== 'object') {
      throw new __compactRuntime.CompactError(`Contract state constructor: expected 'initialZswapLocalState' in argument 1 (as invoked from Typescript) to be an object`);
    }
    const state_0 = new __compactRuntime.ContractState();
    let stateValue_0 = __compactRuntime.StateValue.newArray();
    stateValue_0 = stateValue_0.arrayPush(__compactRuntime.StateValue.newNull());
    state_0.data = new __compactRuntime.ChargedState(stateValue_0);
    state_0.setOperation('storeEthereumAddress', new __compactRuntime.ContractOperation());
    const context = __compactRuntime.createCircuitContext('constructor', __compactRuntime.dummyContractAddress(), constructorContext_0.initialZswapLocalState.coinPublicKey, state_0.data, constructorContext_0.initialPrivateState);
    const partialProofData = {
      input: { value: [], alignment: [] },
      output: undefined,
      publicTranscript: [],
      privateTranscriptOutputs: []
    };
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_3.toValue(0n),
                                                                                              alignment: _descriptor_3.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(new Uint8Array(20)),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    const tmp_0 = new Uint8Array(20);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_3.toValue(0n),
                                                                                              alignment: _descriptor_3.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(tmp_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    state_0.data = new __compactRuntime.ChargedState(context.callContext.currentQueryContext.state.state);
    return {
      currentContractState: state_0,
      currentPrivateState: context.callContext.currentPrivateState,
      currentZswapLocalState: context.callContext.currentZswapLocalState
    }
  }
  _secp256k1BaseBigEndian_0(b_0) {
    const vec_0 = Array.from(__compactRuntime.convertBigintToBytes(32,
                                                                   b_0,
                                                                   '<standard library>'),
                             BigInt);
    return [vec_0[31],
            vec_0[30],
            vec_0[29],
            vec_0[28],
            vec_0[27],
            vec_0[26],
            vec_0[25],
            vec_0[24],
            vec_0[23],
            vec_0[22],
            vec_0[21],
            vec_0[20],
            vec_0[19],
            vec_0[18],
            vec_0[17],
            vec_0[16],
            vec_0[15],
            vec_0[14],
            vec_0[13],
            vec_0[12],
            vec_0[11],
            vec_0[10],
            vec_0[9],
            vec_0[8],
            vec_0[7],
            vec_0[6],
            vec_0[5],
            vec_0[4],
            vec_0[3],
            vec_0[2],
            vec_0[1],
            vec_0[0]];
  }
  _secp256k1EthereumAddress_0(pk_0) {
    __compactRuntime.assert(!this._equal_0(pk_0,
                                           ({x: 0n, y: 0n, identity: true})),
                            'Cannot compute the address for the point at infinity');
    const hash_0 = this._keccak256_0([this._secp256k1BaseBigEndian_0(this._secp256k1PointX_0(pk_0)),
                                      this._secp256k1BaseBigEndian_0(this._secp256k1PointY_0(pk_0))]);
    return ((e, i) => e.slice(i, i+20))(hash_0, Number(12n));
  }
  _keccak256_0(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_5, value_0);
    return result_0;
  }
  _secp256k1PointX_0(pt_0) {
    const result_0 = __compactRuntime.secp256k1PointX(pt_0);
    return result_0;
  }
  _secp256k1PointY_0(pt_0) {
    const result_0 = __compactRuntime.secp256k1PointY(pt_0);
    return result_0;
  }
  async _storeEthereumAddress_0(context, partialProofData, pk_0) {
    const addr_0 = this._secp256k1EthereumAddress_0(pk_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_3.toValue(0n),
                                                                                              alignment: _descriptor_3.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(addr_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return addr_0;
  }
  _equal_0(x0, y0) {
    if (x0.identity) { return y0.identity; }
    if (y0.identity || x0.x != y0.x || x0.y != y0.y) {
      return false;
    }
    return true;
  }
}
export function ledger(stateOrChargedState) {
  const state = stateOrChargedState instanceof __compactRuntime.StateValue ? stateOrChargedState : stateOrChargedState.state;
  const chargedState = stateOrChargedState instanceof __compactRuntime.StateValue ? new __compactRuntime.ChargedState(stateOrChargedState) : stateOrChargedState;
  const context = {
    callContext: { currentQueryContext: new __compactRuntime.QueryContext(chargedState, __compactRuntime.dummyContractAddress()), currentGasCost: __compactRuntime.emptyRunningCost() },
    costModel: __compactRuntime.CostModel.initialCostModel()
  };
  const partialProofData = {
    input: { value: [], alignment: [] },
    output: undefined,
    publicTranscript: [],
    privateTranscriptOutputs: []
  };
  return {
    get lastAddr() {
      return _descriptor_2.fromValue(__compactRuntime.queryLedgerState(context,
                                                                       partialProofData,
                                                                       [
                                                                        { dup: { n: 0 } },
                                                                        { idx: { cached: false,
                                                                                 pushPath: false,
                                                                                 path: [
                                                                                        { tag: 'value',
                                                                                          value: { value: _descriptor_3.toValue(0n),
                                                                                                   alignment: _descriptor_3.alignment() } }] } },
                                                                        { popeq: { cached: false,
                                                                                   result: undefined } }]).value);
    }
  };
}
const _emptyContext = {
  callContext: { currentQueryContext: new __compactRuntime.QueryContext(new __compactRuntime.ContractState().data, __compactRuntime.dummyContractAddress()), currentGasCost: __compactRuntime.emptyRunningCost() }
};
const _dummyContract = new Contract({ });
export const pureCircuits = {};
export const contractReferenceLocations =
  { tag: 'publicLedgerArray', indices: { } };
export const expectedVk = {
  'storeEthereumAddress': '3f4e09b593e82b232fe65def5da74a0e5becc5cac0c0c59f9fe88c0573c93c2f',
};

//# sourceMappingURL=index.js.map
