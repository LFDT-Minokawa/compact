import type * as ocrt from '@midnight-ntwrk/onchain-runtime';

export * from './compact-type';
export * from './built-ins';
export * from './casts';
export * from './error';
export * from './constants';
export * from './zswap';
export * from './constructor-context';
export * from './circuit-context';
export * from './proof-data';
export * from './witness';
export * from './transcript';
export * from './executables';
export * from './contract-dependencies';
export * from './version';

/**
 * Concatenates multiple {@link ocrt.AlignedValue}s
 * @internal
 */
export function alignedConcat(...values: ocrt.AlignedValue[]): ocrt.AlignedValue {
  const res: ocrt.AlignedValue = { value: [], alignment: [] };
  values.forEach((value) => {
    res.value = res.value.concat(value.value);
    res.alignment = res.alignment.concat(value.alignment);
  });
  return res;
}

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
  communicationCommitmentRandomness,
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
