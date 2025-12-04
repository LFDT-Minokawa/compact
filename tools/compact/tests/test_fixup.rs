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
use std::env;

mod common;

#[test]
fn test_compact_fixup_no_compiler_installed() {
    run_command(
        &["fixup", "test.compact"],
        None,
        None,
        Some("./output/fixup/err_no_compiler_installed.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_fixup_invalid_param() {
    run_command(
        &["fixup", "--invalid-flag"],
        None,
        None,
        Some("./output/fixup/err_invalid_param.txt"),
        &[],
        Some(2),
    );
}

#[test]
fn test_compact_fixup_param_help() {
    run_command(
        &["fixup", "--help"],
        None,
        Some("./output/fixup/std_fixup_help.txt"),
        None,
        &[
            ("[COMPACT_VERSION]", COMPACT_VERSION),
            (
                "[COMPACT_DIR]",
                &format!("{}/.compact", env::var("HOME").unwrap()),
            ),
        ],
        None,
    );
}

#[test]
fn test_compact_fixup_param_h() {
    run_command(
        &["fixup", "-h"],
        None,
        Some("./output/fixup/std_fixup_help_short.txt"),
        None,
        &[
            ("[COMPACT_VERSION]", COMPACT_VERSION),
            (
                "[COMPACT_DIR]",
                &format!("{}/.compact", env::var("HOME").unwrap()),
            ),
        ],
        None,
    );
}

#[test]
fn test_compact_fixup_param_version() {
    run_command(
        &["fixup", "--version"],
        None,
        Some("./output/fixup/std_fixup_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        None,
    );
}

#[test]
fn test_compact_fixup_param_v() {
    run_command(
        &["fixup", "-V"],
        None,
        Some("./output/fixup/std_fixup_version.txt"),
        None,
        &[("[COMPACT_VERSION]", COMPACT_VERSION)],
        None,
    );
}

#[test]
fn test_compact_fixup_directory_without_in_place() {
    run_command(
        &["fixup", "."],
        None,
        None,
        Some("./output/fixup/err_directory_needs_in_place.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_fixup_multiple_files_warning() {
    run_command(
        &["fixup", "file1.compact", "file2.compact"],
        None,
        None,
        Some("./output/fixup/err_no_compiler_installed.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_fixup_no_compiler_with_directory() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "fixup",
            "test.compact",
        ],
        None,
        None,
        Some("./output/fixup/err_no_compiler_installed.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_fixup_directory_without_in_place_with_directory() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "fixup",
            ".",
        ],
        None,
        None,
        Some("./output/fixup/err_no_compiler_installed.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_fixup_with_invalid_flag() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "fixup",
            "--invalid-flag",
        ],
        None,
        None,
        Some("./output/fixup/err_invalid_param.txt"),
        &[],
        Some(2),
    );
}

#[test]
fn test_compact_fixup_multiple_files_with_directory() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "fixup",
            "file1.compact",
            "file2.compact",
        ],
        None,
        None,
        Some("./output/fixup/err_no_compiler_installed.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_fixup_update_uint_ranges_flag() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "fixup",
            "--update-Uint-ranges",
            "test.compact",
        ],
        None,
        None,
        Some("./output/fixup/err_no_compiler_installed.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_fixup_update_uint_ranges_with_in_place() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "fixup",
            "--update-Uint-ranges",
            "--in-place",
            "test.compact",
        ],
        None,
        None,
        Some("./output/fixup/err_no_compiler_installed.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_fixup_verbose_flag() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "fixup",
            "--verbose",
            "test.compact",
        ],
        None,
        None,
        Some("./output/fixup/err_no_compiler_installed.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_compact_fixup_verbose_short_flag() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "fixup",
            "-v",
            "test.compact",
        ],
        None,
        None,
        Some("./output/fixup/err_no_compiler_installed.txt"),
        &[],
        Some(1),
    );
}
