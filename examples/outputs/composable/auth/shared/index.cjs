'use strict';
const __compactRuntime = require('@midnight-ntwrk/compact-runtime');
const expectedRuntimeVersionString = '0.7.0';
// @parisa - Normally this will be generated. Commenting out for development purposes.
// __compactRuntime.checkRuntimeVersion(expectedRuntimeVersionString);

const contractId = 'shared';

const _descriptor_2 = __compactRuntime.CompactTypeField;

class _StructExample_0 {
  alignment() {
    return _descriptor_2.alignment();
  }

  fromValue(value) {
    return {
      value: _descriptor_2.fromValue(value),
    };
  }

  toValue(value) {
    return _descriptor_2.toValue(value.value);
  }

  valueAlignment(value) {
    return _descriptor_2.valueAlignment(value.value);
  }
}

const _descriptor_3 = new _StructExample_0();

const pureCircuits = {
  public_key: (...args_0) => {
    if (args_0.length !== 1) {
      throw new __compactRuntime.CompactError(`public_key: expected 1 arguments, received ${args_0.length}`);
    }
    const sk = args_0[0];
    if (!(sk.buffer instanceof ArrayBuffer && sk.BYTES_PER_ELEMENT === 1 && sk.length === 32)) {
      __compactRuntime.typeError('public_key',
        'argument 1',
        'examples/auth-cell.compact line 28, char 1',
        'Bytes[32]',
        sk);
    }
    const result = __compactRuntime.persistentHash(
      new Uint8Array([97, 117, 116, 104, 45, 99, 101, 108, 108, 58, 112, 107, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      sk);
    return result;
  },
};

exports.contractId = contractId;
exports._descriptor_3 = _descriptor_3;
exports.contractReferenceLocations = [] // @parisa - replace with actual 'contractReferenceLocations'
exports.pureCircuits = pureCircuits;
