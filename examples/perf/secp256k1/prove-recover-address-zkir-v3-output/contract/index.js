import * as __compactRuntime from '@midnight-ntwrk/compact-runtime';
__compactRuntime.checkRuntimeVersion('0.18.0-rc.1');

const _descriptor_0 = new __compactRuntime.CompactTypeBytes(32);

const _descriptor_1 = __compactRuntime.CompactTypeSecp256k1Scalar;

const _descriptor_2 = __compactRuntime.CompactTypeSecp256k1Point;

class _Secp256k1EcdsaSignatureWithRecovery_0 {
  alignment() {
    return _descriptor_1.alignment().concat(_descriptor_1.alignment().concat(_descriptor_2.alignment()));
  }
  fromValue(value_0) {
    return {
      r: _descriptor_1.fromValue(value_0),
      s: _descriptor_1.fromValue(value_0),
      R: _descriptor_2.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_1.toValue(value_0.r).concat(_descriptor_1.toValue(value_0.s).concat(_descriptor_2.toValue(value_0.R)));
  }
}

const _descriptor_3 = new _Secp256k1EcdsaSignatureWithRecovery_0();

const _descriptor_4 = new __compactRuntime.CompactTypeBytes(20);

const _descriptor_5 = __compactRuntime.CompactTypeSecp256k1Base;

const _descriptor_6 = new __compactRuntime.CompactTypeBytes(64);

const _descriptor_7 = new __compactRuntime.CompactTypeUnsignedInteger(18446744073709551615n, 8);

const _descriptor_8 = __compactRuntime.CompactTypeBoolean;

class _Either_0 {
  alignment() {
    return _descriptor_8.alignment().concat(_descriptor_0.alignment().concat(_descriptor_0.alignment()));
  }
  fromValue(value_0) {
    return {
      is_left: _descriptor_8.fromValue(value_0),
      left: _descriptor_0.fromValue(value_0),
      right: _descriptor_0.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_8.toValue(value_0.is_left).concat(_descriptor_0.toValue(value_0.left).concat(_descriptor_0.toValue(value_0.right)));
  }
}

const _descriptor_9 = new _Either_0();

const _descriptor_10 = new __compactRuntime.CompactTypeUnsignedInteger(340282366920938463463374607431768211455n, 16);

class _ContractAddress_0 {
  alignment() {
    return _descriptor_0.alignment();
  }
  fromValue(value_0) {
    return {
      bytes: _descriptor_0.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_0.toValue(value_0.bytes);
  }
}

const _descriptor_11 = new _ContractAddress_0();

const _descriptor_12 = new __compactRuntime.CompactTypeUnsignedInteger(255n, 1);

const _descriptor_13 = new __compactRuntime.CompactTypeUnsignedInteger(4294967295n, 4);

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
      recoverAddr: async (...args_1) => {
        if (args_1.length !== 3) {
          throw new __compactRuntime.CompactError(`recoverAddr: expected 3 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const msgHash_0 = args_1[1];
        const sig_0 = args_1[2];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('recoverAddr',
                                     'argument 1 (as invoked from Typescript)',
                                     'secp256k1.compact line 107 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(msgHash_0.buffer instanceof ArrayBuffer && msgHash_0.BYTES_PER_ELEMENT === 1 && msgHash_0.length === 32)) {
          __compactRuntime.typeError('recoverAddr',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'secp256k1.compact line 107 char 1',
                                     'Bytes<32>',
                                     msgHash_0)
        }
        if (!(typeof(sig_0) === 'object' && typeof(sig_0.r) === 'bigint' && sig_0.r >= 0 && sig_0.r <= __compactRuntime.MAX_SECP256K1_SCALAR && typeof(sig_0.s) === 'bigint' && sig_0.s >= 0 && sig_0.s <= __compactRuntime.MAX_SECP256K1_SCALAR && true)) {
          __compactRuntime.typeError('recoverAddr',
                                     'argument 2 (argument 3 as invoked from Typescript)',
                                     'secp256k1.compact line 107 char 1',
                                     'struct Secp256k1EcdsaSignatureWithRecovery<r: Secp256k1Scalar, s: Secp256k1Scalar, R: Opaque<"Secp256k1Point">>',
                                     sig_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_0.toValue(msgHash_0).concat(_descriptor_3.toValue(sig_0)),
            alignment: _descriptor_0.alignment().concat(_descriptor_3.alignment())
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._recoverAddr_0(context,
                                                   partialProofData,
                                                   msgHash_0,
                                                   sig_0);
        partialProofData.output = { value: _descriptor_4.toValue(result_0), alignment: _descriptor_4.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      }
    };
    this.impureCircuits = { recoverAddr: this.circuits.recoverAddr };
    this.provableCircuits = { recoverAddr: this.circuits.recoverAddr };
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
    state_0.setOperation('recoverAddr', new __compactRuntime.ContractOperation());
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
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_12.toValue(0n),
                                                                                              alignment: _descriptor_12.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_4.toValue(new Uint8Array(20)),
                                                                                              alignment: _descriptor_4.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    const tmp_0 = new Uint8Array(20);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_12.toValue(0n),
                                                                                              alignment: _descriptor_12.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_4.toValue(tmp_0),
                                                                                              alignment: _descriptor_4.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    state_0.data = new __compactRuntime.ChargedState(context.callContext.currentQueryContext.state.state);
    return {
      currentContractState: state_0,
      currentPrivateState: context.callContext.currentPrivateState,
      currentZswapLocalState: context.callContext.currentZswapLocalState
    }
  }
  _keccak256_0(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_6, value_0);
    return result_0;
  }
  _neg_0(s_0) {
    const result_0 = __compactRuntime.secp256k1ScalarNeg(s_0);
    return result_0;
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
  _secp256k1PointY_0(pt_0) {
    const result_0 = __compactRuntime.secp256k1PointY(pt_0);
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
  _reverseBytes32_0(b_0) {
    return Uint8Array.from([BigInt(b_0[31n]),
                            BigInt(b_0[30n]),
                            BigInt(b_0[29n]),
                            BigInt(b_0[28n]),
                            BigInt(b_0[27n]),
                            BigInt(b_0[26n]),
                            BigInt(b_0[25n]),
                            BigInt(b_0[24n]),
                            BigInt(b_0[23n]),
                            BigInt(b_0[22n]),
                            BigInt(b_0[21n]),
                            BigInt(b_0[20n]),
                            BigInt(b_0[19n]),
                            BigInt(b_0[18n]),
                            BigInt(b_0[17n]),
                            BigInt(b_0[16n]),
                            BigInt(b_0[15n]),
                            BigInt(b_0[14n]),
                            BigInt(b_0[13n]),
                            BigInt(b_0[12n]),
                            BigInt(b_0[11n]),
                            BigInt(b_0[10n]),
                            BigInt(b_0[9n]),
                            BigInt(b_0[8n]),
                            BigInt(b_0[7n]),
                            BigInt(b_0[6n]),
                            BigInt(b_0[5n]),
                            BigInt(b_0[4n]),
                            BigInt(b_0[3n]),
                            BigInt(b_0[2n]),
                            BigInt(b_0[1n]),
                            BigInt(b_0[0n])],
                           Number);
  }
  _hashToSecp256k1Scalar_0(digest_0) {
    const beReversed_0 = Uint8Array.from([BigInt(digest_0[31n]),
                                          BigInt(digest_0[30n]),
                                          BigInt(digest_0[29n]),
                                          BigInt(digest_0[28n]),
                                          BigInt(digest_0[27n]),
                                          BigInt(digest_0[26n]),
                                          BigInt(digest_0[25n]),
                                          BigInt(digest_0[24n]),
                                          BigInt(digest_0[23n]),
                                          BigInt(digest_0[22n]),
                                          BigInt(digest_0[21n]),
                                          BigInt(digest_0[20n]),
                                          BigInt(digest_0[19n]),
                                          BigInt(digest_0[18n]),
                                          BigInt(digest_0[17n]),
                                          BigInt(digest_0[16n]),
                                          BigInt(digest_0[15n]),
                                          BigInt(digest_0[14n]),
                                          BigInt(digest_0[13n]),
                                          BigInt(digest_0[12n]),
                                          BigInt(digest_0[11n]),
                                          BigInt(digest_0[10n]),
                                          BigInt(digest_0[9n]),
                                          BigInt(digest_0[8n]),
                                          BigInt(digest_0[7n]),
                                          BigInt(digest_0[6n]),
                                          BigInt(digest_0[5n]),
                                          BigInt(digest_0[4n]),
                                          BigInt(digest_0[3n]),
                                          BigInt(digest_0[2n]),
                                          BigInt(digest_0[1n]),
                                          BigInt(digest_0[0n])],
                                         Number);
    return __compactRuntime.convertBytesToField(115792089237316195423570985008687907852837564279074904382605163141518161494336n,
                                                32,
                                                beReversed_0,
                                                'Secp256k1Scalar',
                                                'secp256k1.compact line 88 char 10');
  }
  _secp256k1EcdsaRecover_0(msgHash_0, sig_0) {
    const z_0 = this._hashToSecp256k1Scalar_0(msgHash_0);
    const __compact_pattern_tmp1_0 = sig_0;
    const r_0 = __compact_pattern_tmp1_0.r;
    const s_0 = __compact_pattern_tmp1_0.s;
    const R_0 = __compact_pattern_tmp1_0.R;
    __compactRuntime.assert(__compactRuntime.convertBytesToField(115792089237316195423570985008687907852837564279074904382605163141518161494336n,
                                                                 32,
                                                                 __compactRuntime.convertBigintToBytes(32,
                                                                                                       this._secp256k1PointX_0(R_0),
                                                                                                       'secp256k1.compact line 99 char 11'),
                                                                 'Secp256k1Scalar',
                                                                 'secp256k1.compact line 99 char 10')
                            ===
                            r_0,
                            'R.x does not match r');
    const r_inv_0 = this._inv_0(r_0);
    const u1_0 = this._mul_0(this._neg_0(z_0), r_inv_0);
    const u2_0 = this._mul_0(s_0, r_inv_0);
    return this._ecAdd_0(this._ecMulGenerator_0(u1_0), this._ecMul_0(R_0, u2_0));
  }
  async _recoverAddr_0(context, partialProofData, msgHash_0, sig_0) {
    const pk_0 = this._secp256k1EcdsaRecover_0(msgHash_0, sig_0);
    const xBe_0 = this._reverseBytes32_0(__compactRuntime.convertBigintToBytes(32,
                                                                               this._secp256k1PointX_0(pk_0),
                                                                               'secp256k1.compact line 112 char 41'));
    const yBe_0 = this._reverseBytes32_0(__compactRuntime.convertBigintToBytes(32,
                                                                               this._secp256k1PointY_0(pk_0),
                                                                               'secp256k1.compact line 113 char 41'));
    const uncompressed_0 = Uint8Array.from(((e) => e.slice(0, 64))([...Array.from(xBe_0,
                                                                                  BigInt),
                                                                    ...Array.from(yBe_0,
                                                                                  BigInt)]),
                                           Number);
    const addr_0 = ((e, i) => e.slice(i, i+20))(this._keccak256_0(uncompressed_0),
                                                Number(12n));
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_12.toValue(0n),
                                                                                              alignment: _descriptor_12.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_4.toValue(addr_0),
                                                                                              alignment: _descriptor_4.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return addr_0;
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
      return _descriptor_4.fromValue(__compactRuntime.queryLedgerState(context,
                                                                       partialProofData,
                                                                       [
                                                                        { dup: { n: 0 } },
                                                                        { idx: { cached: false,
                                                                                 pushPath: false,
                                                                                 path: [
                                                                                        { tag: 'value',
                                                                                          value: { value: _descriptor_12.toValue(0n),
                                                                                                   alignment: _descriptor_12.alignment() } }] } },
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
  'recoverAddr': '574a31ac704c26b41d3e2b8085181b8d670ff506d8a75956523b37c90abdc2db',
};

//# sourceMappingURL=index.js.map
