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
import { isEncodedContractAddress } from './utils.js';
import { CompactError } from './error.js';
import { CompactType } from './compact-types.js';
import { EncodedContractAddress } from './zswap.js';

/**
 * A data structure indicating that the current {@link CompactValue} being explored is a contract reference. When this
 * type is recognized, the current {@link CompactValue} should be a {@link ContractAddress}, and the address is added to
 * the dependency set.
 */
export type SparseCompactContractAddress = {
  tag: 'contractAddress';
};

/**
 * A data structure indicating the locations of contract references in a Compact struct.
 */
export type SparseCompactStruct = {
  tag: 'struct';
  /**
   * A data structure indicating the locations of contract references in the elements of a Compact struct. The keys of
   * the record correspond to fields of the Compact struct that contain contract references. We use the keys of the record
   * to explore the elements of the corresponding {@link CompactStruct}.
   */
  elements: Record<string, SparseCompactType>;
};

/**
 * A data structure indicating the locations of contract references in a Compact vector.
 */
export type SparseCompactVector = {
  tag: 'vector';
  /**
   * A data structure indicating the locations of contract references in the elements of a Compact vector.
   */
  sparseType: SparseCompactType;
};

/**
 * A data structure indicating the locations of contract references in a Compact struct, vector, or (the terminating case)
 * a contract address.
 */
export type SparseCompactType = SparseCompactVector | SparseCompactStruct | SparseCompactContractAddress;

/**
 * A TypeScript representation of a Compact vector that contains a contract address.
 */
type CompactVector = CompactValue[];

/**
 * A TypeScript representation of a Compact struct that contains a contract address.
 */
type CompactStruct = { [key: string]: CompactValue };

/**
 * A TypeScript representation of a Compact value that contains a contract address. Currently, the only Compact values
 * that can contain a contract address are contract addresses themselves, `Vector`s, and `struct`s.
 */
type CompactValue = EncodedContractAddress | CompactVector | CompactStruct;

/**
 * Tests whether the input value is a {@link CompactVector}.
 *
 * @param x The value that is tested to be a {@link CompactVector}.
 */
function isCompactVector(x: unknown): x is CompactVector {
  return Array.isArray(x) && x.every((element) => isCompactValue(element));
}

/**
 * Tests whether the input value is a {@link CompactStruct}.
 *
 * @param x The value that is tested to be a {@link CompactStruct}.
 */
function isCompactStruct(x: unknown): x is CompactStruct {
  return (
    typeof x === 'object' &&
    x !== null &&
    x !== undefined &&
    Object.entries(x).every(([key, value]) => typeof key === 'string' && isCompactValue(value))
  );
}

/**
 * Tests whether the input value is a {@link CompactValue}.
 *
 * @param x The value that is tested to be a {@link CompactValue}.
 */
function isCompactValue(x: unknown): x is CompactValue {
  return isEncodedContractAddress(x) || isCompactVector(x) || isCompactStruct(x);
}

const expectedValueError = (expected: string, actual: unknown): void => {
  throw new CompactError(`Expected ${expected} but received ${JSON.stringify(actual)}`);
};

/**
 * Throws an error if the input value is not a {@link ContractAddress}, i.e., string.
 *
 * @param value The value that is asserted to be a {@link ContractAddress}.
 */
function assertIsContractAddress(value: CompactValue): asserts value is EncodedContractAddress {
  if (!isEncodedContractAddress(value)) {
    expectedValueError('contract address', value);
  }
}

/**
 * Throws an error if the input value is not a {@link CompactVector}.
 *
 * @param value The value that is asserted to be a {@link CompactVector}.
 */
function assertIsCompactVector(value: CompactValue): asserts value is CompactVector {
  if (!isCompactVector(value)) {
    expectedValueError('vector', value);
  }
}

/**
 * Throws an error if the input value is not a {@link CompactStruct}.
 *
 * @param value The value that is asserted to be a {@link CompactStruct}.
 */
