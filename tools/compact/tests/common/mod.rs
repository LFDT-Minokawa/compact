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

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::{fs, io};

#[allow(dead_code)]
pub const COMPACT_VERSION: &str = "0.4.0";

#[allow(dead_code)]
pub const PREVIOUS_COMPACT_VERSION: &str = "0.3.0";

#[allow(dead_code)]
pub const LATEST_COMPACTC_VERSION: &str = "0.29.0";

#[allow(dead_code)]
pub const PREVIOUS_COMPACTC_VERSION: &str = "0.28.0";

#[allow(dead_code)]
pub const OLDEST_COMPACTC_VERSION: &str = "0.22.0";

#[allow(dead_code)]
pub const VERSION_WITH_NO_FORMAT: &str = "0.24.0";

#[allow(dead_code)]
pub fn get_version() -> &'static str {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("macos", "aarch64") => "aarch64-darwin",
        ("macos", "x86_64") => "x86_64-apple-darwin",
        ("linux", "x86_64") => "x86_64-unknown-linux-musl",
        _ => "unknown",
    }
}

#[allow(dead_code)]
pub fn load_and_replace<P: AsRef<Path>>(path: P, replacements: &[(&str, &str)]) -> String {
    dbg!(path.as_ref().display());

    let content = fs::read_to_string(path).expect("Failed to read the file");

    let mut result = content;
    for &(from, to) in replacements {
        result = result.replace(from, to);
    }

    result
}

// probably need to rework it one day - normal assert
#[allow(dead_code)]
pub fn assert_command_output(
    binary_path: Option<&str>,
    args: &[&str],
    env: Option<HashMap<String, String>>,
    expected_stdout: &str,
    expected_stderr: &str,
    expected_exit_code: i32,
) {
    let binary = binary_path.unwrap_or("../../target/debug/compact");

    let mut cmd = Command::new(binary);

    if let Some(vars) = env {
        for (k, v) in vars {
            cmd.env(k, v);
        }
    }
    let output = cmd
        .env("RUST_BACKTRACE", "0")
        .args(args)
        .output()
        .expect("Failed to execute command");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let exit_code = output.status.code();

    dbg!(binary, args.join(" "));
    dbg!(&stdout);
    dbg!(&stderr);
    dbg!(exit_code);

    assert_eq!(stdout.trim(), expected_stdout.trim());
    assert_eq!(stderr.trim(), expected_stderr.trim());
    assert_eq!(exit_code, Some(expected_exit_code));
}

// vector assert (non-determined order)
#[allow(dead_code)]
pub fn assert_command_output_sorted(
    binary_path: Option<&str>,
    args: &[&str],
    env: Option<HashMap<String, String>>,
    expected_stdout: &str,
    expected_stderr: &str,
    expected_exit_code: i32,
) {
    let binary = binary_path.unwrap_or("../../target/debug/compact");

    let mut cmd = Command::new(binary);

    if let Some(vars) = env {
        for (k, v) in vars {
            cmd.env(k, v);
        }
    }
    let output = cmd
        .env("RUST_BACKTRACE", "0")
        .args(args)
        .output()
        .expect("Failed to execute command");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let exit_code = output.status.code();

    dbg!(binary, args.join(" "));
    dbg!(&stdout);
    dbg!(&stderr);
    dbg!(exit_code);

    assert_eq!(
        sort_lines(stdout.trim()),
        sort_lines(expected_stdout.trim())
    );
    assert_eq!(
        sort_lines(stderr.trim()),
        sort_lines(expected_stderr.trim())
    );
    assert_eq!(exit_code, Some(expected_exit_code));
}

#[allow(dead_code)]
pub fn run_command(
    args: &[&str],
    env: Option<HashMap<String, String>>,
    expected_stdout: Option<&str>,
    expected_stderr: Option<&str>,
    replacements: &[(&str, &str)],
    expected_exit_code: Option<i32>,
) {
    let expected_stdout = match expected_stdout {
        Some(path) => load_and_replace(path, replacements),
        None => String::new(),
    };

    let expected_stderr = match expected_stderr {
        Some(path) => load_and_replace(path, replacements),
        None => String::new(),
    };

    let exit_code = expected_exit_code.unwrap_or(0);

    assert_command_output(
        None,
        args,
        env,
        &expected_stdout,
        &expected_stderr,
        exit_code,
    );
}

