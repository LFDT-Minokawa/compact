import * as ocrt from '@midnight-ntwrk/onchain-runtime';
import type { CircuitContext } from './circuit-context';
import { assertDefined, CompactError } from './error';
import type { Recipient } from './index';
import { Bytes32Descriptor, ShieldedCoinInfoDescriptor, ShieldedCoinRecipientDescriptor } from './runtime';

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
 * A {@link ocrt.CoinPublicKey} encoded as a byte string. This representation is used internally by the contract executable.
 */
export interface EncodedCoinPublicKey {
  /**
   * The coin public key's bytes.
   */
  readonly bytes: Uint8Array;
}

/**
 * A {@link ocrt.ContractAddress} encoded as a byte string. This representation is used internally by the contract executable.
 */
export interface EncodedContractAddress {
  /**
   * The contract address's bytes.
   */
  readonly bytes: Uint8Array;
}

/**
 * A {@link ocrt.ShieldedCoinInfo} with its fields encoded as byte strings. This representation is used internally by
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
 * A {@link ocrt.QualifiedShieldedCoinInfo} with its fields encoded as byte strings. This representation is used internally by
 * the contract executable.
 */
export interface EncodedQualifiedShieldedCoinInfo extends EncodedShieldedCoinInfo {
  /**
   * The coin's location in the chain's Merkle tree of coin commitments. Bounded to be a non-negative 64-bit integer.
   */
  readonly mt_index: bigint;
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
 * Predicate asserting that an arbitrary value is a valid struct containing `bytes`.
 *
 * @param v A possible struct containing `bytes`.
 */
export function assertIsEncodedBytes(v: any): asserts v is { bytes: Uint8Array } {
  assertIsObject(v);
  if (!('bytes' in v)) {
    throw new CompactError(`Expected 'bytes' in struct, but got ${JSON.stringify(v)}`);
  }
  if (!(v.bytes instanceof Uint8Array)) {
    throw new CompactError(`Expected 'bytes' to be a Uint8Array, but got ${JSON.stringify(v)}`);
  }
}

export function assertIsObject(v: any): asserts v is object {
  if (typeof v !== 'object' || v === null || v === undefined) {
    throw new CompactError(`Expected an object, but got ${JSON.stringify(v)}`);
  }
}

/**
 * Predicate asserting that an arbitrary value is a valid {@link EncodedRecipient}.
 *
 * @param v A possible {@link EncodedRecipient}.
 */
export function assertIsEncodedRecipient(v: any): asserts v is EncodedRecipient {
  assertIsObject(v);
  if (!('is_left' in v)) {
    throw new CompactError(`Expected 'is_left' in recipient, but got ${JSON.stringify(v)}`);
  }
  if (!('left' in v)) {
    throw new CompactError(`Expected 'left' in recipient, but got ${JSON.stringify(v)}`);
  }
  if (!('right' in v)) {
    throw new CompactError(`Expected 'right' in recipient, but got ${JSON.stringify(v)}`);
  }
  assertIsEncodedBytes(v.left);
  assertIsEncodedBytes(v.right);
}

/**
 * Predicate asserting that an arbitrary value is a valid {@link EncodedShieldedCoinInfo}.
 *
 * @param v A possible {@link EncodedShieldedCoinInfo}.
 */
export function assertIsEncodedCoinInfo(v: any): asserts v is EncodedShieldedCoinInfo {
  assertIsObject(v);
  if (!('nonce' in v)) {
    throw new CompactError(`Expected 'nonce' in coin info, but got ${JSON.stringify(v)}`);
  }
  if (!('color' in v)) {
    throw new CompactError(`Expected 'color' in coin info, but got ${JSON.stringify(v)}`);
  }
  if (!('value' in v)) {
    throw new CompactError(`Expected 'value' in coin info, but got ${JSON.stringify(v)}`);
  }
  if (!(v.nonce instanceof Uint8Array)) {
    throw new CompactError(`Expected 'nonce' to be a Uint8Array, but got ${JSON.stringify(v)}`);
  }
  if (!(v.color instanceof Uint8Array)) {
    throw new CompactError(`Expected 'color' to be a Uint8Array, but got ${JSON.stringify(v)}`);
  }
  if (typeof v.value !== 'bigint') {
    throw new CompactError(`Expected 'value' to be a bigint, but got ${JSON.stringify(v)}`);
  }
}

/**
 * Predicate asserting that an arbitrary value is a valid entry in `outputs` of {@link EncodedZswapLocalState}.
 *
 * @param v A possible valid entry in `outputs` of {@link EncodedZswapLocalState}.
 */
export function assertIsEncodedOutput(v: any): asserts v is { coinInfo: EncodedShieldedCoinInfo; recipient: EncodedRecipient } {
  assertIsObject(v);
  if (!('coinInfo' in v)) {
    throw new CompactError(`Expected 'coinInfo' in output, but got ${JSON.stringify(v)}`);
  }
  if (!('recipient' in v)) {
    throw new CompactError(`Expected 'recipient' in output, but got ${JSON.stringify(v)}`);
  }
  assertIsEncodedCoinInfo(v.coinInfo);
  assertIsEncodedRecipient(v.recipient);
}

/**
 * Predicate asserting that an arbitrary value is a valid {@link EncodedQualifiedShieldedCoinInfo}.
 *
 * @param v A possible {@link EncodedQualifiedShieldedCoinInfo}.
 */
export function assertIsEncodedQualifiedCoinInfo(v: any): asserts v is EncodedQualifiedShieldedCoinInfo {
  assertIsObject(v);
  assertIsEncodedCoinInfo(v);
  if (!('mt_index' in v)) {
    throw new CompactError(`Expected an object with 'mt_index', but got ${JSON.stringify(v)}`);
  }
  if (typeof v.mt_index !== 'bigint') {
    throw new CompactError(`Expected 'mt_index' to be a bigint, but got ${JSON.stringify(v)}`);
  }
}

/**
 * Predicate asserting that an arbitrary value is a valid {@link EncodedZswapLocalState}.
 *
 * @param v A possible {@link EncodedZswapLocalState}.
 */
export function assertIsEncodedZswapLocalState(v: any): asserts v is EncodedZswapLocalState {
  assertIsObject(v);
  if (!('coinPublicKey' in v)) {
    throw new CompactError(`Expected 'coinPublicKey' in Zswap local state, but got ${JSON.stringify(v)}`);
  }
  if (!('currentIndex' in v)) {
    throw new CompactError(`Expected 'currentIndex' in Zswap local state, but got ${JSON.stringify(v)}`);
  }
  if (!('inputs' in v)) {
    throw new CompactError(`Expected 'inputs' in Zswap local state, but got ${JSON.stringify(v)}`);
  }
  if (!('outputs' in v)) {
    throw new CompactError(`Expected 'outputs' in Zswap local state, but got ${JSON.stringify(v)}`);
  }
  assertIsEncodedBytes(v.coinPublicKey);
  if (typeof v.currentIndex !== 'bigint') {
    throw new CompactError(`Expected 'currentIndex' to be a bigint, but got ${JSON.stringify(v)}`);
  }
  if (!Array.isArray(v.inputs)) {
    throw new CompactError(`Expected 'inputs' to be an array, but got ${JSON.stringify(v)}`);
  }
  if (!Array.isArray(v.outputs)) {
    throw new CompactError(`Expected 'outputs' to be an array, but got ${JSON.stringify(v)}`);
  }
  v.inputs.forEach(assertIsEncodedQualifiedCoinInfo);
  v.outputs.forEach(assertIsEncodedOutput);
}

/**
 * Constructs a new {@link EncodedZswapLocalState} with the given coin public key. The result can be used to create a
 * {@link ConstructorContext}.
 *
 * @param coinPublicKey The Zswap coin public key of the user executing the circuit.
 */
export const freshZswapLocalState = (coinPublicKey: ocrt.CoinPublicKey): EncodedZswapLocalState => ({
  coinPublicKey: { bytes: ocrt.encodeCoinPublicKey(coinPublicKey) },
  currentIndex: 0n,
  inputs: [],
  outputs: [],
});

/**
 * Constructs a record mapping contract addresses to fresh {@link EncodedZswapLocalState}s, each with the given coin
 * public key.
 *
 * @param coinPublicKey The Zswap coin public key of the user executing the circuit.
 * @param addresses The set of contracts involved in the circuit call. For contracts that don't call other contracts,
 *                  the array has one element.
 */
export const freshZswapLocalStates = (
  coinPublicKey: ocrt.CoinPublicKey,
  addresses: ocrt.ContractAddress[],
): Record<ocrt.ContractAddress, EncodedZswapLocalState> =>
  Object.fromEntries(addresses.map((address) => [address, freshZswapLocalState(coinPublicKey)]));

/**
 * Converts an {@link Recipient} to an {@link EncodedRecipient}. Useful for testing.
 */
export const encodeRecipient = ({ is_left, left, right }: Recipient): EncodedRecipient => ({
  is_left,
  left: { bytes: ocrt.encodeCoinPublicKey(left) },
  right: { bytes: ocrt.encodeContractAddress(right) },
});

/**
 * Converts an {@link EncodedRecipient} to a {@link Recipient}.
 */
export const decodeRecipient = ({ is_left, left, right }: EncodedRecipient): Recipient => ({
  is_left,
  left: ocrt.decodeCoinPublicKey(left.bytes),
  right: ocrt.decodeContractAddress(right.bytes),
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
 * Adds a coin to the list of inputs consumed by the circuit.
 *
 * @param circuitContext The current circuit context.
 * @param qualifiedCoinInfo The input to consume.
 */
export function createZswapInput(circuitContext: CircuitContext, qualifiedCoinInfo: EncodedQualifiedShieldedCoinInfo): void {
  assertDefined(
    circuitContext.currentZswapLocalState,
    `Zswap local state for contract '${circuitContext.contractId}' with address '${circuitContext.contractAddress}'`,
  );
  circuitContext.currentZswapLocalState = {
    ...circuitContext.currentZswapLocalState,
    inputs: circuitContext.currentZswapLocalState.inputs.concat(qualifiedCoinInfo),
  };
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
export function createZswapOutput(circuitContext: CircuitContext, coinInfo: EncodedShieldedCoinInfo, recipient: EncodedRecipient): void {
  assertDefined(circuitContext.currentQueryContext, `query context for contract ${circuitContext.contractAddress}`);
  assertDefined(
    circuitContext.currentZswapLocalState,
    `Zswap local state for contract '${circuitContext.contractId}' with address '${circuitContext.contractAddress}'`,
  );
  circuitContext.currentQueryContext = circuitContext.currentQueryContext.insertCommitment(
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
export function ownPublicKey(circuitContext: CircuitContext): EncodedCoinPublicKey {
  assertDefined(
    circuitContext.currentZswapLocalState,
    `Zswap local state for contract '${circuitContext.contractId}' with address '${circuitContext.contractAddress}'`,
  );
  return circuitContext.currentZswapLocalState.coinPublicKey;
}
