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

#[derive(Debug)]
pub enum FixupStatus {
    Error,
    Success,
    Unchanged,
    Output(String),
}

pub async fn fixup_file(
    bin: &Path,
    source: PathBuf,
    update_uint_ranges: bool,
    vscode: bool,
    in_place: bool,
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

    if in_place {
        command.arg(&source);
        command.arg(&source);
    } else {
        command.arg(&source);
    }

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

    if in_place {
        let new_content = tokio::fs::read_to_string(&source)
            .await
            .context("reading file after fixup")?;

        if new_content != original_content {
            Ok((source, "fixed", FixupStatus::Success))
        } else {
            Ok((source, "unchanged", FixupStatus::Unchanged))
        }
    } else {
        let output_str = String::from_utf8_lossy(&output.stdout).to_string();
        Ok((source, "", FixupStatus::Output(output_str)))
    }
}

pub use crate::formatter::compact_files_excluding_gitignore;
