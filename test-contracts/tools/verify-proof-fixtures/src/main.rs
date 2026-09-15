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

//! Builds the inner proofs the `stdlib/verify_proof/` Compact fixtures verify.
//!
//! The inner statements are midnight-zk relations, not Compact contracts, and
//! are proven with the Poseidon transcript the in-circuit verifier requires
//! rather than ZKIR's default Blake2b. This mirrors
//! `zkir-v3/tests/verify_proof/e2e/harness.rs` in midnight-ledger.
//!
//! Each run writes one self-describing bundle holding everything a verifyProof
//! fixture needs about one inner proof, and everything needed to rebuild it:
//!
//! ```json
//! {
//!     "circuit": "basic",
//!     "vkHash": "ede1c712...",
//!     "vk": "<base64>",
//!     "instance": ["123"],
//!     "proof": "<base64>"
//! }
//! ```
//!
//! Beside it goes `<circuit>.verifier`, the same key as raw bytes, because
//! `verifyProof` names its key by pathname and reads the file at compile time.
//!
//! `vkHash` is sha256 of the decoded `vk`. Note it is *not* the `vk_hash` ZKIR
//! emits: that one is taken over the `verify_proof_vks` entry, which prefixes
//! the key with a decider byte. This one identifies the bundle, so a test can
//! check the `.verifier` the contract names is the key the proof was made
//! against. `instance` is the statement's public inputs, as decimal field
//! elements in the order the contract passes them to verifyProof.
//!
//! The relations live in `src/proofs/`, one module each, and every one is
//! rebuilt on each run: they are cheap, and a stale bundle is worse than the
//! seconds it costs to redo them.

use std::env;
use std::fs;
use std::io::BufReader;
use std::path::{Path, PathBuf};
use std::time::Instant;

use base64::engine::general_purpose::STANDARD as BASE64;
use base64::Engine;
use ff::PrimeField;
use midnight_circuits::hash::poseidon::PoseidonState;
use midnight_curves::{Bls12, Fq};
use midnight_proofs::poly::kzg::params::ParamsKZG;
use midnight_proofs::utils::SerdeFormat;
use midnight_zk_stdlib::{optimal_k, prove, setup_pk, setup_vk, Relation};
use rand::SeedableRng;
use rand_chacha::ChaCha20Rng;
use sha2::Digest;

mod proofs;

/// A deterministic RNG, so a regenerated fixture differs only when the
/// statement does.
const RNG_SEED: [u8; 32] = [7; 32];

/// Floor on the SRS a statement uses. `optimal_k` can report less than the
/// smallest params file on disk; an oversized domain is harmless, a missing
/// file is not. Matches the ledger harness's `MIN_SRS_K`.
const MIN_SRS_K: u32 = 10;

/// Reads the midnight SRS for `k`, the way `transient_crypto::ParamsProver`
/// does: `$MIDNIGHT_PP/bls_midnight_2p{k}`, falling back to the shared cache.
fn read_srs(k: u32) -> ParamsKZG<Bls12> {
    let dir = env::var("MIDNIGHT_PP").unwrap_or_else(|_| {
        let home = env::var("HOME").unwrap_or_default();
        format!("{home}/.cache/midnight/zk-params")
    });
    let path = format!("{dir}/bls_midnight_2p{k}");
    let file = fs::File::open(&path)
        .unwrap_or_else(|error| panic!("SRS {path} could not be opened: {error}"));

    ParamsKZG::read_custom(
        &mut BufReader::new(file),
        SerdeFormat::RawBytesUnchecked,
    )
    .unwrap_or_else(|error| panic!("SRS {path} could not be read: {error}"))
}

