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

//! The statement `stdlib/verify_proof/basic` verifies.
//!
//! Copied from `SingleScalarRelation` in midnight-ledger's
//! `zkir-v3/tests/verify_proof/e2e/harness.rs`, where it is the cheap fixture:
//! "the cheapest fixture here — prefer it whenever a case does not care which
//! relation produced its proofs."
//!
//! Proven with the Poseidon transcript the in-circuit verifier requires, into
//! `out/basic.json`.

use midnight_circuits::instructions::{AssignmentInstructions, PublicInputInstructions};
use midnight_circuits::types::AssignedNative;
use midnight_curves::Fq;
use midnight_proofs::circuit::{Layouter, Value};
use midnight_proofs::plonk;
use midnight_zk_stdlib::{Relation, ZkStdLib, ZkStdLibArch};

/// The relation the fixture's verifying key is generated from.
pub type Circuit = SingleScalarRelation;

/// The statement proven. The harness's `scalar_inner_proof` uses 123.
pub fn instance() -> Fq {
    Fq::from(123)
}

/// What the prover keeps private. This relation exposes its instance and
/// nothing else, so there is nothing to hide.
pub fn witness() {}

/// Witnesses one field element and exposes it. Deliberately unlike
/// `RsaSignatureRelation` — different architecture, and an instance of 1
/// element against RSA's 22.
#[derive(Clone, Default)]
pub struct SingleScalarRelation;

impl Relation for SingleScalarRelation {
    type Instance = Fq;
    type Witness = ();
    type Error = plonk::Error;

    fn format_instance(instance: &Fq) -> Result<Vec<Fq>, plonk::Error> {
        Ok(vec![*instance])
    }

    fn circuit(
        &self,
        std_lib: &ZkStdLib,
        layouter: &mut impl Layouter<Fq>,
        instance: Value<Fq>,
        _witness: Value<()>,
    ) -> Result<(), plonk::Error> {
        let x: AssignedNative<Fq> = std_lib.assign(layouter, instance)?;
        std_lib.constrain_as_public_input(layouter, &x)?;
        Ok(())
    }

    fn used_chips(&self) -> ZkStdLibArch {
        ZkStdLibArch::default()
    }

    fn write_relation<W: std::io::Write>(&self, _writer: &mut W) -> std::io::Result<()> {
        Ok(())
    }

    fn read_relation<R: std::io::Read>(_reader: &mut R) -> std::io::Result<Self> {
        Ok(SingleScalarRelation)
    }
}
