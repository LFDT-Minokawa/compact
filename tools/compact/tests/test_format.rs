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

use crate::common::run_command;
use std::env;

mod common;

#[test]
fn test_compact_format_no_compiler_installed() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "format"],
        None,
        None,
        Some("./output/format/err_no_compiler.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_format_invalid_param() {
    run_command(
        &["format", "--bob"],
        None,
        None,
        Some("./output/format/err_invalid_param.txt"),
        &[],
        Some(2),
    );
}

#[test]
fn test_compact_format_param_help() {
    run_command(
        &["format", "--help"],
        None,
        Some("./output/format/std_format_help.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_format_param_h() {
    run_command(
        &["format", "-h"],
        None,
        Some("./output/format/std_format_help_short.txt"),
        None,
        &[("[USER_DIR]", env::home_dir().unwrap().to_str().unwrap())],
        Some(0),
    );
}

#[test]
fn test_compact_format_param_version() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            "--version",
        ],
        None,
        None,
        Some("./output/format/err_no_compiler.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_format_param_v() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            "-V",
        ],
        None,
        None,
        Some("./output/format/err_no_compiler.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_format_param_language_version() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            "--language-version",
        ],
        None,
        None,
        Some("./output/format/err_no_compiler.txt"),
        &[],
        Some(1),
    );
}
