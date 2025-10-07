// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import inspect from 'object-inspect';
import * as ocrt from '@midnight-ntwrk/onchain-runtime';

export * from './version';

export {
  CostModel,
  Value,
  Alignment,
  AlignmentSegment,
  AlignmentAtom,
  AlignedValue,
  Nullifier,
  CoinCommitment,
  ContractAddress,
  TokenType,
  CoinPublicKey,
  Nonce,
  ShieldedCoinInfo,
  QualifiedShieldedCoinInfo,
  Fr,
  Key,
  Op,
  GatherResult,
  BlockContext,
  Effects,
  runProgram,
  ContractOperation,
  ContractState,
  ContractMaintenanceAuthority,
  QueryContext,
  QueryResults,
  StateBoundedMerkleTree,
  StateMap,
  StateValue,
  Signature,
  SigningKey,
  SignatureVerifyingKey,
  VmResults,
  VmStack,
  PublicAddress,
  UserAddress,
  DomainSeparator,
  RawTokenType,
  valueToBigInt,
  bigIntToValue,
  maxAlignedSize,
  runtimeCoinCommitment,
  leafHash,
  NetworkId,
  sampleContractAddress,
  sampleSigningKey,
  signData,
  signatureVerifyingKey,
  verifySignature,
  encodeRawTokenType,
  decodeRawTokenType,
  encodeContractAddress,
  decodeContractAddress,
  encodeCoinPublicKey,
  decodeCoinPublicKey,
  encodeShieldedCoinInfo,
  encodeQualifiedShieldedCoinInfo,
  decodeShieldedCoinInfo,
  decodeQualifiedShieldedCoinInfo,
  dummyContractAddress,
  rawTokenType,
  sampleRawTokenType,
  sampleUserAddress,
  encodeUserAddress,
  decodeUserAddress,
} from '@midnight-ntwrk/onchain-runtime';

export {
  contractDependencies,
  ContractReferenceLocations,
  ContractReferenceLocationsSet,
  SparseCompactADT,
  SparseCompactCellADT,
  SparseCompactArrayLikeADT,
  SparseCompactMapADT,
  SparseCompactSetADT,
  SparseCompactListADT,
  SparseCompactValue,
  SparseCompactType,
  SparseCompactVector,
  SparseCompactStruct,
  SparseCompactContractAddress,
} from './contract-dependencies';

/**
 * The maximum value representable in Compact's `Field` type
 *
 * One less than the prime modulus of the proof system's scalar field
 */
export const MAX_FIELD: bigint = ocrt.maxField();
const FIELD_MODULUS: bigint = MAX_FIELD + 1n;
/**
 * A valid placeholder contract address
 *
 * @deprecated Cannot handle {@link NetworkId}s, use
 * {@link dummyContractAddress} instead.
 */
export const DUMMY_ADDRESS: string = ocrt.dummyContractAddress();
/**
 * A transcript of operations and their effects, for inclusion and replay in
 * transactions
 */
export type Transcript = ocrt.Transcript<ocrt.AlignedValue>;

/**
 * Concatenates multiple {@link AlignedValue}s
 * @internal
 */
export function alignedConcat(...values: ocrt.AlignedValue[]): ocrt.AlignedValue {
  const res: ocrt.AlignedValue = { value: [], alignment: [] };
  for (const value of values) {
    res.value = res.value.concat(value.value);
    res.alignment = res.alignment.concat(value.alignment);
  }
  return res;
}

/**
 * The Compact builtin `transient_hash` function
 *
 * This function is a circuit-efficient compression function from arbitrary
 * data to field elements, which is not guaranteed to persist between upgrades.
 * It should not be used to derive state data, but can be used for consistency
 * checks.
 */
export function transientHash<a>(rt_type: CompactType<a>, value: a): bigint {
  return ocrt.valueToBigInt(ocrt.transientHash(rt_type.alignment(), rt_type.toValue(value)));
}

/**
 * The Compact builtin `transient_commit` function
 *
 * This function is a circuit-efficient commitment function from arbitrary
 * values representable in Compact, and a field element commitment opening, to
 * field elements, which is not guaranteed to persist between
 * upgrades. It should not be used to derive state data, but can be used for
 * consistency checks.
 *
 * @throws If `opening` is out of range for field elements
 */
export function transientCommit<a>(rt_type: CompactType<a>, value: a, opening: bigint): bigint {
  return ocrt.valueToBigInt(ocrt.transientCommit(rt_type.alignment(), rt_type.toValue(value), ocrt.bigIntToValue(opening)));
}

/**
 * The Compact builtin `persistent_hash` function
 *
 * This function is a non-circuit-optimised hash function for mostly arbitrary
 * data. It is guaranteed to persist between upgrades, with the exception of
 * devnet. It *should* be used to derive state data, and not for consistency
 * checks where avoidable.
 *
 * Note that data containing `Opaque` elements *may* throw runtime errors, and
 * cannot be relied upon as a consistent representation.
 *
 * @throws If `rt_type` encodes a type containing Compact 'Opaque' types
 */