function assertIsCompactStruct(value: CompactValue): asserts value is CompactStruct {
  if (!isCompactStruct(value)) {
    expectedValueError('struct', value);
  }
}

/**
 * Throws an error if the input value is not a {@link CompactValue}.
 *
 * @param x The value that is asserted to be a {@link CompactValue}.
 */
function assertIsCompactValue(x: unknown): asserts x is CompactValue {
  if (!isCompactValue(x)) {
    expectedValueError('Compact value', x);
  }
}

/**
 * Converts an unknown TypeScript value into a {@link CompactValue}. This conversion __should__ always succeed.
 *
 * @param x The value to convert.
 */
function toCompactValue(x: unknown): CompactValue {
  assertIsCompactValue(x);
  return x;
}

/**
 * Extracts the contract addresses present in the given {@link CompactValue}.
 *
 * @param sparseCompactType A data structure indicating the locations of all contract references in the given {@link CompactValue}.
 * @param compactValue The Compact value containing contract references.
 * @param dependencies The current set of contract addresses extracted from the input ledger state.
 */
const compactValueDependencies = (
  sparseCompactType: SparseCompactType,
  compactValue: CompactValue,
  dependencies: Set<ocrt.ContractAddress>,
): void => {
  if (sparseCompactType.tag == 'contractAddress') {
    assertIsContractAddress(compactValue);
    dependencies.add(ocrt.decodeContractAddress(compactValue.bytes));
  } else if (sparseCompactType.tag == 'struct') {
    assertIsCompactStruct(compactValue);
    Object.keys(compactValue).forEach((structElementId) =>
      compactValueDependencies(sparseCompactType.elements[structElementId], compactValue[structElementId], dependencies),
    );
  } else {
    assertIsCompactVector(compactValue);
    compactValue.forEach((vectorElement) => compactValueDependencies(sparseCompactType.sparseType, vectorElement, dependencies));
  }
};

/**
 * Converts a Compact value in the on-chain runtime representation ({@link AlignedValue}) into a TypeScript ({@link CompactValue})
 * representation.
 *
 * @param descriptor The descriptor to convert a {@link AlignedValue} into a TypeScript value.
 * @param value The value to convert.
 */
const alignedValueToCompactValue = (descriptor: CompactType<unknown>, { value }: ocrt.AlignedValue): CompactValue =>
  toCompactValue(descriptor.fromValue(value));

/**
 * Converts a {@link StateValue} into a {@link CompactValue} by treating the state as a `Cell` ADT containing a Compact value.
 *
 * @param descriptor The descriptor used to convert the {@link AlignedValue} extracted from the `Cell` ADT into a TypeScript
 *                   representation of a Compact value containing a contract address.
 * @param stateValue Represents a `Cell` ADT.
 */
const stateValueToCompactValue = (descriptor: CompactType<unknown>, stateValue: ocrt.StateValue): CompactValue =>
  alignedValueToCompactValue(descriptor, stateValue.asCell());

/**
 * A data structure indicating the locations of all contract references in a Compact value.
 */
export type SparseCompactValue = {
  tag: 'compactValue';
  /**
   * A descriptor that can be used to convert an {@link AlignedValue} into a TypeScript representation of the same value.
   * This descriptor will only ever decode `struct`s or `Vector`s that contain contract addresses.
   */
  descriptor: CompactType<unknown>;
  /**
   * A data structure indicating how to navigate to the contract addresses present in the output of the above `descriptor`.
   */
  sparseType: SparseCompactType;
};

/**
 * A data structure indicating the locations of all contract references in a Compact `Cell` ADT.
 */
export type SparseCompactCellADT = {
  tag: 'cell';
  /**
   * A data structure indicating the locations of all contract references in the Compact value contained in the outer `Cell` ADT.
   */
  valueType: SparseCompactValue;
};

/**
 * A data structure indicating the locations of all contract references in a Compact `Set` ADT.
 */
export type SparseCompactSetADT = {
  tag: 'set';
  /**
   * A data structure indicating the locations of all contract references in a Compact value in the outer `Set` ADT.
   */
  valueType: SparseCompactValue;
};

