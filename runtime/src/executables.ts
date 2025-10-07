import * as ocrt from '@midnight-ntwrk/onchain-runtime';
import {
  CircuitContext,
  CircuitId,
  CircuitResults,
  ContractId,
  copyStackFrame,
  freshStackFrame,
  restoreCircuitContext,
} from './circuit-context';
import { WitnessSets } from './witness';
import { ConstructorContext, ConstructorResult } from './constructor-context';
import { assertDefined } from './error';
import { ContractReferenceLocations, ContractReferenceLocationsSet } from './contract-dependencies';

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
  /**
   * A data structure indicating where references to other contracts exist in this contract's ledger state AND
   * all contracts on which this contract depends.
   *
   * @note For contracts that don't reference other contracts, this is an object containing one entry with contract
   *       reference locations for that contract.
   */
  readonly contractReferenceLocationsSet: ContractReferenceLocationsSet;
};

/**
 * Calls a circuit defined in another contract from the currently executing contract and returns the result.
 *
 * @param callerContext The context of the currently executing circuit.
 * @param executables The executables of the contract containing the circuit to be called.
 * @param contractId The ID of the contract to be called.
 * @param circuitId The ID of the circuit to be called in the contract to be called.
 * @param contractAddress The address of the contract to be called.
 * @param args The arguments to the circuit to be called.
 */
export const interContractCall = (
  callerContext: CircuitContext,
  executables: Executables,
  contractId: ContractId,
  circuitId: CircuitId,
  contractAddress: ocrt.ContractAddress,
  ...args: any[]
): any => {
  const impureCircuit = executables.impureCircuits[circuitId];
  assertDefined(impureCircuit, `'${circuitId}' in '${contractId}'`);
  const callerStackFrame = copyStackFrame(callerContext);
  freshStackFrame(callerContext, contractId, circuitId, contractAddress);
  const circuitResult = impureCircuit(callerContext, ...args);
  restoreCircuitContext(callerContext, circuitResult.context, callerStackFrame);
  return circuitResult.result;
};
