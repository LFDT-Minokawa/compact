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
    COMPACT_VERSION, LATEST_COMPACTC_VERSION, assert_path_contains_string, get_version, run_command,
};
use std::collections::HashMap;
use std::env;

mod common;

#[test]
fn test_compact_update_no_param() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "update"],
        None,
        Some("./output/update/std_default.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );
}

#[test]
fn test_compact_update_param_help() {
    run_command(
        &["update", "--help"],
        None,
        Some("./output/update/std_default_help.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_update_param_h() {
    run_command(
        &["update", "-h"],
        None,
        Some("./output/update/std_default_help_short.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_update_param_version() {
    run_command(
        &["update", "--version"],
        None,
        Some("./output/update/std_default_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        Some(0),
    );
}

#[test]
fn test_compact_update_param_v() {
    run_command(
        &["update", "-V"],
        None,
        Some("./output/update/std_default_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        Some(0),
    );
}

#[test]
fn test_compact_update_invalid_param_unzip() {
    run_command(
        &["update", "--unzip"],
        None,
        None,
        Some("./output/update/err_invalid_unzip.txt"),
        &[],
        Some(2),
    );
}

#[test]
fn test_compact_update_invalid_old_version() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            "0.19.0",
        ],
        None,
        None,
        Some("./output/update/err_old_version.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_update_invalid_non_existing_version() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            "bob",
        ],
        None,
        None,
        Some("./output/update/err_invalid_version.txt"),
        &[],
        Some(2),
    );
}

#[test]
#[cfg(all(target_os = "macos", target_arch = "aarch64"))]
fn test_compact_update_missing_release_macos_arm() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            "0.22.0",
        ],
        None,
        None,
        Some("./output/update/err_no_release_macos_aarch64.txt"),
        &[],
        Some(1),
    );
}

#[test]
#[cfg(all(target_os = "macos", target_arch = "x86_64"))]
fn test_compact_update_missing_release_macos_intel() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            "0.23.0",
        ],
        None,
        None,
        Some("./output/update/err_no_release_macos_intel.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_update_env_dir() {
    let temp_dir_env = tempfile::tempdir().unwrap();
    let temp_path_env = temp_dir_env.path();

    run_command(
        &["update", LATEST_COMPACTC_VERSION],
        Some({
            let mut map = HashMap::new();
            map.insert(
                "COMPACT_DIRECTORY".to_string(),
                temp_path_env.display().to_string(),
            );
            map
        }),
        Some("./output/update/std_default.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        Some(0),
    );

    assert_path_contains_string(temp_path_env, &[LATEST_COMPACTC_VERSION, get_version()]);
}
