import type * as ocrt from '@midnight-ntwrk/onchain-runtime';
import { assertIsEncodedZswapLocalState, assertIsObject, EncodedZswapLocalState } from './zswap';
import { freshZswapLocalState } from './zswap';
import { CompactError } from './error';

/**
 * Passed to the constructor of a contract. Used to compute the contract's initial ledger state.
 */
export interface ConstructorContext<T = any> {
  /**
   * The private state we would like to use to execute the contract's constructor.
   */
  readonly initialPrivateState: T | undefined;
  /**
   * An initial (usually fresh) Zswap local state to use to execute the contract's constructor.
   */
  readonly initialZswapLocalState: EncodedZswapLocalState;
}

/**
 * Creates a new {@link ConstructorContext} with the given initial private state and an empty Zswap local state.
 *
 * @param initialPrivateState The private state to use to execute the contract's constructor.
 * @param coinPublicKey The Zswap coin public key of the user executing the contract.
 */
export const createConstructorContext = <T>(
  coinPublicKey: ocrt.CoinPublicKey,
  initialPrivateState?: T,
): ConstructorContext<T> => ({
  initialPrivateState,
  initialZswapLocalState: freshZswapLocalState(coinPublicKey),
});

/**
 * Predicate asserting that an arbitrary value is a valid constructor context.
 *
 * @param v A possible {@link ConstructorContext}.
 */
export function assertIsConstructorContext(v: any): asserts v is ConstructorContext {
  assertIsObject(v);
  if (!('initialPrivateState' in v)) {
    throw new CompactError("Missing 'initialPrivateState' in constructor context");
  }
  if (!('initialZswapLocalState' in v)) {
    throw new CompactError("Missing 'initialZswapLocalState' in constructor context");
  }
  assertIsEncodedZswapLocalState(v.initialZswapLocalState);
}

/**
 * The result of executing a contract constructor.
 */
export interface ConstructorResult<T = any> {
  /**
   * The contract's initial ledger (public state).
   */
  readonly currentContractState: ocrt.ContractState;
  /**
   * The contract's initial private state. Potentially different from the private state passed in {@link ConstructorContext}.
   */
  readonly currentPrivateState?: T;
  /**
   * The contract's initial Zswap local state. Potentially includes outputs created in the contract's constructor.
   */
  readonly currentZswapLocalState: EncodedZswapLocalState;
}
