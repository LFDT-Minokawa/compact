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

use anyhow::{Context, Result, anyhow};
use reqwest::Url;
use semver::Version;
use std::{
    io::ErrorKind,
    path::{Path, PathBuf},
    process::Stdio,
};
use tokio::process::Command;

/// External command used to unpack a downloaded toolchain archive.
pub const EXTRACTION_COMMAND: &str = "unzip";

pub struct CompilerAsset {
    pub path: PathBuf,
    pub asset: octocrab::models::repos::Asset,
    pub version: Version,
}

impl CompilerAsset {
    fn path_zip(&self) -> PathBuf {
        self.path.join("artifact.zip")
    }
    fn path_compactc(&self) -> PathBuf {
        self.path.join("compactc")
    }

    pub fn exist(&self) -> bool {
        self.path_compactc().is_file()
    }

    pub fn download_url(&self) -> &Url {
        &self.asset.browser_download_url
    }

    pub async fn unzip(&self) -> Result<()> {
        extract_archive(EXTRACTION_COMMAND, &self.path, &self.path_zip()).await
    }
}

/// Unpack `zip` into `dir` using an external extraction command.
///
/// `command` is a parameter rather than a constant so that the error path can
/// be tested without touching the process environment.
async fn extract_archive(command: &str, dir: &Path, zip: &Path) -> Result<()> {
    let mut cmd = Command::new(command);

    // execute the extraction command in the artifact directory
    cmd.current_dir(dir);

    // `-o' overwrites without asking. Standard input is closed below, so an
    // overwrite prompt left behind by a partially extracted archive would fail
    // the retry instead of repairing it.
    cmd.arg("-o");
    cmd.arg(zip);

    // capture the StdOut and StdErr
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    // don't allow StdIn, we don't have anything to pass in the standard input
    // and we don't want it to be inherited
    cmd.stdin(Stdio::null());

    let child = cmd.spawn().map_err(|error| {
        // A bare `Failed to spawn artifact extraction command' plus the OS
        // error names neither the missing command nor a way to fix it.
        if error.kind() == ErrorKind::NotFound {
            anyhow!(
                "Failed to unpack the toolchain: `{command}' was not found. The \
                 Compact toolchain is distributed as a zip archive, so `{command}' \
                 must be installed and on your PATH; install it and run the same \
                 command again."
            )
        } else {
            anyhow::Error::new(error).context(format!(
                "Failed to spawn the extraction command `{command}'"
            ))
        }
    })?;

    let output = child
        .wait_with_output()
        .await
        .context("Failed to execute the artifact extraction command")?;

    let status = output.status;

    if status.success() {
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);

        Err(anyhow!("Stderr: {stderr}"))
            .with_context(|| anyhow!("Status: {status}"))
            .with_context(|| anyhow!("Command={command} CWD={dir:?}"))
            .context("artifact Extraction failed")
    }
}

#[cfg(test)]
mod tests {
    use super::{EXTRACTION_COMMAND, extract_archive};

