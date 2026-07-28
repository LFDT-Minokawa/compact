import * as __compactRuntime from '@midnight-ntwrk/compact-runtime';
__compactRuntime.checkRuntimeVersion('0.18.0-rc.1');

const _descriptor_0 = __compactRuntime.CompactTypeField;

const _descriptor_1 = new __compactRuntime.CompactTypeVector(4, _descriptor_0);

const _descriptor_2 = new __compactRuntime.CompactTypeBytes(32);

const _descriptor_3 = new __compactRuntime.CompactTypeBytes(10);

const _descriptor_4 = new __compactRuntime.CompactTypeBytes(18);

const _descriptor_5 = new __compactRuntime.CompactTypeBytes(4);

const _descriptor_6 = new __compactRuntime.CompactTypeBytes(5);

const _descriptor_7 = new __compactRuntime.CompactTypeBytes(1);

const _descriptor_8 = new __compactRuntime.CompactTypeBytes(2);

const _descriptor_9 = new __compactRuntime.CompactTypeBytes(0);

const _descriptor_10 = __compactRuntime.CompactTypeBoolean;

const _descriptor_11 = new __compactRuntime.CompactTypeUnsignedInteger(255n, 1);

const _descriptor_12 = new __compactRuntime.CompactTypeEnum(3, 1);