export function persistentHash<a>(rt_type: CompactType<a>, value: a): Uint8Array {
  const wrapped = ocrt.persistentHash(rt_type.alignment(), rt_type.toValue(value))[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `persistent_commit` function
 *
 * This function is a non-circuit-optimised commitment function from arbitrary
 * values representable in Compact, and a 256-bit bytestring opening, to a
 * 256-bit bytestring. It is guaranteed to persist between upgrades. It
 * *should* be used to derive state data, and not for consistency checks where
 * avoidable.
 *
 * Note that data containing `Opaque` elements *may* throw runtime errors, and
 * cannot be relied upon as a consistent representation.
 *
 * @throws If `rt_type` encodes a type containing Compact 'Opaque' types, or
 * `opening` is not 32 bytes long
 */
export function persistentCommit<a>(rt_type: CompactType<a>, value: a, opening: Uint8Array): Uint8Array {
  if (opening.length != 32) {
    throw new CompactError('Expected 32-byte string');
  }
  const wrapped = ocrt.persistentCommit(rt_type.alignment(), rt_type.toValue(value), [opening])[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `degrade_to_transient` function
 *
 * This function "degrades" the output of a {@link persistentHash} or
 * {@link persistentCommit} to a field element, which can then be used in
 * {@link transientHash} or {@link transientCommit}.
 *
 * @throws If `x` is not 32 bytes long
 */
export function degradeToTransient(x: Uint8Array): bigint {
  if (x.length != 32) {
    throw new CompactError('Expected 32-byte string');
  }
  return ocrt.valueToBigInt(ocrt.degradeToTransient([x]));
}

/**
 * The Compact builtin `upgrade_from_transient` function
 *
 * This function "upgrades" the output of a {@link transientHash} or
 * {@link transientCommit} to 256-bit byte string, which can then be used in
 * {@link persistentHash} or {@link persistentCommit}.
 *
 * @throws If `x` is not a valid field element
 */
export function upgradeFromTransient(x: bigint): Uint8Array {
  const wrapped = ocrt.upgradeFromTransient(ocrt.bigIntToValue(x))[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `hash_to_curve` function
 *
 * This function maps arbitrary values representable in Compact to elliptic
 * curve points in the proof system's embedded curve.
 *
 * Outputs are guaranteed to have unknown discrete logarithm with respect to
 * the group base, and any other output, but are not guaranteed to be unique (a
 * given input can be proven correct for multiple outputs).
 *
 * Inputs of different types may have the same output, if they have the same
 * field-aligned binary representation.
 */
export function hashToCurve<a>(rt_type: CompactType<a>, x: a): CurvePoint {
  return new CompactTypeCurvePoint().fromValue(ocrt.hashToCurve(rt_type.alignment(), rt_type.toValue(x)));
}

/**
 * The Compact builtin `ec_add` function
 *
 * This function add two elliptic curve points (in multiplicative notation)
 */
export function ecAdd(a: CurvePoint, b: CurvePoint): CurvePoint {
  const rt_type = new CompactTypeCurvePoint();
  return rt_type.fromValue(ocrt.ecAdd(rt_type.toValue(a), rt_type.toValue(b)));
}

/**
 * The Compact builtin `ec_mul` function
 *
 * This function multiplies an elliptic curve point by a scalar (in
 * multiplicative notation)
 */
export function ecMul(a: CurvePoint, b: bigint): CurvePoint {
  const rt_type = new CompactTypeCurvePoint();
  return rt_type.fromValue(ocrt.ecMul(rt_type.toValue(a), ocrt.bigIntToValue(b)));
}

/**
 * The Compact builtin `ec_mul_generator` function
 *
 * This function multiplies the primary group generator of the embedded curve
 * by a scalar (in multiplicative notation)
 */
export function ecMulGenerator(b: bigint): CurvePoint {
  return new CompactTypeCurvePoint().fromValue(ocrt.ecMulGenerator(ocrt.bigIntToValue(b)));
}

/**
 * The recipient of a coin produced by a circuit.
 */
export interface Recipient {
  /**
   * Whether the recipient is a user or a contract.
   */
  readonly is_left: boolean;
  /**
   * The recipient's public key, if the recipient is a user.
   */
  readonly left: ocrt.CoinPublicKey;
  /**
   * The recipient's contract address, if the recipient is a contract.
   */
  readonly right: ocrt.ContractAddress;
}

/**
 * A {@link CoinPublicKey} encoded as a byte string. This representation is used internally by the contract executable.
 */
export interface EncodedCoinPublicKey {
  /**
   * The coin public key's bytes.
   */
  readonly bytes: Uint8Array;
}

/**
 * Tracks the coins consumed and produced throughout circuit execution.
 */
export interface EncodedZswapLocalState {
  /**
   * The Zswap coin public key of the user executing the circuit.
   */
  coinPublicKey: EncodedCoinPublicKey;
  /**
   * The Merkle tree index of the next coin produced.
   */
  currentIndex: bigint;
  /**
   * The coins consumed as inputs to the circuit.
   */
  inputs: EncodedQualifiedShieldedCoinInfo[];
  /**
   * The coins produced as outputs from the circuit.
   */
  outputs: {
    coinInfo: EncodedShieldedCoinInfo;
    recipient: EncodedRecipient;
  }[];
}

/**
 * Constructs a new {@link EncodedZswapLocalState} with the given coin public key. The result can be used to create a
 * {@link ConstructorContext}.
 *
 * @param coinPublicKey The Zswap coin public key of the user executing the circuit.
 */
export const emptyZswapLocalState = (coinPublicKey: ocrt.CoinPublicKey): EncodedZswapLocalState => ({
  coinPublicKey: { bytes: ocrt.encodeCoinPublicKey(coinPublicKey) },
  currentIndex: 0n,
  inputs: [],
  outputs: [],
});

/**
 * Converts an {@link Recipient} to an {@link EncodedRecipient}. Useful for testing.
 */
export const encodeRecipient = ({ is_left, left, right }: Recipient): EncodedRecipient => ({
  is_left,
  left: { bytes: ocrt.encodeCoinPublicKey(left) },
  right: { bytes: ocrt.encodeContractAddress(right) },
});

/**
 * Converts a {@link ZswapLocalState} to an {@link EncodedZswapLocalState}. Useful for testing.
 *
 * @param state The decoded Zswap local state.
 */
export const encodeZswapLocalState = (state: ZswapLocalState): EncodedZswapLocalState => ({
  coinPublicKey: { bytes: ocrt.encodeCoinPublicKey(state.coinPublicKey) },
  currentIndex: state.currentIndex,
  inputs: state.inputs.map(ocrt.encodeQualifiedShieldedCoinInfo),
  outputs: state.outputs.map(({ coinInfo, recipient }) => ({
    coinInfo: ocrt.encodeShieldedCoinInfo(coinInfo),
    recipient: encodeRecipient(recipient),
  })),
});

/**
 * Tracks the coins consumed and produced throughout circuit execution.
 */
export interface ZswapLocalState {
  /**
   * The Zswap coin public key of the user executing the circuit.
   */
  coinPublicKey: ocrt.CoinPublicKey;
  /**
   * The Merkle tree index of the next coin produced.
   */
  currentIndex: bigint;
  /**
   * The coins consumed as inputs to the circuit.
   */
  inputs: ocrt.QualifiedShieldedCoinInfo[];
  /**
   * The coins produced as outputs from the circuit.
   */
  outputs: {
    coinInfo: ocrt.ShieldedCoinInfo;
    recipient: Recipient;
  }[];
}

/**
 * Converts an {@link EncodedRecipient} to a {@link Recipient}.
 */
export const decodeRecipient = ({ is_left, left, right }: EncodedRecipient): Recipient => ({
  is_left,
  left: ocrt.decodeCoinPublicKey(left.bytes),
  right: ocrt.decodeContractAddress(right.bytes),
});

/**
 * Converts an {@link EncodedZswapLocalState} to a {@link ZswapLocalState}. Used when we need to use data from contract
 * execution to construct transactions.
 *
 * @param state The encoded Zswap local state.
 */
export const decodeZswapLocalState = (state: EncodedZswapLocalState): ZswapLocalState => ({
  coinPublicKey: ocrt.decodeCoinPublicKey(state.coinPublicKey.bytes),
  currentIndex: state.currentIndex,
  inputs: state.inputs.map(ocrt.decodeQualifiedShieldedCoinInfo),
  outputs: state.outputs.map(({ coinInfo, recipient }) => ({
    coinInfo: ocrt.decodeShieldedCoinInfo(coinInfo),
    recipient: decodeRecipient(recipient),
  })),
});

/**
 * The external information accessible from within a Compact circuit call
 */
export interface CircuitContext<T> {
  /**
   * The original contract state the circuit call was started at.
   */
  originalState: ocrt.ContractState;
  /**
   * The current private state for the contract.
   */
  currentPrivateState: T;
  /**
   * The current Zswap local state. Tracks inputs and outputs produced during circuit execution.
   */
  currentZswapLocalState: EncodedZswapLocalState;
  /**
   * The current on-chain context the transaction is evolving.
   */
  transactionContext: ocrt.QueryContext;
}

/**
 * A {@link QualifiedShieldedCoinInfo} with its fields encoded as byte strings. This representation is used internally by
 * the contract executable.
 */
export interface EncodedQualifiedShieldedCoinInfo {
  /**
   * The coin's randomness, preventing it from colliding with other coins.
   */
  readonly nonce: Uint8Array;
  /**
   * The coin's type, identifying the currency it represents.
   */
  readonly color: Uint8Array;
  /**
   * The coin's value, in atomic units dependent on the currency. Bounded to be a non-negative 64-bit integer.
   */
  readonly value: bigint;
  /**
   * The coin's location in the chain's Merkle tree of coin commitments. Bounded to be a non-negative 64-bit integer.
   */
  readonly mt_index: bigint;
}

/**
 * Adds a coin to the list of inputs consumed by the circuit.
 *
 * @param circuitContext The current circuit context.
 * @param qualifiedShieldedCoinInfo The input to consume.
 */
export function createZswapInput(circuitContext: CircuitContext<unknown>, qualifiedShieldedCoinInfo: EncodedQualifiedShieldedCoinInfo): void {
  circuitContext.currentZswapLocalState = {
    ...circuitContext.currentZswapLocalState,
    inputs: circuitContext.currentZswapLocalState.inputs.concat(qualifiedShieldedCoinInfo),
  };
}

/**
 * A {@link ShieldedCoinInfo} with its fields encoded as byte strings. This representation is used internally by
 * the contract executable.
 */
export interface EncodedShieldedCoinInfo {
  /**
   * The coin's randomness, preventing it from colliding with other coins.
   */
  readonly nonce: Uint8Array;
  /**
   * The coin's type, identifying the currency it represents.
   */
  readonly color: Uint8Array;
  /**
   * The coin's value, in atomic units dependent on the currency. Bounded to be a non-negative 64-bit integer.
   */
  readonly value: bigint;
}

/**
 * A {@link ContractAddress} encoded as a byte string. This representation is used internally by the contract executable.
 */
export interface EncodedContractAddress {
  /**
   * The contract address's bytes.
   */
  readonly bytes: Uint8Array;
}

/**
 * A {@link Recipient} with its fields encoded as byte strings. This representation is used internally by the contract executable.
 */
export interface EncodedRecipient {
  /**
   * Whether the recipient is a user or a contract.
   */
  readonly is_left: boolean;
  /**
   * The recipient's public key, if the recipient is a user.
   */
  readonly left: EncodedCoinPublicKey;
  /**
   * The recipient's contract address, if the recipient is a contract.
   */
  readonly right: EncodedContractAddress;
}

/**
 * Creates a coin commitment from the given coin information and recipient represented as an Impact value.
 *
 * @param coinInfo The coin.
 * @param recipient The coin recipient.
 *
 * @internal
 */
function createCoinCommitment(coinInfo: EncodedShieldedCoinInfo, recipient: EncodedRecipient): ocrt.AlignedValue {
  return ocrt.runtimeCoinCommitment(
    {
      value: ShieldedCoinInfoDescriptor.toValue(coinInfo),
      alignment: ShieldedCoinInfoDescriptor.alignment(),
    },
    {
      value: ShieldedCoinRecipientDescriptor.toValue(recipient),
      alignment: ShieldedCoinRecipientDescriptor.alignment(),
    },
  );
}

/**
 * Adds a coin to the list of outputs produced by the circuit.
 *
 * @param circuitContext The current circuit context.
 * @param coinInfo The coin to produce.
 * @param recipient The coin recipient - either a coin public key representing an end user or a contract address
 *                  representing a contract.
 */
export function createZswapOutput(
  circuitContext: CircuitContext<unknown>,
  coinInfo: EncodedShieldedCoinInfo,
  recipient: EncodedRecipient,
): void {
  circuitContext.transactionContext = circuitContext.transactionContext.insertCommitment(
    Buffer.from(Bytes32Descriptor.fromValue(createCoinCommitment(coinInfo, recipient).value)).toString('hex'),
    circuitContext.currentZswapLocalState.currentIndex,
  );
  circuitContext.currentZswapLocalState = {
    ...circuitContext.currentZswapLocalState,
    currentIndex: circuitContext.currentZswapLocalState.currentIndex + 1n,
    outputs: circuitContext.currentZswapLocalState.outputs.concat({
      coinInfo,
      recipient,
    }),
  };
}

/**
 * Retrieves the Zswap coin public key of the user executing the circuit.
 *
 * @param circuitContext The current circuit context.
 */
export function ownPublicKey(circuitContext: CircuitContext<unknown>): EncodedCoinPublicKey {
  return circuitContext.currentZswapLocalState.coinPublicKey;
}

/**
 * The external information accessible from within a Compact witness call
 */
export interface WitnessContext<L, T> {
  /**
   * The projected ledger state, if the transaction were to run against the
   * ledger state as you locally see it currently
   */
  readonly ledger: L;
  /**
   * The current private state for the contract
   */
  readonly privateState: T;
  /**
   * The address of the contract being called
   */
  readonly contractAddress: string;
}

/**
 * Internal constructor for {@link WitnessContext}.
 * @internal
 */
export function witnessContext<L, T>(ledger: L, privateState: T, contractAddress: ocrt.ContractAddress): WitnessContext<L, T> {
  return {
    ledger,
    privateState,
    contractAddress,
  };
}

/**
 * Encapsulates the data required to produce a zero-knowledge proof
 */
export interface ProofData {
  /**
   * The inputs to a circuit
   */
  input: ocrt.AlignedValue;
  /**
   * The outputs from a circuit
   */
  output: ocrt.AlignedValue;
  /**
   * The public transcript of operations
   */
  publicTranscript: ocrt.Op<ocrt.AlignedValue>[];
  /**
   * The transcript of the witness call outputs
   */
  privateTranscriptOutputs: ocrt.AlignedValue[];
}

/**
 * Verifies a given {@link ProofData} satisfies the constrains of a ZK circuit
 * descripted by given IR
 *
 * @throws If the circuit is not satisfied
 */
export function checkProofData(zkir: string, proofData: ProofData): void {
  return ocrt.checkProofData(
    zkir,
    proofData.input,
    proofData.output,
    proofData.publicTranscript,
    proofData.privateTranscriptOutputs,
  );
}

/**
 * The results of the call to a Compact circuit
 */
export interface CircuitResults<T, U> {
  /**
   * The primary result, as returned from Compact
   */
  result: U;
  /**
   * The data required to prove this circuit run
   */
  proofData: ProofData;
  /**
   * The updated context after the circuit execution, that can be used to
   * inform further runs
   */
  context: CircuitContext<T>;
}

/**
 * Passed to the constructor of a contract. Used to compute the contract's initial ledger state.
 */
export interface ConstructorContext<T> {
  /**
   * The private state we would like to use to execute the contract's constructor.
   */
  initialPrivateState: T;
  /**
   * An initial (usually empty) Zswap local state to use to execute the contract's constructor.
   */
  initialZswapLocalState: EncodedZswapLocalState;
}

/**
 * Creates a new {@link ConstructorContext} with the given initial private state and an empty Zswap local state.
 *
 * @param initialPrivateState The private state to use to execute the contract's constructor.
 * @param coinPublicKey The Zswap coin public key of the user executing the contract.
 */
export const constructorContext = <T>(initialPrivateState: T, coinPublicKey: ocrt.CoinPublicKey): ConstructorContext<T> => ({
  initialPrivateState,
  initialZswapLocalState: emptyZswapLocalState(coinPublicKey),
});

/**
 * The result of executing a contract constructor.
 */
export interface ConstructorResult<T> {
  /**
   * The contract's initial ledger (public state).
   */
  currentContractState: ocrt.ContractState;
  /**
   * The contract's initial private state. Potentially different from the private state passed in {@link ConstructorContext}.
   */
  currentPrivateState: T;
  /**
   * The contract's initial Zswap local state. Potentially includes outputs created in the contract's constructor.
   */
  currentZswapLocalState: EncodedZswapLocalState;
}

/**
 * A runtime representation of a type in Compact
 */
export interface CompactType<a> {
  /**
   * The field-aligned binary alignment of this type.
   */
  alignment(): ocrt.Alignment;

  /**
   * Converts this type's TypeScript representation to its field-aligned binary
   * representation
   */
  toValue(value: a): ocrt.Value;

  /**
   * Converts this type's field-aligned binary representation to its TypeScript
   * representation destructively; (partially) consuming the input, and
   * ignoring superflous data for chaining.
   */
  fromValue(value: ocrt.Value): a;
}

/**
 * A point in the embedded elliptic curve. TypeScript representation of the
 * Compact type of the same name
 */
export interface CurvePoint {
  readonly x: bigint;
  readonly y: bigint;
}

/**
 * The hash value of a Merkle tree. TypeScript representation of the Compact
 * type of the same name
 */
export interface MerkleTreeDigest {
  readonly field: bigint;
}

/**
 * An entry in a Merkle path. TypeScript representation of the Compact type of
 * the same name.
 */
export interface MerkleTreePathEntry {
  readonly sibling: MerkleTreeDigest;
  readonly goes_left: boolean;
}

/**
 * A path demonstrating inclusion in a Merkle tree. TypeScript representation
 * of the Compact type of the same name.
 */
export interface MerkleTreePath<a> {
  readonly leaf: a;
  readonly path: MerkleTreePathEntry[];
}

/**
 * Runtime type of {@link CurvePoint}
 */
export class CompactTypeCurvePoint implements CompactType<CurvePoint> {
  alignment(): ocrt.Alignment {
    return [
      { tag: 'atom', value: { tag: 'field' } },
      { tag: 'atom', value: { tag: 'field' } },
    ];
  }

  fromValue(value: ocrt.Value): CurvePoint {
    const x = value.shift();
    const y = value.shift();
    if (x == undefined || y == undefined) {
      throw new CompactError('expected CurvePoint');
    } else {
      return {
        x: ocrt.valueToBigInt([x]),
        y: ocrt.valueToBigInt([y]),
      };
    }
  }

  toValue(value: CurvePoint): ocrt.Value {
    return ocrt.bigIntToValue(value.x).concat(ocrt.bigIntToValue(value.y));
  }
}

/**
 * Runtime type of {@link MerkleTreeDigest}
 */
export class CompactTypeMerkleTreeDigest implements CompactType<MerkleTreeDigest> {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'field' } }];
  }

  fromValue(value: ocrt.Value): MerkleTreeDigest {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError('expected MerkleTreeDigest');
    } else {
      return { field: ocrt.valueToBigInt([val]) };
    }
  }

  toValue(value: MerkleTreeDigest): ocrt.Value {
    return ocrt.bigIntToValue(value.field);
  }
}

/**
 * Runtime type of {@link MerkleTreePathEntry}
 */
export class CompactTypeMerkleTreePathEntry implements CompactType<MerkleTreePathEntry> {
  readonly digest: CompactTypeMerkleTreeDigest;
  readonly bool: CompactTypeBoolean;

  constructor() {
    this.digest = new CompactTypeMerkleTreeDigest();
    this.bool = new CompactTypeBoolean();
  }

  alignment(): ocrt.Alignment {
    return this.digest.alignment().concat(this.bool.alignment());
  }

  fromValue(value: ocrt.Value): MerkleTreePathEntry {
    const sibling = this.digest.fromValue(value);
    const goes_left = this.bool.fromValue(value);
    return {
      sibling: sibling,
      goes_left: goes_left,
    };
  }

  toValue(value: MerkleTreePathEntry): ocrt.Value {
    return this.digest.toValue(value.sibling).concat(this.bool.toValue(value.goes_left));
  }
}

/**
 * Runtime type of {@link MerkleTreePath}
 */
export class CompactTypeMerkleTreePath<a> implements CompactType<MerkleTreePath<a>> {
  readonly leaf: CompactType<a>;
  readonly path: CompactTypeVector<MerkleTreePathEntry>;

  constructor(n: number, leaf: CompactType<a>) {
    this.leaf = leaf;
    this.path = new CompactTypeVector(n, new CompactTypeMerkleTreePathEntry());
  }

  alignment(): ocrt.Alignment {
    return this.leaf.alignment().concat(this.path.alignment());
  }

  fromValue(value: ocrt.Value): MerkleTreePath<a> {
    const leaf = this.leaf.fromValue(value);
    const path = this.path.fromValue(value);
    return {
      leaf: leaf,
      path: path,
    };
  }

  toValue(value: MerkleTreePath<a>): ocrt.Value {
    return this.leaf.toValue(value.leaf).concat(this.path.toValue(value.path));
  }
}

/**
 * Runtime type of the builtin `Field` type
 */
export class CompactTypeField implements CompactType<bigint> {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'field' } }];
  }

  fromValue(value: ocrt.Value): bigint {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError('expected Field');
    } else {
      return ocrt.valueToBigInt([val]);
    }
  }

  toValue(value: bigint): ocrt.Value {
    return ocrt.bigIntToValue(value);
  }
}

