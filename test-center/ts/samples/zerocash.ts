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

// A coin minted into one wallet's capsule, spent to a second wallet, received into its capsule and
// spent back: the ledger sees commitments, nullifiers and ciphertexts; the coins live off chain.

const KEYS = 'midnight:capsule/keys@1.0.0';
const ENCRYPTION = 'zerocash:dapp/encryption@1.0.0';

type Coin = { nonce: { bytes: Uint8Array }; opening: { bytes: Uint8Array } };

// the DApp's "encryption": the coin's two words, which the recipient's DApp splits back apart
const encrypt = (_context: unknown, _pk: Uint8Array, coin: Coin): Uint8Array => {
  const out = new Uint8Array(64);
  out.set(coin.nonce.bytes, 0);
  out.set(coin.opening.bytes, 32);
  return out;
};
const decrypt = (ciphertext: Uint8Array): Coin => ({
  nonce: { bytes: ciphertext.slice(0, 32) },
  opening: { bytes: ciphertext.slice(32, 64) },
});

class Wallet {
  readonly account = new Account();
  readonly interfaces: Record<string, runtime.HostInterface>;
  constructor(readonly secret: Uint8Array) {
    this.interfaces = { [KEYS]: { secretKey: () => this.secret }, [ENCRYPTION]: { encrypt } };
  }
  // what another wallet needs to pay this one
  get publicKey() {
    return { zk: contractCode.pureCircuits.derive_zk_public_key({ bytes: this.secret }), encryption: this.secret };
  }
}

const call = (chain: TestChain, address: any, w: Wallet, circuitId: string, args: unknown[] = []) =>
  chain.call({ module: contractCode, address, circuitId, args, account: w.account, hostInterfaces: w.interfaces });

const ledger = (chain: TestChain, address: any) => contractCode.ledger(chain.getContractStateOrThrow(address).data);
const coins = (w: Wallet, address: any): Coin[] => [...contractCode.localState(w.account.localState(address)!).coins];

test('mint, spend, receive, spend back', async () => {
  const chain = new TestChain();
  const alice = new Wallet(new Uint8Array(32).fill(1));
  const bob = new Wallet(new Uint8Array(32).fill(2));
  const { address } = await chain.deploy({ module: contractCode, args: [] });
  expect(contractCode.hostInterfaces).toEqual({ [KEYS]: ['secretKey'], [ENCRYPTION]: ['encrypt'] });

  // Alice mints twice: two distinct coins, derived from her secret and her draw counter
  await call(chain, address, alice, 'zerocash_mint');
  await call(chain, address, alice, 'zerocash_mint');
  const [first, second] = coins(alice, address);
  expect(coins(alice, address)).toHaveLength(2);
  expect(first.nonce.bytes).not.toEqual(second.nonce.bytes);

  // Alice spends the first coin to Bob: her capsule forgets it, the ledger gains a nullifier and a
  // ciphertext only Bob's DApp can use
  await call(chain, address, alice, 'spend', [bob.publicKey, first]);
  expect(coins(alice, address)).toEqual([second]);
  expect(ledger(chain, address).nullifiers.size()).toEqual(1n);
  await expect(call(chain, address, alice, 'spend', [bob.publicKey, first])).rejects.toThrow(/Not one of my coins/);

  // Bob's DApp decrypts and his capsule takes the coin in, after checking it is in the public tree
  const received = decrypt(ledger(chain, address).ciphertexts);
  await expect(call(chain, address, alice, 'receive_coin', [received])).rejects.toThrow(/not in the public tree/);
  await call(chain, address, bob, 'receive_coin', [received]);
  expect(coins(bob, address)).toEqual([received]);

  // and spends it back to Alice
  await call(chain, address, bob, 'spend', [alice.publicKey, received]);
  expect(coins(bob, address)).toEqual([]);
  expect(ledger(chain, address).nullifiers.size()).toEqual(2n);
  await call(chain, address, alice, 'receive_coin', [decrypt(ledger(chain, address).ciphertexts)]);
  expect(coins(alice, address)).toHaveLength(2);
});
