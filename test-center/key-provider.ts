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
  KeyMaterialProvider as KeyMaterialProviderV3,
  ProvingKeyMaterial,
  check as checkV3,
  jsonIrToBinary as jsonIrToBinaryV3
} from '@midnightntwrk/zkir-v3';
import { ProofData } from '@midnight-ntwrk/compact-runtime';
import { proofDataIntoSerializedPreimage } from '@midnightntwrk/onchain-runtime-v4';
import fs from 'fs/promises';
import path from 'path';

const FILE_COIN_URL = 'https://midnight-s3-fileshare-dev-eu-west-1.s3.eu-west-1.amazonaws.com/bls_filecoin_2p';
const ZKIR_DIR = 'zkir';
const ZKIR_EXT = '.zkir';

const paramsCache: Record<number, Uint8Array> = {};

type ZkirVersion = { major: number; minor: number };

// Each supported ZKIR major version supplies its own IR encoder and proof checker.  To support a
// new version (e.g., zkir-v4), import its package above and add an entry here.
type ZkirBackend = {
  jsonIrToBinary: (json: string) => Uint8Array;
  check: (preimage: Uint8Array, provider: KeyMaterialProviderV3) => Promise<(bigint | undefined)[]>;
};

const zkirBackends: Record<number, ZkirBackend> = {
  3: { jsonIrToBinary: jsonIrToBinaryV3, check: checkV3 }
};

const readZkirJson = async (contractDir: string, circuitId: string): Promise<string> => {
  return fs.readFile(path.join(contractDir, ZKIR_DIR, circuitId + ZKIR_EXT), 'utf-8');
};

const detectZkirVersion = (json: string): ZkirVersion => {
  const v = JSON.parse(json).version;
  if (!v) {
    throw new Error(`Unable to detect ZKIR version in JSON: ${json}`);
  }
  return v;
};

const backendFor = (json: string): ZkirBackend => {
  const { major } = detectZkirVersion(json);
  const backend = zkirBackends[major];
  if (!backend) {
    throw new Error(`Unsupported ZKIR major version ${major}; supported: ${Object.keys(zkirBackends).join(', ')}`);
  }
  return backend;
};

const readIrFile = async (contractDir: string, circuitId: string): Promise<Uint8Array> => {
  const json = await readZkirJson(contractDir, circuitId);
  return backendFor(json).jsonIrToBinary(json);
};

export const createKeyMaterialProvider = (contractDir: string): KeyMaterialProviderV3 => {
  const lookupKey = async (circuitId: string): Promise<ProvingKeyMaterial | undefined> => {
    return {
      proverKey: new Uint8Array(0),
      verifierKey: new Uint8Array(0),
      ir: await readIrFile(contractDir, circuitId),
    };
  };
  const getParams = async (k: number): Promise<Uint8Array> => {
    if (k in paramsCache) {
      return paramsCache[k];
    }
    const url = `${FILE_COIN_URL}${k}`;
    const resp = await fetch(url);
    const blob = await resp.blob();
    const params = new Uint8Array(await blob.arrayBuffer());
    paramsCache[k] = params;
    return params;
  };
  return { lookupKey, getParams };
};

export const checkProofData = async (contractDir: string, circuitName: string, proofData: ProofData): Promise<(bigint | undefined)[]> => {
  const json = await readZkirJson(contractDir, circuitName);
  const preimage = proofDataIntoSerializedPreimage(proofData.input, proofData.output, proofData.publicTranscript, proofData.privateTranscriptOutputs, circuitName);
  const keyProvider = createKeyMaterialProvider(contractDir);
  return backendFor(json).check(preimage, keyProvider);
};