/**
 * Runtime type of an enum with a given number of entries
 */
export class CompactTypeEnum implements CompactType<number> {
  readonly maxValue: number;
  readonly length: number;

  constructor(maxValue: number, length: number) {
    this.maxValue = maxValue;
    this.length = length;
  }

  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'bytes', length: this.length } }];
  }

  fromValue(value: ocrt.Value): number {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError(`expected Enum[<=${this.maxValue}]`);
    } else {
      let res = 0;
      for (let i = 0; i < val.length; i++) {
        res += (1 << (8 * i)) * val[i];
      }
      if (res > this.maxValue) {
        throw new CompactError(`expected UnsignedInteger[<=${this.maxValue}]`);
      }
      return res;
    }
  }

  toValue(value: number): ocrt.Value {
    return new CompactTypeField().toValue(BigInt(value));
  }
}

/**
 * Runtime type of the builtin `Unsigned Integer` types
 */
export class CompactTypeUnsignedInteger implements CompactType<bigint> {
  readonly maxValue: bigint;
  readonly length: number;

  constructor(maxValue: bigint, length: number) {
    this.maxValue = maxValue;
    this.length = length;
  }

  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'bytes', length: this.length } }];
  }

  fromValue(value: ocrt.Value): bigint {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError(`expected UnsignedInteger[<=${this.maxValue}]`);
    } else {
      let res = 0n;
      for (let i = 0; i < val.length; i++) {
        res += (1n << (8n * BigInt(i))) * BigInt(val[i]);
      }
      if (res > this.maxValue) {
        throw new CompactError(`expected UnsignedInteger[<=${this.maxValue}]`);
      }
      return res;
    }
  }

  toValue(value: bigint): ocrt.Value {
    return new CompactTypeField().toValue(value);
  }
}

