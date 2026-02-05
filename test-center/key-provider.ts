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

import {
  KeyMaterialProvider,
  ProvingKeyMaterial,
  check,
  jsonIrToBinary
} from '@midnight-ntwrk/zkir-v2';
import { ProofData } from '@midnight-ntwrk/compact-runtime';
import { proofDataIntoSerializedPreimage } from '@midnight-ntwrk/onchain-runtime-v1';
import fs from 'fs/promises';
import path from 'path';

const FILE_COIN_URL = 'https://midnight-s3-fileshare-dev-eu-west-1.s3.eu-west-1.amazonaws.com/bls_filecoin_2p';
const ZKIR_DIR = 'zkir';
const ZKIR_EXT = '.zkir';

const cache: Record<number, Uint8Array> = {};

const readIrFile = (contractDir: string, circuitId: string): Promise<Uint8Array> =>
  fs.readFile(path.join(contractDir, ZKIR_DIR, circuitId + ZKIR_EXT), 'utf-8').then(jsonIrToBinary);

export const createKeyMaterialProvider = (contractDir: string): KeyMaterialProvider => {
  const lookupKey = async (circuitId: string): Promise<ProvingKeyMaterial | undefined> => {
    return {
      proverKey: new Uint8Array(0),
      verifierKey: new Uint8Array(0),
      ir: await readIrFile(contractDir, circuitId),
    };
  };
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
  return { lookupKey, getParams };
};

export const checkProofData = (contractDir: string, circuitName: string, proofData: ProofData): Promise<(bigint | undefined)[]>=> {
  const preimage = proofDataIntoSerializedPreimage(proofData.input, proofData.output, proofData.publicTranscript, proofData.privateTranscriptOutputs, circuitName);
  const keyProvider = createKeyMaterialProvider(contractDir);
  return check(preimage, keyProvider);
};
