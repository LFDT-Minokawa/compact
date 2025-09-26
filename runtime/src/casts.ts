import { CompactError } from './error';
import { MAX_FIELD } from './constants';

/**
 * Compiler internal for typecasts
 * @internal
 */
export function convert_bigint_to_Uint8Array(n: number, x: bigint): Uint8Array {
  const x_0 = x;
  const a = new Uint8Array(n);
  // counting on new Uint8Array setting all elements to zero; those not set by the
  // intentionally left with a value of zero
  for (let i = 0; i < n; i++) {
    a[i] = Number(x & 0xffn);
    x /= 0x100n;
    if (x === 0n) return a;
  }
  const msg = `range error: ${x_0} cannot be decomposed into ${n} bytes`;
  throw new CompactError(msg);
}

/**
 * Compiler internal for typecasts
 * @internal
 */
export function convert_Uint8Array_to_bigint(n: number, a: Uint8Array): bigint {
  let x = 0n;
  for (let i = n - 1; i >= 0; i -= 1) {
    x = x * 0x100n + BigInt(a[i]);
  }
  if (x > MAX_FIELD) {
    const msg = `range error: ${x} is greater than maximum for the field ${MAX_FIELD}`;
    throw new CompactError(msg);
  }
  return x;
}
