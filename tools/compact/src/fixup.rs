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

use anyhow::{Context as _, Result};
use std::path::{Path, PathBuf};
use std::process::Stdio;

use crate::formatter::diff_file;

#[derive(Debug)]
pub enum FixupStatus {
    Error,
    Success,
    Unchanged,
    Diff(String),
}

pub async fn fixup_file(
    bin: &Path,
    check: bool,
    source: PathBuf,
    update_uint_ranges: bool,
    vscode: bool,
) -> Result<(PathBuf, &'static str, FixupStatus)> {
    let original_content = tokio::fs::read_to_string(&source)
        .await
        .context("reading source file")?;

    let mut command = tokio::process::Command::new(bin);

    if update_uint_ranges {
        command.arg("--update-Uint-ranges");
    }
    if vscode {
        command.arg("--vscode");
    }

    let args = if check {
        vec![&source]
    } else {
        vec![&source, &source]
    };
    command.args(args);

    let output = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .await
        .context("Failed to spawn fixup-compact command")?;

    if !output.stderr.is_empty() {
        eprint!("{}", String::from_utf8_lossy(&output.stderr));
    }

    if !output.status.success() {
        return Ok((source, "failed", FixupStatus::Error));
    }

    let fixed_output = if check {
        String::from_utf8(output.stdout).context("reading fixup output")?
    } else {
        tokio::fs::read_to_string(&source)
            .await
            .context("reading file after fixup")?
    };

    if fixed_output != original_content {
        if check {
            let comparison = diff_file(&original_content, &fixed_output);
            Ok((source, "", FixupStatus::Diff(comparison)))
        } else {
            Ok((source, "fixed", FixupStatus::Success))
        }
    } else {
        Ok((source, "unchanged", FixupStatus::Unchanged))
    }
}

pub use crate::formatter::compact_files_excluding_gitignore;
