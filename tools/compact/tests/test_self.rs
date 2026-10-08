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

use crate::common::{COMPACT_VERSION, run_command};
use std::collections::HashMap;
use std::env;

mod common;

#[test]
fn test_compact_self_no_param() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "self"],
        None,
        None,
        Some("./output/self/std_default.txt"),
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(2),
    );
}

#[test]
fn test_compact_self_check() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    // `self check' and `self update' load the install receipt written by the
    // official installer. A developer who installed `compact' that way has one,
    // so the receipt is found, the command succeeds, and the expected failure
    // never happens -- these two tests only passed on a machine that had never
    // installed the tool. `AXOUPDATER_CONFIG_PATH' short-circuits the receipt
    // search ahead of `XDG_CONFIG_HOME' and the home directory, so pointing it
    // at an empty directory makes "no receipt" true by construction.
    let receipt_dir = tempfile::tempdir().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "check",
        ],
        Some(HashMap::from([(
            "AXOUPDATER_CONFIG_PATH".to_string(),
            receipt_dir.path().display().to_string(),
        )])),
        None,
        Some("./output/self/err_no_releases.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_self_update() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    // `self check' and `self update' load the install receipt written by the
    // official installer. A developer who installed `compact' that way has one,
    // so the receipt is found, the command succeeds, and the expected failure
    // never happens -- these two tests only passed on a machine that had never
    // installed the tool. `AXOUPDATER_CONFIG_PATH' short-circuits the receipt
    // search ahead of `XDG_CONFIG_HOME' and the home directory, so pointing it
    // at an empty directory makes "no receipt" true by construction.
    let receipt_dir = tempfile::tempdir().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "update",
        ],
        Some(HashMap::from([(
            "AXOUPDATER_CONFIG_PATH".to_string(),
            receipt_dir.path().display().to_string(),
        )])),
        None,
        Some("./output/self/err_no_releases.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_self_help() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "help",
        ],
        None,
        Some("./output/self/std_default_help.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_self_invalid_param() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "jump",
        ],
        None,
        None,
        Some("./output/self/err_invalid_param.txt"),
        &[],
        Some(2),
    );
}

#[test]
fn test_compact_self_param_help() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "--help",
        ],
        None,
        Some("./output/self/std_default_help.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_self_param_h() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "-h",
        ],
        None,
        Some("./output/self/std_default_help_short.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_self_param_version() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "--version",
        ],
        None,
        Some("./output/self/std_default_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        Some(0),
    );
}

#[test]
fn test_compact_self_param_v() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "self",
            "-V",
        ],
        None,
        Some("./output/self/std_default_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        Some(0),
    );
}