/// A field element as the decimal string the Compact runtime takes for a
/// `Field` argument.
fn field_to_decimal(value: &Fq) -> String {
    let mut repr = value.to_repr().as_ref().to_vec();
    repr.reverse();

    let mut digits = vec![0u32];

    for byte in repr {
        let mut carry = u32::from(byte);

        for digit in digits.iter_mut() {
            let acc = *digit * 256 + carry;
            *digit = acc % 1_000_000_000;
            carry = acc / 1_000_000_000;
        }

        while carry > 0 {
            digits.push(carry % 1_000_000_000);
            carry /= 1_000_000_000;
        }
    }

    let mut out = digits.pop().expect("at least one limb").to_string();

    while let Some(limb) = digits.pop() {
        out.push_str(&format!("{limb:09}"));
    }

    out
}

fn write_bundle(out_file: &Path, circuit: &str, vk_blob: &[u8], proof: &[u8], pis: &[Fq]) {
    if let Some(parent) = out_file.parent() {
        fs::create_dir_all(parent).expect("create fixture output directory");
    }

    let vk_hash = sha2::Sha256::digest(vk_blob);
    let vk_hash_hex: String = vk_hash.iter().map(|byte| format!("{byte:02x}")).collect();
    let instance = pis
        .iter()
        .map(|pi| format!("\"{}\"", field_to_decimal(pi)))
        .collect::<Vec<_>>()
        .join(", ");

    let bundle = format!(
        "{{\n    \"circuit\": \"{circuit}\",\n    \"vkHash\": \"{vk_hash_hex}\",\n    \"vk\": \"{vk}\",\n    \"instance\": [{instance}],\n    \"proof\": \"{proof}\"\n}}\n",
        vk = BASE64.encode(vk_blob),
        proof = BASE64.encode(proof),
    );

    fs::write(out_file, bundle).expect("write inner proof bundle");

    // The same key again, as bytes rather than base64: `verifyProof` names its
    // key by pathname and reads the file during macro expansion, so the
    // compiler needs it on disk. Bare `SerdeFormat::Processed` with no tagged
    // envelope -- a key from midnight-zk carries no version tag, which is the
    // case `inner_vk_from_verifier_key` takes untagged.
    let vk_file = out_file.with_extension("verifier");
    fs::write(&vk_file, vk_blob).expect("write inner verifying key");

    println!("vk hash  : {vk_hash_hex}");
    println!("vk bytes : {}", vk_blob.len());
    println!("proof    : {} bytes", proof.len());
    println!("instance : {} public input(s)", pis.len());
    println!("written  : {}", out_file.display());
    println!("key      : {}", vk_file.display());
}

pub(crate) fn generate<R: Relation + Default>(
    circuit: &str,
    out_dir: &Path,
    instance: &R::Instance,
    witness: R::Witness,
) where
    R::Error: std::fmt::Debug,
{
    let relation = R::default();
    let k = optimal_k(&relation).max(MIN_SRS_K);
    println!("circuit: {circuit}, k = {k}");

    let srs = read_srs(k);
    let vk = setup_vk(&srs, &relation);
    let pk = setup_pk(&relation, &vk);

    let mut vk_blob = Vec::new();
    vk.write(&mut vk_blob, SerdeFormat::Processed)
        .expect("serialize inner vk");

    let started = Instant::now();
    let proof = prove::<R, PoseidonState<Fq>>(
        &srs,
        &pk,
        &relation,
        instance,
        witness,
        ChaCha20Rng::from_seed(RNG_SEED),
    )
    .expect("inner prove");
    println!("proved in {:.1?}", started.elapsed());

    let pis = R::format_instance(instance).expect("format instance");

    write_bundle(
        &out_dir.join(format!("{circuit}.json")),
        circuit,
        &vk_blob,
        &proof,
        &pis,
    );
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() > 2 {
        eprintln!("usage: verify-proof-fixtures [out-dir]");
        std::process::exit(2);
    }

    let out_dir = args.get(1).map(PathBuf::from).unwrap_or_else(|| {
        Path::new(env!("CARGO_MANIFEST_DIR")).join("out")
    });

    proofs::generate_all(&out_dir);
}
