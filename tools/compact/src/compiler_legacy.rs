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
use tokio::{fs, process::Command};

/// External command used to unpack a downloaded toolchain archive.
pub const EXTRACTION_COMMAND: &str = "unzip";

/// The compiler binary, whose presence callers take as proof that a version is
/// completely installed.
const COMPILER_BIN: &str = "compactc";

/// Where an archive is unpacked before being moved into place.
const STAGING_DIR: &str = ".incoming";

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
        install_archive(EXTRACTION_COMMAND, &self.path, &self.path_zip()).await
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

/// Unpack `zip` into `dir` so that a partial result can never be mistaken for a
/// complete installation.
///
/// The archive is unpacked into a staging directory and the result moved into
/// place with the compiler binary last. Callers test for `compactc` to decide
/// whether a version is installed, so unpacking directly into `dir` means an
/// interrupted extraction that got as far as writing that one file leaves
/// something that looks installed and is not -- the same mistake, one level
/// down, as trusting the version directory to exist.
async fn install_archive(command: &str, dir: &Path, zip: &Path) -> Result<()> {
    let staging = dir.join(STAGING_DIR);

    // An earlier attempt may have been interrupted part-way through unpacking.
    // Start from nothing rather than unpacking over its leftovers.
    if fs::metadata(&staging).await.is_ok() {
        fs::remove_dir_all(&staging)
            .await
            .with_context(|| anyhow!("Failed to clear `{staging:?}'"))?;
    }

    fs::create_dir_all(&staging)
        .await
        .with_context(|| anyhow!("Failed to create `{staging:?}'"))?;

    extract_archive(command, &staging, zip).await?;

    let mut compiler = None;
    let mut rest = Vec::new();

    let mut entries = fs::read_dir(&staging)
        .await
        .with_context(|| anyhow!("Failed to read `{staging:?}'"))?;

    while let Some(entry) = entries
        .next_entry()
        .await
        .with_context(|| anyhow!("Failed to read `{staging:?}'"))?
    {
        if entry.file_name() == COMPILER_BIN {
            compiler = Some(entry.path());
        } else {
            rest.push(entry.path());
        }
    }

    for path in rest {
        move_into(dir, &path).await?;
    }

    // last, so that nothing is outstanding once it exists
    if let Some(path) = compiler {
        move_into(dir, &path).await?;
    }

    fs::remove_dir_all(&staging)
        .await
        .with_context(|| anyhow!("Failed to remove `{staging:?}'"))?;

    Ok(())
}

/// Move `path` into `dir`, replacing whatever is there.
///
/// `rename` is atomic within a filesystem and the staging directory is a child
/// of `dir`, so an onlooker sees either the previous entry or the complete new
/// one, never a half-written file.
async fn move_into(dir: &Path, path: &Path) -> Result<()> {
    let name = path
        .file_name()
        .ok_or_else(|| anyhow!("Unpacked entry has no file name: `{path:?}'"))?;
    let target = dir.join(name);

    // `rename` will not replace a directory that has anything in it.
    match fs::metadata(&target).await {
        Ok(metadata) if metadata.is_dir() => fs::remove_dir_all(&target)
            .await
            .with_context(|| anyhow!("Failed to replace `{target:?}'"))?,
        Ok(_) => fs::remove_file(&target)
            .await
            .with_context(|| anyhow!("Failed to replace `{target:?}'"))?,
        Err(_) => (),
    }

    fs::rename(path, &target)
        .await
        .with_context(|| anyhow!("Failed to move `{path:?}' to `{target:?}'"))
}

#[cfg(test)]
mod tests {
    use super::{EXTRACTION_COMMAND, extract_archive, install_archive};
    use std::path::Path;

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

    /// A zip holding each entry uncompressed. Names may contain `/`, which the
    /// extraction command turns into directories.
    fn stored_zip(entries: &[(&str, &[u8])]) -> Vec<u8> {
        let mut zip = Vec::new();
        let mut central = Vec::new();

        for (name, contents) in entries {
            let name = name.as_bytes();
            let crc = crc32(contents).to_le_bytes();
            let size = (contents.len() as u32).to_le_bytes();
            let name_len = (name.len() as u16).to_le_bytes();
            let offset = (zip.len() as u32).to_le_bytes();

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
            central.extend_from_slice(&offset);
            central.extend_from_slice(name);
        }

        let central_offset = (zip.len() as u32).to_le_bytes();
        let central_len = (central.len() as u32).to_le_bytes();
        let count = (entries.len() as u16).to_le_bytes();

        zip.extend_from_slice(&central);
        zip.extend_from_slice(b"PK\x05\x06"); // end of central directory
        zip.extend_from_slice(&[0, 0]); // this disk
        zip.extend_from_slice(&[0, 0]); // disk holding the central directory
        zip.extend_from_slice(&count); // entries on this disk
        zip.extend_from_slice(&count); // entries in total
        zip.extend_from_slice(&central_len);
        zip.extend_from_slice(&central_offset);
        zip.extend_from_slice(&[0, 0]); // comment length

        zip
    }

