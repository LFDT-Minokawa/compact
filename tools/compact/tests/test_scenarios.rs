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
    LATEST_COMPACTC_VERSION, OLDEST_COMPACTC_VERSION, PREVIOUS_COMPACTC_VERSION,
    VERSION_WITH_NO_FORMAT, assert_path_contains_string, get_version, read_directory_contents,
    run_command,
};

mod common;

#[test]
fn test_sc1_update_list_compile() {
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

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "list"],
        None,
        Some("./output/list/std_latest_selected.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[PREVIOUS_COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
            ("[OLDEST_COMPACTC_VERSION]", OLDEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "compile",
            "--version",
        ],
        None,
        Some("./output/compile/std_default.txt"),
        None,
        &[("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
        None,
    );

    assert_path_contains_string(
        temp_path,
        &["/bin/compactc", "/bin/fixup-compact", "/bin/format-compact"],
    );
}

#[test]
fn test_sc2_update_update_list() {
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

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "update"],
        None,
        Some("./output/scenarios/sc2_std_already_installed.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "list"],
        None,
        Some("./output/list/std_latest_selected.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[PREVIOUS_COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
            ("[OLDEST_COMPACTC_VERSION]", OLDEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );
}

#[test]
fn test_sc3_update_compile_clean_list() {
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

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "compile",
            "--version",
        ],
        None,
        Some("./output/compile/std_default.txt"),
        None,
        &[("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
        None,
    );

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "clean"],
        None,
        Some("./output/clean/std_clean_latest.txt"),
        None,
        &[("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
        None,
    );

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "list"],
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
fn test_sc4_list_update_list_clean_list() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "list"],
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

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "list"],
        None,
        Some("./output/list/std_latest_selected.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[PREVIOUS_COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
            ("[OLDEST_COMPACTC_VERSION]", OLDEST_COMPACTC_VERSION),
        ],
        None,
    );

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "clean"],
        None,
        Some("./output/clean/std_clean_latest.txt"),
        None,
        &[("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
        None,
    );

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "list"],
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
fn test_sc5_update_clean_folder_check() {
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

    assert_path_contains_string(temp_path, &[LATEST_COMPACTC_VERSION, get_version()]);

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "clean"],
        None,
        Some("./output/clean/std_clean_latest.txt"),
        None,
        &[("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
        None,
    );

    // check we have removed version (only bin / versions left)
    let directories = read_directory_contents(temp_path).unwrap();
    assert_eq!(directories.len(), 2);
}

// clean with the last version without fixup and format
#[test]
fn test_sc5a_update_clean_folder_check_no_fixup_format() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            VERSION_WITH_NO_FORMAT,
        ],
        None,
        Some("./output/update/std_update_other.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", VERSION_WITH_NO_FORMAT),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    assert_path_contains_string(temp_path, &[VERSION_WITH_NO_FORMAT, get_version()]);

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "clean"],
        None,
        Some("./output/clean/std_clean_other.txt"),
        None,
        &[("[COMPACTC_VERSION]", VERSION_WITH_NO_FORMAT)],
        None,
    );

    // check we have removed version (only bin / versions left)
    let directories = read_directory_contents(temp_path).unwrap();
    assert_eq!(directories.len(), 2);
}

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "x86_64")))]
fn test_sc6_update_two_versions_clean_folder_check() {
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

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            PREVIOUS_COMPACTC_VERSION,
        ],
        None,
        Some("./output/update/std_update_other.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    assert_path_contains_string(
        temp_path,
        &[
            LATEST_COMPACTC_VERSION,
            PREVIOUS_COMPACTC_VERSION,
            get_version(),
        ],
    );

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "clean"],
        None,
        Some("./output/scenarios/sc6_std_clean.txt"),
        None,
        &[
            ("[COMPACTC_VERSION_ONE]", LATEST_COMPACTC_VERSION),
            ("[COMPACTC_VERSION_TWO]", PREVIOUS_COMPACTC_VERSION),
        ],
        None,
    );

    let directories = read_directory_contents(temp_path).unwrap();
    assert_eq!(directories.len(), 2);
}

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "x86_64")))]
fn test_sc6a_update_three_versions_clean_folder_check() {
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

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            PREVIOUS_COMPACTC_VERSION,
        ],
        None,
        Some("./output/update/std_update_other.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            "0.23.0",
        ],
        None,
        Some("./output/update/std_update_other.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", "0.23.0"),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    assert_path_contains_string(
        temp_path,
        &[
            LATEST_COMPACTC_VERSION,
            PREVIOUS_COMPACTC_VERSION,
            "0.23.0",
            get_version(),
        ],
    );

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "clean"],
        None,
        Some("./output/scenarios/sc6a_std_clean.txt"),
        None,
        &[
            ("[COMPACTC_VERSION_ONE]", LATEST_COMPACTC_VERSION),
            ("[COMPACTC_VERSION_TWO]", PREVIOUS_COMPACTC_VERSION),
            ("[COMPACTC_VERSION_THREE]", "0.23.0"),
        ],
        None,
    );

    let directories = read_directory_contents(temp_path).unwrap();
    assert_eq!(directories.len(), 2);
}

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "x86_64")))]
fn test_sc7_update_previous_list_compile() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            VERSION_WITH_NO_FORMAT,
        ],
        None,
        Some("./output/update/std_update_other.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", VERSION_WITH_NO_FORMAT),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    assert_path_contains_string(temp_path, &["/bin/compactc"]);

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "list"],
        None,
        Some("./output/list/std_024_selected.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[PREVIOUS_COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
            ("[OLDEST_COMPACTC_VERSION]", OLDEST_COMPACTC_VERSION),
        ],
        None,
    );

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "compile",
            "--version",
        ],
        None,
        Some("./output/compile/std_non_latest.txt"),
        None,
        &[("[COMPACTC_VERSION]", VERSION_WITH_NO_FORMAT)],
        None,
    );
}

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
fn test_sc8_update_oldest_list_compile() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            OLDEST_COMPACTC_VERSION,
        ],
        None,
        Some("./output/update/std_update_other.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", OLDEST_COMPACTC_VERSION),
            ("[SYSTEM_VERSION]", get_version()),
        ],
        None,
    );

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "list"],
        None,
        Some("./output/list/std_oldest_selected.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[PREVIOUS_COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
            ("[OLDEST_COMPACTC_VERSION]", OLDEST_COMPACTC_VERSION),
        ],
        None,
    );

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "compile",
            "--version",
        ],
        None,
        Some("./output/compile/std_oldest.txt"),
        None,
        &[("[COMPACTC_VERSION]", OLDEST_COMPACTC_VERSION)],
        None,
    );
}

#[test]
fn test_sc9_update_compile_contract() {
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

    let temp_output = tempfile::tempdir().unwrap();
    let temp_output_path = temp_output.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "compile",
            "./contract/counter.compact",
            temp_output_path.to_str().unwrap(),
        ],
        None,
        Some("./output/compile/std_compiling.txt"),
        Some("./output/compile/err_compiling.txt"),
        &[("[COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
        None,
    );

    assert_path_contains_string(
        temp_output_path,
        &[
            "/zkir/increment.bzkir",
            "/zkir/increment.zkir",
            "/keys/increment.prover",
            "/keys/increment.verifier",
            "/compiler/contract-info.json",
            "/contract/index.d.cts",
            "/contract/index.cjs.map",
            "/contract/index.cjs",
        ],
    );
}
