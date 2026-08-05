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

// NOTE: this file is included as a test body inside a describe block by
// compiler/test.ss; it therefore has access to `contractCode`, `startContract`,
// `expect`, `test`, and `runtime` (= @midnight-ntwrk/compact-runtime) without
// explicit imports.

const MSG_LEN = 3;
const msgType = new runtime.CompactTypeVector(MSG_LEN, runtime.CompactTypeField);
const sampleMsg = (): bigint[] => [1n, 2n, 3n];

test('TypeScript signature passes in-circuit verification', async () => {
  const sk = runtime.jubjubSampleScalar();
  const pk = runtime.jubjubSchnorrVerifyingKey(sk);
  const msg = sampleMsg();

  const sig = runtime.jubjubSchnorrSign(msgType, msg, sk);

  const [c, Ctxt] = await startContract(contractCode, {}, 0);
  expect((await c.circuits.verifySchnorrN3(Ctxt, msg, sig, pk)).result).toBe(true);
});

test('Tampered signature fails in-circuit verification', async () => {
  const sk = runtime.jubjubSampleScalar();
  const pk = runtime.jubjubSchnorrVerifyingKey(sk);
  const msg = sampleMsg();

  const sig = runtime.jubjubSchnorrSign(msgType, msg, sk);
  const badSig = { ...sig, response: (sig.response + 1n) % runtime.JUBJUB_SCALAR_MODULUS };

  const [c, Ctxt] = await startContract(contractCode, {}, 0);
  expect((await c.circuits.verifySchnorrN3(Ctxt, msg, badSig, pk)).result).toBe(false);
});
