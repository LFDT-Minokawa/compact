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
    LATEST_COMPACTC_VERSION, VERSION_WITH_NO_FORMAT, assert_files_equal, copy_file_to_dir,
    get_version, run_command,
};

mod common;

#[test]
fn test_sc19_update_to_no_formatter_compactc_format() {
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
fn test_sc20_update_latest_format_pass_non_existing_directory() {
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
            "format",
            "./bob",
        ],
        None,
        None,
        Some("./output/format/err_default.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_sc21_update_latest_format_pass_some_gibberish() {
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
            "format",
            "aaaa",
            "bbbb",
            "cccc",
        ],
        None,
        None,
        Some("./output/format/err_default.txt"),
        &[],
        Some(1),
    );
}

#[test]
fn test_sc22_update_latest_format_pass_invalid_contract() {
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

    copy_file_to_dir("./contract/invalid_contract.compact", temp_path).unwrap();
    let output_contract = temp_path.join("invalid_contract.compact");
    let output_contract_as_string = output_contract.to_str().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            output_contract_as_string,
        ],
        None,
        None,
        Some("./output/format/err_format_verbose_one_file_fail.txt"),
        &[
            ("[CONTRACT_PATH]", output_contract_as_string),
            ("[STATUS]", "failed"),
        ],
        Some(1),
    );

    assert_files_equal(
        "./contract/invalid_contract.compact",
        output_contract_as_string,
    );
}

#[test]
fn test_sc23_update_latest_format_check_pass_invalid_contract() {
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

    copy_file_to_dir("./contract/invalid_contract.compact", temp_path).unwrap();
    let output_contract = temp_path.join("invalid_contract.compact");
    let output_contract_as_string = output_contract.to_str().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            output_contract_as_string,
            "--check",
        ],
        None,
        None,
        Some("./output/format/err_format_verbose_one_file_fail.txt"),
        &[
            ("[CONTRACT_PATH]", output_contract_as_string),
            ("[STATUS]", "failed"),
        ],
        Some(1),
    );

    assert_files_equal(
        "./contract/invalid_contract.compact",
        output_contract_as_string,
    );
}

#[test]
fn test_sc24_update_latest_format_verbose_pass_invalid_contract() {
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

    copy_file_to_dir("./contract/invalid_contract.compact", temp_path).unwrap();
    let output_contract = temp_path.join("invalid_contract.compact");
    let output_contract_as_string = output_contract.to_str().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            output_contract_as_string,
            "--verbose",
        ],
        None,
        None,
        Some("./output/format/err_format_verbose_one_file_fail.txt"),
        &[
            ("[CONTRACT_PATH]", output_contract_as_string),
            ("[STATUS]", "failed"),
        ],
        Some(1),
    );

    assert_files_equal(
        "./contract/invalid_contract.compact",
        output_contract_as_string,
    );
}

// kinda of a default (can't use . as it will format also test contracts)
#[test]
fn test_sc25_update_latest_format_pass_directory_one_file() {
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

    copy_file_to_dir("./contract/formatter/input/example_1.compact", temp_path).unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            &format!("{}", temp_path.display()),
        ],
        None,
        Some("./output/format/std_format_default.txt"),
        None,
        &[],
        Some(0),
    );

    let formated_contract = temp_path.join("example_1.compact");
    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        formated_contract.to_str().unwrap(),
    );
}

#[test]
fn test_sc26_update_latest_format_verbose_unformatted_one_file() {
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

    copy_file_to_dir("./contract/formatter/input/example_1.compact", temp_path).unwrap();
    let output_contract = temp_path.join("example_1.compact");
    let output_contract_as_string = output_contract.to_str().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            output_contract_as_string,
            "--verbose",
        ],
        None,
        Some("./output/format/std_format_verbose_one_file.txt"),
        None,
        &[
            ("[CONTRACT_PATH]", output_contract_as_string),
            ("[STATUS]", "formatted"),
        ],
        Some(0),
    );

    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        output_contract_as_string,
    );
}

#[test]
fn test_sc27_update_latest_format_verbose_already_formatted_one_file() {
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

    copy_file_to_dir("./contract/formatter/output/example_1.compact", temp_path).unwrap();
    let output_contract = temp_path.join("example_1.compact");
    let output_contract_as_string = output_contract.to_str().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            output_contract_as_string,
            "--verbose",
        ],
        None,
        Some("./output/format/std_format_verbose_one_file.txt"),
        None,
        &[
            ("[CONTRACT_PATH]", output_contract_as_string),
            ("[STATUS]", "unchanged"),
        ],
        Some(0),
    );

    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        output_contract_as_string,
    );
}

#[test]
fn test_sc28_update_latest_format_check_unformatted_one_file() {
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

    copy_file_to_dir("./contract/formatter/input/example_1.compact", temp_path).unwrap();
    let output_contract = temp_path.join("example_1.compact");
    let output_contract_as_string = output_contract.to_str().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            output_contract_as_string,
            "--check",
        ],
        None,
        None,
        Some("./output/scenarios/sc28_err_format_check_example_1.txt"),
        &[("[CONTRACT_PATH]", output_contract_as_string)],
        Some(1),
    );

    assert_files_equal(
        "./contract/formatter/input/example_1.compact",
        output_contract_as_string,
    );
}

#[test]
fn test_sc29_update_latest_format_verbose_check_unformatted_one_file() {
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

    copy_file_to_dir("./contract/formatter/input/example_2.compact", temp_path).unwrap();
    let output_contract = temp_path.join("example_2.compact");
    let output_contract_as_string = output_contract.to_str().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            output_contract_as_string,
            "--verbose",
            "--check",
        ],
        None,
        None,
        Some("./output/scenarios/sc29_err_format_check_example_2.txt"),
        &[("[CONTRACT_PATH]", output_contract_as_string)],
        Some(1),
    );

    assert_files_equal(
        "./contract/formatter/input/example_2.compact",
        output_contract_as_string,
    );
}

#[test]
fn test_sc30_update_latest_format_verbose_compile() {
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

    copy_file_to_dir("./contract/formatter/input/example_1.compact", temp_path).unwrap();
    let output_contract = temp_path.join("example_1.compact");
    let output_contract_as_string = output_contract.to_str().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            output_contract_as_string,
            "--verbose",
        ],
        None,
        Some("./output/format/std_format_verbose_one_file.txt"),
        None,
        &[
            ("[CONTRACT_PATH]", output_contract_as_string),
            ("[STATUS]", "formatted"),
        ],
        Some(0),
    );

    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        output_contract_as_string,
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
}
