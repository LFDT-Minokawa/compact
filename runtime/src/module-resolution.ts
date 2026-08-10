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

import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import { CircuitId } from './circuit-context.js';
import { ConformanceViolation, UnreadableSignature } from './conformance.js';
import { CompactError } from './error.js';
import { VerifierKeyHash } from './verifier-key-hash.js';

/**
 * The reason a call could not be bound to an implementation. Raised by the runtime, never
 * constructed by an application. A payload rather than an error subclass, so it survives an
 * application re-throwing through its own error type.
 */
export type ModuleResolutionFailure =
  /** The circuit context carries no module provider. */
  | { readonly kind: 'ModuleProviderAbsent' }
  /** The contract type declares the called circuit `pure`, so it has no
   *  verifier key and is never a deployed operation. */
  | { readonly kind: 'PureInterfaceCircuit' }
  /** The contract deployed at the callee's address has no operation for this
   *  circuit, or its operation carries no verifier key. */
  | { readonly kind: 'OperationAbsent' }
  /** The provider returned `undefined`: the application has no binding for this
   *  address. */
  | { readonly kind: 'UnsupportedImplementation' }
  /** `resolve` threw, or returned something that is neither a thunk nor
   *  `undefined`. A defect in the provider. */
  | { readonly kind: 'ProviderThrew'; readonly cause: unknown }
  /** The resolved module does not implement the caller's contract type.
   *  `check` names the rule that failed. */
  | ({ readonly kind: 'NonconformantImplementation' } & ConformanceViolation)
  /** The module's signatures use a type constructor this runtime doesn't know, so it can't be
   *  compared. See {@link UnreadableSignature}. */
  | ({ readonly kind: 'UnreadableModule' } & UnreadableSignature)
  /** The module's recorded fingerprint for this circuit is not a verifier key hash. A defect in the
   *  module's build. */
  | {
      readonly kind: 'MalformedVerifierKeyHash';
      readonly circuitId: CircuitId;
      /** What the module recorded, verbatim. */
      readonly recorded: string;
    }
  /** The module's verifier key hash for this circuit disagrees with the deployed one. `expected` is
   *  absent when the module has no `expectedVk` entry for the circuit. */
  | {
      readonly kind: 'ImplementationMismatch';
      readonly circuitId: CircuitId;
      readonly expected?: VerifierKeyHash;
      readonly actual: VerifierKeyHash;
    }
  /** Awaiting the thunk rejected; `cause` is what it rejected with. */
  | { readonly kind: 'ModuleLoadRejected'; readonly cause: unknown };

/** Which call failed, and through which contract type. */
export type ModuleResolutionContext = {
  readonly calleeAddress: ocrt.ContractAddress;
  readonly calleeCircuitId: CircuitId;
  /** The caller's local name for the contract type. Nothing on the callee's side is matched against
   *  it, since it has no name to offer. */
  readonly interfaceName: string;
  readonly callerAddress: ocrt.ContractAddress;
};

const describeConformance = (failure: ConformanceViolation): string => {
  switch (failure.check) {
    case 'Existence':
      return `it does not implement circuit '${failure.circuitId}'`;
    case 'Purity':
      return `circuit '${failure.circuitId}' is declared pure but is not implemented pure`;
    case 'Provability':
      return `circuit '${failure.circuitId}' is declared impure but is not among the module's provable circuits`;
    case 'Arity':
      return `circuit '${failure.circuitId}' takes a different number of arguments`;
    case 'ArgumentType':
      return `circuit '${failure.circuitId}' argument ${failure.argumentIndex} has a different type`;
    case 'ResultType':
      return `circuit '${failure.circuitId}' returns a different type`;
    default: {
      const exhaustive: never = failure.check;
      throw new CompactError(`unhandled conformance check ${JSON.stringify(exhaustive)}`);
    }
  }
};

const describeFailure = (failure: ModuleResolutionFailure): string => {
  switch (failure.kind) {
    case 'ModuleProviderAbsent':
      return 'the circuit context carries no module provider';
    case 'PureInterfaceCircuit':
      return 'the contract type declares this circuit pure, so it is not a deployed operation';
    case 'OperationAbsent':
      return 'the deployed contract has no operation for this circuit, or its operation carries no verifier key';
    case 'UnsupportedImplementation':
      return 'the module provider has no binding for this address';
    case 'ProviderThrew':
      return 'the module provider threw, or returned something that is neither a thunk nor undefined';
    case 'NonconformantImplementation':
      return `the resolved module does not implement the contract type: ${describeConformance(failure)}`;
    case 'UnreadableModule':
      return (
        `it uses a type constructor this runtime does not know, '${failure.unreadableTag}', in ` +
        (failure.argumentIndex === undefined
          ? `the result type of circuit '${failure.circuitId}'`
          : `argument ${failure.argumentIndex} of circuit '${failure.circuitId}'`) +
        '; the module was probably built by a newer compiler'
      );
    case 'MalformedVerifierKeyHash':
      return (
        `the module records '${failure.recorded}' as the verifier key fingerprint for circuit ` +
        `'${failure.circuitId}', which is not 64 lowercase hex digits`
      );
    case 'ImplementationMismatch':
      return failure.expected === undefined
        ? `the resolved module carries no verifier key fingerprint for circuit '${failure.circuitId}', ` +
            `but the deployed contract's is '${failure.actual}'`
        : `the verifier key for circuit '${failure.circuitId}' is '${failure.expected}' in the resolved ` +
            `module but '${failure.actual}' on chain`;
    case 'ModuleLoadRejected':
      return 'loading the resolved module rejected';
    default: {
      const exhaustive: never = failure;
      throw new CompactError(`unhandled resolution failure ${JSON.stringify(exhaustive)}`);
    }
  }
};

/** A cross-contract call that could not be bound to an implementation. Switch on `failure.kind`. */
export class ModuleResolutionError extends CompactError {
  readonly isModuleResolutionError = true;

  constructor(
    readonly context: ModuleResolutionContext,
    readonly failure: ModuleResolutionFailure,
  ) {
    super(
      `Cross-contract call from '${context.callerAddress}' to '${context.calleeCircuitId}' at ` +
        `'${context.calleeAddress}' through contract type '${context.interfaceName}' could not be bound ` +
        `to an implementation: ${describeFailure(failure)}.`,
    );
    this.name = 'ModuleResolutionError';
  }

  /** Recognizes instances across copies of the package; see {@link CompactError.is} for why. */
  static is(u: unknown): u is ModuleResolutionError {
    return typeof u === 'object' && u !== null && (u as { isModuleResolutionError?: unknown }).isModuleResolutionError === true;
  }
}