/**
 * A data structure indicating the locations of all contract references in a Compact `List` ADT.
 */
export type SparseCompactListADT = {
  tag: 'list';
  /**
   * A data structure indicating the locations of all contract references in a Compact value in the outer `List` ADT.
   */
  valueType: SparseCompactValue;
};

/**
 * A data structure indicating the locations of all contract references in a Compact `Set` or `List` ADT.
 */
export type SparseCompactArrayLikeADT = SparseCompactSetADT | SparseCompactListADT;

/**
 * A data structure indicating the locations of all contract references in a Compact `Map` ADT.
 */
export type SparseCompactMapADT = {
  tag: 'map';
  /**
   * A data structure indicating the locations of all contract references in the Compact values that are the keys of the
   * outer `Map` ADT.
   */
  keyType?: SparseCompactValue;
  /**
   * A data structure indicating the locations of all contract references in the Compact entities that are the values of the
   * outer `Map` ADT. Since the values of a `Map` ADT may be either Compact values or other `Map` ADTs, we take the union
   * of the corresponding data structures.
   */
  valueType?: SparseCompactADT | SparseCompactValue;
};

/**
 * A discriminated union describing the locations of contract references in either a Compact `Cell`, `List`, `Set`, or `Map` ADT.
 */
export type SparseCompactADT = SparseCompactCellADT | SparseCompactArrayLikeADT | SparseCompactMapADT;

/**
 * Extracts the contract references contained in a Compact `Cell` ADT represented by the given {@link StateValue}.
 *
 * @param sparseCompactCellADT A data structure pointing to contract references in the Compact `Cell` ADT corresponding
 *                             to the given `state` parameter, if any exist.
 * @param state A portion of the input ledger state representing a Compact `Cell` ADT.
 * @param dependencies The current set of contract addresses extracted from the input ledger state.
 */
const compactCellDependencies = (
  sparseCompactCellADT: SparseCompactCellADT,
  state: ocrt.StateValue,
  dependencies: Set<ocrt.ContractAddress>,
): void => {
  const { sparseType, descriptor } = sparseCompactCellADT.valueType;
  compactValueDependencies(sparseType, stateValueToCompactValue(descriptor, state), dependencies);
};

/**
 * Extracts the contract references contained in a Compact `List` or `Set` ADT represented by the given {@link StateValue} array.
 *
 * @param sparseCompactArrayLikeADT A data structure pointing to contract references in the Compact `List` or `Set` ADT corresponding
 *                                  to the given `states` parameter, if any exist.
 * @param states A portion of the input ledger state representing a Compact `List` or `Set` ADT.
 * @param dependencies The current set of contract addresses extracted from the input ledger state.
 */
const compactArrayLikeADTDependencies = (
  sparseCompactArrayLikeADT: SparseCompactArrayLikeADT,
  states: ocrt.StateValue[],
  dependencies: Set<ocrt.ContractAddress>,
): void => {
  const { sparseType, descriptor } = sparseCompactArrayLikeADT.valueType;
  states.forEach((state) => compactValueDependencies(sparseType, stateValueToCompactValue(descriptor, state), dependencies));
};

/**
 * Extracts the contract references contained in a Compact `Map` ADT represented by the given {@link StateMap} object.
 *
 * @param sparseCompactMapADT A data structure pointing to contract references in the Compact `Map` ADT corresponding
 *                            to the given `stateMap` parameter, if any exist.
 * @param stateMap A portion of the input ledger state representing a Compact `Map` ADT.
 * @param dependencies The current set of contract addresses extracted from the input ledger state.
 */
