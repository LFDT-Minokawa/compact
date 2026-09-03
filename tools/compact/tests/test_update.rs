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
use std::fs;

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

/// Issue #739: an extraction that fails leaves the version directory in place
/// holding nothing but `artifact.zip'. A retry used to see that directory,
/// report "already installed", skip re-extraction and then fail on the missing
/// binary -- and because the default symlink was written before it was
/// validated, it left a dangling `bin/compactc' that broke every later command
/// too. A retry has to re-extract and end up with a compiler that resolves.
#[test]
fn test_compact_update_repairs_incomplete_installation() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();
    let directory = format!("{}", temp_path.display());

    run_command(
        &["--directory", &directory, "update", LATEST_COMPACTC_VERSION],
        None,
        Some("./output/update/std_update_other.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    // Reproduce what a failed extraction leaves behind: the downloaded archive
    // and nothing else.
    let artifact_dir = temp_path
        .join("versions")
        .join(LATEST_COMPACTC_VERSION)
        .join(get_version());

    for entry in fs::read_dir(&artifact_dir).unwrap() {
        let path = entry.unwrap().path();

        if path.file_name().unwrap() == "artifact.zip" {
            continue;
        }

        if path.is_dir() {
            fs::remove_dir_all(&path).unwrap();
        } else {
            fs::remove_file(&path).unwrap();
        }
    }

    fs::remove_file(temp_path.join("bin").join("compactc")).unwrap();

    assert!(
        artifact_dir.join("artifact.zip").is_file(),
        "the archive should survive a failed extraction"
    );
    assert!(
        !artifact_dir.join("compactc").exists(),
        "a failed extraction leaves no compiler behind"
    );

    run_command(
        &["--directory", &directory, "update", LATEST_COMPACTC_VERSION],
        None,
        Some("./output/update/std_reinstall_incomplete.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    assert!(
        artifact_dir.join("compactc").is_file(),
        "the retry should have re-extracted the compiler"
    );

    // `is_file' follows the link, so this also rules out a dangling symlink.
    assert!(
        temp_path.join("bin").join("compactc").is_file(),
        "the default compiler symlink should resolve to a real file"
    );
}

/// Issue #739, last corner: the archive is only downloaded when it is not
/// already on disk, so an archive that is complete but unreadable -- a bad
/// checksum, a stitched resume -- made every retry fail in exactly the same
/// way, with deleting it by hand the only way forward. That is the shape of the
/// original report. An unreadable archive is now discarded and fetched again.
#[test]
fn test_compact_update_repairs_a_corrupt_archive() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();
    let directory = format!("{}", temp_path.display());

    run_command(
        &["--directory", &directory, "update", LATEST_COMPACTC_VERSION],
        None,
        Some("./output/update/std_update_other.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    let artifact_dir = temp_path
        .join("versions")
        .join(LATEST_COMPACTC_VERSION)
        .join(get_version());

    // Poison the archive and remove what it produced, so the retry has to read
    // the archive rather than trust the directory.
    fs::write(
        artifact_dir.join("artifact.zip"),
        b"not an archive any more",
    )
    .unwrap();
    fs::remove_file(artifact_dir.join("compactc")).unwrap();
    fs::remove_file(temp_path.join("bin").join("compactc")).unwrap();

    run_command(
        &["--directory", &directory, "update", LATEST_COMPACTC_VERSION],
        None,
        Some("./output/update/std_repair_corrupt_archive.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    assert!(
        artifact_dir.join("compactc").is_file(),
        "the compiler should have been reinstalled from a freshly fetched archive"
    );
    assert!(
        temp_path.join("bin").join("compactc").is_file(),
        "the default compiler symlink should resolve to a real file"
    );
}
