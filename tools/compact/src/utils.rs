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

use std::{
    io::ErrorKind,
    path::{Path, PathBuf},
};

use crate::{CommandLineArguments, Target, compiler::Compiler};
use anyhow::{Context, Result, anyhow, ensure};
use semver::Version;
use tokio::fs;

pub async fn read_parent_name_from_link(path: &PathBuf) -> Option<(PathBuf, String)> {
    fs::read_link(&path).await.ok().and_then(|link| {
        link.parent().and_then(|parent| {
            parent.file_name().and_then(|l| l.to_str()).and_then(|l| {
                if l.contains('v') {
                    Some((link.clone(), l.to_string()))
                } else {
                    parent.parent().and_then(|parent| {
                        parent
                            .file_name()
                            .and_then(|l| l.to_str())
                            .map(|l| (link.clone(), l.to_string()))
                    })
                }
            })
        })
    })
}

pub async fn remove_file_if_exists(path: &PathBuf) -> Result<()> {
    if path.try_exists().context("Checking if path exists")? {
        tokio::fs::remove_file(path)
            .await
            .context("Removing file")?;
    }

    Ok(())
}

async fn initialise_directory(path: impl AsRef<Path>) -> Result<()> {
    let path = path.as_ref();

    if !path.is_dir() {
        fs::create_dir_all(&path)
            .await
            .with_context(|| anyhow!("Failed to create compact directory: {path:?}",))?
    }

    Ok(())
}

pub async fn initialise_directories(cfg: &CommandLineArguments) -> Result<()> {
    let bin_dir = cfg.directory.bin_dir();
    let versions_dir = cfg.directory.versions_dir();

    initialise_directory(bin_dir).await?;
    initialise_directory(versions_dir).await?;

    Ok(())
}

#[cfg(unix)]
pub async fn set_current_compiler(
    cfg: &CommandLineArguments,
    compiler: &Compiler,
) -> Result<Compiler> {
    // set compactc
    let source = compiler.path_compactc().to_path_buf();
    let target = cfg.directory.bin_dir().join("compactc");

    if target.is_symlink() {
        fs::remove_file(&target)
            .await
            .with_context(|| anyhow!("Failed to remove previous symlink {target:?}"))?;
    }

    fs::symlink(&source, &target).await.with_context(|| {
        anyhow!(
            "Failed to create symlink from {target:?} {arrow} {source:?}",
            arrow = console::Emoji::new("→", "to")
        )
    })?;

    // set format-compact
    let source = compiler.path_format_compact();
    let target = cfg.directory.bin_dir().join("format-compact");

    if target.is_symlink() {
        fs::remove_file(&target)
            .await
            .with_context(|| anyhow!("Failed to remove previous symlink {target:?}"))?;
    }

    if source.exists() {
        fs::symlink(&source, &target).await.with_context(|| {
            anyhow!(
                "Failed to create symlink from {target:?} {arrow} {source:?}",
                arrow = console::Emoji::new("→", "to")
            )
        })?;
    }

    // set fixup-compact
    let source = compiler.path_fixup_compact();
    let target = cfg.directory.bin_dir().join("fixup-compact");

    if target.is_symlink() {
        fs::remove_file(&target)
            .await
            .with_context(|| anyhow!("Failed to remove previous symlink {target:?}"))?;
    }

    if source.exists() {
        fs::symlink(&source, &target).await.with_context(|| {
            anyhow!(
                "Failed to create symlink from {target:?} {arrow} {source:?}",
                arrow = console::Emoji::new("→", "to")
            )
        })?;
    }

    let new = get_current_compiler(cfg)
        .await?
        .ok_or_else(|| anyhow!("Failed to validate installed default compiler"))?;

    ensure!(
        new.version() == compiler.version(),
        "Installation failed, the default compiler is still set to older version {}",
        new.version()
    );

    Ok(new)
}

pub async fn get_current_compiler(cfg: &CommandLineArguments) -> Result<Option<Compiler>> {
    let bin = cfg.directory.bin_dir().join("compactc");

    let file = match fs::read_link(&bin).await {
        Ok(file) => {
            ensure!(file.is_file(), "Expecting a file: `{file:?}'");
            file
        }
        Err(error) if error.kind() == ErrorKind::NotFound => {
            return Ok(None);
        }
        reason => reason.with_context(|| anyhow!("Failed to read symbolic link: `{bin:?}'"))?,
    };

    // we expect the path to have a precise construction
    // <compact_directory> / versions / <version> / <target> / compactc

    let parent = file
        .parent()
        .ok_or_else(|| anyhow!("Couldn't read target parent directory ({file:?})"))?
        .to_path_buf();
    let target: Target = parent
        .file_name()
        .ok_or_else(|| anyhow!("Couldn't extract the target parent directory ({parent:?})"))?
        .to_string_lossy()
        .parse()
        .with_context(|| anyhow!("Couldn't parse the target parent directory ({parent:?})"))?;

    let parent = parent
        .parent()
        .ok_or_else(|| anyhow!("Couldn't read version parent directory ({parent:?})"))?
        .to_path_buf();
    let version: Version = parent
        .file_name()
        .ok_or_else(|| anyhow!("Couldn't extract the version parent directory ({parent:?})"))?
        .to_string_lossy()
        .parse()
        .with_context(|| anyhow!("Couldn't parse the version parent directory ({parent:?})"))?;

    Compiler::open(cfg, version, target).await.map(Some)
}
