// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

import { CircuitContext, CircuitId, CircuitResults } from './circuit-context.js';
import { CircuitSignatures, DeclaredInterfaces } from './interface-descriptor.js';

/**
 * A circuit evaluable outside a transaction: no ledger access, no cross-contract call, no proof
 * obligation.
 *
 * `any[]` because parameters are contravariant: `unknown[]` accepts no real circuit and `never[]`
 * can't be called. The result is `any` to match.
 */
export type PureCircuit = (...args: any[]) => any;

/** A module's pure circuits. */
export type PureCircuits = Readonly<Record<CircuitId, PureCircuit>>;

/** A circuit that threads the circuit context and produces proof data. `any[]` per {@link PureCircuit}. */
export type ProvableCircuit = (context: CircuitContext, ...args: any[]) => Promise<CircuitResults>;

/** A module's provable circuits. */
export type ProvableCircuits = Readonly<Record<CircuitId, ProvableCircuit>>;

/**
 * An instance of a generated module's `Contract` class. Only `provableCircuits` is reachable from a
 * cross-contract call.
 */
export type ContractInstance = {
  readonly provableCircuits: ProvableCircuits;
};

/**
 * A generated module's `Contract` constructor. `witnesses` is `any` because a generated `Contract`
 * declares `constructor(witnesses: W)`, and an index signature doesn't satisfy a declared property,
 * so anything narrower makes every generated module unassignable.
 */
export type ContractCtor = new (witnesses: any) => ContractInstance;

/**
 * The exports of a generated `contract/index.js` that the runtime needs from a cross-contract
 * callee. A module missing the data exports predates dynamic resolution.
 */
export type Module = {
  readonly Contract: ContractCtor;
  /**
   * Read nowhere: a pure circuit in a contract type cannot be called, so nothing dispatches through
   * this, and it is absent from the runtime's required exports so a module need not carry one.
   * TODO: drop it, unless pure cross-contract calls are made sound — see `PureInterfaceCircuit`.
   */
  readonly pureCircuits: PureCircuits;
  /** Verifier-key fingerprints by external circuit name, compared against what is deployed. */
  readonly expectedVk: Readonly<Record<CircuitId, string>>;
  /** What this module implements. */
  readonly circuitSignatures: CircuitSignatures;
  /** The contract types this module itself calls through. */
  readonly declaredInterfaces: DeclaredInterfaces;
};