const compactMapADTDependencies = (
  sparseCompactMapADT: SparseCompactMapADT,
  stateMap: ocrt.StateMap,
  dependencies: Set<ocrt.ContractAddress>,
): void => {
  const { keyType, valueType } = sparseCompactMapADT;
  stateMap.keys().forEach((key) => {
    if (keyType) {
      compactValueDependencies(keyType.sparseType, alignedValueToCompactValue(keyType.descriptor, key), dependencies);
    }
    if (valueType) {
      const value = stateMap.get(key);
      if (!value) {
        throw new CompactError(`State map ${stateMap.toString(false)} contains key without corresponding value`);
      }
      // Maps are the only ADT that can contain other ADTs, other maps in particular.
      if (valueType.tag == 'compactValue') {
        compactValueDependencies(valueType.sparseType, stateValueToCompactValue(valueType.descriptor, value), dependencies);
      } else {
        compactADTDependencies(valueType, value, dependencies);
      }
    }
  });
};

/**
 * Throw a {@link CompactError} if the input `s` value is undefined. Called when the input {@link StateValue} could not be
 * cast to either a map, array, or boundary Merkle tree representation.
 *
 * @param s The value that is asserted to be defined.
 * @param stateValue The state on which the cast to  a map, array, or boundary Merkle tree representation was attempted.
 * @param expectedCastOutput The representation to which the input state __should__ have been cast.
 */
function assertCastSucceeded<S extends ocrt.StateMap | ocrt.StateValue[]>(
  s: S | undefined,
  stateValue: ocrt.StateValue,
  expectedCastOutput: string,
): asserts s is NonNullable<S> {
  if (!s) {
    throw new CompactError(`State ${stateValue.toString(false)} cannot be cast to a ${expectedCastOutput}`);
  }
}

/**
 * Extracts the contract references present in the ADT that the input {@link StateValue} represents. Attempts to cast the
 * input state to a different representation indicated by the input {@link SparseCompactADT}.
 *
 * @param sparseCompactADT A data structure pointing to contract references in the Compact ADT represented by the input state.
 * @param stateValue The state representing a Compact ADT.
 * @param dependencies The current set of contract addresses extracted from the input ledger state.
 */
const compactADTDependencies = (
  sparseCompactADT: SparseCompactADT,
  stateValue: ocrt.StateValue,
  dependencies: Set<ocrt.ContractAddress>,
): void => {
  if (sparseCompactADT.tag == 'cell') {
    compactCellDependencies(sparseCompactADT, stateValue, dependencies);
  } else if (sparseCompactADT.tag == 'map') {
    const stateMap = stateValue.asMap();
    assertCastSucceeded(stateMap, stateValue, 'map');
    compactMapADTDependencies(sparseCompactADT, stateMap, dependencies);
  } else if (sparseCompactADT.tag == 'list' || sparseCompactADT.tag == 'set') {
    const states = stateValue.asArray();
    assertCastSucceeded(states, stateValue, 'array');
    compactArrayLikeADTDependencies(sparseCompactADT, states, dependencies);
  }
};

/**
 * Converts a {@link StateValue} into an array of state values by calling `asArray`. Throws an error if the cast fails.
 *
 * @param state To state to convert.
 */
const castToStateArray = (state: ocrt.StateValue): ocrt.StateValue[] => {
  const ledgerState = state.asArray();
  assertCastSucceeded(ledgerState, state, 'array');
  return ledgerState;
};

/**
 * A data structure indicating the locations of all contract references in a given ledger state.
 */
export type PublicLedgerSegments = {
  tag: 'publicLedgerArray';
  /**
   * For reasonably small ledger states, the keys of the record identify locations of ADTs in the ledger state. For example,
   * if a Compact source file contains
   *
   * ```
   * contract C {};
   * struct Struct1 {
   *   a: Field;
   *   b: C;
   * }
   * ledger ls1: List[Field];
   * ledger ls2: List[C];
   * ledger ls3: Set[Struct1];
   * ```
   *
   * then the indices record will contain keys `1` and `2`, since ledger declarations `1` and `2` contain contract
   * references while ledger declaration `0` (`List[Field]`) does not.
   *
   * However, the ledger implementation has a fixed maximum length on the state arrays produced by {@link StateValue.toArray}.
   * When the number of entries in a given state exceeds the maximum, {@link StateValue.toArray} produces nested state arrays,
   * where each inner state array is within the maximum. For each nested state array, there will be a key in the indices record
   * pointing to a {@link PublicLedgerSegments} object.
   */
  indices: Record<number, PublicLedgerSegments | SparseCompactADT>;
};