/**
 * Runtime type of the builtin `Vector` types
 */
export class CompactTypeVector<a> implements CompactType<a[]> {
  readonly length: number;
  readonly type: CompactType<a>;

  constructor(length: number, type: CompactType<a>) {
    this.length = length;
    this.type = type;
  }

  alignment(): ocrt.Alignment {
    const inner = this.type.alignment();
    let res: ocrt.Alignment = [];
    for (let i = 0; i < this.length; i++) {
      res = res.concat(inner);
    }
    return res;
  }

  fromValue(value: ocrt.Value): a[] {
    const res = [];
    for (let i = 0; i < this.length; i++) {
      res.push(this.type.fromValue(value));
    }
    return res;
  }

  toValue(value: a[]): ocrt.Value {
    if (value.length != this.length) {
      throw new CompactError(`expected ${this.length}-element array`);
    }
    let res: ocrt.Value = [];
    for (let i = 0; i < this.length; i++) {
      res = res.concat(this.type.toValue(value[i]));
    }
    return res;
  }
}

/**
 * Runtime type of the builtin `Boolean` type
 */
export class CompactTypeBoolean implements CompactType<boolean> {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'bytes', length: 1 } }];
  }

  fromValue(value: ocrt.Value): boolean {
    const val = value.shift();
    if (val == undefined || val.length > 1 || (val.length == 1 && val[0] != 1)) {
      throw new CompactError('expected Boolean');
    }
    return val.length == 1;
  }

  toValue(value: boolean): ocrt.Value {
    if (value) {
      return [new Uint8Array([1])];
    } else {
      return [new Uint8Array(0)];
    }
  }
}

