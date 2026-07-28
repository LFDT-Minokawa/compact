import * as __compactRuntime from '@midnight-ntwrk/compact-runtime';
__compactRuntime.checkRuntimeVersion('0.18.0-rc.1');

const _descriptor_0 = __compactRuntime.CompactTypeBoolean;

const _descriptor_1 = new __compactRuntime.CompactTypeBytes(32);

const _descriptor_2 = __compactRuntime.CompactTypeSecp256k1Scalar;

class _Secp256k1EcdsaSignature_0 {
  alignment() {
    return _descriptor_2.alignment().concat(_descriptor_2.alignment());
  }
  fromValue(value_0) {
    return {
      r: _descriptor_2.fromValue(value_0),
      s: _descriptor_2.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_2.toValue(value_0.r).concat(_descriptor_2.toValue(value_0.s));
  }
}

const _descriptor_3 = new _Secp256k1EcdsaSignature_0();

const _descriptor_4 = __compactRuntime.CompactTypeSecp256k1Point;

const _descriptor_5 = __compactRuntime.CompactTypeSecp256k1Base;

const _descriptor_6 = new __compactRuntime.CompactTypeUnsignedInteger(18446744073709551615n, 8);

class _Either_0 {
  alignment() {
    return _descriptor_0.alignment().concat(_descriptor_1.alignment().concat(_descriptor_1.alignment()));
  }
  fromValue(value_0) {
    return {
      is_left: _descriptor_0.fromValue(value_0),
      left: _descriptor_1.fromValue(value_0),
      right: _descriptor_1.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_0.toValue(value_0.is_left).concat(_descriptor_1.toValue(value_0.left).concat(_descriptor_1.toValue(value_0.right)));
  }
}

const _descriptor_7 = new _Either_0();

const _descriptor_8 = new __compactRuntime.CompactTypeUnsignedInteger(340282366920938463463374607431768211455n, 16);

class _ContractAddress_0 {
  alignment() {
    return _descriptor_1.alignment();
  }
  fromValue(value_0) {
    return {
      bytes: _descriptor_1.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_1.toValue(value_0.bytes);
  }
}

const _descriptor_9 = new _ContractAddress_0();

const _descriptor_10 = new __compactRuntime.CompactTypeUnsignedInteger(255n, 1);

const _descriptor_11 = new __compactRuntime.CompactTypeUnsignedInteger(4294967295n, 4);

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
      verifyAndStore: async (...args_1) => {
        if (args_1.length !== 4) {
          throw new __compactRuntime.CompactError(`verifyAndStore: expected 4 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const msgHash_0 = args_1[1];
        const sig_0 = args_1[2];
        const pk_0 = args_1[3];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('verifyAndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'prove-verify.compact line 55 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(msgHash_0.buffer instanceof ArrayBuffer && msgHash_0.BYTES_PER_ELEMENT === 1 && msgHash_0.length === 32)) {
          __compactRuntime.typeError('verifyAndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'prove-verify.compact line 55 char 1',
                                     'Bytes<32>',
                                     msgHash_0)
        }
        if (!(typeof(sig_0) === 'object' && typeof(sig_0.r) === 'bigint' && sig_0.r >= 0 && sig_0.r <= __compactRuntime.MAX_SECP256K1_SCALAR && typeof(sig_0.s) === 'bigint' && sig_0.s >= 0 && sig_0.s <= __compactRuntime.MAX_SECP256K1_SCALAR)) {
          __compactRuntime.typeError('verifyAndStore',
                                     'argument 2 (argument 3 as invoked from Typescript)',
                                     'prove-verify.compact line 55 char 1',
                                     'struct Secp256k1EcdsaSignature<r: Secp256k1Scalar, s: Secp256k1Scalar>',
                                     sig_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_1.toValue(msgHash_0).concat(_descriptor_3.toValue(sig_0).concat(_descriptor_4.toValue(pk_0))),
            alignment: _descriptor_1.alignment().concat(_descriptor_3.alignment().concat(_descriptor_4.alignment()))
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._verifyAndStore_0(context,
                                                      partialProofData,
                                                      msgHash_0,
                                                      sig_0,
                                                      pk_0);
        partialProofData.output = { value: _descriptor_0.toValue(result_0), alignment: _descriptor_0.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      }
    };
    this.impureCircuits = { verifyAndStore: this.circuits.verifyAndStore };
    this.provableCircuits = { verifyAndStore: this.circuits.verifyAndStore };
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
    state_0.setOperation('verifyAndStore', new __compactRuntime.ContractOperation());
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
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_10.toValue(0n),
                                                                                              alignment: _descriptor_10.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_0.toValue(false),
                                                                                              alignment: _descriptor_0.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_10.toValue(0n),
                                                                                              alignment: _descriptor_10.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_0.toValue(false),
                                                                                              alignment: _descriptor_0.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    state_0.data = new __compactRuntime.ChargedState(context.callContext.currentQueryContext.state.state);
    return {
      currentContractState: state_0,
      currentPrivateState: context.callContext.currentPrivateState,
      currentZswapLocalState: context.callContext.currentZswapLocalState
    }
  }
  _hashToSecp256k1Scalar_0(digest_0) {
    const v_0 = Array.from(digest_0, BigInt);
    const beReversed_0 = Uint8Array.from([v_0[31],
                                          v_0[30],
                                          v_0[29],
                                          v_0[28],
                                          v_0[27],
                                          v_0[26],
                                          v_0[25],
                                          v_0[24],
                                          v_0[23],
                                          v_0[22],
                                          v_0[21],
                                          v_0[20],
                                          v_0[19],
                                          v_0[18],
                                          v_0[17],
                                          v_0[16],
                                          v_0[15],
                                          v_0[14],
                                          v_0[13],
                                          v_0[12],
                                          v_0[11],
                                          v_0[10],
                                          v_0[9],
                                          v_0[8],
                                          v_0[7],
                                          v_0[6],
                                          v_0[5],
                                          v_0[4],
                                          v_0[3],
                                          v_0[2],
                                          v_0[1],
                                          v_0[0]],
                                         Number);
    return __compactRuntime.convertBytesToField(115792089237316195423570985008687907852837564279074904382605163141518161494336n,
                                                32,
                                                beReversed_0,
                                                'Secp256k1Scalar',
                                                '<standard library>');
  }
  _secp256k1EcdsaVerify_0(msgHash_0, sig_0, pk_0) {
    const z_0 = this._hashToSecp256k1Scalar_0(msgHash_0);
    const __compact_pattern_tmp1_0 = sig_0;
    const r_0 = __compact_pattern_tmp1_0.r;
    const s_0 = __compact_pattern_tmp1_0.s;
    const w_0 = this._inv_0(s_0);
    const u1_0 = this._mul_0(z_0, w_0);
    const u2_0 = this._mul_0(r_0, w_0);
    const point_0 = this._ecAdd_0(this._ecMulGenerator_0(u1_0),
                                  this._ecMul_0(pk_0, u2_0));
    return __compactRuntime.convertBytesToField(115792089237316195423570985008687907852837564279074904382605163141518161494336n,
                                                32,
                                                __compactRuntime.convertBigintToBytes(32,
                                                                                      this._secp256k1PointX_0(point_0),
                                                                                      '<standard library>'),
                                                'Secp256k1Scalar',
                                                '<standard library>')
           ===
           r_0;
  }
  _mul_0(x_0, y_0) {
    const result_0 = __compactRuntime.secp256k1ScalarMul(x_0, y_0);
    return result_0;
  }
  _inv_0(s_0) {
    const result_0 = __compactRuntime.secp256k1ScalarInv(s_0);
    return result_0;
  }
  _secp256k1PointX_0(pt_0) {
    const result_0 = __compactRuntime.secp256k1PointX(pt_0);
    return result_0;
  }
  _ecAdd_0(a_0, b_0) {
    const result_0 = __compactRuntime.secp256k1Add(a_0, b_0);
    return result_0;
  }
  _ecMul_0(a_0, b_0) {
    const result_0 = __compactRuntime.secp256k1Mul(a_0, b_0);
    return result_0;
  }
  _ecMulGenerator_0(b_0) {
    const result_0 = __compactRuntime.secp256k1MulGenerator(b_0);
    return result_0;
  }
  async _verifyAndStore_0(context, partialProofData, msgHash_0, sig_0, pk_0) {
    const ok_0 = this._secp256k1EcdsaVerify_0(msgHash_0, sig_0, pk_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_10.toValue(0n),
                                                                                              alignment: _descriptor_10.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_0.toValue(ok_0),
                                                                                              alignment: _descriptor_0.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return ok_0;
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
    get lastVerified() {
      return _descriptor_0.fromValue(__compactRuntime.queryLedgerState(context,
                                                                       partialProofData,
                                                                       [
                                                                        { dup: { n: 0 } },
                                                                        { idx: { cached: false,
                                                                                 pushPath: false,
                                                                                 path: [
                                                                                        { tag: 'value',
                                                                                          value: { value: _descriptor_10.toValue(0n),
                                                                                                   alignment: _descriptor_10.alignment() } }] } },
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
  'verifyAndStore': '04b500731ee7f6ae00dc4988d7d92a14f9bce2a1e2bcb4d893b6af0892497530',
};

//# sourceMappingURL=index.js.map
