<<<<<<< HEAD
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
=======
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

export * from './version.js';
export * from './compact-types.js';
export * from './built-ins.js';
export * from './casts.js';
export * from './error.js';
export * from './constants.js';
export * from './zswap.js';
export * from './constructor-context.js';
export * from './circuit-context.js';
export * from './proof-data.js';
export * from './witness.js';
export * from './contract-dependencies.js';
export * from './utils.js';
>>>>>>> main

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
<<<<<<< HEAD
  ShieldedCoinInfo,
  QualifiedShieldedCoinInfo,
=======
  CoinInfo,
  QualifiedCoinInfo,
>>>>>>> main
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
<<<<<<< HEAD
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
=======
  DomainSeperator,
  valueToBigInt,
  bigIntToValue,
  maxAlignedSize,
  coinCommitment,
  leafHash,
  NetworkId,
  sampleContractAddress,
  sampleTokenType,
>>>>>>> main
  sampleSigningKey,
  signData,
  signatureVerifyingKey,
  verifySignature,
<<<<<<< HEAD
  encodeRawTokenType,
  decodeRawTokenType,
=======
  encodeTokenType,
  decodeTokenType,
>>>>>>> main
  encodeContractAddress,
  decodeContractAddress,
  encodeCoinPublicKey,
  decodeCoinPublicKey,
<<<<<<< HEAD
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
=======
  encodeCoinInfo,
  encodeQualifiedCoinInfo,
  decodeCoinInfo,
  decodeQualifiedCoinInfo,
  dummyContractAddress,
  tokenType,
} from '@midnight-ntwrk/onchain-runtime';

export {
  contractDependencies,
  ContractReferenceLocations,
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
} from './contract-dependencies.js';
>>>>>>> main