/**
 * Runtime type of the builtin `Bytes` types
 */
export class CompactTypeBytes implements CompactType<Uint8Array> {
  readonly length: number;

  constructor(length: number) {
    this.length = length;
  }

  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'bytes', length: this.length } }];
  }

  fromValue(value: ocrt.Value): Uint8Array {
    const val = value.shift();
    if (val == undefined || val.length > this.length) {
      throw new CompactError(`expected Bytes[${this.length}]`);
    }
    if (val.length == this.length) {
      return val;
    }
    const res = new Uint8Array(this.length);
    res.set(val, 0);
    return res;
  }

  toValue(value: Uint8Array): ocrt.Value {
    let end = value.length;
    while (end > 0 && value[end - 1] == 0) {
      end -= 1;
    }
    return [value.slice(0, end)];
  }
}

/**
 * Runtime type of `Opaque["Uint8Array"]`
 */
export class CompactTypeOpaqueUint8Array implements CompactType<Uint8Array> {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'compress' } }];
  }

  fromValue(value: ocrt.Value): Uint8Array {
    return value.shift() as Uint8Array;
  }

  toValue(value: Uint8Array): ocrt.Value {
    return [value];
  }
}

/**
 * Runtime type of `Opaque["string"]`
 */
export class CompactTypeOpaqueString implements CompactType<string> {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'compress' } }];
  }

  fromValue(value: ocrt.Value): string {
    return new TextDecoder('utf-8').decode(value.shift());
  }

  toValue(value: string): ocrt.Value {
    return [new TextEncoder().encode(value)];
  }
}

