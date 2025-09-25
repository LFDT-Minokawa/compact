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

use crate::common::{
    COMPACT_VERSION, PREVIOUS_COMPACT_VERSION, download_to_temp, run_downloaded_binary,
};
use std::collections::HashMap;

mod common;

// returns different values than compactc
#[allow(dead_code)]
pub fn get_compact_version() -> &'static str {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("macos", "aarch64") => "aarch64-apple-darwin",
        ("macos", "x86_64") => "x86_64-apple-darwin",
        ("linux", "x86_64") => "x86_64-unknown-linux-musl-static",
        _ => "unknown",
    }
}

// from 0.1.0, download same way user would do
#[test]
fn test_self_sc1_download_release_and_check() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    // set paths (home, compact binary, receipt home)
    let home_dir = temp_path.to_str().unwrap();
    let compact = temp_path.join(".local/bin/compact");
    let receipt = temp_path.join(".config/compact");

    download_to_temp(
        PREVIOUS_COMPACT_VERSION,
        home_dir,
        receipt.to_str().unwrap(),
    );

    let mut env_hash_map = HashMap::new();
    env_hash_map.insert("HOME".to_string(), home_dir.to_string());
    env_hash_map.insert("XDG_CONFIG_HOME".to_string(), home_dir.to_string());
    env_hash_map.insert(
        "RECEIPT_HOME".to_string(),
        receipt.to_str().unwrap().to_string(),
    );

    run_downloaded_binary(
        Some(compact.to_str().unwrap()),
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "check",
        ],
        Some(env_hash_map),
        Some("./output/self_scenarios/std_update_available.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        Some(0),
    )
}

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "x86_64")))]
fn test_self_sc2_download_release_and_update() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    // set paths (home, compact binary, receipt home)
    let home_dir = temp_path.to_str().unwrap();
    let compact = temp_path.join(".local/bin/compact");
    let receipt = temp_path.join(".config/compact");

    download_to_temp(
        PREVIOUS_COMPACT_VERSION,
        home_dir,
        receipt.to_str().unwrap(),
    );

    let mut env_hash_map = HashMap::new();
    env_hash_map.insert("HOME".to_string(), home_dir.to_string());
    env_hash_map.insert("XDG_CONFIG_HOME".to_string(), home_dir.to_string());
    env_hash_map.insert(
        "RECEIPT_HOME".to_string(),
        receipt.to_str().unwrap().to_string(),
    );

    run_downloaded_binary(
        Some(compact.to_str().unwrap()),
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "update",
        ],
        Some(env_hash_map),
        Some("./output/self_scenarios/std_update_downloaded.txt"),
        Some("./output/self_scenarios/err_update_downloading.txt"),
        &[
            ("[COMPACT_VERSION]", COMPACT_VERSION),
            ("[USER_DIR]", temp_dir.path().to_str().unwrap()),
            ("[SYSTEM_VERSION]", get_compact_version()),
        ],
        Some(0),
    )
}

#[test]
#[cfg(all(target_os = "macos", target_arch = "x86_64"))]
fn test_self_sc2a_download_release_and_update() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    // set paths (home, compact binary, receipt home)
    let home_dir = temp_path.to_str().unwrap();
    let compact = temp_path.join(".local/bin/compact");
    let receipt = temp_path.join(".config/compact");

    download_to_temp(
        PREVIOUS_COMPACT_VERSION,
        home_dir,
        receipt.to_str().unwrap(),
    );

    let mut env_hash_map = HashMap::new();
    env_hash_map.insert("HOME".to_string(), home_dir.to_string());
    env_hash_map.insert("XDG_CONFIG_HOME".to_string(), home_dir.to_string());
    env_hash_map.insert(
        "RECEIPT_HOME".to_string(),
        receipt.to_str().unwrap().to_string(),
    );

    run_downloaded_binary(
        Some(compact.to_str().unwrap()),
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "update",
        ],
        Some(env_hash_map),
        Some("./output/self_scenarios/std_update_downloaded_macos_x86_64.txt"),
        Some("./output/self_scenarios/err_update_downloading.txt"),
        &[
            ("[COMPACT_VERSION]", COMPACT_VERSION),
            ("[USER_DIR]", temp_dir.path().to_str().unwrap()),
            ("[SYSTEM_VERSION]", get_compact_version()),
        ],
        Some(0),
    )
}
