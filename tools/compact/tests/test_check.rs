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

use crate::common::{COMPACT_VERSION, LATEST_COMPACTC_VERSION, run_command};
use std::env;

mod common;

#[test]
fn test_compact_check_no_param() {
    run_command(
        &["check"],
        None,
        Some("./output/check/std_default.txt"),
        None,
        &[("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
        None,
    );
}

#[test]
fn test_compact_check_invalid_param() {
    run_command(
        &["check", "latest"],
        None,
        None,
        Some("./output/check/err_invalid_param.txt"),
        &[],
        Some(2),
    );
}

#[test]
fn test_compact_check_param_help() {
    run_command(
        &["check", "--help"],
        None,
        Some("./output/check/std_check_help.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_check_param_h() {
    run_command(
        &["check", "-h"],
        None,
        Some("./output/check/std_check_help_short.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_check_param_version() {
    run_command(
        &["check", "--version"],
        None,
        Some("./output/check/std_default_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        Some(0),
    );
}

#[test]
fn test_compact_check_param_v() {
    run_command(
        &["check", "-V"],
        None,
        Some("./output/check/std_default_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        Some(0),
    );
}
