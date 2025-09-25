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
    LATEST_COMPACTC_VERSION, assert_files_equal, copy_file_to_dir, get_version, run_command,
    run_command_sorted,
};

mod common;

#[test]
fn test_sc31_update_latest_format_one_directory_three_files() {
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
    copy_file_to_dir("./contract/formatter/input/example_2.compact", temp_path).unwrap();
    copy_file_to_dir("./contract/formatter/input/example_3.compact", temp_path).unwrap();

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

    let formated_contract_one = temp_path.join("example_1.compact");
    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        formated_contract_one.to_str().unwrap(),
    );

    let formated_contract_two = temp_path.join("example_2.compact");
    assert_files_equal(
        "./contract/formatter/output/example_2.compact",
        formated_contract_two.to_str().unwrap(),
    );

    let formated_contract_three = temp_path.join("example_3.compact");
    assert_files_equal(
        "./contract/formatter/output/example_3.compact",
        formated_contract_three.to_str().unwrap(),
    );
}

#[test]
fn test_sc32_update_latest_format_verbose_two_directories_with_one_file_each() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    let temp_dir_two = tempfile::tempdir().unwrap();
    let temp_path_two = temp_dir_two.path();

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
    let formated_contract_one = temp_path.join("example_1.compact");
    let formated_contract_one_as_string = formated_contract_one.to_str().unwrap();

    copy_file_to_dir(
        "./contract/formatter/input/example_2.compact",
        temp_path_two,
    )
    .unwrap();
    let formated_contract_two = temp_path_two.join("example_2.compact");
    let formated_contract_two_as_string = formated_contract_two.to_str().unwrap();

    run_command_sorted(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            &format!("{}", temp_path.display()),
            &format!("{}", temp_path_two.display()),
            "--verbose",
        ],
        None,
        Some("./output/format/std_format_verbose_two_files.txt"),
        None,
        &[
            ("[CONTRACT_PATH]", formated_contract_one_as_string),
            ("[STATUS]", "formatted"),
            ("[CONTRACT_PATH_TWO]", formated_contract_two_as_string),
            ("[STATUS_TWO]", "formatted"),
        ],
        Some(0),
    );

    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        formated_contract_one_as_string,
    );

    assert_files_equal(
        "./contract/formatter/output/example_2.compact",
        formated_contract_two_as_string,
    );
}

#[test]
fn test_sc33_update_latest_format_verbose_check_two_files() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    let temp_dir_two = tempfile::tempdir().unwrap();
    let temp_path_two = temp_dir_two.path();

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
    let formated_contract_one = temp_path.join("example_1.compact");
    let formated_contract_one_as_string = formated_contract_one.to_str().unwrap();

    copy_file_to_dir(
        "./contract/formatter/input/example_2.compact",
        temp_path_two,
    )
    .unwrap();
    let formated_contract_two = temp_path_two.join("example_2.compact");
    let formated_contract_two_as_string = formated_contract_two.to_str().unwrap();

    run_command_sorted(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            formated_contract_one_as_string,
            formated_contract_two_as_string,
            "--verbose",
            "--check",
        ],
        None,
        None,
        Some("./output/format/err_verbose_check_two_files.txt"),
        &[
            ("[CONTRACT_PATH]", formated_contract_one_as_string),
            ("[CONTRACT_PATH_TWO]", formated_contract_two_as_string),
        ],
        Some(1),
    );

    assert_files_equal(
        "./contract/formatter/input/example_1.compact",
        formated_contract_one_as_string,
    );

    assert_files_equal(
        "./contract/formatter/input/example_2.compact",
        formated_contract_two_as_string,
    );
}

#[test]
fn test_sc34_update_latest_format_verbose_same_file_twice() {
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
    let formated_contract = temp_path.join("example_1.compact");
    let formated_contract_as_string = formated_contract.to_str().unwrap();

    run_command_sorted(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            formated_contract_as_string,
            formated_contract_as_string,
            "--verbose",
        ],
        None,
        Some("./output/format/std_format_verbose_two_files.txt"),
        None,
        &[
            ("[CONTRACT_PATH]", formated_contract_as_string),
            ("[STATUS]", "formatted"),
            ("[CONTRACT_PATH_TWO]", formated_contract_as_string),
            ("[STATUS_TWO]", "formatted"),
        ],
        Some(0),
    );

    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        formated_contract_as_string,
    );
}

#[test]
fn test_sc35_update_latest_format_one_directory_one_file() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    let temp_dir_two = tempfile::tempdir().unwrap();
    let temp_path_two = temp_dir_two.path();

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
    let formated_contract_one = temp_path.join("example_1.compact");
    let formated_contract_one_as_string = formated_contract_one.to_str().unwrap();

    copy_file_to_dir(
        "./contract/formatter/input/example_2.compact",
        temp_path_two,
    )
    .unwrap();
    let formated_contract_two = temp_path_two.join("example_2.compact");
    let formated_contract_two_as_string = formated_contract_two.to_str().unwrap();

    run_command(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            &format!("{}", temp_path.display()),
            formated_contract_two_as_string,
        ],
        None,
        Some("./output/format/std_format_default.txt"),
        None,
        &[],
        Some(0),
    );

    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        formated_contract_one_as_string,
    );

    assert_files_equal(
        "./contract/formatter/output/example_2.compact",
        formated_contract_two_as_string,
    );
}

