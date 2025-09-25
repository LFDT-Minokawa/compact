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
    VERSION_WITH_NO_FORMAT, assert_path_contains_string, get_version, run_command,
};

mod common;

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "x86_64")))]
fn test_sc10_update_two_versions_compile_contract_with_previous() {
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

    let temp_output = tempfile::tempdir().unwrap();
    let temp_output_path = temp_output.path();
    let compiler = "+0.24.0";

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "compile",
            compiler,
            "./contract/counter.compact",
            temp_output_path.to_str().unwrap(),
        ],
        None,
        Some("./output/compile/std_compiling_pre_0250.txt"),
        Some("./output/compile/err_compiling.txt"),
        &[
            ("[COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
            ("[CONTRACT_DIR]", temp_output_path.to_str().unwrap()),
        ],
        None,
    );
}

// compile with specific version before 0.25.0 so there should be no version printed
#[test]
fn test_sc10a_update_version_with_run_script_removed() {
    // compi
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

    let temp_output = tempfile::tempdir().unwrap();
    let temp_output_path = temp_output.path();
    let compiler = "+0.24.0";

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "compile",
            compiler,
            "./contract/counter.compact",
            temp_output_path.to_str().unwrap(),
        ],
        None,
        Some("./output/compile/std_compiling_pre_0250.txt"),
        Some("./output/compile/err_compiling.txt"),
        &[
            ("[COMPACTC_VERSION]", VERSION_WITH_NO_FORMAT),
            ("[CONTRACT_DIR]", temp_output_path.to_str().unwrap()),
        ],
        None,
    );
}

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "aarch64")))]
fn test_sc11_update_two_versions_compile_contract_with_oldest() {
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

    let temp_output = tempfile::tempdir().unwrap();
    let temp_output_path = temp_output.path();
    let compiler = "+0.22.0";

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "compile",
            compiler,
            "./contract/counter.compact",
            temp_output_path.to_str().unwrap(),
        ],
        None,
        Some("./output/compile/std_compile_old_zkir.txt"),
        None,
        &[
            ("[COMPACTC_VERSION]", OLDEST_COMPACTC_VERSION),
            ("[CONTRACT_DIR]", temp_output_path.to_str().unwrap()),
        ],
        None,
    );
}

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "x86_64")))]
fn test_sc12_update_two_versions_keep_latest_clean_folder_check_list() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

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

    assert_path_contains_string(
        temp_path,
        &[
            LATEST_COMPACTC_VERSION,
            PREVIOUS_COMPACTC_VERSION,
            get_version(),
        ],
    );

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "clean",
            "--keep-current",
        ],
        None,
        Some("./output/scenarios/sc12_keep_latest.txt"),
        None,
        &[
            ("[COMPACTC_VERSION_ONE]", LATEST_COMPACTC_VERSION),
            ("[COMPACTC_VERSION_TWO]", PREVIOUS_COMPACTC_VERSION),
        ],
        None,
    );

    assert_path_contains_string(temp_path, &[LATEST_COMPACTC_VERSION, get_version()]);

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
}

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "x86_64")))]
fn test_sc13_update_two_versions_keep_previous_clean_folder_check_list() {
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
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "clean",
            "--keep-current",
        ],
        None,
        Some("./output/scenarios/sc13_keep_previous.txt"),
        None,
        &[
            ("[COMPACTC_VERSION_ONE]", LATEST_COMPACTC_VERSION),
            ("[COMPACTC_VERSION_TWO]", PREVIOUS_COMPACTC_VERSION),
        ],
        None,
    );

    assert_path_contains_string(temp_path, &[PREVIOUS_COMPACTC_VERSION, get_version()]);

    run_command(
        &["--directory", &format!("{}", temp_path.display()), "list"],
        None,
        Some("./output/list/std_previous_selected.txt"),
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
#[cfg(not(all(target_os = "macos")))]
fn test_sc14_update_three_versions_keep_latest_clean_folder_check_list() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

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

    assert_path_contains_string(
        temp_path,
        &[
            LATEST_COMPACTC_VERSION,
            PREVIOUS_COMPACTC_VERSION,
            OLDEST_COMPACTC_VERSION,
            get_version(),
        ],
    );

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "clean",
            "--keep-current",
        ],
        None,
        Some("./output/scenarios/sc14_clean_three_versions.txt"),
        None,
        &[
            ("[COMPACTC_VERSION_ONE]", LATEST_COMPACTC_VERSION),
            ("[COMPACTC_VERSION_TWO]", PREVIOUS_COMPACTC_VERSION),
            ("[COMPACTC_VERSION_THREE]", OLDEST_COMPACTC_VERSION),
        ],
        None,
    );

    assert_path_contains_string(temp_path, &[LATEST_COMPACTC_VERSION, get_version()]);

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
}

#[test]
fn test_sc15_update_clean_k_default_clean_list() {
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
            "clean",
            "-k",
        ],
        None,
        Some("./output/scenarios/sc15_keep_latest.txt"),
        None,
        &[("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
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
fn test_sc16_update_list_installed() {
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
            "list",
            "--installed",
        ],
        None,
        Some("./output/scenarios/sc16_list_installed.txt"),
        None,
        &[("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
        None,
    );
}

#[test]
#[cfg(not(all(target_os = "macos", target_arch = "x86_64")))]
fn test_sc17_update_current_update_previous_list_installed() {
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
            "list",
            "--installed",
        ],
        None,
        Some("./output/scenarios/sc17_previous_selected.txt"),
        None,
        &[
            ("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION),
            ("[PREVIOUS_COMPACTC_VERSION]", PREVIOUS_COMPACTC_VERSION),
        ],
        None,
    );
}

#[test]
fn test_sc18_update_current_no_default_list_installed_compile() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "update",
            "--no-set-default",
        ],
        None,
        Some("./output/scenarios/sc18_no_default_set.txt"),
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
            "list",
            "--installed",
        ],
        None,
        Some("./output/scenarios/sc18_list_installed.txt"),
        None,
        &[("[LATEST_COMPACTC_VERSION]", LATEST_COMPACTC_VERSION)],
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
        None,
        Some("./output/compile/err_default.txt"),
        &[],
        Some(1),
    );
}