/**
 * An error originating from code generated by the Compact compiler
 */
export class CompactError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = 'CompactError';
  }
}

/**
 * Compiler internal for assertions
 * @internal
 */
export function assert(b: boolean, s: string): void {
  if (!b) {
    const msg = `failed assert: ${s}`;
    throw new CompactError(msg);
  }
}

/**
 * Compiler internal for type errors
 * @internal
 */
export function type_error(who: string, what: string, where: string, type: string, x: any): never {
  const msg = `type error: ${who} ${what} at ${where}; expected value of type ${type} but received ${inspect(x)}`;
  throw new CompactError(msg);
}

/**
 * Compiler internal for typecasts
 * @internal
 */
export function convert_bigint_to_Uint8Array(n: number, x: bigint): Uint8Array {
  const x_0 = x;
  const a = new Uint8Array(n);
  // counting on new Uint8Array setting all elements to zero; those not set by the
  // intentionally left with a value of zero
  for (let i = 0; i < n; i++) {
    a[i] = Number(x & 0xffn);
    x = x / 0x100n;
    if (x == 0n) return a;
  }
  const msg = `range error: ${x_0} cannot be decomposed into ${n} bytes`;
  throw new CompactError(msg);
}

/**
 * Compiler internal for typecasts
 * @internal
 */
