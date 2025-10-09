import * as ocrt from '@midnight-ntwrk/onchain-runtime';
import {
  CircuitContext,
  CircuitId,
  CircuitResults,
  ContractId,
  copyStackFrame,
  freshStackFrame,
  queryLedgerState,
  restoreCircuitContext,
} from './circuit-context.js';
import { WitnessSets } from './witness.js';
import { ConstructorContext, ConstructorResult } from './constructor-context.js';
import { assertDefined } from './error.js';
import { PartialProofData } from './proof-data.js';
import { Bytes32Descriptor, ContractAddressDescriptor, MaxUint1Descriptor, MaxUint8Descriptor } from './compact-types.js';
import { ContractReferenceLocations } from './contract-dependencies.js';
import { alignedConcat } from './index.js';
import { fromHex } from './utils.js';

/**
 * The type of an impure circuit. An impure circuit is a function that accepts a circuit context and an arbitrary list of
 * parameters and returns a result and additional data used to construct a transaction.
 */
export type ImpureCircuit = (context: CircuitContext, ...args: any[]) => CircuitResults;

/**
 * An object containing implementations of impure circuits for a contract.
 */
export type ImpureCircuits = Record<CircuitId, ImpureCircuit>;

/**
 * The type of a pure circuit. A pure circuit is an arbitrary TypeScript function where the arguments and return types
 * are TypeScript representations of Compact values.
 */
export type PureCircuit = (...args: any[]) => any;

/**
 * An object containing implementations of pure circuits for a contract.
 */
export type PureCircuits = Record<CircuitId, PureCircuit>;

/**
 * The type of a circuit.
 */
export type Circuit = (context: CircuitContext, ...args: any[]) => CircuitResults;

/**
 * An object containing implementations of circuits for a contract.
 */
export type Circuits = Record<CircuitId, Circuit>;

/**
 * A contract constructor.
 */
export type StateConstructor = (context: ConstructorContext, ...params: any[]) => ConstructorResult;

/**
 * A function for converting the {@link ocrt.StateValue} representation of the contracts public state to a
 * TypeScript representation.
 */
export type LedgerStateDecoder = (state: ocrt.StateValue) => any;

/**
 * All information and executables for a compiled smart contract.
 */
export type Executables = {
  /**
   * A unique identifier for the contract.
   */
  readonly contractId: ContractId;
  /**
   * The witnesses of all contracts (with witnesses) on which this contract depends.
   */
  readonly witnessSets: WitnessSets;
  /**
   * The impure circuits of the contract.
   *
   * @note Any deployable contract will have at least one impure circuit.
   */
  readonly impureCircuits: ImpureCircuits;
  /**
   * The pure circuits of the contract.
   *
   * @note For contracts that do not define any pure circuits, this is an empty object.
   */
  readonly pureCircuits: PureCircuits;
  /**
   * The circuits of the contract.
   *
   * @note This is the union of impureCircuits and pureCircuits, and it adds a Context argument for pure circuit declarations.
   */
  readonly circuits: Circuits;
  /**
   * The contract constructor
   *
   * @note For contracts that do not define a ledger state constructor, this is the identity function.
   */
  readonly stateConstructor: StateConstructor;
  /**
   * The ledger state decoder.
   *
   * @note Any deployable contract will have a ledger state and therefore a ledger state decoder.
   */
  readonly ledgerStateDecoder: LedgerStateDecoder;
  /**
   * A data structure indicating where references to other contracts exist in this contract's ledger state.
   *
   * @note For contracts that don't reference other contracts, this is an empty object.
   */
  readonly contractReferenceLocations: ContractReferenceLocations;
};

export type EntryPointHash = string;

const sequenceNumberToValue = (sequenceNumber: bigint): ocrt.AlignedValue => ({
  value: MaxUint8Descriptor.toValue(sequenceNumber),
  alignment: MaxUint8Descriptor.alignment(),
});

const contractAddressToValue = (address: ocrt.ContractAddress): ocrt.AlignedValue => ({
  value: ContractAddressDescriptor.toValue({ bytes: ocrt.encodeContractAddress(address) }),
  alignment: ContractAddressDescriptor.alignment(),
});

const entryPointHashToValue = (hex: string): ocrt.AlignedValue => ({
  value: Bytes32Descriptor.toValue(fromHex(hex)),
  alignment: Bytes32Descriptor.alignment(),
});

/**
 * Converts a communication commitment random value from its hex representation to an aligned value.
 * Notice the `slice` call. Eventually communication commitments will be represented as `bigint`s and this won't be necessary.
 * TODO: https://shielded.atlassian.net/browse/PM-17174
 */