#[test]
fn test_sc36_update_latest_format_verbose_two_directories_one_file_each_not_formatted_invalid() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    let temp_dir_two = tempfile::tempdir().unwrap();
    let temp_path_two = temp_dir_two.path();

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
    let formated_contract_one = temp_path.join("example_1.compact");
    let formated_contract_one_as_string = formated_contract_one.to_str().unwrap();

    copy_file_to_dir("./contract/invalid_contract.compact", temp_path_two).unwrap();
    let formated_contract_two = temp_path_two.join("invalid_contract.compact");
    let formated_contract_two_as_string = formated_contract_two.to_str().unwrap();

    run_command_sorted(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            &format!("{}", temp_path.display()),
            &format!("{}", temp_path_two.display()),
            "--verbose",
        ],
        None,
        Some("./output/scenarios/sc36_std_format_verbose.txt"),
        Some("./output/scenarios/sc36_err_format_verbose.txt"),
        &[
            ("[CONTRACT_PATH]", formated_contract_one_as_string),
            ("[STATUS]", "formatted"),
            ("[ERR_CONTRACT_PATH]", formated_contract_two_as_string),
            ("[ERR_STATUS]", "failed"),
        ],
        Some(1),
    );

    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        formated_contract_one_as_string,
    );

    assert_files_equal(
        "./contract/invalid_contract.compact",
        formated_contract_two_as_string,
    );
}

#[test]
fn test_sc37_update_latest_format_verbose_two_directories_one_file_each_not_formatted_formatted() {
    let temp_dir = tempfile::tempdir().unwrap();
    let temp_path = temp_dir.path();

    let temp_dir_two = tempfile::tempdir().unwrap();
    let temp_path_two = temp_dir_two.path();

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
    let formated_contract_one = temp_path.join("example_1.compact");
    let formated_contract_one_as_string = formated_contract_one.to_str().unwrap();

    copy_file_to_dir(
        "./contract/formatter/output/example_2.compact",
        temp_path_two,
    )
    .unwrap();
    let formated_contract_two = temp_path_two.join("example_2.compact");
    let formated_contract_two_as_string = formated_contract_two.to_str().unwrap();

    run_command_sorted(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            &format!("{}", temp_path.display()),
            &format!("{}", temp_path_two.display()),
            "--verbose",
        ],
        None,
        Some("./output/format/std_format_verbose_two_files.txt"),
        None,
        &[
            ("[CONTRACT_PATH]", formated_contract_one_as_string),
            ("[STATUS]", "formatted"),
            ("[CONTRACT_PATH_TWO]", formated_contract_two_as_string),
            ("[STATUS_TWO]", "unchanged"),
        ],
        Some(0),
    );

    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        formated_contract_one_as_string,
    );

    assert_files_equal(
        "./contract/formatter/output/example_2.compact",
        formated_contract_two_as_string,
    );
}

#[test]
fn test_sc38_update_latest_format_verbose_one_directory_three_files() {
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
    let formated_contract_one = temp_path.join("example_1.compact");
    let formated_contract_one_as_string = formated_contract_one.to_str().unwrap();

    copy_file_to_dir("./contract/formatter/input/example_2.compact", temp_path).unwrap();
    let formated_contract_two = temp_path.join("example_2.compact");
    let formated_contract_two_as_string = formated_contract_two.to_str().unwrap();

    copy_file_to_dir("./contract/formatter/input/example_3.compact", temp_path).unwrap();
    let formated_contract_three = temp_path.join("example_3.compact");
    let formated_contract_three_as_string = formated_contract_three.to_str().unwrap();

    run_command_sorted(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            &format!("{}", temp_path.display()),
            "--verbose",
        ],
        None,
        Some("./output/format/std_format_verbose_three_files.txt"),
        None,
        &[
            ("[CONTRACT_PATH]", formated_contract_one_as_string),
            ("[STATUS]", "formatted"),
            ("[CONTRACT_PATH_TWO]", formated_contract_two_as_string),
            ("[STATUS_TWO]", "formatted"),
            ("[CONTRACT_PATH_THREE]", formated_contract_three_as_string),
            ("[STATUS_THREE]", "formatted"),
        ],
        Some(0),
    );

    assert_files_equal(
        "./contract/formatter/output/example_1.compact",
        formated_contract_one_as_string,
    );

    assert_files_equal(
        "./contract/formatter/output/example_2.compact",
        formated_contract_two_as_string,
    );

    assert_files_equal(
        "./contract/formatter/output/example_3.compact",
        formated_contract_three_as_string,
    );
}

#[test]
fn test_sc39_update_latest_format_check_unformatted_two_files() {
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
    let output_contract_one = temp_path.join("example_1.compact");
    let output_contract_one_as_string = output_contract_one.to_str().unwrap();

    copy_file_to_dir("./contract/formatter/input/example_2.compact", temp_path).unwrap();
    let output_contract_two = temp_path.join("example_2.compact");
    let output_contract_two_as_string = output_contract_two.to_str().unwrap();

    run_command_sorted(
        &[
            "--directory",
            &format!("{}", temp_path.display()),
            "format",
            output_contract_one_as_string,
            output_contract_two_as_string,
            "--check",
        ],
        None,
        None,
        Some("./output/scenarios/sc39_err_format_check_example_1_2.txt"),
        &[
            ("[CONTRACT_PATH_ONE]", output_contract_one_as_string),
            ("[CONTRACT_PATH_TWO]", output_contract_two_as_string),
        ],
        Some(1),
    );

    assert_files_equal(
        "./contract/formatter/input/example_1.compact",
        output_contract_one_as_string,
    );

    assert_files_equal(
        "./contract/formatter/input/example_2.compact",
        output_contract_two_as_string,
    );
}
