import * as ocrt from '@midnight-ntwrk/onchain-runtime';

/**
 * Encapsulates most of the data required to produce a zero-knowledge proof. Lacks a circuit output entry.
 */
export interface PartialProofData {
  /**
   * The inputs to a circuit
   */
  readonly input: ocrt.AlignedValue;
  /**
   * The public transcript of operations
   * TODO: Change this property to 'readonly' once the runtime is immutable.
   */
  publicTranscript: ocrt.Op<ocrt.AlignedValue>[];
  /**
   * The transcript of the witness call outputs
   */
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
 */
export interface ProofData extends PartialProofData {
  /**
   * The outputs from a circuit
   */
  readonly output: ocrt.AlignedValue;
}

/**
 * Verifies a given {@link ProofData} satisfies the constraints of a ZK circuit
 * described by given IR
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
