// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import * as zkir_v2 from '@midnight-ntwrk/zkir-v2';
import * as zkir_v3 from '@midnight-ntwrk/zkir-v3';
import { ProofData } from '@midnight-ntwrk/compact-runtime';
import { proofDataIntoSerializedPreimage } from '@midnight-ntwrk/onchain-runtime-v1';
import fs from 'fs/promises';
import path from 'path';

const FILE_COIN_URL = 'https://midnight-s3-fileshare-dev-eu-west-1.s3.eu-west-1.amazonaws.com/bls_filecoin_2p';
const ZKIR_V2_DIR = 'zkir';
const ZKIR_V3_DIR = 'zkir-v3';
const ZKIR_EXT = '.zkir';

const cache: Record<number, Uint8Array> = {};

const readIrFile = async (contractDir: string, circuitId: string, zkirV3: boolean): Promise<Uint8Array> => {
  const fileContents = await fs.readFile(path.join(contractDir, zkirV3 ? ZKIR_V3_DIR : ZKIR_V2_DIR, circuitId + ZKIR_EXT), 'utf-8');
  return zkirV3 ? zkir_v3.jsonIrToBinary(fileContents) : zkir_v2.jsonIrToBinary(fileContents);
}

const getParams = async (k: number): Promise<Uint8Array> => {
  if (k in cache) {
    return cache[k];
  }
  const url = `${FILE_COIN_URL}${k}`;
  const resp = await fetch(url);
  const blob = await resp.blob();
  const params = new Uint8Array(await blob.arrayBuffer());
  cache[k] = params;
  return params;
};

export const createKeyMaterialProvider = (contractDir: string, zkirV3: boolean): zkir_v2.KeyMaterialProvider => {
  const lookupKey = async (circuitId: string): Promise<zkir_v2.ProvingKeyMaterial | undefined> => {
    return {
      proverKey: new Uint8Array(0),
      verifierKey: new Uint8Array(0),
      ir: await readIrFile(contractDir, circuitId, zkirV3),
    };
  };
  return { lookupKey, getParams };
};

export const checkProofDataVersioned = (contractDir: string, circuitName: string, proofData: ProofData, zkirV3: boolean): Promise<(bigint | undefined)[]> => {
  const preimage = proofDataIntoSerializedPreimage(proofData.input, proofData.output, proofData.publicTranscript, proofData.privateTranscriptOutputs, circuitName);
  const keyProvider = createKeyMaterialProvider(contractDir, zkirV3);
  return zkirV3 ? zkir_v3.check(preimage, keyProvider) : zkir_v2.check(preimage, keyProvider);
};

export const checkProofData = async (contractDir: string, circuitName: string, proofData: ProofData): Promise<void> => {
  const [v2Result, v3Result] = await Promise.all([
    checkProofDataVersioned(contractDir, circuitName, proofData, false),
    checkProofDataVersioned(contractDir, circuitName, proofData, true),
  ]);
};