#[allow(dead_code)]
pub fn run_command_sorted(
    args: &[&str],
    env: Option<HashMap<String, String>>,
    expected_stdout: Option<&str>,
    expected_stderr: Option<&str>,
    replacements: &[(&str, &str)],
    expected_exit_code: Option<i32>,
) {
    let expected_stdout = match expected_stdout {
        Some(path) => load_and_replace(path, replacements),
        None => String::new(),
    };

    let expected_stderr = match expected_stderr {
        Some(path) => load_and_replace(path, replacements),
        None => String::new(),
    };

    let exit_code = expected_exit_code.unwrap_or(0);

    assert_command_output_sorted(
        None,
        args,
        env,
        &expected_stdout,
        &expected_stderr,
        exit_code,
    );
}

#[allow(dead_code)]
pub fn read_directory_contents(path: &Path) -> io::Result<Vec<String>> {
    let mut results = Vec::new();
    visit_dirs(path, &mut results)?;
    Ok(results)
}

fn visit_dirs(dir: &Path, results: &mut Vec<String>) -> io::Result<()> {
    if dir.is_dir() {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            results.push(path.to_str().unwrap().to_string());

            if path.is_dir() {
                visit_dirs(&path, results)?;
            }
        }
    }

    Ok(())
}

#[allow(dead_code)]
pub fn assert_path_contains_string(path: &Path, expected: &[&str]) {
    let directories = read_directory_contents(path).unwrap();

    for kw in expected {
        assert!(
            directories.iter().any(|d| d.contains(kw)),
            "Expected one of the paths to contain: {kw}, but it does not"
        );
    }
}

#[allow(dead_code)]
pub fn copy_file_to_dir<P: AsRef<Path>>(source: P, target_directory: &Path) -> io::Result<PathBuf> {
    let source = source.as_ref();

    fs::create_dir_all(target_directory)?;

    let filename = source
        .file_name()
        .ok_or_else(|| io::Error::other("Source path has no filename"))?;

    let target_path = target_directory.join(filename);

    fs::copy(source, &target_path)?;
    Ok(target_path)
}

#[allow(dead_code)]
pub fn assert_files_equal<P: AsRef<Path>>(actual: P, expected: P) {
    let actual = fs::read_to_string(&actual).expect("Failed to read the actual file");
    let expected = fs::read_to_string(&expected).expect("Failed to read the expected file");

    assert_eq!(
        actual.trim(),
        expected.trim(),
        "File contents are different"
    );
}

#[allow(dead_code)]
pub fn sort_lines(s: &str) -> Vec<&str> {
    let mut v: Vec<_> = s.lines().map(str::trim_end).collect();
    v.sort_unstable();
    v
}

// run command but pass binary
#[allow(dead_code)]
pub fn run_downloaded_binary(
    binary: Option<&str>,
    args: &[&str],
    env: Option<HashMap<String, String>>,
    expected_stdout: Option<&str>,
    expected_stderr: Option<&str>,
    replacements: &[(&str, &str)],
    expected_exit_code: Option<i32>,
) {
    let expected_stdout = match expected_stdout {
        Some(path) => load_and_replace(path, replacements),
        None => String::new(),
    };

    let expected_stderr = match expected_stderr {
        Some(path) => load_and_replace(path, replacements),
        None => String::new(),
    };

    let exit_code = expected_exit_code.unwrap_or(0);

    assert_command_output(
        binary,
        args,
        env,
        &expected_stdout,
        &expected_stderr,
        exit_code,
    );
}

#[allow(dead_code)]
pub fn download_to_temp(version: &str, home_dir: &str, receipt_dir: &str) {
    let curl = format!(
        "curl --proto https --tlsv1.2 -LsSf https://github.com/midnightntwrk/compact/releases/download/compact-v{version}/compact-installer.sh | sh",
    );

    let output = Command::new("sh")
        .arg("-c")
        .arg(curl.as_str())
        .env("HOME", home_dir)
        .env("XDG_CONFIG_HOME", home_dir)
        .env("RECEIPT_HOME", receipt_dir)
        .output()
        .expect("Failed to execute command");

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let exit_code = output.status.code();

    dbg!(&stdout);
    dbg!(&stderr);
    dbg!(exit_code);

    assert_eq!(exit_code, Some(0));
}
