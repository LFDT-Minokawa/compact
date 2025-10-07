<<<<<<< HEAD
import * as ocrt from '@midnight-ntwrk/onchain-runtime';

/**
 * Encapsulates most of the data required to produce a zero-knowledge proof. Lacks a circuit output entry.
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

import * as ocrt from '@midnight-ntwrk/onchain-runtime';

/**
 * Encapsulates the data required to produce a zero-knowledge proof except the circuit output
>>>>>>> main
 */
export interface PartialProofData {
  /**
   * The inputs to a circuit
   */
<<<<<<< HEAD
  readonly input: ocrt.AlignedValue;
  /**
   * The public transcript of operations
   * TODO: Change this property to 'readonly' once the runtime is immutable.
=======
  input: ocrt.AlignedValue;
  /**
   * The public transcript of operations
>>>>>>> main
   */
  publicTranscript: ocrt.Op<ocrt.AlignedValue>[];
  /**
   * The transcript of the witness call outputs
   */
<<<<<<< HEAD
  readonly privateTranscriptOutputs: ocrt.AlignedValue[];
  /**
   * The communication commitment randomness used to construct the contract call corresponding to this object.
   */
  readonly communicationCommitmentRand: ocrt.CommunicationCommitmentRand;
  /**
   * The communication commitment computed from the circuit ID and circuit input and output values.
   */
  communicationCommitment?: ocrt.CommunicationCommitment;
}

/**
 * The data required to create a proof of the contract call corresponding to this object.
=======
  privateTranscriptOutputs: ocrt.AlignedValue[];
}

/**
 * Encapsulates the data required to produce a zero-knowledge proof
>>>>>>> main
 */
export interface ProofData extends PartialProofData {
  /**
   * The outputs from a circuit
   */
<<<<<<< HEAD
  readonly output: ocrt.AlignedValue;
=======
  output: ocrt.AlignedValue;
>>>>>>> main
}

/**
 * Verifies a given {@link ProofData} satisfies the constraints of a ZK circuit
<<<<<<< HEAD
 * described by given IR
=======
 * described by given IR.
>>>>>>> main
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