export function convert_Uint8Array_to_bigint(n: number, a: Uint8Array): bigint {
  let x = 0n;
  for (let i = n - 1; i >= 0; i -= 1) {
    x = x * 0x100n + BigInt(a[i]);
  }
  if (x > MAX_FIELD) {
    const msg = `range error: ${x} is greater than maximum for the field ${MAX_FIELD}`;
    throw new CompactError(msg);
  }
  return x;
}

/**
 * Field addition
 * returns the result of adding x and y, wrapping if necessary
 * x and y are assumed to be values in the range [0, FIELD_MODULUS)
 */
export function addField(x: bigint, y: bigint): bigint {
  const t = x + y;
  // effectively mod(x + y, FIELD_MODULUS) for x and y in the assumed range
  // (x + y) % FIELD_MODULUS would also work but would likely be more expensive
  return t < FIELD_MODULUS ? t : t - FIELD_MODULUS;
}

/**
 * Field subtraction
 * returns the result of subtracting y from x, wrapping if necessary
 * x and y are assumed to be values in the range [0, FIELD_MODULUS)
 */
export function subField(x: bigint, y: bigint): bigint {
  // effectively mod(x - y, FIELD_MODULUS) for x and y in the assumed range
  // NB: JavaScript % implements remainder rather than modulus, so
  // (x - y) % FIELD_MODULUS would return an incorrect value for negative values of x - y.
  // also, any implementation involving % would likely be more expensive
  const t = x - y;
  return t >= 0 ? t : t + FIELD_MODULUS;
}