class _Parcel_0 {
  alignment() {
    return _descriptor_10.alignment().concat(_descriptor_11.alignment().concat(_descriptor_12.alignment()));
  }
  fromValue(value_0) {
    return {
      a: _descriptor_10.fromValue(value_0),
      b: _descriptor_11.fromValue(value_0),
      c: _descriptor_12.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_10.toValue(value_0.a).concat(_descriptor_11.toValue(value_0.b).concat(_descriptor_12.toValue(value_0.c)));
  }
}

const _descriptor_13 = new _Parcel_0();

const _descriptor_14 = new __compactRuntime.CompactTypeVector(3, _descriptor_13);

const _descriptor_15 = new __compactRuntime.CompactTypeVector(3, _descriptor_10);

const _descriptor_16 = new __compactRuntime.CompactTypeUnsignedInteger(18446744073709551615n, 8);

const _descriptor_17 = new __compactRuntime.CompactTypeBytes(376);

const _descriptor_18 = new __compactRuntime.CompactTypeBytes(1024);

const _descriptor_19 = new __compactRuntime.CompactTypeBytes(93);

const _descriptor_20 = new __compactRuntime.CompactTypeBytes(94);

const _descriptor_21 = new __compactRuntime.CompactTypeBytes(62);

const _descriptor_22 = new __compactRuntime.CompactTypeBytes(63);

const _descriptor_23 = new __compactRuntime.CompactTypeBytes(60);

const _descriptor_24 = new __compactRuntime.CompactTypeBytes(61);

const _descriptor_25 = new __compactRuntime.CompactTypeBytes(58);

const _descriptor_26 = new __compactRuntime.CompactTypeBytes(59);

const _descriptor_27 = new __compactRuntime.CompactTypeBytes(56);

const _descriptor_28 = new __compactRuntime.CompactTypeBytes(57);

const _descriptor_29 = new __compactRuntime.CompactTypeBytes(54);

const _descriptor_30 = new __compactRuntime.CompactTypeBytes(55);

const _descriptor_31 = new __compactRuntime.CompactTypeBytes(52);

const _descriptor_32 = new __compactRuntime.CompactTypeBytes(53);

const _descriptor_33 = new __compactRuntime.CompactTypeBytes(50);

const _descriptor_34 = new __compactRuntime.CompactTypeBytes(51);

const _descriptor_35 = new __compactRuntime.CompactTypeBytes(48);

const _descriptor_36 = new __compactRuntime.CompactTypeBytes(49);

const _descriptor_37 = new __compactRuntime.CompactTypeBytes(46);

const _descriptor_38 = new __compactRuntime.CompactTypeBytes(47);

const _descriptor_39 = new __compactRuntime.CompactTypeBytes(44);

const _descriptor_40 = new __compactRuntime.CompactTypeBytes(45);

const _descriptor_41 = new __compactRuntime.CompactTypeBytes(42);

const _descriptor_42 = new __compactRuntime.CompactTypeBytes(43);

const _descriptor_43 = new __compactRuntime.CompactTypeBytes(40);

const _descriptor_44 = new __compactRuntime.CompactTypeBytes(41);

const _descriptor_45 = new __compactRuntime.CompactTypeBytes(38);

const _descriptor_46 = new __compactRuntime.CompactTypeBytes(39);

const _descriptor_47 = new __compactRuntime.CompactTypeBytes(36);

const _descriptor_48 = new __compactRuntime.CompactTypeBytes(37);

const _descriptor_49 = new __compactRuntime.CompactTypeBytes(34);

const _descriptor_50 = new __compactRuntime.CompactTypeBytes(35);

const _descriptor_51 = new __compactRuntime.CompactTypeBytes(33);

class _Triple_0 {
  alignment() {
    return _descriptor_5.alignment().concat(_descriptor_5.alignment().concat(_descriptor_5.alignment()));
  }
  fromValue(value_0) {
    return {
      a: _descriptor_5.fromValue(value_0),
      b: _descriptor_5.fromValue(value_0),
      c: _descriptor_5.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_5.toValue(value_0.a).concat(_descriptor_5.toValue(value_0.b).concat(_descriptor_5.toValue(value_0.c)));
  }
}

const _descriptor_52 = new _Triple_0();

const _descriptor_53 = new __compactRuntime.CompactTypeBytes(7);

class _Uneven_0 {
  alignment() {
    return _descriptor_7.alignment().concat(_descriptor_5.alignment().concat(_descriptor_53.alignment()));
  }
  fromValue(value_0) {
    return {
      head: _descriptor_7.fromValue(value_0),
      mid: _descriptor_5.fromValue(value_0),
      tail: _descriptor_53.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_7.toValue(value_0.head).concat(_descriptor_5.toValue(value_0.mid).concat(_descriptor_53.toValue(value_0.tail)));
  }
}

const _descriptor_54 = new _Uneven_0();

const _descriptor_55 = new __compactRuntime.CompactTypeVector(3, _descriptor_0);

const _descriptor_56 = new __compactRuntime.CompactTypeBytes(12);

class _Either_0 {
  alignment() {
    return _descriptor_10.alignment().concat(_descriptor_2.alignment().concat(_descriptor_2.alignment()));
  }
  fromValue(value_0) {
    return {
      is_left: _descriptor_10.fromValue(value_0),
      left: _descriptor_2.fromValue(value_0),
      right: _descriptor_2.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_10.toValue(value_0.is_left).concat(_descriptor_2.toValue(value_0.left).concat(_descriptor_2.toValue(value_0.right)));
  }
}

const _descriptor_57 = new _Either_0();

const _descriptor_58 = new __compactRuntime.CompactTypeUnsignedInteger(340282366920938463463374607431768211455n, 16);

class _ContractAddress_0 {
  alignment() {
    return _descriptor_2.alignment();
  }
  fromValue(value_0) {
    return {
      bytes: _descriptor_2.fromValue(value_0)
    }
  }
  toValue(value_0) {
    return _descriptor_2.toValue(value_0.bytes);
  }
}

const _descriptor_59 = new _ContractAddress_0();

const _descriptor_60 = new __compactRuntime.CompactTypeUnsignedInteger(4294967295n, 4);

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
      async hashField(context, ...args_1) {
        return { result: pureCircuits.hashField(...args_1), context };
      },
      async hashVector3(context, ...args_1) {
        return { result: pureCircuits.hashVector3(...args_1), context };
      },
      hashFieldAndStore: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashFieldAndStore: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashFieldAndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 36 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(typeof(value_0) === 'bigint' && value_0 >= 0 && value_0 <= __compactRuntime.MAX_FIELD)) {
          __compactRuntime.typeError('hashFieldAndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 36 char 1',
                                     'Field',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_0.toValue(value_0),
            alignment: _descriptor_0.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashFieldAndStore_0(context,
                                                         partialProofData,
                                                         value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashVector3AndStore: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashVector3AndStore: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashVector3AndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 42 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(Array.isArray(value_0) && value_0.length === 3 && value_0.every((t) => typeof(t) === 'bigint' && t >= 0 && t <= __compactRuntime.MAX_FIELD))) {
          __compactRuntime.typeError('hashVector3AndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 42 char 1',
                                     'Vector<3, Field>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_55.toValue(value_0),
            alignment: _descriptor_55.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashVector3AndStore_0(context,
                                                           partialProofData,
                                                           value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      async hashBytes12(context, ...args_1) {
        return { result: pureCircuits.hashBytes12(...args_1), context };
      },
      async hashTriple(context, ...args_1) {
        return { result: pureCircuits.hashTriple(...args_1), context };
      },
      async hashUneven(context, ...args_1) {
        return { result: pureCircuits.hashUneven(...args_1), context };
      },
      hashBytes: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashBytes: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashBytes',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 72 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 32)) {
          __compactRuntime.typeError('hashBytes',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 72 char 1',
                                     'Bytes<32>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_2.toValue(value_0),
            alignment: _descriptor_2.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashBytes_0(context,
                                                 partialProofData,
                                                 value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore1: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore1: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore1',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 78 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 1)) {
          __compactRuntime.typeError('hashAndStore1',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 78 char 1',
                                     'Bytes<1>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_7.toValue(value_0),
            alignment: _descriptor_7.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore1_0(context,
                                                     partialProofData,
                                                     value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore32: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore32: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore32',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 87 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 32)) {
          __compactRuntime.typeError('hashAndStore32',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 87 char 1',
                                     'Bytes<32>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_2.toValue(value_0),
            alignment: _descriptor_2.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore32_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore33: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore33: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore33',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 93 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 33)) {
          __compactRuntime.typeError('hashAndStore33',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 93 char 1',
                                     'Bytes<33>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_51.toValue(value_0),
            alignment: _descriptor_51.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore33_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore34: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore34: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore34',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 99 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 34)) {
          __compactRuntime.typeError('hashAndStore34',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 99 char 1',
                                     'Bytes<34>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_49.toValue(value_0),
            alignment: _descriptor_49.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore34_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore35: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore35: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore35',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 105 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 35)) {
          __compactRuntime.typeError('hashAndStore35',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 105 char 1',
                                     'Bytes<35>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_50.toValue(value_0),
            alignment: _descriptor_50.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore35_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore36: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore36: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore36',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 111 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 36)) {
          __compactRuntime.typeError('hashAndStore36',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 111 char 1',
                                     'Bytes<36>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_47.toValue(value_0),
            alignment: _descriptor_47.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore36_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore37: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore37: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore37',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 117 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 37)) {
          __compactRuntime.typeError('hashAndStore37',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 117 char 1',
                                     'Bytes<37>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_48.toValue(value_0),
            alignment: _descriptor_48.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore37_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore38: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore38: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore38',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 123 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 38)) {
          __compactRuntime.typeError('hashAndStore38',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 123 char 1',
                                     'Bytes<38>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_45.toValue(value_0),
            alignment: _descriptor_45.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore38_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore39: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore39: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore39',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 129 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 39)) {
          __compactRuntime.typeError('hashAndStore39',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 129 char 1',
                                     'Bytes<39>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_46.toValue(value_0),
            alignment: _descriptor_46.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore39_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore40: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore40: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore40',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 135 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 40)) {
          __compactRuntime.typeError('hashAndStore40',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 135 char 1',
                                     'Bytes<40>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_43.toValue(value_0),
            alignment: _descriptor_43.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore40_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore41: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore41: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore41',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 141 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 41)) {
          __compactRuntime.typeError('hashAndStore41',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 141 char 1',
                                     'Bytes<41>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_44.toValue(value_0),
            alignment: _descriptor_44.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore41_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore42: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore42: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore42',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 147 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 42)) {
          __compactRuntime.typeError('hashAndStore42',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 147 char 1',
                                     'Bytes<42>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_41.toValue(value_0),
            alignment: _descriptor_41.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore42_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore43: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore43: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore43',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 153 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 43)) {
          __compactRuntime.typeError('hashAndStore43',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 153 char 1',
                                     'Bytes<43>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_42.toValue(value_0),
            alignment: _descriptor_42.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore43_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore44: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore44: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore44',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 159 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 44)) {
          __compactRuntime.typeError('hashAndStore44',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 159 char 1',
                                     'Bytes<44>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_39.toValue(value_0),
            alignment: _descriptor_39.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore44_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore45: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore45: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore45',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 165 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 45)) {
          __compactRuntime.typeError('hashAndStore45',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 165 char 1',
                                     'Bytes<45>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_40.toValue(value_0),
            alignment: _descriptor_40.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore45_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore46: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore46: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore46',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 171 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 46)) {
          __compactRuntime.typeError('hashAndStore46',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 171 char 1',
                                     'Bytes<46>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_37.toValue(value_0),
            alignment: _descriptor_37.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore46_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore47: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore47: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore47',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 177 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 47)) {
          __compactRuntime.typeError('hashAndStore47',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 177 char 1',
                                     'Bytes<47>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_38.toValue(value_0),
            alignment: _descriptor_38.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore47_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore48: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore48: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore48',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 183 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 48)) {
          __compactRuntime.typeError('hashAndStore48',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 183 char 1',
                                     'Bytes<48>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_35.toValue(value_0),
            alignment: _descriptor_35.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore48_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore49: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore49: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore49',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 189 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 49)) {
          __compactRuntime.typeError('hashAndStore49',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 189 char 1',
                                     'Bytes<49>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_36.toValue(value_0),
            alignment: _descriptor_36.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore49_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore50: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore50: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore50',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 195 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 50)) {
          __compactRuntime.typeError('hashAndStore50',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 195 char 1',
                                     'Bytes<50>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_33.toValue(value_0),
            alignment: _descriptor_33.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore50_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore51: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore51: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore51',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 201 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 51)) {
          __compactRuntime.typeError('hashAndStore51',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 201 char 1',
                                     'Bytes<51>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_34.toValue(value_0),
            alignment: _descriptor_34.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore51_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore52: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore52: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore52',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 207 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 52)) {
          __compactRuntime.typeError('hashAndStore52',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 207 char 1',
                                     'Bytes<52>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_31.toValue(value_0),
            alignment: _descriptor_31.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore52_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore53: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore53: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore53',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 213 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 53)) {
          __compactRuntime.typeError('hashAndStore53',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 213 char 1',
                                     'Bytes<53>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_32.toValue(value_0),
            alignment: _descriptor_32.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore53_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore54: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore54: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore54',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 219 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 54)) {
          __compactRuntime.typeError('hashAndStore54',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 219 char 1',
                                     'Bytes<54>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_29.toValue(value_0),
            alignment: _descriptor_29.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore54_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore55: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore55: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore55',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 225 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 55)) {
          __compactRuntime.typeError('hashAndStore55',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 225 char 1',
                                     'Bytes<55>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_30.toValue(value_0),
            alignment: _descriptor_30.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore55_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore56: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore56: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore56',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 231 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 56)) {
          __compactRuntime.typeError('hashAndStore56',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 231 char 1',
                                     'Bytes<56>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_27.toValue(value_0),
            alignment: _descriptor_27.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore56_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore57: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore57: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore57',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 237 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 57)) {
          __compactRuntime.typeError('hashAndStore57',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 237 char 1',
                                     'Bytes<57>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_28.toValue(value_0),
            alignment: _descriptor_28.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore57_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore58: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore58: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore58',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 243 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 58)) {
          __compactRuntime.typeError('hashAndStore58',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 243 char 1',
                                     'Bytes<58>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_25.toValue(value_0),
            alignment: _descriptor_25.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore58_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore59: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore59: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore59',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 249 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 59)) {
          __compactRuntime.typeError('hashAndStore59',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 249 char 1',
                                     'Bytes<59>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_26.toValue(value_0),
            alignment: _descriptor_26.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore59_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore60: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore60: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore60',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 255 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 60)) {
          __compactRuntime.typeError('hashAndStore60',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 255 char 1',
                                     'Bytes<60>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_23.toValue(value_0),
            alignment: _descriptor_23.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore60_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore61: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore61: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore61',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 261 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 61)) {
          __compactRuntime.typeError('hashAndStore61',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 261 char 1',
                                     'Bytes<61>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_24.toValue(value_0),
            alignment: _descriptor_24.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore61_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore62: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore62: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore62',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 267 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 62)) {
          __compactRuntime.typeError('hashAndStore62',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 267 char 1',
                                     'Bytes<62>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_21.toValue(value_0),
            alignment: _descriptor_21.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore62_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore63: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore63: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore63',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 273 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 63)) {
          __compactRuntime.typeError('hashAndStore63',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 273 char 1',
                                     'Bytes<63>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_22.toValue(value_0),
            alignment: _descriptor_22.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore63_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore93: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore93: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore93',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 280 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 93)) {
          __compactRuntime.typeError('hashAndStore93',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 280 char 1',
                                     'Bytes<93>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_19.toValue(value_0),
            alignment: _descriptor_19.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore93_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore94: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore94: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore94',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 287 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 94)) {
          __compactRuntime.typeError('hashAndStore94',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 287 char 1',
                                     'Bytes<94>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_20.toValue(value_0),
            alignment: _descriptor_20.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore94_0(context,
                                                      partialProofData,
                                                      value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore376: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore376: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore376',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 294 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 376)) {
          __compactRuntime.typeError('hashAndStore376',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 294 char 1',
                                     'Bytes<376>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_17.toValue(value_0),
            alignment: _descriptor_17.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore376_0(context,
                                                       partialProofData,
                                                       value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore1024: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore1024: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore1024',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 302 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 1024)) {
          __compactRuntime.typeError('hashAndStore1024',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 302 char 1',
                                     'Bytes<1024>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_18.toValue(value_0),
            alignment: _descriptor_18.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore1024_0(context,
                                                        partialProofData,
                                                        value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      async hashBytes32(context, ...args_1) {
        return { result: pureCircuits.hashBytes32(...args_1), context };
      },
      async hashBytes33(context, ...args_1) {
        return { result: pureCircuits.hashBytes33(...args_1), context };
      },
      async hashBytes34(context, ...args_1) {
        return { result: pureCircuits.hashBytes34(...args_1), context };
      },
      async hashBytes35(context, ...args_1) {
        return { result: pureCircuits.hashBytes35(...args_1), context };
      },
      async hashBytes36(context, ...args_1) {
        return { result: pureCircuits.hashBytes36(...args_1), context };
      },
      async hashBytes37(context, ...args_1) {
        return { result: pureCircuits.hashBytes37(...args_1), context };
      },
      async hashBytes38(context, ...args_1) {
        return { result: pureCircuits.hashBytes38(...args_1), context };
      },
      async hashBytes39(context, ...args_1) {
        return { result: pureCircuits.hashBytes39(...args_1), context };
      },
      async hashBytes40(context, ...args_1) {
        return { result: pureCircuits.hashBytes40(...args_1), context };
      },
      async hashBytes41(context, ...args_1) {
        return { result: pureCircuits.hashBytes41(...args_1), context };
      },
      async hashBytes42(context, ...args_1) {
        return { result: pureCircuits.hashBytes42(...args_1), context };
      },
      async hashBytes43(context, ...args_1) {
        return { result: pureCircuits.hashBytes43(...args_1), context };
      },
      async hashBytes44(context, ...args_1) {
        return { result: pureCircuits.hashBytes44(...args_1), context };
      },
      async hashBytes45(context, ...args_1) {
        return { result: pureCircuits.hashBytes45(...args_1), context };
      },
      async hashBytes46(context, ...args_1) {
        return { result: pureCircuits.hashBytes46(...args_1), context };
      },
      async hashBytes47(context, ...args_1) {
        return { result: pureCircuits.hashBytes47(...args_1), context };
      },
      async hashBytes48(context, ...args_1) {
        return { result: pureCircuits.hashBytes48(...args_1), context };
      },
      async hashBytes49(context, ...args_1) {
        return { result: pureCircuits.hashBytes49(...args_1), context };
      },
      async hashBytes50(context, ...args_1) {
        return { result: pureCircuits.hashBytes50(...args_1), context };
      },
      async hashBytes51(context, ...args_1) {
        return { result: pureCircuits.hashBytes51(...args_1), context };
      },
      async hashBytes52(context, ...args_1) {
        return { result: pureCircuits.hashBytes52(...args_1), context };
      },
      async hashBytes53(context, ...args_1) {
        return { result: pureCircuits.hashBytes53(...args_1), context };
      },
      async hashBytes54(context, ...args_1) {
        return { result: pureCircuits.hashBytes54(...args_1), context };
      },
      async hashBytes55(context, ...args_1) {
        return { result: pureCircuits.hashBytes55(...args_1), context };
      },
      async hashBytes56(context, ...args_1) {
        return { result: pureCircuits.hashBytes56(...args_1), context };
      },
      async hashBytes57(context, ...args_1) {
        return { result: pureCircuits.hashBytes57(...args_1), context };
      },
      async hashBytes58(context, ...args_1) {
        return { result: pureCircuits.hashBytes58(...args_1), context };
      },
      async hashBytes59(context, ...args_1) {
        return { result: pureCircuits.hashBytes59(...args_1), context };
      },
      async hashBytes60(context, ...args_1) {
        return { result: pureCircuits.hashBytes60(...args_1), context };
      },
      async hashBytes61(context, ...args_1) {
        return { result: pureCircuits.hashBytes61(...args_1), context };
      },
      async hashBytes62(context, ...args_1) {
        return { result: pureCircuits.hashBytes62(...args_1), context };
      },
      async hashBytes63(context, ...args_1) {
        return { result: pureCircuits.hashBytes63(...args_1), context };
      },
      async hashBytes93(context, ...args_1) {
        return { result: pureCircuits.hashBytes93(...args_1), context };
      },
      async hashBytes94(context, ...args_1) {
        return { result: pureCircuits.hashBytes94(...args_1), context };
      },
      async hashBytes376(context, ...args_1) {
        return { result: pureCircuits.hashBytes376(...args_1), context };
      },
      async hashBytes1024(context, ...args_1) {
        return { result: pureCircuits.hashBytes1024(...args_1), context };
      },
      async hashBool(context, ...args_1) {
        return { result: pureCircuits.hashBool(...args_1), context };
      },
      async hashUint(context, ...args_1) {
        return { result: pureCircuits.hashUint(...args_1), context };
      },
      async hashVecBool(context, ...args_1) {
        return { result: pureCircuits.hashVecBool(...args_1), context };
      },
      async hashEnum(context, ...args_1) {
        return { result: pureCircuits.hashEnum(...args_1), context };
      },
      async hashStruct(context, ...args_1) {
        return { result: pureCircuits.hashStruct(...args_1), context };
      },
      async hashVecStruct(context, ...args_1) {
        return { result: pureCircuits.hashVecStruct(...args_1), context };
      },
      hashBoolAndStore: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashBoolAndStore: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const x_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashBoolAndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 552 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(typeof(x_0) === 'boolean')) {
          __compactRuntime.typeError('hashBoolAndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 552 char 1',
                                     'Boolean',
                                     x_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_10.toValue(x_0),
            alignment: _descriptor_10.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashBoolAndStore_0(context,
                                                        partialProofData,
                                                        x_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashUintAndStore: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashUintAndStore: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const x_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashUintAndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 558 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(typeof(x_0) === 'bigint' && x_0 >= 0n && x_0 <= 18446744073709551615n)) {
          __compactRuntime.typeError('hashUintAndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 558 char 1',
                                     'Uint<0..18446744073709551616>',
                                     x_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_16.toValue(x_0),
            alignment: _descriptor_16.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashUintAndStore_0(context,
                                                        partialProofData,
                                                        x_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashVecBoolAndStore: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashVecBoolAndStore: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const x_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashVecBoolAndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 564 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(Array.isArray(x_0) && x_0.length === 3 && x_0.every((t) => typeof(t) === 'boolean'))) {
          __compactRuntime.typeError('hashVecBoolAndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 564 char 1',
                                     'Vector<3, Boolean>',
                                     x_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_15.toValue(x_0),
            alignment: _descriptor_15.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashVecBoolAndStore_0(context,
                                                           partialProofData,
                                                           x_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashEnumAndStore: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashEnumAndStore: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const x_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashEnumAndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 570 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(typeof(x_0) === 'number' && x_0 >= 0 && x_0 <= 3)) {
          __compactRuntime.typeError('hashEnumAndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 570 char 1',
                                     'Enum<Direction, North, East, South, West>',
                                     x_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_12.toValue(x_0),
            alignment: _descriptor_12.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashEnumAndStore_0(context,
                                                        partialProofData,
                                                        x_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashStructAndStore: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashStructAndStore: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const x_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashStructAndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 576 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(typeof(x_0) === 'object' && typeof(x_0.a) === 'boolean' && typeof(x_0.b) === 'bigint' && x_0.b >= 0n && x_0.b <= 255n && typeof(x_0.c) === 'number' && x_0.c >= 0 && x_0.c <= 3)) {
          __compactRuntime.typeError('hashStructAndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 576 char 1',
                                     'struct Parcel<a: Boolean, b: Uint<0..256>, c: Enum<Direction, North, East, South, West>>',
                                     x_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_13.toValue(x_0),
            alignment: _descriptor_13.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashStructAndStore_0(context,
                                                          partialProofData,
                                                          x_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashVecStructAndStore: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashVecStructAndStore: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const x_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashVecStructAndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 582 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(Array.isArray(x_0) && x_0.length === 3 && x_0.every((t) => typeof(t) === 'object' && typeof(t.a) === 'boolean' && typeof(t.b) === 'bigint' && t.b >= 0n && t.b <= 255n && typeof(t.c) === 'number' && t.c >= 0 && t.c <= 3))) {
          __compactRuntime.typeError('hashVecStructAndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 582 char 1',
                                     'Vector<3, struct Parcel<a: Boolean, b: Uint<0..256>, c: Enum<Direction, North, East, South, West>>>',
                                     x_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_14.toValue(x_0),
            alignment: _descriptor_14.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashVecStructAndStore_0(context,
                                                             partialProofData,
                                                             x_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      hashAndStore: async (...args_1) => {
        if (args_1.length !== 2) {
          throw new __compactRuntime.CompactError(`hashAndStore: expected 2 arguments (as invoked from Typescript), received ${args_1.length}`);
        }
        const contextOrig_0 = args_1[0];
        const value_0 = args_1[1];
        if (!(typeof(contextOrig_0) === 'object' && contextOrig_0.callContext.currentQueryContext != undefined)) {
          __compactRuntime.typeError('hashAndStore',
                                     'argument 1 (as invoked from Typescript)',
                                     'keccak.compact line 588 char 1',
                                     'CircuitContext',
                                     contextOrig_0)
        }
        if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 32)) {
          __compactRuntime.typeError('hashAndStore',
                                     'argument 1 (argument 2 as invoked from Typescript)',
                                     'keccak.compact line 588 char 1',
                                     'Bytes<32>',
                                     value_0)
        }
        const context = __compactRuntime.copyCircuitContext(contextOrig_0);
        const partialProofData = {
          input: {
            value: _descriptor_2.toValue(value_0),
            alignment: _descriptor_2.alignment()
          },
          output: undefined,
          publicTranscript: [],
          privateTranscriptOutputs: []
        };
        const result_0 = await this._hashAndStore_0(context,
                                                    partialProofData,
                                                    value_0);
        partialProofData.output = { value: _descriptor_2.toValue(result_0), alignment: _descriptor_2.alignment() };
        __compactRuntime.finalizeCallProofData(context, partialProofData);
        return { result: result_0, context: context, gasCost: context.callContext.currentGasCost };
      },
      async hashBytes0(context, ...args_1) {
        return { result: pureCircuits.hashBytes0(...args_1), context };
      },
      async hashBytes1(context, ...args_1) {
        return { result: pureCircuits.hashBytes1(...args_1), context };
      },
      async hashBytes2(context, ...args_1) {
        return { result: pureCircuits.hashBytes2(...args_1), context };
      },
      async hashBytes4(context, ...args_1) {
        return { result: pureCircuits.hashBytes4(...args_1), context };
      },
      async hashBytes5(context, ...args_1) {
        return { result: pureCircuits.hashBytes5(...args_1), context };
      },
      async hashBytes10(context, ...args_1) {
        return { result: pureCircuits.hashBytes10(...args_1), context };
      },
      async hashBytes18(context, ...args_1) {
        return { result: pureCircuits.hashBytes18(...args_1), context };
      },
      async hashVector(context, ...args_1) {
        return { result: pureCircuits.hashVector(...args_1), context };
      }
    };
    this.impureCircuits = {
      hashFieldAndStore: this.circuits.hashFieldAndStore,
      hashVector3AndStore: this.circuits.hashVector3AndStore,
      hashBytes: this.circuits.hashBytes,
      hashAndStore1: this.circuits.hashAndStore1,
      hashAndStore32: this.circuits.hashAndStore32,
      hashAndStore33: this.circuits.hashAndStore33,
      hashAndStore34: this.circuits.hashAndStore34,
      hashAndStore35: this.circuits.hashAndStore35,
      hashAndStore36: this.circuits.hashAndStore36,
      hashAndStore37: this.circuits.hashAndStore37,
      hashAndStore38: this.circuits.hashAndStore38,
      hashAndStore39: this.circuits.hashAndStore39,
      hashAndStore40: this.circuits.hashAndStore40,
      hashAndStore41: this.circuits.hashAndStore41,
      hashAndStore42: this.circuits.hashAndStore42,
      hashAndStore43: this.circuits.hashAndStore43,
      hashAndStore44: this.circuits.hashAndStore44,
      hashAndStore45: this.circuits.hashAndStore45,
      hashAndStore46: this.circuits.hashAndStore46,
      hashAndStore47: this.circuits.hashAndStore47,
      hashAndStore48: this.circuits.hashAndStore48,
      hashAndStore49: this.circuits.hashAndStore49,
      hashAndStore50: this.circuits.hashAndStore50,
      hashAndStore51: this.circuits.hashAndStore51,
      hashAndStore52: this.circuits.hashAndStore52,
      hashAndStore53: this.circuits.hashAndStore53,
      hashAndStore54: this.circuits.hashAndStore54,
      hashAndStore55: this.circuits.hashAndStore55,
      hashAndStore56: this.circuits.hashAndStore56,
      hashAndStore57: this.circuits.hashAndStore57,
      hashAndStore58: this.circuits.hashAndStore58,
      hashAndStore59: this.circuits.hashAndStore59,
      hashAndStore60: this.circuits.hashAndStore60,
      hashAndStore61: this.circuits.hashAndStore61,
      hashAndStore62: this.circuits.hashAndStore62,
      hashAndStore63: this.circuits.hashAndStore63,
      hashAndStore93: this.circuits.hashAndStore93,
      hashAndStore94: this.circuits.hashAndStore94,
      hashAndStore376: this.circuits.hashAndStore376,
      hashAndStore1024: this.circuits.hashAndStore1024,
      hashBoolAndStore: this.circuits.hashBoolAndStore,
      hashUintAndStore: this.circuits.hashUintAndStore,
      hashVecBoolAndStore: this.circuits.hashVecBoolAndStore,
      hashEnumAndStore: this.circuits.hashEnumAndStore,
      hashStructAndStore: this.circuits.hashStructAndStore,
      hashVecStructAndStore: this.circuits.hashVecStructAndStore,
      hashAndStore: this.circuits.hashAndStore
    };
    this.provableCircuits = {
      hashFieldAndStore: this.circuits.hashFieldAndStore,
      hashVector3AndStore: this.circuits.hashVector3AndStore,
      hashBytes: this.circuits.hashBytes,
      hashAndStore1: this.circuits.hashAndStore1,
      hashAndStore32: this.circuits.hashAndStore32,
      hashAndStore33: this.circuits.hashAndStore33,
      hashAndStore34: this.circuits.hashAndStore34,
      hashAndStore35: this.circuits.hashAndStore35,
      hashAndStore36: this.circuits.hashAndStore36,
      hashAndStore37: this.circuits.hashAndStore37,
      hashAndStore38: this.circuits.hashAndStore38,
      hashAndStore39: this.circuits.hashAndStore39,
      hashAndStore40: this.circuits.hashAndStore40,
      hashAndStore41: this.circuits.hashAndStore41,
      hashAndStore42: this.circuits.hashAndStore42,
      hashAndStore43: this.circuits.hashAndStore43,
      hashAndStore44: this.circuits.hashAndStore44,
      hashAndStore45: this.circuits.hashAndStore45,
      hashAndStore46: this.circuits.hashAndStore46,
      hashAndStore47: this.circuits.hashAndStore47,
      hashAndStore48: this.circuits.hashAndStore48,
      hashAndStore49: this.circuits.hashAndStore49,
      hashAndStore50: this.circuits.hashAndStore50,
      hashAndStore51: this.circuits.hashAndStore51,
      hashAndStore52: this.circuits.hashAndStore52,
      hashAndStore53: this.circuits.hashAndStore53,
      hashAndStore54: this.circuits.hashAndStore54,
      hashAndStore55: this.circuits.hashAndStore55,
      hashAndStore56: this.circuits.hashAndStore56,
      hashAndStore57: this.circuits.hashAndStore57,
      hashAndStore58: this.circuits.hashAndStore58,
      hashAndStore59: this.circuits.hashAndStore59,
      hashAndStore60: this.circuits.hashAndStore60,
      hashAndStore61: this.circuits.hashAndStore61,
      hashAndStore62: this.circuits.hashAndStore62,
      hashAndStore63: this.circuits.hashAndStore63,
      hashAndStore93: this.circuits.hashAndStore93,
      hashAndStore94: this.circuits.hashAndStore94,
      hashAndStore376: this.circuits.hashAndStore376,
      hashAndStore1024: this.circuits.hashAndStore1024,
      hashBoolAndStore: this.circuits.hashBoolAndStore,
      hashUintAndStore: this.circuits.hashUintAndStore,
      hashVecBoolAndStore: this.circuits.hashVecBoolAndStore,
      hashEnumAndStore: this.circuits.hashEnumAndStore,
      hashStructAndStore: this.circuits.hashStructAndStore,
      hashVecStructAndStore: this.circuits.hashVecStructAndStore,
      hashAndStore: this.circuits.hashAndStore
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
    state_0.data = new __compactRuntime.ChargedState(stateValue_0);
    state_0.setOperation('hashFieldAndStore', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashVector3AndStore', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashBytes', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore1', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore32', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore33', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore34', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore35', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore36', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore37', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore38', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore39', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore40', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore41', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore42', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore43', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore44', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore45', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore46', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore47', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore48', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore49', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore50', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore51', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore52', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore53', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore54', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore55', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore56', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore57', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore58', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore59', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore60', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore61', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore62', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore63', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore93', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore94', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore376', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore1024', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashBoolAndStore', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashUintAndStore', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashVecBoolAndStore', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashEnumAndStore', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashStructAndStore', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashVecStructAndStore', new __compactRuntime.ContractOperation());
    state_0.setOperation('hashAndStore', new __compactRuntime.ContractOperation());
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
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(new Uint8Array(32)),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(1n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_10.toValue(false),
                                                                                              alignment: _descriptor_10.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    const tmp_0 = new Uint8Array(32);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(tmp_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(1n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_10.toValue(false),
                                                                                              alignment: _descriptor_10.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    state_0.data = new __compactRuntime.ChargedState(context.callContext.currentQueryContext.state.state);
    return {
      currentContractState: state_0,
      currentPrivateState: context.callContext.currentPrivateState,
      currentZswapLocalState: context.callContext.currentZswapLocalState
    }
  }
  _keccak256_0(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_0, value_0);
    return result_0;
  }
  _keccak256_1(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_55, value_0);
    return result_0;
  }
  _keccak256_2(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_56, value_0);
    return result_0;
  }
  _keccak256_3(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_52, value_0);
    return result_0;
  }
  _keccak256_4(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_54, value_0);
    return result_0;
  }
  _keccak256_5(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_51, value_0);
    return result_0;
  }
  _keccak256_6(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_49, value_0);
    return result_0;
  }
  _keccak256_7(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_50, value_0);
    return result_0;
  }
  _keccak256_8(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_47, value_0);
    return result_0;
  }
  _keccak256_9(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_48, value_0);
    return result_0;
  }
  _keccak256_10(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_45, value_0);
    return result_0;
  }
  _keccak256_11(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_46, value_0);
    return result_0;
  }
  _keccak256_12(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_43, value_0);
    return result_0;
  }
  _keccak256_13(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_44, value_0);
    return result_0;
  }
  _keccak256_14(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_41, value_0);
    return result_0;
  }
  _keccak256_15(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_42, value_0);
    return result_0;
  }
  _keccak256_16(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_39, value_0);
    return result_0;
  }
  _keccak256_17(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_40, value_0);
    return result_0;
  }
  _keccak256_18(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_37, value_0);
    return result_0;
  }
  _keccak256_19(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_38, value_0);
    return result_0;
  }
  _keccak256_20(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_35, value_0);
    return result_0;
  }
  _keccak256_21(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_36, value_0);
    return result_0;
  }
  _keccak256_22(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_33, value_0);
    return result_0;
  }
  _keccak256_23(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_34, value_0);
    return result_0;
  }
  _keccak256_24(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_31, value_0);
    return result_0;
  }
  _keccak256_25(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_32, value_0);
    return result_0;
  }
  _keccak256_26(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_29, value_0);
    return result_0;
  }
  _keccak256_27(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_30, value_0);
    return result_0;
  }
  _keccak256_28(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_27, value_0);
    return result_0;
  }
  _keccak256_29(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_28, value_0);
    return result_0;
  }
  _keccak256_30(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_25, value_0);
    return result_0;
  }
  _keccak256_31(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_26, value_0);
    return result_0;
  }
  _keccak256_32(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_23, value_0);
    return result_0;
  }
  _keccak256_33(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_24, value_0);
    return result_0;
  }
  _keccak256_34(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_21, value_0);
    return result_0;
  }
  _keccak256_35(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_22, value_0);
    return result_0;
  }
  _keccak256_36(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_19, value_0);
    return result_0;
  }
  _keccak256_37(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_20, value_0);
    return result_0;
  }
  _keccak256_38(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_17, value_0);
    return result_0;
  }
  _keccak256_39(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_18, value_0);
    return result_0;
  }
  _keccak256_40(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_10, value_0);
    return result_0;
  }
  _keccak256_41(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_16, value_0);
    return result_0;
  }
  _keccak256_42(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_15, value_0);
    return result_0;
  }
  _keccak256_43(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_12, value_0);
    return result_0;
  }
  _keccak256_44(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_13, value_0);
    return result_0;
  }
  _keccak256_45(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_14, value_0);
    return result_0;
  }
  _keccak256_46(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_2, value_0);
    return result_0;
  }
  _keccak256_47(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_9, value_0);
    return result_0;
  }
  _keccak256_48(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_7, value_0);
    return result_0;
  }
  _keccak256_49(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_8, value_0);
    return result_0;
  }
  _keccak256_50(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_5, value_0);
    return result_0;
  }
  _keccak256_51(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_6, value_0);
    return result_0;
  }
  _keccak256_52(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_3, value_0);
    return result_0;
  }
  _keccak256_53(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_4, value_0);
    return result_0;
  }
  _keccak256_54(value_0) {
    const result_0 = __compactRuntime.keccak256(_descriptor_1, value_0);
    return result_0;
  }
  _hashField_0(value_0) { return this._keccak256_0(value_0); }
  _hashVector3_0(value_0) { return this._keccak256_1(value_0); }
  async _hashFieldAndStore_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_0(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashVector3AndStore_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_1(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  _hashBytes12_0(x_0) { return this._keccak256_2(x_0); }
  _hashTriple_0(t_0) { return this._keccak256_3(t_0); }
  _hashUneven_0(u_0) { return this._keccak256_4(u_0); }
  async _hashBytes_0(context, partialProofData, value_0) {
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(1n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_10.toValue(true),
                                                                                              alignment: _descriptor_10.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return this._keccak256_46(value_0);
  }
  async _hashAndStore1_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_48(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore32_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_46(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore33_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_5(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore34_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_6(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore35_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_7(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore36_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_8(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore37_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_9(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore38_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_10(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore39_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_11(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore40_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_12(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore41_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_13(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore42_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_14(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore43_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_15(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore44_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_16(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore45_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_17(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore46_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_18(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore47_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_19(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore48_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_20(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore49_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_21(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore50_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_22(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore51_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_23(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore52_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_24(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore53_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_25(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore54_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_26(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore55_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_27(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore56_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_28(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore57_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_29(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore58_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_30(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore59_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_31(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore60_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_32(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore61_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_33(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore62_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_34(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore63_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_35(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore93_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_36(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore94_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_37(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore376_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_38(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore1024_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_39(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  _hashBytes32_0(value_0) { return this._keccak256_46(value_0); }
  _hashBytes33_0(value_0) { return this._keccak256_5(value_0); }
  _hashBytes34_0(value_0) { return this._keccak256_6(value_0); }
  _hashBytes35_0(value_0) { return this._keccak256_7(value_0); }
  _hashBytes36_0(value_0) { return this._keccak256_8(value_0); }
  _hashBytes37_0(value_0) { return this._keccak256_9(value_0); }
  _hashBytes38_0(value_0) { return this._keccak256_10(value_0); }
  _hashBytes39_0(value_0) { return this._keccak256_11(value_0); }
  _hashBytes40_0(value_0) { return this._keccak256_12(value_0); }
  _hashBytes41_0(value_0) { return this._keccak256_13(value_0); }
  _hashBytes42_0(value_0) { return this._keccak256_14(value_0); }
  _hashBytes43_0(value_0) { return this._keccak256_15(value_0); }
  _hashBytes44_0(value_0) { return this._keccak256_16(value_0); }
  _hashBytes45_0(value_0) { return this._keccak256_17(value_0); }
  _hashBytes46_0(value_0) { return this._keccak256_18(value_0); }
  _hashBytes47_0(value_0) { return this._keccak256_19(value_0); }
  _hashBytes48_0(value_0) { return this._keccak256_20(value_0); }
  _hashBytes49_0(value_0) { return this._keccak256_21(value_0); }
  _hashBytes50_0(value_0) { return this._keccak256_22(value_0); }
  _hashBytes51_0(value_0) { return this._keccak256_23(value_0); }
  _hashBytes52_0(value_0) { return this._keccak256_24(value_0); }
  _hashBytes53_0(value_0) { return this._keccak256_25(value_0); }
  _hashBytes54_0(value_0) { return this._keccak256_26(value_0); }
  _hashBytes55_0(value_0) { return this._keccak256_27(value_0); }
  _hashBytes56_0(value_0) { return this._keccak256_28(value_0); }
  _hashBytes57_0(value_0) { return this._keccak256_29(value_0); }
  _hashBytes58_0(value_0) { return this._keccak256_30(value_0); }
  _hashBytes59_0(value_0) { return this._keccak256_31(value_0); }
  _hashBytes60_0(value_0) { return this._keccak256_32(value_0); }
  _hashBytes61_0(value_0) { return this._keccak256_33(value_0); }
  _hashBytes62_0(value_0) { return this._keccak256_34(value_0); }
  _hashBytes63_0(value_0) { return this._keccak256_35(value_0); }
  _hashBytes93_0(value_0) { return this._keccak256_36(value_0); }
  _hashBytes94_0(value_0) { return this._keccak256_37(value_0); }
  _hashBytes376_0(value_0) { return this._keccak256_38(value_0); }
  _hashBytes1024_0(value_0) { return this._keccak256_39(value_0); }
  _hashBool_0(x_0) { return this._keccak256_40(x_0); }
  _hashUint_0(x_0) { return this._keccak256_41(x_0); }
  _hashVecBool_0(x_0) { return this._keccak256_42(x_0); }
  _hashEnum_0(x_0) { return this._keccak256_43(x_0); }
  _hashStruct_0(x_0) { return this._keccak256_44(x_0); }
  _hashVecStruct_0(x_0) { return this._keccak256_45(x_0); }
  async _hashBoolAndStore_0(context, partialProofData, x_0) {
    const digest_0 = this._keccak256_40(x_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashUintAndStore_0(context, partialProofData, x_0) {
    const digest_0 = this._keccak256_41(x_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashVecBoolAndStore_0(context, partialProofData, x_0) {
    const digest_0 = this._keccak256_42(x_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashEnumAndStore_0(context, partialProofData, x_0) {
    const digest_0 = this._keccak256_43(x_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashStructAndStore_0(context, partialProofData, x_0) {
    const digest_0 = this._keccak256_44(x_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashVecStructAndStore_0(context, partialProofData, x_0) {
    const digest_0 = this._keccak256_45(x_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  async _hashAndStore_0(context, partialProofData, value_0) {
    const digest_0 = this._keccak256_46(value_0);
    __compactRuntime.queryLedgerState(context,
                                      partialProofData,
                                      [
                                       { push: { storage: false,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_11.toValue(0n),
                                                                                              alignment: _descriptor_11.alignment() }).encode() } },
                                       { push: { storage: true,
                                                 value: __compactRuntime.StateValue.newCell({ value: _descriptor_2.toValue(digest_0),
                                                                                              alignment: _descriptor_2.alignment() }).encode() } },
                                       { ins: { cached: false, n: 1 } }]);
    return digest_0;
  }
  _hashBytes0_0(value_0) { return this._keccak256_47(value_0); }
  _hashBytes1_0(value_0) { return this._keccak256_48(value_0); }
  _hashBytes2_0(value_0) { return this._keccak256_49(value_0); }
  _hashBytes4_0(value_0) { return this._keccak256_50(value_0); }
  _hashBytes5_0(value_0) { return this._keccak256_51(value_0); }
  _hashBytes10_0(value_0) { return this._keccak256_52(value_0); }
  _hashBytes18_0(value_0) { return this._keccak256_53(value_0); }
  _hashVector_0(x_0) { return this._keccak256_54(x_0); }
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
    get lastDigest() {
      return _descriptor_2.fromValue(__compactRuntime.queryLedgerState(context,
                                                                       partialProofData,
                                                                       [
                                                                        { dup: { n: 0 } },
                                                                        { idx: { cached: false,
                                                                                 pushPath: false,
                                                                                 path: [
                                                                                        { tag: 'value',
                                                                                          value: { value: _descriptor_11.toValue(0n),
                                                                                                   alignment: _descriptor_11.alignment() } }] } },
                                                                        { popeq: { cached: false,
                                                                                   result: undefined } }]).value);
    },
    get withZkir() {
      return _descriptor_10.fromValue(__compactRuntime.queryLedgerState(context,
                                                                        partialProofData,
                                                                        [
                                                                         { dup: { n: 0 } },
                                                                         { idx: { cached: false,
                                                                                  pushPath: false,
                                                                                  path: [
                                                                                         { tag: 'value',
                                                                                           value: { value: _descriptor_11.toValue(1n),
                                                                                                    alignment: _descriptor_11.alignment() } }] } },
                                                                         { popeq: { cached: false,
                                                                                    result: undefined } }]).value);
    }
  };
}
const _emptyContext = {
  callContext: { currentQueryContext: new __compactRuntime.QueryContext(new __compactRuntime.ContractState().data, __compactRuntime.dummyContractAddress()), currentGasCost: __compactRuntime.emptyRunningCost() }
};
const _dummyContract = new Contract({ });
export const pureCircuits = {
  hashField: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashField: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(typeof(value_0) === 'bigint' && value_0 >= 0 && value_0 <= __compactRuntime.MAX_FIELD)) {
      __compactRuntime.typeError('hashField',
                                 'argument 1',
                                 'keccak.compact line 28 char 1',
                                 'Field',
                                 value_0)
    }
    return _dummyContract._hashField_0(value_0);
  },
  hashVector3: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashVector3: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(Array.isArray(value_0) && value_0.length === 3 && value_0.every((t) => typeof(t) === 'bigint' && t >= 0 && t <= __compactRuntime.MAX_FIELD))) {
      __compactRuntime.typeError('hashVector3',
                                 'argument 1',
                                 'keccak.compact line 32 char 1',
                                 'Vector<3, Field>',
                                 value_0)
    }
    return _dummyContract._hashVector3_0(value_0);
  },
  hashBytes12: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes12: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const x_0 = args_0[0];
    if (!(x_0.buffer instanceof ArrayBuffer && x_0.BYTES_PER_ELEMENT === 1 && x_0.length === 12)) {
      __compactRuntime.typeError('hashBytes12',
                                 'argument 1',
                                 'keccak.compact line 56 char 1',
                                 'Bytes<12>',
                                 x_0)
    }
    return _dummyContract._hashBytes12_0(x_0);
  },
  hashTriple: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashTriple: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const t_0 = args_0[0];
    if (!(typeof(t_0) === 'object' && t_0.a.buffer instanceof ArrayBuffer && t_0.a.BYTES_PER_ELEMENT === 1 && t_0.a.length === 4 && t_0.b.buffer instanceof ArrayBuffer && t_0.b.BYTES_PER_ELEMENT === 1 && t_0.b.length === 4 && t_0.c.buffer instanceof ArrayBuffer && t_0.c.BYTES_PER_ELEMENT === 1 && t_0.c.length === 4)) {
      __compactRuntime.typeError('hashTriple',
                                 'argument 1',
                                 'keccak.compact line 60 char 1',
                                 'struct Triple<a: Bytes<4>, b: Bytes<4>, c: Bytes<4>>',
                                 t_0)
    }
    return _dummyContract._hashTriple_0(t_0);
  },
  hashUneven: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashUneven: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const u_0 = args_0[0];
    if (!(typeof(u_0) === 'object' && u_0.head.buffer instanceof ArrayBuffer && u_0.head.BYTES_PER_ELEMENT === 1 && u_0.head.length === 1 && u_0.mid.buffer instanceof ArrayBuffer && u_0.mid.BYTES_PER_ELEMENT === 1 && u_0.mid.length === 4 && u_0.tail.buffer instanceof ArrayBuffer && u_0.tail.BYTES_PER_ELEMENT === 1 && u_0.tail.length === 7)) {
      __compactRuntime.typeError('hashUneven',
                                 'argument 1',
                                 'keccak.compact line 64 char 1',
                                 'struct Uneven<head: Bytes<1>, mid: Bytes<4>, tail: Bytes<7>>',
                                 u_0)
    }
    return _dummyContract._hashUneven_0(u_0);
  },
  hashBytes32: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes32: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 32)) {
      __compactRuntime.typeError('hashBytes32',
                                 'argument 1',
                                 'keccak.compact line 311 char 1',
                                 'Bytes<32>',
                                 value_0)
    }
    return _dummyContract._hashBytes32_0(value_0);
  },
  hashBytes33: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes33: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 33)) {
      __compactRuntime.typeError('hashBytes33',
                                 'argument 1',
                                 'keccak.compact line 315 char 1',
                                 'Bytes<33>',
                                 value_0)
    }
    return _dummyContract._hashBytes33_0(value_0);
  },
  hashBytes34: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes34: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 34)) {
      __compactRuntime.typeError('hashBytes34',
                                 'argument 1',
                                 'keccak.compact line 319 char 1',
                                 'Bytes<34>',
                                 value_0)
    }
    return _dummyContract._hashBytes34_0(value_0);
  },
  hashBytes35: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes35: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 35)) {
      __compactRuntime.typeError('hashBytes35',
                                 'argument 1',
                                 'keccak.compact line 323 char 1',
                                 'Bytes<35>',
                                 value_0)
    }
    return _dummyContract._hashBytes35_0(value_0);
  },
  hashBytes36: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes36: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 36)) {
      __compactRuntime.typeError('hashBytes36',
                                 'argument 1',
                                 'keccak.compact line 327 char 1',
                                 'Bytes<36>',
                                 value_0)
    }
    return _dummyContract._hashBytes36_0(value_0);
  },
  hashBytes37: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes37: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 37)) {
      __compactRuntime.typeError('hashBytes37',
                                 'argument 1',
                                 'keccak.compact line 331 char 1',
                                 'Bytes<37>',
                                 value_0)
    }
    return _dummyContract._hashBytes37_0(value_0);
  },
  hashBytes38: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes38: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 38)) {
      __compactRuntime.typeError('hashBytes38',
                                 'argument 1',
                                 'keccak.compact line 335 char 1',
                                 'Bytes<38>',
                                 value_0)
    }
    return _dummyContract._hashBytes38_0(value_0);
  },
  hashBytes39: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes39: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 39)) {
      __compactRuntime.typeError('hashBytes39',
                                 'argument 1',
                                 'keccak.compact line 339 char 1',
                                 'Bytes<39>',
                                 value_0)
    }
    return _dummyContract._hashBytes39_0(value_0);
  },
  hashBytes40: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes40: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 40)) {
      __compactRuntime.typeError('hashBytes40',
                                 'argument 1',
                                 'keccak.compact line 343 char 1',
                                 'Bytes<40>',
                                 value_0)
    }
    return _dummyContract._hashBytes40_0(value_0);
  },
  hashBytes41: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes41: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 41)) {
      __compactRuntime.typeError('hashBytes41',
                                 'argument 1',
                                 'keccak.compact line 347 char 1',
                                 'Bytes<41>',
                                 value_0)
    }
    return _dummyContract._hashBytes41_0(value_0);
  },
  hashBytes42: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes42: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 42)) {
      __compactRuntime.typeError('hashBytes42',
                                 'argument 1',
                                 'keccak.compact line 351 char 1',
                                 'Bytes<42>',
                                 value_0)
    }
    return _dummyContract._hashBytes42_0(value_0);
  },
  hashBytes43: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes43: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 43)) {
      __compactRuntime.typeError('hashBytes43',
                                 'argument 1',
                                 'keccak.compact line 355 char 1',
                                 'Bytes<43>',
                                 value_0)
    }
    return _dummyContract._hashBytes43_0(value_0);
  },
  hashBytes44: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes44: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 44)) {
      __compactRuntime.typeError('hashBytes44',
                                 'argument 1',
                                 'keccak.compact line 359 char 1',
                                 'Bytes<44>',
                                 value_0)
    }
    return _dummyContract._hashBytes44_0(value_0);
  },
  hashBytes45: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes45: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 45)) {
      __compactRuntime.typeError('hashBytes45',
                                 'argument 1',
                                 'keccak.compact line 363 char 1',
                                 'Bytes<45>',
                                 value_0)
    }
    return _dummyContract._hashBytes45_0(value_0);
  },
  hashBytes46: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes46: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 46)) {
      __compactRuntime.typeError('hashBytes46',
                                 'argument 1',
                                 'keccak.compact line 367 char 1',
                                 'Bytes<46>',
                                 value_0)
    }
    return _dummyContract._hashBytes46_0(value_0);
  },
  hashBytes47: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes47: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 47)) {
      __compactRuntime.typeError('hashBytes47',
                                 'argument 1',
                                 'keccak.compact line 371 char 1',
                                 'Bytes<47>',
                                 value_0)
    }
    return _dummyContract._hashBytes47_0(value_0);
  },
  hashBytes48: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes48: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 48)) {
      __compactRuntime.typeError('hashBytes48',
                                 'argument 1',
                                 'keccak.compact line 375 char 1',
                                 'Bytes<48>',
                                 value_0)
    }
    return _dummyContract._hashBytes48_0(value_0);
  },
  hashBytes49: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes49: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 49)) {
      __compactRuntime.typeError('hashBytes49',
                                 'argument 1',
                                 'keccak.compact line 379 char 1',
                                 'Bytes<49>',
                                 value_0)
    }
    return _dummyContract._hashBytes49_0(value_0);
  },
  hashBytes50: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes50: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 50)) {
      __compactRuntime.typeError('hashBytes50',
                                 'argument 1',
                                 'keccak.compact line 383 char 1',
                                 'Bytes<50>',
                                 value_0)
    }
    return _dummyContract._hashBytes50_0(value_0);
  },
  hashBytes51: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes51: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 51)) {
      __compactRuntime.typeError('hashBytes51',
                                 'argument 1',
                                 'keccak.compact line 387 char 1',
                                 'Bytes<51>',
                                 value_0)
    }
    return _dummyContract._hashBytes51_0(value_0);
  },
  hashBytes52: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes52: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 52)) {
      __compactRuntime.typeError('hashBytes52',
                                 'argument 1',
                                 'keccak.compact line 391 char 1',
                                 'Bytes<52>',
                                 value_0)
    }
    return _dummyContract._hashBytes52_0(value_0);
  },
  hashBytes53: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes53: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 53)) {
      __compactRuntime.typeError('hashBytes53',
                                 'argument 1',
                                 'keccak.compact line 395 char 1',
                                 'Bytes<53>',
                                 value_0)
    }
    return _dummyContract._hashBytes53_0(value_0);
  },
  hashBytes54: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes54: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 54)) {
      __compactRuntime.typeError('hashBytes54',
                                 'argument 1',
                                 'keccak.compact line 399 char 1',
                                 'Bytes<54>',
                                 value_0)
    }
    return _dummyContract._hashBytes54_0(value_0);
  },
  hashBytes55: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes55: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 55)) {
      __compactRuntime.typeError('hashBytes55',
                                 'argument 1',
                                 'keccak.compact line 403 char 1',
                                 'Bytes<55>',
                                 value_0)
    }
    return _dummyContract._hashBytes55_0(value_0);
  },
  hashBytes56: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes56: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 56)) {
      __compactRuntime.typeError('hashBytes56',
                                 'argument 1',
                                 'keccak.compact line 407 char 1',
                                 'Bytes<56>',
                                 value_0)
    }
    return _dummyContract._hashBytes56_0(value_0);
  },
  hashBytes57: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes57: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 57)) {
      __compactRuntime.typeError('hashBytes57',
                                 'argument 1',
                                 'keccak.compact line 411 char 1',
                                 'Bytes<57>',
                                 value_0)
    }
    return _dummyContract._hashBytes57_0(value_0);
  },
  hashBytes58: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes58: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 58)) {
      __compactRuntime.typeError('hashBytes58',
                                 'argument 1',
                                 'keccak.compact line 415 char 1',
                                 'Bytes<58>',
                                 value_0)
    }
    return _dummyContract._hashBytes58_0(value_0);
  },
  hashBytes59: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes59: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 59)) {
      __compactRuntime.typeError('hashBytes59',
                                 'argument 1',
                                 'keccak.compact line 419 char 1',
                                 'Bytes<59>',
                                 value_0)
    }
    return _dummyContract._hashBytes59_0(value_0);
  },
  hashBytes60: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes60: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 60)) {
      __compactRuntime.typeError('hashBytes60',
                                 'argument 1',
                                 'keccak.compact line 423 char 1',
                                 'Bytes<60>',
                                 value_0)
    }
    return _dummyContract._hashBytes60_0(value_0);
  },
  hashBytes61: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes61: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 61)) {
      __compactRuntime.typeError('hashBytes61',
                                 'argument 1',
                                 'keccak.compact line 427 char 1',
                                 'Bytes<61>',
                                 value_0)
    }
    return _dummyContract._hashBytes61_0(value_0);
  },
  hashBytes62: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes62: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 62)) {
      __compactRuntime.typeError('hashBytes62',
                                 'argument 1',
                                 'keccak.compact line 431 char 1',
                                 'Bytes<62>',
                                 value_0)
    }
    return _dummyContract._hashBytes62_0(value_0);
  },
  hashBytes63: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes63: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 63)) {
      __compactRuntime.typeError('hashBytes63',
                                 'argument 1',
                                 'keccak.compact line 435 char 1',
                                 'Bytes<63>',
                                 value_0)
    }
    return _dummyContract._hashBytes63_0(value_0);
  },
  hashBytes93: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes93: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 93)) {
      __compactRuntime.typeError('hashBytes93',
                                 'argument 1',
                                 'keccak.compact line 440 char 1',
                                 'Bytes<93>',
                                 value_0)
    }
    return _dummyContract._hashBytes93_0(value_0);
  },
  hashBytes94: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes94: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 94)) {
      __compactRuntime.typeError('hashBytes94',
                                 'argument 1',
                                 'keccak.compact line 445 char 1',
                                 'Bytes<94>',
                                 value_0)
    }
    return _dummyContract._hashBytes94_0(value_0);
  },
  hashBytes376: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes376: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 376)) {
      __compactRuntime.typeError('hashBytes376',
                                 'argument 1',
                                 'keccak.compact line 450 char 1',
                                 'Bytes<376>',
                                 value_0)
    }
    return _dummyContract._hashBytes376_0(value_0);
  },
  hashBytes1024: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes1024: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 1024)) {
      __compactRuntime.typeError('hashBytes1024',
                                 'argument 1',
                                 'keccak.compact line 455 char 1',
                                 'Bytes<1024>',
                                 value_0)
    }
    return _dummyContract._hashBytes1024_0(value_0);
  },
  hashBool: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBool: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const x_0 = args_0[0];
    if (!(typeof(x_0) === 'boolean')) {
      __compactRuntime.typeError('hashBool',
                                 'argument 1',
                                 'keccak.compact line 524 char 1',
                                 'Boolean',
                                 x_0)
    }
    return _dummyContract._hashBool_0(x_0);
  },
  hashUint: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashUint: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const x_0 = args_0[0];
    if (!(typeof(x_0) === 'bigint' && x_0 >= 0n && x_0 <= 18446744073709551615n)) {
      __compactRuntime.typeError('hashUint',
                                 'argument 1',
                                 'keccak.compact line 528 char 1',
                                 'Uint<0..18446744073709551616>',
                                 x_0)
    }
    return _dummyContract._hashUint_0(x_0);
  },
  hashVecBool: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashVecBool: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const x_0 = args_0[0];
    if (!(Array.isArray(x_0) && x_0.length === 3 && x_0.every((t) => typeof(t) === 'boolean'))) {
      __compactRuntime.typeError('hashVecBool',
                                 'argument 1',
                                 'keccak.compact line 532 char 1',
                                 'Vector<3, Boolean>',
                                 x_0)
    }
    return _dummyContract._hashVecBool_0(x_0);
  },
  hashEnum: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashEnum: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const x_0 = args_0[0];
    if (!(typeof(x_0) === 'number' && x_0 >= 0 && x_0 <= 3)) {
      __compactRuntime.typeError('hashEnum',
                                 'argument 1',
                                 'keccak.compact line 536 char 1',
                                 'Enum<Direction, North, East, South, West>',
                                 x_0)
    }
    return _dummyContract._hashEnum_0(x_0);
  },
  hashStruct: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashStruct: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const x_0 = args_0[0];
    if (!(typeof(x_0) === 'object' && typeof(x_0.a) === 'boolean' && typeof(x_0.b) === 'bigint' && x_0.b >= 0n && x_0.b <= 255n && typeof(x_0.c) === 'number' && x_0.c >= 0 && x_0.c <= 3)) {
      __compactRuntime.typeError('hashStruct',
                                 'argument 1',
                                 'keccak.compact line 540 char 1',
                                 'struct Parcel<a: Boolean, b: Uint<0..256>, c: Enum<Direction, North, East, South, West>>',
                                 x_0)
    }
    return _dummyContract._hashStruct_0(x_0);
  },
  hashVecStruct: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashVecStruct: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const x_0 = args_0[0];
    if (!(Array.isArray(x_0) && x_0.length === 3 && x_0.every((t) => typeof(t) === 'object' && typeof(t.a) === 'boolean' && typeof(t.b) === 'bigint' && t.b >= 0n && t.b <= 255n && typeof(t.c) === 'number' && t.c >= 0 && t.c <= 3))) {
      __compactRuntime.typeError('hashVecStruct',
                                 'argument 1',
                                 'keccak.compact line 544 char 1',
                                 'Vector<3, struct Parcel<a: Boolean, b: Uint<0..256>, c: Enum<Direction, North, East, South, West>>>',
                                 x_0)
    }
    return _dummyContract._hashVecStruct_0(x_0);
  },
  hashBytes0: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes0: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 0)) {
      __compactRuntime.typeError('hashBytes0',
                                 'argument 1',
                                 'keccak.compact line 595 char 1',
                                 'Bytes<0>',
                                 value_0)
    }
    return _dummyContract._hashBytes0_0(value_0);
  },
  hashBytes1: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes1: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 1)) {
      __compactRuntime.typeError('hashBytes1',
                                 'argument 1',
                                 'keccak.compact line 600 char 1',
                                 'Bytes<1>',
                                 value_0)
    }
    return _dummyContract._hashBytes1_0(value_0);
  },
  hashBytes2: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes2: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 2)) {
      __compactRuntime.typeError('hashBytes2',
                                 'argument 1',
                                 'keccak.compact line 605 char 1',
                                 'Bytes<2>',
                                 value_0)
    }
    return _dummyContract._hashBytes2_0(value_0);
  },
  hashBytes4: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes4: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 4)) {
      __compactRuntime.typeError('hashBytes4',
                                 'argument 1',
                                 'keccak.compact line 610 char 1',
                                 'Bytes<4>',
                                 value_0)
    }
    return _dummyContract._hashBytes4_0(value_0);
  },
  hashBytes5: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes5: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 5)) {
      __compactRuntime.typeError('hashBytes5',
                                 'argument 1',
                                 'keccak.compact line 615 char 1',
                                 'Bytes<5>',
                                 value_0)
    }
    return _dummyContract._hashBytes5_0(value_0);
  },
  hashBytes10: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes10: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 10)) {
      __compactRuntime.typeError('hashBytes10',
                                 'argument 1',
                                 'keccak.compact line 620 char 1',
                                 'Bytes<10>',
                                 value_0)
    }
    return _dummyContract._hashBytes10_0(value_0);
  },
  hashBytes18: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashBytes18: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const value_0 = args_0[0];
    if (!(value_0.buffer instanceof ArrayBuffer && value_0.BYTES_PER_ELEMENT === 1 && value_0.length === 18)) {
      __compactRuntime.typeError('hashBytes18',
                                 'argument 1',
                                 'keccak.compact line 625 char 1',
                                 'Bytes<18>',
                                 value_0)
    }
    return _dummyContract._hashBytes18_0(value_0);
  },
  hashVector: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`hashVector: expected 1 argument (as invoked from Typescript), received ${args_0.length}`);
    }
    const x_0 = args_0[0];
    if (!(Array.isArray(x_0) && x_0.length === 4 && x_0.every((t) => typeof(t) === 'bigint' && t >= 0 && t <= __compactRuntime.MAX_FIELD))) {
      __compactRuntime.typeError('hashVector',
                                 'argument 1',
                                 'keccak.compact line 652 char 1',
                                 'Vector<4, Field>',
                                 x_0)
    }
    return _dummyContract._hashVector_0(x_0);
  }
};
export const contractReferenceLocations =
  { tag: 'publicLedgerArray', indices: { } };