    /// CRC-32 (IEEE), computed here so the test needs no extra dependency.
    fn crc32(data: &[u8]) -> u32 {
        let mut crc = 0xFFFF_FFFFu32;

        for byte in data {
            crc ^= u32::from(*byte);

            for _ in 0..8 {
                crc = if crc & 1 == 1 {
                    (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >> 1
                };
            }
        }

        !crc
    }

    /// A single-entry zip holding `contents` uncompressed under `name`.
    fn stored_zip(name: &str, contents: &[u8]) -> Vec<u8> {
        let name = name.as_bytes();
        let crc = crc32(contents).to_le_bytes();
        let size = (contents.len() as u32).to_le_bytes();
        let name_len = (name.len() as u16).to_le_bytes();

        let mut zip = Vec::new();
        zip.extend_from_slice(b"PK\x03\x04"); // local file header
        zip.extend_from_slice(&[20, 0]); // version needed
        zip.extend_from_slice(&[0, 0]); // flags
        zip.extend_from_slice(&[0, 0]); // method 0: stored
        zip.extend_from_slice(&[0, 0, 0, 0]); // mtime, mdate
        zip.extend_from_slice(&crc);
        zip.extend_from_slice(&size); // compressed size
        zip.extend_from_slice(&size); // uncompressed size
        zip.extend_from_slice(&name_len);
        zip.extend_from_slice(&[0, 0]); // extra length
        zip.extend_from_slice(name);
        zip.extend_from_slice(contents);

        let central_offset = (zip.len() as u32).to_le_bytes();

        let mut central = Vec::new();
        central.extend_from_slice(b"PK\x01\x02"); // central directory header
        central.extend_from_slice(&[20, 0]); // version made by
        central.extend_from_slice(&[20, 0]); // version needed
        central.extend_from_slice(&[0, 0]); // flags
        central.extend_from_slice(&[0, 0]); // method
        central.extend_from_slice(&[0, 0, 0, 0]); // mtime, mdate
        central.extend_from_slice(&crc);
        central.extend_from_slice(&size);
        central.extend_from_slice(&size);
        central.extend_from_slice(&name_len);
        central.extend_from_slice(&[0, 0]); // extra length
        central.extend_from_slice(&[0, 0]); // comment length
        central.extend_from_slice(&[0, 0]); // disk number
        central.extend_from_slice(&[0, 0]); // internal attributes
        central.extend_from_slice(&[0, 0, 0, 0]); // external attributes
        central.extend_from_slice(&0u32.to_le_bytes()); // local header offset
        central.extend_from_slice(name);

        let central_len = (central.len() as u32).to_le_bytes();

        zip.extend_from_slice(&central);
        zip.extend_from_slice(b"PK\x05\x06"); // end of central directory
        zip.extend_from_slice(&[0, 0]); // this disk
        zip.extend_from_slice(&[0, 0]); // disk holding the central directory
        zip.extend_from_slice(&[1, 0]); // entries on this disk
        zip.extend_from_slice(&[1, 0]); // entries in total
        zip.extend_from_slice(&central_len);
        zip.extend_from_slice(&central_offset);
        zip.extend_from_slice(&[0, 0]); // comment length

        zip
    }

    /// An artifact directory holding nothing but `artifact.zip` -- the state a
    /// failed extraction leaves behind.
    fn artifact_dir(contents: &[u8]) -> tempfile::TempDir {
        let dir = tempfile::tempdir().expect("Failed to create a temporary directory");

        std::fs::write(
            dir.path().join("artifact.zip"),
            stored_zip("compactc", contents),
        )
        .expect("Failed to write artifact.zip");

        dir
    }

    #[tokio::test]
    async fn extracts_the_compiler_from_the_archive() {
        let dir = artifact_dir(b"binary");

        extract_archive(
            EXTRACTION_COMMAND,
            dir.path(),
            &dir.path().join("artifact.zip"),
        )
        .await
        .expect("Extraction should succeed");

        assert_eq!(
            std::fs::read(dir.path().join("compactc")).expect("Failed to read compactc"),
            b"binary"
        );
    }

    /// Issue #739: a retry runs over whatever the failed attempt left behind, so
    /// extraction has to overwrite rather than stop at an overwrite prompt --
    /// standard input is closed, so a prompt fails the retry.
    #[tokio::test]
    async fn re_extraction_overwrites_a_partial_result() {
        let dir = artifact_dir(b"binary");

        // a truncated leftover from an interrupted extraction
        std::fs::write(dir.path().join("compactc"), b"trunc")
            .expect("Failed to write the partial file");

        extract_archive(
            EXTRACTION_COMMAND,
            dir.path(),
            &dir.path().join("artifact.zip"),
        )
        .await
        .expect("Re-extraction should overwrite rather than prompt");

        assert_eq!(
            std::fs::read(dir.path().join("compactc")).expect("Failed to read compactc"),
            b"binary"
        );
    }

    /// Issue #739: an absent extraction command reported only as
    /// `No such file or directory (os error 2)' tells the user nothing. The
    /// error has to name the command and say what to do about it.
    #[tokio::test]
    async fn a_missing_extraction_command_is_named() {
        let dir = artifact_dir(b"binary");
        let missing = "compact-test-no-such-extraction-command";

        let error = extract_archive(missing, dir.path(), &dir.path().join("artifact.zip"))
            .await
            .expect_err("A missing extraction command must fail");

        let message = format!("{error:#}");

        assert!(
            message.contains(missing),
            "the error should name the missing command: {message}"
        );
        assert!(
            message.contains("PATH"),
            "the error should say where the command is looked for: {message}"
        );
    }
}