/**
 * Field multiplication
 * returns the result of multipying x and y, wrapping if necessary
 * x and y are assumed to be values in the range [0, FIELD_MODULUS)
 */
export function mulField(x: bigint, y: bigint): bigint {
  // effectively mod(x * y, FIELD_MODULUS) for x and y in the assumed range
  // (although JavaScript % implements remainder rather than modulo, remainder
  // and modulo coincide for nonnegative inputs)
  return (x * y) % FIELD_MODULUS;
}

/**
 * The following are type descriptors used to implement {@link createCoinCommitment}. They are not intended for direct
 * consumption.
 */

export const Bytes32Descriptor = new CompactTypeBytes(32);

export const MaxUint8Descriptor = new CompactTypeUnsignedInteger(18446744073709551615n, 8);

export const ShieldedCoinInfoDescriptor = {
  alignment(): ocrt.Alignment {
    return Bytes32Descriptor.alignment().concat(Bytes32Descriptor.alignment().concat(MaxUint8Descriptor.alignment()));
  },
  fromValue(value: ocrt.Value): { nonce: Uint8Array; color: Uint8Array; value: bigint } {
    return {
      nonce: Bytes32Descriptor.fromValue(value),
      color: Bytes32Descriptor.fromValue(value),
      value: MaxUint8Descriptor.fromValue(value),
    };
  },
  toValue(value: { nonce: Uint8Array; color: Uint8Array; value: bigint }): ocrt.Value {
    return Bytes32Descriptor
      .toValue(value.nonce)
      .concat(Bytes32Descriptor.toValue(value.color).concat(MaxUint8Descriptor.toValue(value.value)));
  },
};

export const ZswapCoinPublicKeyDescriptor = {
  alignment(): ocrt.Alignment {
    return Bytes32Descriptor.alignment();
  },
  fromValue(value: ocrt.Value): { bytes: Uint8Array } {
    return {
      bytes: Bytes32Descriptor.fromValue(value),
    };
  },
  toValue(value: { bytes: Uint8Array }): ocrt.Value {
    return Bytes32Descriptor.toValue(value.bytes);
  },
};

export const ContractAddressDescriptor = {
  alignment(): ocrt.Alignment {
    return Bytes32Descriptor.alignment();
  },
  fromValue(value: ocrt.Value): { bytes: Uint8Array } {
    return {
      bytes: Bytes32Descriptor.fromValue(value),
    };
  },
  toValue(value: { bytes: Uint8Array }): ocrt.Value {
    return Bytes32Descriptor.toValue(value.bytes);
  },
};

export const BooleanDescriptor = new CompactTypeBoolean();

export const ShieldedCoinRecipientDescriptor = {
  alignment(): ocrt.Alignment {
    return BooleanDescriptor
      .alignment()
      .concat(ZswapCoinPublicKeyDescriptor.alignment().concat(ContractAddressDescriptor.alignment()));
  },
  fromValue(value: ocrt.Value): { is_left: boolean; left: { bytes: Uint8Array }; right: { bytes: Uint8Array } } {
    return {
      is_left: BooleanDescriptor.fromValue(value),
      left: ZswapCoinPublicKeyDescriptor.fromValue(value),
      right: ContractAddressDescriptor.fromValue(value),
    };
  },
  toValue(value: { is_left: boolean; left: { bytes: Uint8Array }; right: { bytes: Uint8Array } }): ocrt.Value {
    return BooleanDescriptor
      .toValue(value.is_left)
      .concat(ZswapCoinPublicKeyDescriptor.toValue(value.left).concat(ContractAddressDescriptor.toValue(value.right)));
  },
};