/**
 * A type indicating that no contract references are present in a contract's ledger state.
 */
export type EmptyPublicLedger = {
  tag: 'publicLedgerArray';
  indices: undefined;
};

/**
 * A data structure indicating the locations of all contract references in a given ledger state. If it is a {@link EmptyPublicLedger},
 * then no contract references are present in the ledger state. If it is a {@link PublicLedgerSegments}, then contract references are
 * present and can be extracted using {@link contractDependencies}.
 */
export type ContractReferenceLocations = EmptyPublicLedger | PublicLedgerSegments;

/**
 * Extracts the contract references present in a {@link PublicLedgerSegments} by converting the given state value into
 * a state array, iterating over the entries of {@link PublicLedgerSegments.indices}, and either recurring or calling
 * {@link compactADTDependencies} with a {@link SparseCompactADT} value.
 *
 * @param publicLedgerSegments A data structure pointing to contract references in a segment of the ledger state of
 *                             the root contract.
 * @param state A segment of the ledger state of the root contract.
 * @param dependencies The current set of contract addresses extracted from the input ledger state.
 */
const publicLedgerSegmentsDependencies = (
  publicLedgerSegments: PublicLedgerSegments,
  state: ocrt.StateValue,
  dependencies: Set<ocrt.ContractAddress>,
): void => {
  const ledgerState = castToStateArray(state);
  Object.keys(publicLedgerSegments.indices)
    .map(parseInt)
    .forEach((idx) => {
      const referenceLocations = publicLedgerSegments.indices[idx];
      if ('tag' in referenceLocations && referenceLocations['tag'] === 'publicLedgerArray') {
        publicLedgerSegmentsDependencies(referenceLocations, ledgerState[idx], dependencies);
      } else {
        compactADTDependencies(referenceLocations, ledgerState[idx], dependencies);
      }
    });
};

/**
 * Given a {@link StateValue} representing the current ledger state of a contract, uses the {@link ContractReferenceLocations}
 * object produced by the Compact compiler to extract the current contract addresses present in the given ledger state. The produced
 * contract addresses represent the contracts on which the root contract depends. The dependencies are used in a multi-contract
 * setting to fetch the ledger states of all contracts on which the root contract depends prior to execution.
 *
 * NOTE: The given {@link ContractReferenceLocations} must be from the contract executable containing the ledger state constructor
 *       that produced the given {@link StateValue}.
 *
 * @param contractReferenceLocations A data structure pointing to contract references in the ledger state of the root contract.
 * @param state The current ledger state of the root contract.
 * @returns A list of all contract addresses (references) present in the given ledger state.
 *
 * @remarks The algorithm has three main stages:
 *
 *          1. It unwraps the {@link PublicLedgerSegments} in the given {@link ContractReferenceLocations} until a {@link SparseCompactADT} is reached.
 *             Each time a {@link PublicLedgerSegments} is unwrapped, it casts the current state value to a state value array and proceeds recursively with each
 *             of the state values and unwrapped ledger segments.
 *          2. It unwraps each {@link SparseCompactADT} in the current {@link PublicLedgerSegments} until a {@link SparseCompactType} is reached.
 *             Each time a {@link SparseCompactADT} is unwrapped, it casts the current state value to a state representation indicated by
 *             the {@link SparseCompactADT}.
 *          3. Once the current state can no longer be reduced, it must represent a Compact contract address somewhere inside the state,
 *             and that contract address is added to the dependency set.
 */
export const contractDependencies = (
  contractReferenceLocations: ContractReferenceLocations,
  state: ocrt.StateValue,
): ocrt.ContractAddress[] => {
  const dependencies = new Set<ocrt.ContractAddress>();
  if (contractReferenceLocations.indices) {
    publicLedgerSegmentsDependencies(contractReferenceLocations, state, dependencies);
  }
  return [...dependencies];
};
