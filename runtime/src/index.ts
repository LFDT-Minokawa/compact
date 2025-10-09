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
  CoinInfo,
  QualifiedCoinInfo,
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
  DomainSeperator,
  valueToBigInt,
  bigIntToValue,
  maxAlignedSize,
  coinCommitment,
  leafHash,
  NetworkId,
  sampleContractAddress,
  sampleTokenType,
  sampleSigningKey,
  signData,
  signatureVerifyingKey,
  verifySignature,
  encodeTokenType,
  decodeTokenType,
  encodeContractAddress,
  decodeContractAddress,
  encodeCoinPublicKey,
  decodeCoinPublicKey,
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