    /// An artifact directory holding nothing but `artifact.zip` -- the state a
    /// failed extraction leaves behind.
    fn artifact_dir(entries: &[(&str, &[u8])]) -> tempfile::TempDir {
        let dir = tempfile::tempdir().expect("Failed to create a temporary directory");

        std::fs::write(dir.path().join("artifact.zip"), stored_zip(entries))
            .expect("Failed to write artifact.zip");

        dir
    }

    fn zip_in(dir: &Path) -> std::path::PathBuf {
        dir.join("artifact.zip")
    }

    const COMPILER: &[(&str, &[u8])] = &[("compactc", b"binary")];

    #[tokio::test]
    async fn extracts_the_compiler_from_the_archive() {
        let dir = artifact_dir(COMPILER);

        extract_archive(EXTRACTION_COMMAND, dir.path(), &zip_in(dir.path()))
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
        let dir = artifact_dir(COMPILER);

        // a truncated leftover from an interrupted extraction
        std::fs::write(dir.path().join("compactc"), b"trunc")
            .expect("Failed to write the partial file");

        extract_archive(EXTRACTION_COMMAND, dir.path(), &zip_in(dir.path()))
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
        let dir = artifact_dir(COMPILER);
        let missing = "compact-test-no-such-extraction-command";

        let error = extract_archive(missing, dir.path(), &zip_in(dir.path()))
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

    #[tokio::test]
    async fn installs_every_entry_and_clears_the_staging_directory() {
        let entries: &[(&str, &[u8])] = &[
            ("compactc", b"compiler"),
            ("format-compact", b"formatter"),
            ("lib/helper", b"library"),
        ];
        let dir = artifact_dir(entries);

        install_archive(EXTRACTION_COMMAND, dir.path(), &zip_in(dir.path()))
            .await
            .expect("Installation should succeed");

        assert_eq!(
            std::fs::read(dir.path().join("compactc")).expect("compactc"),
            b"compiler"
        );
        assert_eq!(
            std::fs::read(dir.path().join("format-compact")).expect("format-compact"),
            b"formatter"
        );
        assert_eq!(
            std::fs::read(dir.path().join("lib").join("helper")).expect("lib/helper"),
            b"library"
        );
        assert!(
            !dir.path().join(".incoming").exists(),
            "the staging directory should not survive a successful installation"
        );
    }

    /// Issue #739, one level down: callers treat the presence of `compactc' as
    /// proof that a version is installed, so an extraction that fails partway
    /// must not leave that file behind. Unpacking straight into the version
    /// directory did exactly that whenever the failure came after the compiler
    /// binary had been written -- a full disk, a killed process, a corrupt
    /// archive -- and the next run then reported "already installed" over a
    /// broken installation.
    #[cfg(unix)]
    #[tokio::test]
    async fn an_extraction_that_fails_after_writing_the_compiler_installs_nothing() {
        use std::os::unix::fs::PermissionsExt;

        let dir = artifact_dir(COMPILER);

        // stands in for an extraction that reaches the compiler binary and then
        // dies; it runs in the directory it is told to unpack into
        let script = dir.path().join("half-extract");
        std::fs::write(&script, "#!/bin/sh\nprintf partial > compactc\nexit 1\n")
            .expect("Failed to write the stub");
        std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755))
            .expect("Failed to make the stub executable");

        install_archive(
            script.to_str().expect("stub path"),
            dir.path(),
            &zip_in(dir.path()),
        )
        .await
        .expect_err("A failed extraction must fail the installation");

        assert!(
            !dir.path().join("compactc").exists(),
            "a failed installation must not leave something that looks installed"
        );
    }

    #[tokio::test]
    async fn leftovers_from_an_interrupted_attempt_are_discarded() {
        let dir = artifact_dir(COMPILER);

        let staging = dir.path().join(".incoming");
        std::fs::create_dir_all(&staging).expect("staging");
        std::fs::write(staging.join("compactc"), b"stale").expect("stale compiler");
        std::fs::write(staging.join("junk"), b"junk").expect("junk");

        install_archive(EXTRACTION_COMMAND, dir.path(), &zip_in(dir.path()))
            .await
            .expect("Installation should succeed");

        assert_eq!(
            std::fs::read(dir.path().join("compactc")).expect("compactc"),
            b"binary"
        );
        assert!(
            !dir.path().join("junk").exists(),
            "leftovers from the interrupted attempt should not be installed"
        );
    }

    #[tokio::test]
    async fn installing_replaces_a_directory_that_is_already_there() {
        let entries: &[(&str, &[u8])] = &[("compactc", b"binary"), ("lib/helper", b"new")];
        let dir = artifact_dir(entries);

        let lib = dir.path().join("lib");
        std::fs::create_dir_all(&lib).expect("lib");
        std::fs::write(lib.join("stale"), b"stale").expect("stale");

        install_archive(EXTRACTION_COMMAND, dir.path(), &zip_in(dir.path()))
            .await
            .expect("Installation should succeed");

        assert_eq!(
            std::fs::read(lib.join("helper")).expect("lib/helper"),
            b"new"
        );
        assert!(
            !lib.join("stale").exists(),
            "a replaced directory should not keep its old contents"
        );
    }
}
