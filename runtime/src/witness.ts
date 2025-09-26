import type * as ocrt from '@midnight-ntwrk/onchain-runtime';
import type { CircuitContext, ContractId } from './circuit-context';
import { assertDefined } from './error';

/**
 * The external information accessible from within a Compact witness call.
 *
 * @typeparam L The type of the TypeScript representation of the ledger state used in a witness.
 * @typeparam PS The type of the private state updated by a witness.
 */
export interface WitnessContext<L = any, PS = any> {
  /**
   * The projected ledger state, if the transaction were to run against the ledger state as you locally see it currently.
   */
  readonly ledger: L;
  /**
   * The current private state for the contract.
   */
  readonly privateState: PS;
  /**
   * The address of the current contract.
   */
  readonly contractAddress: ocrt.ContractAddress;
}

/**
 * Internal constructor for {@link WitnessContext}.
 *
 * @typeparam L The type of the TypeScript representation of the ledger state of the contract defining the witness.
 * @typeparam PS The type of the private state updated by the witness.
 *
 * @internal
 */
export const createWitnessContext = <L = any, PS = any>(
  ledger: L,
  privateState: PS,
  contractAddress: ocrt.ContractAddress,
): WitnessContext<L, PS> => ({
  ledger,
  privateState,
  contractAddress,
});

/**
 * Describes a single witness - a function that accepts a witness context, an arbitrary list of parameters
 * and returns an updated private state and a result.
 */
export type Witness = (context: WitnessContext, ...rest: any[]) => readonly [any, any];

/**
 * An identifier for a witness.
 */
export type WitnessId = string;

/**
 * Describes the witness set of a single contract - an object holding functions, where each function
 * implements a witness from the Compact source file.
 */
export type Witnesses = Record<WitnessId, Witness>;

/**
 * Describes the witness sets of all contracts involved in a circuit call. Each key of the record is a contract
 * name (derived from the contract source code) and each value is the set of witnesses for that contract.
 */
export type WitnessSets = Record<ContractId, Witnesses>;

/**
 * Selects the witness specified by the contract and witness IDs.
 *
 * @param witnessSets The object containing the witness set containing the witness to read.
 * @param contractId The contract ID identifying the witness set containing the witness to read.
 * @param witnessId The witness ID of the witness to read from the witness set.
 */
export const readWitness = (witnessSets: WitnessSets, contractId: ContractId, witnessId: WitnessId): Witness => {
  const witnessSet = witnessSets[contractId];
  assertDefined(witnessSet, `witness set for contract '${contractId}'`);
  const witness = witnessSet[witnessId];
  assertDefined(witness, `witness '${witnessId}' for contract '${contractId}'`);
  return witness;
};

/**
 * Calls the witness specified by the parameters with the given arguments. Updates the current private state with the
 * updated private state produced by the witness. Returns the computed (return) value of the witness.
 *
 * @param circuitContext The context of the circuit using the witness.
 * @param ledger The TypeScript representation of the ledger state of the current contract.
 * @param witnessSets The witness set object containing all necessary witness implementations.
 * @param contractId The contract ID identifying the witness set containing the witness to call.
 * @param witnessId The witness ID of the witness to call.
 * @param args The arguments to the witness.
 */
export const callWitness = (
  circuitContext: CircuitContext,
  ledger: any,
  witnessSets: WitnessSets,
  contractId: ContractId,
  witnessId: WitnessId,
  ...args: any[]
): unknown => {
  const witness = readWitness(witnessSets, contractId, witnessId);
  const witnessContext = createWitnessContext(ledger, circuitContext.currentPrivateState, circuitContext.contractAddress);
  const [nextPrivateState, result] = witness(witnessContext, ...args);
  circuitContext.currentPrivateState = nextPrivateState;
  return result;
};
