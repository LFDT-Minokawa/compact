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
    COMPACT_VERSION, LATEST_COMPACTC_VERSION, OLDEST_COMPACTC_VERSION, PREVIOUS_COMPACTC_VERSION,
    run_command,
};
use std::env;

mod common;

#[test]
fn test_compact_list_no_param() {
    run_command(
        &["list"],
        None,
        Some("./output/list/std_default.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[PREVIOUS_COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
            ("[OLDEST_COMPACTC_VERSION]", OLDEST_COMPACTC_VERSION),
        ],
        None,
    );
}

#[test]
fn test_compact_list_param_i_nothing_installed() {
    run_command(
        &["list", "-i"],
        None,
        Some("./output/list/std_list_installed.txt"),
        None,
        &[],
        None,
    );
}

#[test]
fn test_compact_list_param_installed_nothing_installed() {
    run_command(
        &["list", "--installed"],
        None,
        Some("./output/list/std_list_installed.txt"),
        None,
        &[],
        None,
    );
}

#[test]
fn test_compact_list_invalid_param() {
    run_command(
        &["list", "latest"],
        None,
        None,
        Some("./output/list/err_invalid_param.txt"),
        &[],
        Some(2),
    );
}

#[test]
fn test_compact_list_param_help() {
    run_command(
        &["list", "--help"],
        None,
        Some("./output/list/std_list_help.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_list_param_h() {
    run_command(
        &["list", "-h"],
        None,
        Some("./output/list/std_list_help_short.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_list_param_version() {
    run_command(
        &["list", "--version"],
        None,
        Some("./output/list/std_default_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        Some(0),
    );
}

#[test]
fn test_compact_list_param_v() {
    run_command(
        &["list", "-V"],
        None,
        Some("./output/list/std_default_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        Some(0),
    );
}
