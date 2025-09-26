import type * as ocrt from '@midnight-ntwrk/onchain-runtime';

/**
 * A transcript of operations and their effects, for inclusion and replay in
 * transactions
 */
export type Transcript = ocrt.Transcript<ocrt.AlignedValue>;
