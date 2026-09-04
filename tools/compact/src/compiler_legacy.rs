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

use anyhow::{Context, Result, anyhow, bail};
use reqwest::Url;
use semver::Version;
use std::path::{Path, PathBuf};
use tokio::fs;

/// Marker attached to a failure caused by the archive itself -- unreadable, or
/// an entry that failed its checksum -- rather than by the machine unpacking
/// it. A caller discards such an archive and fetches it again; it must not do
/// that for a full disk or a permission error, which re-downloading cannot fix.
#[derive(Debug)]
pub struct CorruptArchive;

impl std::fmt::Display for CorruptArchive {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("the downloaded archive could not be read")
    }
}

impl std::error::Error for CorruptArchive {}

/// Whether `error` was caused by the archive rather than by the machine.
pub fn is_corrupt_archive(error: &anyhow::Error) -> bool {
    // `downcast_ref' searches the context chain; `chain()' yields anyhow's own
    // wrappers rather than the attached values, so it would never match.
    error.downcast_ref::<CorruptArchive>().is_some()
}

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

    pub async fn install(&self) -> Result<()> {
        install_archive(&self.path, &self.path_zip()).await
    }
}

/// Unpack `zip` into `dir`.
///
/// The toolchain used to be unpacked by running `unzip`, which is not installed
/// by default on many systems -- the machine in issue #739 had `tar`, `gzip`,
/// `xz` and `zstd` but not `unzip`, so the toolchain could not be installed at
/// all. Reading the archive here removes that dependency.
///
/// The release archive is produced by `zip --junk-paths` (see
/// `.github/workflows/release-build.yml`), so it is a flat set of regular
/// files. Entries are written by their file name alone, which also means a
/// hand-made archive cannot direct a write outside `dir`.
fn extract_archive(dir: &Path, zip: &Path) -> Result<()> {
    let file = std::fs::File::open(zip).with_context(|| anyhow!("Failed to open `{zip:?}'"))?;

    let mut archive = zip::ZipArchive::new(file)
        .map_err(anyhow::Error::new)
        .context(CorruptArchive)
        .with_context(|| anyhow!("Failed to read `{zip:?}' as a zip archive"))?;

    for index in 0..archive.len() {
        let mut entry = archive
            .by_index(index)
            .map_err(anyhow::Error::new)
            .context(CorruptArchive)
            .with_context(|| anyhow!("Failed to read entry {index} of `{zip:?}'"))?;

        if entry.is_dir() {
            continue;
        }

        let Some(name) = entry.enclosed_name() else {
            bail!("Refusing entry {index} of `{zip:?}': its name escapes the archive");
        };

        let Some(name) = name.file_name().map(|name| name.to_owned()) else {
            continue;
        };

        let target = dir.join(name);

        let mut output = std::fs::File::create(&target)
            .with_context(|| anyhow!("Failed to create `{target:?}'"))?;

        std::io::copy(&mut entry, &mut output)
            .map_err(|error| {
                // a bad checksum or a malformed compressed stream is the
                // archive's fault; a full disk is not
                let corrupt = error.kind() == std::io::ErrorKind::InvalidData;
                let error = anyhow::Error::new(error);

                if corrupt {
                    error.context(CorruptArchive)
                } else {
                    error
                }
            })
            .with_context(|| anyhow!("Failed to write `{target:?}'"))?;

        // `unzip` restores the mode recorded in the archive. Nothing else does
        // it for us, and a `compactc` without its executable bit is an
        // installation that looks complete and cannot run.
        //
        // The recorded mode is archive data, so it is masked before use. A
        // crafted entry could otherwise ask for group- or world-writable --
        // letting another local user rewrite a file before it is run -- or for
        // setuid or setgid. A symlink entry records 0o120777, which `from_mode'
        // would turn into a world-writable regular file. Masking keeps what the
        // release archives actually rely on, including the read-only 0o555 that
        // the nix store ships, and drops the rest.
        #[cfg(unix)]
        if let Some(mode) = entry.unix_mode() {
            use std::os::unix::fs::PermissionsExt;

            let mode = mode & 0o755;

            std::fs::set_permissions(&target, std::fs::Permissions::from_mode(mode))
                .with_context(|| anyhow!("Failed to set the mode of `{target:?}'"))?;
        }
    }

    Ok(())
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
async fn install_archive(dir: &Path, zip: &Path) -> Result<()> {
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

    // reading and inflating an archive is blocking work
    let unpack_into = staging.clone();
    let unpack = zip.to_path_buf();
    tokio::task::spawn_blocking(move || extract_archive(&unpack_into, &unpack))
        .await
        .context("The task unpacking the archive did not finish")??;

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
    use super::{extract_archive, install_archive, is_corrupt_archive};

    /// Compression method 0: the payload is stored verbatim.
    const STORED: u16 = 0;
    /// Compression method 12: bzip2, which this build deliberately does not
    /// enable. Useful for making one entry unreadable on purpose.
    const UNSUPPORTED: u16 = 12;

    struct Entry<'a> {
        name: &'a str,
        contents: &'a [u8],
        mode: u32,
        method: u16,
    }

    fn file<'a>(name: &'a str, contents: &'static [u8], mode: u32) -> Entry<'a> {
        Entry {
            name,
            contents,
            mode,
            method: STORED,
        }
    }

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

    /// Build a zip holding each entry, recording its unix mode and compression
    /// method so a test can ask for one that cannot be read.
    fn zip_of(entries: &[Entry]) -> Vec<u8> {
        let mut zip = Vec::new();
        let mut central = Vec::new();

        for entry in entries {
            let name = entry.name.as_bytes();
            let crc = crc32(entry.contents).to_le_bytes();
            let size = (entry.contents.len() as u32).to_le_bytes();
            let name_len = (name.len() as u16).to_le_bytes();
            let method = entry.method.to_le_bytes();
            let offset = (zip.len() as u32).to_le_bytes();

            zip.extend_from_slice(b"PK\x03\x04"); // local file header
            zip.extend_from_slice(&[20, 0]); // version needed
            zip.extend_from_slice(&[0, 0]); // flags
            zip.extend_from_slice(&method);
            zip.extend_from_slice(&[0, 0, 0, 0]); // mtime, mdate
            zip.extend_from_slice(&crc);
            zip.extend_from_slice(&size); // compressed size
            zip.extend_from_slice(&size); // uncompressed size
            zip.extend_from_slice(&name_len);
            zip.extend_from_slice(&[0, 0]); // extra length
            zip.extend_from_slice(name);
            zip.extend_from_slice(entry.contents);

            central.extend_from_slice(b"PK\x01\x02"); // central directory header
            central.extend_from_slice(&[20, 3]); // version made by: 3 = unix
            central.extend_from_slice(&[20, 0]); // version needed
            central.extend_from_slice(&[0, 0]); // flags
            central.extend_from_slice(&method);
            central.extend_from_slice(&[0, 0, 0, 0]); // mtime, mdate
            central.extend_from_slice(&crc);
            central.extend_from_slice(&size);
            central.extend_from_slice(&size);
            central.extend_from_slice(&name_len);
            central.extend_from_slice(&[0, 0]); // extra length
            central.extend_from_slice(&[0, 0]); // comment length
            central.extend_from_slice(&[0, 0]); // disk number
            central.extend_from_slice(&[0, 0]); // internal attributes
            central.extend_from_slice(&(entry.mode << 16).to_le_bytes()); // external attributes
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
    fn artifact_dir(entries: &[Entry]) -> tempfile::TempDir {
        let dir = tempfile::tempdir().expect("Failed to create a temporary directory");

        std::fs::write(dir.path().join("artifact.zip"), zip_of(entries))
            .expect("Failed to write artifact.zip");

        dir
    }

    fn zip_in(dir: &std::path::Path) -> std::path::PathBuf {
        dir.join("artifact.zip")
    }

    #[cfg(unix)]
    fn mode_of(path: &std::path::Path) -> u32 {
        use std::os::unix::fs::PermissionsExt;

        std::fs::metadata(path)
            .expect("Failed to stat the extracted file")
            .permissions()
            .mode()
            & 0o777
    }

    #[test]
    fn extracts_every_entry() {
        let dir = artifact_dir(&[
            file("compactc", b"compiler", 0o755),
            file("format-compact", b"formatter", 0o755),
            file("public_params.bin", b"params", 0o644),
        ]);

        extract_archive(dir.path(), &zip_in(dir.path())).expect("Extraction should succeed");

        assert_eq!(
            std::fs::read(dir.path().join("compactc")).expect("compactc"),
            b"compiler"
        );
        assert_eq!(
            std::fs::read(dir.path().join("format-compact")).expect("format-compact"),
            b"formatter"
        );
        assert_eq!(
            std::fs::read(dir.path().join("public_params.bin")).expect("public_params.bin"),
            b"params"
        );
    }

    /// `unzip` restored the mode from the archive and nothing does it for us
    /// now, so a compiler extracted without its executable bit would look
    /// installed and refuse to run.
    #[cfg(unix)]
    #[test]
    fn the_extracted_compiler_is_executable() {
        let dir = artifact_dir(&[file("compactc", b"compiler", 0o755)]);

        extract_archive(dir.path(), &zip_in(dir.path())).expect("Extraction should succeed");

        assert_eq!(mode_of(&dir.path().join("compactc")), 0o755);
    }

    /// ...and the mode is taken from the archive rather than applied to
    /// everything, so a data file does not come out executable.
    #[cfg(unix)]
    #[test]
    fn a_hostile_mode_in_the_archive_is_not_honoured() {
        // 0o4777 asks for setuid and writable-by-anyone; 0o2775 for setgid
        // and group-writable; 0o120777 is what a symlink entry records, and
        // `from_mode' would keep its 0o777.
        let dir = artifact_dir(&[
            file("compactc", b"compiler", 0o4777),
            file("shared.bin", b"data", 0o2775),
            file("link", b"../../../etc/passwd", 0o120777),
        ]);

        extract_archive(dir.path(), &zip_in(dir.path())).expect("Extraction should succeed");

        for name in ["compactc", "shared.bin", "link"] {
            let target = dir.path().join(name);

            assert_eq!(
                mode_of(&target),
                0o755,
                "`{name}' kept a mode the archive asked for"
            );

            // and the symlink entry is a regular file holding the target as its
            // bytes, not a link: nothing here can create one
            assert!(
                target
                    .symlink_metadata()
                    .expect("stat")
                    .file_type()
                    .is_file(),
                "`{name}' is not a regular file"
            );
        }
    }

    #[test]
    fn a_file_that_is_not_executable_in_the_archive_stays_that_way() {
        let dir = artifact_dir(&[file("public_params.bin", b"params", 0o644)]);

        extract_archive(dir.path(), &zip_in(dir.path())).expect("Extraction should succeed");

        assert_eq!(mode_of(&dir.path().join("public_params.bin")), 0o644);
    }

    /// The archive is unpacked read-only; a compiler stored read-only in the
    /// archive must still be replaceable by a later install.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_read_only_compiler_can_still_be_reinstalled() {
        let dir = artifact_dir(&[file("compactc", b"first", 0o555)]);

        install_archive(dir.path(), &zip_in(dir.path()))
            .await
            .expect("The first installation should succeed");
        assert_eq!(mode_of(&dir.path().join("compactc")), 0o555);

        std::fs::write(
            zip_in(dir.path()),
            zip_of(&[file("compactc", b"second", 0o555)]),
        )
        .expect("Failed to replace the archive");

        install_archive(dir.path(), &zip_in(dir.path()))
            .await
            .expect("Reinstalling over a read-only compiler should succeed");

        assert_eq!(
            std::fs::read(dir.path().join("compactc")).expect("compactc"),
            b"second"
        );
    }

    #[test]
    fn an_entry_that_cannot_be_decompressed_is_an_error() {
        let dir = artifact_dir(&[
            file("compactc", b"compiler", 0o755),
            Entry {
                name: "public_params.bin",
                contents: b"params",
                mode: 0o644,
                method: UNSUPPORTED,
            },
        ]);

        extract_archive(dir.path(), &zip_in(dir.path()))
            .expect_err("An entry that cannot be decompressed must fail");
    }

    /// Issue #739, one level down: callers treat the presence of `compactc' as
    /// proof that a version is installed, so an extraction that fails partway
    /// must not leave that file behind. Here the compiler is the first entry
    /// and the second cannot be read, so extraction fails after `compactc' has
    /// been written into the staging directory.
    #[tokio::test]
    async fn a_failed_installation_leaves_no_compiler_in_place() {
        let dir = artifact_dir(&[
            file("compactc", b"compiler", 0o755),
            Entry {
                name: "public_params.bin",
                contents: b"params",
                mode: 0o644,
                method: UNSUPPORTED,
            },
        ]);

        install_archive(dir.path(), &zip_in(dir.path()))
            .await
            .expect_err("A failed extraction must fail the installation");

        assert!(
            !dir.path().join("compactc").exists(),
            "a failed installation must not leave something that looks installed"
        );
    }

    #[tokio::test]
    async fn installs_every_entry_and_clears_the_staging_directory() {
        let dir = artifact_dir(&[
            file("compactc", b"compiler", 0o755),
            file("format-compact", b"formatter", 0o755),
        ]);

        install_archive(dir.path(), &zip_in(dir.path()))
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
        assert!(
            !dir.path().join(".incoming").exists(),
            "the staging directory should not survive a successful installation"
        );
        assert!(
            zip_in(dir.path()).is_file(),
            "the archive itself should not be moved into place"
        );
    }

    #[tokio::test]
    async fn leftovers_from_an_interrupted_attempt_are_discarded() {
        let dir = artifact_dir(&[file("compactc", b"compiler", 0o755)]);

        let staging = dir.path().join(".incoming");
        std::fs::create_dir_all(&staging).expect("staging");
        std::fs::write(staging.join("compactc"), b"stale").expect("stale compiler");
        std::fs::write(staging.join("junk"), b"junk").expect("junk");

        install_archive(dir.path(), &zip_in(dir.path()))
            .await
            .expect("Installation should succeed");

        assert_eq!(
            std::fs::read(dir.path().join("compactc")).expect("compactc"),
            b"compiler"
        );
        assert!(
            !dir.path().join("junk").exists(),
            "leftovers from the interrupted attempt should not be installed"
        );
    }

    /// A broken installation can leave a directory where a file belongs;
    /// `rename` will not replace a directory that has anything in it.
    #[tokio::test]
    async fn installing_replaces_a_directory_left_where_a_file_belongs() {
        let dir = artifact_dir(&[file("compactc", b"compiler", 0o755)]);

        let wrong = dir.path().join("compactc");
        std::fs::create_dir_all(&wrong).expect("directory");
        std::fs::write(wrong.join("junk"), b"junk").expect("junk");

        install_archive(dir.path(), &zip_in(dir.path()))
            .await
            .expect("Installation should succeed");

        assert_eq!(
            std::fs::read(dir.path().join("compactc")).expect("compactc"),
            b"compiler"
        );
    }

    /// The release archive is flat, but nothing about a downloaded file
    /// guarantees that. An entry naming a path outside the directory must not
    /// be followed.
    #[test]
    fn an_entry_whose_name_escapes_the_archive_is_refused() {
        let dir = artifact_dir(&[file("../escaped", b"nope", 0o644)]);

        extract_archive(dir.path(), &zip_in(dir.path()))
            .expect_err("An entry naming a path outside the archive must be refused");

        assert!(
            !dir.path().parent().unwrap().join("escaped").exists(),
            "nothing may be written outside the destination directory"
        );
    }

    /// Every other test here stores its entries uncompressed, but the release
    /// archive is built by `zip --junk-paths`, which deflates. If the crate's
    /// deflate feature were ever dropped from Cargo.toml the stored-entry tests
    /// would all still pass and every real installation would fail, so this one
    /// carries a genuinely deflated archive: 536 bytes compressed to 69.
    #[cfg(unix)]
    #[test]
    fn extracts_a_deflated_archive() {
        const DEFLATED: &[u8] = &[
            0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x21, 0x00,
            0x9c, 0x7d, 0xd0, 0xdf, 0x45, 0x00, 0x00, 0x00, 0x18, 0x02, 0x00, 0x00, 0x08, 0x00,
            0x00, 0x00, 0x63, 0x6f, 0x6d, 0x70, 0x61, 0x63, 0x74, 0x63, 0xed, 0x8c, 0xc1, 0x0d,
            0x80, 0x30, 0x0c, 0x03, 0x57, 0xf1, 0x00, 0x88, 0x9d, 0x42, 0x6a, 0x68, 0x25, 0x9a,
            0x54, 0x6d, 0x3e, 0x6c, 0x4f, 0xe6, 0x40, 0xfc, 0xce, 0x3a, 0xf9, 0xd4, 0xfb, 0x10,
            0x0d, 0xc5, 0xd1, 0x4c, 0xe6, 0x03, 0x75, 0x0b, 0x5a, 0xac, 0x0d, 0x93, 0x83, 0x12,
            0x2c, 0x58, 0x8e, 0xc2, 0xf3, 0x4e, 0x46, 0x95, 0x95, 0xb3, 0x33, 0x6a, 0xb3, 0x0b,
            0x91, 0xc2, 0xf7, 0xbc, 0xfc, 0x89, 0xcf, 0x25, 0x5e, 0x50, 0x4b, 0x01, 0x02, 0x14,
            0x03, 0x14, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x21, 0x00, 0x9c, 0x7d, 0xd0,
            0xdf, 0x45, 0x00, 0x00, 0x00, 0x18, 0x02, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xed, 0x01, 0x00, 0x00, 0x00, 0x00, 0x63,
            0x6f, 0x6d, 0x70, 0x61, 0x63, 0x74, 0x63, 0x50, 0x4b, 0x05, 0x06, 0x00, 0x00, 0x00,
            0x00, 0x01, 0x00, 0x01, 0x00, 0x36, 0x00, 0x00, 0x00, 0x6b, 0x00, 0x00, 0x00, 0x00,
            0x00,
        ];

        let dir = tempfile::tempdir().expect("temporary directory");
        std::fs::write(zip_in(dir.path()), DEFLATED).expect("Failed to write the archive");

        extract_archive(dir.path(), &zip_in(dir.path()))
            .expect("A deflated archive should extract");

        assert_eq!(
            std::fs::read(dir.path().join("compactc")).expect("compactc"),
            "compactc binary contents, repeated so deflate has something to do. "
                .repeat(8)
                .as_bytes()
        );
        assert_eq!(mode_of(&dir.path().join("compactc")), 0o755);
    }

    /// A wrong checksum means the bytes on disk are not the archive that was
    /// published, so fetching it again is the way out. The caller keys its
    /// retry off this, hence a test for the classification and not only for the
    /// failure.
    #[test]
    fn a_failed_checksum_is_the_archives_fault() {
        let dir = artifact_dir(&[file("compactc", b"compiler", 0o755)]);
        let path = zip_in(dir.path());

        let mut bytes = std::fs::read(&path).expect("archive");
        let at = bytes
            .windows(8)
            .position(|window| window == b"compiler")
            .expect("payload");
        bytes[at] = b'X';
        std::fs::write(&path, &bytes).expect("Failed to corrupt the archive");

        let error = extract_archive(dir.path(), &path).expect_err("A bad checksum must fail");

        assert!(
            is_corrupt_archive(&error),
            "a bad checksum should be blamed on the archive: {error:#}"
        );
    }

    #[test]
    fn a_file_that_is_not_an_archive_is_the_archives_fault() {
        let dir = tempfile::tempdir().expect("temporary directory");
        std::fs::write(zip_in(dir.path()), b"this is not a zip file").expect("write");

        let error =
            extract_archive(dir.path(), &zip_in(dir.path())).expect_err("Not an archive must fail");

        assert!(
            is_corrupt_archive(&error),
            "an unreadable file should be blamed on the archive: {error:#}"
        );
    }

    /// The counterpart: a failure to write is the machine's problem, and
    /// fetching the archive again would only waste the download.
    #[test]
    fn a_failure_to_write_is_not_the_archives_fault() {
        let dir = artifact_dir(&[file("compactc", b"compiler", 0o755)]);

        let error = extract_archive(
            std::path::Path::new("/compact-test/no/such/directory"),
            &zip_in(dir.path()),
        )
        .expect_err("Writing into a directory that does not exist must fail");

        assert!(
            !is_corrupt_archive(&error),
            "a write failure should not be blamed on the archive: {error:#}"
        );
    }

    #[test]
    fn a_file_that_is_not_an_archive_is_rejected() {
        let dir = tempfile::tempdir().expect("temporary directory");
        std::fs::write(zip_in(dir.path()), b"this is not a zip file").expect("write");

        let error = extract_archive(dir.path(), &zip_in(dir.path()))
            .expect_err("A file that is not an archive must be rejected");

        assert!(
            format!("{error:#}").contains("zip archive"),
            "the error should say the file is not a zip archive: {error:#}"
        );
    }
}
