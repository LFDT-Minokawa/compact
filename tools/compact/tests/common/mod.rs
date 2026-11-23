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

use clap::Parser;
use compact::CommandLineArguments;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::{fs, io};

#[allow(dead_code)]
pub const COMPACT_VERSION: &str = "0.5.3";

#[allow(dead_code)]
pub const PREVIOUS_COMPACT_VERSION: &str = "0.5.2";

#[allow(dead_code)]
pub const LATEST_COMPACTC_VERSION: &str = "0.36.1";

#[allow(dead_code)]
pub const PREVIOUS_COMPACTC_VERSION: &str = "0.36.0";

/// The oldest release `compact update' offers: every release from it on has
/// all four platforms, archives named alike, and the same packaging.
#[allow(dead_code)]
pub const OLDEST_COMPACTC_VERSION: &str = "0.29.0";

/// A release between the oldest and the previous one.
#[allow(dead_code)]
pub const OTHER_COMPACTC_VERSION: &str = "0.30.0";

/// A version no release offers, for a compiler made on disk by
/// `make_compiler_without_formatter'.
#[allow(dead_code)]
pub const VERSION_ON_DISK_ONLY: &str = "0.24.0";

/// A release candidate, for the tests that install one by name.
#[allow(dead_code)]
pub const CANDIDATE_COMPACTC_VERSION: &str = "0.35.0-rc.1";

/// Make a compiler of `version' in the compact directory `directory' with
/// nothing beside `compactc': no `format-compact', no `fixup-compact', as the
/// releases before 0.25.0 shipped. Those are no longer offered, so a test that
/// needs such a compiler makes one, and `compact update <version>' finds it
/// installed. Running it prints its version.
#[allow(dead_code)]
pub fn make_compiler_without_formatter(directory: &Path, version: &str) {
    let dir = directory.join("versions").join(version).join(get_version());
    fs::create_dir_all(&dir).expect("Failed to create the compiler's directory");

    let compactc = dir.join("compactc");
    fs::write(&compactc, format!("#!/bin/sh\necho {version}\n"))
        .expect("Failed to write the compiler");

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;

        fs::set_permissions(&compactc, fs::Permissions::from_mode(0o755))
            .expect("Failed to make the compiler executable");
    }
}

#[allow(dead_code)]
pub fn get_version() -> &'static str {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("macos", "aarch64") => "aarch64-darwin",
        ("macos", "x86_64") => "x86_64-apple-darwin",
        ("linux", "x86_64") => "x86_64-unknown-linux-musl",
        ("linux", "aarch64") => "aarch64-unknown-linux-musl",
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

/// Fail loudly rather than let a test operate on the developer's real
/// `~/.compact`.
///
/// Tests used to invoke stateful subcommands with no directory argument, so
/// `cargo test` ran `clean` against the caller's own installation and deleted
/// their compilers -- the tests were named `*_nothing_installed' because
/// whoever wrote them had nothing installed.
///
/// An invocation is exempt only when it cannot reach a command handler: when
/// clap answers it (`--help', `--version', the `help' subcommand) or rejects
/// it, and exits. The CLI's own parser decides, not a list of flags: `compile'
/// hands `--help' and `--version' to the installed compiler (#649), so a list
/// of them let `compact compile --help' read the caller's installation, and the
/// tests expecting no compiler to be installed failed on any machine with one.
///
/// Everything else has to name a directory: `--directory', or
/// `COMPACT_DIRECTORY' or `HOME' -- the default directory is under it -- in
/// the command's environment. A `COMPACT_DIRECTORY' in the caller's own
/// environment is never passed on (`without_callers_directory'), since it
/// would override that `HOME'.
#[allow(dead_code)]
fn assert_directory_is_isolated(args: &[&str], env: Option<&HashMap<String, String>>) {
    let reaches_a_handler = CommandLineArguments::try_parse_from(
        std::iter::once("compact").chain(args.iter().copied()),
    )
    .is_ok();

    if !reaches_a_handler {
        return;
    }

    assert!(
        args.contains(&"--directory")
            || env.is_some_and(|env| {
                env.contains_key("COMPACT_DIRECTORY") || env.contains_key("HOME")
            }),
        "`compact {}' was invoked with no --directory, and with neither COMPACT_DIRECTORY \
         nor HOME in its environment. It would act on the real ~/.compact and can delete \
         the caller's installed compilers. Pass --directory with a tempfile::tempdir() path.",
        args.join(" ")
    );
}

/// A command for the CLI that does not inherit the caller's
/// `COMPACT_DIRECTORY': a test names its directory itself, and one exported by
/// whoever runs the suite would otherwise override the `HOME' a test isolates
/// a command with. A test may still set `COMPACT_DIRECTORY' for the command.
#[allow(dead_code)]
fn without_callers_directory(binary: &str) -> Command {
    let mut cmd = Command::new(binary);
    cmd.env_remove("COMPACT_DIRECTORY");
    cmd
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
    assert_directory_is_isolated(args, env.as_ref());

    let binary = binary_path.unwrap_or("../../target/debug/compact");

    let mut cmd = without_callers_directory(binary);

    // Clap wraps help to the terminal width. Under test there is no terminal,
    // so it falls back to 100 columns, which makes the expected output depend
    // on the length of `$HOME' and of the temporary directory path -- a test
    // that passes in CI fails for a developer whose home or TMPDIR is longer.
    // Ask for a width nothing wraps at, so help output is a function of its
    // content alone. Set before the caller's variables so a test can override.
    cmd.env("COLUMNS", "10000");

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
    assert_directory_is_isolated(args, env.as_ref());

    let binary = binary_path.unwrap_or("../../target/debug/compact");

    let mut cmd = without_callers_directory(binary);

    // Clap wraps help to the terminal width. Under test there is no terminal,
    // so it falls back to 100 columns, which makes the expected output depend
    // on the length of `$HOME' and of the temporary directory path -- a test
    // that passes in CI fails for a developer whose home or TMPDIR is longer.
    // Ask for a width nothing wraps at, so help output is a function of its
    // content alone. Set before the caller's variables so a test can override.
    cmd.env("COLUMNS", "10000");

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

/// Run `compact' and check that its standard output holds `expected' as one of
/// its lines, for listings that grow with every release.
#[allow(dead_code)]
pub fn run_command_listing(args: &[&str], expected: &str) {
    assert_directory_is_isolated(args, None);

    let output = without_callers_directory("../../target/debug/compact")
        .env("COLUMNS", "10000")
        .env("RUST_BACKTRACE", "0")
        .args(args)
        .output()
        .expect("Failed to execute command");

    let stdout = String::from_utf8_lossy(&output.stdout);

    dbg!(args.join(" "));
    dbg!(&stdout);
    dbg!(String::from_utf8_lossy(&output.stderr));

    assert_eq!(output.status.code(), Some(0));
    assert!(
        stdout.lines().any(|line| line.trim_end() == expected),
        "no line of the output is `{expected}'"
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
