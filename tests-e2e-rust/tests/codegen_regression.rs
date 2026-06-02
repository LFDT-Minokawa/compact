// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

//
// Codegen byte-parity regression guard.
//
// Iter 9 (commit 405be1c) restored the Scheme codegen build after Iters
// 4-6 had introduced phantom nanopass dispatches that prevented compactc
// from rebuilding. The e2e tests stayed green only because every
// fixture's `lib.rs` was hand-written / pre-generated and checked in.
// That allowed a real regression to hide in the IR-level emit logic.
//
// This test re-runs the locally-built `compactc --rust` over each
// example contract and asserts that the output is byte-identical to the
// committed `tests-e2e-rust/contracts/<dir>/lib.rs`. It is the regression
// guard that ensures future Scheme-side changes to rust-passes (or to
// the upstream nanopass IR they target) don't silently drift away from
// the checked-in expectation.
//
// Behaviour:
// - The test is **skipped with a warning** (not failed) when the
//   `compactc` binary or the `examples/*.compact` sources cannot be
//   located. This keeps CI green on builds that haven't run
//   `nix build .#compactc` yet (e.g. a Rust-only contributor running
//   `cargo test -p tests-e2e-rust` against a clean checkout). The test
//   only enforces byte-parity when the binary is genuinely available,
//   which is exactly the regression signal we want.
// - The compactc location is resolved by walking up from the test
//   crate's `CARGO_MANIFEST_DIR` looking for `./result/bin/compactc`.
//   That symlink is what `nix build .#compactc` produces at the repo
//   root. The `COMPACTC` env var overrides this if set.

use std::path::{Path, PathBuf};
use std::process::Command;

/// (source filename in examples/, contract dir under tests-e2e-rust/contracts/)
const FIXTURES: &[(&str, &str)] = &[
    ("aliases_fixture.compact", "aliases-fixture"),
    ("bounded_uint_fixture.compact", "bounded-uint-fixture"),
    ("cross_circuit_fixture.compact", "cross-circuit-fixture"),
    ("election.compact", "election"),
    ("fold_fixture.compact", "fold-fixture"),
    ("for_iter_fixture.compact", "for-iter-fixture"),
    ("for_range_fixture.compact", "for-range-fixture"),
    ("if_stmt_fixture.compact", "if-stmt-fixture"),
    ("list_fixture.compact", "list-fixture"),
    ("map_fixture.compact", "map-fixture"),
    ("sealed_ledger_fixture.compact", "sealed-ledger-fixture"),
    ("set_fixture.compact", "set-fixture"),
    ("tiny.compact", "tiny"),
    ("uints_fixture.compact", "uints-fixture"),
    ("vector_fixture.compact", "vector-fixture"),
    ("witnesses_fixture.compact", "witnesses-fixture"),
    ("zerocash.compact", "zerocash"),
];

/// Walks up from `start` looking for `./result/bin/compactc` (the nix
/// build symlink). Returns the absolute path of the repo root that
/// contains it, or `None` if not found within 6 levels.
fn find_repo_root(start: &Path) -> Option<PathBuf> {
    let mut cur = start.to_path_buf();
    for _ in 0..6 {
        if cur.join("result/bin/compactc").exists() && cur.join("examples").exists() {
            return Some(cur);
        }
        if !cur.pop() {
            break;
        }
    }
    None
}

#[test]
fn rust_codegen_byte_parity_against_committed_fixtures() {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let (compactc, repo_root): (PathBuf, PathBuf) = match std::env::var_os("COMPACTC") {
        Some(p) => {
            let path = PathBuf::from(p);
            let root = find_repo_root(&manifest).unwrap_or_else(|| manifest.clone());
            (path, root)
        }
        None => match find_repo_root(&manifest) {
            Some(root) => (root.join("result/bin/compactc"), root),
            None => {
                eprintln!(
                    "SKIP: compactc not found (no ./result/bin/compactc above {}; \
                     run `nix build .#compactc` to enable this regression guard)",
                    manifest.display()
                );
                return;
            }
        },
    };

    if !compactc.exists() {
        eprintln!(
            "SKIP: compactc binary at {} does not exist",
            compactc.display()
        );
        return;
    }

    let examples_dir = repo_root.join("examples");
    let contracts_dir = manifest.join("contracts");
    let mut drift = Vec::new();

    for (src_name, dir_name) in FIXTURES {
        let src = examples_dir.join(src_name);
        let committed = contracts_dir.join(dir_name).join("lib.rs");
        if !src.exists() {
            eprintln!("SKIP {}: source {} missing", dir_name, src.display());
            continue;
        }
        if !committed.exists() {
            eprintln!(
                "SKIP {}: committed {} missing",
                dir_name,
                committed.display()
            );
            continue;
        }

        let outdir = tempdir(&format!("codegen-regen-{}", dir_name));
        let status = Command::new(&compactc)
            .arg("--rust")
            .arg("--skip-zk")
            .arg(&src)
            .arg(&outdir)
            .status()
            .expect("failed to spawn compactc");
        assert!(
            status.success(),
            "compactc failed for {} (exit {:?})",
            src_name,
            status.code()
        );

        let regen = outdir.join("contract/lib.rs");
        let regen_bytes = std::fs::read(&regen)
            .unwrap_or_else(|e| panic!("read regen {}: {}", regen.display(), e));
        let committed_bytes = std::fs::read(&committed)
            .unwrap_or_else(|e| panic!("read committed {}: {}", committed.display(), e));

        if regen_bytes != committed_bytes {
            drift.push((dir_name.to_string(), regen.clone(), committed.clone()));
        }

        // Best-effort cleanup; ignore errors so a stale dir doesn't fail
        // the test.
        let _ = std::fs::remove_dir_all(&outdir);
    }

    if !drift.is_empty() {
        let summary: String = drift
            .iter()
            .map(|(name, regen, committed)| {
                format!(
                    "  - {}: regen={} vs committed={}",
                    name,
                    regen.display(),
                    committed.display()
                )
            })
            .collect::<Vec<_>>()
            .join("\n");
        panic!(
            "compactc --rust output drifted from committed fixtures \
             ({} drift{}):\n{}\n\n\
             To investigate: diff each pair above. If the regen is correct, \
             update the committed lib.rs. If the regen is wrong, fix the Scheme \
             rust-passes and rerun this test.",
            drift.len(),
            if drift.len() == 1 { "" } else { "s" },
            summary
        );
    }
}

/// Create a fresh temp dir under `$TMPDIR/<prefix>-<pid>-<nanos>`. Used
/// per-fixture so parallel test runs (or restarts after a panic) don't
/// collide. Kept dependency-free — `tempfile` isn't in the workspace.
fn tempdir(prefix: &str) -> PathBuf {
    use std::time::{SystemTime, UNIX_EPOCH};
    let base = std::env::temp_dir();
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let pid = std::process::id();
    let dir = base.join(format!("{}-{}-{}", prefix, pid, nanos));
    std::fs::create_dir_all(&dir).unwrap_or_else(|e| panic!("mkdir {}: {}", dir.display(), e));
    dir
}
