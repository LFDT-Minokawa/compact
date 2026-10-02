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

import * as ocrt from '@midnightntwrk/onchain-runtime-v4';

/**
 * One entry in a call's local transcript, offset-tagged against the call's public transcript:
 * `offset` is the public transcript's length at the moment the entry was recorded, so the
 * checkpoint split partitions the local transcript by the same position that partitions the
 * public one.
 *
 * The two kinds are the two kinds of checkable mark a local observation can leave. An `ops`
 * entry is a batch of Impact operations, replayed in verify mode, its `popeq`s carrying the
 * observed reads (a tree's root pin is such a batch). An `observe` entry pins a whole state
 * value - a container about to be iterated - which no Impact read expresses; the fold checks
 * it against the folding state with the VM's own content equality.
 */
export interface LocalOpsEntry {
  readonly tag: 'ops';
  readonly offset: number;
  readonly ops: ocrt.Op<ocrt.AlignedValue>[];
}

export interface LocalObserveEntry {
  readonly tag: 'observe';
  readonly offset: number;
  /** The observed value's indices under the local state root. */
  readonly path: readonly number[];
  /** The observed value, encoded. */
  readonly value: ocrt.EncodedStateValue;
}

export type LocalTranscriptEntry = LocalOpsEntry | LocalObserveEntry;

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
  /**
   * The transcript of local-state operations, offset-tagged against {@link publicTranscript}.
   * Absent until the first local operation runs, so proof data built by older generated code is
   * unaffected.
   */
  localTranscript?: LocalTranscriptEntry[];
  /**
   * Every host function result of the call, in call order: the pinned nondeterminism a
   * re-execution consumes instead of re-sampling. Absent until the first host call, so proof
   * data built by older generated code is unaffected.
   */
  hostOutputs?: ocrt.AlignedValue[];
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
