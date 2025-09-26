import * as ocrt from '@midnight-ntwrk/onchain-runtime';
/**
 * The maximum value representable in Compact's `Field` type
 *
 * One less than the prime modulus of the proof system's scalar field
 */
export const MAX_FIELD: bigint = ocrt.maxField();
/**
 * A valid placeholder contract address
 *
 * @deprecated Cannot handle {@link ocrt.NetworkId}s, use
 * {@link ocrt.dummyContractAddress} instead.
 */
export const DUMMY_ADDRESS: string = ocrt.dummyContractAddress();
