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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v1';

/**
 * Encapsulates the data required to produce a zero-knowledge proof except the circuit output
 */
export interface PartialProofData {
  /**
   * The inputs to a circuit
   */
  input: ocrt.AlignedValue;
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
 * Encapsulates the data required to produce a zero-knowledge proof
 */
export interface ProofData extends PartialProofData {
  /**
   * The outputs from a circuit
   */
  output: ocrt.AlignedValue;
}