const communicationCommitmentToValue = (hex: string): ocrt.AlignedValue => ({
  value: Bytes32Descriptor.toValue(fromHex(hex).slice(1)),
  alignment: Bytes32Descriptor.alignment(),
});

/**
 * Called by {@link interContractCall}. Performs a 'kernel.claim_contract_call' operation. Links the proofs for the
 * execution of the caller circuit and the callee circuit.
 *
 * @param callerContext The context of the currently executing circuit.
 * @param partialProofData The proof data of the currently executing contract.
 * @param contractAddress The address of the contract that was called.
 * @param entryPointHash The hash of the entry point of the circuit that was called.
 * @param communicationCommitment The communication commitment of the circuit that was called.
 */
export const kernelClaimContractCall = (
  callerContext: CircuitContext,
  partialProofData: PartialProofData,
  contractAddress: ocrt.ContractAddress,
  entryPointHash: EntryPointHash,
  communicationCommitment: ocrt.CommunicationCommitment,
) =>
  queryLedgerState(callerContext, partialProofData, [
    { swap: { n: 0 } },
    {
      idx: {
        cached: true,
        pushPath: true,
        path: [
          {
            tag: 'value',
            value: {
              value: MaxUint1Descriptor.toValue(3n),
              alignment: MaxUint1Descriptor.alignment(),
            },
          },
        ],
      },
    },
    {
      push: {
        storage: false,
        value: ocrt.StateValue.newCell(
          alignedConcat(
            sequenceNumberToValue(callerContext.sequenceNumber),
            contractAddressToValue(contractAddress),
            entryPointHashToValue(entryPointHash),
            communicationCommitmentToValue(communicationCommitment),
          ),
        ).encode(),
      },
    },
    { push: { storage: false, value: ocrt.StateValue.newNull().encode() } },
    { ins: { cached: true, n: 2 } },
    { swap: { n: 0 } },
  ]);

/**
 * Converts a communication commitment random value from its hex representation to an aligned value.
 * Notice the `slice` call. Eventually communication commitments will be represented as `bigint`s and this won't be necessary.
 * TODO: https://shielded.atlassian.net/browse/PM-17174
 */
const communicationCommitmentRandToValue = (hex: string): ocrt.AlignedValue => ({
  value: Bytes32Descriptor.toValue(fromHex(hex).slice(1)),
  alignment: Bytes32Descriptor.alignment(),
});

/**
 * Calls a circuit defined in another contract from the currently executing contract and returns the result.
 *
 * @param callerContext The context of the currently executing circuit.
 * @param executables The executables of the contract containing the circuit to be called.
 * @param contractId The ID of the contract to be called.
 * @param circuitId The ID of the circuit to be called in the contract to be called.
 * @param contractAddress The address of the contract to be called.
 * @param partialProofData The proof data of the currently executing contract.
 * @param args The arguments to the circuit to be called.
 */
export const interContractCall = (
  callerContext: CircuitContext,
  executables: Executables,
  contractId: ContractId,
  circuitId: CircuitId,
  contractAddress: ocrt.ContractAddress,
  partialProofData: PartialProofData,
  ...args: any[]
): any => {
  const impureCircuit = executables.impureCircuits[circuitId];
  assertDefined(impureCircuit, `'${circuitId}' in '${contractId}'`);
  const callerStackFrame = copyStackFrame(callerContext);
  freshStackFrame(callerContext, contractId, circuitId, contractAddress);
  const circuitResult = impureCircuit(callerContext, ...args);
  restoreCircuitContext(callerContext, circuitResult.context, callerStackFrame);
  const calleeProofDataFrame = callerContext.proofDataTrace[callerContext.proofDataTrace.length - 1];
  assertDefined(
    calleeProofDataFrame,
    `proof data frame for circuit '${circuitId}' in '${contractId}' with address '${contractAddress}'`,
  );
  const communicationCommitment = ocrt.communicationCommitment(
    calleeProofDataFrame.input,
    calleeProofDataFrame.output,
    calleeProofDataFrame.communicationCommitmentRand,
  );
  calleeProofDataFrame.communicationCommitment = communicationCommitment;
  partialProofData.privateTranscriptOutputs.push(calleeProofDataFrame.output);
  partialProofData.privateTranscriptOutputs.push(
    communicationCommitmentRandToValue(calleeProofDataFrame.communicationCommitmentRand),
  );
  const entryPointHash = ocrt.entryPointHash(circuitId);
  kernelClaimContractCall(callerContext, partialProofData, contractAddress, entryPointHash, communicationCommitment);
  callerContext.sequenceNumber = callerContext.sequenceNumber + 1n;
  return circuitResult.result;
};