export const expectedVk = {
  'hashAndStore': '729143a620806528bd2ab9a4a4c553175cb0673355f4aab174c2525773e0b66d',
  'hashAndStore1': '88fa1c2fc4f3fef818c516913e99910370adbd71331d3f58635c9a74e4d8405b',
  'hashAndStore1024': 'ec5c57831e17d0fac3ed60aaedbe2f8a7017f150dfb9cd81a67be727ed675324',
  'hashAndStore32': '729143a620806528bd2ab9a4a4c553175cb0673355f4aab174c2525773e0b66d',
  'hashAndStore33': 'cd0ce957b81273d3819fe6b21463d7b4ead0295a60428b343886ac9a7299583a',
  'hashAndStore34': '2652b1a8f907202c6a5cab5d84aef1ed3b64d0902d4be44252cdb34af8b9fc95',
  'hashAndStore35': '0b57eaed4fd997c8858476a77055925e61fa70e1b358f2056e1421f7424509a2',
  'hashAndStore36': '7764a74be3d6ba3c7a55b7ca031824d8a986fffa3ad52fd5b427dd9c50287099',
  'hashAndStore37': 'e57b77a377ab61f422cc091c64f8948159914e1db79d719c7848b68264d0fdd6',
  'hashAndStore376': '8d56671371f8605aef5e841735edd44b9e1bb0b68ddc1c8c885d8a799bf7b8c8',
  'hashAndStore38': '5ec80d4317d7ded136f4910313c82185bc43fb9b2c8998615261905be6f46719',
  'hashAndStore39': '0406f90a8c6389d675eb63c9d66b9420cb68a6ea620a5d112e9140a2bc2ea128',
  'hashAndStore40': 'dcddd0c3365ef1f002d10394ee9deeb61986a6c3bc6fc779f2549247e9111e46',
  'hashAndStore41': 'f2f1384699d51ca34b35cd71750234c589aff8024a5a13b628a7c2d9894fd0e3',
  'hashAndStore42': '5ad15279209e3dcbac82dc5d5a0d843ef4fefda12e404e28b18b6b71b5f1391e',
  'hashAndStore43': '33cafbf1b5af3cd84ce0ff0a60ee8ebbdf6a1d5cf760da1de1863374054b027e',
  'hashAndStore44': '8224b2509cfc8f301b6f66fdad692d982611b55506578cd19467a300ab58852e',
  'hashAndStore45': '528b192088d12d40032c4406dc4b74866c95e363d17110b648037d26e04f77de',
  'hashAndStore46': 'a4b874a1cfe22e2de0b7002e87e59868ec32ede9a2868ed104f57e7bd4f65636',
  'hashAndStore47': 'f512154a7de5a791d6fc3cc1304c72da1636508eec0fe4f7908f86cac17d6d60',
  'hashAndStore48': 'e6bb6d6882f92021202b249867fdb586587032a1754953e07d75b81723e8c65f',
  'hashAndStore49': '7fccc267052fc1714ce14f9950714d1b8d115282a84891a86e3a31717a04121e',
  'hashAndStore50': 'ab67754bbd750d3a8f99bca7e8429575a0baca93b6776ac4abea08d00e49c08c',
  'hashAndStore51': '9a664e36643f5be9ea139305f16d6e85629adb827b37eba5c98c73c9b4eb52ba',
  'hashAndStore52': 'a597d7f09b31b1bc2bbeafb195e6878e8eaaad5b525bd5620bcd201fd136bd63',
  'hashAndStore53': 'b61913253db0960376c74df8dd9bc1172951adfd83e6f24509a55609a0183ca4',
  'hashAndStore54': 'af2fbaf0b3a13a712bc7aa3b3cd97684e7e50e6240e9f64f24f61047889cc541',
  'hashAndStore55': '480a2701461011baf65e98a648d1866312f99b4232ffb4814522874b4179d29c',
  'hashAndStore56': '76146bd32c557247aac12552e33d8bcb36503f6248d6d8da1ff8d51152763d7d',
  'hashAndStore57': '6a7f536f5f14fe751e7a24b6672412fcaffa8117950a3a5d1886f032fdb4a95e',
  'hashAndStore58': '0614479a9ae364d0903ec08d452323468727dba2515b0896345aff825ab0820b',
  'hashAndStore59': 'be65670cdeb4d7b33256745fe32397c1259b84cde05ad38983f6717c8ad10eaf',
  'hashAndStore60': '39dc58e4136c681648ffd982219049e527fbab44e1599d48758ad49bea9dbb0d',
  'hashAndStore61': '6e0be040b1e18341dacc32ebe23b302e48aeb2058926682fa154b5131266d817',
  'hashAndStore62': '792290f0771b4603f2cb99b808af98f9177bef240e40fc017b4c6d22c35d8f40',
  'hashAndStore63': 'b0b2c9521824d2d0f6a5c4327edbe914c867bdf0087d6af91e9a66318ac462ed',
  'hashAndStore93': '81b43fdae197415b65d153b5a71cd249c41378a240b3d92c9f9749d805941460',
  'hashAndStore94': 'c39cdfaa7665064c791270a3287d3371c5f80e61da94d4f8c94579a738895177',
  'hashBoolAndStore': '673432ac1da3e89d771cf10b3b02069494d958aab229369e8664aeee6ee3e8d2',
  'hashBytes': 'cfec8ad9e2c43a161229b167b15be589c5545818ef49ae6a16f8867babf8f5bf',
  'hashEnumAndStore': '18675d89e058905695416435ce0d55c42b35ece0143b983fc4ea249218475353',
  'hashFieldAndStore': '72c5c8b8ab8b38319ceba3d6c6124716cbe9448a07603ccf34277b4c04dd4263',
  'hashStructAndStore': 'aac95da4703c8a35f84ce48fe3c53a3dba938579f1a6bd7d14ed0dc7fa50cda9',
  'hashUintAndStore': 'b84dc6449818bae6147c911ca8bef36cd46bbefba8e4bbb52be64e757411c112',
  'hashVecBoolAndStore': '739e8f13dc6d94730ec2c18f210753d390aa405f85cf86dd42a49a76314b6c1d',
  'hashVecStructAndStore': 'e931d81a4891408362045badb7f15c31bd0f86b522a2c2d05b87d10a936ee093',
  'hashVector3AndStore': '4082db28ce944274565ea580282f5a5da77aa0621f96e19feeb691052c74fba8',
};

//# sourceMappingURL=index.js.map
