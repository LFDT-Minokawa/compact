import * as __compactRuntime from '@midnight-ntwrk/compact-runtime';
__compactRuntime.checkRuntimeVersion('0.18.0-rc.1');

const _descriptor_0 = new __compactRuntime.CompactTypeBytes(32);

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

const _descriptor_1 = new _ContractAddress_0();

const _descriptor_2 = __compactRuntime.CompactTypeJubjubPoint;

const _descriptor_3 = new __compactRuntime.CompactTypeUnsignedInteger(65535n, 2);

const _descriptor_4 = __compactRuntime.CompactTypeBoolean;

class _ZswapCoinPublicKey_0 {
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

const _descriptor_5 = new _ZswapCoinPublicKey_0();

class _Either_0 {
  alignment() {
    return _descriptor_4.alignment().concat(_descriptor_5.alignment().concat(_descriptor_1.alignment()));
  }
  fromValue(value_0) {
    return {
      is_left: _descriptor_4.fromValue(value_0),
      left: _descriptor_5.fromValue(value_0),
      right: _descriptor_1.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_4.toValue(value_0.is_left).concat(_descriptor_5.toValue(value_0.left).concat(_descriptor_1.toValue(value_0.right)));
  }
}

const _descriptor_6 = new _Either_0();

const _descriptor_7 = new __compactRuntime.CompactTypeUnsignedInteger(340282366920938463463374607431768211455n, 16);

class _ShieldedCoinInfo_0 {
  alignment() {
    return _descriptor_0.alignment().concat(_descriptor_0.alignment().concat(_descriptor_7.alignment()));
  }
  fromValue(value_0) {
    return {
      nonce: _descriptor_0.fromValue(value_0),
      color: _descriptor_0.fromValue(value_0),
      value: _descriptor_7.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_0.toValue(value_0.nonce).concat(_descriptor_0.toValue(value_0.color).concat(_descriptor_7.toValue(value_0.value)));
  }
}

const _descriptor_8 = new _ShieldedCoinInfo_0();

const _descriptor_9 = __compactRuntime.CompactTypeField;

class _ZswapCoinSecretKey_0 {
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

const _descriptor_10 = new _ZswapCoinSecretKey_0();

class _MerkleTreeDigest_0 {
  alignment() {
    return _descriptor_9.alignment();
  }
  fromValue(value_0) {
    return {
      field: _descriptor_9.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_9.toValue(value_0.field);
  }
}

const _descriptor_11 = new _MerkleTreeDigest_0();

class _Either_1 {
  alignment() {
    return _descriptor_4.alignment().concat(_descriptor_10.alignment().concat(_descriptor_1.alignment()));
  }
  fromValue(value_0) {
    return {
      is_left: _descriptor_4.fromValue(value_0),
      left: _descriptor_10.fromValue(value_0),
      right: _descriptor_1.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_4.toValue(value_0.is_left).concat(_descriptor_10.toValue(value_0.left).concat(_descriptor_1.toValue(value_0.right)));
  }
}

const _descriptor_12 = new _Either_1();

class _MerkleTreePathEntry_0 {
  alignment() {
    return _descriptor_11.alignment().concat(_descriptor_4.alignment());
  }
  fromValue(value_0) {
    return {
      sibling: _descriptor_11.fromValue(value_0),
      goes_left: _descriptor_4.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_11.toValue(value_0.sibling).concat(_descriptor_4.toValue(value_0.goes_left));
  }
}

const _descriptor_13 = new _MerkleTreePathEntry_0();

const _descriptor_14 = new __compactRuntime.CompactTypeVector(32, _descriptor_13);

class _MerkleTreePath_0 {
  alignment() {
    return _descriptor_0.alignment().concat(_descriptor_14.alignment());
  }
  fromValue(value_0) {
    return {
      leaf: _descriptor_0.fromValue(value_0),
      path: _descriptor_14.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_0.toValue(value_0.leaf).concat(_descriptor_14.toValue(value_0.path));
  }
}

const _descriptor_15 = new _MerkleTreePath_0();

const _descriptor_16 = __compactRuntime.CompactTypeField;

class _tuple_0 {
  alignment() {
    return _descriptor_0.alignment().concat(_descriptor_3.alignment());
  }
  fromValue(value_0) {
    return [
      _descriptor_0.fromValue(value_0),
      _descriptor_3.fromValue(value_0)
    ]
  }
  toValue(value_0) {
    return _descriptor_0.toValue(value_0[0]).concat(_descriptor_3.toValue(value_0[1]));
  }
}

const _descriptor_17 = new _tuple_0();

const _descriptor_18 = new __compactRuntime.CompactTypeBytes(21);

class _PublicKeyPreimage_0 {
  alignment() {
    return _descriptor_18.alignment().concat(_descriptor_10.alignment());
  }
  fromValue(value_0) {
    return {
      sep: _descriptor_18.fromValue(value_0),
      secretKey: _descriptor_10.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_18.toValue(value_0.sep).concat(_descriptor_10.toValue(value_0.secretKey));
  }
}

const _descriptor_19 = new _PublicKeyPreimage_0();

const _descriptor_20 = new __compactRuntime.CompactTypeVector(2, _descriptor_9);

class _CoinPreimage_0 {
  alignment() {
    return _descriptor_18.alignment().concat(_descriptor_8.alignment().concat(_descriptor_4.alignment().concat(_descriptor_0.alignment())));
  }
  fromValue(value_0) {
    return {
      sep: _descriptor_18.fromValue(value_0),
      info: _descriptor_8.fromValue(value_0),
      dataType: _descriptor_4.fromValue(value_0),
      data: _descriptor_0.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_18.toValue(value_0.sep).concat(_descriptor_8.toValue(value_0.info).concat(_descriptor_4.toValue(value_0.dataType).concat(_descriptor_0.toValue(value_0.data))));
  }
}

const _descriptor_21 = new _CoinPreimage_0();

const _descriptor_22 = new __compactRuntime.CompactTypeUnsignedInteger(18446744073709551615n, 8);

class _Either_2 {
  alignment() {
    return _descriptor_4.alignment().concat(_descriptor_0.alignment().concat(_descriptor_0.alignment()));
  }
  fromValue(value_0) {
    return {
      is_left: _descriptor_4.fromValue(value_0),
      left: _descriptor_0.fromValue(value_0),
      right: _descriptor_0.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_4.toValue(value_0.is_left).concat(_descriptor_0.toValue(value_0.left).concat(_descriptor_0.toValue(value_0.right)));
  }
}

const _descriptor_23 = new _Either_2();

const _descriptor_24 = new __compactRuntime.CompactTypeUnsignedInteger(255n, 1);

const _descriptor_25 = new __compactRuntime.CompactTypeUnsignedInteger(4294967295n, 4);

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
      spend: async (...args_1) => {
        if (args_1.length !== 5) {
          throw new __compactRuntime.CompactError(`spend: expected 5 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const sk_0 = args_1[1];
        const path_0 = args_1[2];
        const coin_0 = args_1[3];
        const rc_0 = args_1[4];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('spend',
                                     'argument 1 (as invoked from Typescript)',
                                     'zswap.compact line 36 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(typeof(sk_0) === 'object' && typeof(sk_0.is_left) === 'boolean' && typeof(sk_0.left) === 'object' && sk_0.left.bytes.buffer instanceof ArrayBuffer && sk_0.left.bytes.BYTES_PER_ELEMENT === 1 && sk_0.left.bytes.length === 32 && typeof(sk_0.right) === 'object' && sk_0.right.bytes.buffer instanceof ArrayBuffer && sk_0.right.bytes.BYTES_PER_ELEMENT === 1 && sk_0.right.bytes.length === 32)) {
          __compactRuntime.typeError('spend',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'zswap.compact line 36 char 1',
                                     'struct Either<is_left: Boolean, left: struct ZswapCoinSecretKey<bytes: Bytes<32>>, right: struct ContractAddress<bytes: Bytes<32>>>',
                                     sk_0)
        }
        if (!(typeof(path_0) === 'object' && path_0.leaf.buffer instanceof ArrayBuffer && path_0.leaf.BYTES_PER_ELEMENT === 1 && path_0.leaf.length === 32 && Array.isArray(path_0.path) && path_0.path.length === 32 && path_0.path.every((t) => typeof(t) === 'object' && typeof(t.sibling) === 'object' && typeof(t.sibling.field) === 'bigint' && t.sibling.field >= 0 && t.sibling.field <= __compactRuntime.MAX_FIELD && typeof(t.goes_left) === 'boolean'))) {
          __compactRuntime.typeError('spend',
                                     'argument 2 (argument 3 as invoked from Typescript)',
                                     'zswap.compact line 36 char 1',
                                     'struct MerkleTreePath<leaf: Bytes<32>, path: Vector<32, struct MerkleTreePathEntry<sibling: struct MerkleTreeDigest<field: Field>, goes_left: Boolean>>>',
                                     path_0)
        }
        if (!(typeof(coin_0) === 'object' && coin_0.nonce.buffer instanceof ArrayBuffer && coin_0.nonce.BYTES_PER_ELEMENT === 1 && coin_0.nonce.length === 32 && coin_0.color.buffer instanceof ArrayBuffer && coin_0.color.BYTES_PER_ELEMENT === 1 && coin_0.color.length === 32 && typeof(coin_0.value) === 'bigint' && coin_0.value >= 0n && coin_0.value <= 340282366920938463463374607431768211455n)) {
          __compactRuntime.typeError('spend',
                                     'argument 3 (argument 4 as invoked from Typescript)',
                                     'zswap.compact line 36 char 1',
                                     'struct ShieldedCoinInfo<nonce: Bytes<32>, color: Bytes<32>, value: Uint<0..340282366920938463463374607431768211456>>',
                                     coin_0)
        }
        if (!(typeof(rc_0) === 'bigint' && rc_0 >= 0 && rc_0 <= __compactRuntime.MAX_FIELD)) {
          __compactRuntime.typeError('spend',
                                     'argument 4 (argument 5 as invoked from Typescript)',
                                     'zswap.compact line 36 char 1',
                                     'Field',
                                     rc_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_12.toValue(sk_0).concat(_descriptor_15.toValue(path_0).concat(_descriptor_8.toValue(coin_0).concat(_descriptor_9.toValue(rc_0)))),
            alignment: _descriptor_12.alignment().concat(_descriptor_15.alignment().concat(_descriptor_8.alignment().concat(_descriptor_9.alignment())))
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._spend_0(context,
                                             partialProofData,
                                             sk_0,
                                             path_0,
                                             coin_0,
                                             rc_0);
        partialProofData.output = { value: [], alignment: [] };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      output: async (...args_1) => {
        if (args_1.length !== 4) {
          throw new __compactRuntime.CompactError(`output: expected 4 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const pk_0 = args_1[1];
        const coin_0 = args_1[2];
        const rc_0 = args_1[3];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('output',
                                     'argument 1 (as invoked from Typescript)',
                                     'zswap.compact line 84 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(typeof(pk_0) === 'object' && typeof(pk_0.is_left) === 'boolean' && typeof(pk_0.left) === 'object' && pk_0.left.bytes.buffer instanceof ArrayBuffer && pk_0.left.bytes.BYTES_PER_ELEMENT === 1 && pk_0.left.bytes.length === 32 && typeof(pk_0.right) === 'object' && pk_0.right.bytes.buffer instanceof ArrayBuffer && pk_0.right.bytes.BYTES_PER_ELEMENT === 1 && pk_0.right.bytes.length === 32)) {
          __compactRuntime.typeError('output',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'zswap.compact line 84 char 1',
                                     'struct Either<is_left: Boolean, left: struct ZswapCoinPublicKey<bytes: Bytes<32>>, right: struct ContractAddress<bytes: Bytes<32>>>',
                                     pk_0)
        }
        if (!(typeof(coin_0) === 'object' && coin_0.nonce.buffer instanceof ArrayBuffer && coin_0.nonce.BYTES_PER_ELEMENT === 1 && coin_0.nonce.length === 32 && coin_0.color.buffer instanceof ArrayBuffer && coin_0.color.BYTES_PER_ELEMENT === 1 && coin_0.color.length === 32 && typeof(coin_0.value) === 'bigint' && coin_0.value >= 0n && coin_0.value <= 340282366920938463463374607431768211455n)) {
          __compactRuntime.typeError('output',
                                     'argument 2 (argument 3 as invoked from Typescript)',
                                     'zswap.compact line 84 char 1',
                                     'struct ShieldedCoinInfo<nonce: Bytes<32>, color: Bytes<32>, value: Uint<0..340282366920938463463374607431768211456>>',
                                     coin_0)
        }
        if (!(typeof(rc_0) === 'bigint' && rc_0 >= 0 && rc_0 <= __compactRuntime.MAX_FIELD)) {
          __compactRuntime.typeError('output',
                                     'argument 3 (argument 4 as invoked from Typescript)',
                                     'zswap.compact line 84 char 1',
                                     'Field',
                                     rc_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_6.toValue(pk_0).concat(_descriptor_8.toValue(coin_0).concat(_descriptor_9.toValue(rc_0))),
            alignment: _descriptor_6.alignment().concat(_descriptor_8.alignment().concat(_descriptor_9.alignment()))
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._output_0(context,
                                              partialProofData,
                                              pk_0,
                                              coin_0,
                                              rc_0);
        partialProofData.output = { value: [], alignment: [] };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      sign: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`sign: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const secretKey_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('sign',
                                     'argument 1 (as invoked from Typescript)',
                                     'zswap.compact line 106 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(typeof(secretKey_0) === 'object' && secretKey_0.bytes.buffer instanceof ArrayBuffer && secretKey_0.bytes.BYTES_PER_ELEMENT === 1 && secretKey_0.bytes.length === 32)) {
          __compactRuntime.typeError('sign',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'zswap.compact line 106 char 1',
                                     'struct ZswapCoinSecretKey<bytes: Bytes<32>>',
                                     secretKey_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_10.toValue(secretKey_0),
            alignment: _descriptor_10.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._sign_0(context,
                                            partialProofData,
                                            secretKey_0);
        partialProofData.output = { value: [], alignment: [] };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      }
    };
    this.impureCircuits = {
      spend: this.circuits.spend,
      output: this.circuits.output,
      sign: this.circuits.sign
    };
    this.provableCircuits = {
      spend: this.circuits.spend,
      output: this.circuits.output,
      sign: this.circuits.sign
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
    stateValue_0 = stateValue_0.arrayPush(__compactRuntime.StateValue.newNull());
    stateValue_0 = stateValue_0.arrayPush(__compactRuntime.StateValue.newNull());
    stateValue_0 = stateValue_0.arrayPush(__compactRuntime.StateValue.newNull());
    stateValue_0 = stateValue_0.arrayPush(__compactRuntime.StateValue.newNull());
    stateValue_0 = stateValue_0.arrayPush(__compactRuntime.StateValue.newNull());
    state_0.data = new __compactRuntime.ChargedState(stateValue_0);
    state_0.setOperation('spend', new __compactRuntime.ContractOperation());
    state_0.setOperation('output', new __compactRuntime.ContractOperation());
    state_0.setOperation('sign', new __compactRuntime.ContractOperation());
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
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(0n),
                                                                                              alignment: _descriptor_24.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newArray()
                                                          .arrayPush(__compactRuntime.StateValue.newBoundedMerkleTree(
                                                                       new __compactRuntime.StateBoundedMerkleTree(32)
                                                                     )).arrayPush(__compactRuntime.StateValue.newCell({ value: _descriptor_22.toValue(0n),
                                                                                                                        alignment: _descriptor_22.alignment() })).arrayPush(__compactRuntime.StateValue.newMap(
                                                                                                                                                                              new __compactRuntime.StateMap()
                                                                                                                                                                            ))
                                                          .encode() } },
                                       { idx: { cached: false,
                                                pushPath: true,
                                                path: [
                                                       { tag: 'value',
                                                         value: { value: _descriptor_24.toValue(2n),
                                                                  alignment: _descriptor_24.alignment() } }] } },
                                       { dup: { n: 2 } },
                                       { idx: { cached: false,
                                                pushPath: false,
                                                path: [
                                                       { tag: 'value',
                                                         value: { value: _descriptor_24.toValue(0n),
                                                                  alignment: _descriptor_24.alignment() } }] } },
                                       'root',
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newNull().encode() } },
                                       { ins: { cached: true, n: 2 } },
                                       { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(1n),
                                                                                              alignment: _descriptor_24.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newMap(
                                                          new __compactRuntime.StateMap()
                                                        ).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(2n),
                                                                                              alignment: _descriptor_24.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(({x: 0n, y: 1n})),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(3n),
                                                                                              alignment: _descriptor_24.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_1.toValue({ bytes: new Uint8Array(32) }),
                                                                                              alignment: _descriptor_1.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(4n),
                                                                                              alignment: _descriptor_24.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_5.toValue({ bytes: new Uint8Array(32) }),
                                                                                              alignment: _descriptor_5.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(5n),
                                                                                              alignment: _descriptor_24.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_3.toValue(0n),
                                                                                              alignment: _descriptor_3.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    state_0.data = new __compactRuntime.ChargedState(context.callContext.currentQueryContext.state.state);
    return {
      currentContractState: state_0,
      currentPrivateState: context.callContext.currentPrivateState,
      currentZswapLocalState: context.callContext.currentZswapLocalState
    }
  }
  _merkleTreePathRootNoLeafHash_0(path_0) {
    return { field:
               this._folder_0((...args_0) =>
                                this._merkleTreePathEntryRoot_0(...args_0),
                              this._degradeToTransient_0(path_0.leaf),
                              path_0.path) };
  }
  _merkleTreePathEntryRoot_0(recursiveDigest_0, entry_0) {
    const left_0 = entry_0.goes_left ? recursiveDigest_0 : entry_0.sibling.field;
    const right_0 = entry_0.goes_left ?
                    entry_0.sibling.field :
                    recursiveDigest_0;
    return this._transientHash_0([left_0, right_0]);
  }
  _transientHash_0(value_0) {
    const result_0 = __compactRuntime.transientHash(_descriptor_20, value_0);
    return result_0;
  }
  _persistentHash_0(value_0) {
    const result_0 = __compactRuntime.persistentHash(_descriptor_21, value_0);
    return result_0;
  }
  _persistentHash_1(value_0) {
    const result_0 = __compactRuntime.persistentHash(_descriptor_19, value_0);
    return result_0;
  }
  _degradeToTransient_0(x_0) {
    const result_0 = __compactRuntime.degradeToTransient(x_0);
    return result_0;
  }
  _ecAdd_0(a_0, b_0) {
    const result_0 = __compactRuntime.ecAdd(a_0, b_0);
    return result_0;
  }
  _ecMul_0(a_0, b_0) {
    const result_0 = __compactRuntime.ecMul(a_0, b_0);
    return result_0;
  }
  _ecMulGenerator_0(b_0) {
    const result_0 = __compactRuntime.ecMulGenerator(b_0);
    return result_0;
  }
  _hashToCurve_0(value_0) {
    const result_0 = __compactRuntime.hashToCurve(_descriptor_17, value_0);
    return result_0;
  }
  async _spend_0(context, partialProofData, sk_0, path_0, coin_0, rc_0) {
    const tmp_0 = this._merkleTreePathRootNoLeafHash_0(path_0);
    _descriptor_4.fromValue(__compactRuntime.queryLedgerState(context,
                                                              partialProofData,
                                                              [
                                                               { dup: { n: 0 } },
                                                               { idx: { cached: false,
                                                                        pushPath: false,
                                                                        path: [
                                                                               { tag: 'value',
                                                                                 value: { value: _descriptor_24.toValue(0n),
                                                                                          alignment: _descriptor_24.alignment() } }] } },
                                                               { idx: { cached: false,
                                                                        pushPath: false,
                                                                        path: [
                                                                               { tag: 'value',
                                                                                 value: { value: _descriptor_24.toValue(2n),
                                                                                          alignment: _descriptor_24.alignment() } }] } },
                                                               { push: { storage: false,
                                                                         value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(tmp_0),
                                                                                                                      alignment: _descriptor_11.alignment() }).encode() } },
                                                               'member',
                                                               { popeq: { cached: true,
                                                                          result: undefined } }]).value);
    const pk_0 = this._derivePublicKey_0(sk_0.left);
    const coinCom_0 = this._persistentHash_0({ sep:
                                                 new Uint8Array([109, 105, 100, 110, 105, 103, 104, 116, 58, 122, 115, 119, 97, 112, 45, 99, 99, 91, 118, 49, 93]),
                                               info: coin_0,
                                               dataType: sk_0.is_left,
                                               data:
                                                 sk_0.is_left ?
                                                 pk_0.bytes :
                                                 sk_0.right.bytes });
    __compactRuntime.assert(this._equal_0(coinCom_0, path_0.leaf),
                            'Path must be to coin commitment');
    const nul_0 = this._persistentHash_0({ sep:
                                             new Uint8Array([109, 105, 100, 110, 105, 103, 104, 116, 58, 122, 115, 119, 97, 112, 45, 99, 110, 91, 118, 49, 93]),
                                           info: coin_0,
                                           dataType: sk_0.is_left,
                                           data:
                                             sk_0.is_left ?
                                             sk_0.left.bytes :
                                             sk_0.right.bytes });
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { idx: { cached: false,
                                                pushPath: true,
                                                path: [
                                                       { tag: 'value',
                                                         value: { value: _descriptor_24.toValue(1n),
                                                                  alignment: _descriptor_24.alignment() } }] } },
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_0.toValue(nul_0),
                                                                                              alignment: _descriptor_0.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newNull().encode() } },
                                       { ins: { cached: false, n: 1 } },
                                       { ins: { cached: true, n: 1 } }]);
    if (!sk_0.is_left) {
      const tmp_1 = sk_0.right;
      __compactRuntime.queryLedgerState(context,
                                        partialProofData,
                                        [
                                         { push: { storage: false,
                                                   value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(3n),
                                                                                                alignment: _descriptor_24.alignment() }).encode() } },
                                         { push: { storage: true,
                                                   value: __compactRuntime.StateValue.newCell({ value: _descriptor_1.toValue(tmp_1),
                                                                                                alignment: _descriptor_1.alignment() }).encode() } },
                                         { ins: { cached: false, n: 1 } }]);
    }
    const colorBase_0 = this._hashToCurve_0([coin_0.color,
                                             _descriptor_3.fromValue(__compactRuntime.queryLedgerState(context,
                                                                                                       partialProofData,
                                                                                                       [
                                                                                                        { dup: { n: 0 } },
                                                                                                        { idx: { cached: false,
                                                                                                                 pushPath: false,
                                                                                                                 path: [
                                                                                                                        { tag: 'value',
                                                                                                                          value: { value: _descriptor_24.toValue(5n),
                                                                                                                                   alignment: _descriptor_24.alignment() } }] } },
                                                                                                        { popeq: { cached: false,
                                                                                                                   result: undefined } }]).value)]);
    const pedersenBlinding_0 = this._ecMulGenerator_0(rc_0);
    const pedersenCommit_0 = this._ecMul_0(colorBase_0, coin_0.value);
    const tmp_2 = this._ecAdd_0(pedersenBlinding_0, pedersenCommit_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(2n),
                                                                                              alignment: _descriptor_24.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(tmp_2),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return [];
  }
  _derivePublicKey_0(secretKey_0) {
    return { bytes:
               this._persistentHash_1({ sep:
                                          new Uint8Array([109, 105, 100, 110, 105, 103, 104, 116, 58, 122, 115, 119, 97, 112, 45, 112, 107, 91, 118, 49, 93]),
                                        secretKey: secretKey_0 }) };
  }
  async _output_0(context, partialProofData, pk_0, coin_0, rc_0) {
    const coinCom_0 = this._persistentHash_0({ sep:
                                                 new Uint8Array([109, 105, 100, 110, 105, 103, 104, 116, 58, 122, 115, 119, 97, 112, 45, 99, 99, 91, 118, 49, 93]),
                                               info: coin_0,
                                               dataType: pk_0.is_left,
                                               data:
                                                 pk_0.is_left ?
                                                 pk_0.left.bytes :
                                                 pk_0.right.bytes });
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { idx: { cached: false,
                                                pushPath: true,
                                                path: [
                                                       { tag: 'value',
                                                         value: { value: _descriptor_24.toValue(0n),
                                                                  alignment: _descriptor_24.alignment() } }] } },
                                       { idx: { cached: false,
                                                pushPath: true,
                                                path: [
                                                       { tag: 'value',
                                                         value: { value: _descriptor_24.toValue(0n),
                                                                  alignment: _descriptor_24.alignment() } }] } },
                                       { dup: { n: 2 } },
                                       { idx: { cached: false,
                                                pushPath: false,
                                                path: [
                                                       { tag: 'value',
                                                         value: { value: _descriptor_24.toValue(1n),
                                                                  alignment: _descriptor_24.alignment() } }] } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_0.toValue(coinCom_0),
                                                                                              alignment: _descriptor_0.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } },
                                       { ins: { cached: true, n: 1 } },
                                       { idx: { cached: false,
                                                pushPath: true,
                                                path: [
                                                       { tag: 'value',
                                                         value: { value: _descriptor_24.toValue(1n),
                                                                  alignment: _descriptor_24.alignment() } }] } },
                                       { addi: { immediate: 1 } },
                                       { ins: { cached: true, n: 1 } },
                                       { idx: { cached: false,
                                                pushPath: true,
                                                path: [
                                                       { tag: 'value',
                                                         value: { value: _descriptor_24.toValue(2n),
                                                                  alignment: _descriptor_24.alignment() } }] } },
                                       { dup: { n: 2 } },
                                       { idx: { cached: false,
                                                pushPath: false,
                                                path: [
                                                       { tag: 'value',
                                                         value: { value: _descriptor_24.toValue(0n),
                                                                  alignment: _descriptor_24.alignment() } }] } },
                                       'root',
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newNull().encode() } },
                                       { ins: { cached: false, n: 1 } },
                                       { ins: { cached: true, n: 2 } }]);
    if (!pk_0.is_left) {
      const tmp_0 = pk_0.right;
      __compactRuntime.queryLedgerState(context,
                                        partialProofData,
                                        [
                                         { push: { storage: false,
                                                   value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(3n),
                                                                                                alignment: _descriptor_24.alignment() }).encode() } },
                                         { push: { storage: true,
                                                   value: __compactRuntime.StateValue.newCell({ value: _descriptor_1.toValue(tmp_0),
                                                                                                alignment: _descriptor_1.alignment() }).encode() } },
                                         { ins: { cached: false, n: 1 } }]);
    }
    const colorBase_0 = this._hashToCurve_0([coin_0.color,
                                             _descriptor_3.fromValue(__compactRuntime.queryLedgerState(context,
                                                                                                       partialProofData,
                                                                                                       [
                                                                                                        { dup: { n: 0 } },
                                                                                                        { idx: { cached: false,
                                                                                                                 pushPath: false,
                                                                                                                 path: [
                                                                                                                        { tag: 'value',
                                                                                                                          value: { value: _descriptor_24.toValue(5n),
                                                                                                                                   alignment: _descriptor_24.alignment() } }] } },
                                                                                                        { popeq: { cached: false,
                                                                                                                   result: undefined } }]).value)]);
    const pedersenBlinding_0 = this._ecMulGenerator_0(rc_0);
    const pedersenCommit_0 = this._ecMul_0(colorBase_0, coin_0.value);
    const tmp_1 = this._ecAdd_0(pedersenBlinding_0, pedersenCommit_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(2n),
                                                                                              alignment: _descriptor_24.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(tmp_1),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return [];
  }
  async _sign_0(context, partialProofData, secretKey_0) {
    const tmp_0 = this._derivePublicKey_0(secretKey_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_24.toValue(4n),
                                                                                              alignment: _descriptor_24.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_5.toValue(tmp_0),
                                                                                              alignment: _descriptor_5.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return [];
  }
  _folder_0(f, x, a0) {
    for (let i = 0; i < 32; i++) { x = f(x, a0[i]); }
    return x;
  }
  _equal_0(x0, y0) {
    if (!x0.every((x, i) => y0[i] === x)) { return false; }
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
  'output': 'afc0a02f245aa4b22dcc9976970c27fa3ff8fdfe0594b7e709574695cdf2166f',
  'sign': '44a94eebb0e66bb84f8dd42541358b3de3dfba56cf005570e91039f0b019dc4d',
  'spend': '60b2c9e6b702a4594e020179c57733afab6d4f0deba408b1888c02fffea5cfd0',
};

//# sourceMappingURL=index.js.map
