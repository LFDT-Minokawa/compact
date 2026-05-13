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

type PrimitiveType = BooleanType | FieldType | UintType | BytesType | OpaqueType | VectorType | TupleType;

interface BooleanType {
    'type-name': 'Boolean';
}

interface FieldType {
    'type-name': 'Field';
}

interface UintType {
    'type-name': 'Uint';
    maxval: number;
}

interface BytesType {
    'type-name': 'Bytes';
    length: number;
}

interface OpaqueType {
    'type-name': 'Opaque';
    tsType: 'string' | 'Uint8Array';
}

interface VectorType {
    'type-name': 'Vector';
    length: number;
    type: OrdinaryType;
}

interface TupleType {
    'type-name': 'Tuple';
    types: OrdinaryType[];
}

/** Program defined type */
export type ProgramDefinedType = EnumType | StructType;

interface EnumType {
    'type-name': 'Enum';
    name: string;
    elements: string[];
}

interface StructType {
    'type-name': 'Struct';
    name: string;
    elements: {
        name: string;
        type: OrdinaryType;
    }[];
}

export type OrdinaryType = PrimitiveType | ProgramDefinedType;

interface Argument {
    name: string;
    type: OrdinaryType;
}

/** Circuit entry from contract-info.json */
export interface ContractInfoCircuit {
    name: string;
    pure: boolean;
    proof: boolean;
    arguments: Argument[];
    'result-type': OrdinaryType;
}

/** Ledger entry from contract-info.json — discriminated by `storage`. */
export type ContractInfoLedger =
    | LedgerCell
    | LedgerCounter
    | LedgerSet
    | LedgerList
    | LedgerMap
    | LedgerMerkleTree
    | LedgerHistoricMerkleTree;

interface LedgerEntryBase {
    name: string;
    index: number | number[];
    exported: boolean;
}

interface LedgerCell extends LedgerEntryBase {
    storage: 'Cell';
    type: OrdinaryType;
}

interface LedgerCounter extends LedgerEntryBase {
    storage: 'Counter';
}

interface LedgerSet extends LedgerEntryBase {
    storage: 'Set';
    type: OrdinaryType;
}

interface LedgerList extends LedgerEntryBase {
    storage: 'List';
    type: OrdinaryType;
}

interface LedgerMap extends LedgerEntryBase {
    storage: 'Map';
    key: OrdinaryType;
    /** Map value may be a nested ADT (Cell/Counter/Set/List/Map/MerkleTree/HistoricMerkleTree) or an OrdinaryType. */
    value: OrdinaryType | LedgerAdtType;
}

interface LedgerMerkleTree extends LedgerEntryBase {
    storage: 'MerkleTree';
    depth: number;
    type: OrdinaryType;
}

interface LedgerHistoricMerkleTree extends LedgerEntryBase {
    storage: 'HistoricMerkleTree';
    depth: number;
    type: OrdinaryType;
}

export type LedgerAdtType =
    | { 'type-name': 'Cell'; type: OrdinaryType }
    | { 'type-name': 'Counter' }
    | { 'type-name': 'Set'; type: OrdinaryType }
    | { 'type-name': 'List'; type: OrdinaryType }
    | { 'type-name': 'Map'; key: OrdinaryType; value: OrdinaryType | LedgerAdtType }
    | { 'type-name': 'MerkleTree'; depth: number; type: OrdinaryType }
    | { 'type-name': 'HistoricMerkleTree'; depth: number; type: OrdinaryType };

/** Structure of contract-info.json */
export interface ContractInfo {
    'compiler-version': string;
    'language-version': string;
    'runtime-version': string;
    circuits: ContractInfoCircuit[];
    witnesses: unknown[];
    contracts: unknown[];
    ledger: ContractInfoLedger[];
}
