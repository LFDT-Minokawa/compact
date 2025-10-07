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
fn test_compact_help_no_param() {
    run_command(
        &["help"],
        None,
        Some("./output/help/std_default.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        None,
    );
}

#[test]
fn test_compact_help_param_help() {
    run_command(
        &["--help"],
        None,
        Some("./output/help/std_default.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        None,
    );
}

#[test]
fn test_compact_help_param_h() {
    run_command(
        &["-h"],
        None,
        Some("./output/help/std_short.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        None,
    );
}

#[test]
fn test_compact_help_param_version() {
    run_command(
        &["--version"],
        None,
        Some("./output/help/std_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        None,
    );
}

#[test]
fn test_compact_help_param_v() {
    run_command(
        &["-V"],
        None,
        Some("./output/help/std_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        None,
    );
}

#[test]
fn test_compact_help_invalid_param() {
    run_command(
        &["--bob"],
        None,
        None,
        Some("./output/help/err_invalid_param.txt"),
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(2),
    );
}

#[test]
fn test_compact_help_two_params() {
    run_command(
        &["--help", "--version"],
        None,
        Some("./output/help/std_default.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_help_both_dir_and_env_dir() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    let temp_dir_env = tempfile::tempdir().unwrap();
    let temp_path_env = temp_dir_env.path();

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "--help"],
        Some({
            let mut map = HashMap::new();
            map.insert(
                "COMPACT_DIRECTORY".to_string(),
                temp_path_env.display().to_string(),
            );
            map
        }),
        Some("./output/help/std_default_env.txt"),
        None,
        &[
            ("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap()),
            ("[COMPACT_DIRECTORY]", temp_path_env.to_str().unwrap()),
        ],
        Some(0),
    );
}

#[test]
fn test_compact_help_env_dir() {
    let temp_dir_env = tempfile::tempdir().unwrap();
    let temp_path_env = temp_dir_env.path();

    run_command(
        &["--help"],
        Some({
            let mut map = HashMap::new();
            map.insert(
                "COMPACT_DIRECTORY".to_string(),
                temp_path_env.display().to_string(),
            );
            map
        }),
        Some("./output/help/std_default_env.txt"),
        None,
        &[
            ("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap()),
            ("[COMPACT_DIRECTORY]", temp_path_env.to_str().unwrap()),
        ],
        Some(0),
    );
}

#[test]
fn test_compact_help_dir() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "--help"],
        None,
        Some("./output/help/std_default.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}
